import Foundation

/// Validation and storage rules for replicated `_device_registry.certificate`.
///
/// The certificate is an X25519 *public-key pin*, not secret key material. Its
/// durable representation is `x25519:<canonical-base64-32-byte-key>` so every
/// authorized paired device can consume the same replicated record. The database
/// is SQLCipher-protected at rest; this codec intentionally must not add a
/// device-local encryption layer to a value that replication needs to share.
///
/// `wpdr-cert:` is a reserved legacy envelope namespace. Existing envelopes are
/// rejected rather than decrypted with a device-local key or reinterpreted as
/// plaintext. A re-pair writes a durable raw public-key pin.
enum DeviceRegistryCertificateError: Error, Equatable {
    case malformedLegacyRecord
    case unsupportedEnvelope
}

struct DeviceRegistryCertificateCodec: Sendable {
    static let legacyEnvelopePrefix = "wpdr-cert:"
    static let production = DeviceRegistryCertificateCodec()

    /// Validates a public pin before it is persisted for replication.
    func store(_ publicKeyRecord: String?) throws -> String? {
        guard let publicKeyRecord else { return nil }
        guard Self.isLegacyX25519Record(publicKeyRecord) else {
            throw DeviceRegistryCertificateError.malformedLegacyRecord
        }
        return publicKeyRecord
    }

    /// Reads only a canonical public pin. No envelope value can downgrade into
    /// plaintext, including truncated, tampered, or wrong-device-key envelopes.
    func read(_ storedRecord: String?) throws -> String? {
        guard let storedRecord else { return nil }
        if storedRecord.hasPrefix(Self.legacyEnvelopePrefix) {
            throw DeviceRegistryCertificateError.unsupportedEnvelope
        }
        guard Self.isLegacyX25519Record(storedRecord) else {
            throw DeviceRegistryCertificateError.malformedLegacyRecord
        }
        return storedRecord
    }

    func validateStored(_ storedRecord: String?) throws {
        _ = try read(storedRecord)
    }

    static func isLegacyX25519Record(_ record: String) -> Bool {
        let prefix = "x25519:"
        guard record.hasPrefix(prefix) else { return false }
        let encoded = String(record.dropFirst(prefix.count))
        guard let data = strictBase64Data(encoded), data.count == 32 else { return false }
        return data.base64EncodedString() == encoded
    }

    private static func strictBase64Data(_ value: String) -> Data? {
        Data(base64Encoded: value, options: [.ignoreUnknownCharacters])
            .flatMap { $0.base64EncodedString() == value ? $0 : nil }
    }
}
