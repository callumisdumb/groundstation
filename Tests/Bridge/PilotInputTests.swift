import AppKit
import XCTest

final class PilotInputTests: XCTestCase {
    func testEveryDirectionUsesDJIBodyVelocityCoordinates() {
        let cases: [(PilotKey, [Double])] = [
            (.forward, [0, 0.35, 0, 0]), (.backward, [0, -0.35, 0, 0]),
            (.right, [0.35, 0, 0, 0]), (.left, [-0.35, 0, 0, 0]),
            (.yawRight, [0, 0, 8, 0]), (.yawLeft, [0, 0, -8, 0]),
            (.climb, [0, 0, 0, 0.25]), (.descend, [0, 0, 0, -0.25])
        ]
        for (key, expected) in cases {
            var input = PilotInput()
            input.press(key, code: 1)
            XCTAssertEqual(input.axes(precision: true), PilotAxes())
            input.press(.hold, code: 49)
            let command = input.axes(precision: true).command(pairingCode: "123456")
            XCTAssertEqual([command.pitch, command.roll, command.yaw, command.vertical].compactMap { $0 }, expected, key.rawValue)
        }
    }

    func testArrowAliasesCancelOppositesAndKeepDiagonalSpeedBounded() {
        var input = PilotInput()
        input.press(.hold, code: 49)
        for (code, expected) in [(UInt16(126), PilotKey.forward), (125, .backward), (123, .left), (124, .right)] {
            XCTAssertEqual(PilotKey.resolve(code: code, characters: ""), expected)
        }
        input.press(.forward, code: 13)
        input.press(.forward, code: 126)
        input.release(code: 13)
        XCTAssertEqual(input.axes(precision: false).forward, 0.8)
        input.press(.backward, code: 125)
        XCTAssertEqual(input.axes(precision: false), PilotAxes())
        input.release(code: 125)
        input.press(.right, code: 124)
        let axes = input.axes(precision: false)
        XCTAssertEqual(hypot(axes.forward, axes.right), 0.8, accuracy: 0.00001)
        input.release(code: 49)
        input.press(.hold, code: 49)
        XCTAssertEqual(input.axes(precision: false), PilotAxes())
    }

    @MainActor
    func testPracticeNeverRequestsOrSendsToTheBridge() {
        let link = TestFlightLink()
        let keyboard = KeyboardPilotController()
        let window = NSWindow()
        keyboard.install(client: link)
        defer { keyboard.uninstall() }
        keyboard.beginPractice(in: window)
        keyboard.keyChanged(code: 49, characters: " ", down: true, repeating: false)
        keyboard.keyChanged(code: 126, characters: "", down: true, repeating: false)
        XCTAssertEqual(keyboard.input.axes(precision: true).forward, 0.35)
        keyboard.stop()
        XCTAssertEqual(link.requests, 0)
        XCTAssertEqual(link.releases, 0)
        XCTAssertTrue(link.transmitted.isEmpty)
    }

    @MainActor
    func testGrantNeedsFreshInputAndWindowLossCancelsControl() {
        let link = TestFlightLink()
        let keyboard = KeyboardPilotController()
        let window = NSWindow()
        keyboard.install(client: link)
        defer { keyboard.uninstall() }
        keyboard.beginFlight(in: window)
        XCTAssertEqual(link.requests, 1)
        keyboard.keyChanged(code: 49, characters: " ", down: true, repeating: false)
        keyboard.keyChanged(code: 13, characters: "w", down: true, repeating: false)
        XCTAssertTrue(keyboard.input.pressed.isEmpty)
        link.stickAuthority = .active
        keyboard.syncAuthority()
        keyboard.keyChanged(code: 13, characters: "w", down: true, repeating: true)
        XCTAssertTrue(link.transmitted.isEmpty)
        keyboard.keyChanged(code: 49, characters: " ", down: true, repeating: false)
        keyboard.keyChanged(code: 126, characters: "", down: true, repeating: false)
        XCTAssertEqual(link.transmitted, [PilotAxes(forward: 0.35)])
        keyboard.keyChanged(code: 49, characters: "", down: false, repeating: false)
        XCTAssertEqual(link.transmitted.last, PilotAxes())
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertEqual(keyboard.mode, .off)
        XCTAssertEqual(link.releases, 1)
        // A late telemetry or enable reply cannot reactivate local keyboard capture.
        link.stickAuthority = .active
        keyboard.syncAuthority()
        XCTAssertEqual(keyboard.mode, .off)
    }

    @MainActor
    func testEscapeSheetAndReadinessLossReleasePendingOrActiveControl() {
        let link = TestFlightLink()
        let keyboard = KeyboardPilotController()
        let window = NSWindow()
        keyboard.install(client: link)
        defer { keyboard.uninstall() }
        keyboard.beginFlight(in: window)
        keyboard.keyChanged(code: 53, characters: "", down: true, repeating: false)
        XCTAssertEqual(keyboard.mode, .off)
        XCTAssertEqual(link.releases, 1)
        keyboard.beginFlight(in: window)
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)
        XCTAssertEqual(link.releases, 2)
        keyboard.beginFlight(in: window)
        link.stickAuthority = .active
        keyboard.syncAuthority()
        link.canPilot = false
        keyboard.syncAuthority()
        XCTAssertEqual(keyboard.mode, .off)
        XCTAssertEqual(link.releases, 3)
        XCTAssertTrue(link.transmitted.isEmpty)
    }
}

@MainActor
private final class TestFlightLink: KeyboardFlightLink {
    var canPilot = true
    var stickAuthority = StickAuthority.idle
    var requests = 0
    var releases = 0
    var transmitted: [PilotAxes] = []
    func requestVirtualSticks() { requests += 1; stickAuthority = .requesting("test") }
    func releaseVirtualSticks() { releases += 1; stickAuthority = .idle }
    func startSticks(_ axes: PilotAxes) { transmitted.append(axes) }
    func stopSticks() { transmitted.append(PilotAxes()) }
}
