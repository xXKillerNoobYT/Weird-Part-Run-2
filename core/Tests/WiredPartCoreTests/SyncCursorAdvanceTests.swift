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

    @Test("processInbox records a terminal refusal and applies later rows through the production path")
    func processInboxDoesNotBlockLaterRowsAfterPermanentRefusal() async throws {
        let db = try freshDB()
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE business_profiles")
        }
        let manager = PeerManager(db: db)
        let serverState = SyncServerState(deviceId: "receiver", deviceName: "Receiver", companyId: "company", db: db)
        await manager.testInstallServerState(serverState)
        await serverState.appendToInbox([
            IncomingChange(
                deviceId: "peer", tableName: "business_profiles", recordId: "1", operation: "INSERT",
                recordData: #"{"id":1}"#,
                timestamp: "2026-08-22T00:00:00Z"
            ),
            IncomingChange(
                deviceId: "peer", tableName: "users", recordId: "100", operation: "INSERT",
                recordData: #"{"id":100,"display_name":"later row","pin_hash":"hash","is_active":1}"#,
                timestamp: "2026-08-22T00:00:01Z"
            ),
        ])

        await manager.testProcessInbox()

        #expect((await serverState.inbox).isEmpty)
        let refusalState = try await db.writer.read {
            try String.fetchOne($0, sql: "SELECT state FROM _sync_receive_journal WHERE source_peer_id = 'lan_inbox' ORDER BY id LIMIT 1")
        }
        #expect(refusalState == "refused")
        let displayName = try await db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT display_name FROM users WHERE id = 100")
        }
        #expect(displayName == "later row")
    }

    @Test("processInbox retains a child until a later parent applies through the production path")
    func processInboxConvergesChildBeforeParent() async throws {
        let db = try freshDB()
        let manager = PeerManager(db: db)
        let serverState = SyncServerState(deviceId: "receiver", deviceName: "Receiver", companyId: "company", db: db)
        await manager.testInstallServerState(serverState)
        await serverState.appendToInbox([
            IncomingChange(
                deviceId: "peer", tableName: "part_styles", recordId: "101", operation: "INSERT",
                recordData: #"{"id":"101","category_id":"901","name":"Inbox child"}"#,
                timestamp: "2026-08-22T00:00:00Z"
            ),
            IncomingChange(
                deviceId: "peer", tableName: "part_categories", recordId: "901", operation: "INSERT",
                recordData: #"{"id":"901","name":"Inbox parent"}"#,
                timestamp: "2026-08-22T00:00:01Z"
            ),
        ])

        await manager.testProcessInbox()

        #expect((await serverState.inbox).isEmpty)
        let childJournalState = try await db.writer.read {
            try String.fetchOne($0, sql: "SELECT state FROM _sync_receive_journal WHERE source_peer_id = 'lan_inbox' ORDER BY id LIMIT 1")
        }
        #expect(childJournalState == "applied")
        let childName = try await db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_styles WHERE id = 101")
        }
        #expect(childName == "Inbox child")
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

    @Test("processInbox restores legacy rows when receipt persistence fails")
    func processInboxRestoresLegacyRowsWhenReceiptWriteFails() async throws {
        let db = try freshDB()
        let manager = PeerManager(db: db)
        let serverState = SyncServerState(deviceId: "receiver", deviceName: "Receiver", companyId: "company", db: db)
        await manager.testInstallServerState(serverState)
        let row = IncomingChange(
            deviceId: "peer", tableName: "users", recordId: "101", operation: "INSERT",
            recordData: #"{"id":101,"display_name":"retain me","pin_hash":"hash","is_active":1}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        await serverState.appendToInbox([row])
        try await db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE _sync_receive_journal")
        }

        await manager.testProcessInbox()

        #expect((await serverState.inbox).count == 1,
                "a receipt-write failure must retain the legacy row for a later retry")
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

    @Test("journal retains a deterministic zero-apply as a terminal refusal")
    func receiveJournalDoesNotReportDeterministicNonApplyAsApplied() throws {
        let db = try freshDB()
        let ignored = IncomingChange(
            id: 60, deviceId: "peer", tableName: "not_a_synced_table", recordId: "1", operation: "INSERT",
            recordData: #"{"id":1}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [ignored], auditMetadata: "test")

        let first = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        let second = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        #expect(first.applied == 0)
        #expect(first.refused == 1)
        #expect(second.refused == 0, "terminal non-applies must not replay")
        let evidence = try db.writer.read { dbConn in
            try Row.fetchOne(
                dbConn,
                sql: "SELECT state, disposition_reason, retry_count FROM _sync_receive_journal WHERE source_sequence = 60"
            )
        }
        #expect(evidence?["state"] as String? == "refused")
        #expect(evidence?["disposition_reason"] as String? == "deterministic_non_apply")
        #expect(evidence?["retry_count"] as Int? == 1)
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
        #expect(evidence?["audit_metadata"] as String? == "test")
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

    @Test("syncWithPeer converges child-before-parent rows through syncViaHTTP")
    func syncWithPeerConvergesChildBeforeParent() async throws {
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
        await remoteState.setOutbox([
            IncomingChange(
                id: 81, deviceId: "remote", tableName: "part_styles", recordId: "181", operation: "INSERT",
                recordData: #"{"id":"181","category_id":"981","name":"LAN child"}"#,
                timestamp: "2026-08-22T00:00:00Z"
            ),
            IncomingChange(
                id: 82, deviceId: "remote", tableName: "part_categories", recordId: "981", operation: "INSERT",
                recordData: #"{"id":"981","name":"LAN parent"}"#,
                timestamp: "2026-08-22T00:00:01Z"
            ),
        ])
        try await manager.startPeerSync(
            deviceId: "receiver", deviceName: "Receiver", companyId: "company", startMultipeer: false
        )
        defer { Task { await manager.stopPeerSync() } }
        let receiverIdentity = try await manager.localSyncIdentity(deviceId: "receiver")
        try await remoteState.registerAuthorizedPeer(
            deviceId: "receiver", deviceName: "Receiver", platform: "test",
            keyAgreementPublicKey: receiverIdentity.publicKeyB64
        )

        let result = await manager.syncWithPeer(DiscoveredPeer(
            deviceId: "remote", deviceName: "Remote", companyId: "company",
            host: "127.0.0.1", port: remotePort, transport: "lan"
        ))

        #expect(result.success)
        #expect(result.pulled == 2)
        #expect(try ChangeTracker.getVectorClock(db: db, deviceId: "receiver")["remote"] == 82)
        let lanChildName = try await db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_styles WHERE id = 181")
        }
        #expect(lanChildName == "LAN child")
    }

    @Test("syncWithPeer replays a journal receipt after an empty pull without a local server")
    func syncWithPeerReplaysJournalAfterEmptyPullWithoutServerState() async throws {
        let db = try freshDB()
        let remoteDB = try freshDB()
        let manager = PeerManager(db: db)
        let remoteState = SyncServerState(
            deviceId: "remote", deviceName: "Remote", companyId: "company", db: remoteDB
        )
        let remoteServer = LanSyncServer(state: remoteState)
        let remotePort = try await remoteServer.start()
        defer { Task { await remoteServer.stop() } }

        let deferredReceipt = IncomingChange(
            id: 83, deviceId: "remote", tableName: "part_categories", recordId: "983", operation: "INSERT",
            recordData: #"{"id":"983","name":"Replay after empty pull"}"#,
            timestamp: "2026-08-22T00:00:02Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "remote", changes: [deferredReceipt], auditMetadata: "test")
        try ChangeTracker.registerPeerDevice(
            db: db, peerId: "remote", peerName: "Remote", platform: "test",
            keyAgreementPublicKey: remoteState.kaPublicKeyB64
        )
        try await manager.startPeerSync(
            deviceId: "receiver", deviceName: "Receiver", companyId: "company",
            startMultipeer: false, startSyncServer: false
        )
        defer { Task { await manager.stopPeerSync() } }
        let receiverIdentity = try await manager.localSyncIdentity(deviceId: "receiver")
        try await remoteState.registerAuthorizedPeer(
            deviceId: "receiver", deviceName: "Receiver", platform: "test",
            keyAgreementPublicKey: receiverIdentity.publicKeyB64
        )

        let result = await manager.syncWithPeer(DiscoveredPeer(
            deviceId: "remote", deviceName: "Remote", companyId: "company",
            host: "127.0.0.1", port: remotePort, transport: "lan"
        ))

        #expect(result.success)
        #expect(result.pulled == 1, "an empty response must still replay this peer's receipt")
        #expect(try await db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_categories WHERE id = 983")
        } == "Replay after empty pull")
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

    @Test("receive journal redacts only expired terminal payloads while retaining audit evidence")
    func receiveJournalRedactsExpiredTerminalPayloads() throws {
        let db = try freshDB()
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                INSERT INTO _sync_receive_journal
                    (source_peer_id, source_sequence, payload, state, disposition_reason,
                     retry_count, audit_metadata, last_attempt_at, applied_at, created_at, updated_at)
                VALUES
                    ('peer-applied', 1, 'applied-business-payload', 'applied', NULL, 2, 'lan_pull',
                     '2026-03-31 12:00:00', '2026-03-31 12:00:00', '2026-03-01 12:00:00', '2026-03-31 12:00:00'),
                    ('peer-refused', 2, 'refused-business-payload', 'refused', 'irreconcilable_apply_refusal', 3, 'lan_push',
                     '2026-03-31 12:00:00', NULL, '2026-03-01 12:00:00', '2026-03-31 12:00:00'),
                    ('peer-received', 3, 'received-payload', 'received', NULL, 0, 'lan_pull',
                     NULL, NULL, '2026-03-01 12:00:00', '2026-03-01 12:00:00'),
                    ('peer-deferred', 4, 'deferred-payload', 'deferred', 'foreign_key_parent_unavailable', 1, 'lan_pull',
                     '2026-03-01 12:00:00', NULL, '2026-03-01 12:00:00', '2026-03-01 12:00:00'),
                    ('peer-retry', 5, 'retry-payload', 'retry', 'transient_apply_failure', 1, 'lan_pull',
                     '2026-03-01 12:00:00', NULL, '2026-03-01 12:00:00', '2026-03-01 12:00:00'),
                    ('peer-fresh', 6, 'fresh-terminal-payload', 'applied', NULL, 1, 'lan_pull',
                     '2026-03-31 12:00:01', '2026-03-31 12:00:01', '2026-03-01 12:00:00', '2026-03-31 12:00:01')
                """
            )
        }

        let firstRedaction = try SyncReceiveJournal.redactExpiredTerminalPayloads(
            db: db, now: "2026-04-30 12:00:00"
        )
        #expect(firstRedaction == 2)
        #expect(try SyncReceiveJournal.redactExpiredTerminalPayloads(
            db: db, now: "2026-04-30 12:00:00"
        ) == 0, "redaction is idempotent after payload removal")

        let rows = try db.writer.read { dbConn in
            try Row.fetchAll(
                dbConn,
                sql: """
                SELECT source_peer_id, source_sequence, payload, state, disposition_reason,
                       retry_count, audit_metadata, last_attempt_at, applied_at, created_at,
                       updated_at, redacted_at
                FROM _sync_receive_journal
                ORDER BY source_sequence
                """
            )
        }
        let applied = rows[0]
        #expect(applied["payload"] as String? == "")
        #expect(applied["state"] as String? == "applied")
        #expect(applied["source_peer_id"] as String? == "peer-applied")
        #expect(applied["source_sequence"] as Int64? == 1)
        #expect(applied["retry_count"] as Int? == 2)
        #expect(applied["audit_metadata"] as String? == "lan_pull")
        #expect(applied["last_attempt_at"] as String? == "2026-03-31 12:00:00")
        #expect(applied["applied_at"] as String? == "2026-03-31 12:00:00")
        #expect(applied["created_at"] as String? == "2026-03-01 12:00:00")
        #expect(applied["updated_at"] as String? == "2026-03-31 12:00:00")
        #expect(applied["redacted_at"] as String? == "2026-04-30 12:00:00")

        let refused = rows[1]
        #expect(refused["payload"] as String? == "")
        #expect(refused["state"] as String? == "refused")
        #expect(refused["disposition_reason"] as String? == "irreconcilable_apply_refusal")
        #expect(refused["audit_metadata"] as String? == "lan_push")
        #expect(refused["redacted_at"] as String? == "2026-04-30 12:00:00")

        for index in 2...5 {
            #expect(rows[index]["payload"] as String? != "")
            #expect(rows[index]["redacted_at"] as String? == nil)
        }
    }

    @Test("shop ACK retains a foreign-key deferral in the durable receive journal")
    func shopForeignKeyDeferralIsJournaledBeforeAcknowledgement() async throws {
        let db = try freshDB()
        let server = try HTTPStubServer { request in
            switch request.path {
            case "/api/sync/push":
                return HTTPStubResponse(
                    statusCode: 200,
                    body: #"{"data":{"sync_batch_id":"shop-batch","shop_changes":[{"id":901,"device_id":"shop","table_name":"job_stages","record_id":"1","operation":"UPDATE","changed_fields":"{\"template_id\":\"999999\"}","timestamp":"2026-08-22T00:00:00Z"}]}}"#
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
        #expect(await engine.runSync(deviceId: "receiver", shopUrl: "http://127.0.0.1:\(port)"))
        let disposition = try await db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: "SELECT state FROM _sync_receive_journal WHERE source_peer_id LIKE 'shop:%' AND source_sequence = 901"
            )
        }
        #expect(disposition == "deferred", "ACK may only follow a durable replayable receipt")
    }

    @Test("nonterminal journal payload remains replayable before terminal disposition")
    func receiveJournalKeepsNonterminalPayloadReplayable() throws {
        let db = try freshDB()
        let change = IncomingChange(
            id: 71, deviceId: "peer", tableName: "part_categories", recordId: "701", operation: "INSERT",
            recordData: #"{"id":"701","name":"Retention replay"}"#,
            timestamp: "2026-03-01T00:00:00Z"
        )
        try SyncReceiveJournal.record(
            db: db, sourcePeerId: "peer", changes: [change], auditMetadata: #"{"business":"must-not-persist"}"#
        )
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _sync_receive_journal SET created_at = '2026-03-01 00:00:00', updated_at = '2026-03-01 00:00:00' WHERE source_sequence = 71"
            )
        }

        #expect(try SyncReceiveJournal.redactExpiredTerminalPayloads(
            db: db, now: "2026-04-30 12:00:00"
        ) == 0)
        let receipt = try db.writer.read { dbConn in
            try Row.fetchOne(
                dbConn,
                sql: "SELECT payload, state, audit_metadata, redacted_at FROM _sync_receive_journal WHERE source_sequence = 71"
            )
        }
        #expect(receipt?["payload"] as String? != "")
        #expect(receipt?["state"] as String? == "received")
        #expect(receipt?["audit_metadata"] as String? == "test", "business data is not copied into audit metadata")
        #expect(receipt?["redacted_at"] as String? == nil)

        #expect(try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver").applied == 1)
        #expect(try db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_categories WHERE id = 701")
        } == "Retention replay")
    }

    @Test("journal apply and disposition roll back together when disposition persistence fails")
    func receiveJournalApplyAndDispositionAreAtomic() throws {
        let db = try freshDB()
        let change = IncomingChange(
            id: 72, deviceId: "peer", tableName: "part_categories", recordId: "702", operation: "INSERT",
            recordData: #"{"id":"702","name":"Must not survive failed disposition"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [change], auditMetadata: "test")
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                CREATE TRIGGER fail_receive_journal_disposition
                BEFORE UPDATE OF state ON _sync_receive_journal
                BEGIN SELECT RAISE(FAIL, 'injected disposition failure'); END
                """)
        }

        #expect(throws: (any Error).self) {
            _ = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        }
        #expect(try db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_categories WHERE id = 702")
        } == nil, "a journal disposition failure must roll back the business apply")
        #expect(try db.writer.read {
            try String.fetchOne($0, sql: "SELECT state FROM _sync_receive_journal WHERE source_sequence = 72")
        } == "received", "the uncommitted row remains safely replayable after interruption")
    }

    @Test("same source sequence with a changed restored payload creates a distinct receipt")
    func receiveJournalDoesNotDiscardRestoredSequenceReuse() throws {
        let db = try freshDB()
        let original = IncomingChange(
            id: 73, deviceId: "peer", tableName: "part_categories", recordId: "703", operation: "INSERT",
            recordData: #"{"id":"703","name":"Before restore"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        let restored = IncomingChange(
            id: 73, deviceId: "peer", tableName: "part_categories", recordId: "704", operation: "INSERT",
            recordData: #"{"id":"704","name":"After restore"}"#,
            timestamp: "2026-08-22T00:00:01Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [original], auditMetadata: "test")
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [restored], auditMetadata: "test")
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [restored], auditMetadata: "test")

        let receipts = try db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM _sync_receive_journal WHERE source_peer_id = 'peer' AND source_sequence = 73"
            )
        }
        #expect(receipts == 2, "identical redelivery deduplicates, but restore sequence reuse remains replayable")
        #expect(try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver").applied == 2)
        #expect(try db.writer.read {
            try String.fetchOne($0, sql: "SELECT name FROM part_categories WHERE id = 704")
        } == "After restore")
    }

    @Test("unresolved journal entries wait for their bounded retry time")
    func receiveJournalBoundsDeferredRetryWrites() throws {
        let db = try freshDB()
        let orphan = IncomingChange(
            id: 74, deviceId: "peer", tableName: "part_styles", recordId: "704", operation: "INSERT",
            recordData: #"{"id":"704","category_id":"999999","name":"Orphan"}"#,
            timestamp: "2026-08-22T00:00:00Z"
        )
        try SyncReceiveJournal.record(db: db, sourcePeerId: "peer", changes: [orphan], auditMetadata: "test")
        #expect(try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver").deferred == 1)
        let first = try db.writer.read { dbConn in
            try Row.fetchOne(
                dbConn,
                sql: "SELECT retry_count, next_attempt_at FROM _sync_receive_journal WHERE source_sequence = 74"
            )
        }
        #expect(first?["retry_count"] as Int? == 1)
        #expect(first?["next_attempt_at"] as String? != nil)

        let immediateReplay = try SyncReceiveJournal.applyPending(db: db, localDeviceId: "receiver")
        #expect(immediateReplay.deferred == 0, "timer calls before next_attempt_at must not retry the orphan")
        let second = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT retry_count FROM _sync_receive_journal WHERE source_sequence = 74")
        }
        #expect(second == 1, "a skipped timer pass must not churn the durable receipt")
    }
}
