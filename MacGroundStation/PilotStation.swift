import AppKit
import SwiftUI

struct PilotStation: View {
    @ObservedObject var client: BridgeClient
    @ObservedObject var keyboard: KeyboardPilotController
    let status: ProjectStatus
    @Binding var showGuide: Bool
    let openConnection: () -> Void
    let openSetup: () -> Void
    let confirmTakeoff: () -> Void

    private enum Step {
        case connect, verify, waiting, setup, arm, takeoff, engage, requesting, release, releasing, practice
    }

    private var step: Step {
        switch keyboard.mode {
        case .flight: return .release
        case .requesting: return .requesting
        case .practice: return .practice
        case .off: break
        }
        if case .releasing = client.stickAuthority { return .releasing }
        if !client.connected { return client.connecting ? .waiting : .connect }
        if !client.flightKeyVerified { return .verify }
        guard status.hasAircraftData else { return .waiting }
        guard client.flightReady else { return .setup }
        if client.canPilot { return .engage }
        guard client.latestStatus?.payload.isFlying == false else { return .setup }
        return client.flightArmed ? .takeoff : .arm
    }

    private var actionTitle: String {
        switch step {
        case .connect: return "Connect iPhone"
        case .verify: return "Pair flight key"
        case .waiting: return status.rawValue
        case .setup: return "Review flight setup"
        case .arm: return "Arm for takeoff"
        case .takeoff: return "Take off…"
        case .engage: return "Fly with keyboard"
        case .requesting: return "Cancel control request"
        case .release: return "Release to controller"
        case .releasing: return "Releasing control…"
        case .practice: return "End key practice"
        }
    }

    private var detail: String {
        switch step {
        case .connect: return "Pair the bridge to see aircraft readiness."
        case .verify: return "Copy the flight key from the paired iPhone."
        case .waiting: return status == .demo ? "Demo telemetry has no flight controls." : "Waiting for a current aircraft sample."
        case .setup: return client.liveFlightAuthorized || client.djiSimulatorActive ? "Check the aircraft and flight readiness." : "Choose live flight or the DJI simulator."
        case .arm: return "Grounded · takeoff requires confirmation."
        case .takeoff: return "Armed · \(max(0, Int(ceil(client.flightArmExpires.timeIntervalSinceNow)))) s remaining"
        case .engage: return "Airborne · request keyboard control from the iPhone."
        case .requesting, .practice: return keyboard.status
        case .release: return keyboard.holdsSpace ? keyboard.status : "Hold Space and a direction. Esc hands back control."
        case .releasing: return "Waiting for the iPhone to confirm handoff."
        }
    }

    private func performStep() {
        switch step {
        case .connect, .verify: openConnection()
        case .setup: openSetup()
        case .arm: client.send(.armFlight)
        case .takeoff: confirmTakeoff()
        case .engage: keyboard.beginFlight(in: NSApp.keyWindow)
        case .release, .requesting, .practice: keyboard.stop()
        case .waiting, .releasing: break
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Pilot station", systemImage: "gamecontroller.fill").fontWeight(.semibold)
                Spacer()
                Text(status == .simulator ? "DJI simulator" : (status == .aircraft ? "Live aircraft" : status.rawValue))
                    .foregroundStyle(status.tint).lineLimit(1)
            }
            .font(.system(size: 11)).padding(.horizontal, 10).frame(height: 30).background(GSPalette.side)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if showGuide {
                        keyGuide
                    } else {
                        Text(detail).font(.system(size: 12)).foregroundStyle(GSPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(action: performStep) {
                            Label(actionTitle, systemImage: step == .release ? "hand.raised.fill" : "gamecontroller")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                        .disabled(step == .waiting || step == .releasing)
                        .accessibilityIdentifier("pilot-next-step")
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(spacing: 12) {
                Button(action: openSetup) { Label("Flight setup", systemImage: "checklist") }
                Spacer()
                Button { showGuide.toggle() } label: {
                    Label(showGuide ? "Back to pilot" : "Key guide  ?", systemImage: "keyboard")
                }
                .accessibilityLabel(showGuide ? "Close key guide" : "Open key guide")
                .keyboardShortcut("?", modifiers: [])
            }
            .buttonStyle(.plain).foregroundStyle(GSPalette.cyan)
            .font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).frame(height: 31)
        }
        .background(GSPalette.background)
    }

    private var keyGuide: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Keyboard guide").font(.system(size: 13, weight: .semibold))
                Spacer()
                if keyboard.mode == .off || keyboard.mode == .practice {
                    Button(keyboard.mode == .practice ? "End practice" : "Practice keys") {
                        if keyboard.mode == .practice { keyboard.stop() }
                        else { keyboard.beginPractice(in: NSApp.keyWindow) }
                    }
                    .controlSize(.small).disabled(client.stickAuthority != .idle)
                } else {
                    Button(keyboard.mode == .requesting ? "Cancel request" : "Release control") { keyboard.stop() }
                        .controlSize(.small)
                }
            }
            keyRow([.forward, .backward], "↑ ↓", "Forward / back")
            keyRow([.left, .right], "← →", "Left / right")
            keyRow([.yawLeft, .yawRight], "", "Turn left / right")
            keyRow([.climb, .descend], "", "Climb / descend")
            Text("Hold Space to move. Release for neutral. Esc releases control.")
                .font(.system(size: 11)).foregroundStyle(GSPalette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(keyboard.preciseMode ? "X  Precision" : "X  Normal") { keyboard.togglePrecision() }
                    .disabled(keyboard.holdsSpace)
                Spacer()
                Text(keyboard.mode == .practice ? "Local practice" : (keyboard.mode == .flight ? "Flight input" : "Keyboard off"))
                    .font(.caption).foregroundStyle(GSPalette.cyan)
            }.controlSize(.small)
        }
    }

    private func keyRow(_ keys: [PilotKey], _ arrows: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                let down = keyboard.input.pressed.contains(key)
                Text(key.rawValue).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(down ? Color.black : .white)
                    .frame(width: 19, height: 17)
                    .background(down ? GSPalette.green : GSPalette.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(arrows).foregroundStyle(GSPalette.muted)
            Spacer()
            Text(label)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.map(\.rawValue).joined(separator: ", ") + " · " + label)
        .accessibilityValue(keys.filter { keyboard.input.pressed.contains($0) }.map(\.rawValue).joined(separator: ", "))
    }
}
