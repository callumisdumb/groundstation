import Foundation
import Combine
import Darwin
import Network

/// Local, unauthenticated prototype listener. Never expose this port to the internet.
@MainActor
final class BridgeServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var localAddress: String?
    @Published private(set) var lastEvent = "Waiting"

    private var listener: NWListener?
    private var client: NWConnection?
    private var timer: Timer?

    func start() {
        guard listener == nil else { return }
        do {
            let newListener = try NWListener(using: .tcp, on: 8765)
            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.running = true
                        self?.lastEvent = "Listening on TCP 8765"
                        self?.localAddress = Self.wifiAddress()
                    case .failed(let error):
                        self?.lastEvent = "Listener error: \(error)"
                        self?.running = false
                    case .cancelled:
                        self?.running = false
                    default: break
                    }
                }
            }
            listener = newListener
            newListener.start(queue: .global(qos: .userInitiated))
        } catch {
            lastEvent = "Could not start listener: \(error)"
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        client?.cancel()
        client = nil
        listener?.cancel()
        listener = nil
        running = false
        lastEvent = "Stopped"
    }

    private func accept(_ connection: NWConnection) {
        timer?.invalidate()
        client?.cancel()
        client = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.client === connection else { return }
                switch state {
                case .ready:
                    self.lastEvent = "Mac connected"
                    self.sendHello()
                    self.startStatusStream()
                    self.monitorClient(connection)
                case .failed(let error):
                    self.lastEvent = "Client error: \(error)"
                    self.timer?.invalidate()
                case .cancelled:
                    self.timer?.invalidate()
                default: break
                }
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func monitorClient(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, done, error in
            Task { @MainActor in
                guard let self, self.client === connection else { return }
                if done || error != nil {
                    self.timer?.invalidate()
                    self.lastEvent = "Mac disconnected"
                    self.client?.cancel()
                    self.client = nil
                } else {
                    self.monitorClient(connection)
                }
            }
        }
    }

    private func sendHello() {
        var payload = GroundStationMessage.Payload()
        payload.appName = "iOSFlightBridge"
        payload.deviceName = "iPhone"
        payload.connectionState = "bridge-ready"
        payload.simulated = true
        send(GroundStationMessage(kind: .hello, payload: payload))
    }

    private func startStatusStream() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendSimulatedStatus() }
        }
        sendSimulatedStatus()
    }

    private func sendSimulatedStatus() {
        // DEMONSTRATION VALUES, not live readings.
        var payload = GroundStationMessage.Payload()
        payload.connectionState = "SIMULATED — no aircraft connection"
        payload.aircraftModel = "Original Mavic Pro (simulated)"
        payload.batteryPercent = 82
        payload.latitude = 55.95
        payload.longitude = -3.19
        payload.altitudeMeters = 0
        payload.speedMetersPerSecond = 0
        payload.simulated = true
        send(GroundStationMessage(kind: .aircraftStatus, payload: payload))
    }

    private func send(_ message: GroundStationMessage) {
        guard let client else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(message)
            data.append(0x0A)
            client.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task { @MainActor in self?.lastEvent = "Send error: \(error)" }
                }
            })
        } catch {
            lastEvent = "Encoding error: \(error)"
        }
    }

    private static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let name = String(cString: entry.ifa_name)
            guard name == "en0", let socket = entry.ifa_addr,
                  socket.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(socket, socklen_t(socket.pointee.sa_len),
                                     &host, socklen_t(host.count),
                                     nil, 0, NI_NUMERICHOST)
            if status == 0 {
                address = String(cString: host)
                break
            }
        }
        return address
    }
}
