import AppKit
import Combine

@MainActor
protocol KeyboardFlightLink: AnyObject {
    var canPilot: Bool { get }
    var stickAuthority: StickAuthority { get }
    func requestVirtualSticks()
    func releaseVirtualSticks()
    func startSticks(_ axes: PilotAxes)
    func stopSticks()
}

@MainActor
final class KeyboardPilotController: NSObject, ObservableObject {
    enum Mode { case off, practice, requesting, flight }

    @Published private(set) var mode: Mode = .off
    @Published private(set) var input = PilotInput()
    @Published private(set) var preciseMode = true

    private weak var client: KeyboardFlightLink?
    private weak var captureWindow: NSWindow?
    private var eventMonitor: Any?
    private var lastAxes = PilotAxes()
    var holdsSpace: Bool { input.pressed.contains(.hold) }
    var status: String {
        switch mode {
        case .off: return "Keyboard off"
        case .requesting: return "Waiting for the iPhone to grant control"
        case .practice: return "Key practice · local to this Mac"
        case .flight:
            if !holdsSpace { return "Keyboard ready · hold Space to move" }
            return lastAxes == PilotAxes() ? "Neutral input" : "Sending movement"
        }
    }

    func install(client: KeyboardFlightLink) {
        self.client = client
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in self?.handle(event) == true ? nil : event }
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSMenu.didBeginTrackingNotification,
                     NSControl.textDidBeginEditingNotification, NSText.didBeginEditingNotification] {
            center.addObserver(self, selector: #selector(interrupted), name: name, object: nil)
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification] {
            center.addObserver(self, selector: #selector(windowInterrupted(_:)), name: name, object: nil)
        }
    }

    func uninstall() {
        stop()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        NotificationCenter.default.removeObserver(self)
        client = nil
    }

    func beginPractice(in window: NSWindow?) {
        guard mode == .off, client?.stickAuthority == .idle, let window else { return }
        captureWindow = window
        mode = .practice
    }

    func beginFlight(in window: NSWindow?) {
        guard mode == .off, let client, client.canPilot, client.stickAuthority == .idle,
              let window else { return }
        captureWindow = window
        mode = .requesting
        client.requestVirtualSticks()
        syncAuthority()
    }

    func syncAuthority() {
        guard mode == .requesting || mode == .flight else { return }
        guard let client, client.canPilot else { stop(); return }
        switch client.stickAuthority {
        case .active:
            if mode == .requesting {
                input = PilotInput()
                mode = .flight
            }
        case .requesting: break
        case .idle, .releasing: stop()
        }
    }

    func stop() {
        let heldAuthority = mode == .requesting || mode == .flight
        mode = .off
        captureWindow = nil
        input = PilotInput()
        lastAxes = PilotAxes()
        if heldAuthority { client?.releaseVirtualSticks() }
    }

    @objc private func interrupted() { if mode != .off { stop() } }
    @objc private func windowInterrupted(_ note: Notification) {
        if let window = note.object as? NSWindow, window === captureWindow { interrupted() }
    }

    func togglePrecision() {
        guard !holdsSpace else { return }
        preciseMode.toggle()
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard mode != .off else { return false }
        guard let window = captureWindow, NSApp.isActive, window.isKeyWindow,
              window.attachedSheet == nil, NSApp.modalWindow == nil,
              !(window.firstResponder is NSTextView) else { stop(); return false }
        if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            stop()
            return false
        }
        if event.type == .flagsChanged { return false }
        guard event.window === window else { stop(); return false }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !input.pressed.isEmpty { stop() }
            return false
        }
        return keyChanged(code: event.keyCode, characters: event.charactersIgnoringModifiers ?? "",
                          down: event.type == .keyDown, repeating: event.isARepeat)
    }

    @discardableResult
    func keyChanged(code: UInt16, characters: String, down: Bool, repeating: Bool) -> Bool {
        guard mode != .off else { return false }
        if code == 53 {
            if down { stop() }
            return true
        }
        guard mode != .requesting else { return false }
        if mode == .flight, client?.canPilot != true || client?.stickAuthority != .active {
            stop()
            return false
        }
        if characters.lowercased() == "x" {
            if down && !repeating { togglePrecision() }
            return true
        }
        if !down {
            guard input.release(code: code) else { return false }
        } else {
            guard let key = PilotKey.resolve(code: code, characters: characters) else { return false }
            if repeating { return true }
            input.press(key, code: code)
        }
        let axes = input.axes(precision: preciseMode)
        if axes != lastAxes, mode == .flight {
            if axes == PilotAxes() { client?.stopSticks() } else { client?.startSticks(axes) }
        }
        lastAxes = axes
        return true
    }
}
