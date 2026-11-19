import AppKit
import AVFoundation
import Combine
import CoreMedia
import Network
import SwiftUI
import VideoToolbox

/// Separate H.264 transport and decoder. Video is NOT multiplexed with
/// flight telemetry or control messages, preventing encoded video backpressure
/// from blocking the small command messages on port 8765.
///
/// DJI's feed is Annex-B H.264. The server sends raw byte chunks with a
/// four-byte big-endian chunk length; this reader reconstructs H.264 NAL units.
@MainActor
final class H264LiveVideoClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var streamStatus = "Not connected"
    @Published private(set) var framesDisplayed = 0
    @Published private(set) var framesPerSecond = 0
    @Published private(set) var lastVideoAt: Date?

    let display = H264LiveDisplay()
    let vision = VisionTrackingEngine()

    private var connection: NWConnection?
    private var transportBuffer = Data()
    private let parser = H264AccessUnitParser()
    private var recentFrames = 0
    private var statsClock = Date()
    private let maxChunkSize = 256 * 1024

    init() {
        display.onDecodedFrame = { [weak self] pixelBuffer in
            self?.vision.receive(pixelBuffer)
        }
        parser.onAccessUnit = { [weak self] nalUnits, sps, pps in
            Task { @MainActor in
                self?.present(nalUnits, sps: sps, pps: pps)
            }
        }
    }

    func connect(host: String, pairingCode: String) {
        disconnect()
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, code.count == 6, code.allSatisfy(\.isNumber) else {
            streamStatus = "Enter iPhone IP and six-digit pairing code"
            return
        }
        guard let port = NWEndpoint.Port(rawValue: 8766) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        connection = conn
        streamStatus = "Connecting to iPhone video port 8766…"
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.connected = true
                    self.streamStatus = "Video socket connected; waiting for H.264 parameter sets"
                    conn.send(content: Data(("GSVIDEO1 " + code + "\n").utf8),
                              completion: .contentProcessed { [weak self] error in
                        if let error {
                            Task { @MainActor in
                                self?.close(conn, reason: "Video pairing failed: \(error.localizedDescription)")
                            }
                        }
                    })
                    self.receive(from: conn)
                case .failed(let error):
                    self.close(conn, reason: "Video connection failed: \(error.localizedDescription)")
                case .cancelled: self.close(conn, reason: "Video disconnected")
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        if let conn = connection {
            close(conn, reason: "Video disconnected")
        } else {
            resetVideo()
        }
    }

    private func close(_ conn: NWConnection, reason: String) {
        guard connection === conn else { return }
        connection = nil
        conn.cancel()
        resetVideo()
        streamStatus = reason
    }

    private func resetVideo() {
        connected = false
        framesDisplayed = 0
        framesPerSecond = 0
        lastVideoAt = nil
        recentFrames = 0
        statsClock = Date()
        transportBuffer.removeAll()
        parser.reset()
        display.reset()
    }

    private func receive(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                if let data, !data.isEmpty { self.consume(data, from: conn) }
                guard self.connection === conn else { return }
                if let error {
                    self.close(conn, reason: "Video stream interrupted: \(error.localizedDescription)")
                } else if done {
                    self.close(conn, reason: "Video stream closed; verify the iPhone bridge is active")
                } else {
                    self.receive(from: conn)
                }
            }
        }
    }

    private func consume(_ bytes: Data, from conn: NWConnection) {
        transportBuffer.append(bytes)
        if transportBuffer.count > 2 * 1024 * 1024 {
            close(conn, reason: "Video stream packet buffer exceeded 2 MB")
            return
        }
        while transportBuffer.count >= 4 {
            let count = transportBuffer.prefix(4).reduce(UInt32(0)) {
                ($0 << 8) | UInt32($1)
            }
            guard count > 0 && count <= maxChunkSize else {
                close(conn, reason: "Video stream has invalid packet length")
                return
            }
            guard transportBuffer.count >= Int(count) + 4 else { break }
            let payload = transportBuffer.subdata(in: 4 ..< 4 + Int(count))
            transportBuffer.removeSubrange(0 ..< 4 + Int(count))
            parser.append(payload)
        }
    }

    private func present(_ nalUnits: [Data], sps: Data, pps: Data) {
        guard connected else { return }
        guard display.show(nalUnits, sps: sps, pps: pps) else { return }
        framesDisplayed += 1
        recentFrames += 1
        lastVideoAt = Date()
        if Date().timeIntervalSince(statsClock) >= 1 {
            let seconds = max(Date().timeIntervalSince(statsClock), 0.001)
            framesPerSecond = Int((Double(recentFrames) / seconds).rounded())
            recentFrames = 0
            statsClock = Date()
            streamStatus = "LIVE H.264 · \(framesPerSecond) fps (decoded on Mac)"
        }
    }
}

