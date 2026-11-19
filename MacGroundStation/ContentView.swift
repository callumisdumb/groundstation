import CoreLocation
import SwiftUI

/// App navigation lives in a compact command bar rather than a permanent
/// sidebar. FlightHub's cockpit uses its real estate for video and maps.
enum GSWorkspace: String, CaseIterable, Identifiable {
    case cockpit = "Virtual Cockpit"
    case missions = "Mission Planning"
    case activity = "Activity & Logs"
    var id: Self { self }
}

struct ContentView: View {
    @StateObject private var client = BridgeClient()
    @StateObject private var liveVideo = H264LiveVideoClient()
    @StateObject private var keyboard = KeyboardPilotController()
    @StateObject private var missions = MissionLibrary()

    @State private var workspace: GSWorkspace = .cockpit
    @State private var host = UserDefaults.standard.string(forKey: "GroundStationBridgeIP") ?? ""
    @State private var satellite = true
    @State private var followAircraft = true
    @State private var track: [CLLocationCoordinate2D] = []
    @State private var showConnection = false

    private var status: GroundStationMessage.Payload? { client.latestStatus?.payload }
    private var aircraftConnected: Bool { status?.validAircraft == true }

    var body: some View {
        VStack(spacing: 0) {
            commandBar
                .frame(height: 52)
            Rectangle().fill(Color.white.opacity(0.11)).frame(height: 1)
            Group {
                switch workspace {
                case .cockpit:
                    FlightCockpitView(
                        client: client, video: liveVideo, keyboard: keyboard,
                        missions: missions, satellite: $satellite,
                        followAircraft: $followAircraft, track: track)
                case .missions:
                    MissionWorkspace(missions: missions, client: client,
                                     satellite: $satellite, track: track)
                case .activity:
                    ActivityWorkspace(client: client)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomStatus
                .frame(height: 24)
        }
        .background(Color(red: 0.055, green: 0.066, blue: 0.08))
        .preferredColorScheme(.dark)
        .frame(minWidth: 1130, minHeight: 710)
        .onAppear { keyboard.install(client: client) }
        .onDisappear {
            keyboard.uninstall()
            liveVideo.disconnect()
            client.disconnect()
        }
        .onChange(of: workspace) { _ in
            keyboard.keyboardEnabled = false
            keyboard.releaseAll()
        }
        .onChange(of: client.connected) { connected in
            keyboard.connectionChanged()
            if !connected { liveVideo.disconnect() }
        }
        .onChange(of: client.latestStatus?.payload.latitude) { _ in
            guard let status, status.validAircraft,
                  let lat = status.latitude, let lon = status.longitude else { return }
            let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            guard CLLocationCoordinate2DIsValid(point) else { return }
            if let last = track.last,
               abs(last.latitude - lat) + abs(last.longitude - lon) < 0.000001 {
                return
            }
            track.append(point)
            if track.count > 400 { track.removeFirst(track.count - 400) }
        }
    }

    private var commandBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.17, green: 0.75, blue: 0.68))
                    .frame(width: 28, height: 28)
                Image(systemName: "airplane")
                    .foregroundStyle(.black)
                    .font(.system(size: 15, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("GROUNDSTATION")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                Text("VIRTUAL COCKPIT  /  MAVIC PRO")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.47))
            }
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: 29)
                .padding(.horizontal, 5)

            HStack(spacing: 7) {
                Circle()
                    .fill(aircraftConnected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(aircraftConnected ? "AIRCRAFT LINKED" :
                     (client.connected ? "RC / AIRCRAFT CHECK" : "STANDBY · DISCONNECTED"))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.83))
            }
            Spacer(minLength: 8)

            if workspace == .cockpit {
                Text("FLIGHT OUTPUT LOCKED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            topCommand("Virtual Cockpit", icon: "viewfinder",
                       active: workspace == .cockpit) { workspace = .cockpit }
            topCommand("Routes", icon: "point.topleft.down.curvedto.point.bottomright.up",
                       active: workspace == .missions) { workspace = .missions }
            topCommand("Logs", icon: "clock.arrow.circlepath",
                       active: workspace == .activity) { workspace = .activity }

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: 27)

            Button { showConnection.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: client.connected ? "wifi" : "wifi.slash")
                        .foregroundStyle(client.connected ? Color.green : Color.orange)
                    Text(client.connected ? "Connected" : "Connect")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showConnection, arrowEdge: .bottom) {
                connectionPopover
                    .frame(width: 318)
            }
        }
        .padding(.horizontal, 15)
        .background(Color(red: 0.085, green: 0.096, blue: 0.111))
    }

    private func topCommand(_ title: String, icon: String,
                            active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 11, weight: active ? .semibold : .medium))
            .foregroundStyle(active ? .white : .white.opacity(0.57))
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(active ? Color.white.opacity(0.11) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var connectionPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("iPhone bridge", systemImage: "iphone.gen3")
                    .font(.headline)
                Spacer()
                Image(systemName: client.connected ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(client.connected ? .green : .orange)
            }
            Text("Mac and iPhone must be on the same trusted Wi-Fi. The iPhone runs the DJI SDK while connected to the original controller.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("iPHONE WI-FI ADDRESS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("e.g. 192.168.4.57", text: $host)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("SIX-DIGIT PAIRING CODE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                SecureField("From iOSFlightBridge", text: $client.pairingCode)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button {
                    UserDefaults.standard.set(host, forKey: "GroundStationBridgeIP")
                    client.connect(host: host, port: 8765)
                    liveVideo.connect(host: host, pairingCode: client.pairingCode)
                    showConnection = false
                } label: { Label("Connect", systemImage: "link") }
                    .disabled(host.isEmpty || client.pairingCode.count != 6)
                    .keyboardShortcut(.return, modifiers: [])
                Button("Disconnect") {
                    keyboard.releaseAll()
                    liveVideo.disconnect()
                    client.disconnect()
                    showConnection = false
                }.disabled(!client.connected && !liveVideo.connected)
            }
            Divider()
            HStack {
                Text("TELEMETRY 8765")
                Spacer()
                Text("VIDEO 8766")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(17)
    }

    private var bottomStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(client.connected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(client.connected ? "BRIDGE ONLINE" : "BRIDGE OFFLINE")
            Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 10)
            Text(liveVideo.streamStatus)
                .lineLimit(1)
            Spacer()
            Text("MAC CONTROL STATION")
            Text("·")
            Text("LOCAL LINK ONLY")
            Text("·")
            Text("FLIGHT ACTUATION DISABLED")
                .foregroundStyle(.orange)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.48))
        .padding(.horizontal, 13)
        .background(Color(red: 0.085, green: 0.096, blue: 0.111))
    }
}
