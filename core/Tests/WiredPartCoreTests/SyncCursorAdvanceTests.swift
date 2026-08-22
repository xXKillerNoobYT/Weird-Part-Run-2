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

    @Test("A permanent foreign-key refusal is deterministic rather than retryable")
    func permanentForeignKeyRefusalAdvances() throws {
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

        #expect(result.permanentRefusals == 1)
        #expect(result.errors == 0)
        #expect(result.isSafeToAdvanceReceiveCursor)
    }

    @Test("processInbox clears deterministic results but requeues transient results")
    func processInboxClassifiesRetryPolicyAtTheProductionCallSite() async throws {
        let db = try freshDB()
        let manager = PeerManager(db: db)
        let serverState = SyncServerState(deviceId: "receiver", deviceName: "Receiver", companyId: "company", db: db)
        await manager.testInstallServerState(serverState)

        let row = IncomingChange(
            deviceId: "peer", tableName: "users", recordId: "100", operation: "INSERT",
            timestamp: "2026-08-22T00:00:00Z"
        )
        await serverState.appendToInbox([row])
        await manager.testProcessInbox { _, _ in MergeResult(permanentRefusals: 1) }
        #expect((await serverState.inbox).isEmpty)

        await serverState.appendToInbox([row])
        await manager.testProcessInbox { _, _ in MergeResult(errors: 1) }
        #expect((await serverState.inbox).count == 1)
    }

    // MARK: - #1794: backlog is capped, count is not

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
