import Testing
import Foundation
@testable import WiredPartCore

@Suite("PeerManager Tests")
struct PeerManagerTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    @Test("Initial state is not running with empty peers")
    func testInitialState() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let state = await pm.getState()
        #expect(state.running == false)
        #expect(state.syncPort == 0)
        #expect(state.peers.isEmpty)
        #expect(state.lastPeerSyncs.isEmpty)
        #expect(state.syncingWith == nil)
    }

    @Test("isOfficePeer detects office-like names")
    func testIsOfficePeer() {
        let office = DiscoveredPeer(
            deviceId: "dev-1",
            deviceName: "Office Mac",
            companyId: "co",
            host: "10.0.0.1",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(office) == true)

        let shop = DiscoveredPeer(
            deviceId: "dev-2",
            deviceName: "Shop Computer",
            companyId: "co",
            host: "10.0.0.2",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(shop) == true)

        let server = DiscoveredPeer(
            deviceId: "dev-3",
            deviceName: "Main Server",
            companyId: "co",
            host: "10.0.0.3",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(server) == true)

        let phone = DiscoveredPeer(
            deviceId: "dev-4",
            deviceName: "John's iPhone",
            companyId: "co",
            host: "10.0.0.4",
            port: 8080
        )
        #expect(PeerManager.isOfficePeer(phone) == false)
    }

    @Test("enrichChangesWithData includes record_data for INSERT")
    func testEnrichInsert() async throws {
        let db = try freshDB()

        // Insert a user
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Alice', 'hash123', 1)
                """)
        }

        // Create a change log entry for that user
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .insert,
            deviceId: "test-device"
        )

        let pm = PeerManager(db: db)
        let pending = try ChangeTracker.getPendingChanges(db: db)
        let enriched = try await pm.testEnrichChanges(pending)

        #expect(enriched.count == 1)
        #expect(enriched[0].recordData != nil)
        #expect(enriched[0].recordData!.contains("Alice"))
        #expect(enriched[0].operation == "INSERT")
    }

    @Test("enrichChangesWithData skips record_data for DELETE")
    func testEnrichDelete() async throws {
        let db = try freshDB()

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 999,
            operation: .delete,
            deviceId: "test-device"
        )

        let pm = PeerManager(db: db)
        let pending = try ChangeTracker.getPendingChanges(db: db)
        let enriched = try await pm.testEnrichChanges(pending)

        #expect(enriched.count == 1)
        #expect(enriched[0].recordData == nil)
        #expect(enriched[0].operation == "DELETE")
    }

    @Test("Sync with unreachable peer returns failure")
    func testUnreachablePeer() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        // Start peer sync so serverState is set
        try await pm.startPeerSync(
            deviceId: "dev-001",
            deviceName: "Test Device",
            companyId: "test-company"
        )

        let peer = DiscoveredPeer(
            deviceId: "unreachable-dev",
            deviceName: "Unreachable",
            companyId: "test-company",
            host: "127.0.0.1",
            port: 1,  // Connection refused
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)
        #expect(result.success == false)
        #expect(result.error != nil)
        #expect(result.peerDeviceId == "unreachable-dev")

        await pm.stopPeerSync()
    }

    // MARK: - Fix #385: Encryption/Decode Failure Propagation

    @Test("AES-GCM encryption throws with invalid key size (Fix #385)")
    func testEncryptionThrowsWithBadKey() {
        let plain = Data("{\"test\":true}".utf8)
        // 1-byte key is invalid for AES-GCM (needs 16/24/32 bytes)
        let badKeyData = Data([0x42])
        do {
            _ = try SyncCrypto.encryptAESGCM(data: plain, keyData: badKeyData)
            Issue.record("Expected encryptAESGCM to throw with 1-byte key")
        } catch {
            // Expected: encryption failure propagates
        }
    }

    @Test("AES-GCM decryption throws on garbage ciphertext (Fix #385)")
    func testDecryptionThrowsOnGarbage() throws {
        let (privA, _) = SyncCrypto.generateKeyAgreementPair()
        let (_, pubB) = SyncCrypto.generateKeyAgreementPair()
        let keyData = try SyncCrypto.deriveSharedKeyData(ourPrivateKeyB64: privA, theirPublicKeyB64: pubB)

        let garbageData = Data("this is not encrypted at all".utf8)
        do {
            _ = try SyncCrypto.decryptAESGCM(data: garbageData, keyData: keyData)
            Issue.record("Expected decryptAESGCM to throw on garbage ciphertext")
        } catch {
            // Expected: decryption failure propagates instead of returning garbage as plaintext
        }
    }

    @Test("Key derivation throws on invalid base64 peer key (Fix #385)")
    func testKeyDerivationThrowsOnBadPeerKey() {
        let (priv, _) = SyncCrypto.generateKeyAgreementPair()
        do {
            _ = try SyncCrypto.deriveSharedKeyData(
                ourPrivateKeyB64: priv,
                theirPublicKeyB64: "not-valid-base64!!!"
            )
            Issue.record("Expected deriveSharedKeyData to throw on invalid base64")
        } catch {
            // Expected: key derivation failure propagates instead of silent fallback to unencrypted
        }
    }

    @Test("Sync with peer where server is down reports failure not false success (Fix #385)")
    func testSyncWithDownPeerReportsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "dev-385",
            deviceName: "Test Device",
            companyId: "test-company"
        )

        // Peer on a port that will refuse connection
        let peer = DiscoveredPeer(
            deviceId: "down-peer",
            deviceName: "Down Peer",
            companyId: "test-company",
            host: "127.0.0.1",
            port: 1,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)
        // Must report failure, not false success
        #expect(result.success == false)
        #expect(result.error != nil)
        #expect(result.pushed == 0)
        #expect(result.pulled == 0)

        await pm.stopPeerSync()
    }

    @Test("PeerSyncResult stores all fields correctly")
    func testPeerSyncResult() {
        let result = PeerSyncResult(
            peerDeviceId: "dev-123",
            peerName: "Test Peer",
            pushed: 5,
            pulled: 3,
            success: true
        )
        #expect(result.peerDeviceId == "dev-123")
        #expect(result.peerName == "Test Peer")
        #expect(result.pushed == 5)
        #expect(result.pulled == 3)
        #expect(result.success == true)
        #expect(result.error == nil)
        #expect(!result.syncedAt.isEmpty)
    }
}

// Test helper to expose private enrich method
extension PeerManager {
    func testEnrichChanges(_ entries: [ChangeLogEntry]) throws -> [IncomingChange] {
        try enrichChangesWithData(entries)
    }

}
