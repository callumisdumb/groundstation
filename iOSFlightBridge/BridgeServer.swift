import Combine
import Darwin
import Foundation
import Network

/// Local-only iPhone bridge. All operator controls originate on the Mac.
/// Session code is shown on iPhone for pairing; no phone flight UI is provided.
/// Telemetry and video use separate, paired TLS channels.
@MainActor
final class BridgeServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var localAddress: String?
    @Published private(set) var lastEvent = "Waiting"
    @Published private(set) var djiStatus = "DJI SDK not linked (simulator mode)"
    @Published private(set) var pairingCode = String(Int.random(in: 100_000...999_999))
    /// 256-bit shared key shown once during setup and stored in Keychain.
    /// Never sent over the 8765/8766 connections.
    @Published private(set) var flightAccessKey = FlightKeyStore.loadOrCreate()

    private let listener = BridgeListener()
    private var starting = false
    private var client: NWConnection? { listener.active }
    var bridgeKey: String { BridgeTransport.bridgeKey(fromFlightKey: flightAccessKey) ?? "" }
    private var timer: Timer?
    private let djiAdapter = DJIAdapter()
    private var latestDJIStatus: GroundStationMessage.Payload?
    private var startedDJI = false
    private var commandBuffer = Data()
    private var commandWindow = CommandWindow()
    private var badPairingAttempts = 0
    private let video = DJIFramePreview.shared
    private let videoServer = H264VideoServer()

    func start() {
        guard !starting, !running else { return }
        if flightAccessKey.isEmpty { flightAccessKey = FlightKeyStore.loadOrCreate() }
        pairingCode = String(Int.random(in: 100_000...999_999))
        guard let parameters = BridgeTransport.parameters(key: bridgeKey, code: pairingCode, channel: .telemetry),
              let videoParameters = BridgeTransport.parameters(key: bridgeKey, code: pairingCode, channel: .video)
        else { lastEvent = "Unlock the iPhone to access its pairing key."; return }
        starting = true
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
        // A dedicated TCP channel carries encoded H.264. Telemetry stays on 8765.
        video.onH264Data = { [weak self] bytes in
            Task { @MainActor in self?.videoServer.pushH264(bytes) }
        }
        listener.onListening = { [weak self] in
            self?.starting = false
            self?.running = true
            self?.localAddress = Self.wifiAddress()
            self?.lastEvent = "Waiting for a paired Mac"
        }
        listener.onFailure = { [weak self] error in self?.listenerFailed(error) }
        videoServer.onFailure = { [weak self] error in self?.listenerFailed(error) }
        listener.onReady = { [weak self] conn in
            guard let self else { return }
            self.lastEvent = "Paired Mac connected"
            self.sendHello()
            self.startStatusStream()
            self.receiveNext(from: conn)
        }
        listener.onClose = { [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.djiAdapter.networkDisconnected()
            self.commandBuffer.removeAll()
            self.badPairingAttempts = 0
            self.lastEvent = "Mac disconnected · controls released"
        }
        do {
            try videoServer.start(parameters: videoParameters)
            try listener.start(parameters: parameters, port: 8765)
        } catch {
            stop()
            lastEvent = "Could not start the bridge: \(error.localizedDescription)"
        }
    }

    func resetPairing(restart: Bool) {
        let replacement = FlightSecurity.generateKey()
        guard FlightKeyStore.save(replacement) else {
            lastEvent = "Could not update Keychain. Unlock the iPhone and try again."
            return
        }
        stop()
        flightAccessKey = replacement
        if restart { start() }
    }

    private func listenerFailed(_ error: NWError) {
        stop()
        lastEvent = "Bridge stopped: \(error.localizedDescription)"
    }

    func stop() {
        listener.stop()
        videoServer.stop()
        video.onH264Data = nil
        starting = false
        running = false
        lastEvent = "Stopped"
    }

    private func endSession() {
        if let client { listener.close(client) }
    }

    private func startStatusStream() {
        timer?.invalidate()
        guard let session = client else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak session] _ in
            Task { @MainActor in
                guard let session, self?.client === session else { return }
                self?.djiAdapter.refreshConnection()
                self?.video.start()
                self?.sendCurrentStatus()
            }
        }
        sendCurrentStatus()
        #if canImport(DJISDK)
        video.start()
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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // The flight key is a separate privilege inside the paired TLS session.
            if let packet = try? decoder.decode(EncryptedFlightPacket.self, from: line) {
                guard let command = FlightSecurity.open(packet, key: flightAccessKey) else {
                    badPairingAttempts += 1
                    lastEvent = "Encrypted flight packet authentication failed"
                    if badPairingAttempts >= 5 { endSession() }
                    continue
                }
                validateAndDispatch(command, encrypted: true)
            } else if let command = try? decoder.decode(GroundStationCommand.self, from: line) {
                validateAndDispatch(command, encrypted: false)
            } else {
                lastEvent = "Invalid bridge command packet"
            }
        }
    }

    private func validateAndDispatch(_ command: GroundStationCommand, encrypted: Bool) {
        guard command.pairingCode == pairingCode else {
            badPairingAttempts += 1
            sendResult(id: command.id, accepted: false, detail: "Incorrect pairing code")
            if badPairingAttempts >= 5 {
                lastEvent = "Too many incorrect pairing attempts"
                endSession()
            }
            return
        }
        guard !command.action.requiresEncryptedFlightLink || encrypted else {
            sendResult(id: command.id, accepted: false,
                       detail: "Flight commands require the paired encrypted control key")
            return
        }

        guard commandWindow.admit(command) else {
            sendResult(id: command.id, accepted: false, detail: "Expired, duplicate or unsupported command")
            return
        }
        badPairingAttempts = 0

        if command.action == .verifyFlightKey {
            sendResult(id: command.id, accepted: encrypted,
                       detail: encrypted ? "Flight key verified for this session" : "Flight key missing")
            return
        }
        djiAdapter.handle(command)
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
