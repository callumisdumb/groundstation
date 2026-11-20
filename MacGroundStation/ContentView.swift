import CoreLocation
import SwiftUI

enum GSWorkspace: String, CaseIterable, Identifiable {
    case project = "Team"
    case missions = "Flight Route Library"
    case cockpit = "Virtual Cockpit"
    case activity = "Activity"
    var id: Self { self }

    var icon: String {
        switch self {
        case .project: return "person.2.fill"
        case .missions: return "point.topleft.down.curvedto.point.bottomright.up"
        case .cockpit: return "viewfinder"
        case .activity: return "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @StateObject private var client = BridgeClient()
    @StateObject private var liveVideo = H264LiveVideoClient()
    @StateObject private var keyboard = KeyboardPilotController()
    @StateObject private var missions = MissionLibrary()
    @State private var workspace: GSWorkspace = .project
    @AppStorage("GroundStationBridgeIP") private var host = ""
    @State private var satellite = true
    @State private var followAircraft = true
    @State private var track: [CLLocationCoordinate2D] = []
    @State private var trackSource: String?
    @State private var showConnection = false

    var body: some View {
        HStack(spacing: 0) {
            if workspace != .cockpit { rail }
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                let status = ProjectStatus(client: client, now: clock.date)
                VStack(spacing: 0) {
                    if workspace == .cockpit { cockpitMenu(status) }
                    workspaceView(status: status, now: clock.date)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    statusBar(status)
                }
            }
        }
        .background(GSPalette.background)
        .tint(GSPalette.highlight)
        .preferredColorScheme(.dark)
        .onAppear { keyboard.install(client: client) }
        .onDisappear {
            keyboard.uninstall()
            liveVideo.disconnect()
            client.disconnect()
        }
        .onChange(of: workspace) { _ in keyboard.keyboardEnabled = false }
        .onChange(of: showConnection) { shown in
            if shown { keyboard.keyboardEnabled = false }
        }
        .onChange(of: client.connected) { connected in
            keyboard.connectionChanged()
            track.removeAll()
            trackSource = nil
            if connected, let key = client.bridgeKey {
                liveVideo.connect(host: host, pairingCode: client.pairingCode, bridgeKey: key)
            } else {
                liveVideo.disconnect()
                keyboard.keyboardEnabled = false
            }
        }
        .onChange(of: client.lastTelemetryAt) { _ in recordPosition() }
    }

    @ViewBuilder
    private func workspaceView(status: ProjectStatus, now: Date) -> some View {
        switch workspace {
        case .project:
            ProjectWorkspace(client: client, missions: missions, status: status, satellite: $satellite,
                             track: track, openConnection: { showConnection = true },
                             openCockpit: { workspace = .cockpit }, openRoutes: { workspace = .missions })
        case .missions:
            MissionWorkspace(missions: missions, client: client, satellite: $satellite, track: track, status: status,
                             closeLibrary: { workspace = .project })
        case .cockpit:
            FlightCockpitView(client: client, video: liveVideo, keyboard: keyboard, missions: missions,
                              satellite: $satellite, followAircraft: $followAircraft, track: track,
                              status: status, now: now)
        case .activity:
            ActivityWorkspace(client: client)
        }
    }

    private var rail: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 17, weight: .bold))
                .frame(height: 42)
                .accessibilityLabel("GroundStation")
            Divider().overlay(.white.opacity(0.25)).padding(.horizontal, 8)
            ForEach(GSWorkspace.allCases) { item in
                let selected = item == workspace
                Button { workspace = item } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 32)
                        .background(selected ? Color.white.opacity(0.23) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help(item.rawValue)
                .accessibilityLabel(item.rawValue)
                .accessibilityIdentifier("nav-\(item.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            Button { showConnection.toggle() } label: {
                Image(systemName: client.connected ? "link.circle.fill" : "link.circle")
                    .font(.system(size: 18)).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Bridge connection")
            .help("Bridge connection")

        }
        .padding(.bottom, 8)
        .frame(width: 46)
        .foregroundStyle(.white)
        .background(GSPalette.rail)
    }

    private func cockpitMenu(_ status: ProjectStatus) -> some View {
        HStack(spacing: 10) {
            ProjectIconButton(label: "Return to project", symbol: "chevron.left") { workspace = .project }
            Text("Virtual Cockpit").fontWeight(.semibold)
            Divider().frame(height: 14)
            Text("Mavic Pro Project").foregroundStyle(GSPalette.muted)
            Spacer()
            Circle().fill(status.tint).frame(width: 6, height: 6)
            Text(status.rawValue)
            ProjectIconButton(label: "Flight Route Library", symbol: GSWorkspace.missions.icon) { workspace = .missions }
            ProjectIconButton(label: "Bridge connection", symbol: "link") { showConnection = true }
        }
        .font(.system(size: 12)).padding(.horizontal, 6).frame(height: 38).background(GSPalette.side)
    }

    private func statusBar(_ status: ProjectStatus) -> some View {
        HStack(spacing: 7) {
            Circle().fill(status.tint).frame(width: 6, height: 6)
            Text(status.rawValue)
            if client.connected {
                Divider().frame(height: 11)
                Text(liveVideo.lastVideoAt == nil ? liveVideo.streamStatus : "H.264")
                    .lineLimit(1)
            }
            Spacer()
            if client.connected && client.flightKeyVerified {
                Text(client.liveFlightAuthorized ? "Live flight authorized" :
                     (client.djiSimulatorActive ? "DJI Simulator" : "Live flight locked"))
            }
            Button(client.connected ? "Connection" : "Connect bridge") { showConnection = true }
                .buttonStyle(.plain)
                .foregroundStyle(GSPalette.cyan)
                .popover(isPresented: $showConnection, arrowEdge: .top) {
                    BridgeConnectionView(client: client, host: $host)
                }
        }
        .font(.system(size: 11))
        .foregroundStyle(GSPalette.muted)
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(GSPalette.background)
    }

    private func recordPosition() {
        guard let payload = client.latestStatus?.payload, payload.validAircraft else {
            track.removeAll()
            trackSource = nil
            return
        }
        let source = (payload.djiSimulatorActive == true ? "sim/" : "aircraft/") + (payload.aircraftModel ?? "")
        if source != trackSource {
            track.removeAll()
            trackSource = source
        }
        guard let point = payload.aircraftPoint else { return }
        if let last = track.last, last.latitude == point.latitude && last.longitude == point.longitude { return }
        track.append(point)
        if track.count > 400 { track.removeFirst(track.count - 400) }
    }
}
