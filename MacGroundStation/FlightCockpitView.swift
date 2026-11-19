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

    @State private var activeTool: CockpitTool = .vision
    @State private var showToolPanel = false
    @State private var gimbalPitch = -30.0
    @State private var manualTrackingLabel = "Vehicle / object"

    private let line = Color.white.opacity(0.12)
    private let green = Color(red: 0.23, green: 0.89, blue: 0.70)
    private let amber = Color(red: 1.0, green: 0.72, blue: 0.33)
    private let console = Color(red: 0.061, green: 0.069, blue: 0.081)

    enum CockpitTool: String, CaseIterable {
        case vision = "AI Tracking"
        case camera = "Camera"
        case aircraft = "Aircraft"
        case flight = "Control"
    }

    private var telemetry: GroundStationMessage.Payload? { client.latestStatus?.payload }
    private var aircraftLinked: Bool { telemetry?.validAircraft == true }

    var body: some View {
        GeometryReader { geometry in
            let stripHeight: CGFloat = 170
            let mapWidth = max(325, geometry.size.width * 0.35)
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    mapPane
                        .frame(width: mapWidth)
                    cameraPane
                        .frame(maxWidth: .infinity)
                }
                .frame(height: max(325, geometry.size.height - stripHeight))
                Rectangle().fill(line).frame(height: 1)
                flightDeck
                    .frame(height: stripHeight - 1)
            }
        }
        .background(console)
    }

    // MARK: Full-height satellite map
    private var mapPane: some View {
        ZStack(alignment: .topLeading) {
            GroundStationMap(
                aircraft: aircraftCoordinate,
                home: homeCoordinate,
                route: missions.selectedRoute?.waypoints ?? [],
                flightTrack: track,
                satellite: satellite,
                followAircraft: followAircraft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(green)
                    Text("MAP")
                        .tracking(1)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text(satellite ? "SATELLITE" : "STANDARD")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(.black.opacity(0.79))

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        mapTag("AIRCRAFT", aircraftLinked ?
                               (telemetry?.aircraftModel ?? "CONNECTED") : "NO AIRCRAFT FIX",
                               icon: "airplane")
                        if let route = missions.selectedRoute {
                            mapTag("PLANNED", "\(route.waypoints.count) WAYPOINTS",
                                   icon: "point.topleft.down.curvedto.point.bottomright.up")
                        }
                    }
                    Spacer()
                    VStack(spacing: 5) {
                        mapControl("square.3.layers.3d", help: "Toggle satellite map") {
                            satellite.toggle()
                        }
                        mapControl("location.north.line", help: "Follow aircraft position") {
                            followAircraft.toggle()
                        }
                        mapControl("arrow.triangle.2.circlepath", help: "Reset flight trail") {
                            // A refresh-friendly map control: retain the real trail.
                            followAircraft = true
                        }
                    }
                }
                .padding(11)
                Spacer()
                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(green)
                    Text(telemetry?.locationText ?? "AIRCRAFT POSITION UNAVAILABLE")
                        .lineLimit(1)
                    Spacer()
                    Text("WGS84")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(.black.opacity(0.77))
            }
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
        .help(help)
    }

    // MARK: Immersive video (no card, no dead space)
    private var cameraPane: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
            H264LiveVideoView(display: video.display)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if video.framesDisplayed > 0 {
                VisionVideoOverlay(vision: video.vision,
                                   client: client,
                                   manualLabel: manualTrackingLabel)
            }
            if video.framesDisplayed == 0 {
                VStack(spacing: 11) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("NO LIVE VIDEO")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                    Text(video.streamStatus)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 390)
                    Text("Connect the iPhone bridge and link the aircraft")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.40))
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
                    Text(video.framesDisplayed > 0 ? "\(video.framesPerSecond) FPS" : "NO SIGNAL")
                        .foregroundStyle(video.framesDisplayed > 0 ? green : amber)
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
                HStack {
                    Label(video.vision.selectedBounds == nil ?
                          "VIDEO MONITOR" : "LOCAL TARGET SELECTED",
                          systemImage: "viewfinder")
                        .foregroundStyle(video.vision.selectedBounds == nil ? .white : green)
                    Spacer()
                    Text("DEVELOPMENT PREVIEW · NOT FOR PILOTING")
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
                        .background(Color(red: 0.105, green: 0.118, blue: 0.135))
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
        VStack(alignment: .leading, spacing: 13) {
            Label("FLIGHT ACTUATION LOCKED", systemImage: "lock.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(amber)
            Text("Keyboard input is available for preview. Flight commands remain disabled until authenticated transport, latency and failsafe testing are complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Keyboard preview", isOn: $keyboard.keyboardEnabled)
            Text("HOLD SPACE + W/A/S/D • Q/E • C/Z")
                .font(.system(size: 10, design: .monospaced))
            Text(keyboard.status)
                .font(.caption)
                .foregroundStyle(green)
            Divider()
            HStack {
                Button("Takeoff") {}
                Button("Land") {}
                Button("RTH") {}
            }
            .disabled(true)
            .controlSize(.small)
            Text("Original DJI remote controller is the required manual fallback.")
                .font(.caption).foregroundStyle(.secondary)
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
    private var aircraftCoordinate: CLLocationCoordinate2D? {
        guard aircraftLinked, let lat = telemetry?.latitude,
              let lon = telemetry?.longitude else { return nil }
        let p = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(p) ? p : nil
    }
    private var homeCoordinate: CLLocationCoordinate2D? {
        guard aircraftLinked, telemetry?.homeLocationSet == true,
              let lat = telemetry?.homeLatitude, let lon = telemetry?.homeLongitude else { return nil }
        let p = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CLLocationCoordinate2DIsValid(p) ? p : nil
    }

    // MARK: FlightHub-style OSD and keyboard ribbon
    private var flightDeck: some View {
        HStack(spacing: 0) {
            batteryDeck
                .frame(width: 139)
            deckDivider
            instrumentGauge
                .frame(width: 156)
            deckDivider
            performanceDeck
                .frame(maxWidth: .infinity)
            deckDivider
            keyboardDeck
                .frame(width: 248)
            deckDivider
            flightActionDeck
                .frame(width: 245)
        }
        .background(console)
    }
    private var deckDivider: some View {
        Rectangle().fill(line).frame(width: 1)
            .padding(.vertical, 15)
    }

    private var batteryDeck: some View {
        VStack(alignment: .leading, spacing: 8) {
            deckLabel("AIRCRAFT")
            Text(telemetry?.batteryText ?? "—")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .foregroundStyle(telemetry?.batteryPercent == nil ? .white : green)
                .monospacedDigit()
            HStack(spacing: 6) {
                Image(systemName: "battery.75percent")
                Text("BATTERY")
            }
            .foregroundStyle(.white.opacity(0.5))
            .font(.system(size: 9, design: .monospaced))
            Divider().overlay(line)
            HStack {
                Text("GPS")
                Spacer()
                Text(telemetry?.satelliteCount.map { "\($0) SAT" } ?? "—")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.65))
            Spacer(minLength: 0)
        }
        .padding(12)
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
                Image(systemName: "location.north.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(green)
                    .rotationEffect(.degrees(telemetry?.yawDegrees ?? 0))
                Text(telemetry?.yawDegrees.map { String(format: "%03.0f°", $0) } ?? "—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .offset(y: 36)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private var performanceDeck: some View {
        VStack(alignment: .leading, spacing: 12) {
            deckLabel("FLIGHT INSTRUMENTS")
            HStack(spacing: 18) {
                performance("H. ALT", telemetry?.altitudeText ?? "—", icon: "arrow.up.to.line")
                performance("H. SPEED", telemetry?.speedText ?? "—", icon: "speedometer")
                performance("V. SPEED", telemetry?.velocityZ.map {
                    String(format: "%.1f m/s", $0)
                } ?? "—", icon: "arrow.up.arrow.down")
            }
            Divider().overlay(line)
            HStack(spacing: 12) {
                Label(telemetry?.flightMode ?? "FLIGHT MODE —", systemImage: "airplane")
                Spacer(minLength: 0)
                Label(telemetry?.flightTimeSeconds.map {
                    String(format: "%02d:%02d", $0 / 60, $0 % 60)
                } ?? "--:--", systemImage: "clock")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.64))
            Spacer(minLength: 0)
        }
        .padding(12)
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
    private var keyboardDeck: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                deckLabel("KEYBOARD")
                Spacer()
                Toggle("", isOn: $keyboard.keyboardEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .help("Preview keyboard controls (does not move the drone)")
            }
            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        keyCap("Q"); keyCap("W"); keyCap("E")
                    }
                    HStack(spacing: 3) {
                        keyCap("A"); keyCap("S"); keyCap("D")
                    }
                    HStack(spacing: 3) {
                        keyCap("Z"); keyCap("C")
                        keyCap("SPACE", wide: true)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("WASD  MOVE")
                    Text("Q/E  YAW")
                    Text("C/Z  ALT")
                    Text("SPACE  HOLD")
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            }
            Text(keyboard.status)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(amber)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(11)
    }

    private func keyCap(_ title: String, wide: Bool = false) -> some View {
        let active = keyboard.keysDown.contains(title == "SPACE" ? "space" : title.lowercased())
        return Text(title)
            .font(.system(size: title == "SPACE" ? 7 : 10, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? .black : .white.opacity(0.8))
            .frame(width: wide ? 42 : 26, height: 22)
            .background(active ? green : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var flightActionDeck: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                deckLabel("FLIGHT OPERATIONS")
                Spacer()
                Image(systemName: "lock.shield")
                    .foregroundStyle(amber)
            }
            HStack(spacing: 5) {
                flightButton("TAKEOFF", icon: "arrow.up")
                flightButton("LAND", icon: "arrow.down")
                flightButton("RTH", icon: "house.fill")
            }
            HStack {
                Circle().fill(amber).frame(width: 6, height: 6)
                Text("ACTUATION LOCKED")
                    .foregroundStyle(amber)
                Spacer()
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text("Safe UI preview only. Physical RC required.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func flightButton(_ title: String, icon: String) -> some View {
        Button {} label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.bordered)
        .disabled(true)
        .help("Flight actuation locked pending safety and link testing")
    }
    private func deckLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.50))
    }
}
