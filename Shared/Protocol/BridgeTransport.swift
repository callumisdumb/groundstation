import CryptoKit
import Foundation
import Network
import Security

/// Both peers provision the bridge key out of band. The short code is a session
/// salt. Possession of a bridge key does not reveal the separate flight key.
enum BridgeTransport {
    enum Channel: String {
        case telemetry, video
    }

    static func validCode(_ value: String) -> Bool {
        value.utf8.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func bridgeKey(fromFlightKey flightKey: String) -> String? {
        guard let bytes = Data(base64Encoded: flightKey), bytes.count == 32 else { return nil }
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes),
                                         info: Data("GroundStation/bridge-key/v1".utf8),
                                         outputByteCount: 32)
        return key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    static func parameters(key: String, code: String, channel: Channel) -> NWParameters? {
        guard validCode(code), let bytes = Data(base64Encoded: key), bytes.count == 32,
              let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))
        else { return nil }
        let identity = Data("GroundStation/v2/\(channel.rawValue)".utf8)
        let psk = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes),
                                         salt: Data(code.utf8), info: identity, outputByteCount: 32)
        let secret = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let label = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_append_tls_ciphersuite(options, suite)
        sec_protocol_options_add_pre_shared_key(options, secret as __DispatchData, label as __DispatchData)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 8
        return NWParameters(tls: tls, tcp: tcp)
    }

    static func authenticated(_ connection: NWConnection) -> Bool {
        guard let tls = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
        else { return false }
        return sec_protocol_metadata_get_negotiated_tls_ciphersuite(tls.securityProtocolMetadata).rawValue
            == UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)
    }
}
