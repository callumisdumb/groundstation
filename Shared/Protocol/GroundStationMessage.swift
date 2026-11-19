import Foundation

/// Single newline-delimited JSON protocol between the Mac operator and iPhone bridge.
/// DJI SDK classes never cross the wire.
struct GroundStationMessage: Codable {
    enum Kind: String, Codable {
        case hello, aircraftStatus, cameraFrame, commandResult, heartbeat, error
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
        var aircraftConnected: Bool? = nil
        var controllerConnected: Bool? = nil
        var batteryPercent: Int? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var altitudeMeters: Double? = nil
        var speedMetersPerSecond: Double? = nil
        var velocityX: Double? = nil
        var velocityY: Double? = nil
        var velocityZ: Double? = nil
        var pitchDegrees: Double? = nil
        var rollDegrees: Double? = nil
        var yawDegrees: Double? = nil
        var satelliteCount: Int? = nil
        var flightMode: String? = nil
        var motorsOn: Bool? = nil
        var isFlying: Bool? = nil
        var homeLocationSet: Bool? = nil
        var homeLatitude: Double? = nil
        var homeLongitude: Double? = nil
        var imuPreheating: Bool? = nil
        var flightTimeSeconds: Int? = nil
        /// True only when DJI's own flight simulator is actively running.
        /// This is not the UI telemetry demo simulator.
        var djiSimulatorActive: Bool? = nil
        var virtualSticksEngaged: Bool? = nil
        var flightControlStatus: String? = nil
        // DJI native ActiveTrack status; unavailable in baseline builds.
        var activeTrackState: String? = nil
        var activeTrackTargetRect: TrackingRectangle? = nil
        var activeTrackMovementEnabled: Bool? = nil
        var activeTrackError: String? = nil
        var imageJPEGBase64: String? = nil
        var commandID: String? = nil
        var commandAccepted: Bool? = nil
        var simulated: Bool? = nil
        var message: String? = nil
    }
}

/// Mac-originated operator actions. The iPhone checks a short-lived pairing
/// code, timestamp freshness and actual aircraft state before acting.
struct GroundStationCommand: Codable {
    enum Action: String, Codable {
        case gimbalPitch, takePhoto, startRecording, stopRecording
        case armFlight, disarmFlight, takeoff, land, returnHome
        case motorsOn, motorsOff
        case enableSticks, disableSticks, sticks
        case startDJISimulator, stopDJISimulator
        case activeTrackPrepare, activeTrackConfirm, activeTrackStop
    }
    var version: Int = 1
    var id: String = UUID().uuidString
    var timestamp: Date = Date()
    var pairingCode: String
    var action: Action
    var value: Double? = nil
    var pitch: Double? = nil
    var roll: Double? = nil
    var yaw: Double? = nil
    var vertical: Double? = nil
    /// DJI's video stream coordinate space: top-left origin; values 0–1.
    var trackingRect: TrackingRectangle? = nil
}

/// A subject rectangle in DJI's normalised video space (origin top-left).
struct TrackingRectangle: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        [x, y, width, height].allSatisfy { $0.isFinite } &&
        x >= 0 && y >= 0 && width > 0 && height > 0 &&
        x + width <= 1.0001 && y + height <= 1.0001 &&
        width >= 0.025 && height >= 0.025
    }
}
