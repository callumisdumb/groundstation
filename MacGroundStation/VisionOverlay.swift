import SwiftUI

/// Target overlay and selection on the Mac's native H.264 display.
/// Rectangles follow Apple's bottom-left Vision coordinate convention here;
/// the bridge converts them to DJI's top-left mission rectangles.
struct VisionVideoOverlay: View {
    @ObservedObject var vision: VisionTrackingEngine
    @ObservedObject var client: BridgeClient
    var manualLabel: String = "Vehicle / object"

    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let video = aspectFitRect(in: geometry.size)
            ZStack(alignment: .topLeading) {
                Color.clear.contentShape(Rectangle())

                if vision.enabled {
                    ForEach(vision.candidates) { item in
                        candidateBox(item, in: video)
                    }
                }

                if let tracked = vision.selectedBounds {
                    let bounds = displayRect(for: tracked, in: video)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(vision.selectedLost ? .red : GSPalette.green,
                                      style: StrokeStyle(lineWidth: 2.5, dash: [8, 4]))
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                        .allowsHitTesting(false)
                    Text(vision.selectedLost ? "TARGET LOST" :
                            "\(vision.selectedLabel.uppercased()) · \(Int(vision.selectedConfidence * 100))%")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(vision.selectedLost ? Color.red : GSPalette.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .position(x: min(bounds.minX + 75, video.maxX - 65),
                                  y: max(bounds.minY - 12, video.minY + 10))
                        .allowsHitTesting(false)
                }

                if let sdk = client.latestStatus?.payload.activeTrackTargetRect,
                   sdk.isValid {
                    let flipped = CGRect(x: sdk.x, y: 1 - sdk.y - sdk.height,
                                         width: sdk.width, height: sdk.height)
                    let bounds = displayRect(for: flipped, in: video)
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(GSPalette.amber,
                                      style: StrokeStyle(lineWidth: 1.8, dash: [5, 3]))
                        .frame(width: bounds.width, height: bounds.height)
                        .position(x: bounds.midX, y: bounds.midY)
                        .allowsHitTesting(false)
                }

                if let dragStart, let dragEnd {
                    let rect = CGRect(x: min(dragStart.x, dragEnd.x),
                                      y: min(dragStart.y, dragEnd.y),
                                      width: abs(dragEnd.x - dragStart.x),
                                      height: abs(dragEnd.y - dragStart.y))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(GSPalette.cyan.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(GSPalette.cyan, lineWidth: 2))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard video.contains(value.startLocation),
                          video.contains(value.location) else { return }
                    dragStart = value.startLocation
                    dragEnd = value.location
                }
                .onEnded { value in
                    defer {
                        dragStart = nil
                        dragEnd = nil
                    }
                    guard video.contains(value.startLocation),
                          video.contains(value.location),
                          video.width > 0, video.height > 0 else { return }
                    let x1 = (value.startLocation.x - video.minX) / video.width
                    let x2 = (value.location.x - video.minX) / video.width
                    let y1 = 1 - (value.startLocation.y - video.minY) / video.height
                    let y2 = 1 - (value.location.y - video.minY) / video.height
                    let rect = CGRect(x: min(x1, x2), y: min(y1, y2),
                                      width: abs(x2-x1), height: abs(y2-y1))
                    vision.selectRect(rect, label: manualLabel)
                }
            )
        }
        .accessibilityLabel("AI targets and manual box selection over live aircraft camera")
    }

    @ViewBuilder
    private func candidateBox(_ item: VisionCandidate, in video: CGRect) -> some View {
        let bounds = displayRect(for: item.bounds, in: video)
        Button {
            vision.select(item)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(GSPalette.cyan, lineWidth: 1.8)
                .background(GSPalette.cyan.opacity(0.09))
                .overlay(alignment: .topLeading) {
                    Text("\(item.kind) · \(Int(item.confidence * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(4)
                        .background(GSPalette.cyan)
                        .foregroundStyle(.black)
                        .offset(y: -19)
                }
        }
        .buttonStyle(.plain)
        .frame(width: bounds.width, height: bounds.height)
        .position(x: bounds.midX, y: bounds.midY)
        .help("Select \(item.kind) for video tracking")
    }

    private func aspectFitRect(in area: CGSize) -> CGRect {
        let video = vision.videoDimensions
        let width = max(video.width, 1)
        let height = max(video.height, 1)
        let scale = min(area.width / width, area.height / height)
        let w = width * scale
        let h = height * scale
        return CGRect(x: (area.width-w)/2, y: (area.height-h)/2,
                      width: w, height: h)
    }

    private func displayRect(for normalized: CGRect, in video: CGRect) -> CGRect {
        // Vision: x increases right; y increases UP, so flip for SwiftUI.
        CGRect(x: video.minX + normalized.minX * video.width,
               y: video.minY + (1-normalized.maxY) * video.height,
               width: normalized.width * video.width,
               height: normalized.height * video.height)
    }
}