/// Incremental Annex-B NAL parser. It can begin in the middle of the stream.
/// It collects SPS/PPS, waits for an IDR, and groups VCL slices into access
/// units by parsing the first_mb_in_slice Exp-Golomb value.
final class H264AccessUnitParser {
    var onAccessUnit: (([Data], Data, Data) -> Void)?

    private var bytes: [UInt8] = []
    private var sps: Data?
    private var pps: Data?
    private var frame: [Data] = []
    private var hasVCL = false
    private var seenIDR = false

    func reset() {
        bytes.removeAll(keepingCapacity: true)
        frame.removeAll()
        sps = nil
        pps = nil
        hasVCL = false
        seenIDR = false
    }

    func append(_ newBytes: Data) {
        bytes.append(contentsOf: newBytes)
        if bytes.count > 2 * 1024 * 1024 {
            reset()
            return
        }
        while let first = findStart(at: 0) {
            if first.index > 0 { bytes.removeFirst(first.index) }
            guard let next = findStart(at: first.count) else { break }
            let nal = Data(bytes[first.count ..< next.index])
            bytes.removeFirst(next.index)
            processNAL(nal)
        }
    }

    private func findStart(at offset: Int) -> (index: Int, count: Int)? {
        guard bytes.count >= 4 else { return nil }
        let end = bytes.count - 3
        guard offset < end else { return nil }
        for i in offset ..< end {
            if bytes[i] == 0 && bytes[i+1] == 0 {
                if bytes[i+2] == 1 { return (i, 3) }
                if bytes[i+2] == 0 && bytes[i+3] == 1 { return (i, 4) }
            }
        }
        return nil
    }

    private func processNAL(_ nal: Data) {
        guard let first = nal.first, !nal.isEmpty else { return }
        let type = first & 0x1F
        switch type {
        case 7:
            flush()
            if sps != nal { sps = nal; seenIDR = false }
        case 8:
            flush()
            if pps != nal { pps = nal; seenIDR = false }
        case 9: // Access-unit delimiter
            flush()
        case 1, 5: // Non-IDR / IDR slice
            // first_mb_in_slice == 0 starts a new picture; different slices
            // belonging to the same picture are kept together.
            if hasVCL && firstMacroblockIsZero(nal) { flush() }
            if type == 5 { seenIDR = true }
            frame.append(nal)
            hasVCL = true
        case 6: // SEI
            if hasVCL { flush() }
            frame.append(nal)
        case 10, 11:
            flush()
        default:
            if hasVCL { flush() }
            if type < 24 { frame.append(nal) }
        }
    }

    private func flush() {
        defer {
            frame.removeAll(keepingCapacity: true)
            hasVCL = false
        }
        guard hasVCL, seenIDR, let sps, let pps else { return }
        onAccessUnit?(frame, sps, pps)
    }

    private func firstMacroblockIsZero(_ nal: Data) -> Bool {
        // Exp-Golomb syntax for first_mb_in_slice: 1 bit for value zero.
        // Remove emulation-prevention bytes in the RBSP.
        guard nal.count >= 2 else { return true }
        let firstRBSPByte = nal[nal.index(after: nal.startIndex)]
        return (firstRBSPByte & 0x80) != 0
    }
}

/// Converts H.264 Annex-B NAL units into AVCC samples and queues them onto
/// Apple's hardware-backed AVSampleBufferDisplayLayer in the app's window.
@MainActor
final class H264LiveDisplay {
    let layer = AVSampleBufferDisplayLayer()
    var onDecodedFrame: ((CVPixelBuffer) -> Void)?

    private var analysisDecoder: VTDecompressionSession?

