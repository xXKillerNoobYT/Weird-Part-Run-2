import Testing
import Foundation
import GRDB
@testable import WiredPartCore

private final class PairResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SyncPairResponse] = []

    func append(_ response: SyncPairResponse) {
        lock.lock()
        storage.append(response)
        lock.unlock()
    }

    var values: [SyncPairResponse] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class SnapshotAcknowledgementCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FullSyncApplyAcknowledgement] = []

    func append(_ acknowledgement: FullSyncApplyAcknowledgement) {
        lock.lock()
        storage.append(acknowledgement)
        lock.unlock()
    }

    var values: [FullSyncApplyAcknowledgement] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private actor PeerManagerStateCollector {
    private var snapshots: [PeerManagerState] = []
    private var transportErrorWaiter: (message: String, continuation: CheckedContinuation<PeerManagerState, Never>)?

    func append(_ state: PeerManagerState) {
        snapshots.append(state)
        guard let waiter = transportErrorWaiter,
              state.lastTransportError == waiter.message else { return }
        transportErrorWaiter = nil
        waiter.continuation.resume(returning: state)
    }

    func nextTransportError(_ message: String) async -> PeerManagerState {
        if let snapshot = snapshots.first(where: { $0.lastTransportError == message }) {
            return snapshot
        }
        return await withCheckedContinuation { continuation in
            transportErrorWaiter = (message, continuation)
        }
    }
}

private func authenticatedBluetoothPairingFixture(
    requestNonce: String = SyncCrypto.bluetoothPairingRequestNonce()
) throws -> (context: BluetoothPairingAttemptContext, response: SyncPairResponse) {
    let client = SyncCrypto.generateKeyAgreementPair()
    let host = SyncCrypto.generateKeyAgreementPair()
    let code = "ABCD1234"
    let proof = SyncCrypto.bluetoothPairingProof(
        normalizedCode: code,
        expectedHostDeviceId: "host",
        clientDeviceId: "joiner",
        clientPublicKeyB64: client.publicKey,
        requestNonce: requestNonce
    )
    let context = BluetoothPairingAttemptContext(
        protocolVersion: 4,
        expectedHostDeviceId: "host",
        clientDeviceId: "joiner",
        clientPrivateKeyB64: client.privateKey,
        clientPublicKeyB64: client.publicKey,
        normalizedPairingCode: code,
        requestNonce: requestNonce,
        requestPairingProof: proof
    )
    let pairedAt = "2026-07-18T09:00:00Z"
    let token = "snapshot-token"
    let authenticator = try SyncCrypto.bluetoothPairingResponseAuthenticator(
        normalizedCode: code,
        ourPrivateKeyB64: host.privateKey,
        theirPublicKeyB64: client.publicKey,
        protocolVersion: 4,
        requestNonce: requestNonce,
        requestPairingProof: proof,
        accepted: true,
        clientDeviceId: "joiner",
        clientPublicKeyB64: client.publicKey,
        hostDeviceId: "host",
        hostPublicKeyB64: host.publicKey,
        companyId: "company",
        snapshotToken: token,
        pairedAt: pairedAt
    )
    let response = SyncPairResponse(
        accepted: true,
        serverDeviceId: "host",
        companyId: "company",
        pairedAt: pairedAt,
        bluetoothProtocolVersion: 4,
        bluetoothRequestNonce: requestNonce,
        bluetoothRequestPairingProof: proof,
        bluetoothClientDeviceId: "joiner",
        bluetoothClientKeyAgreementPublicKey: client.publicKey,
        bluetoothSnapshotToken: token,
        serverKeyAgreementPublicKey: host.publicKey,
        bluetoothResponseAuthenticator: authenticator
    )
    return (context, response)
}

private func bluetoothPairingAttemptPayload(
    pairingCode: String,
    hostDeviceId: String = "host",
    peerDeviceId: String = "joiner",
    peerName: String = "Joiner"
) throws -> (context: BluetoothPairingAttemptContext, payload: Data) {
    let client = SyncCrypto.generateKeyAgreementPair()
    let nonce = SyncCrypto.bluetoothPairingRequestNonce()
    let normalizedCode = try #require(SyncCrypto.normalizedPairingCode(pairingCode))
    let pairingProof = SyncCrypto.bluetoothPairingProof(
        normalizedCode: normalizedCode,
        expectedHostDeviceId: hostDeviceId,
        clientDeviceId: peerDeviceId,
        clientPublicKeyB64: client.publicKey,
        requestNonce: nonce
    )
    let context = BluetoothPairingAttemptContext(
        protocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
        expectedHostDeviceId: hostDeviceId,
        clientDeviceId: peerDeviceId,
        clientPrivateKeyB64: client.privateKey,
        clientPublicKeyB64: client.publicKey,
        normalizedPairingCode: normalizedCode,
        requestNonce: nonce,
        requestPairingProof: pairingProof
    )
    let payload = try JSONEncoder().encode(SyncPairRequest(
        deviceId: peerDeviceId,
        deviceName: peerName,
        pairingProof: pairingProof,
        platform: "ios",
        bluetoothProtocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
        bluetoothRequestNonce: nonce,
        bluetoothExpectedHostDeviceId: hostDeviceId,
        keyAgreementPublicKey: client.publicKey
    ))
    return (context, payload)
}

private func bluetoothPairRequestPayload(
    pairingCode: String,
    hostDeviceId: String = "host",
    peerDeviceId: String = "joiner",
    peerName: String = "Joiner"
) throws -> Data {
    try bluetoothPairingAttemptPayload(
        pairingCode: pairingCode,
        hostDeviceId: hostDeviceId,
        peerDeviceId: peerDeviceId,
        peerName: peerName
    ).payload
}

private func expectTrustSnapshot(
    _ actual: PeerDeviceTrustSnapshot?,
    equals expected: PeerDeviceTrustSnapshot?
) throws {
    let actual = try #require(actual)
    let expected = try #require(expected)
    #expect(actual.deviceName == expected.deviceName)
    #expect(actual.platform == expected.platform)
    #expect(actual.role == expected.role)
    #expect(actual.certificate == expected.certificate)
    #expect(actual.lastSeenAt == expected.lastSeenAt)
    #expect(actual.lastSyncAt == expected.lastSyncAt)
    #expect(actual.isTrusted == expected.isTrusted)
    #expect(actual.isDeactivated == expected.isDeactivated)
    #expect(actual.createdAt == expected.createdAt)
}

