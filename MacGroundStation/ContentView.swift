import CoreLocation
import SwiftUI

enum GSWorkspace: String, CaseIterable, Identifiable {
    case cockpit = "Virtual Cockpit"
    case missions = "Mission Planning"
    case activity = "Activity & Logs"
    var id: Self { self }
    var icon: String {
        switch self {
        case .cockpit: return "rectangle.split.3x1"
        case .missions: return "point.topleft.down.curvedto.point.bottomright.up"
        case .activity: return "waveform.path.ecg.rectangle"
        }
    }
    var subtitle: String {
        switch self {
        case .cockpit: return "Live camera • aircraft map • control centre"
        case .missions: return "Offline route drafting and map overlays"
        case .activity: return "Connection events and command acknowledgements"
        }
    }
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

    private var telemetry: GroundStationMessage.Payload? { client.latestStatus?.payload }
    private var aircraftConnected: Bool { telemetry?.validAircraft == true }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)
                .background(GSPalette.side)
            Rectangle().fill(GSPalette.border).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Divider().overlay(GSPalette.border)
                Group {
                    switch workspace {
                    case .cockpit:
                        CockpitWorkspace(
                            client: client,
                            video: liveVideo,
                            keyboard: keyboard,
                            missions: missions,
                            satellite: $satellite,
                            followAircraft: $followAircraft,
                            track: track)
                    case .missions:
                        MissionWorkspace(
                            missions: missions,
                            client: client,
                            satellite: $satellite,
                            track: track)
                    case .activity:
                        ActivityWorkspace(client: client)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .background(GSPalette.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 1250, minHeight: 770)
        .onAppear { keyboard.install(client: client) }
        .onDisappear {
            keyboard.uninstall()
            liveVideo.disconnect()
            client.disconnect()
        }
        .onChange(of: client.connected) { connected in
            keyboard.connectionChanged()
            if !connected { liveVideo.disconnect() }
        }
        .onChange(of: client.latestStatus?.payload.latitude) { _ in
            guard let data = telemetry, data.validAircraft,
                  let lat = data.latitude, let lon = data.longitude else { return }
            let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            guard CLLocationCoordinate2DIsValid(point) else { return }
            if let last = track.last,
               abs(last.latitude - point.latitude) + abs(last.longitude - point.longitude) < 0.000001 {
                return
            }
            track.append(point)
            if track.count > 350 { track.removeFirst(track.count - 350) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 29))
                    .foregroundStyle(GSPalette.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("GROUNDSTATION")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                    Text("MAVIC PRO · V1")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(GSPalette.muted)
                }
            }
            .padding(.horizontal, 12).padding(.top, 14)

            Text("WORKSPACE")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GSPalette.muted)
                .padding(.horizontal, 14)

            ForEach(GSWorkspace.allCases) { tab in
                Button { workspace = tab } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon).frame(width: 17)
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: workspace == tab ? .semibold : .medium))
                        Spacer()
                    }
                    .foregroundStyle(workspace == tab ? GSPalette.cyan : .white.opacity(0.7))
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    .background(workspace == tab ? GSPalette.cyan.opacity(0.10) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Divider().padding(.horizontal, 14)
            Text("CONNECTED DEVICES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GSPalette.muted)
                .padding(.horizontal, 14)
            VStack(alignment: .leading, spacing: 13) {
                device("iPhone Bridge", status: client.connected, icon: "iphone")
                device("Mavic Pro", status: aircraftConnected, icon: "airplane")
                device("Controller", status: telemetry?.controllerConnected == true, icon: "gamecontroller")
            }.padding(.horizontal, 16)

            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                Label("LOCAL DEVELOPMENT", systemImage: "wrench.adjustable")
                    .foregroundStyle(GSPalette.amber)
                    .font(.system(size: 10, weight: .bold))
                Text("Flight actuation locked pending safety and network verification.")
                    .font(.system(size: 10))
                    .foregroundStyle(GSPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(GSPalette.raised.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
    }

    private func device(_ name: String, status: Bool, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(GSPalette.muted)
            Text(name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Circle()
                .fill(status ? GSPalette.green : GSPalette.muted.opacity(0.4))
                .frame(width: 7, height: 7)
        }
    }

    private var topbar: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workspace.rawValue)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Text(workspace.subtitle)
                        .font(.caption)
                        .foregroundStyle(GSPalette.muted)
                }
                Spacer()
                GSStatusChip(label: aircraftConnected ? "AIRCRAFT ONLINE" :
                             (client.connected ? "BRIDGE ONLINE · RC ONLY" : "DISCONNECTED"),
                             kind: aircraftConnected ? .good : .caution)
                GSStatusChip(label: "FLIGHT CONTROLS LOCKED", kind: .caution)
            }
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .foregroundStyle(GSPalette.cyan)
                TextField("iPhone Wi-Fi IP", text: $host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 155)
                SecureField("Pairing code", text: $client.pairingCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Button {
                    UserDefaults.standard.set(host, forKey: "GroundStationBridgeIP")
                    client.connect(host: host, port: 8765)
                    liveVideo.connect(host: host, pairingCode: client.pairingCode)
                } label: { Label("Connect", systemImage: "link") }
                .disabled(host.isEmpty || client.pairingCode.count != 6)
                Button {
                    liveVideo.disconnect()
                    client.disconnect()
                    keyboard.releaseAll()
                } label: { Label("Disconnect", systemImage: "xmark.circle") }
                .disabled(!client.connected && !liveVideo.connected)
                Spacer()
                Text("TELEM 8765  •  VIDEO 8766")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GSPalette.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(GSPalette.side)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Circle().fill(client.connected ? GSPalette.green : GSPalette.amber)
                .frame(width: 6, height: 6)
            Text(client.connected ? "Bridge connected" : "Bridge disconnected")
            Text("·")
            Text(liveVideo.streamStatus)
                .lineLimit(1)
            Spacer()
            Text("LOCAL MAC GROUND CONTROL · NOT DJI FLIGHTHUB")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(GSPalette.muted)
        .padding(.horizontal, 18)
        .frame(height: 27)
        .background(GSPalette.side)
    }
}
