import XCTest

final class RouteStorageTests: XCTestCase {
    @MainActor
    func testExistingRoutesOpenAndExportWithLongitudeFirst() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mission-routes.json")
        let id = UUID()
        let legacy = [["id": id.uuidString, "name": "Saved route", "createdAt": 0, "waypoints": []]] as [[String: Any]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let library = MissionLibrary(storageURL: url)
        XCTAssertEqual(library.selectedID, id)
        library.addWaypoint(latitude: 54.5, longitude: -3, altitudeMeters: 35)
        let reloaded = MissionLibrary(storageURL: url)
        let data = try XCTUnwrap(reloaded.geoJSONData())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try XCTUnwrap(json["features"] as? [[String: Any]])
        let geometry = try XCTUnwrap(features.first?["geometry"] as? [String: Any])
        XCTAssertEqual(geometry["coordinates"] as? [Double], [-3, 54.5])
    }

    @MainActor
    func testUnreadableLibrarySurvivesAnAttemptedEdit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("incomplete saved route file".utf8)
        try original.write(to: url)
        let library = MissionLibrary(storageURL: url)
        XCTAssertFalse(library.newRoute())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(library.lastError)
    }
}
