import AppKit
import Combine
import CoreML
import CoreVideo
import Foundation
import Vision

/// Vision-normalised bounding box has a BOTTOM-LEFT origin. DJI ActiveTrack
/// uses TOP-LEFT; convert when sending a rectangle to the iPhone.
struct VisionCandidate: Identifiable, @unchecked Sendable {
    var id: UUID = UUID()
    var kind: String
    var confidence: Float
    var bounds: CGRect
}

struct VisionTrackingOutput: @unchecked Sendable {
    var people: [VisionCandidate]
    var vehicles: [VisionCandidate]
    var targetBounds: CGRect?
    var targetConfidence: Float
    var lost: Bool
}

/// Mac-side person detection and selectable visual object tracking.
/// No steering commands are emitted by this class.
///
/// Person detection works with Apple's built-in VNDetectHumanRectanglesRequest.
/// Vehicle *classification* requires an optional Core ML detector model;
/// manually drawing around a vehicle can track it without that model.
@MainActor
final class VisionTrackingEngine: ObservableObject {
    @Published var enabled = false {
        didSet {
            if !enabled { candidates.removeAll() }
        }
    }
    @Published private(set) var candidates: [VisionCandidate] = []
    @Published private(set) var selectedBounds: CGRect?
    @Published private(set) var selectedLabel = ""
    @Published private(set) var selectedConfidence: Float = 0
    @Published private(set) var selectedLost = false
    @Published private(set) var vehicleModelInstalled = false
    @Published private(set) var status = "Analysis off"
    @Published private(set) var lastAnalysedAt: Date?
    @Published private(set) var videoDimensions = CGSize(width: 16, height: 9)

    private let workQueue = DispatchQueue(label: "org.groundstation.vision", qos: .userInitiated)
    private let worker = VisionAnalysisWorker()
    private var isProcessing = false
    private var lastSubmittedAt = Date.distantPast
    private var lastDetectedAt = Date.distantPast
    private let minFrameInterval: TimeInterval = 0.18

    init() {
        // Capture the serial-queue-confined worker while on MainActor.
        // Never access actor-isolated properties from DispatchQueue callbacks.
        let worker = self.worker
        workQueue.async { [weak self] in
            let loaded = worker.loadVehicleModelIfPresent()
            Task { @MainActor [weak self] in
                self?.vehicleModelInstalled = loaded
            }
        }
    }

    func receive(_ image: CVPixelBuffer) {
        guard enabled || selectedBounds != nil else { return }
        guard !isProcessing, Date().timeIntervalSince(lastSubmittedAt) >= minFrameInterval else { return }
        isProcessing = true
        lastSubmittedAt = Date()
        let detect = enabled && Date().timeIntervalSince(lastDetectedAt) >= 0.65
        if detect { lastDetectedAt = Date() }
        videoDimensions = CGSize(width: CVPixelBufferGetWidth(image),
                                 height: CVPixelBufferGetHeight(image))

        // The immutable frame is retained while analysis happens off-main.
        // CVPixelBuffer isn't annotated Sendable by CoreVideo.
        let frame = ReadOnlyPixelBuffer(image)
        let worker = self.worker
        workQueue.async { [weak self] in
            let result = worker.analyse(frame.value, detect: detect)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProcessing = false
                self.lastAnalysedAt = Date()
                if detect {
                    self.candidates = result.people + result.vehicles
                }
                if self.selectedBounds != nil {
                    if let target = result.targetBounds {
                        self.selectedBounds = target
                        self.selectedConfidence = result.targetConfidence
                        self.selectedLost = false
                        self.status = "\(self.selectedLabel) tracked · \(Int(result.targetConfidence * 100))%"
                    } else if result.lost {
                        self.selectedLost = true
                        self.selectedConfidence = 0
                        self.status = "Target lost — select again"
                    }
                } else {
                    self.status = self.enabled ?
                        "People: \(result.people.count) · Vehicle model \(self.vehicleModelInstalled ? "ready" : "not installed")" :
                        "Analysis off"
                }
            }
        }
    }

    func select(_ candidate: VisionCandidate) {
        selectRect(candidate.bounds, label: candidate.kind)
    }

    func selectRect(_ rect: CGRect, label: String = "Object / vehicle") {
        guard rect.width >= 0.025 && rect.height >= 0.025,
              rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= 1, rect.maxY <= 1 else {
            status = "Target must be a visible box within the camera frame"
            return
        }
        selectedBounds = rect
        selectedLabel = label
        selectedConfidence = 1
        selectedLost = false
        status = "\(label) selected — local video tracking"
        let worker = self.worker
        workQueue.async {
            worker.select(rect)
        }
    }

    func clearSelection() {
        selectedBounds = nil
        selectedLabel = ""
        selectedConfidence = 0
        selectedLost = false
        status = enabled ? "Detecting people" : "Analysis off"
        let worker = self.worker
        workQueue.async {
            worker.clearSelection()
        }
    }

    /// DJI's targetRect is top-left-origin, unlike the Vision overlay.
    /// Requires a fresh detected frame and a human-selected target.
    func djiRect() -> TrackingRectangle? {
        guard let box = selectedBounds, !selectedLost,
              let lastAnalysedAt, Date().timeIntervalSince(lastAnalysedAt) < 2 else { return nil }
        let rect = TrackingRectangle(x: box.minX, y: 1 - box.maxY,
                                     width: box.width, height: box.height)
        return rect.isValid ? rect : nil
    }
}

