import CryptoKit
import Foundation
import Security

/// Shared AES-GCM encryption/decryption helpers for the sensitive `billing_rate`
/// field. Both `JobsService` (write path) and `ReportsService` (read path) use
/// these helpers so that the Keychain-backed key is managed in exactly one place.
enum BillingRateCrypto {

    // MARK: - Keychain-backed symmetric key

    /// Device-specific AES-GCM key persisted in the Keychain.
    /// Generated once on first launch and reused thereafter, so ciphertext
    /// written by `JobsService` can always be decrypted by any other service.
    static let encryptionKey: SymmetricKey = {
        let service = "com.wiredpart.billing-rate-encryption-key"
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
        // Generate a new 256-bit key. SecRandomCopyBytes must succeed; a zero key
        // would be catastrophically insecure, so we hard-fail on generation error.
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let rngStatus = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard rngStatus == errSecSuccess else {
            fatalError("SecRandomCopyBytes failed (OSStatus \(rngStatus)) — cannot generate a secure billing-rate encryption key")
        }
        let keyData = Data(keyBytes)
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecValueData: keyData,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess && addStatus != errSecDuplicateItem {
            // Key generated but not persisted — encrypted values will be unreadable
            // after app restart. errSecDuplicateItem is benign (race on first launch).
            print("BillingRateCrypto: SecItemAdd failed (OSStatus \(addStatus)) — key in memory only; encrypted billing rates will not survive app restart.")
        }
        return SymmetricKey(data: keyData)
    }()

    // MARK: - Encrypt / Decrypt

    /// Encrypts a `Double` to a Base64-encoded AES-GCM ciphertext string.
    /// Returns `nil` when `value` is `nil`. Throws `BillingRateCryptoError.encryptionFailed`
    /// if the sealed box cannot produce a combined representation.
    static func encrypt(_ value: Double?) throws -> String? {
        guard let value else { return nil }
        let plaintext = String(value)
        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: encryptionKey)
        guard let combined = sealedBox.combined else {
            throw BillingRateCryptoError.encryptionFailed
        }
        return combined.base64EncodedString()
    }

    /// Decrypts a Base64-encoded AES-GCM ciphertext back to a `Double`.
    /// Returns `nil` when `ciphertext` is `nil` or if decryption fails,
    /// so callers can fall back to the legacy plaintext column gracefully.
    static func decrypt(_ ciphertext: String?) -> Double? {
        guard let ciphertext,
              let combined = Data(base64Encoded: ciphertext),
              let sealedBox = try? AES.GCM.SealedBox(combined: combined),
              let plainData = try? AES.GCM.open(sealedBox, using: encryptionKey),
              let plainString = String(data: plainData, encoding: .utf8) else { return nil }
        return Double(plainString)
    }

    /// Convenience helper: decrypt `encrypted` and fall back to `legacy` for rows
    /// written before migration 077 (when billing_rate was a plain numeric column).
    static func decryptOrFallback(encrypted: String?, legacy: Double?) -> Double? {
        decrypt(encrypted) ?? legacy
    }

    // MARK: - Errors

    enum BillingRateCryptoError: Error {
        case encryptionFailed
    }
}
