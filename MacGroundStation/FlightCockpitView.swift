import CoreLocation
import MapKit
import SwiftUI

/// FlightHub-inspired spatial arrangement, built entirely with native SwiftUI
/// and MapKit. Main camera and satellite map have uninterrupted surfaces;
/// secondary tools are contextual overlays rather than permanent dashboard cards.
struct FlightCockpitView: View {
    @ObservedObject var client: BridgeClient
    @ObservedObject var video: H264LiveVideoClient
    @ObservedObject var keyboard: KeyboardPilotController
    @ObservedObject var missions: MissionLibrary
    @Binding var satellite: Bool
    @Binding var followAircraft: Bool
    let track: [CLLocationCoordinate2D]
    let status: ProjectStatus
    let now: Date
    let openConnection: () -> Void
    @State private var showKeyboard = false
    @State private var simulatorSetup = false

    @State private var activeTool: CockpitTool = .aircraft
    @State private var showToolPanel = false
    @State private var mapFocused = false
    @State private var gimbalPitch = -30.0
    @State private var manualTrackingLabel = "Vehicle / object"
    @State private var actionToConfirm: GroundStationCommand.Action?
    @State private var liveClearArea = false
    @State private var livePilotAtRC = false
    @State private var liveVLOSAndRegulations = false
    @State private var liveFailsafeReviewed = false
    @State private var liveConfirmPhrase = ""

    private var liveChecklistReady: Bool {
        liveClearArea && livePilotAtRC && liveVLOSAndRegulations &&
        liveFailsafeReviewed &&
        liveConfirmPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "ENABLE LIVE FLIGHT" &&
        client.livePreflightReady
    }

    private let line = Color.white.opacity(0.12)
    private let green = GSPalette.green
    private let amber = Color(red: 1.0, green: 0.72, blue: 0.33)
    private let console = GSPalette.background

    enum CockpitTool: String, CaseIterable {
        case vision = "AI Tracking"
        case camera = "Camera"
        case aircraft = "Aircraft"
        case flight = "Control"
    }

    private var telemetry: GroundStationMessage.Payload? { status.hasAircraftData ? client.latestStatus?.payload : nil }
    private var staleVideo: Bool { video.lastVideoAt.map { now.timeIntervalSince($0) > 3 } ?? false }
    private var lastAirborne: Bool {
        client.latestStatus?.payload.validAircraft == true && client.latestStatus?.payload.isFlying == true
    }
    private var aircraftLinked: Bool { telemetry?.validAircraft == true }

    var body: some View {
        GeometryReader { geometry in
            let width = max(280, geometry.size.width * (mapFocused ? 0.46 : 0.32))
            HStack(spacing: 2) {
                VStack(spacing: 2) {
                    PilotStation(client: client, keyboard: keyboard, status: status, showGuide: $showKeyboard,
                                 openConnection: openConnection, openSetup: openFlightSetup,
                                 confirmTakeoff: { confirm(.takeoff) })
                        .frame(height: min(geometry.size.height * 0.58,
                                           showKeyboard ? 274 : (mapFocused ? 148 : 168)))
                    mapPane
                }
                .frame(width: width)
                cameraPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(console)
        .onChange(of: client.connected) { connected in
            if !connected {
                actionToConfirm = nil
                resetChecklist()
            }
        }
        .onChange(of: client.djiSimulatorActive) { _ in
            actionToConfirm = nil
            resetChecklist()
        }
        .confirmationDialog(
            (client.djiSimulatorActive || actionToConfirm == .startDJISimulator) ?
                "Confirm DJI Simulator command" : "Confirm REAL aircraft command",
            isPresented: Binding(
                get: { actionToConfirm != nil },
                set: { if !$0 { actionToConfirm = nil } }),
            titleVisibility: .visible
        ) {
            if let action = actionToConfirm {
                Button(confirmTitle(action)) {
                    guard client.connected, action != .authorizeLiveFlight || liveChecklistReady else { return }
                    if action == .takeoff {
                        guard client.flightReady, client.flightArmed, telemetry?.isFlying == false else { return }
                    }
                    if action == .land || action == .returnHome ||
                       action == .stopDJISimulator || action == .revokeLiveFlight {
                        keyboard.stop()
                        client.releaseVirtualSticks()
                    }
                    if action == .revokeLiveFlight {
                        client.revokeLiveFlight()
                    } else {
                        client.send(action)
                    }
                    if action == .authorizeLiveFlight {
                        resetChecklist()
                    }
                    actionToConfirm = nil
                }
            }
            Button("Cancel", role: .cancel) { actionToConfirm = nil }
        } message: {
            Text((client.djiSimulatorActive || actionToConfirm == .startDJISimulator)
                 ? "Keep the remote linked and remove the propellers for the DJI simulator."
                 : "REAL AIRCRAFT: motors and propellers may start. Ensure a clear outdoor flight area, legal visual line of sight, and a pilot holding the physical DJI remote controller. Cancel if unsure.")
        }
    }

    private func resetChecklist() {
        liveConfirmPhrase = ""
        liveClearArea = false
        livePilotAtRC = false
        liveVLOSAndRegulations = false
        liveFailsafeReviewed = false
    }

    private func openFlightSetup() {
        keyboard.stop()
        activeTool = .flight
        showToolPanel = true
    }

    private func confirm(_ action: GroundStationCommand.Action) {
        keyboard.stop()
        actionToConfirm = action
    }

    private var mapPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Label("Map", systemImage: "map")
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { mapFocused.toggle() }
                } label: {
                    Label(mapFocused ? "Camera focus" : "Map focus", systemImage: "rectangle.split.2x1")
                }
                .buttonStyle(.plain).foregroundStyle(GSPalette.cyan)
                Text(satellite ? "Satellite" : "Standard").foregroundStyle(GSPalette.muted)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10).frame(height: 30).background(GSPalette.side)