    private var currentSPS: Data?
    private var currentPPS: Data?
    private var format: CMVideoFormatDescription?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
    }

    func reset() {
        if let analysisDecoder {
            VTDecompressionSessionInvalidate(analysisDecoder)
        }
        analysisDecoder = nil
        layer.flushAndRemoveImage()
        currentSPS = nil
        currentPPS = nil
        format = nil
    }

    func show(_ nalUnits: [Data], sps: Data, pps: Data) -> Bool {
        if format == nil || sps != currentSPS || pps != currentPPS {
            guard configure(sps: sps, pps: pps) else { return false }
        }
        guard let format else { return false }
        var sampleBytes = Data()
        for nal in nalUnits {
            guard !nal.isEmpty, nal.count <= 512 * 1024 else { continue }
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { sampleBytes.append(contentsOf: $0) }
            sampleBytes.append(nal)
        }
        guard !sampleBytes.isEmpty else { return false }
        var block: CMBlockBuffer?
        let allocation = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: sampleBytes.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: sampleBytes.count,
            flags: 0,
            blockBufferOut: &block)
        guard allocation == noErr, let block else { return false }

        let copied = sampleBytes.withUnsafeBytes { raw -> OSStatus in
            guard let ptr = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: ptr, blockBuffer: block,
                                                 offsetIntoDestination: 0,
                                                 dataLength: sampleBytes.count)
        }
        guard copied == noErr else { return false }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: .invalid,
                                        decodeTimeStamp: .invalid)
        var size = sampleBytes.count
        let made = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample)
        guard made == noErr, let sample else { return false }

        // This is the CoreMedia-defined way to mark compressed video for
        // immediate display rather than waiting for an external playback clock.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0,
           let attachmentPointer = CFArrayGetValueAtIndex(attachments, 0) {
            let dictionary = unsafeBitCast(attachmentPointer, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        if layer.status == .failed { layer.flushAndRemoveImage() }
        guard layer.isReadyForMoreMediaData else { return false }
        layer.enqueue(sample)
        if let analysisDecoder, onDecodedFrame != nil {
            // Second VideoToolbox decoding path exposes uncompressed pixels to
            // Apple Vision without ever blocking or interfering with the
            // separate DJI camera/telemetry transport.
            _ = VTDecompressionSessionDecodeFrame(
                analysisDecoder,
                sampleBuffer: sample,
                flags: [],
                frameRefcon: nil,
                infoFlagsOut: nil)
        }
        return true
    }

    private func configure(sps: Data, pps: Data) -> Bool {
        var description: CMVideoFormatDescription?
        let result: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                guard let spsPtr = spsRaw.bindMemory(to: UInt8.self).baseAddress,
                      let ppsPtr = ppsRaw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                var pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                var sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description)
            }
        }
        guard result == noErr, let description else { return false }
        layer.flushAndRemoveImage()
        if let analysisDecoder {
            VTDecompressionSessionInvalidate(analysisDecoder)
        }
        analysisDecoder = nil
        var callback = VTDecompressionOutputCallbackRecord()
        callback.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()
        callback.decompressionOutputCallback = { refcon, _, status, _, imageBuffer, _, _ in
            guard status == noErr, let refcon, let imageBuffer else { return }
            let owner = Unmanaged<H264LiveDisplay>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                owner.onDecodedFrame?(imageBuffer)
            }
        }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let resultCode = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &analysisDecoder)
        if resultCode != noErr {
            analysisDecoder = nil
            NSLog("Vision analysis decoder unavailable: %d", resultCode)
        }
        format = description
        currentSPS = sps
        currentPPS = pps
        return true
    }
}

struct H264LiveVideoView: NSViewRepresentable {
    let display: H264LiveDisplay

    func makeNSView(context: Context) -> LiveVideoHostView {
        let view = LiveVideoHostView()
        view.attach(display.layer)
        return view
    }

    func updateNSView(_ view: LiveVideoHostView, context: Context) {
        if view.videoLayer !== display.layer {
            view.attach(display.layer)
        }
    }
}

final class LiveVideoHostView: NSView {
    weak var videoLayer: AVSampleBufferDisplayLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    func attach(_ videoLayer: AVSampleBufferDisplayLayer) {
        self.videoLayer = videoLayer
        videoLayer.removeFromSuperlayer()
        layer?.addSublayer(videoLayer)
        videoLayer.frame = bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }
    override func layout() {
        super.layout()
        videoLayer?.frame = bounds
    }
}
