import Foundation
import CryptoKit
import Security

/// Device-local AES-GCM encryption for sensitive database fields (email, phone, etc.).
///
/// The symmetric key is generated once per device and persisted in the Keychain under
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. On first launch a cryptographically
/// random 256-bit key is created and stored; subsequent launches reuse the same key so
/// ciphertext survives app restarts.
///
/// This follows the same Keychain-persistence pattern as `AuthService.signingKey`.
enum FieldEncryption {

    // MARK: - Keychain-backed symmetric key

    /// Device-specific 256-bit key, persisted in the Keychain so encrypted field values
    /// survive app restarts. Never falls back to a constant — if the key cannot be
    /// persisted it is still used for the lifetime of the process (same graceful-degradation
    /// pattern used by `AuthService.signingKey`).
    static let key: SymmetricKey = {
        let service = "com.wiredpart.field-encryption-key"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // Generate a new cryptographically random 256-bit key.
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let keyData = Data(keyBytes)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            // Key generated but not persisted — ciphertext will not survive app restart.
            // errSecDuplicateItem is benign (item was added between our read and write).
        }
        return SymmetricKey(data: keyData)
    }()

    // MARK: - Encrypt / Decrypt

    /// Encrypt an optional plaintext string using AES-GCM with the device-specific Keychain key.
    ///
    /// - Returns the input unchanged when `value` is `nil` or empty (preserves `nil` semantics
    ///   for optional columns).
    /// - Returns a base64-encoded AES-GCM sealed box (nonce + ciphertext + tag) otherwise.
    /// - Throws `SyncCrypto.CryptoError.encryptionFailed` if the sealed box cannot produce
    ///   combined bytes (should never happen in practice with CryptoKit AES.GCM).
    static func encrypt(_ value: String?) throws -> String? {
        guard let value, !value.isEmpty else { return value }
        let sealed = try AES.GCM.seal(Data(value.utf8), using: key)
        guard let combined = sealed.combined else {
            throw SyncCrypto.CryptoError.encryptionFailed
        }
        return combined.base64EncodedString()
    }

    /// Decrypt a base64-encoded AES-GCM ciphertext produced by `encrypt(_:)`.
    ///
    /// - Returns the input unchanged when `value` is `nil` or empty.
    /// - Returns the original plaintext on success.
    /// - Returns the original value as-is on any decryption failure (invalid base64, wrong key,
    ///   or a row that was stored as plaintext before encryption was enabled). This ensures a
    ///   seamless transition from existing plaintext rows.
    static func decrypt(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return value }
        guard let data = Data(base64Encoded: value),
              let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let plainData = try? AES.GCM.open(sealedBox, using: key),
              let plainText = String(data: plainData, encoding: .utf8) else {
            // Not valid ciphertext — return as-is for backward compatibility with
            // rows written before this encryption was introduced.
            return value
        }
        return plainText
    }
}
