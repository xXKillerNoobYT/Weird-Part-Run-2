import Foundation
import CryptoKit
import Security
import os.log

/// Manages the SQLCipher database key for WiredPart.
///
/// Key derivation: `SHA-256(pin.utf8 || salt)` where `salt` is 32 random bytes
/// stored in the Keychain under `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
/// The resulting hex string is passed to SQLCipher as passphrase material, so
/// SQLCipher still applies its configured PBKDF2 work factor before deriving
/// the database page key.
///
/// - The **salt** ties the key to this specific device (cross-device rainbow tables useless).
/// - The **PIN** can be used for explicit re-key operations if the app adds a
///   pre-open unlock flow. Normal user PIN changes do not re-key the app DB.
/// - The derived passphrase material is never stored — it is re-created each time
///   from PIN + salt.
///
/// Note: The production app DB is encrypted with a random device-bound bootstrap key
/// (`AppCore.deviceBootstrapKeyHex`), not with a PIN-derived key. This class is used
/// for PIN-derived key material in advanced scenarios (e.g. explicit DB re-key tests).
///
/// Usage:
/// ```swift
/// let manager = CipherKeyManager.shared
/// let keyHex  = try manager.deriveKeyHex(pin: "1234")
/// ```
public final class CipherKeyManager: Sendable {

    public static let shared = CipherKeyManager()

    private static let keychainAccount = "wp.dbcipher.salt"
    private static let keychainService = "com.wiredpart.dbcipher"
    private static let logger = Logger(subsystem: "com.wiredpart.core", category: "CipherKeyManager")
    nonisolated(unsafe) private static var testSalt: Data?
    private static let testSaltLock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Derive a 64-character hex key from a PIN string and this device's persisted salt.
    /// - Parameter pin: The user's plaintext PIN.
    /// - Returns: 64-character lowercase hex string suitable as SQLCipher passphrase material.
    /// - Throws: `CipherKeyError.keychainAccessFailed` if the salt cannot be read/written.
    public func deriveKeyHex(pin: String) throws -> String {
        let salt = try loadOrCreateSalt()
        return Self.deriveKey(pin: pin, salt: salt)
    }

    /// Deterministically derive a hex key from a PIN and an explicit salt.
    /// Pure function — no Keychain I/O. Use `deriveKeyHex(pin:)` for the device key.
    /// - Parameters:
    ///   - pin: The user's plaintext PIN.
    ///   - salt: 32-byte (or any length) salt value.
    /// - Returns: 64-character lowercase hex string.
    public static func deriveKey(pin: String, salt: Data) -> String {
        var input = Data(pin.utf8)
        input.append(salt)
        let digest = SHA256.hash(data: input)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Load the persisted device salt from the Keychain, or generate and store a new one.
    /// - Returns: 32-byte `Data` value.
    /// - Throws: `CipherKeyError.keychainAccessFailed` on a hard Keychain failure.
    public func loadOrCreateSalt() throws -> Data {
        // SwiftPM's command-line test runner can block indefinitely on macOS Keychain
        // access when no GUI authorization session is available. Production app code
        // still uses the Keychain path below; tests use a process-local stable salt so
        // key derivation behavior remains deterministic without touching user Keychains.
        if Self.isRunningUnderTestBundle {
            return try Self.loadOrCreateProcessLocalTestSalt()
        }

        // Attempt read first.
        if let existing = readSaltFromKeychain() {
            return existing
        }

        let salt = try Self.generateSalt()

        do {
            try writeSaltToKeychain(salt)
            return salt
        } catch CipherKeyError.keychainAccessFailed(errSecDuplicateItem) {
            // Another thread raced and wrote the salt first. Re-read to get the winner's value
            // so all callers share the same stable salt (different salts → different DB keys →
            // encrypted data becomes unreadable).
            if let existing = readSaltFromKeychain() {
                return existing
            }
            // Duplicate-item write raced but the follow-up re-read also failed.
            Self.logger.error("CipherKeyManager: salt write raced (errSecDuplicateItem) and re-read also failed")
            throw CipherKeyError.keychainAccessFailed(errSecDuplicateItem)
        } catch {
            // Any other write failure (e.g. errSecNotAvailable, errSecAuthFailed) — surface
            // the original error directly so callers get the real failure reason.
            throw error
        }
    }

    /// Delete the persisted salt (use only during device wipe / factory reset).
    public func deleteSalt() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Self.logger.warning("CipherKeyManager: SecItemDelete returned \(status) — salt may persist")
        }
    }

    // MARK: - Private Test Helpers

    private static var isRunningUnderTestBundle: Bool {
        let executablePath = Bundle.main.executablePath ?? ""
        return executablePath.contains(".xctest") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func loadOrCreateProcessLocalTestSalt() throws -> Data {
        testSaltLock.lock()
        defer { testSaltLock.unlock() }
        if let existing = testSalt { return existing }
        let salt = try generateSalt()
        testSalt = salt
        return salt
    }

    private static func generateSalt() throws -> Data {
        // Generate 32 cryptographically-random bytes.
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        guard rc == errSecSuccess else {
            throw CipherKeyError.saltGenerationFailed(rc)
        }
        return Data(bytes)
    }

    // MARK: - Private Keychain Helpers

    private func readSaltFromKeychain() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            return nil
        }
        return data
    }

    private func writeSaltToKeychain(_ salt: Data) throws {
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecValueData: salt,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CipherKeyError.keychainAccessFailed(status)
        }
        // If the item already exists (race condition between two callers), do NOT
        // overwrite it — doing so could change the stored salt, invalidating the
        // derived DB key for all other sessions. Instead, surface the duplicate so
        // loadOrCreateSalt() can re-read and use the already-persisted value.
        if status == errSecDuplicateItem {
            throw CipherKeyError.keychainAccessFailed(status)
        }
    }
}

// MARK: - CipherKeyError

public enum CipherKeyError: Error, Sendable {
    case saltGenerationFailed(OSStatus)
    case bootstrapKeyGenerationFailed(OSStatus)
    case keychainAccessFailed(OSStatus)
    case missingPin
}

extension CipherKeyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .saltGenerationFailed(let code):
            return "Failed to generate cipher salt (OSStatus \(code))."
        case .bootstrapKeyGenerationFailed(let code):
            return "Failed to generate device bootstrap key (OSStatus \(code))."
        case .keychainAccessFailed(let code):
            return "Keychain access failed for cipher salt (OSStatus \(code))."
        case .missingPin:
            return "No PIN available — cannot derive cipher key."
        }
    }
}
