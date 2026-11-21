import Foundation

enum PilotKey: String, CaseIterable {
    case forward = "W", backward = "S", left = "A", right = "D"
    case yawLeft = "Q", yawRight = "E", climb = "C", descend = "Z", hold = "Space"

    static func resolve(code: UInt16, characters: String) -> Self? {
        switch code {
        case 49: return .hold
        case 123: return .left
        case 124: return .right
        case 125: return .backward
        case 126: return .forward
        default: return Self(rawValue: characters.uppercased())
        }
    }
}

struct PilotAxes: Equatable {
    var forward = 0.0
    var right = 0.0
    var yaw = 0.0
    var climb = 0.0

    func command(pairingCode: String) -> GroundStationCommand {
        // DJI SDK v4 body velocity uses pitch along Y (right), roll along X (forward).
        GroundStationCommand(pairingCode: pairingCode, action: .sticks,
                             pitch: right, roll: forward, yaw: yaw, vertical: climb)
    }
}

struct PilotInput {
    private var held: [UInt16: PilotKey] = [:]
    var pressed: Set<PilotKey> { Set(held.values) }

    mutating func press(_ key: PilotKey, code: UInt16) { held[code] = key }

    @discardableResult mutating func release(code: UInt16) -> Bool {
        guard let released = held.removeValue(forKey: code) else { return false }
        if released == .hold { held.removeAll() }
        return true
    }

    func axes(precision: Bool) -> PilotAxes {
        let keys = pressed
        guard keys.contains(.hold) else { return PilotAxes() }
        func axis(_ positive: PilotKey, _ negative: PilotKey) -> Double {
            (keys.contains(positive) ? 1 : 0) - (keys.contains(negative) ? 1 : 0)
        }
        let forward = axis(.forward, .backward)
        let right = axis(.right, .left)
        let travel = (precision ? 0.35 : 0.8) / max(1, hypot(forward, right))
        return PilotAxes(forward: forward * travel, right: right * travel,
                         yaw: axis(.yawRight, .yawLeft) * (precision ? 8 : 16),
                         climb: axis(.climb, .descend) * (precision ? 0.25 : 0.6))
    }
}

enum StickAuthority: Equatable {
    case idle, requesting(String), active, releasing(String)
}