/// Transfer a read-only, reference-counted CoreVideo frame to the serial
/// analysis queue. No code in this worker mutates the pixel data.
private struct ReadOnlyPixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) { self.value = value }
}

/// Vision requests run on a serial background queue: never use the SwiftUI
/// main actor to execute model inference.
// Confined to VisionTrackingEngine's single serial workQueue. This type
// never accesses AppKit/SwiftUI or shared mutable state concurrently.
private final class VisionAnalysisWorker: @unchecked Sendable {
    private let trackingHandler = VNSequenceRequestHandler()
    private var trackRequest: VNTrackObjectRequest?
    private var coreMLRequest: VNCoreMLRequest?
    private var lastPeople: [VisionCandidate] = []
    private var lastVehicles: [VisionCandidate] = []

    func loadVehicleModelIfPresent() -> Bool {
        // Compile and place an object-detection Core ML model at
        // Resources/GroundStationDetector.mlmodelc in the app bundle.
        // The model must output VNRecognizedObjectObservation results with
        // car / truck / bus / motorcycle / bicycle labels.
        guard let url = Bundle.main.url(forResource: "GroundStationDetector", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: url),
              let vision = try? VNCoreMLModel(for: model) else { return false }
        let request = VNCoreMLRequest(model: vision)
        request.imageCropAndScaleOption = .scaleFit
        coreMLRequest = request
        return true
    }

    func select(_ rect: CGRect) {
        let observation = VNDetectedObjectObservation(boundingBox: rect)
        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate
        trackRequest = request
    }

    func clearSelection() {
        trackRequest = nil
    }

    func analyse(_ image: CVPixelBuffer, detect: Bool) -> VisionTrackingOutput {
        var lost = false
        var bounds: CGRect?
        var confidence: Float = 0

        if let request = trackRequest {
            do {
                try trackingHandler.perform([request], on: image)
                if let found = request.results?.first as? VNDetectedObjectObservation,
                   found.confidence >= 0.32,
                   found.boundingBox.width >= 0.015,
                   found.boundingBox.height >= 0.015 {
                    bounds = found.boundingBox
                    confidence = found.confidence
                    request.inputObservation = found
                } else {
                    lost = true
                    trackRequest = nil
                }
            } catch {
                lost = true
                trackRequest = nil
            }
        }

        if detect {
            do {
                let personRequest = VNDetectHumanRectanglesRequest()
                let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
                try handler.perform([personRequest])
                lastPeople = (personRequest.results ?? []).prefix(16).map {
                    VisionCandidate(kind: "Person", confidence: $0.confidence,
                                    bounds: $0.boundingBox)
                }
            } catch { lastPeople = [] }

            if let vehicleRequest = coreMLRequest {
                do {
                    let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
                    try handler.perform([vehicleRequest])
                    let labels: Set<String> = ["car", "truck", "bus", "motorcycle",
                                               "motorbike", "vehicle", "bicycle"]
                    lastVehicles = (vehicleRequest.results as? [VNRecognizedObjectObservation] ?? [])
                        .filter {
                            guard let top = $0.labels.first else { return false }
                            return labels.contains(top.identifier.lowercased()) &&
                                top.confidence >= 0.3
                        }
                        .prefix(16)
                        .map {
                            VisionCandidate(kind: $0.labels[0].identifier.capitalized,
                                            confidence: $0.labels[0].confidence,
                                            bounds: $0.boundingBox)
                        }
                } catch { lastVehicles = [] }
            } else { lastVehicles = [] }
        }
        return VisionTrackingOutput(people: lastPeople, vehicles: lastVehicles,
                                    targetBounds: bounds, targetConfidence: confidence,
                                    lost: lost)
    }
}
