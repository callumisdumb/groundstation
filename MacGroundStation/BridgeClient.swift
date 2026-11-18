import Foundation
import Combine
import Network

@MainActor
final class BridgeClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var latestStatus: GroundStationMessage?
    @Published var logs: [String] = []

    private var connection: NWConnection?
    private var receiveBuffer = Data()

    func connect(host: String, port: UInt16) {
        disconnect()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            addLog("Invalid port")
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.connected = true
                    self.addLog("TCP connection established")
                    self.receiveNext()
                case .failed(let error):
                    self.addLog("Connection failed: \(error)")
                    self.connected = false
                case .cancelled:
                    self.connected = false
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        addLog("Connecting to \(host):\(port)…")
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        connected = false
        latestStatus = nil
        receiveBuffer.removeAll()
        addLog("Disconnected")
    }

    private func receiveNext() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.consume(data) }
                if let error { self.addLog("Receive error: \(error)") }
                if complete {
                    self.connected = false
                    self.addLog("Bridge closed connection")
                } else if error == nil {
                    self.receiveNext()
                }
            }
        }
    }

    private func consume(_ data: Data) {
        receiveBuffer.append(data)
        if receiveBuffer.count > 1_000_000 {
            addLog("Message buffer exceeded limit")
            disconnect()
            return
        }
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer.prefix(upTo: newline)
            receiveBuffer.removeSubrange(...newline)
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let message = try decoder.decode(GroundStationMessage.self, from: Data(line))
                guard message.version == 1 else {
                    addLog("Unsupported message version")
                    continue
                }
                if message.kind == .aircraftStatus { latestStatus = message }
                addLog("Received \(message.kind.rawValue)")
            } catch {
                addLog("Invalid message: \(error.localizedDescription)")
            }
        }
    }

    private func addLog(_ entry: String) {
        logs.insert("[\(Date.now.formatted(date: .omitted, time: .standard))] \(entry)", at: 0)
        if logs.count > 80 { logs.removeLast(logs.count - 80) }
    }
}
