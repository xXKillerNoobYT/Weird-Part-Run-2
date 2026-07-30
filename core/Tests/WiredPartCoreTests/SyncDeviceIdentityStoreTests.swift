import Testing

#if canImport(Security)
import Security
@testable import WiredPartCore

@Suite("Sync Device Identity Store Tests")
struct SyncDeviceIdentityStoreTests {
    @Test("Duplicate Keychain add updates the existing identity")
    func duplicateKeychainAddUpdatesExistingIdentity() throws {
        var updateAttempts = 0

        try PlatformSyncDeviceIdentityStore.completeKeychainWrite(
            addStatus: errSecDuplicateItem
        ) {
            updateAttempts += 1
            return errSecSuccess
        }

        #expect(updateAttempts == 1)
    }

    @Test("Duplicate Keychain add surfaces update failure")
    func duplicateKeychainAddSurfacesUpdateFailure() {
        let expectedStatus = errSecAuthFailed

        do {
            try PlatformSyncDeviceIdentityStore.completeKeychainWrite(
                addStatus: errSecDuplicateItem
            ) {
                expectedStatus
            }
            Issue.record("Expected the duplicate-item update failure to be surfaced")
        } catch {
            #expect(
                error as? SyncIdentityStoreError == .keychainWriteFailed(Int32(expectedStatus))
            )
        }
    }

    @Test("Keychain read failure remains visible instead of creating a fallback identity")
    func keychainReadFailureRemainsFailClosed() {
        let expectedStatus = errSecMissingEntitlement

        do {
            _ = try PlatformSyncDeviceIdentityStore.decodeKeychainRead(
                status: expectedStatus,
                item: nil
            )
            Issue.record("Expected Keychain read failure to remain visible")
        } catch {
            #expect(
                error as? SyncIdentityStoreError == .keychainReadFailed(Int32(expectedStatus))
            )
        }
    }
}
#endif
