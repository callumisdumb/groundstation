import Foundation
import Network

/// One-client continuous H.264 byte relay.
/// Input is the DJI video feeder's compressed data, without re-encoding.
/// Output is length-prefixed frames of arbitrary H.264 BYTE CHUNKS, *not* decoded
/// video frames. The Mac reassembles Annex-B NALs before decoding.
///
/// This LAN transport is plaintext and only appropriate for local preview
/// development; do not expose 8766 to the internet.
@MainActor
final class H264VideoServer {
    private let pairingCode: () -> String
    private var listener: NWListener?
    private var client: NWConnection?
    private var authorized = false
    private var handshakeBuffer = Data()
    private var outstandingBytes = 0
    private var lastSentAt = Date.distantPast

    /// Video is expendable when the network backs up; flight telemetry is not.
    private let maxOutstandingBytes = 768 * 1024
    private let maxChunkBytes = 256 * 1024

    init(pairingCode: @escaping () -> String) {
        self.pairingCode = pairingCode
    }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: 8766)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in self?.stop() }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            NSLog("GroundStation video listener failed: %@", error.localizedDescription)
        }
    }

    func stop() {
        client?.cancel()
        client = nil
        listener?.cancel()
        listener = nil
        authorized = false
        handshakeBuffer.removeAll()
        outstandingBytes = 0
    }

    private func accept(_ conn: NWConnection) {
        client?.cancel()
        client = conn
        authorized = false
        outstandingBytes = 0
        handshakeBuffer.removeAll()
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.client === conn else { return }
                switch state {
                case .ready: self.receiveHandshake(from: conn)
                case .failed, .cancelled: self.disconnect(conn)
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func receiveHandshake(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 128) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, self.client === conn else { return }
                if let data { self.handshakeBuffer.append(data) }
                if self.handshakeBuffer.count > 96 || done || error != nil {
                    self.disconnect(conn)
                    return
                }
                if let newline = self.handshakeBuffer.firstIndex(of: 0x0A) {
                    let line = self.handshakeBuffer.prefix(upTo: newline)
                    let text = String(data: line, encoding: .utf8) ?? ""
                    guard text == "GSVIDEO1 " + self.pairingCode() else {
                        self.disconnect(conn)
                        return
                    }
                    self.handshakeBuffer.removeAll()
                    self.authorized = true
                    self.monitorDisconnect(from: conn)
                } else {
                    self.receiveHandshake(from: conn)
                }
            }
        }
    }

    private func monitorDisconnect(from conn: NWConnection) {
        // Keep reading so a closed Mac socket releases our video sink promptly.
        conn.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self] _, _, done, error in
            Task { @MainActor in
                guard let self, self.client === conn else { return }
                if done || error != nil {
                    self.disconnect(conn)
                } else {
                    self.monitorDisconnect(from: conn)
                }
            }
        }
    }

    private func disconnect(_ conn: NWConnection) {
        guard client === conn else { return }
        client = nil
        authorized = false
        outstandingBytes = 0
        conn.cancel()
    }

    func pushH264(_ bytes: Data) {
        guard let conn = client, authorized,
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
                if error != nil { self.disconnect(conn) }
            }
        })
    }
}
