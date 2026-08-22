import Testing
import Foundation
import GRDB
@testable import WiredPartCore

@Suite("ChangeTracker Tests")
struct ChangeTrackerTests {

    private func freshDB() throws -> AppDatabase {
        let db = try AppDatabase.openInMemoryDatabase()
        // Migration 112 backfills seeded reference rows into _change_log; these
        // unit tests assert on specific manually-tracked entries, so start empty.
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }
        return db
    }

    @Test("trackChange inserts a change log entry")
    func testTrackChangeInserts() throws {
        let db = try freshDB()

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 42,
            operation: .insert,
            changedFields: ["display_name": "Alice", "email": "alice@test.com"],
            deviceId: "test-device-1"
        )

        let entries = try ChangeTracker.getPendingChanges(db: db)
        #expect(entries.count == 1)
        #expect(entries[0].tableName == "users")
        #expect(entries[0].recordId == 42)
        #expect(entries[0].operation == "INSERT")
        #expect(entries[0].deviceId == "test-device-1")
        #expect(entries[0].synced == 0)
    }

    @Test("trackChange records old values for UPDATE")
    func testTrackChangeOldValues() throws {
        let db = try freshDB()

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: 1,
            operation: .update,
            changedFields: ["email": "new@test.com"],
            oldValues: ["email": "old@test.com"],
            deviceId: "test-device-1"
        )

        let entries = try ChangeTracker.getPendingChanges(db: db)
        #expect(entries.count == 1)
        #expect(entries[0].operation == "UPDATE")
        #expect(entries[0].changedFields != nil)
        #expect(entries[0].oldValues != nil)
        #expect(entries[0].changedFields!.contains("new@test.com"))
        #expect(entries[0].oldValues!.contains("old@test.com"))
    }

    @Test("getPendingChangeCount returns correct count")
    func testPendingCount() throws {
        let db = try freshDB()

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db,
                tableName: "parts",
                recordId: Int64(i),
                operation: .insert,
                deviceId: "test-device"
            )
        }

        let count = try ChangeTracker.getPendingChangeCount(db: db)
        #expect(count == 3)
    }

    @Test("markSynced marks entries as synced")
    func testMarkSynced() throws {
        let db = try freshDB()

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db,
                tableName: "parts",
                recordId: Int64(i),
                operation: .insert,
                deviceId: "test-device"
            )
        }

        let entries = try ChangeTracker.getPendingChanges(db: db)
        let ids = entries.compactMap { $0.id }
        #expect(ids.count == 3)

        try ChangeTracker.markSynced(db: db, ids: Array(ids.prefix(2)), batchId: "batch-001")

        let remaining = try ChangeTracker.getPendingChangeCount(db: db)
        #expect(remaining == 1)
    }

    @Test("markSynced with empty ids is a no-op")
    func testMarkSyncedEmpty() throws {
        let db = try freshDB()
        try ChangeTracker.markSynced(db: db, ids: [], batchId: "batch-empty")
    }

    @Test("getMaxSequence returns 0 on empty log")
    func testMaxSequenceEmpty() throws {
        let db = try freshDB()
        let maxSeq = try ChangeTracker.getMaxSequence(db: db)
        #expect(maxSeq == 0)
    }

    @Test("getVectorClock returns empty dict initially")
    func testVectorClockEmpty() throws {
        let db = try freshDB()
        let vc = try ChangeTracker.getVectorClock(db: db, deviceId: "test-device")
        #expect(vc.isEmpty)
    }

    @Test("updateVectorClock stores and retrieves peer sequence")
    func testUpdateVectorClock() throws {
        let db = try freshDB()
        let deviceId = "my-device"
        let peerId = "peer-device"

        try ChangeTracker.updateVectorClock(db: db, peerId: peerId, lastSequence: 42, deviceId: deviceId)

        let vc = try ChangeTracker.getVectorClock(db: db, deviceId: deviceId)
        #expect(vc[peerId] == 42)
    }

    @Test("updateVectorClock uses MAX for existing peer")
    func testVectorClockMax() throws {
        let db = try freshDB()
        let deviceId = "my-device"
        let peerId = "peer-device"

        try ChangeTracker.updateVectorClock(db: db, peerId: peerId, lastSequence: 42, deviceId: deviceId)
        try ChangeTracker.updateVectorClock(db: db, peerId: peerId, lastSequence: 30, deviceId: deviceId)

        let vc = try ChangeTracker.getVectorClock(db: db, deviceId: deviceId)
        #expect(vc[peerId] == 42)
    }

    @Test("registerPeerDevice without key records metadata but does not trust")
    func testRegisterPeerDevice() throws {
        let db = try freshDB()

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-1", peerName: "iPad Pro", platform: "iOS")

        let device = try db.writer.read { dbConn in
            try DeviceRegistryEntry.fetchOne(
                dbConn,
                sql: "SELECT * FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(device != nil)
        #expect(device?.deviceName == "iPad Pro")
        #expect(device?.platform == "iOS")
        #expect(device?.isTrusted == 0)

        // Update the same device without a pairing key: metadata can refresh, but
        // discovery must not silently create trust.
        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-1", peerName: "iPad Pro (updated)")

        let updated = try db.writer.read { dbConn in
            try DeviceRegistryEntry.fetchOne(
                dbConn,
                sql: "SELECT * FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(updated?.deviceName == "iPad Pro (updated)")
        #expect(updated?.isTrusted == 0)
    }

    @Test("Pairing-bound LAN key persists and deactivation remains fail-closed")
    func testPairingBoundKeyPersistenceAndDeactivation() async throws {
        let db = try freshDB()
        let (_, publicKey) = SyncCrypto.generateKeyAgreementPair()
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "peer-1",
            peerName: "iPad",
            platform: "iOS",
            keyAgreementPublicKey: publicKey
        )

        let state = SyncServerState(
            deviceId: "server",
            deviceName: "Server",
            companyId: "company",
            db: db
        )
        #expect(try await state.authorizedPeerKey(deviceId: "peer-1") == publicKey)

        try await db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _device_registry SET is_deactivated = 1 WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(try await state.authorizedPeerKey(deviceId: "peer-1") == nil)

        // Normal discovery/sync bookkeeping must not silently reactivate a revoked peer.
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "peer-1",
            peerName: "iPad seen again"
        )
        #expect(try await state.authorizedPeerKey(deviceId: "peer-1") == nil)

        // A fresh pairing proof with a bound key intentionally reauthorizes it.
        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "peer-1",
            peerName: "iPad re-paired",
            keyAgreementPublicKey: publicKey
        )
        #expect(try await state.authorizedPeerKey(deviceId: "peer-1") == publicKey)
    }

    @Test("updatePeerSyncTime updates timestamps")
    func testUpdatePeerSyncTime() throws {
        let db = try freshDB()

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-1", peerName: "Test Device")
        try ChangeTracker.updatePeerSyncTime(db: db, peerId: "peer-1")

        let device = try db.writer.read { dbConn in
            try DeviceRegistryEntry.fetchOne(
                dbConn,
                sql: "SELECT * FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(device != nil)
        #expect(device?.lastSyncAt != nil)
    }

    // MARK: - Per-Peer Send Watermark (#1645 P1 finding 9)

    /// THE regression test for #1645 P1-9. Before the per-peer cursor, pushing a
    /// change to peer B set the global `synced` flag, so peer C — which had
    /// received nothing — was offered nothing, forever.
    @Test("a change delivered to one peer is still pending for another")
    func testDeliveryToOnePeerLeavesItPendingForAnother() throws {
        let db = try freshDB()
        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-b", peerName: "B")
        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-c", peerName: "C")

        try ChangeTracker.trackChange(
            db: db, tableName: "parts", recordId: 7, operation: .insert, deviceId: "device-a"
        )

        let forB = try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-b")
        #expect(forB.count == 1)

        // Exactly what PeerManager does on a successful push to B.
        let sequence = Int64(forB[0].sequence ?? 0)
        try ChangeTracker.markSynced(db: db, ids: forB.compactMap { $0.id }, batchId: "batch-b")
        try ChangeTracker.advanceSendWatermark(db: db, peerId: "peer-b", lastSequence: sequence)

        #expect(try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-b").isEmpty)
        // The row is globally `synced = 1` now. C must still get it.
        #expect(try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-c").count == 1)
    }

    /// Pins the nested-trigger behaviour the watermark depends on: a row written
    /// by the migration-112 table triggers (not by `trackChange`) must still get
    /// a sequence, or it is invisible to `WHERE sequence > ?` and never syncs.
    @Test("every change log row gets a non-null sequence")
    func testSequenceIsPopulatedForTriggerWrittenRows() throws {
        let db = try freshDB()

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO jobs (job_number, job_name, status, created_at, updated_at)
                    VALUES ('WM-SEQ-1', 'watermark trigger probe', 'active',
                            datetime('now'), datetime('now'))
                    """
            )
        }

        let rows = try db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: "SELECT sequence FROM _change_log")
        }
        #expect(!rows.isEmpty, "the migration-112 trigger should have logged the INSERT")
        for row in rows {
            let sequence: Int64? = row["sequence"]
            #expect(sequence != nil && sequence! > 0)
        }
    }

    /// Re-pairing runs the same idempotent registration UPSERT. If the seed were
    /// written as an upsert rather than `INSERT OR IGNORE`, it would reset the
    /// cursor to "now" and silently burn everything still queued for that peer.
    @Test("re-registering a peer does not burn its unsent backlog")
    func testRepairPreservesBacklog() throws {
        let db = try freshDB()
        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-b", peerName: "B")

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db, tableName: "parts", recordId: Int64(i), operation: .insert,
                deviceId: "device-a"
            )
        }

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-b", peerName: "B renamed")

        #expect(try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-b").count == 3)
    }

    /// A peer seen for the first time must not be handed the entire history —
    /// replaying old DELETEs would re-delete records it has since restored,
    /// because inbound deletes are applied unconditionally.
    @Test("a newly registered peer starts at the delivered floor, not at zero")
    func testNewPeerDoesNotReplayDeliveredHistory() throws {
        let db = try freshDB()

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db, tableName: "parts", recordId: Int64(i), operation: .insert,
                deviceId: "device-a"
            )
        }
        // Everything so far has already been pushed somewhere.
        let delivered = try ChangeTracker.getPendingChanges(db: db)
        try ChangeTracker.markSynced(db: db, ids: delivered.compactMap { $0.id }, batchId: "old")

        // Work that was never pushed ANYWHERE, logged BEFORE this peer existed.
        // Seeding at MAX(sequence) would strand it — that is the same bug this
        // fix exists to remove, reintroduced through the seeding rule.
        try ChangeTracker.trackChange(
            db: db, tableName: "parts", recordId: 98, operation: .insert, deviceId: "device-a"
        )

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-new", peerName: "New")
        let atRegistration = try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-new")
        #expect(atRegistration.count == 1, "never-pushed work must survive peer registration")
        #expect(atRegistration.first?.recordId == 98)

        // ...but the three already-delivered rows are NOT replayed to it.
        #expect(!atRegistration.contains { $0.recordId <= 3 })

        // And new work after registration reaches it too.
        try ChangeTracker.trackChange(
            db: db, tableName: "parts", recordId: 99, operation: .insert, deviceId: "device-a"
        )
        #expect(try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-new").count == 2)
    }

    /// The seed rides inside the pairing transaction, so a rolled-back pairing
    /// must leave no cursor behind for a later re-pair to inherit.
    @Test("a rolled-back pairing leaves no send watermark")
    func testRolledBackPairingLeavesNoWatermark() throws {
        let db = try freshDB()

        let snapshot = try ChangeTracker.capturePeerDeviceTrust(db: db, peerId: "peer-x")
        #expect(snapshot == nil, "peer-x should not exist yet")

        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-x", peerName: "X")
        #expect(try ChangeTracker.getSendWatermark(db: db, peerId: "peer-x") != nil)

        try ChangeTracker.restorePeerDeviceTrust(db: db, peerId: "peer-x", snapshot: snapshot)
        #expect(try ChangeTracker.getSendWatermark(db: db, peerId: "peer-x") == nil)
    }

    /// The cursor is monotonic: a late or duplicated call must not rewind it and
    /// cause the same rows to be pushed again.
    @Test("advanceSendWatermark never moves backwards")
    func testWatermarkIsMonotonic() throws {
        let db = try freshDB()
        try ChangeTracker.advanceSendWatermark(db: db, peerId: "peer-b", lastSequence: 50)
        try ChangeTracker.advanceSendWatermark(db: db, peerId: "peer-b", lastSequence: 10)
        #expect(try ChangeTracker.getSendWatermark(db: db, peerId: "peer-b") == 50)
    }

    /// The global flag keeps its old meaning and its old readers. This is the
    /// test that fails if someone "simplifies" the fix by deleting `markSynced`.
    @Test("markSynced still clears the pending badge count")
    func testGlobalSyncedFlagSemanticsUnchanged() throws {
        let db = try freshDB()
        try ChangeTracker.registerPeerDevice(db: db, peerId: "peer-b", peerName: "B")

        try ChangeTracker.trackChange(
            db: db, tableName: "parts", recordId: 1, operation: .insert, deviceId: "device-a"
        )
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 1)

        let forB = try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-b")
        try ChangeTracker.markSynced(db: db, ids: forB.compactMap { $0.id }, batchId: "batch-b")

        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 0)
    }

    /// Pruning must not delete a row a slower peer has not received, and must
    /// never delete the row holding MAX(sequence) — that would let the trigger's
    /// counter fall back and reuse sequence values already passed by a cursor.
    @Test("pruneOldChanges keeps rows a peer has not received")
    func testPruneRespectsSlowestPeer() throws {
        let db = try freshDB()

        for i in 1...3 {
            try ChangeTracker.trackChange(
                db: db, tableName: "parts", recordId: Int64(i), operation: .insert,
                deviceId: "device-a"
            )
        }
        let all = try ChangeTracker.getPendingChanges(db: db)
        try ChangeTracker.markSynced(db: db, ids: all.compactMap { $0.id }, batchId: "old")
        // Age every row past the 30-day retention window.
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _change_log SET timestamp = datetime('now', '-60 days')"
            )
        }
        // A peer that has received nothing at all.
        try ChangeTracker.advanceSendWatermark(db: db, peerId: "peer-slow", lastSequence: 0)

        let deleted = try ChangeTracker.pruneOldChanges(db: db)
        #expect(deleted == 0)
        #expect(try ChangeTracker.getChangesForPeer(db: db, peerId: "peer-slow").count == 3)
    }

    @Test("Raw certificate pins remain compatible while reserved envelopes fail closed")
    func testCertificateLegacyCompatibilityAndFailClosedDecoding() throws {
        let (_, publicKey) = SyncCrypto.generateKeyAgreementPair()
        let legacy = "x25519:\(publicKey)"
        let codec = DeviceRegistryCertificateCodec.production
        let reservedEnvelope = "wpdr-cert:v1:\(Data(legacy.utf8).base64EncodedString())"

        #expect(try codec.store(legacy) == legacy)
        #expect(try codec.read(legacy) == legacy)
        #expect(throws: DeviceRegistryCertificateError.self) {
            try codec.read("x25519:not-base64")
        }
        #expect(throws: DeviceRegistryCertificateError.self) {
            try codec.read(reservedEnvelope)
        }
    }

    @Test("Malformed certificate storage denies authorization and rollback")
    func testMalformedCertificateDeniesAuthorizationAndRollback() async throws {
        let db = try freshDB()
        let (_, publicKey) = SyncCrypto.generateKeyAgreementPair()
        try ChangeTracker.registerPeerDevice(
            db: db, peerId: "peer-1", peerName: "Peer", keyAgreementPublicKey: publicKey
        )
        let state = SyncServerState(
            deviceId: "server", deviceName: "Server", companyId: "company", db: db
        )
        try await db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _device_registry SET certificate = ? WHERE device_id = ?",
                arguments: ["wpdr-cert:v1:truncated", "peer-1"]
            )
        }
        #expect((try? await state.authorizedPeerKey(deviceId: "peer-1")) == nil)
        #expect(throws: DeviceRegistryCertificateError.self) {
            try ChangeTracker.capturePeerDeviceTrust(db: db, peerId: "peer-1")
        }

        let invalidSnapshot = PeerDeviceTrustSnapshot(
            deviceName: "Peer", platform: "ios", role: nil,
            certificate: "wpdr-cert:v1:truncated", lastSeenAt: nil, lastSyncAt: nil,
            isTrusted: 1, isDeactivated: 0, createdAt: "2026-08-01T00:00:00Z"
        )
        #expect(throws: DeviceRegistryCertificateError.self) {
            try ChangeTracker.restorePeerDeviceTrust(db: db, peerId: "peer-1", snapshot: invalidSnapshot)
        }
    }

    @Test("Capture and restore preserve canonical public-key storage")
    func testCertificateCaptureRestorePreservesRepresentation() throws {
        let db = try freshDB()
        let (_, publicKey) = SyncCrypto.generateKeyAgreementPair()
        let legacy = "x25519:\(publicKey)"
        try ChangeTracker.registerPeerDevice(
            db: db, peerId: "peer-1", peerName: "Peer", keyAgreementPublicKey: publicKey
        )
        let capturedSnapshot = try ChangeTracker.capturePeerDeviceTrust(db: db, peerId: "peer-1")
        let captured = try #require(capturedSnapshot)
        #expect(captured.certificate == legacy)
        try ChangeTracker.restorePeerDeviceTrust(db: db, peerId: "peer-1", snapshot: captured)
        let restored = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: "SELECT certificate FROM _device_registry WHERE device_id = ?",
                arguments: ["peer-1"]
            )
        }
        #expect(restored == legacy)
    }
}
