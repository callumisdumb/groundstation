import Foundation
import Network
import XCTest

final class PilotBridgeTests: XCTestCase {
    @MainActor
    func testPairedBridgeCarriesPilotingInputInSimulatedAndAuthorizedAircraftSessions() async throws {
        for simulator in [true, false] {
            let peer = PilotTestPeer(simulator: simulator)
            let client = BridgeClient()
            defer { client.disconnect(); peer.listener.stop() }
            let listening = expectation(description: "Test peer is listening on its assigned port")
            peer.listener.onListening = { listening.fulfill() }
            try peer.start()
            await fulfillment(of: [listening], timeout: 8)
            let port = try XCTUnwrap(peer.listener.port?.rawValue)
            XCTAssertNotEqual(port, 0)
            client.bridgeKeyInput = ""
            client.flightKeyInput = peer.key
            client.pairingCode = peer.code
            client.connect(host: "127.0.0.1", port: port)
            try await waitUntil { client.flightKeyVerified && client.latestStatus != nil }
            if !simulator {
                XCTAssertFalse(client.canPilot)
                client.requestVirtualSticks()
                XCTAssertEqual(client.stickAuthority, .idle)
                peer.authorized = true
                peer.sendStatus()
            }
            try await waitUntil { client.canPilot }
            // Cancel before the iPhone answers. A late grant or telemetry hint must never start output.
            client.requestVirtualSticks()
            try await waitUntil { peer.commands.contains { $0.action == .enableSticks } }
            let cancelled = try XCTUnwrap(peer.commands.last { $0.action == .enableSticks })
            client.releaseVirtualSticks()
            try await waitUntil { client.stickAuthority == .idle }
            peer.reply(to: cancelled, detail: "Late grant")
            peer.sendStatus(engaged: true)
            try await waitUntil { client.lastControlResult == "Late grant" && client.latestStatus?.payload.virtualSticksEngaged == true }
            XCTAssertEqual(client.stickAuthority, .idle)
            XCTAssertFalse(peer.commands.contains { $0.action == .sticks })

            client.requestVirtualSticks()
            try await waitUntil { peer.commands.filter { $0.action == .enableSticks }.count == 2 }
            let current = try XCTUnwrap(peer.commands.last { $0.action == .enableSticks })
            peer.reply(to: current, detail: "Grant")
            peer.sendStatus(engaged: true)
            try await waitUntil { client.stickAuthority == .active }
            var input = PilotInput()
            input.press(.hold, code: 49)
            input.press(.forward, code: 126)
            client.startSticks(input.axes(precision: true))
            try await waitUntil { peer.commands.contains { $0.action == .sticks && $0.roll == 0.35 && $0.pitch == 0 } }
            client.releaseVirtualSticks()
            try await waitUntil { client.stickAuthority == .idle }
            let lastStick = try XCTUnwrap(peer.commands.last { $0.action == .sticks })
            XCTAssertEqual([lastStick.pitch, lastStick.roll, lastStick.yaw, lastStick.vertical].compactMap { $0 }, [0, 0, 0, 0])
            XCTAssertEqual(peer.commands.last?.action, .disableSticks)
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        guard condition() else {
            XCTFail("Timed out waiting for the paired bridge", line: line)
            throw CocoaError(.coderValueNotFound)
        }
    }
}

@MainActor
private final class PilotTestPeer {
    let listener = BridgeListener()
    let key = FlightSecurity.generateKey()
    let code = "123456"
    let simulator: Bool
    var authorized = false
    private(set) var commands: [GroundStationCommand] = []
    private var buffer = Data()

    init(simulator: Bool) { self.simulator = simulator }

    func start() throws {
        let bridgeKey = try XCTUnwrap(BridgeTransport.bridgeKey(fromFlightKey: key))
        let params = try XCTUnwrap(BridgeTransport.parameters(key: bridgeKey, code: code, channel: .telemetry))
        listener.onReady = { [weak self] connection in
            self?.sendStatus()
            self?.read(from: connection)
        }
        try listener.start(parameters: params, port: .any)
    }

    func sendStatus(engaged: Bool = false) {
        var p = GroundStationMessage.Payload()
        p.aircraftConnected = true
        p.controllerConnected = true
        p.aircraftModel = "Mavic Pro"
        p.aircraftSampledAt = Date()
        p.djiSimulatorActive = simulator
        p.simulated = false
        p.liveFlightAuthorized = authorized
        p.virtualSticksEngaged = engaged
        p.isFlying = true
        p.batteryPercent = 80
        p.satelliteCount = 15
        p.homeLocationSet = true
        p.imuPreheating = false
        send(.init(kind: .aircraftStatus, payload: p))
    }

    func reply(to command: GroundStationCommand, detail: String) {
        var p = GroundStationMessage.Payload()
        p.commandID = command.id
        p.commandAccepted = true
        p.message = detail
        send(.init(kind: .commandResult, payload: p))
    }

    private func send(_ message: GroundStationMessage) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            var data = try encoder.encode(message)
            data.append(0x0A)
            listener.active?.send(content: data, completion: .idempotent)
        } catch { XCTFail(error.localizedDescription) }
    }

    private func read(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, self.listener.active === connection else { return }
                if let data { self.buffer.append(data) }
                while let end = self.buffer.firstIndex(of: 0x0A) {
                    let line = Data(self.buffer.prefix(upTo: end))
                    self.buffer.removeSubrange(...end)
                    guard let envelope = try? JSONDecoder().decode(EncryptedFlightPacket.self, from: line),
                          let command = FlightSecurity.open(envelope, key: self.key) else {
                        XCTFail("Expected an authenticated flight command")
                        return
                    }
                    self.commands.append(command)
                    if command.action == .verifyFlightKey || command.action == .disableSticks {
                        self.reply(to: command, detail: command.action.rawValue)
                    }
                }
                if !done && error == nil { self.read(from: connection) }
            }
        }
    }
}
