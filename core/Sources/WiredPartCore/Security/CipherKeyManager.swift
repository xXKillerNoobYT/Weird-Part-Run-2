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
        // Keychain-less environments: local Catalyst builds without
        // entitlements AND the iPad app running on Apple Silicon Macs, where
        // SecItem calls fail with errSecMissingEntitlement (-34018). The
        // fallback was originally compiled ONLY for Catalyst, so iPad-on-Mac
        // had no rescue path and the app could never start there (owner
        // field report 2026-08-02, build 39, Mac14_13: "Still will not
        // start"). The fallback is now a RUNTIME decision on every platform;
        // a real iPhone/iPad never reaches it because its keychain works.
        // The file name keeps its historical "catalyst-" prefix so existing
        // Catalyst installs keep their salt — and their decryptable DBs.
        if let fallback = try readFallbackSalt() {
            return fallback
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
        } catch CipherKeyError.keychainAccessFailed(let status)
            where status != errSecInteractionNotAllowed {
            // FIELD P0 (owner, 2026-08-04, builds 41 AND 47 both dead on Mac):
            // the previous version rescued only errSecMissingEntitlement and
            // errSecNotAvailable — an ALLOWLIST. The iPad-on-Mac keychain
            // rejects the write with a different status (errSecParam is the
            // documented one for iOS accessibility classes on Mac, and the
            // add query sets kSecAttrAccessible on this build), so the rescue
            // never fired and the app could not open its database at all.
            //
            // Inverted to a DENYLIST, which is the correct shape: the sandbox
            // fallback is safe wherever the keychain is genuinely unusable,
            // and only ONE status is dangerous — errSecInteractionNotAllowed
            // means "temporarily locked, try later", where minting a second
            // salt would orphan an existing encrypted database. That one still
            // throws.
            Self.logger.warning("CipherKeyManager: keychain unusable (OSStatus \(status)) — using sandbox fallback salt")
            try writeFallbackSalt(salt)
            return salt
        } catch {
            // Any other write failure (e.g. errSecAuthFailed) — surface the
            // original error directly so callers get the real failure reason.
            throw error
        }
    }

    /// Delete the persisted salt (use only during device wipe / factory reset).
    public func deleteSalt() {
        if Self.isRunningUnderTestBundle {
            Self.clearProcessLocalTestSalt()
            return
        }

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

    private static func clearProcessLocalTestSalt() {
        testSaltLock.lock()
        defer { testSaltLock.unlock() }
        testSalt = nil
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

    /// True on Catalyst AND on the iPad binary running on Apple Silicon —
    /// the environment TestFlight actually delivers to Macs.
    static var isRunningOnMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif canImport(UIKit)
        return ProcessInfo.processInfo.isiOSAppOnMac
        #else
        return false
        #endif
    }

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
        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: Self.keychainAccount,
            kSecValueData: salt
        ]
        // Catalyst AND iPad-on-Mac keychains can reject iOS accessibility
        // classes with errSecParam, so the attribute is omitted on any Mac
        // (2026-08-04: the compile-time Catalyst check missed iPad-on-Mac,
        // which is what TestFlight actually ships to Macs — the #1622 lesson).
        if !Self.isRunningOnMac {
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
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

    private func catalystFallbackSaltURL() throws -> URL {
        guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CipherKeyError.keychainAccessFailed(errSecParam)
        }
        let dir = supportURL.appendingPathComponent("WiredPart", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("catalyst-dbcipher-salt.bin")
    }

    private func readFallbackSalt() throws -> Data? {
        let url = try catalystFallbackSaltURL()
        guard let data = try? Data(contentsOf: url), data.count == 32 else {
            return nil
        }
        return data
    }

    private func writeFallbackSalt(_ salt: Data) throws {
        let url = try catalystFallbackSaltURL()
        try salt.write(to: url, options: .atomic)
        // Best-effort: keep the salt out of iCloud/device backups — restoring
        // a backup onto different hardware should trigger re-pairing, not
        // silently carry a decryption salt.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
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