struct VisionControlPanel: View {
    @ObservedObject var vision: VisionTrackingEngine
    @ObservedObject var client: BridgeClient
    @State private var selectedKind: ManualObjectKind = .vehicle

    private enum ManualObjectKind: String, CaseIterable, Identifiable {
        case vehicle = "Vehicle / object"
        case person = "Person"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "viewfinder")
                    .foregroundStyle(GSPalette.cyan)
                Text("Vision Intelligence")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                GSStatusChip(label: "ON-DEVICE AI", kind: .neutral)
            }
            Toggle("Detect people on live video", isOn: $vision.enabled)
                .font(.system(size: 11))
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PERSON DETECTION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GSPalette.muted)
                    Text("Apple Vision · built-in")
                        .font(.system(size: 11))
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GSPalette.green)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VEHICLE CLASSIFICATION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GSPalette.muted)
                    Text(vision.vehicleModelInstalled ? "Core ML model loaded" :
                            "Optional detector model not installed")
                        .font(.system(size: 10))
                }
                Spacer()
                Image(systemName: vision.vehicleModelInstalled ?
                      "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(vision.vehicleModelInstalled ?
                                     GSPalette.green : GSPalette.amber)
            }
            Divider().overlay(GSPalette.border)

            Text("Select subject").font(.system(size: 11, weight: .semibold))
            Picker("Manual selection", selection: $selectedKind) {
                ForEach(ManualObjectKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .font(.caption)
            Text("Click a detected person, or drag a rectangle over any object or vehicle in the video.")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let rect = vision.selectedBounds {
                GSStatusChip(label: vision.selectedLost ? "TARGET LOST" : "LOCAL TRACK ACTIVE",
                             kind: vision.selectedLost ? .bad : .good)
                Text("\(vision.selectedLabel) · \(Int(vision.selectedConfidence*100))%")
                    .font(.system(size: 11, weight: .medium))
                Text("Box \(String(format: "%.3f", rect.minX)), \(String(format: "%.3f", rect.minY))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GSPalette.muted)
                Button("Clear selection") { vision.clearSelection() }
            } else {
                Text("No subject selected")
                    .font(.system(size: 11))
                    .foregroundStyle(GSPalette.muted)
            }

            Divider().overlay(GSPalette.border)
            HStack {
                Text("DJI ActiveTrack")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                GSStatusChip(label: "FLIGHT LOCKED", kind: .caution)
            }
            Text("Original Mavic Pro supports DJI native ActiveTrack. Subject selection is independent of aircraft steering.")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(client.latestStatus?.payload.activeTrackState ??
                 "No autonomous mission started")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(GSPalette.amber)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Prepare DJI target") {
                    guard let rect = vision.djiRect() else { return }
                    client.prepareActiveTrack(rect: rect)
                }
                .disabled(!client.flightReady || vision.djiRect() == nil)
                Button("Confirm & follow") { client.send(.activeTrackConfirm) }
                    .disabled(!client.flightReady)
            }
            .controlSize(.small)
            Button(role: .destructive) {
                client.send(.activeTrackStop)
                vision.clearSelection()
            } label: {
                Label("Stop DJI tracking", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!client.connected)
            .controlSize(.small)
            Text("Autonomous movement requires separately validated, encrypted flight control and a supervising pilot with physical RC override.")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var manualSelectionLabel: String { selectedKind.rawValue }
}
