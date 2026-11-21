import Foundation

/// Keep each accepted ID through its entire acceptance window, across sockets.
/// At capacity, refuse new IDs until an entry expires.
struct CommandWindow {
    private var expires: [String: Date] = [:]
    static let tolerance: TimeInterval = 3
    private let capacity = 256

    mutating func admit(_ command: GroundStationCommand, now: Date = Date()) -> Bool {
        guard command.version == 1, !command.id.isEmpty, command.id.utf8.count <= 80,
              abs(now.timeIntervalSince(command.timestamp)) <= Self.tolerance else { return false }
        expires = expires.filter { $0.value >= now }
        guard expires[command.id] == nil, expires.count < capacity else { return false }
        expires[command.id] = command.timestamp.addingTimeInterval(Self.tolerance)
        return true
    }
}
