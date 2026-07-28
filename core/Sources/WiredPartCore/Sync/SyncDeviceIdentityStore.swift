import CryptoKit
import Foundation

#if canImport(Security)
import Security
#endif

public struct SyncDeviceIdentity: Codable, Sendable, Equatable {
    public let privateKeyB64: String
    public let publicKeyB64: String

    public init(privateKeyB64: String, publicKeyB64: String) {
        self.privateKeyB64 = privateKeyB64
        self.publicKeyB64 = publicKeyB64
    }
}

public protocol SyncDeviceIdentityStoring: Sendable {
    func loadOrCreateIdentity(deviceId: String) throws -> SyncDeviceIdentity
}

/// Deterministic injectable storage for tests and non-Apple SwiftPM hosts.
public final class InMemorySyncDeviceIdentityStore: SyncDeviceIdentityStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let seededIdentity: SyncDeviceIdentity?
    private var identities: [String: SyncDeviceIdentity] = [:]

    public init(identity: SyncDeviceIdentity? = nil) {
        self.seededIdentity = identity
    }

    public func loadOrCreateIdentity(deviceId: String) throws -> SyncDeviceIdentity {
        lock.lock()
        defer { lock.unlock() }

        if let identity = identities[deviceId] {
            return identity
        }
        let identity: SyncDeviceIdentity
        if let seededIdentity {
            identity = seededIdentity
        } else {
            let pair = SyncCrypto.generateKeyAgreementPair()
            identity = SyncDeviceIdentity(
                privateKeyB64: pair.privateKey,
                publicKeyB64: pair.publicKey
            )
        }
        try Self.validate(identity)
        identities[deviceId] = identity
        return identity
    }

    fileprivate static func validate(_ identity: SyncDeviceIdentity) throws {
        guard let privateKeyData = Data(base64Encoded: identity.privateKeyB64),
              let publicKeyData = Data(base64Encoded: identity.publicKeyB64),
              privateKeyData.count == 32,
              publicKeyData.count == 32 else {
            throw SyncIdentityStoreError.invalidStoredIdentity
        }

        let privateKey: Curve25519.KeyAgreement.PrivateKey
        do {
            privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        } catch {
            throw SyncIdentityStoreError.invalidStoredIdentity
        }
        guard privateKey.publicKey.rawRepresentation == publicKeyData else {
            throw SyncIdentityStoreError.invalidStoredIdentity
        }
    }
}

/// Stores the local device's long-lived X25519 identity outside the sync database.
///
/// Apple platforms use a this-device-only Keychain item keyed by the local device id.
/// Keychain read/write failures are surfaced to the caller; silently rotating to an
/// ephemeral key would invalidate every pairing-pinned peer relationship.
public final class PlatformSyncDeviceIdentityStore: SyncDeviceIdentityStoring, @unchecked Sendable {
    public static let shared = PlatformSyncDeviceIdentityStore()

    private let lock = NSLock()
    #if !canImport(Security)
    private let fallback = InMemorySyncDeviceIdentityStore()
    #endif

    public init() {}

    public func loadOrCreateIdentity(deviceId: String) throws -> SyncDeviceIdentity {
        guard !deviceId.isEmpty else {
            throw SyncIdentityStoreError.invalidDeviceId
        }

        #if canImport(Security)
        lock.lock()
        defer { lock.unlock() }

        if let stored = try loadFromKeychain(deviceId: deviceId) {
            try InMemorySyncDeviceIdentityStore.validate(stored)
            return stored
        }

        let pair = SyncCrypto.generateKeyAgreementPair()
        let identity = SyncDeviceIdentity(
            privateKeyB64: pair.privateKey,
            publicKeyB64: pair.publicKey
        )
        try InMemorySyncDeviceIdentityStore.validate(identity)
        try saveToKeychain(identity, deviceId: deviceId)
        return identity
        #else
        return try fallback.loadOrCreateIdentity(deviceId: deviceId)
        #endif
    }

    #if canImport(Security)
    private func keychainQuery(deviceId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.wiredpart.sync.x25519.identity",
            kSecAttrAccount as String: deviceId,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func loadFromKeychain(deviceId: String) throws -> SyncDeviceIdentity? {
        var query = keychainQuery(deviceId: deviceId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return try Self.decodeKeychainRead(status: status, item: item)
    }

    /// Decodes the direct Keychain result without providing an identity fallback.
    /// Internal for a no-Keychain-mutation regression of the fail-closed branch.
    static func decodeKeychainRead(
        status: OSStatus,
        item: CFTypeRef?
    ) throws -> SyncDeviceIdentity? {
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SyncIdentityStoreError.keychainReadFailed(Int32(status))
        }
        do {
            return try JSONDecoder().decode(SyncDeviceIdentity.self, from: data)
        } catch {
            throw SyncIdentityStoreError.invalidStoredIdentity
        }
    }

    private func saveToKeychain(_ identity: SyncDeviceIdentity, deviceId: String) throws {
        let data = try JSONEncoder().encode(identity)
        var query = keychainQuery(deviceId: deviceId)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        try Self.completeKeychainWrite(addStatus: addStatus) {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            return SecItemUpdate(
                keychainQuery(deviceId: deviceId) as CFDictionary,
                attributes as CFDictionary
            )
        }
    }

    /// Completes an add-first Keychain write, replacing a matching item when one already exists.
    /// Internal so tests can exercise the duplicate-item branch without mutating the host Keychain.
    static func completeKeychainWrite(
        addStatus: OSStatus,
        updateExisting: () -> OSStatus
    ) throws {
        let finalStatus = addStatus == errSecDuplicateItem ? updateExisting() : addStatus
        guard finalStatus == errSecSuccess else {
            throw SyncIdentityStoreError.keychainWriteFailed(Int32(finalStatus))
        }
    }
    #endif
}

public enum SyncIdentityStoreError: Error, Equatable {
    case invalidDeviceId
    case invalidStoredIdentity
    case keychainReadFailed(Int32)
    case keychainWriteFailed(Int32)
}
