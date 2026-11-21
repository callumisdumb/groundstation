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

    var waypointCountLabel: String {
        waypoints.count == 1 ? "1 waypoint" : "\(waypoints.count) waypoints"
    }
}

@MainActor
final class MissionLibrary: ObservableObject {
    @Published private(set) var routes: [MissionRoute] = []
    @Published var selectedID: UUID?
    @Published private(set) var lastError: String?

    var selectedRoute: MissionRoute? {
        routes.first { $0.id == selectedID }
    }

    private let storageURL: URL?
    private var loadFailure: String?

    convenience init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GROUNDSTATION_TEMPORARY_ROUTES"] == "1" {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            self.init(storageURL: root.appendingPathComponent("routes.json"))
            return
        }
        #endif
        self.init(storageURL: Self.saveURL)
    }

    init(storageURL: URL?) {
        self.storageURL = storageURL
        guard let storageURL else {
            loadFailure = "Application Support is unavailable."
            lastError = loadFailure
            return
        }
        do {
            routes = try JSONDecoder().decode([MissionRoute].self, from: Data(contentsOf: storageURL))
            selectedID = routes.first?.id
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // First launch has no library yet.
        } catch {
            loadFailure = "Could not read the saved routes. Restore mission-routes.json and reopen GroundStation."
            lastError = loadFailure
        }
    }

    @discardableResult
    func newRoute(name: String = "New flight route") -> Bool {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = MissionRoute(name: title.isEmpty ? "Untitled route" : title)
        return persist(routes + [route], selection: route.id)
    }

    func renameSelected(_ name: String) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateSelected { $0.name = title }
    }

    func removeSelected() {
        guard let i = selectedIndex else { return }
        var next = routes
        next.remove(at: i)
        persist(next, selection: next.first?.id)
    }

    func addWaypoint(latitude: Double, longitude: Double, altitudeMeters: Double) {
        guard latitude.isFinite, longitude.isFinite, altitudeMeters.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (0...500).contains(altitudeMeters) else {
            lastError = "Check latitude, longitude and altitude (0–500 m)"
            return
        }
        updateSelected { route in
            route.waypoints.append(MissionWaypoint(label: "Waypoint \(route.waypoints.count + 1)",
                                                   latitude: latitude, longitude: longitude, altitudeMeters: altitudeMeters))
        }
    }

    func deleteWaypoint(id: UUID) {
        updateSelected { route in route.waypoints.removeAll { $0.id == id } }
    }

    private func updateSelected(_ change: (inout MissionRoute) -> Void) {
        guard let i = selectedIndex else { return }
        var next = routes
        change(&next[i])
        next[i].updatedAt = Date()
        persist(next, selection: selectedID)
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

    @discardableResult
    private func persist(_ next: [MissionRoute], selection: UUID?) -> Bool {
        guard let url = storageURL, loadFailure == nil else {
            lastError = loadFailure
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            routes = next
            selectedID = selection
            lastError = nil
            return true
        } catch {
            lastError = "Could not save routes: \(error.localizedDescription)"
            return false
        }
    }
}
