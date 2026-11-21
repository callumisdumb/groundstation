import AppKit
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct MissionWorkspace: View {
    @ObservedObject var missions: MissionLibrary
    @ObservedObject var client: BridgeClient
    @Binding var satellite: Bool
    let track: [CLLocationCoordinate2D]
    let status: ProjectStatus
    let closeLibrary: () -> Void
    let openCockpit: () -> Void

    @State private var editing = false
    @State private var settings = false
    @State private var search = ""
    @State private var newestFirst = true
    @State private var renameText = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var altitude = 35.0
    @State private var feedback: String?
    @State private var deletion: MissionRoute?
    @State private var mapRequest: MapRequest?
    @FocusState private var searchFocused: Bool

    private var current: MissionRoute? { missions.selectedRoute }
    private var telemetry: GroundStationMessage.Payload? { status.hasAircraftData ? client.latestStatus?.payload : nil }
    private var visibleRoutes: [MissionRoute] {
        missions.routes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted {
                let lhs = $0.updatedAt ?? $0.createdAt
                let rhs = $1.updatedAt ?? $1.createdAt
                return newestFirst ? lhs > rhs : lhs < rhs
            }
    }

    var body: some View {
        GeometryReader { size in
            ZStack {
                GroundStationMap(aircraft: telemetry?.aircraftPoint, home: telemetry?.homePoint,
                                 route: current?.waypoints ?? [], flightTrack: track,
                                 satellite: satellite, followAircraft: false, request: mapRequest)
                    .padding(.trailing, editing ? 300 : 0)
                if editing, let current {
                    VStack(spacing: 0) {
                        HStack {
                            ProjectIconButton(label: "Back to Route Library", symbol: "chevron.left") {
                                editing = false
                                feedback = nil
                            }
                            Text(current.name).fontWeight(.semibold).lineLimit(1)
                            Text("Waypoint route").font(.caption).foregroundStyle(GSPalette.muted)
                            Spacer()
                            Button(action: openCockpit) { Label("View in cockpit", systemImage: "viewfinder") }
                                .buttonStyle(.plain).foregroundStyle(GSPalette.cyan)
                                .help("Show this draft on the cockpit map")
                            Toggle("Satellite", isOn: $satellite).toggleStyle(.checkbox)
                        }.padding(.trailing, 12).frame(height: 40).background(GSPalette.side)
                        HStack(spacing: 0) {
                            Spacer()
                            editor(current).frame(width: 300)
                        }
                    }
                } else {
                    Color.black.opacity(0.23).allowsHitTesting(false)
                    library
                        .frame(width: size.size.width * 0.90, height: size.size.height * 0.90)
                        .environment(\.colorScheme, .light)
                }
            }
        }
        .confirmationDialog("Delete \(deletion?.name ?? "route")?",
                            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                            titleVisibility: .visible, presenting: deletion) { route in
            Button("Delete route", role: .destructive) {
                missions.selectedID = route.id
                missions.removeSelected()
                editing = false
                deletion = nil
            }
            Button("Cancel", role: .cancel) { deletion = nil }
        } message: { _ in Text("This removes the saved route and all of its waypoints from this Mac.") }
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Route Library", systemImage: "list.bullet.rectangle").font(.headline)
                Spacer()
                Button(action: closeLibrary) { Image(systemName: "xmark").padding(6) }
                    .buttonStyle(.plain).accessibilityLabel("Close route library")
            }.padding(.horizontal, 12).frame(height: 43)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Project Folder", systemImage: "folder").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 42)
                    HStack {
                        Image(systemName: "folder.fill")
                        Text("Local routes (\(missions.routes.count))").lineLimit(1)
                        Spacer()
                    }.padding(.horizontal, 15).frame(height: 34)
                    .foregroundStyle(Color.blue).background(Color.blue.opacity(0.09))
                    Spacer()
                }.frame(width: 176)
                Divider()
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button { if missions.newRoute() { openEditor() } } label: {
                            Image(systemName: "plus").fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent).accessibilityLabel("Create route").help("Create route")
                        Button {
                            newestFirst.toggle()
                        } label: { Label("Update time", systemImage: newestFirst ? "arrow.down" : "arrow.up") }
                        .help(newestFirst ? "Newest first" : "Oldest first")
                        Spacer()
                        TextField("Search routes", text: $search)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 175).focused($searchFocused)
                    }.padding(.horizontal, 10).padding(.vertical, 8)
                    Divider()
                    if visibleRoutes.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder").font(.system(size: 29, weight: .light))
                            Text(search.isEmpty ? "No flight routes" : "No matching routes").font(.headline)
                            if search.isEmpty {
                                Button("Create route") { if missions.newRoute() { openEditor() } }
                            }
                        }.foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(visibleRoutes) { route in
                                    routeRow(route)
                                }
                            }.padding(5)
                        }
                    }
                    if let error = missions.lastError {
                        Text(error).foregroundStyle(.red).font(.caption).padding(6)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color(white: 0.15))
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .onExitCommand(perform: closeLibrary)
    }

    private func routeRow(_ route: MissionRoute) -> some View {
        let selected = missions.selectedID == route.id
        return HStack(spacing: 8) {
            Button {
                missions.selectedID = route.id
                openEditor()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .foregroundStyle(.white).frame(width: 27, height: 27)
                        .background(Color(red: 0.07, green: 0.15, blue: 0.34))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.name).fontWeight(.semibold).lineLimit(1)
                        Text("\(route.waypointCountLabel)  ·  Mavic Pro")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text((route.updatedAt ?? route.createdAt).formatted(date: .numeric, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit \(route.name)")
            Menu {
                Button("Edit route") { missions.selectedID = route.id; openEditor() }
                Button("Delete route", role: .destructive) { deletion = route }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(route.name)")
        }
        .padding(.horizontal, 8).frame(height: 51)
        .background(selected ? Color.blue.opacity(0.05) : .white)
        .overlay(Rectangle().strokeBorder(selected ? Color.blue : Color(white: 0.89)))
    }

    private func editor(_ route: MissionRoute) -> some View {
        VStack(spacing: 0) {
            Picker("Route editor", selection: $settings) {
                Text("Waypoints").tag(false)
                Text("Settings").tag(true)
            }.pickerStyle(.segmented).labelsHidden().padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if settings {
                        Text("Route name").font(.headline)
                        TextField("Route name", text: $renameText)
                        Button("Rename") { missions.renameSelected(renameText) }
                            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Divider()
                        Button("Export GeoJSON", action: exportRoute)
                        Button("Delete route", role: .destructive) { deletion = route }
                    } else {
                        Text("Waypoints (\(route.waypoints.count))").font(.headline)
                        ForEach(Array(route.waypoints.enumerated()), id: \.element.id) { index, point in
                            HStack(spacing: 6) {
                                Button {
                                    mapRequest = MapRequest(action: .center(point.coordinate))
                                } label: {
                                    HStack {
                                        Text("\(index + 1)").foregroundStyle(GSPalette.green).monospacedDigit()
                                        VStack(alignment: .leading) {
                                            Text(point.label)
                                            Text(String(format: "%.5f, %.5f", point.latitude, point.longitude))
                                                .font(.caption).foregroundStyle(GSPalette.muted)
                                        }
                                    }
                                }.buttonStyle(.plain)
                                Spacer()
                                Text(String(format: "%.0f m", point.altitudeMeters)).monospacedDigit()
                                Button { missions.deleteWaypoint(id: point.id); fitRoute() } label: {
                                    Image(systemName: "minus.circle")
                                }.buttonStyle(.plain).accessibilityLabel("Remove waypoint \(index + 1)")
                            }
                        }
                        Divider()
                        Text("Add coordinate").font(.headline)
                        TextField("Latitude (−90 to 90)", text: $latitudeText)
                        TextField("Longitude (−180 to 180)", text: $longitudeText)
                        HStack {
                            Text("Altitude")
                            Slider(value: $altitude, in: 5...120, step: 5)
                            Text("\(Int(altitude)) m").monospacedDigit()
                        }
                        Button("Add waypoint") {
                            guard let point = ProjectWorkspace.coordinate(latitudeText + "," + longitudeText) else {
                                feedback = "Enter valid decimal latitude and longitude."
                                return
                            }
                            add(point)
                        }.buttonStyle(.borderedProminent)
                        Button("Add aircraft position") {
                            if let point = telemetry?.aircraftPoint { add(point) }
                        }.disabled(telemetry?.aircraftPoint == nil)
                    }
                    if let notice = missions.lastError ?? feedback {
                        Text(notice).font(.caption).foregroundStyle(GSPalette.amber)
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Label("Local draft · planning only", systemImage: "lock")
                .font(.caption).foregroundStyle(GSPalette.muted).padding(10)
        }.textFieldStyle(.roundedBorder).font(.system(size: 12)).background(GSPalette.side)
    }

    private func openEditor() {
        renameText = current?.name ?? ""
        latitudeText = ""
        longitudeText = ""
        feedback = nil
        settings = false
        editing = current != nil
        fitRoute()
    }

    private func fitRoute() {
        if let points = current?.waypoints, !points.isEmpty {
            mapRequest = MapRequest(action: .fit(points.map(\.coordinate)))
        }
    }

    private func add(_ point: CLLocationCoordinate2D) {
        missions.addWaypoint(latitude: point.latitude, longitude: point.longitude, altitudeMeters: altitude)
        feedback = nil
        fitRoute()
    }

    private func exportRoute() {
        guard let data = missions.geoJSONData() else { feedback = "Could not prepare route for export."; return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "geojson") ?? .json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (current?.name ?? "Route").replacingOccurrences(of: "/", with: "-") + ".geojson"
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); feedback = "Exported \(url.lastPathComponent)" }
            catch { feedback = "Export failed: \(error.localizedDescription)" }
        }
    }
}