            GroundStationMap(aircraft: aircraftCoordinate, home: homeCoordinate,
                             route: missions.selectedRoute?.waypoints ?? [], flightTrack: track,
                             satellite: satellite, followAircraft: followAircraft)
                .overlay(alignment: .topTrailing) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            if let model = telemetry?.aircraftModel {
                                mapTag("AIRCRAFT", model, icon: "airplane")
                            }
                            if let route = missions.selectedRoute {
                                mapTag("PLANNED", route.waypointCountLabel.uppercased(),
                                       icon: "point.topleft.down.curvedto.point.bottomright.up")
                            }
                        }
                        Spacer()
                        VStack(spacing: 4) {
                            mapControl("square.3.layers.3d", help: "Toggle satellite map") { satellite.toggle() }
                            mapControl(followAircraft ? "location.fill" : "location",
                                       help: followAircraft ? "Stop following aircraft" : "Follow aircraft") {
                                followAircraft.toggle()
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.top, 40)
                }

            HStack(spacing: 6) {
                Image(systemName: "location").foregroundStyle(GSPalette.muted)
                Text(telemetry?.locationText ?? "Position unavailable").lineLimit(1)
                Spacer()
                Text("WGS84").foregroundStyle(GSPalette.muted)
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 10).frame(height: 23).background(GSPalette.side)
        }
        .clipped()
    }

    private func mapTag(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(green)
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text(value).lineLimit(1)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(.black.opacity(0.71))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func mapControl(_ symbol: String, help: String,
                            perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 31, height: 32)
                .background(.black.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .help(help)
    }

    // MARK: Immersive video (no card, no dead space)
    private var cameraPane: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            H264LiveVideoView(display: video.display)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if video.framesDisplayed > 0 && !staleVideo {
                VisionVideoOverlay(vision: video.vision,
                                   client: client,
                                   manualLabel: manualTrackingLabel)
            }
            if staleVideo { Color.black.opacity(0.77).allowsHitTesting(false) }
            if video.framesDisplayed == 0 || staleVideo {
                VStack(spacing: 11) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(staleVideo ? "Video paused" : "No live video")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                    Text(staleVideo ? "Waiting for a new camera frame" : video.streamStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 390)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            // Camera OSD: true link/feed state. No fake signal or exposure values.
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    Label("WIDE", systemImage: "camera")
                        .foregroundStyle(.white)
                    Rectangle().fill(.white.opacity(0.28)).frame(width: 1, height: 13)
                    Text("H.264")
                    Text(staleVideo ? "STALE" : (video.framesDisplayed > 0 ? "\(video.framesPerSecond) FPS" : "NO SIGNAL"))
                        .foregroundStyle(video.framesDisplayed > 0 && !staleVideo ? green : amber)
                    if video.vision.enabled {
                        Text("AI")
                            .foregroundStyle(green)
                    }
                    Spacer()
                    Text(aircraftLinked ? "AIRCRAFT CONNECTED" : "RC / AIRCRAFT LINK REQUIRED")
                        .foregroundStyle(aircraftLinked ? green : amber)
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(.black.opacity(0.80))
                .allowsHitTesting(false)

                HStack(alignment: .top) {
                    Spacer()
                    toolRail
                        .padding(.top, 13)
                        .padding(.trailing, 11)
                }
                Spacer(minLength: 0)
                if !showToolPanel { cameraInstruments }
                HStack {
                    Label(video.vision.selectedBounds == nil ?
                          "VIDEO MONITOR" : "LOCAL TARGET SELECTED",
                          systemImage: "viewfinder")
                        .foregroundStyle(video.vision.selectedBounds == nil ? .white : green)
                    Spacer()
                    Text("Development video preview")
                        .foregroundStyle(amber)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(.black.opacity(0.76))
                .allowsHitTesting(false)
            }

            if showToolPanel {
                HStack(spacing: 0) {
                    Spacer()
                    toolInspector
                        .frame(width: 304)
                        .background(GSPalette.side)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(line).frame(width: 1)
                        }
                }
                .padding(.top, 36)
                .padding(.bottom, 30)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .clipped()
    }

    private var toolRail: some View {
        VStack(spacing: 5) {
            toolIcon("camera.viewfinder", tip: "Camera and gimbal", tool: .camera)
            toolIcon("scope", tip: "AI detection and target tracking", tool: .vision)
            toolIcon("airplane", tip: "Aircraft telemetry", tool: .aircraft)
            toolIcon("gamecontroller", tip: "Flight control status", tool: .flight)
            Rectangle().fill(.white.opacity(0.25))
                .frame(width: 25, height: 1).padding(.vertical, 4)
            Button {
                client.send(.takePhoto)
            } label: {
                Image(systemName: "camera.fill")
                    .frame(width: 35, height: 35)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.79))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!aircraftLinked || client.pairingCode.isEmpty)
            .help("Take photo on aircraft")
            Button {
                client.send(.startRecording)
            } label: {
                Image(systemName: "record.circle")
                    .foregroundStyle(.red)
                    .frame(width: 35, height: 35)
                    .background(.black.opacity(0.79))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!aircraftLinked || client.pairingCode.isEmpty)
            .help("Start recording on aircraft")
        }
    }

    private func toolIcon(_ symbol: String, tip: String, tool: CockpitTool) -> some View {
        Button {
            keyboard.stop()
            withAnimation(.easeOut(duration: 0.18)) {
                if showToolPanel && activeTool == tool {
                    showToolPanel = false
                } else {
                    activeTool = tool
                    showToolPanel = true
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(activeTool == tool && showToolPanel ? green : .white)
                .frame(width: 35, height: 35)
                .background(.black.opacity(0.79))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tip)
        .help(tip)
    }

    private var toolInspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text(activeTool.rawValue.uppercased())
                    .tracking(0.8)
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Button { withAnimation { showToolPanel = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityLabel("Close inspector")
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(Color.white.opacity(0.045))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    switch activeTool {
                    case .vision:
                        VisionControlPanel(vision: video.vision, client: client,
                                           manualLabel: $manualTrackingLabel)
                    case .camera:
                        cameraInspector
                    case .aircraft:
                        aircraftInspector
                    case .flight:
                        flightInspector
                    }
                }
                .padding(14)
            }
        }
    }

    private var cameraInspector: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("CAMERA CONTROL")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(green)
            HStack {
                Button("Photo") { client.send(.takePhoto) }
                Button("Record") { client.send(.startRecording) }
                Button("Stop") { client.send(.stopRecording) }
            }
            .controlSize(.small)
            .disabled(!aircraftLinked || client.pairingCode.isEmpty)
            Divider()
            Text("GIMBAL TILT")
                .font(.system(size: 10, weight: .bold))
            HStack {
                Slider(value: $gimbalPitch, in: -90...0, step: 5)
                Text("\(Int(gimbalPitch))°").monospacedDigit().frame(width: 38)
            }
            HStack {
                Button("Forward") { client.send(.gimbalPitch, value: 0) }
                Button("Down") { client.send(.gimbalPitch, value: -90) }
                Button("Apply") { client.send(.gimbalPitch, value: gimbalPitch) }
            }
            .controlSize(.small)
            .disabled(!aircraftLinked || client.pairingCode.isEmpty)
            Text("DJI SDK commands are sent from the Mac via the iPhone controller bridge.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aircraftInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow("Model", telemetry?.aircraftModel ?? "—")
            statusRow("Flight mode", telemetry?.flightMode ?? "—")
            statusRow("Battery", telemetry?.batteryText ?? "—")
            statusRow("Satellites", telemetry?.satelliteCount.map(String.init) ?? "—")
            statusRow("GPS", telemetry?.locationText ?? "—")
            statusRow("Motors", boolValue(telemetry?.motorsOn))
            statusRow("Airborne", boolValue(telemetry?.isFlying))
            statusRow("Home point", boolValue(telemetry?.homeLocationSet))
            statusRow("IMU heating", boolValue(telemetry?.imuPreheating))
            statusRow("Pitch", angle(telemetry?.pitchDegrees))
            statusRow("Roll", angle(telemetry?.rollDegrees))
            statusRow("Yaw", angle(telemetry?.yawDegrees))
            Text(telemetry?.connectionState ?? "No aircraft state")
                .font(.system(size: 10))
                .foregroundStyle(amber)
        }
    }

    private var flightInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(client.djiSimulatorActive ? "DJI SIMULATOR" : "REAL AIRCRAFT CONTROL",
                  systemImage: client.djiSimulatorActive ? "gamecontroller" : "airplane")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(client.djiSimulatorActive ? green : amber)

            statusRow("Flight link", client.flightKeyVerified ? "ENCRYPTED COMMANDS READY" : "PAIR FLIGHT KEY")
            statusRow("Aircraft", aircraftLinked ? (telemetry?.aircraftModel ?? "CONNECTED") : "OFFLINE")
            statusRow("Mode", client.djiSimulatorActive ? "SIMULATOR" :
                       (client.liveFlightAuthorized ? "LIVE AUTHORIZED" : "LIVE LOCKED"))
            statusRow("Virtual Sticks", client.virtualSticksEnabled ? "ENGAGED" : "RELEASED")
            statusRow("Flight", telemetry?.isFlying.map { $0 ? "AIRBORNE" : "ON GROUND" } ?? "—")

            Divider().overlay(line)

            if client.djiSimulatorActive {
                Button("Stop DJI simulator…") { confirm(.stopDJISimulator) }
                    .disabled(telemetry?.isFlying != false)
            } else if client.liveFlightAuthorized {
                liveFlightSection
            } else {
                Picker("Flight environment", selection: $simulatorSetup) {
                    Text("Live flight").tag(false)
                    Text("DJI simulator").tag(true)
                }.pickerStyle(.segmented)
                if simulatorSetup {
                    Text("The DJI simulator runs on the linked aircraft. Remove its propellers for ground testing.")
                        .font(.caption).foregroundStyle(GSPalette.muted)
                    Button("Start DJI simulator…") { confirm(.startDJISimulator) }
                        .disabled(!aircraftLinked || !client.flightKeyVerified ||
                                  telemetry?.isFlying != false || telemetry?.motorsOn != false)
                } else {
                    liveFlightSection
                }
            }
            Divider().overlay(line)
            Text("Takeoff / landing")
                .font(.system(size: 11, weight: .bold))
            HStack {
                Button("Arm (30s)") {
                    client.send(.armFlight)
                }
                .disabled(!client.flightReady || telemetry?.isFlying != false)
                Button("Take off") {
                    confirm(.takeoff)
                }
                .disabled(!client.flightReady || !client.flightArmed ||
                          telemetry?.isFlying != false)
            }
            .controlSize(.small)

            HStack {
                Button {
                    confirm(.land)
                } label: {
                    Label("Land", systemImage: "arrow.down")
                }
                .disabled(!client.connected || !client.flightKeyVerified ||
                          !lastAirborne)
                Button {
                    confirm(.returnHome)
                } label: {
                    Label("Return Home", systemImage: "house.fill")
                }
                .disabled(!client.connected || !client.flightKeyVerified ||
                          !lastAirborne || client.latestStatus?.payload.homeLocationSet != true)
            }
            .controlSize(.small)

            Divider().overlay(line)
            Button("Show keyboard guide") {
                keyboard.stop()
                showToolPanel = false
                showKeyboard = true
            }
            Text(client.lastControlResult)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(amber)
                .fixedSize(horizontal: false, vertical: true)
            Text("If the Mac/iPhone link fails, the iPhone stops Virtual Stick input. Always keep the physical remote controller in hand.")
                .font(.system(size: 10))
                .foregroundStyle(amber)
                .fixedSize(horizontal: false, vertical: true)
        }

    }

    private var liveFlightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LIVE FLIGHT AUTHORIZATION", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text(client.liveFlightAuthorized ? "APPROVED" : "LOCKED")
                    .foregroundStyle(client.liveFlightAuthorized ? green : amber)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
            }
            Text("This mode commands real motors. Authorization expires after 15 minutes and is revoked on link loss.")
                .font(.system(size: 10))
                .foregroundStyle(amber)
                .fixedSize(horizontal: false, vertical: true)

            if client.liveFlightAuthorized {
                Button(role: .destructive) {
                    confirm(.revokeLiveFlight)
                } label: {
                    Label("Revoke live controls", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
            } else {
                Toggle("Clear outdoor launch / landing area", isOn: $liveClearArea)
                Toggle("Pilot holding linked DJI remote controller", isOn: $livePilotAtRC)
                Toggle("Visual line of sight and clear of bystanders", isOn: $liveVLOSAndRegulations)
                Toggle("RTH height, home point and failsafe checked", isOn: $liveFailsafeReviewed)
                Text("Type ENABLE LIVE FLIGHT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                TextField("ENABLE LIVE FLIGHT", text: $liveConfirmPhrase)
                    .textFieldStyle(.roundedBorder)
                Button {
                    confirm(.authorizeLiveFlight)
                } label: {
                    Label("Authorize real aircraft (15m)", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!liveChecklistReady)
                .controlSize(.small)
            }
            if !client.livePreflightReady && !client.liveFlightAuthorized {
                ForEach(client.livePreflightChecks) { check in
                    HStack(spacing: 6) {
                        Image(systemName: check.passed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(check.passed ? green : amber)
                        Text(check.label)
                        Spacer()
                        Text(check.value).foregroundStyle(GSPalette.muted)
                    }.font(.system(size: 11))
                }
            }
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.54))
            Spacer()
            Text(value).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
    }
    private func boolValue(_ value: Bool?) -> String {
        value.map { $0 ? "YES" : "NO" } ?? "—"
    }
    private func angle(_ value: Double?) -> String {
        value.map { String(format: "%.1f°", $0) } ?? "—"
    }
    private var aircraftCoordinate: CLLocationCoordinate2D? { telemetry?.aircraftPoint }
    private var homeCoordinate: CLLocationCoordinate2D? { telemetry?.homePoint }

    private var cameraInstruments: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                instrumentGauge.frame(width: 130, height: 145)
                    .background(.black.opacity(0.44))
                Spacer()

            }
            .padding(.horizontal, 12)
            HStack(spacing: 10) {
                performance("ALT", telemetry?.altitudeText ?? "—", icon: "arrow.up.to.line")
                performance("SPEED", telemetry?.speedText ?? "—", icon: "speedometer")
                performance("V. SPEED", telemetry?.velocityZ.map { String(format: "%.1f m/s", $0) } ?? "—", icon: "arrow.up.arrow.down")
                performance("BATTERY", telemetry?.batteryText ?? "—", icon: "battery.75percent")
                Button("Flight controls", action: openFlightSetup)
                .controlSize(.small)
            }
            .padding(10).background(.black.opacity(0.80))
        }
    }

    private var instrumentGauge: some View {
        VStack(spacing: 4) {
            deckLabel("ORIENTATION")
            ZStack {
                Circle()
                    .stroke(line, lineWidth: 1)
                    .frame(width: 111, height: 111)
                Circle()
                    .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 3, dash: [2, 7]))
                    .frame(width: 91, height: 91)
                ForEach(0..<12, id: \.self) { i in
                    Rectangle()
                        .fill(i % 3 == 0 ? .white.opacity(0.65) : .white.opacity(0.25))
                        .frame(width: 1.5, height: i % 3 == 0 ? 9 : 4)
                        .offset(y: -54)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                Text("N")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(amber)
                    .offset(y: -40)
                if let heading = telemetry?.yawDegrees {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 26, weight: .medium)).foregroundStyle(green)
                        .rotationEffect(.degrees(heading))
                }
                Text(telemetry?.yawDegrees.map { String(format: "%03.0f°", $0) } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .offset(y: 36)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private func performance(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(green)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func confirmTitle(_ action: GroundStationCommand.Action) -> String {
        switch action {
        case .startDJISimulator: return "Start DJI Simulator"
        case .stopDJISimulator: return "Stop DJI Simulator"
        case .takeoff: return client.djiSimulatorActive ?
            "Confirm simulated takeoff" : "CONFIRM REAL TAKEOFF — MOTORS WILL START"
        case .land: return client.djiSimulatorActive ?
            "Confirm simulated landing" : "Confirm REAL landing"
        case .returnHome: return "Confirm Return to Home"
        case .authorizeLiveFlight: return "Authorize live motor controls"
        case .revokeLiveFlight: return "Revoke live flight authorization"
        default: return "Confirm command"
        }
    }

    private func deckLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.50))
    }
}
