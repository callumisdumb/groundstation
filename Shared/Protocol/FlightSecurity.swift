import CryptoKit
import Foundation
import Security

/// Flight commands are integrity-protected and confidential independently
/// of the video/telemetry TCP transport. A six-digit pairing code alone does
/// NOT authenticate a flight-control channel.
///
/// A randomly generated 256-bit key is copied once from iPhone to Mac and
/// saved in each device's own Keychain. It is NEVER sent over the network.
/// This is an experimental trusted-LAN link, not a certified flight system.
struct EncryptedFlightPacket: Codable {
    var type = "groundstation.sealed-flight.v1"
    var combined: String
}

enum FlightSecurity {
    static func generateKey() -> String {
        let bytes = SymmetricKey(size: .bits256)
        return bytes.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    static func validKey(_ candidate: String) -> Bool {
        guard let bytes = Data(base64Encoded: candidate.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return bytes.count == 32
    }

    static func seal(_ command: GroundStationCommand, key: String) -> Data? {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32 else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let plaintext = try? encoder.encode(command),
              let sealed = try? AES.GCM.seal(plaintext, using: SymmetricKey(data: bytes)),
              let combined = sealed.combined else { return nil }
        let packet = EncryptedFlightPacket(combined: combined.base64EncodedString())
        return try? encoder.encode(packet)
    }

    static func open(_ packet: EncryptedFlightPacket, key: String) -> GroundStationCommand? {
        guard packet.type == "groundstation.sealed-flight.v1",
              let keyBytes = Data(base64Encoded: key), keyBytes.count == 32,
              let combined = Data(base64Encoded: packet.combined), combined.count < 8192,
              let sealed = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(sealed, using: SymmetricKey(data: keyBytes)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GroundStationCommand.self, from: plaintext)
    }
}

enum FlightKeyStore {
    private static let service = "org.groundstation.paired-flight-key.v1"
    private static let account = "shared-key"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              FlightSecurity.validKey(value) else { return nil }
        return value
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FlightSecurity.validKey(trimmed) else { return false }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updated = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        let add = identity.merging(attributes) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Only the iPhone bridge generates this key. Macs must explicitly pair.
    static func loadOrCreate() -> String {
        if let existing = load() { return existing }
        let newKey = FlightSecurity.generateKey()
        return save(newKey) ? newKey : ""
    }
}

extension GroundStationCommand.Action {
    var requiresEncryptedFlightLink: Bool {
        switch self {
        case .startDJISimulator, .stopDJISimulator,
             .armFlight, .disarmFlight, .takeoff, .land, .returnHome,
             .motorsOn, .motorsOff, .enableSticks, .disableSticks, .sticks,
             .activeTrackPrepare, .activeTrackConfirm, .activeTrackStop:
            return true
        default:
            return false
        }
    }
}
