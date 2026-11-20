import CoreLocation
import SwiftUI

struct ProjectWorkspace: View {
    @ObservedObject var client: BridgeClient
    @ObservedObject var missions: MissionLibrary
    let status: ProjectStatus
    @Binding var satellite: Bool
    let track: [CLLocationCoordinate2D]
    let openConnection: () -> Void
    let openCockpit: () -> Void
    let openRoutes: () -> Void

    @AppStorage("GroundStationCallSign") private var callSign = NSFullUserName()
    @State private var editingCallSign = false
    @State private var panelVisible = true
    @State private var stationExpanded = true
    @State private var devicesExpanded = true
    @State private var membersExpanded = false
    @State private var showLayers = false
    @State private var showSearch = false
    @State private var search = ""
    @State private var showRoute = true
    @State private var showTrack = true
    @State private var request: MapRequest?

    private var payload: GroundStationMessage.Payload? {
        status.hasAircraftData ? client.latestStatus?.payload : nil
    }
    private var route: [MissionWaypoint] { showRoute ? missions.selectedRoute?.waypoints ?? [] : [] }
    private var aircraft: CLLocationCoordinate2D? { payload?.aircraftPoint }
    private var name: String { callSign.isEmpty ? "Mac operator" : callSign }

    var body: some View {
        HStack(spacing: 0) {
            if panelVisible { panel.frame(width: 264) }
            ZStack {
                GroundStationMap(aircraft: aircraft, home: payload?.homePoint, route: route,
                                 flightTrack: showTrack ? track : [], satellite: satellite,
                                 followAircraft: false, request: request)
                if !panelVisible {
                    VStack {
                        HStack {
                            ProjectIconButton(label: "Show team panel", symbol: "sidebar.left") { panelVisible = true }
                                .background(GSPalette.panel)
                            Spacer()
                        }
                        Spacer()
                    }.padding(10)
                }
            }
            .overlay(alignment: .topTrailing) { mapTools.padding(.top, 55).padding(.trailing, 10) }
            .overlay(alignment: .bottomLeading) {
                if route.count > 1 || (showTrack && track.count > 1) {
                    HStack(spacing: 12) {
                        if route.count > 1 { legend("Planned route", color: GSPalette.green) }
                        if showTrack && track.count > 1 { legend("Flight track", color: GSPalette.cyan) }
                    }
                    .padding(7).background(GSPalette.side.opacity(0.95))
                    .padding(.leading, 10).padding(.bottom, 26)
                }
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mavic Pro Project").font(.system(size: 14, weight: .semibold))
                Spacer()
                ProjectIconButton(label: "Hide team panel", symbol: "sidebar.left") { panelVisible = false }
            }
            .padding(.leading, 12).padding(.trailing, 3).frame(height: 43)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("My Call Sign").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.top, 11)
                    HStack(spacing: 7) {
                        Image(systemName: "person.crop.circle.fill").foregroundStyle(GSPalette.cyan)
                        if editingCallSign {
                            TextField("Call sign", text: $callSign)
                                .onSubmit { editingCallSign = false }
                        } else {
                            Text(name).lineLimit(1)
                        }
                        Spacer()
                        Button { editingCallSign.toggle() } label: {
                            Image(systemName: editingCallSign ? "checkmark" : "pencil")
                        }
                        .buttonStyle(.plain).accessibilityLabel(editingCallSign ? "Save call sign" : "Edit call sign")
                    }
                    .font(.system(size: 12)).padding(.horizontal, 12).frame(minHeight: 35)
                    section("Ground Station", count: 1, expanded: $stationExpanded)
                    if stationExpanded {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 7) {
                                Image(systemName: "iphone")
                                Text("iPhone bridge").fontWeight(.medium)
                                Spacer()
                                Text(client.connected ? "Online" : (client.connecting ? "Pairing" : "Offline"))
                                    .foregroundStyle(client.connected ? GSPalette.green : GSPalette.muted)
                            }.padding(9)
                            Divider()
                            HStack {
                                Label("Connection", systemImage: "wifi")
                                Spacer()
                                Button(client.connected ? "Manage" : "Connect", action: openConnection)
                                    .buttonStyle(.plain).foregroundStyle(GSPalette.cyan)
                            }.padding(9)
                        }
                        .font(.system(size: 12))
                        .background(GSPalette.panel)
                        .overlay(Rectangle().strokeBorder(GSPalette.border))
                        .padding(8)
                    }
                    section("Online Devices", count: status.hasAircraftData ? 1 : 0, expanded: $devicesExpanded)
                    if devicesExpanded {
                        if let payload {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: "airplane")
                                    Button(payload.aircraftModel ?? "Aircraft") {
                                        if let aircraft { request = MapRequest(action: .center(aircraft)) }
                                    }
                                    .buttonStyle(.plain).disabled(aircraft == nil)
                                    Spacer()
                                    Circle().fill(status.tint).frame(width: 6, height: 6)
                                }.font(.system(size: 12, weight: .semibold))
                                HStack {
                                    Text(payload.flightMode ?? status.rawValue)
                                    Spacer()
                                    Label(payload.batteryText, systemImage: "battery.75percent")
                                }.font(.system(size: 11)).foregroundStyle(GSPalette.muted)
                                if status == .simulator { Text(status.rawValue).foregroundStyle(GSPalette.cyan) }
                            }
                            .padding(10).background(GSPalette.panel).padding(8)
                        } else {
                            Text(status == .stale ? "Last telemetry update is stale" :
                                 (status == .demo ? "Demo bridge · no aircraft" : "No online aircraft"))
                                .font(.system(size: 12)).foregroundStyle(GSPalette.muted)
                                .padding(.horizontal, 12).padding(.vertical, 14)
                        }
                    }
                    section("Online Members", count: 1, expanded: $membersExpanded)
                    if membersExpanded {
                        Label("\(name) · This Mac", systemImage: "person.crop.circle").font(.callout).padding(12)
                    }
                }
            }
            Divider()
            HStack {
                Button(action: openCockpit) { Label("Virtual Cockpit", systemImage: "viewfinder") }
                Spacer()
                Button(action: openRoutes) { Image(systemName: "point.topleft.down.curvedto.point.bottomright.up") }
                    .accessibilityLabel("Open flight route library").help("Flight Route Library")
            }
            .buttonStyle(.plain).foregroundStyle(GSPalette.cyan)
            .font(.system(size: 12, weight: .medium)).padding(12)
        }
        .background(GSPalette.side)
    }

    private func section(_ title: String, count: Int, expanded: Binding<Bool>) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold)).frame(width: 10)
                Text(title).fontWeight(.medium)
                Spacer()
                Text(String(count)).foregroundStyle(GSPalette.muted).monospacedDigit()
            }
            .padding(.horizontal, 10).frame(height: 31).background(GSPalette.raised)
            .overlay(alignment: .bottom) { Rectangle().fill(GSPalette.border).frame(height: 1) }
        }
        .buttonStyle(.plain).font(.system(size: 12))
        .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    private var mapTools: some View {
        VStack(spacing: 1) {
            ProjectIconButton(label: "Search project map", symbol: "magnifyingglass", selected: showSearch) {
                showSearch.toggle()
            }
            .popover(isPresented: $showSearch, arrowEdge: .leading) { mapSearch }
            ProjectIconButton(label: "Map layers", symbol: "square.3.layers.3d", selected: showLayers) {
                showLayers.toggle()
            }
            .popover(isPresented: $showLayers, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Map Layers").font(.headline)
                    Picker("Basemap", selection: $satellite) {
                        Text("Standard").tag(false)
                        Text("Satellite").tag(true)
                    }.pickerStyle(.segmented)
                    Toggle("Selected flight route", isOn: $showRoute)
                    Toggle("Flight track", isOn: $showTrack)
                }.padding(15).frame(width: 240)
            }
            Divider().frame(width: 24)
            ProjectIconButton(label: "Recenter project map", symbol: "scope") {
                if let aircraft { request = MapRequest(action: .center(aircraft)) }
                else if !route.isEmpty { request = MapRequest(action: .fit(route.map(\.coordinate))) }
                else { request = MapRequest(action: .overview) }
            }
            ProjectIconButton(label: "Zoom in", symbol: "plus") { request = MapRequest(action: .zoom(0.5)) }
            ProjectIconButton(label: "Zoom out", symbol: "minus") { request = MapRequest(action: .zoom(2)) }
        }
        .background(GSPalette.side.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.3), radius: 3)
    }

    private var mapSearch: some View {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = missions.routes.filter { !$0.waypoints.isEmpty && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        let findAircraft = aircraft != nil && (query.isEmpty || (payload?.aircraftModel ?? "Aircraft").localizedCaseInsensitiveContains(query))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Search project map").font(.headline)
            TextField("Device, route or latitude, longitude", text: $search)
                .onSubmit { if let point = Self.coordinate(query) { move(.center(point)) } }
            if let point = Self.coordinate(query) {
                Button("Go to coordinates") { move(.center(point)) }
            }
            if findAircraft, let aircraft {
                Button(payload?.aircraftModel ?? "Aircraft") { move(.center(aircraft)) }
            }
            if !matches.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(matches) { entry in
                            Button(entry.name) {
                                missions.selectedID = entry.id
                                showRoute = true
                                move(.fit(entry.waypoints.map(\.coordinate)))
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 165)
            } else if !findAircraft && Self.coordinate(query) == nil {
                Text(query.isEmpty ? "Enter coordinates to locate a point." : "No matching project item or valid coordinates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).frame(width: 280)
    }

    private func move(_ action: MapRequest.Action) {
        request = MapRequest(action: action)
        showSearch = false
    }

    static func coordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func legend(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 14, height: 3)
            Text(label).font(.system(size: 10))
        }
    }
}
