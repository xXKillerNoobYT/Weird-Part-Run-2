import Foundation
import CryptoKit

/// Shared utility for encrypting and decrypting sensitive string fields (email, phone, etc.)
/// before they are persisted to the local SQLite database.
///
/// Uses a device-specific AES-GCM 256-bit key backed by the system Keychain.
/// The key is generated on first launch and reused on subsequent launches.
/// Accessibility tier: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
///
/// This is the single canonical encryption helper for all services. Do **not** create
/// per-service encryption helpers — route all sensitive-field I/O through this type.
public enum FieldEncryption {

    // MARK: - Errors

    public enum FieldEncryptionError: Error, Sendable, Equatable {
        /// Could not store the generated key in the Keychain.
        case keychainStoreFailed
        /// Decryption failed (wrong key, corrupted data, etc.).
        case decryptionFailed
    }

    // MARK: - Keychain-backed symmetric key

    /// Device-specific 256-bit symmetric key. Loaded from (or stored to) the Keychain on
    /// first access, then cached in memory for the lifetime of the process.
    ///
    /// Service: `com.wiredpart.field-encryption-key` / Account: `v1`
    /// Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
    static let key: SymmetricKey = {
        let service = "com.wiredpart.field-encryption-key"
        let account = "v1"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // Generate a new cryptographically random 256-bit key and persist it.
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let keyData = Data(keyBytes)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        _ = SecItemAdd(addQuery as CFDictionary, nil)
        return SymmetricKey(data: keyData)
    }()

    // MARK: - Encrypt

    /// Encrypt a sensitive string value using AES-GCM.
    ///
    /// Returns the base64-encoded combined sealed box (12-byte nonce + ciphertext + 16-byte tag).
    /// `nil` and empty strings pass through unchanged so that optional fields stored as SQL NULL
    /// or empty strings are preserved without alteration.
    public static func encrypt(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return value }
        let sealedBox = try AES.GCM.seal(Data(value.utf8), using: key)
        guard let combined = sealedBox.combined else {
            throw FieldEncryptionError.keychainStoreFailed
        }
        return combined.base64EncodedString()
    }

    // MARK: - Decrypt

    /// Decrypt a base64-encoded AES-GCM sealed value.
    ///
    /// - `nil` and empty strings pass through unchanged.
    /// - Non-base64 strings (legacy plaintext rows) pass through unchanged so that
    ///   the app continues to display pre-encryption data during a rolling migration.
    /// - Values that fail AES-GCM decryption (wrong key, corrupted data) pass through
    ///   unchanged rather than throwing, so that a key rotation or bad row doesn't crash
    ///   the whole list query.
    public static func decrypt(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return value }
        guard let data = Data(base64Encoded: value) else {
            // Not base64 — treat as legacy plaintext and return as-is.
            return value
        }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return String(data: decrypted, encoding: .utf8) ?? value
        } catch {
            // Decryption failed (different key, truncated data, etc.) — pass through.
            return value
        }
    }
}
