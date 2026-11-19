import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var client = BridgeClient()
    @StateObject private var liveVideo = H264LiveVideoClient()
    @State private var host = "192.168.1.100"
    @State private var pitch = -30.0
    @State private var actionToConfirm: GroundStationCommand.Action?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55.95, longitude: -3.19),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))

    private var telemetry: GroundStationMessage.Payload? { client.latestStatus?.payload }
    private var aircraft: Bool { telemetry?.aircraftConnected == true }
    private var flying: Bool { telemetry?.isFlying == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                connectionRow
                HStack(alignment: .top, spacing: 14) {
                    videoPanel.frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        telemetryPanel
                        locationPanel
                    }
                    .frame(width: 330)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        cameraPanel
                        gimbalPanel
                    }
                    .frame(width: 330)
                    flightPanel
                        .frame(maxWidth: .infinity)
                }
                logPanel
                Text("EXPERIMENTAL: flight actions remain disabled. The live H.264 camera preview is for bench monitoring only, not a validated low-latency piloting link.")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
            .padding(18)
        }
        .background(Color(red: 0.055, green: 0.07, blue: 0.10))
        .confirmationDialog(
            "Confirm \(titleFor(actionToConfirm))",
            isPresented: Binding(
                get: { actionToConfirm != nil },
                set: { if !$0 { actionToConfirm = nil } }),
            titleVisibility: .visible) {
                if let action = actionToConfirm {
                    Button("Confirm \(titleFor(action))",
                           role: action == .motorsOff ? .destructive : nil) {
                        client.send(action)
                        actionToConfirm = nil
                    }
                }
                Button("Cancel", role: .cancel) { actionToConfirm = nil }
            } message: {
                Text("Operate only with a clear area, a valid DJI aircraft link, and a human ready at the physical controller.")
            }
        .onDisappear {
            liveVideo.disconnect()
            client.disconnect()
        }
        .onChange(of: client.latestStatus?.payload.latitude) { value in
            if let latitude = value, let longitude = client.latestStatus?.payload.longitude,
               CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                region.center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 38)).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text("GroundStation").font(.largeTitle.bold())
                Text("Mavic Pro · Mac operator console")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("EXPERIMENTAL", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            statusPill(aircraft ? "AIRCRAFT LINKED" : (client.connected ? "CONTROLLER ONLY / WAITING" : "OFFLINE"),
                       good: aircraft)
        }
    }

    private var connectionRow: some View {
        GroupBox("iPhone communications bridge") {
            HStack(spacing: 10) {
                TextField("iPhone Wi-Fi IP", text: $host)
                    .textFieldStyle(.roundedBorder).frame(width: 180)
                SecureField("Six-digit pairing code", text: $client.pairingCode)
                    .textFieldStyle(.roundedBorder).frame(width: 170)
                Button("Connect") {
                    client.connect(host: host, port: 8765)
                    liveVideo.connect(host: host, pairingCode: client.pairingCode)
                }
                Button("Disconnect") {
                    liveVideo.disconnect()
                    client.disconnect()
                }.disabled(!client.connected && !liveVideo.connected)
                Spacer()
                Image(systemName: "wifi").foregroundStyle(client.connected ? .green : .gray)
                Text(client.connected ? "Bridge online" : "Disconnected")
            }.padding(.vertical, 5)
        }
    }

    private var videoPanel: some View {
        GroupBox {
            ZStack {
                H264LiveVideoView(display: liveVideo.display)
                    .frame(height: 345)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                if liveVideo.framesDisplayed == 0 {
                    VStack(spacing: 9) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 34))
                        Text("Waiting for live H.264 stream")
                            .font(.headline)
                        Text(liveVideo.streamStatus)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Text("Check aircraft camera link and enter the six-digit pairing code")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.6))
                }
                VStack {
                    HStack(spacing: 8) {
                        Label("LIVE H.264", systemImage: "video")
                            .foregroundStyle(.cyan)
                        Text(liveVideo.framesDisplayed > 0 ?
                             "\(liveVideo.framesPerSecond) FPS" : "WAITING")
                            .foregroundStyle(liveVideo.framesDisplayed > 0 ? .green : .orange)
                        Spacer()
                        Text("EXPERIMENTAL · DO NOT PILOT BY VIDEO")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.bold())
                    .padding(10)
                    .background(.black.opacity(0.65))
                    Spacer()
                    HStack {
                        Spacer()
                        Text(liveVideo.streamStatus)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .padding(8)
                            .background(.black.opacity(0.7))
                    }
                }
                .padding(6)
            }
        } label: {
            Label("Continuous aircraft video (dedicated Wi-Fi channel)", systemImage: "camera")
        }
    }

    private var telemetryPanel: some View {
        GroupBox("Live aircraft telemetry") {
            VStack(alignment: .leading, spacing: 9) {
                metric("Connection", telemetry?.connectionState ?? "No data")
                Divider()
                HStack {
                    metric("Model", telemetry?.aircraftModel ?? "Not connected")
                    Spacer()
                    metric("Battery", telemetry?.batteryPercent.map { "\($0)%" } ?? "—")
                }
                HStack {
                    metric("Altitude", number(telemetry?.altitudeMeters, "m"))
                    Spacer()
                    metric("Speed", number(telemetry?.speedMetersPerSecond, "m/s"))
                    Spacer()
                    metric("Satellites", telemetry?.satelliteCount.map(String.init) ?? "—")
                }
                HStack {
                    metric("Motors", optionalState(telemetry?.motorsOn, active: "ON", inactive: "OFF"))
                    Spacer()
                    metric("Flying", optionalState(telemetry?.isFlying, active: "YES", inactive: "NO"))
                    Spacer()
                    metric("Flight mode", telemetry?.flightMode ?? "—")
                }
                HStack {
                    metric("Pitch", number(telemetry?.pitchDegrees, "°"))
                    Spacer()
                    metric("Roll", number(telemetry?.rollDegrees, "°"))
                    Spacer()
                    metric("Heading", number(telemetry?.yawDegrees, "°"))
                }
                HStack {
                    metric("Home point", optionalState(telemetry?.homeLocationSet, active: "SET", inactive: "NO"))
                    Spacer()
                    metric("IMU warming", optionalState(telemetry?.imuPreheating, active: "YES", inactive: "NO"))
                }
                Text(telemetry?.simulated == true ? "SIMULATED" : "DJI SDK")
                    .font(.caption.bold())
                    .foregroundStyle(telemetry?.simulated == true ? .orange : .green)
            }.padding(.vertical, 5)
        }
    }

    private var locationPanel: some View {
        GroupBox("GPS location") {
            VStack(alignment: .leading, spacing: 8) {
                Map(coordinateRegion: $region, annotationItems: aircraftPin) { item in
                    MapMarker(coordinate: item.coordinate, tint: .cyan)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    metric("Latitude", telemetry?.latitude.map { String(format: "%.6f", $0) } ?? "—")
                    Spacer()
                    metric("Longitude", telemetry?.longitude.map { String(format: "%.6f", $0) } ?? "—")
                }
            }
        }
    }

    private var aircraftPin: [AircraftPin] {
        guard let lat = telemetry?.latitude, let lon = telemetry?.longitude,
              aircraft else { return [] }
        return [AircraftPin(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))]
    }

    private var cameraPanel: some View {
        GroupBox("Camera commands (Mac)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        client.send(.takePhoto)
                    } label: { Label("Photo", systemImage: "camera") }
                    Button {
                        client.send(.startRecording)
                    } label: { Label("Record", systemImage: "record.circle") }
                    Button {
                        client.send(.stopRecording)
                    } label: { Label("Stop", systemImage: "stop.fill") }
                }
                .disabled(!aircraft || client.pairingCode.isEmpty)
                Text("These commands control the Mavic's camera via DJI SDK; they do not record the Mac preview.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
    }

    private var gimbalPanel: some View {
        GroupBox("Gimbal tilt (Mac)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pitch")
                    Slider(value: $pitch, in: -90...0, step: 5)
                    Text("\(Int(pitch))°").monospacedDigit().frame(width: 42)
                }
                HStack {
                    Button("Look forward") { client.send(.gimbalPitch, value: 0) }
                    Button("Look down") { client.send(.gimbalPitch, value: -90) }
                    Button("Apply") { client.send(.gimbalPitch, value: pitch) }
                }
                .disabled(!aircraft || client.pairingCode.isEmpty)
            }.padding(.vertical, 4)
        }
    }

    private var flightPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Flight operations — Mac only", systemImage: "shield.lefthalf.filled")
                        .font(.title3.bold())
                    Spacer()
                    statusPill(client.flightReady ? "PREFLIGHT READY" : "LOCKED / CHECK TELEMETRY",
                               good: client.flightReady)
                }
                Text("Confirm commands individually. Physical controller remains the emergency backup.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    actionButton("Arm 30s", icon: "lock.open", action: .armFlight,
                                 enabled: client.flightReady)
                    actionButton("Take off", icon: "arrow.up.circle", action: .takeoff,
                                 enabled: client.flightReady && !flying)
                    actionButton("Land", icon: "arrow.down.circle", action: .land,
                                 enabled: aircraft && flying)
                    actionButton("Return Home", icon: "house", action: .returnHome,
                                 enabled: aircraft && flying && telemetry?.homeLocationSet == true)
                }
                HStack {
                    actionButton("Start motors", icon: "fanblades", action: .motorsOn,
                                 enabled: client.flightReady && !flying)
                    actionButton("Stop motors (ground only)", icon: "stop.circle",
                                 action: .motorsOff, enabled: aircraft && !flying)
                    Button("Disarm") { client.send(.disarmFlight) }.disabled(!aircraft)
                }
                Divider()
                HStack {
                    Text("Virtual Stick (hold direction)").font(.headline)
                    Spacer()
                    Button("Enable") { client.send(.enableSticks) }
                        .disabled(!client.flightReady || !flying)
                    Button("Release to RC") {
                        client.stopSticks()
                        client.send(.disableSticks)
                    }.disabled(!aircraft)
                }
                HStack(alignment: .center, spacing: 22) {
                    VStack(spacing: 8) {
                        holdButton("Forward", symbol: "arrow.up", pitch: 0.6)
                        HStack {
                            holdButton("Left", symbol: "arrow.left", roll: -0.6)
                            holdButton("Right", symbol: "arrow.right", roll: 0.6)
                        }
                        holdButton("Back", symbol: "arrow.down", pitch: -0.6)
                        Text("Horizontal").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        holdButton("Rise", symbol: "arrow.up", vertical: 0.4)
                        HStack {
                            holdButton("Yaw L", symbol: "rotate.left", yaw: -12)
                            holdButton("Yaw R", symbol: "rotate.right", yaw: 12)
                        }
                        holdButton("Descend", symbol: "arrow.down", vertical: -0.4)
                        Text("Vertical / yaw").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
        } label: {
            Label("Safety-gated flight panel", systemImage: "airplane")
        }
    }

    private var logPanel: some View {
        GroupBox("Bridge and command log") {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(client.logs) { entry in
                        Text(entry.text).font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 115)
        }
    }

    private func holdButton(_ title: String, symbol: String,
                            pitch: Double = 0, roll: Double = 0,
                            yaw: Double = 0, vertical: Double = 0) -> some View {
        Button {
            // Only a press-and-hold gesture generates flight motion.
        } label: {
            Label(title, systemImage: symbol)
                .frame(minWidth: 75, minHeight: 29)
        }
        .buttonStyle(.bordered)
        .disabled(!client.flightReady || !flying)
        .onLongPressGesture(minimumDuration: 0.08,
                            pressing: { down in
                                if down {
                                    client.startSticks(pitch: pitch, roll: roll,
                                                       yaw: yaw, vertical: vertical)
                                } else {
                                    client.stopSticks()
                                }
                            }, perform: {})
    }

    private func actionButton(_ title: String, icon: String,
                              action: GroundStationCommand.Action,
                              enabled: Bool) -> some View {
        Button {
            actionToConfirm = action
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(!enabled || client.pairingCode.isEmpty)
    }

    private func statusPill(_ title: String, good: Bool) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(good ? .green : .orange)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background((good ? Color.green : Color.orange).opacity(0.12))
            .clipShape(Capsule())
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
                .lineLimit(2).minimumScaleFactor(0.7)
        }
    }

    private func number(_ n: Double?, _ unit: String) -> String {
        n.map { String(format: "%.1f", $0) + " " + unit } ?? "—"
    }

    private func optionalState(_ n: Bool?, active: String, inactive: String) -> String {
        n.map { $0 ? active : inactive } ?? "—"
    }

    private func titleFor(_ action: GroundStationCommand.Action?) -> String {
        switch action {
        case .armFlight: return "arming flight controls"
        case .takeoff: return "aircraft takeoff"
        case .land: return "landing"
        case .returnHome: return "Return to Home"
        case .motorsOn: return "starting motors"
        case .motorsOff: return "stopping motors"
        default: return "aircraft command"
        }
    }
}

private struct AircraftPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
