import Testing
import Foundation
import GRDB
@testable import WiredPartCore

@Suite("PeerManager Tests")
struct PeerManagerTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
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
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "joiner",
            peerName: "Joiner",
            platform: "ios"
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

    @Test("Snapshot capability is reserved once, restored only after failed apply, and consumed after durable success")
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
        #expect(await pm.testHostedSnapshotTokenAvailable(token, for: peer))
        #expect(!(await pm.testHostedSnapshotIsReserved(for: peer)))

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

    @Test("Bluetooth pairing wire format distinguishes capability protocol clients from legacy clients")
    func testBluetoothPairingProtocolVersionWireFormat() throws {
        let current = SyncPairRequest(
            deviceId: "joiner",
            deviceName: "Joiner",
            pairingCode: "ABCD-1234",
            platform: "ios",
            bluetoothProtocolVersion: 2
        )
        let currentRoundTrip = try JSONDecoder().decode(
            SyncPairRequest.self,
            from: JSONEncoder().encode(current)
        )
        #expect(currentRoundTrip.bluetoothProtocolVersion == 2)

        let legacy = try JSONDecoder().decode(
            SyncPairRequest.self,
            from: Data(#"{"device_id":"legacy","device_name":"Legacy","pairing_code":"ABCD-1234","platform":"ios"}"#.utf8)
        )
        #expect(legacy.bluetoothProtocolVersion == nil)
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
        await pm.testFailPendingTransportOperations()

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
    #endif

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
        let (_, peerPublicKey) = SyncCrypto.generateKeyAgreementPair()
        let body = try JSONEncoder().encode(SyncPairRequest(
            deviceId: "phone-dev",
            deviceName: "Phone",
            pairingCode: issuedCode,
            platform: "iOS",
            keyAgreementPublicKey: peerPublicKey
        ))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(state.syncPort)/sync/pair")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        let pairResponse = try JSONDecoder().decode(SyncPairResponse.self, from: data)
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
