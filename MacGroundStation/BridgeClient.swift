import AppKit
import Combine
import Foundation
import Network

struct GroundStationLogEntry: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class BridgeClient: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var virtualSticksEnabled = false
    @Published private(set) var latestStatus: GroundStationMessage?
    @Published private(set) var latestFrame: NSImage?
    @Published private(set) var lastTelemetryAt: Date?
    @Published private(set) var lastFrameAt: Date?
    @Published var pairingCode = ""
    @Published var logs: [GroundStationLogEntry] = []

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var pendingActions: [String: GroundStationCommand.Action] = [:]
    private var lastStatusLog = Date.distantPast
    private var sticksTimer: Timer?
    private var stickAxes = (pitch: 0.0, roll: 0.0, yaw: 0.0, vertical: 0.0)

    var flightReady: Bool {
        #if GROUNDSTATION_FLIGHT_TESTED
        return connected && latestStatus?.payload.aircraftConnected == true &&
        latestStatus?.payload.simulated == false &&
        (latestStatus?.payload.batteryPercent ?? 0) >= 30 &&
        (latestStatus?.payload.satelliteCount ?? 0) >= 8 &&
        latestStatus?.payload.homeLocationSet == true &&
        (lastTelemetryAt.map { Date().timeIntervalSince($0) < 3 } ?? false) &&
        !pairingCode.isEmpty
        #else
        return false
        #endif
    }

    func connect(host: String, port: UInt16) {
        disconnect()
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            addLog("Enter a valid iPhone IP address")
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(trimmed), port: nwPort, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                switch state {
                case .ready:
                    self.connected = true
                    self.addLog("Connected to iPhone bridge")
                    self.receiveNext(from: conn)
                case .failed(let error):
                    self.close(conn, reason: "Connection failed: \(error.localizedDescription)")
                case .cancelled:
                    self.close(conn, reason: "Connection cancelled")
                default: break
                }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        addLog("Connecting to \(trimmed):\(port)…")
    }

    func disconnect() {
        stopSticks()
        if let conn = connection { close(conn, reason: "Disconnected") }
    }

    private func close(_ conn: NWConnection, reason: String) {
        guard connection === conn else { return }
        sticksTimer?.invalidate()
        sticksTimer = nil
        connection = nil
        conn.cancel()
        connected = false
        virtualSticksEnabled = false
        pendingActions.removeAll()
        latestStatus = nil
        latestFrame = nil
        lastTelemetryAt = nil
        lastFrameAt = nil
        receiveBuffer.removeAll()
        addLog(reason)
    }

    private func receiveNext(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                if let data, !data.isEmpty { self.consume(data, from: conn) }
                guard self.connection === conn else { return }
                if let error {
                    self.close(conn, reason: "Connection interrupted: \(error.localizedDescription). Check the iPhone app is open, then reconnect.")
                } else if complete {
                    self.close(conn, reason: "iPhone closed the connection. Reconnect when ready.")
                } else {
                    self.receiveNext(from: conn)
                }
            }
        }
    }

    private func consume(_ bytes: Data, from conn: NWConnection) {
        receiveBuffer.append(bytes)
        if receiveBuffer.count > 4_000_000 {
            close(conn, reason: "Incoming frame exceeded 4 MB limit")
            return
        }
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let line = Data(receiveBuffer.prefix(upTo: newline))
            receiveBuffer.removeSubrange(...newline)
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let message = try decoder.decode(GroundStationMessage.self, from: line)
                guard message.version == 1 else {
                    addLog("Unsupported message protocol")
                    continue
                }
                switch message.kind {
                case .aircraftStatus:
                    latestStatus = message
                    lastTelemetryAt = Date()
                    if Date().timeIntervalSince(lastStatusLog) > 10 {
                        addLog("Telemetry updates received (\(message.payload.aircraftConnected == true ? "aircraft" : "controller only"))")
                        lastStatusLog = Date()
                    }
                case .cameraFrame:
                    if let text = message.payload.imageJPEGBase64,
                       let data = Data(base64Encoded: text),
                       let image = NSImage(data: data) {
                        latestFrame = image
                        lastFrameAt = Date()
                    }
                case .commandResult:
                    if let id = message.payload.commandID,
                       let action = pendingActions.removeValue(forKey: id) {
                        if action == .enableSticks {
                            virtualSticksEnabled = message.payload.commandAccepted == true
                        }
                        if action == .disableSticks || action == .disarmFlight {
                            virtualSticksEnabled = false
                        }
                    }
                    addLog("Command: \(message.payload.message ?? "Unknown response")")
                case .error:
                    addLog("Bridge error: \(message.payload.message ?? "Unknown")")
                default: break
                }
            } catch {
                addLog("Could not decode a bridge message: \(error.localizedDescription)")
            }
        }
    }


    /// Stage a selected video rectangle for DJI's native ActiveTrack.
    /// DJI-side movement is still rejected until safety commissioning.
    func prepareActiveTrack(rect: TrackingRectangle) {
        guard rect.isValid else {
            addLog("Selected subject is outside the video frame")
            return
        }
        let command = GroundStationCommand(pairingCode: pairingCode,
                                           action: .activeTrackPrepare,
                                           trackingRect: rect)
        sendCommand(command)
    }

    func send(_ action: GroundStationCommand.Action, value: Double? = nil) {
        let command = GroundStationCommand(pairingCode: pairingCode, action: action, value: value)
        sendCommand(command)
    }

    private func sendCommand(_ command: GroundStationCommand) {
        guard connected, let conn = connection else {
            addLog("Not connected to bridge")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if command.action != .sticks {
                pendingActions[command.id] = command.action
            }
            var data = try encoder.encode(command)
            data.append(0x0A)
            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    Task { @MainActor in self?.addLog("Command send failed: \(error.localizedDescription)") }
                }
            })
        } catch {
            addLog("Could not encode command: \(error.localizedDescription)")
        }
    }

    /// Continuous movement requires a held control on the Mac.
    /// Releasing it immediately requests neutral velocity and releases the stick timer.
    func startSticks(pitch: Double = 0, roll: Double = 0,
                     yaw: Double = 0, vertical: Double = 0) {
        guard flightReady && virtualSticksEnabled else { return }
        stickAxes = (pitch, roll, yaw, vertical)
        sticksTimer?.invalidate()
        emitSticks()
        sticksTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emitSticks() }
        }
    }

    private func emitSticks() {
        let cmd = GroundStationCommand(pairingCode: pairingCode, action: .sticks,
                                       pitch: stickAxes.pitch, roll: stickAxes.roll,
                                       yaw: stickAxes.yaw, vertical: stickAxes.vertical)
        sendCommand(cmd)
    }

    func stopSticks() {
        sticksTimer?.invalidate()
        sticksTimer = nil
        stickAxes = (0, 0, 0, 0)
        if connected {
            emitSticks()
        }
    }

    private func addLog(_ entry: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        logs.insert(GroundStationLogEntry(text: "[\(timestamp)] \(entry)"), at: 0)
        if logs.count > 100 { logs.removeLast(logs.count - 100) }
    }
}
