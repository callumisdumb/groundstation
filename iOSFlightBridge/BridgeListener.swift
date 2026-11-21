import Foundation
import Network

/// Admit one authenticated session. New sockets never evict the active peer.
@MainActor
final class BridgeListener {
    var onReady: ((NWConnection) -> Void)?
    var onClose: (() -> Void)?
    var onListening: (() -> Void)?
    var onFailure: ((NWError) -> Void)?

    var port: NWEndpoint.Port? { listener?.port }
    private var listener: NWListener?
    private var candidates: [ObjectIdentifier: NWConnection] = [:]
    private(set) var active: NWConnection?

    func start(parameters: NWParameters, port: NWEndpoint.Port) throws {
        guard listener == nil else { return }
        let server = try NWListener(using: parameters, on: port)
        listener = server
        server.newConnectionHandler = { [weak self, weak server] conn in
            Task { @MainActor in
                guard let self, let server, self.listener === server else { conn.cancel(); return }
                self.accept(conn)
            }
        }
        server.stateUpdateHandler = { [weak self, weak server] state in
            Task { @MainActor in
                guard let self, let server, self.listener === server else { return }
                switch state {
                case .ready: self.onListening?()
                case .failed(let error):
                    self.stop()
                    self.onFailure?(error)
                default: break
                }
            }
        }
        server.start(queue: .global(qos: .userInitiated))
    }

    private func accept(_ conn: NWConnection) {
        guard active == nil, candidates.count < 4 else { conn.cancel(); return }
        let id = ObjectIdentifier(conn)
        candidates[id] = conn
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            Task { @MainActor in
                guard let self, let conn else { return }
                switch state {
                case .ready:
                    guard self.candidates.removeValue(forKey: id) != nil,
                          self.active == nil, BridgeTransport.authenticated(conn) else {
                        conn.cancel()
                        return
                    }
                    self.active = conn
                    self.cancelCandidates()
                    self.onReady?(conn)
                case .waiting(let error):
                    if case .tls = error { self.close(conn) }
                case .failed, .cancelled: self.close(conn)
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        Task { @MainActor [weak self, weak conn] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, let conn, self.candidates[id] === conn else { return }
            self.close(conn)
        }
    }

    func close(_ conn: NWConnection) {
        candidates.removeValue(forKey: ObjectIdentifier(conn))
        conn.stateUpdateHandler = nil
        conn.cancel()
        if active === conn {
            active = nil
            onClose?()
        }
    }

    private func cancelCandidates() {
        let pending = Array(candidates.values)
        candidates.removeAll()
        for conn in pending { conn.cancel() }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        cancelCandidates()
        if let active { close(active) }
    }
}
