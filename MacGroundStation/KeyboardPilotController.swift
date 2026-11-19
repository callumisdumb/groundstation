import AppKit
import Combine
import SwiftUI

/// Desktop keyboard preview and (once separately verified) Virtual Stick input.
/// Keyboard shortcuts never activate the aircraft by themselves. On release,
/// focus loss, connection loss or disabling keyboard input, neutral commands
/// and stop requests are issued.
struct PilotAxes: Equatable {
    var forward = 0.0
    var strafe = 0.0
    var turn = 0.0
    var climb = 0.0
    var isNeutral: Bool {
        forward == 0 && strafe == 0 && turn == 0 && climb == 0
    }
}

@MainActor
final class KeyboardPilotController: ObservableObject {
    @Published var keyboardEnabled = false {
        didSet { if !keyboardEnabled { releaseAll() } }
    }
    @Published private(set) var keysDown: Set<String> = []
    @Published private(set) var deadmanHeld = false
    @Published private(set) var axes = PilotAxes()
    @Published private(set) var status = "Keyboard inactive"

    private weak var client: BridgeClient?
    private var eventMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?
    private var sendingMovement = false
    private var lastAxes = PilotAxes()

    /// Tracks only keys used by the cockpit. W/S translation, A/D strafe,
    /// Q/E yaw, C/Z altitude and SPACE as held-to-move interlock.
    private let mapped: Set<String> = ["w", "a", "s", "d", "q", "e", "z", "c", "space"]

    func install(client: BridgeClient) {
        self.client = client
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.consume(event)
        }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.releaseAll() }
            }
    }

    func uninstall() {
        releaseAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        deactivationObserver = nil
        client = nil
    }

    func releaseAll() {
        if sendingMovement {
            client?.stopSticks()
        }
        sendingMovement = false
        lastAxes = PilotAxes()
        keysDown.removeAll()
        deadmanHeld = false
        axes = PilotAxes()
        status = keyboardEnabled ? "Keyboard ready: hold SPACE + direction" : "Keyboard inactive"
    }

    func connectionChanged() {
        guard client?.connected == true else { releaseAll(); return }
        if client?.virtualSticksEnabled != true && sendingMovement {
            releaseAll()
        }
    }

    private func consume(_ event: NSEvent) -> NSEvent? {
        guard keyboardEnabled else { return event }
        // Do not intercept passwords, IP fields or other normal text inputs.
        if NSApp.keyWindow?.firstResponder is NSTextView {
            releaseAll()
            return event
        }
        guard NSApp.isActive, event.window == NSApp.keyWindow else {
            releaseAll()
            return event
        }
        let key = event.keyCode == 49 ? "space" :
            (event.charactersIgnoringModifiers ?? "").lowercased()
        guard mapped.contains(key) else {
            if event.keyCode == 53 { releaseAll() } // ESC
            return event
        }
        if event.type == .keyDown {
            if event.isARepeat { return nil }
            keysDown.insert(key)
        } else if event.type == .keyUp {
            keysDown.remove(key)
        }
        updateAxes()
        return nil
    }

    private func updateAxes() {
        deadmanHeld = keysDown.contains("space")
        let keyset = keysDown
        func component(_ positive: String, _ negative: String, _ maxSpeed: Double) -> Double {
            (keyset.contains(positive) ? maxSpeed : 0) -
            (keyset.contains(negative) ? maxSpeed : 0)
        }
        axes = PilotAxes(
            forward: component("w", "s", 0.6),
            strafe: component("d", "a", 0.6),
            turn: component("e", "q", 12),
            climb: component("c", "z", 0.35))

        guard deadmanHeld, !axes.isNeutral else {
            if sendingMovement { client?.stopSticks() }
            sendingMovement = false
            lastAxes = PilotAxes()
            status = deadmanHeld ? "Neutral / hovering requested" : "Hold SPACE + direction"
            return
        }
        guard let client,
              client.connected, client.flightReady, client.virtualSticksEnabled else {
            if sendingMovement { client?.stopSticks() }
            sendingMovement = false
            lastAxes = PilotAxes()
            status = "INPUT PREVIEW ONLY — flight actuation locked"
            return
        }
        // Once tested, the existing BridgeClient timer will send the bounded
        // axes at 10 Hz until a key is released or focus is lost.
        if !sendingMovement || axes != lastAxes {
            client.startSticks(pitch: axes.forward,
                               roll: axes.strafe,
                               yaw: axes.turn,
                               vertical: axes.climb)
        }
        sendingMovement = true
        lastAxes = axes
        status = "Virtual Stick input active — SPACE held"
    }
}
