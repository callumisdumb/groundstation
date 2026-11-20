import Combine
import CoreLocation
import Foundation

/// Offline mission drafting only. DJI waypoint mission upload/execution is NOT
/// implemented: original Mavic Pro missions require a separately validated
/// legacy DJI Mobile SDK workflow and safety review.
struct MissionWaypoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var latitude: Double
    var longitude: Double
    var altitudeMeters: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MissionRoute: Identifiable, Codable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var updatedAt: Date?
    var waypoints: [MissionWaypoint] = []
}

@MainActor
final class MissionLibrary: ObservableObject {
    @Published private(set) var routes: [MissionRoute] = []
    @Published var selectedID: UUID?
    @Published private(set) var lastError: String?

    var selectedRoute: MissionRoute? {
        routes.first { $0.id == selectedID }
    }

    init() {
        load()
        if selectedID == nil { selectedID = routes.first?.id }
    }

    func newRoute(name: String = "New flight route") {
        let route = MissionRoute(name: name)
        routes.append(route)
        selectedID = route.id
        persist()
    }

    func renameSelected(_ name: String) {
        guard let i = selectedIndex, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        routes[i].name = name.trimmingCharacters(in: .whitespaces)
        routes[i].updatedAt = Date()
        persist()
    }

    func removeSelected() {
        guard let i = selectedIndex else { return }
        routes.remove(at: i)
        selectedID = routes.first?.id
        persist()
    }

    func addWaypoint(latitude: Double, longitude: Double,
                     altitudeMeters: Double) {
        guard let i = selectedIndex,
              latitude.isFinite, longitude.isFinite, altitudeMeters.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...500).contains(altitudeMeters) else {
            lastError = "Check latitude, longitude and altitude (0–500 m)"
            return
        }
        lastError = nil
        routes[i].updatedAt = Date()
        let number = routes[i].waypoints.count + 1
        routes[i].waypoints.append(MissionWaypoint(
            label: "Waypoint \(number)",
            latitude: latitude, longitude: longitude, altitudeMeters: altitudeMeters))
        persist()
    }

    func deleteWaypoint(id: UUID) {
        guard let i = selectedIndex else { return }
        routes[i].updatedAt = Date()
        routes[i].waypoints.removeAll { $0.id == id }
        persist()
    }

    /// GeoJSON export works with GIS tools, but does not imply that the Mavic
    /// will accept or execute the exported coordinates.
    func geoJSONData() -> Data? {
        guard let route = selectedRoute else { return nil }
        let features: [[String: Any]] = route.waypoints.enumerated().map { index, point in
            [
                "type": "Feature",
                "properties": [
                    "name": point.label,
                    "index": index + 1,
                    "altitudeMeters": point.altitudeMeters
                ],
                "geometry": [
                    "type": "Point",
                    "coordinates": [point.longitude, point.latitude]
                ]
            ]
        }
        let fc: [String: Any] = [
            "type": "FeatureCollection",
            "name": route.name,
            "features": features
        ]
        return try? JSONSerialization.data(withJSONObject: fc,
                                           options: [.prettyPrinted, .sortedKeys])
    }

    private var selectedIndex: Int? {
        routes.firstIndex { $0.id == selectedID }
    }

    private static var saveURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("GroundStation", isDirectory: true)
            .appendingPathComponent("mission-routes.json")
    }

    private func persist() {
        guard let url = Self.saveURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(routes)
            try data.write(to: url, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn't save route: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard let url = Self.saveURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MissionRoute].self, from: data) else { return }
        routes = decoded
    }
}
