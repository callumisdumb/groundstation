import Foundation
import Network

/// One-client continuous H.264 byte relay.
/// Input is the DJI video feeder's compressed data, without re-encoding.
/// Output is length-prefixed frames of arbitrary H.264 BYTE CHUNKS, *not* decoded
/// video frames. The Mac reassembles Annex-B NALs before decoding.
///
/// The TLS handshake verifies the bridge key and current session code.
@MainActor
final class H264VideoServer {
    private let listener = BridgeListener()
    var onFailure: ((NWError) -> Void)?
    private var client: NWConnection? { listener.active }
    private var outstandingBytes = 0

    /// Video is expendable when the network backs up; flight telemetry is not.
    private let maxOutstandingBytes = 768 * 1024
    private let maxChunkBytes = 256 * 1024

    func start(parameters: NWParameters) throws {
        listener.onReady = { [weak self] conn in self?.monitorDisconnect(from: conn) }
        listener.onClose = { [weak self] in self?.outstandingBytes = 0 }
        listener.onFailure = { [weak self] error in self?.onFailure?(error) }
        try listener.start(parameters: parameters, port: 8766)
    }

    func stop() {
        listener.stop()
    }

    private func monitorDisconnect(from conn: NWConnection) {
        // Keep reading so a closed Mac socket releases our video sink promptly.
        conn.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] _, _, done, error in
            Task { @MainActor in
                guard let self, self.client === conn else { return }
                if done || error != nil {
                    self.listener.close(conn)
                } else {
                    self.monitorDisconnect(from: conn)
                }
            }
        }
    }

    func pushH264(_ bytes: Data) {
        guard let conn = client,
              bytes.count > 0, bytes.count <= maxChunkBytes,
              outstandingBytes + bytes.count <= maxOutstandingBytes else { return }

        var count = UInt32(bytes.count).bigEndian
        var packet = Data(capacity: 4 + bytes.count)
        withUnsafeBytes(of: &count) { packet.append(contentsOf: $0) }
        packet.append(bytes)
        outstandingBytes += bytes.count

        conn.send(content: packet, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                guard self.client === conn else { return }
                self.outstandingBytes = max(0, self.outstandingBytes - bytes.count)
                if error != nil { self.listener.close(conn) }
            }
        })
    }
}
