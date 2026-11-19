import CoreLocation
import MapKit
import SwiftUI

/// The FlightHub-style single-operator view for original Mavic Pro.
/// DJI FlightHub 2 itself does not support this legacy aircraft.
struct CockpitWorkspace: View {
    @ObservedObject var client: BridgeClient
    @ObservedObject var video: H264LiveVideoClient
    @ObservedObject var keyboard: KeyboardPilotController
    @ObservedObject var missions: MissionLibrary
    @Binding var satellite: Bool
    @Binding var followAircraft: Bool
    let track: [CLLocationCoordinate2D]

    @State private var inspector: ControlTab = .vision
    @State private var manualTrackingLabel = "Vehicle / object"
    @State private var gimbalPitch = -30.0
    @State private var cameraFocusMode = false
    @State private var confirmAction: GroundStationCommand.Action?

    private var telemetry: GroundStationMessage.Payload? { client.latestStatus?.payload }
    private var connectedAircraft: Bool { telemetry?.validAircraft == true }

    enum ControlTab: String, CaseIterable, Identifiable {
        case flight = "Flight"
        case camera = "Camera"
        case aircraft = "Status"
        case vision = "AI Tracking"
        var id: Self { self }
    }

    var body: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        fpv
                            .frame(minWidth: 340, maxWidth: .infinity)
                        if !cameraFocusMode {
                            mapPanel
                                .frame(width: 350)
                        }
                    }
                    liveInstruments
                    GSPanel("Operations overview", icon: "info.circle") {
                        HStack(spacing: 16) {
                            Label(telemetry?.flightMode ?? "Flight mode unavailable", systemImage: "airplane")
                            Spacer()
                            Label(telemetry?.locationText ?? "Position unavailable", systemImage: "location")
                            Spacer()
                            Label(telemetry?.homeLocationSet == true ? "Home point saved" : "No home point",
                                  systemImage: "house")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(GSPalette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                inspectorPanel
                    .frame(width: 294)
            }
            .padding(14)
        }
        .background(GSPalette.background)
        .confirmationDialog(
            "Confirm \(titleFor(confirmAction))?",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }),
            titleVisibility: .visible) {
                if let action = confirmAction {
                    Button("Confirm \(titleFor(action))", role: .destructive) {
                        client.send(action)
                        confirmAction = nil
                    }
                }
                Button("Cancel", role: .cancel) { confirmAction = nil }
            } message: {
                Text("The aircraft requires an established link, operator control and physical RC backup.")
            }
    }

    private var fpv: some View {
        GSPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("LIVE CAMERA", systemImage: "video")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    GSStatusChip(label: video.framesDisplayed > 0 ? "LIVE H.264" : "WAITING",
                                 kind: video.framesDisplayed > 0 ? .good : .caution)
                    Text("\(video.framesPerSecond) FPS")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(GSPalette.cyan)
                }
                ZStack {
                    H264LiveVideoView(display: video.display)
                        .frame(height: cameraFocusMode ? 480 : 360)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if video.framesDisplayed > 0 {
                        VisionVideoOverlay(vision: video.vision,
                                           client: client,
                                           manualLabel: manualTrackingLabel)
                            .frame(height: cameraFocusMode ? 480 : 360)
                    }
                    if video.framesDisplayed == 0 {
                        VStack(spacing: 9) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 33))
                            Text("Camera feed unavailable")
                                .font(.headline)
                            Text(video.streamStatus)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                            Text("Aircraft must be linked through iPhone bridge")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.8))
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Text(telemetry?.aircraftModel ?? "MAVIC PRO · NO AIRCRAFT")
                            Spacer()
                            Text("DEV PREVIEW · NOT CERTIFIED FOR PILOTING")
                                .foregroundStyle(GSPalette.amber)
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(9)
                        .background(.black.opacity(0.70))
                    }
                }
                HStack(spacing: 9) {
                    Button { client.send(.takePhoto) } label: {
                        Label("Capture photo", systemImage: "camera")
                    }
                    Button { client.send(.startRecording) } label: {
                        Label("Record", systemImage: "record.circle")
                    }
                    Button { client.send(.stopRecording) } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    Spacer()
                    Text("LIVE · PORT 8766")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(GSPalette.muted)
                }
                .disabled(!connectedAircraft || client.pairingCode.isEmpty)
                .controlSize(.small)
            }
        }
    }

    private var mapPanel: some View {
        GSPanel {
            VStack(spacing: 10) {
                HStack {
                    Label("LIVE MAP", systemImage: "map")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Toggle("Satellite", isOn: $satellite)
                        .font(.system(size: 10))
                        .toggleStyle(.checkbox)
                    Toggle("Follow", isOn: $followAircraft)
                        .font(.system(size: 10))
                        .toggleStyle(.checkbox)
                }
                GroundStationMap(
                    aircraft: aircraftCoordinate,
                    home: homeCoordinate,
                    route: missions.selectedRoute?.waypoints ?? [],
                    flightTrack: track,
                    satellite: satellite,
                    followAircraft: followAircraft)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Image(systemName: "location.circle")
                        .foregroundStyle(GSPalette.cyan)
                    Text(telemetry?.locationText ?? "Aircraft position unavailable")
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Text("MAPKIT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GSPalette.muted)
                }
            }
        }
    }

    private var aircraftCoordinate: CLLocationCoordinate2D? {
        guard connectedAircraft,
              let lat = telemetry?.latitude,
              let lon = telemetry?.longitude else { return nil }
        let result = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(result) ? result : nil
    }

    private var homeCoordinate: CLLocationCoordinate2D? {
        guard connectedAircraft,
              telemetry?.homeLocationSet == true,
              let lat = telemetry?.homeLatitude,
              let lon = telemetry?.homeLongitude else { return nil }
        let result = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(result) ? result : nil
    }

    private var liveInstruments: some View {
        GSPanel("Flight instruments", icon: "gauge.with.dots.needle.50percent") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                      alignment: .leading, spacing: 12) {
                GSReadout(label: "Battery", value: telemetry?.batteryText ?? "—",
                          symbol: "battery.75percent",
                          tint: (telemetry?.batteryPercent ?? 100) < 30 ?
                              GSPalette.amber : GSPalette.green)
                GSReadout(label: "Altitude", value: telemetry?.altitudeText ?? "—",
                          symbol: "arrow.up.to.line")
                GSReadout(label: "Ground speed", value: telemetry?.speedText ?? "—",
                          symbol: "speedometer")
                GSReadout(label: "GPS sats",
                          value: telemetry?.satelliteCount.map(String.init) ?? "—",
                          symbol: "location.north.circle")
                GSReadout(label: "Yaw / heading",
                          value: telemetry?.yawDegrees.map {
                              String(format: "%.0f°", $0)
                          } ?? "—", symbol: "safari")
                GSReadout(label: "Flight time",
                          value: telemetry?.flightTimeSeconds.map {
                              "\($0 / 60)m \($0 % 60)s"
                          } ?? "—", symbol: "clock")
            }
        }
    }

    private var inspectorPanel: some View {
        VStack(spacing: 12) {
            GSPanel {
                VStack(spacing: 12) {
                    HStack {
                        Label("OPERATOR CONTROLS", systemImage: "gamecontroller")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                    }
                    Picker("Control panel", selection: $inspector) {
                        ForEach(ControlTab.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch inspector {
                    case .flight: flightPanel
                    case .camera: cameraPanel
                    case .aircraft: aircraftPanel
                    case .vision:
                        VisionControlPanel(vision: video.vision,
                                           client: client,
                                           manualLabel: $manualTrackingLabel)
                    }
                }
            }
            GSPanel("Current route", icon: "point.topleft.down.curvedto.point.bottomright.up") {
                VStack(alignment: .leading, spacing: 7) {
                    Text(missions.selectedRoute?.name ?? "No mission selected")
                        .font(.system(size: 13, weight: .semibold))
                    HStack {
                        Text("\(missions.selectedRoute?.waypoints.count ?? 0) waypoints")
                        Spacer()
                        GSStatusChip(label: "DRAFT ONLY", kind: .caution)
                    }
                    .font(.caption)
                    .foregroundStyle(GSPalette.muted)
                    Text("Planned routes are saved locally. Upload and execution are not implemented.")
                        .font(.system(size: 10))
                        .foregroundStyle(GSPalette.muted)
                }
            }
        }
    }

    private var flightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GSStatusChip(label: "FLIGHT ACTUATION LOCKED", kind: .caution)
            Text("WASD keyboard piloting")
                .font(.system(size: 13, weight: .semibold))
            Toggle("Capture keyboard in cockpit", isOn: $keyboard.keyboardEnabled)
                .font(.system(size: 11))
            keyboardDiagram
            Text("Hold SPACE + direction. Esc or leaving the app releases input.")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.muted)
            Text(keyboard.status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(GSPalette.cyan)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(GSPalette.border)
            HStack {
                Button("Enable sticks") { client.send(.enableSticks) }
                    .disabled(!client.flightReady)
                Button("Release") {
                    client.stopSticks()
                    client.send(.disableSticks)
                    keyboard.releaseAll()
                }
                .disabled(!client.connected)
            }
            .controlSize(.small)
            Text("Aircraft actions")
                .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                operationButton("Arm", systemImage: "lock.open", action: .armFlight)
                operationButton("Take off", systemImage: "arrow.up.circle", action: .takeoff)
                operationButton("Land", systemImage: "arrow.down.circle", action: .land)
                operationButton("Return home", systemImage: "house", action: .returnHome)
            }
            Text("Controls are deliberately disabled until encryption, simulator tests and physical failsafe checks pass.")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.amber)
        }
    }

    private var keyboardDiagram: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                GSKeyCap(text: "Q", active: key("q"))
                GSKeyCap(text: "W", active: key("w"))
                GSKeyCap(text: "E", active: key("e"))
            }
            HStack(spacing: 5) {
                GSKeyCap(text: "A", active: key("a"))
                GSKeyCap(text: "S", active: key("s"))
                GSKeyCap(text: "D", active: key("d"))
            }
            HStack(spacing: 5) {
                GSKeyCap(text: "Z", active: key("z"))
                GSKeyCap(text: "C", active: key("c"))
                GSKeyCap(text: "SPACE", active: keyboard.deadmanHeld, wide: true)
            }
            HStack {
                Text("WASD move")
                Spacer()
                Text("QE yaw")
                Spacer()
                Text("C up · Z down")
            }
            .font(.system(size: 9))
            .foregroundStyle(GSPalette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func key(_ name: String) -> Bool { keyboard.keysDown.contains(name) }

    private func operationButton(_ text: String, systemImage: String,
                                 action: GroundStationCommand.Action) -> some View {
        Button {
            confirmAction = action
        } label: {
            Label(text, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .disabled(!client.flightReady)
        .controlSize(.small)
    }

    private var cameraPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Camera and payload").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 7) {
                Button("Photo") { client.send(.takePhoto) }
                Button("REC") { client.send(.startRecording) }
                Button("Stop") { client.send(.stopRecording) }
            }
            .controlSize(.small)
            .disabled(!connectedAircraft || client.pairingCode.isEmpty)
            Divider().overlay(GSPalette.border)
            Text("Gimbal pitch").font(.system(size: 11))
            HStack {
                Slider(value: $gimbalPitch, in: -90...0, step: 5)
                Text("\(Int(gimbalPitch))°")
                    .font(.caption.monospaced())
                    .frame(width: 37)
            }
            HStack {
                Button("Level") { client.send(.gimbalPitch, value: 0) }
                Button("Down") { client.send(.gimbalPitch, value: -90) }
                Button("Apply") { client.send(.gimbalPitch, value: gimbalPitch) }
            }
            .controlSize(.small)
            .disabled(!connectedAircraft || client.pairingCode.isEmpty)
            Text("Additional zoom/exposure controls depend on Mavic Pro camera SDK support.")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.muted)
        }
    }

    private var aircraftPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow("Aircraft", connectedAircraft ? "Linked" : "Not linked")
            statusRow("RC", telemetry?.controllerConnected == true ? "Connected" : "Offline")
            statusRow("Motors", bool(telemetry?.motorsOn, on: "On", off: "Off"))
            statusRow("Flying", bool(telemetry?.isFlying, on: "Yes", off: "No"))
            statusRow("IMU preheat", bool(telemetry?.imuPreheating, on: "Yes", off: "No"))
            statusRow("Home point", bool(telemetry?.homeLocationSet, on: "Set", off: "Unset"))
            statusRow("Pitch", angle(telemetry?.pitchDegrees))
            statusRow("Roll", angle(telemetry?.rollDegrees))
            statusRow("Yaw", angle(telemetry?.yawDegrees))
            Text(telemetry?.connectionState ?? "Waiting for SDK state")
                .font(.system(size: 10))
                .foregroundStyle(GSPalette.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(GSPalette.muted)
            Spacer()
            Text(value).foregroundStyle(.white)
        }
        .font(.system(size: 11))
    }
    private func bool(_ value: Bool?, on: String, off: String) -> String {
        value.map { $0 ? on : off } ?? "—"
    }
    private func angle(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0) } ?? "—"
    }
    private func titleFor(_ action: GroundStationCommand.Action?) -> String {
        switch action {
        case .armFlight: return "arm flight"
        case .takeoff: return "takeoff"
        case .land: return "landing"
        case .returnHome: return "return home"
        default: return "flight action"
        }
    }
}
