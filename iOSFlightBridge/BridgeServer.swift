import Combine
import Darwin
import Foundation
import Network

/// Local-only iPhone bridge. All operator controls originate on the Mac.
/// Session code is shown on iPhone for pairing; no phone flight UI is provided.
/// IMPORTANT: this is plain TCP. Never use on untrusted Wi-Fi or port-forward.
@MainActor
final class BridgeServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var localAddress: String?
    @Published private(set) var lastEvent = "Waiting"
    @Published private(set) var djiStatus = "DJI SDK not linked (simulator mode)"
    @Published private(set) var pairingCode = String(Int.random(in: 100_000...999_999))

    private var listener: NWListener?
    private var client: NWConnection?
    private var timer: Timer?
    private var framesTimer: Timer?
    private let djiAdapter = DJIAdapter()
    private var latestDJIStatus: GroundStationMessage.Payload?
    private var startedDJI = false
    private var commandBuffer = Data()
    private var seenCommands = Set<String>()
    private var badPairingAttempts = 0
    private let video = DJIFramePreview()

    func start() {
        if !startedDJI {
            startedDJI = true
            djiAdapter.onUpdate = { [weak self] payload in
                Task { @MainActor in
                    self?.latestDJIStatus = payload
                    self?.djiStatus = payload.connectionState ?? "DJI status unavailable"
                }
            }
            djiAdapter.onResult = { [weak self] id, accepted, detail in
                Task { @MainActor in
                    self?.sendResult(id: id, accepted: accepted, detail: detail)
                }
            }
            #if canImport(DJISDK)
            djiStatus = "DJI SDK loaded: registering…"
            #endif
            djiAdapter.start()
        }
        guard listener == nil else { return }
        do {
            let newListener = try NWListener(using: .tcp, on: 8765)
            newListener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.running = true
                        self?.lastEvent = "Listening on TCP 8765"
                        self?.localAddress = Self.wifiAddress()
                    case .failed(let error):
                        self?.lastEvent = "Listener failed: \(error)"
                        self?.running = false
                    case .cancelled:
                        self?.running = false
                    default: break
                    }
                }
            }
            listener = newListener
            newListener.start(queue: .global(qos: .userInitiated))
        } catch { lastEvent = "Could not open port: \(error)" }
    }

    func stop() {
        endSession()
        listener?.cancel()
        listener = nil
        running = false
        lastEvent = "Stopped"
    }

    private func accept(_ conn: NWConnection) {
        endSession()
        client = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.client === conn else { return }
                switch state {
                case .ready:
                    self.lastEvent = "Mac connected"
                    self.sendHello()
                    self.startStatusStream()
                    self.receiveNext(from: conn)
                case .failed(let error):
                    self.lastEvent = "Mac connection failed: \(error)"
                    self.endSession()
                case .cancelled:
                    self.endSession()
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
    }

    private func endSession() {
        timer?.invalidate()
        timer = nil
        framesTimer?.invalidate()
        framesTimer = nil
        djiAdapter.networkDisconnected()
        client?.cancel()
        client = nil
        commandBuffer.removeAll()
        badPairingAttempts = 0
        seenCommands.removeAll()
    }

    private func startStatusStream() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.djiAdapter.refreshConnection()
                self?.sendCurrentStatus()
            }
        }
        sendCurrentStatus()
        #if canImport(DJISDK)
        video.start()
        framesTimer?.invalidate()
        framesTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPreview() }
        }
        #endif
    }

    private func receiveNext(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self, self.client === conn else { return }
                if let bytes, !bytes.isEmpty { self.consumeCommands(bytes) }
                guard self.client === conn else { return }
                if complete || error != nil {
                    self.lastEvent = "Mac disconnected — controls released"
                    self.endSession()
                } else {
                    self.receiveNext(from: conn)
                }
            }
        }
    }

    private func consumeCommands(_ bytes: Data) {
        commandBuffer.append(bytes)
        if commandBuffer.count > 24_576 {
            lastEvent = "Oversized command rejected"
            endSession()
            return
        }
        while let newline = commandBuffer.firstIndex(of: 0x0A) {
            let line = Data(commandBuffer.prefix(upTo: newline))
            commandBuffer.removeSubrange(...newline)
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let command = try decoder.decode(GroundStationCommand.self, from: line)
                guard command.version == 1,
                      abs(Date().timeIntervalSince(command.timestamp)) <= 3,
                      command.id.count <= 80, !seenCommands.contains(command.id) else {
                    sendResult(id: command.id, accepted: false,
                               detail: "Expired, duplicate or unsupported command")
                    continue
                }
                guard command.pairingCode == pairingCode else {
                    badPairingAttempts += 1
                    sendResult(id: command.id, accepted: false, detail: "Incorrect pairing code")
                    if badPairingAttempts >= 5 {
                        lastEvent = "Too many incorrect pairing attempts"
                        endSession()
                    }
                    continue
                }
                seenCommands.insert(command.id)
                if seenCommands.count > 250 { seenCommands.removeAll() }
                djiAdapter.handle(command)
            } catch {
                lastEvent = "Invalid command JSON: \(error.localizedDescription)"
            }
        }
    }

    private func sendCurrentStatus() {
        if let current = latestDJIStatus {
            send(GroundStationMessage(kind: .aircraftStatus, payload: current))
            return
        }
        #if canImport(DJISDK)
        var status = GroundStationMessage.Payload()
        status.connectionState = "Waiting for DJI registration and RC connection"
        status.aircraftConnected = false
        status.simulated = false
        send(GroundStationMessage(kind: .aircraftStatus, payload: status))
        #else
        var test = GroundStationMessage.Payload()
        test.connectionState = "SIMULATED — no aircraft connection"
        test.aircraftModel = "Original Mavic Pro (simulated)"
        test.aircraftConnected = false
        test.batteryPercent = 82
        test.latitude = 55.95
        test.longitude = -3.19
        test.altitudeMeters = 0
        test.speedMetersPerSecond = 0
        test.simulated = true
        send(GroundStationMessage(kind: .aircraftStatus, payload: test))
        #endif
    }

    private func sendHello() {
        var payload = GroundStationMessage.Payload()
        payload.appName = "iOSFlightBridge"
        payload.deviceName = "iPhone"
        payload.connectionState = "bridge-ready"
        send(GroundStationMessage(kind: .hello, payload: payload))
    }

    private func sendPreview() {
        guard latestDJIStatus?.aircraftConnected == true else { return }
        video.captureJPEG { [weak self] jpeg in
            guard let jpeg, jpeg.count <= 400_000 else { return }
            Task { @MainActor in
                var payload = GroundStationMessage.Payload()
                payload.imageJPEGBase64 = jpeg.base64EncodedString()
                payload.simulated = false
                self?.send(GroundStationMessage(kind: .cameraFrame, payload: payload))
            }
        }
    }

    private func sendResult(id: String, accepted: Bool, detail: String) {
        var payload = GroundStationMessage.Payload()
        payload.commandID = id
        payload.commandAccepted = accepted
        payload.message = (accepted ? "OK: " : "REJECTED: ") + detail
        send(GroundStationMessage(kind: .commandResult, payload: payload))
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
        } catch { lastEvent = "JSON encoding error: \(error)" }
    }

    private static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard String(cString: entry.ifa_name) == "en0",
                  let socket = entry.ifa_addr,
                  socket.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(socket, socklen_t(socket.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                address = String(cString: host)
                break
            }
        }
        return address
    }
}
