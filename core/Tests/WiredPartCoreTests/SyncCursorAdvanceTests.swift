import Testing
import GRDB
@testable import WiredPartCore

/// Cluster A — "advance the receive cursor on confirmed apply, not on transport-accept."
///
/// Covers the shared invariant behind #1792 (inbox drain re-queue), #1793 (LAN pull
/// vector-clock advance), and the backlog-reporting premise of #1794.
@Suite("Sync receive-cursor advance (#1792 / #1793 / #1794)")
struct SyncCursorAdvanceTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    // MARK: - isSafeToAdvanceReceiveCursor (the #1792/#1793 decision)

    @Test("A clean apply may advance the receive cursor")
    func cleanApplyAdvances() {
        let r = MergeResult(applied: 10)
        #expect(r.isSafeToAdvanceReceiveCursor)
    }

    @Test("A transient error holds the receive cursor so the peer re-sends")
    func transientErrorHolds() {
        // errors > 0 == SQLITE_BUSY / disk full: retryable, must NOT advance.
        #expect(MergeResult(applied: 7, errors: 3).isSafeToAdvanceReceiveCursor == false)
        // Even if nothing else went wrong, a lone error blocks the advance.
        #expect(MergeResult(errors: 1).isSafeToAdvanceReceiveCursor == false)
    }

    @Test("Deterministic non-applies do NOT hold the cursor (guards against the #1749 loop)")
    func deterministicNonAppliesAdvance() {
        // keyCollisions / schemaDrops / supersededMerges will NEVER apply on retry.
        // Holding the cursor for them re-sends forever and the peer never converges —
        // the exact failure PR #1749 was reverted for. They must still advance.
        #expect(MergeResult(applied: 5, keyCollisions: 2).isSafeToAdvanceReceiveCursor)
        #expect(MergeResult(applied: 5, schemaDrops: 4).isSafeToAdvanceReceiveCursor)
        #expect(MergeResult(applied: 5, supersededMerges: 9).isSafeToAdvanceReceiveCursor)
        // All three together, still no transient error → still safe to advance.
        #expect(
            MergeResult(applied: 1, keyCollisions: 1, schemaDrops: 1, supersededMerges: 1)
                .isSafeToAdvanceReceiveCursor
        )
    }

    @Test("A partial batch with any transient error holds the whole cursor")
    func partialWithTransientHolds() {
        // Mixed: some applied, some deterministic drops, but ALSO a transient error.
        // The transient error wins — do not advance, so the peer re-sends the batch.
        let r = MergeResult(applied: 8, skipped: 1, errors: 1, keyCollisions: 1)
        #expect(r.isSafeToAdvanceReceiveCursor == false)
    }

    @Test("A foreign-key refusal is deferred durably instead of becoming terminal")
    func foreignKeyRefusalDefers() throws {
        let db = try freshDB()
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [IncomingChange(
                deviceId: "peer",
                tableName: "job_stages",
                recordId: "1",
                operation: "UPDATE",
                changedFields: #"{"template_id":"999999"}"#,
                timestamp: "2026-08-22T00:00:00Z"
            )],
            localDeviceId: "receiver"
        )

        #expect(result.foreignKeyDeferrals == 1)
        #expect(result.permanentRefusals == 0)
        #expect(result.errors == 0)
    }

    @Test("A missing target table is deterministic rather than retryable")
    func missingTableRefusalAdvances() throws {
        let db = try freshDB()
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE business_profiles")
        }

        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [IncomingChange(
                deviceId: "peer",
                tableName: "business_profiles",
                recordId: "1",
                operation: "INSERT",
                recordData: #"{"id":1}"#,
                timestamp: "2026-08-22T00:00:00Z"
            )],
            localDeviceId: "receiver"
        )

        #expect(result.permanentRefusals == 1)
        #expect(result.errors == 0)
        #expect(result.isSafeToAdvanceReceiveCursor)
    }

    @Test("processInbox acknowledges a permanent refusal and applies later rows through the production path")
    func processInboxDoesNotBlockLaterRowsAfterPermanentRefusal() async throws {
        let db = try freshDB()
        let manager = PeerManager(db: db)
        let serverState = SyncServerState(deviceId: "receiver", deviceName: "Receiver", companyId: "company", db: db)
        await manager.testInstallServerState(serverState)
        await serverState.appendToInbox([
            IncomingChange(
                deviceId: "peer",
                tableName: "job_stages",
                recordId: "1",
                operation: "UPDATE",
                changedFields: #"{"template_id":"999999"}"#,
                timestamp: "2026-08-22T00:00:00Z"
            ),
            IncomingChange(
                deviceId: "peer",
                tableName: "users",
                recordId: "100",
                operation: "INSERT",
                recordData: #"{"id":100,"display_name":"later row","pin_hash":"hash","is_active":1}"#,
                timestamp: "2026-08-22T00:00:01Z"
            ),
        ])

        await manager.testProcessInbox()

        #expect((await serverState.inbox).isEmpty)
        let displayName = try await db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT display_name FROM users WHERE id = 100")
        }
        #expect(displayName == "later row")
    }

    @Test("processInbox drains legacy memory input only after persisting it in the journal")
    func processInboxPersistsLegacyRowsBeforeApply() async throws {
        let db = try freshDB()
        let manager = PeerManager(db: db)
        let serverState = SyncServerState(deviceId: "receiver", deviceName: "Receiver", companyId: "company", db: db)
        await manager.testInstallServerState(serverState)

        let row = IncomingChange(
            deviceId: "peer", tableName: "users", recordId: "100", operation: "INSERT",
            recordData: #"{"id":100,"display_name":"journaled","pin_hash":"hash","is_active":1}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        await serverState.appendToInbox([row])
        await manager.testProcessInbox()

        #expect((await serverState.inbox).isEmpty)
        let journalState = try await db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT state FROM _sync_receive_journal WHERE source_peer_id = 'lan_inbox'")
        }
        #expect(journalState == "applied")
    }

    @Test("journal retains child before a later parent then converges in source order")
    func receiveJournalDefersChildUntilLaterParent() throws {
        let db = try freshDB()
        let child = IncomingChange(
            id: 41, deviceId: "peer", tableName: "part_styles", recordId: "77", operation: "INSERT",
            recordData: #"{"id":"77","category_id":"700","name":"Deferred child"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [child], auditMetadata: "test")
        let first = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        #expect(first.deferred == 1)
        #expect(try db.writer.read { try String.fetchOne($0, sql: "SELECT state FROM _sync_receive_journal WHERE source_sequence = 41") } == "deferred")
        #expect(try db.writer.read { try String.fetchOne($0, sql: "SELECT name FROM part_styles WHERE id = 77") } == nil)

        let parent = IncomingChange(
            id: 42, deviceId: "peer", tableName: "part_categories", recordId: "700", operation: "INSERT",
            recordData: #"{"id":"700","name":"Later parent"}"#,
            timestamp: "2026-08-22T00:00:01Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [parent], auditMetadata: "test")
        let second = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        #expect(second.applied == 2)
        #expect(try db.writer.read { try String.fetchOne($0, sql: "SELECT state FROM _sync_receive_journal WHERE source_sequence = 41") } == "applied")
        #expect(try db.writer.read { try String.fetchOne($0, sql: "SELECT name FROM part_styles WHERE id = 77") } == "Deferred child")
    }

    @Test("journal replays a child before its later parent in durable source order")
    func receiveJournalPreservesSourceOrderAcrossFixedPointReplay() throws {
        let db = try freshDB()
        let child = IncomingChange(
            id: 51, deviceId: "peer", tableName: "part_styles", recordId: "88", operation: "INSERT",
            recordData: #"{"id":"88","category_id":"701","name":"Source-ordered child"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        let parent = IncomingChange(
            id: 52, deviceId: "peer", tableName: "part_categories", recordId: "701", operation: "INSERT",
            recordData: #"{"id":"701","name":"Source-ordered parent"}"#,
            timestamp: "2026-08-22T00:00:01Z"
        )

        try SyncReceiveJournal.record(
            db: db, sourcePeerId: "peer", changes: [child, parent], auditMetadata: "source_order_test"
        )
        let result = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")

        #expect(result.deferred == 1, "the child must be attempted before its later parent")
        #expect(result.applied == 2)
        let retries = try db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT retry_count FROM _sync_receive_journal WHERE source_sequence = 51"
            )
        }
        #expect(retries == 2, "child is deferred once, then applied only after the later parent")
        #expect(try db.writer.read {
            try String.fetchOne($0, sql: "SELECT state FROM _sync_receive_journal WHERE source_sequence = 51")
        } == "applied")
        #expect(try db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_styles WHERE id = 88")
        } == "Source-ordered child")
    }

    @Test("journal retains an irreconcilable refusal as structured non-retrying audit evidence")
    func receiveJournalRetainsIrreconcilableRefusal() throws {
        let db = try freshDB()
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE business_profiles")
        }
        let refusal = IncomingChange(
            id: 61, deviceId: "peer", tableName: "business_profiles", recordId: "1", operation: "INSERT",
            recordData: #"{"id":1}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [refusal], auditMetadata: "refusal_test")

        let first = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        let second = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        #expect(first.refused == 1)
        #expect(second.refused == 0, "terminal refusals must not hot-loop")
        let evidence = try db.writer.read { dbConn in
            try Row.fetchOne(
                dbConn,
                sql: "SELECT state, disposition_reason, retry_count, audit_metadata FROM _sync_receive_journal WHERE source_sequence = 61"
            )
        }
        #expect(evidence?["state"] as String? == "refused")
        #expect(evidence?["disposition_reason"] as String? == "irreconcilable_apply_refusal")
        #expect(evidence?["retry_count"] as Int? == 1)
        #expect(evidence?["audit_metadata"] as String? == "refusal_test")
    }

    @Test("syncWithPeer advances the LAN receive vector for a permanent refusal")
    func syncWithPeerAdvancesVectorClockAfterPermanentRefusal() async throws {
        let db = try freshDB()
        let remoteDB = try freshDB()
        let manager = PeerManager(db: db)
        let remoteState = SyncServerState(
            deviceId: "remote",
            deviceName: "Remote",
            companyId: "company",
            db: remoteDB
        )
        let remoteServer = LanSyncServer(state: remoteState)
        let remotePort = try await remoteServer.start()
        defer { Task { await remoteServer.stop() } }

        try ChangeTracker.registerPeerDevice(
            db: db,
            peerId: "remote",
            peerName: "Remote",
            platform: "test",
            keyAgreementPublicKey: remoteState.kaPublicKeyB64
        )
        await remoteState.setOutbox([IncomingChange(
            id: 41,
            deviceId: "remote",
            tableName: "job_stages",
            recordId: "1",
            operation: "UPDATE",
            changedFields: #"{"template_id":"999999"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )])

        try await manager.startPeerSync(
            deviceId: "receiver",
            deviceName: "Receiver",
            companyId: "company",
            startMultipeer: false
        )
        defer { Task { await manager.stopPeerSync() } }
        let receiverIdentity = try await manager.localSyncIdentity(deviceId: "receiver")
        try await remoteState.registerAuthorizedPeer(
            deviceId: "receiver",
            deviceName: "Receiver",
            platform: "test",
            keyAgreementPublicKey: receiverIdentity.publicKeyB64
        )

        let result = await manager.syncWithPeer(DiscoveredPeer(
            deviceId: "remote",
            deviceName: "Remote",
            companyId: "company",
            host: "127.0.0.1",
            port: remotePort,
            transport: "lan"
        ))

        #expect(result.success)
        #expect(result.pulled == 0)
        #expect(try ChangeTracker.getVectorClock(db: db, deviceId: "receiver")["remote"] == 41)
        let journalState = try await db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: "SELECT state FROM _sync_receive_journal WHERE source_peer_id = 'remote' AND source_sequence = 41"
            )
        }
        #expect(journalState != nil, "the vector may advance only after a durable journal receipt")
        #expect(journalState != "received", "receipt must reach an explicit apply disposition")
    }

    @Test("syncWithPeer does not advance a receive vector when durable receipt fails")
    func syncWithPeerHoldsVectorWhenJournalReceiptFails() async throws {
        let db = try freshDB()
        let remoteDB = try freshDB()
        let manager = PeerManager(db: db)
        let remoteState = SyncServerState(
            deviceId: "remote", deviceName: "Remote", companyId: "company", db: remoteDB
        )
        let remoteServer = LanSyncServer(state: remoteState)
        let remotePort = try await remoteServer.start()
        defer { Task { await remoteServer.stop() } }

        try ChangeTracker.registerPeerDevice(
            db: db, peerId: "remote", peerName: "Remote", platform: "test",
            keyAgreementPublicKey: remoteState.kaPublicKeyB64
        )
        await remoteState.setOutbox([IncomingChange(
            id: 71, deviceId: "remote", tableName: "part_categories", recordId: "701", operation: "INSERT",
            recordData: #"{"id":"701","name":"Receipt must precede vector"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )])
        try await manager.startPeerSync(
            deviceId: "receiver", deviceName: "Receiver", companyId: "company", startMultipeer: false
        )
        defer { Task { await manager.stopPeerSync() } }
        let receiverIdentity = try await manager.localSyncIdentity(deviceId: "receiver")
        try await remoteState.registerAuthorizedPeer(
            deviceId: "receiver", deviceName: "Receiver", platform: "test",
            keyAgreementPublicKey: receiverIdentity.publicKeyB64
        )
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE _sync_receive_journal")
        }

        let result = await manager.syncWithPeer(DiscoveredPeer(
            deviceId: "remote", deviceName: "Remote", companyId: "company",
            host: "127.0.0.1", port: remotePort, transport: "lan"
        ))

        #expect(!result.success)
        #expect(try ChangeTracker.getVectorClock(db: db, deviceId: "receiver")["remote"] == nil,
                "an accepted transport row is unreachable if receipt fails before vector advance")
    }

    // MARK: - #1794: backlog is capped, count is not

    @Test("runSync reports the remaining pending backlog after a successful capped upload")
    func runSyncReportsRemainingPendingBacklog() async throws {
        let db = try freshDB()
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }
        for index in 1...505 {
            try ChangeTracker.trackChange(
                db: db,
                tableName: "parts",
                recordId: Int64(index),
                operation: .insert,
                deviceId: "device"
            )
        }

        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"batch","shop_changes":[]}}"#
                )
            case "/api/sync/ack":
                return HTTPStubResponse(statusCode: 200, body: #"{"ok":true}"#)
            default:
                return HTTPStubResponse(statusCode: 404, body: #"{"error":"not found"}"#)
            }
        }
        let port = try await server.start()
        defer { server.stop() }

        let engine = SyncEngine(db: db)
        #expect(await engine.runSync(deviceId: "device", shopUrl: "http://127.0.0.1:\(port)"))

        let state = await engine.getState()
        #expect(state.status == .synced)
        #expect(state.pendingCount == 5)
        #expect(try ChangeTracker.getPendingChangeCount(db: db) == 5)
    }

    @Test("getPendingChanges is capped at 500 while getPendingChangeCount is the true backlog")
    func pendingCapVersusCount() throws {
        let db = try freshDB()

        // A fresh DB already carries some seeded change-log rows from migrations, so
        // this test asserts on DELTAS, not absolute counts.
        let baseline = try ChangeTracker.getPendingChangeCount(db: db)

        // Seed more than one push window (LIMIT 500) of additional unsynced changes.
        for i in 1...505 {
            try ChangeTracker.trackChange(
                db: db,
                tableName: "parts",
                recordId: Int64(i),
                operation: .insert,
                deviceId: "test-device"
            )
        }

        let window = try ChangeTracker.getPendingChanges(db: db)
        let backlog = try ChangeTracker.getPendingChangeCount(db: db)

        // The push window is capped at 500...
        #expect(window.count == 500)
        // ...but the true backlog exceeds it. This divergence is the whole bug:
        // #1794's runSync must report getPendingChangeCount, not a hardcoded 0.
        #expect(backlog == baseline + 505)
        #expect(backlog > window.count)

        // After syncing exactly one capped window, the backlog is still non-empty —
        // a hardcoded pendingCount of 0 would have hidden every remaining row.
        let firstWindowIds = window.compactMap { $0.id }
        try ChangeTracker.markSynced(db: db, ids: firstWindowIds, batchId: "batch-1")
        let remaining = try ChangeTracker.getPendingChangeCount(db: db)
        #expect(remaining == backlog - 500)
        #expect(remaining > 0)
    }
}
