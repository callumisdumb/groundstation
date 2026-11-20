import Network
import XCTest

final class BridgeTests: XCTestCase {
    func testKeyAndSessionValidation() throws {
        let flightKey = FlightSecurity.generateKey()
        let bridgeKey = try XCTUnwrap(BridgeTransport.bridgeKey(fromFlightKey: flightKey))
        XCTAssertNotEqual(flightKey, bridgeKey)
        XCTAssertEqual(bridgeKey, BridgeTransport.bridgeKey(fromFlightKey: flightKey))
        XCTAssertNil(BridgeTransport.parameters(key: "", code: "123456", channel: .telemetry))
        XCTAssertNil(BridgeTransport.parameters(key: bridgeKey, code: "１２３４５６", channel: .video))
        let command = GroundStationCommand(pairingCode: "123456", action: .verifyFlightKey)
        let envelope = try XCTUnwrap(FlightSecurity.seal(command, key: flightKey))
        let packet = try JSONDecoder().decode(EncryptedFlightPacket.self, from: envelope)
        XCTAssertNil(FlightSecurity.open(packet, key: bridgeKey))
        XCTAssertEqual(FlightSecurity.open(packet, key: flightKey)?.id, command.id)
    }

    func testCommandIDsStayReservedUntilExpiry() {
        let now = Date()
        var window = CommandWindow()
        var command = GroundStationCommand(timestamp: now, pairingCode: "123456", action: .verifyFlightKey)
        let first = command
        for i in 0..<256 {
            if i > 0 { command.id = UUID().uuidString }
            XCTAssertTrue(window.admit(command, now: now))
        }
        command.id = UUID().uuidString
        XCTAssertFalse(window.admit(command, now: now))
        XCTAssertFalse(window.admit(first, now: now.addingTimeInterval(2.9)))
        XCTAssertFalse(window.admit(first, now: now.addingTimeInterval(4)))
        command.timestamp = now.addingTimeInterval(4)
        XCTAssertTrue(window.admit(command, now: command.timestamp))
    }

    func testTLSChannelsOnLoopback() async throws {
        let key = FlightSecurity.generateKey()
        try await exchange(key: key, serverChannel: .telemetry, clientChannel: .telemetry)
        try await exchange(key: key, serverChannel: .video, clientChannel: .video)
        try await exchange(key: key, serverChannel: .telemetry, clientChannel: .video, shouldPair: false)
        try await exchange(key: key, serverChannel: .video, clientChannel: .video, clientCode: "234567", shouldPair: false)
    }

    @MainActor
    private func exchange(key: String, serverChannel: BridgeTransport.Channel, clientChannel: BridgeTransport.Channel,
                          clientCode: String = "123456", shouldPair: Bool = true) async throws {
        let listener = BridgeListener()
        let listening = expectation(description: "TLS listener ready")
        let outcome = expectation(description: "Pairing outcome")
        let data = Data("GroundStation review".utf8)
        listener.onListening = { listening.fulfill() }
        listener.onReady = { connection in
            XCTAssertTrue(shouldPair)
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        let server = try XCTUnwrap(BridgeTransport.parameters(key: key, code: "123456", channel: serverChannel))
        try listener.start(parameters: server, port: .any)
        defer { listener.stop() }
        await fulfillment(of: [listening], timeout: 10)
        let port = try XCTUnwrap(listener.port)
        let parameters = try XCTUnwrap(BridgeTransport.parameters(key: key, code: clientCode, channel: clientChannel))
        let connection = NWConnection(host: "127.0.0.1", port: port, using: parameters)
        defer { connection.cancel() }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                XCTAssertTrue(shouldPair)
                XCTAssertTrue(BridgeTransport.authenticated(connection))
                connection.receive(minimumIncompleteLength: data.count, maximumLength: 128) { response, _, _, _ in
                    XCTAssertEqual(response, data)
                    outcome.fulfill()
                }
            case .waiting(let error), .failed(let error):
                XCTAssertFalse(shouldPair, "Unexpected handshake failure: \(error)")
                connection.cancel()
                outcome.fulfill()
            default: break
            }
        }
        connection.start(queue: DispatchQueue(label: "GroundStation.transport-test"))
        await fulfillment(of: [outcome], timeout: 12)
        if !shouldPair { XCTAssertNil(listener.active) }
    }
}
