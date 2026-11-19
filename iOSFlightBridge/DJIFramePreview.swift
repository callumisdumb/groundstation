import Foundation
import UIKit
import SwiftUI

#if canImport(DJISDK)
import DJISDK
#endif

/// Optional DJIWidget FPV preview and low-frame-rate JPEG snapshot transport.
/// JPEG snapshots are for situational awareness only, NOT for real-time piloting.
/// A production FPV link should use a measured low-latency encoded video path.
final class DJIFramePreview: NSObject {
    /// Continuous compressed H.264 bytes from DJI; shared with the Mac video relay.
    /// Do not convert this stream into JPEG snapshots.
    var onH264Data: ((Data) -> Void)?
    static let shared = DJIFramePreview()

    #if canImport(DJISDK)
    private weak var feed: DJIVideoFeed?
    private weak var displayView: UIView?

    func attach(to view: UIView) {
        displayView = view
        start()
    }

    func start() {
        DispatchQueue.main.async {
            guard let displayView = self.displayView else { return }
            let previewer = DJIVideoPreviewer.instance()
            previewer?.start()
            previewer?.setView(displayView)

            if self.feed == nil, let videoFeed = DJISDKManager.videoFeeder()?.primaryVideoFeed {
                self.feed = videoFeed
                videoFeed.add(self, with: nil)
            }
            if let aircraft = DJISDKManager.product() as? DJIAircraft,
               aircraft.camera?.displayName == DJICameraDisplayNameMavicProCamera,
               aircraft.airLink?.wifiLink != nil {
                // DJI's original SDK Swift sample uses this for the Mavic Pro Wi-Fi camera feed.
                previewer?.encoderType = ._1860_phantom4x
            }
        }
    }

    func captureJPEG(completion: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            self.start()
            guard self.feed != nil else {
                completion(nil)
                return
            }
            DJIVideoPreviewer.instance()?.snapshotPreview({ frame in
                guard let frame else {
                    completion(nil)
                    return
                }
                // Resize to avoid overwhelming the shared TCP telemetry connection.
                let maxWidth: CGFloat = 800
                let scale = min(1.0, maxWidth / max(1, frame.size.width))
                let imageSize = CGSize(width: frame.size.width * scale,
                                       height: frame.size.height * scale)
                let renderer = UIGraphicsImageRenderer(size: imageSize)
                let scaled = renderer.image { _ in
                    frame.draw(in: CGRect(origin: .zero, size: imageSize))
                }
                completion(scaled.jpegData(compressionQuality: 0.43))
            })
        }
    }
    #else
    func attach(to view: UIView) {}
    func start() {}
    func captureJPEG(completion: @escaping (Data?) -> Void) { completion(nil) }
    #endif
}

#if canImport(DJISDK)
extension DJIFramePreview: DJIVideoFeedListener {
    func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData videoData: Data) {
        guard videoFeed == feed else { return }
        onH264Data?(videoData)
        var buffer = videoData
        buffer.withUnsafeMutableBytes { rawBuffer in
            guard let data = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            DJIVideoPreviewer.instance()?.push(data, length: Int32(rawBuffer.count))
        }
    }
}
#endif

struct DJIFramePreviewSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        DJIFramePreview.shared.attach(to: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        DJIFramePreview.shared.start()
    }
}
