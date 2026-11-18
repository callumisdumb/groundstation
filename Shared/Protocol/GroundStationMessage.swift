import Foundation

/// A versioned, newline-delimited JSON envelope exchanged by Mac and iPhone.
/// Keep DJI-specific SDK types entirely inside the iOS bridge.
struct GroundStationMessage: Codable {
    enum Kind: String, Codable {
        case hello
        case aircraftStatus
        case heartbeat
        case error
    }

    var version: Int = 1
    var kind: Kind
    var timestamp: Date = Date()
    var payload: Payload

    struct Payload: Codable {
        var appName: String? = nil
        var deviceName: String? = nil
        var connectionState: String? = nil
        var aircraftModel: String? = nil
        var batteryPercent: Int? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var altitudeMeters: Double? = nil
        var speedMetersPerSecond: Double? = nil
        var simulated: Bool? = nil
        var message: String? = nil
    }
}