private func seedPriorTrust(
    in db: AppDatabase,
    peerDeviceId: String = "joiner"
) async throws -> PeerDeviceTrustSnapshot {
    try await db.writer.write { dbConn in
        try dbConn.execute(
            sql: """
                INSERT INTO _device_registry (
                    device_id, device_name, platform, role, certificate,
                    last_seen_at, last_sync_at, is_trusted, is_deactivated, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                peerDeviceId, "Prior Device", "legacy", "viewer", "prior-certificate",
                "2026-06-01T01:02:03Z", "2026-06-02T04:05:06Z", 1, 1,
                "2026-05-01T00:00:00Z",
            ]
        )
    }
    let snapshot = try ChangeTracker.capturePeerDeviceTrust(
        db: db,
        peerId: peerDeviceId
    )
    return try #require(snapshot)
}

@Suite("PeerManager Tests")
struct PeerManagerTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    @Test("Bluetooth startup errors immediately publish the recovery diagnostic")
    func testTransportStartErrorPublishesStateImmediately() async throws {
        let pm = PeerManager(db: try freshDB())
        let collector = PeerManagerStateCollector()
        let message = "BT-SCAN-START — access denied"

        await pm.setOnStateChanged { state in
            Task { await collector.append(state) }
        }
        try await pm.startPeerSync(
            deviceId: "callback-test-device",
            deviceName: "Callback Test Device",
            companyId: "callback-test-company",
            startSyncServer: false
        )
        defer { Task { await pm.stopPeerSync() } }

        async let observedSnapshot = collector.nextTransportError(message)
        await pm.testTriggerConfiguredTransportError(message)
        let snapshot = await observedSnapshot

        #expect(snapshot.lastTransportError == message)
    }

    @Test("iOS unit-test runtime selects injected identity storage")
    func testUnitTestRuntimeUsesInjectedIdentityStore() async throws {
        let store = PeerManager.identityStoreForRuntime(isRunningUnitTests: true)
        #expect(store is InMemorySyncDeviceIdentityStore)

        let pm = PeerManager(db: try freshDB())
        try await pm.startPeerSync(
            deviceId: "test-bundle-device",
            deviceName: "Test Bundle Device",
            companyId: "test-company",
            startMultipeer: false,
            startSyncServer: false
        )
        await pm.stopPeerSync()
    }

    @Test("production runtime continues to select durable Keychain identity storage")
    func testProductionRuntimeUsesPlatformIdentityStore() {
        let store = PeerManager.identityStoreForRuntime(isRunningUnitTests: false)
        #expect(store is PlatformSyncDeviceIdentityStore)
    }

    /// Migration 112 backfills every seeded reference row into _change_log so
    /// pre-trigger data syncs on first contact. Tests that assert on SPECIFIC
    /// change entries clear that backfill first.
    private func clearChangeLog(_ db: AppDatabase) async throws {
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }
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

    @Test("PeerManager reuses injected X25519 identity across restarts")
    func testInjectedIdentityPersistsAcrossPeerManagerRestarts() async throws {
        let db = try freshDB()
        let keys = SyncCrypto.generateKeyAgreementPair()
        let identity = SyncDeviceIdentity(
            privateKeyB64: keys.privateKey,
            publicKeyB64: keys.publicKey
        )
        let store = InMemorySyncDeviceIdentityStore(identity: identity)

        let first = PeerManager(db: db, identityStore: store)
        try await first.startPeerSync(
            deviceId: "device-a",
            deviceName: "Device A",
            companyId: "co-1",
            startMultipeer: false,
            startSyncServer: false
        )
        let firstPublicKey = await first.testCurrentKeyAgreementPublicKey()
        await first.stopPeerSync()

        let second = PeerManager(db: db, identityStore: store)
        try await second.startPeerSync(
            deviceId: "device-a",
            deviceName: "Device A",
            companyId: "co-1",
            startMultipeer: false,
            startSyncServer: false
        )
        let secondPublicKey = await second.testCurrentKeyAgreementPublicKey()
        await second.stopPeerSync()

        #expect(firstPublicKey == keys.publicKey)
        #expect(secondPublicKey == keys.publicKey)
    }

    @Test("Incremental push is deferred while a hosted snapshot is unacknowledged (#1417)")
    func testIncrementalPushDeferredUntilSnapshotAcknowledged() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        try await pm.startPeerSync(
            deviceId: "host-001",
            deviceName: "Host Device",
            companyId: "company-abc",
            allowAnyCompanyPeerDiscovery: true,
            startMultipeer: false,
            startSyncServer: false
        )
        // Simulate a freshly paired joiner: its snapshot token is outstanding
        // (it is only consumed on durable apply acknowledgement).
        await pm.testIssueHostedSnapshotToken("token-123", for: "joiner-9")

        let result = await pm.syncWithPeer(DiscoveredPeer(
            deviceId: "joiner-9",
            deviceName: "New iPad",
            companyId: "company-abc",
            host: "127.0.0.1",
            port: 12345
        ))
        // Deferred: not a success (nothing was pushed), with the honest
        // waiting message — and NOT recorded as a completed sync.
        #expect(result.success == false)
        // Deferral must be distinguishable from failure (#1625 follow-up): the
        // host UI counts !success as a red "Sync failed" otherwise.
        #expect(result.deferred == true)
        #expect(result.error == "Waiting for the new device's initial download to finish.")
        let state = await pm.getState()
        #expect(state.lastPeerSyncs["joiner-9"] == nil)

        await pm.stopPeerSync()
    }

    @Test("Hosted snapshot SKIPS id-less tables instead of aborting the transfer (#field P0 build 44)")
    func testSnapshotSkipsIdlessTables() async throws {
        let db = try freshDB()
        // Synthetic stand-in for warehouse_user_positions (composite/user_id
        // primary key, NO id column) — with a real row, the pre-fix pager
        // threw missingRecordID here and killed the whole company download.
        try await db.writer.write { dbc in
            try dbc.execute(sql: "CREATE TABLE zz_no_id (k TEXT PRIMARY KEY, v TEXT)")
            try dbc.execute(sql: "INSERT INTO zz_no_id (k, v) VALUES ('a', 'b')")
        }
        let page = try await PeerManager.hostedSnapshotPage(
            db: db, table: "zz_no_id", limit: 200, offset: 0,
            hostDeviceId: "host-1", fallbackTimestamp: "2026-08-02T00:00:00Z"
        )
        #expect(page.changes.isEmpty)
        #expect(page.sourceRowCount == 0)   // pager treats it as exhausted, moves on

        // And the production instance: warehouse_user_positions must also skip.
        let prod = try await PeerManager.hostedSnapshotPage(
            db: db, table: "warehouse_user_positions", limit: 200, offset: 0,
            hostDeviceId: "host-1", fallbackTimestamp: "2026-08-02T00:00:00Z"
        )
        #expect(prod.sourceRowCount == 0)

        // A normal id-ful table still pages rows.
        try await db.writer.write { dbc in
            try dbc.execute(sql: "INSERT INTO part_categories (name) VALUES ('Wire')")
        }
        let normal = try await PeerManager.hostedSnapshotPage(
            db: db, table: "part_categories", limit: 200, offset: 0,
            hostDeviceId: "host-1", fallbackTimestamp: "2026-08-02T00:00:00Z"
        )
        #expect(normal.sourceRowCount >= 1)
        #expect(normal.changes.contains { $0.tableName == "part_categories" })
    }

    @Test("Discovery-only peer sync starts browsing without a sync server")
    func testDiscoveryOnlyPeerSyncState() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "dev-001",
            deviceName: "Test Device",
            companyId: "onboarding-test",
            allowAnyCompanyPeerDiscovery: true,
            startMultipeer: false,
            startSyncServer: false
        )

        let state = await pm.getState()
        #expect(state.running)
        #expect(state.syncPort == 0)

        let peer = DiscoveredPeer(
            deviceId: "peer-001",
            deviceName: "Peer Device",
            companyId: "company-abc",
            host: "127.0.0.1",
            port: 12345
        )
        let result = await pm.syncWithPeer(peer)
        #expect(result.success == false)
        #expect(result.error == "Sync server not running")

        await pm.stopPeerSync()
        let stoppedState = await pm.getState()
        #expect(!stoppedState.running)
        #expect(stoppedState.syncPort == 0)
    }

    @Test("Stopping Multipeer discovery preserves LAN peer sync")
    func testStopMultipeerDiscoveryPreservesLanSync() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "dev-001",
            deviceName: "Test Device",
            companyId: "test-company",
            startMultipeer: false
        )

        let runningState = await pm.getState()
        #expect(runningState.running)
        #expect(runningState.syncPort > 0)

        await pm.stopMultipeerDiscovery()

        let lanOnlyState = await pm.getState()
        #expect(lanOnlyState.running)
        #expect(lanOnlyState.syncPort == runningState.syncPort)
        #expect(lanOnlyState.peers.allSatisfy { $0.transport != "multipeer" })

        await pm.stopPeerSync()
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
        try await clearChangeLog(db)

        // Insert a user — the migration-112 triggers log the change
        // automatically (no manual trackChange call needed anymore).
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Alice', 'hash123', 1)
                """)
        }

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
        try await clearChangeLog(db)

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

    @Test("AES-GCM encryption throws with invalid key size")
    func testEncryptionThrowsWithBadKey() {
        #expect(throws: (any Error).self) {
            _ = try SyncCrypto.encryptAESGCM(
                data: Data("{\"test\":true}".utf8),
                keyData: Data([0x42])
            )
        }
    }

    @Test("AES-GCM decryption throws on garbage ciphertext")
    func testDecryptionThrowsOnGarbage() throws {
        let (privA, _) = SyncCrypto.generateKeyAgreementPair()
        let (_, pubB) = SyncCrypto.generateKeyAgreementPair()
        let keyData = try SyncCrypto.deriveSharedKeyData(
            ourPrivateKeyB64: privA,
            theirPublicKeyB64: pubB
        )

        #expect(throws: (any Error).self) {
            _ = try SyncCrypto.decryptAESGCM(
                data: Data("this is not encrypted at all".utf8),
                keyData: keyData
            )
        }
    }

    @Test("Key derivation throws on invalid base64 peer key")
    func testKeyDerivationThrowsOnBadPeerKey() {
        let (priv, _) = SyncCrypto.generateKeyAgreementPair()

        #expect(throws: (any Error).self) {
            _ = try SyncCrypto.deriveSharedKeyData(
                ourPrivateKeyB64: priv,
                theirPublicKeyB64: "not-valid-base64!!!"
            )
        }
    }

    @Test("Malformed key exchange fails closed instead of downgrading to plaintext")
    func testMalformedKeyExchangeFailsClosed() async throws {
        let pm = PeerManager(db: try freshDB())
        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )
        let malformedKeyServer = try HTTPStubServer(
            statusCode: 200,
            body: #"{"not":"a-sync-key-response"}"#
        )
        let port = try await malformedKeyServer.start()

        let result = await pm.syncWithPeer(DiscoveredPeer(
            deviceId: "malformed-key-peer",
            deviceName: "Malformed Key Peer",
            companyId: "local-company",
            host: "127.0.0.1",
            port: port,
            transport: "lan"
        ))

        #expect(result.success == false)
        #expect(result.error?.contains("key") == true)
        malformedKeyServer.stop()
        await pm.stopPeerSync()
    }

    @Test("LAN sync rejects a server key that differs from the pairing-pinned identity")
    func testLANSyncRejectsSpoofedServerKey() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let pinned = SyncCrypto.generateKeyAgreementPair()
        let attacker = SyncCrypto.generateKeyAgreementPair()
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "shop-dev",
            peerName: "Shop",
            platform: "shop",
            keyAgreementPublicKey: pinned.publicKey
        )
        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )
        let keyBody = String(
            data: try JSONEncoder().encode(SyncKeyResponse(key: attacker.publicKey)),
            encoding: .utf8
        )!
        let spoofServer = try HTTPStubServer(statusCode: 200, body: keyBody)
        let port = try await spoofServer.start()

        let result = await pm.syncWithPeer(DiscoveredPeer(
            deviceId: "shop-dev",
            deviceName: "Shop",
            companyId: "local-company",
            host: "127.0.0.1",
            port: port,
            transport: "lan"
        ))

        #expect(result.success == false)
        #expect(result.error?.contains("key") == true)
        spoofServer.stop()
        await pm.stopPeerSync()
    }

    @Test("Sync with a down peer reports failure rather than false success")
    func testSyncWithDownPeerReportsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        try await pm.startPeerSync(
            deviceId: "dev-385",
            deviceName: "Test Device",
            companyId: "test-company"
        )

        let result = await pm.syncWithPeer(DiscoveredPeer(
            deviceId: "down-peer",
            deviceName: "Down Peer",
            companyId: "test-company",
            host: "127.0.0.1",
            port: 1,
            transport: "lan"
        ))

        #expect(result.success == false)
        #expect(result.error != nil)
        #expect(result.pushed == 0)
        #expect(result.pulled == 0)
        await pm.stopPeerSync()
    }

    @Test("Sync by peer device ID does not fall back to all peers")
    func testSyncByPeerDeviceIdRequiresSelectedPeer() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        let result = await pm.syncWithPeer(deviceId: "missing-peer")

        #expect(result.success == false)
        #expect(result.peerDeviceId == "missing-peer")
        #expect(result.error == "Peer not found: missing-peer")

        let state = await pm.getState()
        #expect(state.lastPeerSyncs["missing-peer"]?.success == false)
        #expect(state.lastPeerSyncs.count == 1)
    }

    @Test("LAN sync reports HTTP pull errors as failed peer sync")
    func testLANSyncHTTPPullErrorReturnsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )

        // No pending changes → the push leg is skipped and the PULL error path
        // is what this test exercises (clears the migration-112 backfill).
        try await clearChangeLog(db)

        let (_, stubPublicKey) = SyncCrypto.generateKeyAgreementPair()
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "foreign-dev",
            peerName: "Foreign Device",
            platform: "test",
            keyAgreementPublicKey: stubPublicKey
        )
        let keyBody = String(
            data: try JSONEncoder().encode(SyncKeyResponse(key: stubPublicKey)),
            encoding: .utf8
        )!
        let foreignServer = try HTTPStubServer { request in
            request.path == "/sync/key"
                ? HTTPStubResponse(statusCode: 200, body: keyBody)
                : HTTPStubResponse(statusCode: 403, body: #"{"error":"foreign company"}"#)
        }
        let foreignPort = try await foreignServer.start()

        let peer = DiscoveredPeer(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company",
            host: "127.0.0.1",
            port: foreignPort,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)

        #expect(result.success == false)
        #expect(result.error == "LAN sync pull failed: HTTP 403")
        #expect(result.peerDeviceId == "foreign-dev")

        let state = await pm.getState()
        #expect(state.lastPeerSyncs["foreign-dev"]?.success == false)

        foreignServer.stop()
        await pm.stopPeerSync()
    }

    @Test("LAN sync reports malformed 200 pull responses as failed peer sync")
    func testLANSyncMalformedPullResponseReturnsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )

        let (_, stubPublicKey) = SyncCrypto.generateKeyAgreementPair()
        let keyBody = String(
            data: try JSONEncoder().encode(SyncKeyResponse(key: stubPublicKey)),
            encoding: .utf8
        )!
        let malformedServer = try HTTPStubServer { request in
            request.path == "/sync/key"
                ? HTTPStubResponse(statusCode: 200, body: keyBody)
                : HTTPStubResponse(statusCode: 200, body: #"{"not":"a-sync-pull-response"}"#)
        }
        let port = try await malformedServer.start()

        let peer = DiscoveredPeer(
            deviceId: "malformed-dev",
            deviceName: "Malformed Peer",
            companyId: "local-company",
            host: "127.0.0.1",
            port: port,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)

        #expect(result.success == false)
        #expect(result.error != nil)
        #expect(result.peerDeviceId == "malformed-dev")

        let state = await pm.getState()
        #expect(state.lastPeerSyncs["malformed-dev"]?.success == false)

        malformedServer.stop()
        await pm.stopPeerSync()
    }

    @Test("LAN sync reports key authorization errors as failed peer sync")
    func testLANSyncKeyAuthorizationErrorReturnsFailure() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await clearChangeLog(db)
        // The migration-112 triggers auto-log this insert as the one pending change.
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active)
                VALUES ('Alice', 'hash123', 1)
                """)
        }

        try await pm.startPeerSync(
            deviceId: "local-dev",
            deviceName: "Local Device",
            companyId: "local-company"
        )

        let foreignState = SyncServerState(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company"
        )
        let foreignServer = LanSyncServer(state: foreignState)
        let foreignPort = try await foreignServer.start()

        let peer = DiscoveredPeer(
            deviceId: "foreign-dev",
            deviceName: "Foreign Device",
            companyId: "foreign-company",
            host: "127.0.0.1",
            port: foreignPort,
            transport: "lan"
        )

        let result = await pm.syncWithPeer(peer)

        #expect(result.success == false)
        #expect(result.error == "LAN sync key failed: HTTP 403")
        #expect(result.peerDeviceId == "foreign-dev")
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        await foreignServer.stop()
        await pm.stopPeerSync()
    }

    // MARK: - Bluetooth full-snapshot completion integrity

    #if canImport(MultipeerConnectivity)
    @Test("Full snapshot capability must match the trusted pairing session")
    func testFullSnapshotCapabilityBinding() {
        #expect(BluetoothSnapshotAuthorization.isAuthorized(
            trustedDevice: true,
            providedToken: "pairing-capability",
            expectedToken: "pairing-capability"
        ))
        #expect(!BluetoothSnapshotAuthorization.isAuthorized(
            trustedDevice: true,
            providedToken: "spoofed-capability",
            expectedToken: "pairing-capability"
        ))
        #expect(!BluetoothSnapshotAuthorization.isAuthorized(
            trustedDevice: false,
            providedToken: "pairing-capability",
            expectedToken: "pairing-capability"
        ))
        #expect(!BluetoothSnapshotAuthorization.isAuthorized(
            trustedDevice: true,
            providedToken: "",
            expectedToken: ""
        ))
    }

    @Test("Full snapshot authorization requires a trusted active device")
    func testFullSnapshotRequiresTrustedActiveDevice() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        #expect(try await pm.isTrustedBluetoothPeer("joiner") == false)
        let (_, publicKey) = SyncCrypto.generateKeyAgreementPair()
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "joiner",
            peerName: "Joiner",
            platform: "ios",
            keyAgreementPublicKey: publicKey
        )
        #expect(try await pm.isTrustedBluetoothPeer("joiner") == true)
        try await db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _device_registry SET is_deactivated = 1 WHERE device_id = ?",
                arguments: ["joiner"]
            )
        }
        #expect(try await pm.isTrustedBluetoothPeer("joiner") == false)
    }

    @Test("Snapshot capability is reserved once and never restored after completion acknowledgement")
    func testFullSnapshotCapabilityLifecycle() async throws {
        let pm = PeerManager(db: try freshDB())
        let peer = "joiner"
        let token = "pairing-capability"
        await pm.testIssueHostedSnapshotToken(token, for: peer)

        async let firstReservation = pm.testReserveHostedSnapshot(token: token, for: peer)
        async let duplicateReservation = pm.testReserveHostedSnapshot(token: token, for: peer)
        let reservationResults = await [firstReservation, duplicateReservation]
        #expect(reservationResults.filter { $0 }.count == 1)
        #expect(await pm.testHostedSnapshotIsReserved(for: peer))

        await pm.testAcknowledgeHostedSnapshot(
            token: token,
            for: peer,
            succeeded: false,
            error: "database apply failed"
        )
        #expect(!(await pm.testHostedSnapshotTokenAvailable(token, for: peer)))
        #expect(!(await pm.testHostedSnapshotIsReserved(for: peer)))
        #expect(!(await pm.testReserveHostedSnapshot(token: token, for: peer)))

        await pm.testIssueHostedSnapshotToken(token, for: peer)
        #expect(await pm.testReserveHostedSnapshot(token: token, for: peer))
        await pm.testSetHostedSnapshotRowsSent(42, for: peer)
        await pm.testAcknowledgeHostedSnapshot(token: token, for: peer, succeeded: true)
        #expect(!(await pm.testHostedSnapshotTokenAvailable(token, for: peer)))
        #expect(!(await pm.testHostedSnapshotIsReserved(for: peer)))
        #expect(!(await pm.testReserveHostedSnapshot(token: token, for: peer)))

        let state = await pm.getState()
        #expect(state.lastPeerSyncs[peer]?.success == true)
        #expect(state.lastPeerSyncs[peer]?.pushed == 42)
    }

    @Test("Any snapshot request during a reservation is ignored without disrupting the original transfer")
    func testMismatchedSnapshotRequestCannotDisruptInFlightReservation() async throws {
        let pm = PeerManager(db: try freshDB())
        let peer = "joiner"
        let originalToken = "original-capability"

        await pm.testIssueHostedSnapshotToken(originalToken, for: peer)
        #expect(await pm.testReserveHostedSnapshot(token: originalToken, for: peer))

        // The production request guard is peer-scoped, not token-scoped: both an
        // exact retransmission and a mismatched second request are duplicate traffic.
        #expect(await pm.testHostedSnapshotRequestIsDuplicate(token: originalToken, for: peer))
        #expect(await pm.testHostedSnapshotRequestIsDuplicate(token: "mismatched-capability", for: peer))
        #expect(await pm.testHostedSnapshotIsReserved(for: peer))
        #expect(!(await pm.testHostedSnapshotTokenAvailable(originalToken, for: peer)))

        // A legitimate fresh capability can still start after the original transfer
        // reaches a terminal acknowledgement and pairing issues a retry token.
        await pm.testAcknowledgeHostedSnapshot(
            token: originalToken,
            for: peer,
            succeeded: false,
            error: "joiner apply failed"
        )
        let retryToken = "retry-capability"
        await pm.testIssueHostedSnapshotToken(retryToken, for: peer)
        #expect(await pm.testReserveHostedSnapshot(token: retryToken, for: peer))
        #expect(await pm.testHostedSnapshotIsReserved(for: peer))
    }

    @Test("Snapshot capability restores only before completion send")
    func testSnapshotCapabilityRestorationBoundary() {
        #expect(PeerManager.shouldRestoreHostedSnapshot(
            after: BluetoothSnapshotTransferError.batchSendFailed(table: "users", offset: 0)
        ))
        #expect(!PeerManager.shouldRestoreHostedSnapshot(
            after: BluetoothSnapshotTransferError.completionSendFailed
        ))
    }

    @Test("Transport shutdown restores a pre-completion snapshot capability")
    func testTransportShutdownRestoresPreCompletionSnapshotCapability() async throws {
        let pm = PeerManager(db: try freshDB())
        let peer = "joiner"
        let token = "retryable-capability"
        await pm.testIssueHostedSnapshotToken(token, for: peer)
        #expect(await pm.testReserveHostedSnapshot(token: token, for: peer))

        await pm.stopMultipeerDiscovery()

        #expect(await pm.testHostedSnapshotTokenAvailable(token, for: peer))
        #expect(!(await pm.testHostedSnapshotIsReserved(for: peer)))
        #expect(await pm.testReserveHostedSnapshot(token: token, for: peer))
    }

    @Test("Transport shutdown keeps a post-completion snapshot capability consumed")
    func testTransportShutdownKeepsPostCompletionSnapshotCapabilityConsumed() async throws {
        let pm = PeerManager(db: try freshDB())
        let peer = "joiner"
        let token = "consumed-capability"
        await pm.testIssueHostedSnapshotToken(token, for: peer)
        #expect(await pm.testReserveHostedSnapshot(token: token, for: peer))
        await pm.testSetHostedSnapshotRowsSent(42, for: peer)

        await pm.stopMultipeerDiscovery()

        #expect(!(await pm.testHostedSnapshotTokenAvailable(token, for: peer)))
        #expect(!(await pm.testHostedSnapshotIsReserved(for: peer)))
        #expect(!(await pm.testReserveHostedSnapshot(token: token, for: peer)))
    }

    @Test("Bluetooth pairing wire format distinguishes capability protocol clients from legacy clients")
    func testBluetoothPairingProtocolVersionWireFormat() throws {
        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let current = SyncPairRequest(
            deviceId: "joiner",
            deviceName: "Joiner",
            pairingProof: "proof",
            platform: "ios",
            bluetoothProtocolVersion: 4,
            bluetoothRequestNonce: nonce,
            bluetoothExpectedHostDeviceId: "host"
        )
        let currentRoundTrip = try JSONDecoder().decode(
            SyncPairRequest.self,
            from: JSONEncoder().encode(current)
        )
        #expect(currentRoundTrip.bluetoothProtocolVersion == 4)
        #expect(currentRoundTrip.bluetoothRequestNonce == nonce)
        #expect(currentRoundTrip.bluetoothExpectedHostDeviceId == "host")
        #expect(currentRoundTrip.pairingCode == nil)

        let legacy = try JSONDecoder().decode(
            SyncPairRequest.self,
            from: Data(#"{"device_id":"legacy","device_name":"Legacy","pairing_code":"ABCD-1234","platform":"ios"}"#.utf8)
        )
        #expect(legacy.bluetoothProtocolVersion == nil)
    }

    @Test("Bluetooth host rejects non-v4 requests without consuming the fresh pairing offer")
    func testBluetoothHostRejectsOldProtocolWithoutConsumingOffer() async throws {
        let pm = PeerManager(db: try freshDB())
        try await pm.startPeerSync(deviceId: "host", deviceName: "Host", companyId: "company")
        let code = try await pm.issuePairingCode()
        let normalizedCode = try #require(SyncCrypto.normalizedPairingCode(code))
        let client = SyncCrypto.generateKeyAgreementPair()
        let responses = PairResponseCollector()

        func request(
            version: Int? = 4,
            nonce: String? = SyncCrypto.bluetoothPairingRequestNonce(),
            expectedHost: String? = "host",
            clientKey: String? = nil,
            proofOverride: String? = nil
        ) -> SyncPairRequest {
            let proofNonce = nonce ?? SyncCrypto.bluetoothPairingRequestNonce()
            let proofKey = clientKey ?? client.publicKey
            let proofHost = expectedHost ?? "host"
            return SyncPairRequest(
                deviceId: "joiner",
                deviceName: "Joiner",
                pairingProof: proofOverride ?? SyncCrypto.bluetoothPairingProof(
                    normalizedCode: normalizedCode,
                    expectedHostDeviceId: proofHost,
                    clientDeviceId: "joiner",
                    clientPublicKeyB64: proofKey,
                    requestNonce: proofNonce
                ),
                platform: "ios",
                bluetoothProtocolVersion: version,
                bluetoothRequestNonce: nonce,
                bluetoothExpectedHostDeviceId: expectedHost,
                keyAgreementPublicKey: proofKey
            )
        }

        let invalidRequests = [
            request(version: 3),
            request(version: nil),
            request(version: 5),
            request(nonce: nil),
            request(nonce: "malformed-nonce"),
            request(expectedHost: "other-host"),
            request(clientKey: "malformed-client-key"),
            request(proofOverride: "wrong-proof")
        ]
        for invalidRequest in invalidRequests {
            let payload = try JSONEncoder().encode(invalidRequest)
            await pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
                responses.append(response)
                return true
            }
            #expect(responses.values.last?.accepted == false)
            #expect(try await pm.isTrustedBluetoothPeer("joiner") == false)
        }

        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let validPayload = try JSONEncoder().encode(request(nonce: nonce))
        await pm.processBluetoothPairRequest(from: "joiner", payload: validPayload) { response in
            responses.append(response)
            return true
        }

        #expect(responses.values.last?.accepted == true)
        #expect(try await pm.isTrustedBluetoothPeer("joiner"))
        await pm.stopPeerSync()
    }

    @Test("Bluetooth response verification precedes trust/token mutation and rejects replay")
    func testBluetoothResponseVerificationPersistenceAndReplayBoundary() async throws {
        let fixture = try authenticatedBluetoothPairingFixture()
        let otherKey = SyncCrypto.generateKeyAgreementPair()
        let mutations: [(String, (inout SyncPairResponse) -> Void)] = [
            ("host id", { $0.serverDeviceId = "other-host" }),
            ("host key", { $0.serverKeyAgreementPublicKey = otherKey.publicKey }),
            ("client id", { $0.bluetoothClientDeviceId = "other-client" }),
            ("client key", { $0.bluetoothClientKeyAgreementPublicKey = otherKey.publicKey }),
            ("company", { $0.companyId = "other-company" }),
            ("snapshot token", { $0.bluetoothSnapshotToken = "other-token" }),
            ("nonce", { $0.bluetoothRequestNonce = SyncCrypto.bluetoothPairingRequestNonce() }),
            ("request proof", { $0.bluetoothRequestPairingProof = "other-proof" }),
            ("version", { $0.bluetoothProtocolVersion = 5 }),
            ("paired at", { $0.pairedAt = "2026-07-18T09:00:01Z" }),
            ("missing authenticator", { $0.bluetoothResponseAuthenticator = nil }),
            ("malformed authenticator", { $0.bluetoothResponseAuthenticator = "not-base64" })
        ]

        for (field, mutate) in mutations {
            let forgedPM = PeerManager(db: try freshDB())
            var forged = fixture.response
            mutate(&forged)
            do {
                _ = try await forgedPM.acceptBluetoothPairingResponse(
                    forged,
                    context: fixture.context,
                    peerName: "Host"
                )
                Issue.record("Expected tampered \(field) response to fail")
            } catch {
                // Expected: no mutation may precede response verification.
            }
            #expect(try await forgedPM.isTrustedBluetoothPeer("host") == false)
            #expect(await forgedPM.testReceivedSnapshotToken(from: "host") == nil)
        }

        let invalidContexts = [
            BluetoothPairingAttemptContext(
                protocolVersion: fixture.context.protocolVersion,
                expectedHostDeviceId: fixture.context.expectedHostDeviceId,
                clientDeviceId: fixture.context.clientDeviceId,
                clientPrivateKeyB64: fixture.context.clientPrivateKeyB64,
                clientPublicKeyB64: fixture.context.clientPublicKeyB64,
                normalizedPairingCode: "WXYZ1234",
                requestNonce: fixture.context.requestNonce,
                requestPairingProof: fixture.context.requestPairingProof
            ),
            BluetoothPairingAttemptContext(
                protocolVersion: fixture.context.protocolVersion,
                expectedHostDeviceId: fixture.context.expectedHostDeviceId,
                clientDeviceId: fixture.context.clientDeviceId,
                clientPrivateKeyB64: otherKey.privateKey,
                clientPublicKeyB64: fixture.context.clientPublicKeyB64,
                normalizedPairingCode: fixture.context.normalizedPairingCode,
                requestNonce: fixture.context.requestNonce,
                requestPairingProof: fixture.context.requestPairingProof
            )
        ]
        for context in invalidContexts {
            let forgedPM = PeerManager(db: try freshDB())
            await #expect(throws: MultipeerPairingError.self) {
                try await forgedPM.acceptBluetoothPairingResponse(
                    fixture.response,
                    context: context,
                    peerName: "Host"
                )
            }
            #expect(try await forgedPM.isTrustedBluetoothPeer("host") == false)
            #expect(await forgedPM.testReceivedSnapshotToken(from: "host") == nil)
        }

        let validPM = PeerManager(db: try freshDB())
        _ = try await validPM.acceptBluetoothPairingResponse(
            fixture.response,
            context: fixture.context,
            peerName: "Host"
        )
        #expect(try await validPM.isTrustedBluetoothPeer("host"))
        #expect(await validPM.testReceivedSnapshotToken(from: "host") == "snapshot-token")

        let replayPM = PeerManager(db: try freshDB())
        let freshAttempt = try authenticatedBluetoothPairingFixture()
        #expect(freshAttempt.context.requestNonce != fixture.context.requestNonce)
        await #expect(throws: MultipeerPairingError.self) {
            try await replayPM.acceptBluetoothPairingResponse(
                fixture.response,
                context: freshAttempt.context,
                peerName: "Host"
            )
        }
        #expect(try await replayPM.isTrustedBluetoothPeer("host") == false)
        #expect(await replayPM.testReceivedSnapshotToken(from: "host") == nil)
    }

    @Test("Transport shutdown resumes pending pairing and full-sync continuations with an error")
    func testTransportShutdownResumesPendingContinuations() async throws {
        let pm = PeerManager(db: try freshDB())
        let pairingTask = Task {
            try await pm.testAwaitPairingTransport(peerDeviceId: "pair-peer")
        }
        let fullSyncTask = Task {
            try await pm.testAwaitFullSyncTransport(peerDeviceId: "sync-peer")
        }

        while await pm.testPendingTransportOperationCount() < 2 {
            await Task.yield()
        }
        await pm.stopMultipeerDiscovery()

        for task in [pairingTask, fullSyncTask] {
            do {
                try await task.value
                Issue.record("Expected transport shutdown to fail the pending operation")
            } catch MultipeerPairingError.transportStopped {
                // Expected: every checked continuation is resumed exactly once.
            } catch {
                Issue.record("Unexpected shutdown error: \(error)")
            }
        }
        #expect(await pm.testPendingTransportOperationCount() == 0)
    }

    @Test("A stale pairing timeout cannot remove a newer attempt for the same host")
    func testStalePairingTimeoutDoesNotOwnReplacementAttempt() async throws {
        let pm = PeerManager(db: try freshDB())
        let firstNonce = SyncCrypto.bluetoothPairingRequestNonce()
        let secondNonce = SyncCrypto.bluetoothPairingRequestNonce()
        let firstTask = Task {
            try await pm.testAwaitPairingTransport(
                peerDeviceId: "host",
                requestNonce: firstNonce
            )
        }
        while await pm.testPendingPairingNonce(for: "host") != firstNonce {
            await Task.yield()
        }
        try await pm.testResolvePairingTransport(
            SyncPairResponse(
                accepted: false,
                serverDeviceId: "host",
                companyId: "",
                pairedAt: "",
                bluetoothProtocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
                bluetoothRequestNonce: firstNonce
            ),
            from: "host"
        )
        try await firstTask.value

        let secondTask = Task {
            try await pm.testAwaitPairingTransport(
                peerDeviceId: "host",
                requestNonce: secondNonce
            )
        }
        while await pm.testPendingPairingNonce(for: "host") != secondNonce {
            await Task.yield()
        }

        await pm.testTimeoutPairing(peerDeviceId: "host", requestNonce: firstNonce)
        #expect(await pm.testPendingPairingNonce(for: "host") == secondNonce)
        try await pm.testResolvePairingTransport(
            SyncPairResponse(
                accepted: false,
                serverDeviceId: "host",
                companyId: "",
                pairedAt: "",
                bluetoothProtocolVersion: SyncCrypto.bluetoothPairingProtocolVersion,
                bluetoothRequestNonce: secondNonce
            ),
            from: "host"
        )
        try await secondTask.value
        #expect(await pm.testPendingPairingNonce(for: "host") == nil)
    }

    @Test("Pairing task cancellation removes only its owned attempt")
    func testPairingCancellationRemovesOwnedAttempt() async throws {
        let pm = PeerManager(db: try freshDB())
        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let task = Task {
            try await pm.testAwaitPairingTransport(peerDeviceId: "host", requestNonce: nonce)
        }
        while await pm.testPendingPairingNonce(for: "host") != nonce {
            await Task.yield()
        }

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(await pm.testPendingPairingNonce(for: "host") == nil)
    }

    @Test("Bluetooth activation failure rejects before either peer commits and permits retry")
    func testBluetoothActivationFailureRejectsBeforeEitherPeerCommitsAndPermitsRetry() async throws {
        let hostDB = try freshDB()
        let joinerDB = try freshDB()
        let host = PeerManager(db: hostDB)
        let joiner = PeerManager(db: joinerDB)
        try await host.startPeerSync(deviceId: "host", deviceName: "Host", companyId: "company")
        let attempt = try bluetoothPairingAttemptPayload(pairingCode: try await host.issuePairingCode())
        let responses = PairResponseCollector()

        #expect(try ChangeTracker.capturePeerDeviceTrust(db: hostDB, peerId: "joiner") == nil)
        #expect(try ChangeTracker.capturePeerDeviceTrust(db: joinerDB, peerId: "host") == nil)
        await host.processBluetoothPairRequest(
            from: "joiner",
            payload: attempt.payload,
            injectActivationFailure: true
        ) { response in
            responses.append(response)
            return true
        }

        let rejected = try #require(responses.values.last)
        #expect(rejected.accepted == false)
        await #expect(throws: MultipeerPairingError.self) {
            try await joiner.acceptBluetoothPairingResponse(
                rejected,
                context: attempt.context,
                peerName: "Host"
            )
        }
        #expect(try ChangeTracker.capturePeerDeviceTrust(db: hostDB, peerId: "joiner") == nil)
        #expect(try ChangeTracker.capturePeerDeviceTrust(db: joinerDB, peerId: "host") == nil)
        #expect(try await host.isTrustedBluetoothPeer("joiner") == false)
        #expect(try await joiner.isTrustedBluetoothPeer("host") == false)
        #expect(await joiner.testReceivedSnapshotToken(from: "host") == nil)

        // The restored pairing offer permits a fresh, authenticated retry without
        // trusting either peer until both sides receive the committed transition.
        await host.processBluetoothPairRequest(from: "joiner", payload: attempt.payload) { response in
            responses.append(response)
            return true
        }
        let accepted = try #require(responses.values.last)
        #expect(accepted.accepted == true)
        _ = try await joiner.acceptBluetoothPairingResponse(
            accepted,
            context: attempt.context,
            peerName: "Host"
        )
        #expect(try await host.isTrustedBluetoothPeer("joiner"))
        #expect(try await joiner.isTrustedBluetoothPeer("host"))
        #expect(await host.testHostedSnapshotTokenAvailable(
            try #require(accepted.bluetoothSnapshotToken),
            for: "joiner"
        ))
        #expect(await joiner.testReceivedSnapshotToken(from: "host") == accepted.bluetoothSnapshotToken)
        await host.stopPeerSync()
    }

    @Test("Injected Bluetooth activation failure preserves the exact prior row and token")
    func testBluetoothActivationFailurePreservesPriorStateByDatabaseReadback() async throws {
        let db = try freshDB()
        let before = try await seedPriorTrust(in: db)
        let pm = PeerManager(db: db)
        try await pm.startPeerSync(deviceId: "host", deviceName: "Host", companyId: "company")
        let priorToken = "prior-hosted-token"
        await pm.testIssueHostedSnapshotToken(priorToken, for: "joiner")
        let payload = try bluetoothPairRequestPayload(pairingCode: try await pm.issuePairingCode())

        await pm.processBluetoothPairRequest(
            from: "joiner",
            payload: payload,
            injectActivationFailure: true
        ) { _ in true }

        let after = try ChangeTracker.capturePeerDeviceTrust(db: db, peerId: "joiner")
        try expectTrustSnapshot(after, equals: before)
        #expect(await pm.testHostedSnapshotTokenAvailable(priorToken, for: "joiner"))
        await pm.stopPeerSync()
    }

    @Test("Undelivered Bluetooth pairing restores prior trust, token, and pairing code")
    func testUndeliveredBluetoothPairingRollsBack() async throws {
        let db = try freshDB()
        let before = try await seedPriorTrust(in: db)
        let pm = PeerManager(db: db)
        try await pm.startPeerSync(deviceId: "host", deviceName: "Host", companyId: "company")
        let pairingCode = try await pm.issuePairingCode()
        let oldToken = "existing-token"
        await pm.testIssueHostedSnapshotToken(oldToken, for: "joiner")
        let (_, peerKey) = SyncCrypto.generateKeyAgreementPair()
        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let payload = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "joiner",
            deviceName: "Joiner",
            pairingProof: SyncCrypto.bluetoothPairingProof(
                normalizedCode: try #require(SyncCrypto.normalizedPairingCode(pairingCode)),
                expectedHostDeviceId: "host",
                clientDeviceId: "joiner",
                clientPublicKeyB64: peerKey,
                requestNonce: nonce
            ),
            platform: "ios",
            bluetoothProtocolVersion: 4,
            bluetoothRequestNonce: nonce,
            bluetoothExpectedHostDeviceId: "host",
            keyAgreementPublicKey: peerKey
        ))
        let responses = PairResponseCollector()

        await pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
            responses.append(response)
            return false
        }

        #expect(responses.values.last?.accepted == true)
        #expect(await pm.testHostedSnapshotTokenAvailable(oldToken, for: "joiner"))
        try expectTrustSnapshot(
            ChangeTracker.capturePeerDeviceTrust(db: db, peerId: "joiner"),
            equals: before
        )

        await pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
            responses.append(response)
            return true
        }

        let delivered = try #require(responses.values.last)
        #expect(delivered.accepted == true)
        #expect(try await pm.isTrustedBluetoothPeer("joiner") == true)
        #expect(await pm.testHostedSnapshotTokenAvailable(
            try #require(delivered.bluetoothSnapshotToken),
            for: "joiner"
        ))
        await pm.stopPeerSync()
    }

    @Test("Bluetooth authenticator generation failure restores trust, token, and pairing offer")
    func testBluetoothAuthenticatorFailureRollsBackPreparation() async throws {
        let db = try freshDB()
        let before = try await seedPriorTrust(in: db)
        let pm = PeerManager(db: db)
        try await pm.startPeerSync(deviceId: "host", deviceName: "Host", companyId: "company")
        let pairingCode = try await pm.issuePairingCode()
        let normalizedCode = try #require(SyncCrypto.normalizedPairingCode(pairingCode))
        let client = SyncCrypto.generateKeyAgreementPair()
        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let payload = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "joiner",
            deviceName: "Joiner",
            pairingProof: SyncCrypto.bluetoothPairingProof(
                normalizedCode: normalizedCode,
                expectedHostDeviceId: "host",
                clientDeviceId: "joiner",
                clientPublicKeyB64: client.publicKey,
                requestNonce: nonce
            ),
            platform: "ios",
            bluetoothProtocolVersion: 4,
            bluetoothRequestNonce: nonce,
            bluetoothExpectedHostDeviceId: "host",
            keyAgreementPublicKey: client.publicKey
        ))
        let responses = PairResponseCollector()
        await pm.testIssueHostedSnapshotToken("prior-token", for: "joiner")
        await pm.testSetKeyAgreementIdentity(
            privateKeyB64: "malformed-private-key",
            publicKeyB64: SyncCrypto.generateKeyAgreementPair().publicKey
        )

        await pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
            responses.append(response)
            return true
        }

        #expect(responses.values.last?.accepted == false)
        #expect(await pm.testHostedSnapshotTokenAvailable("prior-token", for: "joiner"))
        try expectTrustSnapshot(
            ChangeTracker.capturePeerDeviceTrust(db: db, peerId: "joiner"),
            equals: before
        )

        let validHost = SyncCrypto.generateKeyAgreementPair()
        await pm.testSetKeyAgreementIdentity(
            privateKeyB64: validHost.privateKey,
            publicKeyB64: validHost.publicKey
        )
        await pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
            responses.append(response)
            return true
        }
        #expect(responses.values.last?.accepted == true)
        #expect(try await pm.isTrustedBluetoothPeer("joiner"))
        await pm.stopPeerSync()
    }

    @Test("Bluetooth pairing code reservation accepts only one concurrent request")
    func testBluetoothPairingCodeReservationIsAtomic() async throws {
        let pm = PeerManager(db: try freshDB())
        try await pm.startPeerSync(deviceId: "host", deviceName: "Host", companyId: "company")
        let pairingCode = try await pm.issuePairingCode()
        let (_, peerKey) = SyncCrypto.generateKeyAgreementPair()
        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let payload = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "joiner",
            deviceName: "Joiner",
            pairingProof: SyncCrypto.bluetoothPairingProof(
                normalizedCode: try #require(SyncCrypto.normalizedPairingCode(pairingCode)),
                expectedHostDeviceId: "host",
                clientDeviceId: "joiner",
                clientPublicKeyB64: peerKey,
                requestNonce: nonce
            ),
            platform: "ios",
            bluetoothProtocolVersion: 4,
            bluetoothRequestNonce: nonce,
            bluetoothExpectedHostDeviceId: "host",
            keyAgreementPublicKey: peerKey
        ))
        let responses = PairResponseCollector()

        async let first: Void = pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
            responses.append(response)
            return true
        }
        async let second: Void = pm.processBluetoothPairRequest(from: "joiner", payload: payload) { response in
            responses.append(response)
            return true
        }
        _ = await (first, second)

        #expect(responses.values.filter(\.accepted).count == 1)
        #expect(responses.values.filter { !$0.accepted }.count == 1)
        await pm.stopPeerSync()
    }
    #endif

    /// The build-62 field failure: the Mac showed "connected" then
    /// "Sync with iPhone failed" while the joiner sat around a quarter of the
    /// download. A transient Multipeer flap made one `send` return `false`, and
    /// the loop aborted the entire company transfer on that single batch.
    ///
    /// A batch that fails once must be re-attempted, not fatal.
    @Test("A transient send failure is retried, not fatal (#1580 build 62)")
    func testSnapshotTransferRetriesTransientSendFailure() async throws {
        let change = IncomingChange(
            deviceId: "host", tableName: "users", recordId: "1",
            operation: "INSERT", changedFields: "{\"id\":\"1\"}", timestamp: "2026-08-09T00:00:00Z"
        )
        var attempts = 0
        var pagesServed = 0

        let sent = try await BluetoothSnapshotTransfer.run(
            maxSendAttempts: 4,
            interBatchPause: .zero,
            sleep: { _ in },                       // no real waiting in tests
            listTables: { ["users"] },
            readPage: { _, _, _ in
                pagesServed += 1
                return pagesServed == 1
                    ? BluetoothSnapshotPage(changes: [change], sourceRowCount: 1)
                    : BluetoothSnapshotPage(changes: [], sourceRowCount: 0)
            },
            encode: { _ in Data([0x01]) },
            send: { _ in
                attempts += 1
                return attempts >= 3          // fails twice, then the session recovers
            }
        )

        #expect(sent == 1, "the batch should have landed after the session recovered")
        #expect(attempts == 3, "expected two failed attempts then a success")
    }

    /// Retries are bounded — a genuinely dead session still fails, and it fails
    /// naming the table and offset rather than hanging forever.
    @Test("A permanently dead session still fails, with the table and offset (#1580)")
    func testSnapshotTransferGivesUpOnPermanentSendFailure() async {
        let change = IncomingChange(
            deviceId: "host", tableName: "users", recordId: "1",
            operation: "INSERT", changedFields: "{\"id\":\"1\"}", timestamp: "2026-08-09T00:00:00Z"
        )
        var attempts = 0

        await #expect(throws: BluetoothSnapshotTransferError.self) {
            _ = try await BluetoothSnapshotTransfer.run(
                maxSendAttempts: 3,
                interBatchPause: .zero,
                sleep: { _ in },
                listTables: { ["users"] },
                readPage: { _, _, _ in BluetoothSnapshotPage(changes: [change], sourceRowCount: 1) },
                encode: { _ in Data([0x01]) },
                send: { _ in
                    attempts += 1
                    return false
                }
            )
        }
        #expect(attempts == 3, "should stop at maxSendAttempts rather than retrying forever")
    }

    @Test("Snapshot transfer fails when table enumeration fails")
    func testSnapshotTableEnumerationFailurePropagates() async {
        await #expect(throws: SnapshotProbeError.self) {
            _ = try await BluetoothSnapshotTransfer.run(
                listTables: { throw SnapshotProbeError.injected },
                readPage: { _, _, _ in BluetoothSnapshotPage(changes: [], sourceRowCount: 0) },
                encode: { _ in Data() },
                send: { _ in true }
            )
        }
    }

    @Test("Snapshot transfer fails when a page read fails")
    func testSnapshotPageReadFailurePropagates() async {
        await #expect(throws: SnapshotProbeError.self) {
            _ = try await BluetoothSnapshotTransfer.run(
                listTables: { ["users"] },
                readPage: { _, _, _ in throw SnapshotProbeError.injected },
                encode: { _ in Data() },
                send: { _ in true }
            )
        }
    }

    @Test("Snapshot transfer fails when a batch cannot encode")
    func testSnapshotBatchEncodingFailurePropagates() async {
        let change = snapshotUserChange(recordId: "1")
        await #expect(throws: SnapshotProbeError.self) {
            _ = try await BluetoothSnapshotTransfer.run(
                listTables: { ["users"] },
                readPage: { _, _, _ in BluetoothSnapshotPage(changes: [change], sourceRowCount: 1) },
                encode: { _ in throw SnapshotProbeError.injected },
                send: { _ in true }
            )
        }
    }

    @Test("Snapshot transfer fails when a batch send fails")
    func testSnapshotBatchSendFailurePropagates() async {
        let change = snapshotUserChange(recordId: "1")
        await #expect(throws: BluetoothSnapshotTransferError.self) {
            _ = try await BluetoothSnapshotTransfer.run(
                listTables: { ["users"] },
                readPage: { _, _, _ in BluetoothSnapshotPage(changes: [change], sourceRowCount: 1) },
                encode: { _ in Data("batch".utf8) },
                send: { _ in false }
            )
        }
    }

    @Test("Snapshot transfer counts only successfully sent batches")
    func testSnapshotTransferCountsSuccessfulBatches() async throws {
        let changes = [snapshotUserChange(recordId: "1"), snapshotUserChange(recordId: "2")]
        let sent = try await BluetoothSnapshotTransfer.run(
            listTables: { ["users"] },
            readPage: { _, _, _ in BluetoothSnapshotPage(changes: changes, sourceRowCount: changes.count) },
            encode: { try JSONEncoder().encode($0) },
            send: { _ in true }
        )
        #expect(sent == 2)
    }

    #if canImport(MultipeerConnectivity)
    @Test("Full-sync completion is processed only after the preceding batch is durable")
    func testFullSyncBatchAppliesBeforeCompletion() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let changesData = try JSONEncoder().encode([snapshotUserChange(recordId: "7001")])
        let changesEnvelope = try JSONEncoder().encode(MPEnvelope(type: "changes", payload: changesData))
        let completionEnvelope = try JSONEncoder().encode(
            MPEnvelope(type: "fullSyncComplete", payload: try JSONEncoder().encode(FullSyncCompletion.success))
        )
        await pm.testBeginSnapshotBuffer(from: "host")

        let applied = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: changesEnvelope)
        )
        #expect(applied == .changesApplied(1))
        let persisted = try await db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT display_name FROM users WHERE id = 7001")
        }
        #expect(persisted == nil, "snapshot pages must remain uncommitted until completion")

        let completed = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: completionEnvelope)
        )
        #expect(completed == .fullSyncCompleted)
        let durableAfterCompletion = try await db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT display_name FROM users WHERE id = 7001")
        }
        #expect(durableAfterCompletion == "Snapshot User")
    }

    @Test("A failed full-sync batch is visible and cannot advance completion")
    func testFullSyncApplyFailurePropagates() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let valid = snapshotUserChange(recordId: "7002")
        let databaseFailure = IncomingChange(
            deviceId: "host",
            tableName: "users",
            recordId: "7003",
            operation: "INSERT",
            recordData: #"{"id":7003,"display_name":"Invalid","pin_hash":"hash","is_active":1,"not_a_real_column":"boom"}"#,
            timestamp: "2026-07-15T00:00:00Z"
        )
        let validEnvelope = try JSONEncoder().encode(
            MPEnvelope(type: "changes", payload: try JSONEncoder().encode([valid]))
        )
        let failingEnvelope = try JSONEncoder().encode(
            MPEnvelope(type: "changes", payload: try JSONEncoder().encode([databaseFailure]))
        )
        let completionEnvelope = try JSONEncoder().encode(
            MPEnvelope(type: "fullSyncComplete", payload: try JSONEncoder().encode(FullSyncCompletion.success))
        )
        await pm.testBeginSnapshotBuffer(from: "host")

        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: validEnvelope)
        )
        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: failingEnvelope)
        )

        await #expect(throws: (any Error).self) {
            _ = try await pm.testProcessMultipeerMessage(
                ReceivedMultipeerMessage(fromDeviceId: "host", data: completionEnvelope)
            )
        }
        await pm.testAbandonSnapshotBuffer(from: "host")

        let latePage = try JSONEncoder().encode(
            MPEnvelope(
                type: "changes",
                payload: try JSONEncoder().encode([snapshotUserChange(recordId: "7004")])
            )
        )
        let lateOutcome = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: latePage)
        )
        #expect(lateOutcome == .ignored)

        let committedPrefix = try await db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM users WHERE id IN (7002, 7003, 7004)") ?? 0
        }
        #expect(
            committedPrefix == 0,
            "a failed later snapshot page must roll back earlier pages and quarantine queued remainder"
        )
    }

    @Test("Atomic apply failure negatively acknowledges, releases reservation, and requires fresh authorization")
    func testAtomicApplyFailureReleasesHostReservationAndRequiresFreshAuthorization() async throws {
        let host = PeerManager(db: try freshDB())
        let joiner = PeerManager(db: try freshDB())
        let peer = "joiner"
        let hostDeviceId = "host"
        let consumedToken = "consumed-capability"

        try await host.startPeerSync(deviceId: hostDeviceId, deviceName: "Host", companyId: "company")
        await host.testIssueHostedSnapshotToken(consumedToken, for: peer)
        #expect(await host.testReserveHostedSnapshot(token: consumedToken, for: peer))
        await host.testSetHostedSnapshotRowsSent(1, for: peer)

        await joiner.testAuthorizeReceivedSnapshot(consumedToken, from: hostDeviceId)
        await joiner.testBeginSnapshotBuffer(from: hostDeviceId)
        let fullSyncWaiter = Task {
            try await joiner.testAwaitFullSyncTransport(peerDeviceId: hostDeviceId)
        }
        while await joiner.testPendingTransportOperationCount() == 0 {
            await Task.yield()
        }

        let validEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "changes",
            payload: try JSONEncoder().encode([snapshotUserChange(recordId: "7101")])
        ))
        let invalidChange = IncomingChange(
            deviceId: hostDeviceId,
            tableName: "users",
            recordId: "7102",
            operation: "INSERT",
            recordData: #"{"id":7102,"display_name":"Invalid","pin_hash":"hash","is_active":1,"not_a_real_column":"boom"}"#,
            timestamp: "2026-07-15T00:00:00Z"
        )
        let invalidEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "changes",
            payload: try JSONEncoder().encode([invalidChange])
        ))
        let completionEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "fullSyncComplete",
            payload: try JSONEncoder().encode(FullSyncCompletion.success)
        ))
        let acknowledgements = SnapshotAcknowledgementCollector()

        await #expect(throws: (any Error).self) {
            _ = try await joiner.testProcessMultipeerMessagesInFIFO(
                [
                    ReceivedMultipeerMessage(fromDeviceId: hostDeviceId, data: validEnvelope),
                    ReceivedMultipeerMessage(fromDeviceId: hostDeviceId, data: invalidEnvelope),
                    ReceivedMultipeerMessage(fromDeviceId: hostDeviceId, data: completionEnvelope),
                ],
                sendApplyAcknowledgement: { acknowledgement, destination in
                    #expect(destination == hostDeviceId)
                    acknowledgements.append(acknowledgement)
                    return true
                }
            )
        }
        await #expect(throws: (any Error).self) {
            try await fullSyncWaiter.value
        }

        let negativeAcknowledgement = try #require(acknowledgements.values.first)
        #expect(acknowledgements.values.count == 1)
        #expect(negativeAcknowledgement.authorizationToken == consumedToken)
        #expect(negativeAcknowledgement.succeeded == false)
        #expect(negativeAcknowledgement.error?.isEmpty == false)

        let acknowledgementEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "fullSyncApplied",
            payload: try JSONEncoder().encode(negativeAcknowledgement)
        ))
        _ = try await host.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: peer, data: acknowledgementEnvelope)
        )
        #expect(!(await host.testHostedSnapshotIsReserved(for: peer)))
        #expect(!(await host.testHostedSnapshotTokenAvailable(consumedToken, for: peer)))
        #expect(!(await host.testReserveHostedSnapshot(token: consumedToken, for: peer)))
        #expect(await host.getState().lastPeerSyncs[peer]?.success == false)

        let pairingCode = try await host.issuePairingCode()
        let (_, peerKey) = SyncCrypto.generateKeyAgreementPair()
        let nonce = SyncCrypto.bluetoothPairingRequestNonce()
        let pairRequest = try JSONEncoder().encode(SyncPairRequest(
            deviceId: peer,
            deviceName: "Joiner",
            pairingProof: SyncCrypto.bluetoothPairingProof(
                normalizedCode: try #require(SyncCrypto.normalizedPairingCode(pairingCode)),
                expectedHostDeviceId: hostDeviceId,
                clientDeviceId: peer,
                clientPublicKeyB64: peerKey,
                requestNonce: nonce
            ),
            platform: "ios",
            bluetoothProtocolVersion: 4,
            bluetoothRequestNonce: nonce,
            bluetoothExpectedHostDeviceId: hostDeviceId,
            keyAgreementPublicKey: peerKey
        ))
        let responses = PairResponseCollector()
        await host.processBluetoothPairRequest(from: peer, payload: pairRequest) { response in
            responses.append(response)
            return true
        }
        let freshToken = try #require(responses.values.first?.bluetoothSnapshotToken)
        #expect(responses.values.count == 1)
        #expect(freshToken != consumedToken)

        async let firstFreshReservation = host.testReserveHostedSnapshot(token: freshToken, for: peer)
        async let duplicateFreshReservation = host.testReserveHostedSnapshot(token: freshToken, for: peer)
        let freshReservationResults = await [firstFreshReservation, duplicateFreshReservation]
        #expect(freshReservationResults.filter { $0 }.count == 1)
        await host.stopPeerSync()
    }

    // MARK: - Durable snapshot staging (WEI-7022)

    /// The memory fix, proven where it matters: every batch is on DISK the
    /// moment it is accepted, not accumulating in the actor. A real company is
    /// hundreds of thousands of rows, and holding them all as decoded
    /// `IncomingChange` objects is what makes iOS jetsam-kill the joiner
    /// mid-download — a failure mode indistinguishable from a dropped link.
    ///
    /// The all-or-nothing contract has to survive the change, so this also
    /// pins the two invariants that protect it: nothing is visible in the real
    /// tables before completion, and everything is visible after it.
    @Test("A large snapshot stages durably and applies in full on completion (WEI-7022)")
    func testLargeSnapshotStagesDurablyThenAppliesAtomically() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let batchSize = 200
        let batchCount = 6
        let totalRecords = batchSize * batchCount

        await pm.testBeginSnapshotBuffer(from: "host")

        var staged = 0
        for batch in 0..<batchCount {
            let changes = (0..<batchSize).map {
                snapshotUserChange(recordId: String(20_000 + batch * batchSize + $0))
            }
            let envelope = try JSONEncoder().encode(
                MPEnvelope(type: "changes", payload: try JSONEncoder().encode(changes))
            )
            let outcome = try await pm.testProcessMultipeerMessage(
                ReceivedMultipeerMessage(fromDeviceId: "host", data: envelope)
            )
            #expect(outcome == .changesApplied(batchSize))
            staged += batchSize

            // Durability, batch by batch: the rows are queryable from the
            // database, not merely retained by the actor.
            #expect(try await pm.testStagedSnapshotRowCount(for: "host") == staged)
            // The progress UI reads this; it must track the durable count.
            #expect(await pm.getState().snapshotReceivedRecords["host"] == staged)
        }

        let visibleBeforeCompletion = try await db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM users WHERE id >= 20000") ?? 0
        }
        #expect(
            visibleBeforeCompletion == 0,
            "staged rows must not reach the real tables before completion"
        )

        let completionEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "fullSyncComplete",
            payload: try JSONEncoder().encode(FullSyncCompletion.success)
        ))
        let completed = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: completionEnvelope)
        )
        #expect(completed == .fullSyncCompleted)

        let applied = try await db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM users WHERE id >= 20000") ?? 0
        }
        #expect(applied == totalRecords, "every staged record must be applied")
        #expect(
            try await pm.testStagedSnapshotRowCount(for: "host") == 0,
            "staging must be cleared once the snapshot is applied and acknowledged"
        )
        #expect(!(await pm.testIsStagingSnapshot(from: "host")))
    }

    /// Injected failure AFTER staging, BEFORE apply — the exact window the
    /// staging table introduces. A poisoned record cannot be detected until it
    /// is replayed, so the guarantee has to come from the transaction: the
    /// company must be entirely absent afterwards, never partially populated.
    ///
    /// A half-populated company is the worst outcome available. It looks like a
    /// successful onboarding to every screen in the app.
    @Test("A failure between staging and apply leaves no partial company data (WEI-7022)")
    func testStagedSnapshotFailureLeavesNoPartialCompanyData() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let hostDeviceId = "host"

        await pm.testAuthorizeReceivedSnapshot("staging-token", from: hostDeviceId)
        await pm.testBeginSnapshotBuffer(from: hostDeviceId)
        let waiter = Task { try await pm.testAwaitFullSyncTransport(peerDeviceId: hostDeviceId) }
        while await pm.testPendingTransportOperationCount() == 0 {
            await Task.yield()
        }

        // 500 perfectly good records...
        let goodChanges = (0..<500).map { snapshotUserChange(recordId: String(30_000 + $0)) }
        let goodEnvelope = try JSONEncoder().encode(
            MPEnvelope(type: "changes", payload: try JSONEncoder().encode(goodChanges))
        )
        // ...then one that only fails when it is actually applied.
        let poisoned = IncomingChange(
            deviceId: hostDeviceId,
            tableName: "users",
            recordId: "30999",
            operation: "INSERT",
            recordData: #"{"id":30999,"display_name":"Invalid","pin_hash":"hash","is_active":1,"not_a_real_column":"boom"}"#,
            timestamp: "2026-07-15T00:00:00Z"
        )
        let poisonedEnvelope = try JSONEncoder().encode(
            MPEnvelope(type: "changes", payload: try JSONEncoder().encode([poisoned]))
        )
        let completionEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "fullSyncComplete",
            payload: try JSONEncoder().encode(FullSyncCompletion.success)
        ))

        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: hostDeviceId, data: goodEnvelope)
        )
        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: hostDeviceId, data: poisonedEnvelope)
        )
        // Everything staged cleanly — the failure is still ahead of us.
        #expect(try await pm.testStagedSnapshotRowCount(for: hostDeviceId) == 501)

        let acknowledgements = SnapshotAcknowledgementCollector()
        await #expect(throws: (any Error).self) {
            _ = try await pm.testProcessMultipeerMessagesInFIFO(
                [ReceivedMultipeerMessage(fromDeviceId: hostDeviceId, data: completionEnvelope)],
                sendApplyAcknowledgement: { acknowledgement, _ in
                    acknowledgements.append(acknowledgement)
                    return true
                }
            )
        }
        await #expect(throws: (any Error).self) { try await waiter.value }

        let visible = try await db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM users WHERE id >= 30000") ?? 0
        }
        #expect(
            visible == 0,
            "the 500 valid staged records must roll back with the poisoned one"
        )
        // The host is told before it waits out its timeout, and never records
        // a success against a joiner that stored nothing.
        #expect(acknowledgements.values.first?.succeeded == false)
        // Failure clears staging: a retry starts from a clean slate.
        #expect(try await pm.testStagedSnapshotRowCount(for: hostDeviceId) == 0)
        #expect(!(await pm.testIsStagingSnapshot(from: hostDeviceId)))
    }

    /// A snapshot that dies mid-transfer can leave rows behind — a jetsam kill
    /// is exactly that scenario, and it is the one durable staging is meant to
    /// survive. The next attempt must not replay them: mixing two snapshots
    /// produces a company assembled from two different points in time.
    @Test("A second snapshot from the same peer discards leftover staging (WEI-7022)")
    func testSecondSnapshotDoesNotMixWithLeftoverStaging() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        // Simulate the wreckage of a previous, killed transfer.
        let leftoverPayloads: [String] = try (0..<3).map { seq in
            let data = try JSONEncoder().encode(snapshotUserChange(recordId: String(40_000 + seq)))
            return try #require(String(data: data, encoding: .utf8))
        }
        try await db.writer.write { dbConn in
            for (seq, payload) in leftoverPayloads.enumerated() {
                try dbConn.execute(
                    sql: """
                        INSERT INTO _snapshot_staging (peer_device_id, seq, payload)
                        VALUES (?, ?, ?)
                        """,
                    arguments: ["host", seq, payload]
                )
            }
        }
        #expect(try await pm.testStagedSnapshotRowCount(for: "host") == 3)

        // A fresh snapshot begins for the SAME peer.
        await pm.testBeginSnapshotBuffer(from: "host")
        #expect(
            try await pm.testStagedSnapshotRowCount(for: "host") == 0,
            "beginning a snapshot must discard the previous attempt's rows"
        )

        let envelope = try JSONEncoder().encode(MPEnvelope(
            type: "changes",
            payload: try JSONEncoder().encode([snapshotUserChange(recordId: "41000")])
        ))
        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: envelope)
        )
        let completionEnvelope = try JSONEncoder().encode(MPEnvelope(
            type: "fullSyncComplete",
            payload: try JSONEncoder().encode(FullSyncCompletion.success)
        ))
        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host", data: completionEnvelope)
        )

        let leftoverApplied = try await db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM users WHERE id >= 40000 AND id < 41000") ?? 0
        }
        let currentApplied = try await db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM users WHERE id = 41000") ?? 0
        }
        #expect(leftoverApplied == 0, "leftover staging must never be replayed")
        #expect(currentApplied == 1, "the current snapshot must still apply in full")
    }

    /// Staging is scratch space for ONE in-flight transfer. A timeout is the
    /// silent path — nothing throws, nothing is logged by the caller — so it
    /// needs its own proof that the rows do not survive.
    @Test("Snapshot staging is cleared on timeout and on transport shutdown (WEI-7022)")
    func testSnapshotStagingClearedOnTimeoutAndShutdown() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)
        let envelope = try JSONEncoder().encode(MPEnvelope(
            type: "changes",
            payload: try JSONEncoder().encode([snapshotUserChange(recordId: "50001")])
        ))

        // 1. Idle-watchdog timeout.
        await pm.testBeginSnapshotBuffer(from: "host-a")
        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host-a", data: envelope)
        )
        #expect(try await pm.testStagedSnapshotRowCount(for: "host-a") == 1)
        await pm.testTimeoutFullSync(with: "host-a")
        #expect(try await pm.testStagedSnapshotRowCount(for: "host-a") == 0)
        #expect(await pm.getState().snapshotReceivedRecords["host-a"] == nil)

        // 2. Transport shutdown, which fails every pending operation at once.
        await pm.testBeginSnapshotBuffer(from: "host-b")
        _ = try await pm.testProcessMultipeerMessage(
            ReceivedMultipeerMessage(fromDeviceId: "host-b", data: envelope)
        )
        #expect(try await pm.testStagedSnapshotRowCount(for: "host-b") == 1)
        await pm.testFailPendingTransportOperations()
        #expect(
            try await pm.testTotalStagedSnapshotRowCount() == 0,
            "transport shutdown must leave no staged rows for any peer"
        )
    }

    /// The staging table is sync INFRASTRUCTURE. If it ever became a synced
    /// table it would replicate one device's half-finished download to the rest
    /// of the company — and, being id-keyed, would do so silently.
    ///
    /// This also proves migration 122 is actually REGISTERED. A migration
    /// that is defined but never wired into the migrator does nothing at all,
    /// and the failure is invisible until a query hits a missing table.
    @Test("Snapshot staging exists, is indexed, and never syncs (WEI-7022)")
    func testSnapshotStagingIsRegisteredInfrastructureAndNeverSyncs() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        let tableExists = try db.writer.read { dbConn in
            try Bool.fetchOne(dbConn, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM sqlite_master
                    WHERE type = 'table' AND name = '_snapshot_staging'
                )
                """) ?? false
        }
        #expect(tableExists, "migration 122 is not registered in the migrator")

        let indexExists = try db.writer.read { dbConn in
            try Bool.fetchOne(dbConn, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM sqlite_master
                    WHERE type = 'index' AND name = 'idx_snapshot_staging_peer_seq'
                )
                """) ?? false
        }
        #expect(indexExists, "ordered replay and per-peer clear both need this index")

        #expect(!ConflictResolver.isAllowedTable("_snapshot_staging"))
        #expect(!ConflictResolver.allowedSyncTables.contains("_snapshot_staging"))

        let triggerCount = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type = 'trigger' AND tbl_name = '_snapshot_staging'
                """) ?? 0
        }
        #expect(triggerCount == 0, "staging writes must never enter the change log")
    }
    #endif

    @Test("LAN sync base URL is built from host and discovered port")
    func testLANSyncBaseURLUsesPeerHostAndPort() throws {
        let peer = DiscoveredPeer(
            deviceId: "dev-url",
            deviceName: "Office Mac",
            companyId: "co",
            host: "192.168.1.50",
            port: 51943
        )

        let baseURL = try PeerManager.makeLANSyncBaseURL(for: peer)

        #expect(baseURL.absoluteString == "http://192.168.1.50:51943")
        #expect(baseURL.appendingPathComponent("sync/pull").absoluteString == "http://192.168.1.50:51943/sync/pull")
    }

    @Test("LAN sync base URL normalizes bracketless IPv6")
    func testLANSyncBaseURLNormalizesIPv6() throws {
        let peer = DiscoveredPeer(
            deviceId: "dev-ipv6",
            deviceName: "Office Mac",
            companyId: "co",
            host: "fe80::1",
            port: 51943
        )

        let baseURL = try PeerManager.makeLANSyncBaseURL(for: peer)

        #expect(baseURL.absoluteString == "http://[fe80::1]:51943")
    }

    @Test("LAN sync base URL rejects incomplete Bonjour endpoint data")
    func testLANSyncBaseURLRejectsMissingPort() {
        let peer = DiscoveredPeer(
            deviceId: "dev-bad",
            deviceName: "Office Mac",
            companyId: "co",
            host: "WiredPart-dev-bad",
            port: 0
        )

        #expect(throws: URLError.self) {
            _ = try PeerManager.makeLANSyncBaseURL(for: peer)
        }
    }

    @Test("LAN sync base URL rejects raw Bonjour service instance hosts")
    func testLANSyncBaseURLRejectsRawBonjourInstanceName() {
        let peer = DiscoveredPeer(
            deviceId: "dev-bonjour",
            deviceName: "Office Mac",
            companyId: "co",
            host: "WiredPart-dev-bonjour",
            port: 51943
        )

        #expect(throws: URLError.self) {
            _ = try PeerManager.makeLANSyncBaseURL(for: peer)
        }
    }

    @Test("PeerManager issued pairing code activates sync pair endpoint")
    func testIssuedPairingCodePairsThroughSyncServer() async throws {
        let db = try freshDB()
        let pm = PeerManager(db: db)

        try await pm.startPeerSync(
            deviceId: "shop-dev",
            deviceName: "Shop Mac",
            companyId: "co-1"
        )
        let issuedCode = try await pm.issuePairingCode()
        #expect(SyncCrypto.normalizedPairingCode(issuedCode) != nil)

        let state = await pm.getState()
        let peerKeys = SyncCrypto.generateKeyAgreementPair()
        let normalizedCode = try #require(SyncCrypto.normalizedPairingCode(issuedCode))
        let body = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "phone-dev",
            deviceName: "Phone",
            pairingProof: SyncCrypto.pairingProof(
                normalizedCode: normalizedCode,
                deviceId: "phone-dev",
                clientPublicKeyB64: peerKeys.publicKey
            ),
            platform: "iOS",
            keyAgreementPublicKey: peerKeys.publicKey
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(state.syncPort)/sync/pair")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        let wrapper = try JSONDecoder().decode(SyncPairEncryptedResponse.self, from: data)
        let encryptedPayload = try #require(Data(base64Encoded: wrapper.encryptedPayload))
        let sharedKey = try SyncCrypto.derivePairingSharedKeyData(
            ourPrivateKeyB64: peerKeys.privateKey,
            theirPublicKeyB64: wrapper.serverKeyAgreementPublicKey,
            normalizedCode: normalizedCode,
            clientPublicKeyB64: peerKeys.publicKey,
            serverPublicKeyB64: wrapper.serverKeyAgreementPublicKey
        )
        let aad = Data(
            [
                "wiredpart-sync-pairing-response-aad-v1",
                "phone-dev",
                peerKeys.publicKey,
                wrapper.serverKeyAgreementPublicKey,
            ].joined(separator: "\n").utf8
        )
        let plainData = try SyncCrypto.decryptAESGCM(
            data: encryptedPayload,
            keyData: sharedKey,
            aad: aad
        )
        let pairResponse = try JSONDecoder().decode(SyncPairResponse.self, from: plainData)
        #expect(pairResponse.accepted)
        #expect(pairResponse.serverDeviceId == "shop-dev")
        #expect(pairResponse.companyId == "co-1")

        let (_, secondResponse) = try await URLSession.shared.data(for: request)
        #expect((secondResponse as! HTTPURLResponse).statusCode == 403)

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
        #expect(result.executedTransport == nil)
        #expect(!result.syncedAt.isEmpty)
    }

    // MARK: - Row → JSON serialization (the "No User Found" root cause)

    @Test("Rows with NULL columns serialize to valid JSON and round-trip to a fresh DB")
    func testNullColumnRowsSurviveSnapshotRoundTrip() throws {
        let hostDB = try freshDB()

        // Seed a user the way onboarding does: email/phone are NULL — the exact
        // shape that used to fail JSONSerialization and get silently skipped,
        // leaving a Bluetooth-joined device with no users to log in as.
        let userId: Int64 = try {
            var user = User(displayName: "Tester", pinHash: "hash", isActive: 1)
            try hostDB.writer.write { dbConn in
                try user.insert(dbConn)
            }
            return user.id!
        }()

        let row = try hostDB.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT * FROM users WHERE id = ?", arguments: [userId])
        }
        let dict = PeerManager.jsonRecordDict(from: try #require(row))

        // NULL columns must be present as NSNull, and the dict must be valid JSON.
        #expect(dict["email"] is NSNull)
        #expect(JSONSerialization.isValidJSONObject(dict))
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        let recordData = try #require(String(data: jsonData, encoding: .utf8))

        // Apply the snapshot-style change on a fresh (joiner) database.
        let joinerDB = try freshDB()
        let change = IncomingChange(
            deviceId: "host-device",
            tableName: "users",
            recordId: String(userId),
            operation: "INSERT",
            recordData: recordData,
            timestamp: "2026-07-06T12:00:00Z"
        )
        let mergeResult = try ConflictResolver.resolveAndApplyChanges(
            db: joinerDB,
            changes: [change],
            localDeviceId: "joiner-device"
        )
        #expect(mergeResult.applied == 1, "apply result: applied=\(mergeResult.applied) skipped=\(mergeResult.skipped) errors=\(mergeResult.errors)")

        let joined = try joinerDB.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT display_name, email, is_active FROM users WHERE id = ?", arguments: [userId])
        }
        let joinedRow = try #require(joined, "the seeded user must arrive on the joiner")
        #expect(joinedRow["display_name"] == "Tester")
        #expect((joinedRow["email"] as String?) == nil)
        #expect(joinedRow["is_active"] == 1)
    }

    // MARK: - Automatic change tracking (migration 112 triggers)

    @Test("A job created on device A is auto-tracked, syncs to device B, and does not echo")
    func testJobCreationAutoTracksAndSyncsWithoutEcho() async throws {
        let deviceA = try freshDB()
        let deviceB = try freshDB()

        // Create a job through plain SQL (any write path hits the triggers —
        // that is the point: no service has to remember to call trackChange).
        try await deviceA.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO jobs (job_number, job_name, status, created_at, updated_at)
                VALUES ('TEST-001', 'Tablet Test Job', 'active', datetime('now'), datetime('now'))
                """)
        }

        // The trigger must have logged it, and the read must attribute it to us.
        let pendingA = try ChangeTracker.getPendingChanges(db: deviceA)
        let jobChange = try #require(
            pendingA.first(where: { $0.tableName == "jobs" }),
            "creating a job must auto-log a change entry"
        )
        #expect(jobChange.operation == "INSERT")
        #expect(!jobChange.deviceId.isEmpty, "device id must be filled at read time")

        // Push it to device B the way peer sync does (enrich → apply).
        let pmA = PeerManager(db: deviceA)
        let enriched = try await pmA.testEnrichChanges([jobChange])
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: deviceB,
            changes: enriched,
            localDeviceId: "device-b"
        )
        #expect(result.applied == 1)

        let jobOnB = try await deviceB.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT job_name FROM jobs WHERE job_number = 'TEST-001'")
        }
        #expect(try #require(jobOnB)["job_name"] == "Tablet Test Job")

        // Echo guard: applying A's change on B must NOT create a pending change
        // on B — otherwise the change ping-pongs between devices forever.
        let pendingB = try ChangeTracker.getPendingChanges(db: deviceB)
        #expect(
            pendingB.first(where: { $0.tableName == "jobs" }) == nil,
            "sync-applied writes must not re-enter the change log"
        )
    }

    private func snapshotUserChange(recordId: String) -> IncomingChange {
        IncomingChange(
            deviceId: "host-device",
            tableName: "users",
            recordId: recordId,
            operation: "INSERT",
            recordData: "{\"id\":\(recordId),\"display_name\":\"Snapshot User\",\"pin_hash\":\"hash\",\"is_active\":1}",
            timestamp: "2026-07-15T00:00:00Z"
        )
    }
}

private enum SnapshotProbeError: Error {
    case injected
}

// Test helper to expose private enrich method
extension PeerManager {
    func testEnrichChanges(_ entries: [ChangeLogEntry]) throws -> [IncomingChange] {
        try enrichChangesWithData(entries)
    }

    #if canImport(MultipeerConnectivity)
    func testProcessMultipeerMessage(_ message: ReceivedMultipeerMessage) async throws -> MultipeerMessageOutcome {
        try await processMultipeerMessage(message)
    }
    #endif
}
