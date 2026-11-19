import AppKit
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

/// Offline route editor inspired by mission management workflows.
/// Plans are not sent to the Mavic Pro until DJI SDK waypoint support has been
/// independently validated with the original aircraft.
struct MissionWorkspace: View {
    @ObservedObject var missions: MissionLibrary
    @ObservedObject var client: BridgeClient
    @Binding var satellite: Bool
    let track: [CLLocationCoordinate2D]

    @State private var newRouteName = "Inspection route"
    @State private var renameText = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var altitude = 35.0
    @State private var exportMessage: String?

    private var current: MissionRoute? { missions.selectedRoute }
    private var telemetry: GroundStationMessage.Payload? { client.latestStatus?.payload }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            routeLibrary.frame(width: 245)
            VStack(spacing: 12) {
                GSPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("MISSION MAP", systemImage: "map")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Toggle("Satellite", isOn: $satellite)
                                .toggleStyle(.checkbox)
                                .font(.caption)
                        }
                        GroundStationMap(
                            aircraft: aircraftPoint,
                            home: homePoint,
                            route: current?.waypoints ?? [],
                            flightTrack: track,
                            satellite: satellite, followAircraft: false)
                        .frame(minHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text("Orange = planned route • Cyan = flight track • Green = home point")
                            .font(.system(size: 10))
                            .foregroundStyle(GSPalette.muted)
                    }
                }
                GSPanel("Waypoints", icon: "mappin.and.ellipse") {
                    if let points = current?.waypoints, !points.isEmpty {
                        ScrollView {
                            VStack(spacing: 7) {
                                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                    HStack(spacing: 10) {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.caption.monospaced())
                                            .foregroundStyle(GSPalette.amber)
                                            .frame(width: 26)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(point.label)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(String(format: "%.6f, %.6f",
                                                        point.latitude, point.longitude))
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(GSPalette.muted)
                                        }
                                        Spacer()
                                        Text("\(Int(point.altitudeMeters)) m")
                                            .font(.system(size: 11, design: .monospaced))
                                        Button {
                                            missions.deleteWaypoint(id: point.id)
                                        } label: { Image(systemName: "trash") }
                                            .buttonStyle(.borderless)
                                            .help("Delete waypoint")
                                    }
                                    Divider().overlay(GSPalette.border)
                                }
                            }
                        }
                        .frame(maxHeight: 215)
                    } else {
                        Label("No waypoints yet. Add one using the editor.",
                              systemImage: "mappin.slash")
                            .foregroundStyle(GSPalette.muted)
                            .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            routeEditor.frame(width: 280)
        }
        .padding(14)
        .background(GSPalette.background)
        .onChange(of: missions.selectedID) { _ in
            renameText = current?.name ?? ""
        }
    }

    private var routeLibrary: some View {
        VStack(spacing: 12) {
            GSPanel("Route library", icon: "square.stack.3d.up") {
                VStack(spacing: 11) {
                    TextField("New route name", text: $newRouteName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        missions.newRoute(name: newRouteName.isEmpty ? "Untitled route" : newRouteName)
                        renameText = missions.selectedRoute?.name ?? ""
                    } label: {
                        Label("Create route", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(missions.routes) { route in
                        Button {
                            missions.selectedID = route.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                    .foregroundStyle(missions.selectedID == route.id ?
                                                     GSPalette.cyan : GSPalette.muted)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(route.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text("\(route.waypoints.count) waypoints")
                                        .font(.caption2)
                                        .foregroundStyle(GSPalette.muted)
                                }
                                Spacer()
                            }
                            .padding(9)
                            .background(missions.selectedID == route.id ?
                                        GSPalette.cyan.opacity(0.11) : GSPalette.raised.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    if missions.routes.isEmpty {
                        Text("Create your first mission to begin planning.")
                            .font(.caption)
                            .foregroundStyle(GSPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer()
        }
    }

    private var routeEditor: some View {
        VStack(spacing: 12) {
            GSPanel("Route configuration", icon: "slider.horizontal.3") {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Route title", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(current == nil)
                    Button("Rename") { missions.renameSelected(renameText) }
                        .disabled(current == nil || renameText.isEmpty)
                    Divider().overlay(GSPalette.border)
                    Text("Add coordinate").font(.headline)
                    TextField("Latitude (-90…90)", text: $latitudeText)
                        .textFieldStyle(.roundedBorder)
                    TextField("Longitude (-180…180)", text: $longitudeText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("Altitude")
                        Slider(value: $altitude, in: 5...120, step: 5)
                        Text("\(Int(altitude)) m")
                            .font(.caption.monospacedDigit())
                    }
                    Button {
                        guard let lat = Double(latitudeText),
                              let lon = Double(longitudeText) else {
                            exportMessage = "Enter decimal GPS coordinates."
                            return
                        }
                        missions.addWaypoint(latitude: lat, longitude: lon,
                                             altitudeMeters: altitude)
                        exportMessage = missions.lastError
                    } label: {
                        Label("Add waypoint", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(current == nil)

                    Button {
                        guard let lat = telemetry?.latitude,
                              let lon = telemetry?.longitude else { return }
                        missions.addWaypoint(latitude: lat, longitude: lon,
                                             altitudeMeters: altitude)
                    } label: {
                        Label("Add aircraft position", systemImage: "location")
                    }
                    .disabled(current == nil || telemetry?.validAircraft != true ||
                              telemetry?.latitude == nil || telemetry?.longitude == nil)
                    Divider().overlay(GSPalette.border)
                    Button {
                        exportRoute()
                    } label: {
                        Label("Export GeoJSON", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(current == nil)
                    Button(role: .destructive) {
                        missions.removeSelected()
                        renameText = missions.selectedRoute?.name ?? ""
                    } label: {
                        Label("Delete route", systemImage: "trash")
                    }
                    .disabled(current == nil)
                    if let message = exportMessage ?? missions.lastError {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(GSPalette.amber)
                    }
                }
                .controlSize(.small)
            }
            GSPanel("Execution status", icon: "lock.shield") {
                GSStatusChip(label: "PLANNING ONLY", kind: .caution)
                Text("This library persists routes locally on the Mac and exports GeoJSON. It does not upload or execute waypoint missions.")
                    .font(.system(size: 11))
                    .foregroundStyle(GSPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var aircraftPoint: CLLocationCoordinate2D? {
        guard telemetry?.validAircraft == true,
              let lat = telemetry?.latitude, let lon = telemetry?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var homePoint: CLLocationCoordinate2D? {
        guard telemetry?.homeLocationSet == true,
              let lat = telemetry?.homeLatitude,
              let lon = telemetry?.homeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private func exportRoute() {
        guard let data = missions.geoJSONData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (current?.name ?? "Route")
            .replacingOccurrences(of: "/", with: "-") + ".geojson"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                exportMessage = "Exported \(url.lastPathComponent)"
            } catch {
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
