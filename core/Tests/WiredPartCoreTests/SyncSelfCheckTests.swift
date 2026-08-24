import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// #1780 — the on-device half of the sync-trigger invariant.
///
/// `SyncTableClassificationTests` proves a *freshly migrated* database is correct
/// and spot-checks five tables. Neither fact travels to a tester's device that has
/// accumulated migrations for months, which is the population that reports "X
/// doesn't sync". These tests pin the check that can run there.
@Suite("Sync self-check")
struct SyncSelfCheckTests {

    /// The denominator test, and the most important one here.
    ///
    /// "0 tables missing triggers" is worthless if 0 tables were examined — that is
    /// the exact shape of the blind Dependabot zero in #1777. Any future refactor
    /// that narrows eligibility until nothing is checked must fail loudly rather
    /// than report a serene pass.
    @Test("A migrated database is healthy AND actually examined a meaningful number of tables")
    func freshDatabaseIsHealthyWithARealDenominator() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let audit = try db.writer.read { try SyncSelfCheck.auditTriggers($0) }

        #expect(
            audit.checkedTables > 100,
            "only \(audit.checkedTables) tables examined — a pass over a tiny denominator is a blind pass"
        )
        #expect(
            audit.isHealthy,
            "fresh install cannot replicate: \(audit.tablesMissingTriggers)"
        )
        #expect(audit.missingTriggerCount == 0)
    }

    /// The audit must actually detect a gap, not merely never complain. Without
    /// this, `auditTriggers` could return healthy unconditionally and every other
    /// test here would still pass.
    @Test("A table whose triggers were dropped is reported, with the exact operations")
    func droppedTriggersAreDetected() throws {
        let db = try AppDatabase.openInMemoryDatabase()

        try db.writer.write { dbc in
            try dbc.execute(sql: "DROP TRIGGER IF EXISTS trg_sync_jobs_update")
            try dbc.execute(sql: "DROP TRIGGER IF EXISTS trg_sync_jobs_delete")
        }

        let audit = try db.writer.read { try SyncSelfCheck.auditTriggers($0) }

        #expect(!audit.isHealthy)
        let jobs = audit.tablesMissingTriggers.first { $0.table == "jobs" }
        #expect(jobs != nil, "the dropped table must be named")
        #expect(jobs?.missingOperations == ["update", "delete"])
        #expect(
            audit.tablesMissingTriggers.count == 1,
            "only the damaged table should be reported, not a storm: got \(audit.tablesMissingTriggers.map(\.table))"
        )
        #expect(audit.checkedTables > 100, "the denominator must survive a failure path too")
    }

    @Test("Reconcile repairs exactly what was missing and restores health")
    func reconcileRepairsTheGap() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try db.writer.write { dbc in
            try dbc.execute(sql: "DROP TRIGGER IF EXISTS trg_sync_parts_insert")
        }

        let created = try db.writer.write { try SyncSelfCheck.reconcileMissingTriggers($0) }
        #expect(created == ["trg_sync_parts_insert"])

        let after = try db.writer.read { try SyncSelfCheck.auditTriggers($0) }
        #expect(after.isHealthy, "still broken after repair: \(after.tablesMissingTriggers)")
    }

    /// A repair that is not idempotent cannot be run on every launch, which is the
    /// whole point of having one.
    @Test("Reconcile is idempotent — a second run creates nothing")
    func reconcileIsIdempotent() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try db.writer.write { dbc in
            try dbc.execute(sql: "DROP TRIGGER IF EXISTS trg_sync_parts_insert")
        }

        _ = try db.writer.write { try SyncSelfCheck.reconcileMissingTriggers($0) }
        let second = try db.writer.write { try SyncSelfCheck.reconcileMissingTriggers($0) }

        #expect(second.isEmpty, "second reconcile created: \(second)")
    }

    /// A repaired trigger must be functionally identical to a migration-created
    /// one, not merely present under the right name. A trigger that exists but
    /// writes nothing to `_change_log` would satisfy the audit and still not sync
    /// — the same false-confidence shape the audit exists to eliminate.
    ///
    /// This compares the *stored definition* rather than inserting a fixture row:
    /// it is schema-independent (no coupling to any table's columns or foreign
    /// keys, which drift across migrations) and it is a stricter claim — byte
    /// equality with what the migration produced, for all three operations.
    @Test("A reconciled device_logs trigger preserves migration 126's severity guard")
    func reconciledDeviceLogTriggerMatchesMigration126Definition() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let table = "device_logs"

        func storedSQL(_ dbc: Database, _ name: String) throws -> String? {
            try String.fetchOne(
                dbc,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?",
                arguments: [name]
            )
        }

        for op in SyncSelfCheck.trackedOperations {
            let name = SyncSelfCheck.triggerName(table: table, operation: op)

            let original = try db.writer.read { try storedSQL($0, name) }
            #expect(original != nil, "\(name) should exist on a migrated database")

            try db.writer.write { try $0.execute(sql: "DROP TRIGGER IF EXISTS \(name)") }
            let created = try db.writer.write { try SyncSelfCheck.reconcileMissingTriggers($0) }
            #expect(created == [name], "reconcile should recreate exactly \(name), got \(created)")

            let rebuilt = try db.writer.read { try storedSQL($0, name) }
            #expect(
                rebuilt == original,
                "reconciled \(name) differs from migration 126's severity-gated definition — a trigger that exists but replicates info logs is worse than a missing one, because the audit calls it healthy"
            )
            #expect(
                rebuilt?.contains("COALESCE(\(op == "delete" ? "OLD" : "NEW").severity, 30) >= \(DeviceLogService.replicationMinSeverity)") == true,
                "reconciled \(name) must retain migration 126's device_logs severity guard"
            )
        }
    }

    @Test("The rendered report names the denominator, so a zero can never stand alone")
    func renderedReportCarriesItsDenominator() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let audit = try db.writer.read { try SyncSelfCheck.auditTriggers($0) }
        let text = SyncSelfCheck.renderTriggerAudit(audit)

        #expect(
            text.contains("allowlisted tables : \(ConflictResolver.allowedSyncTables.count)"),
            "the report must distinguish the complete allowlist from the eligible checked denominator"
        )
        #expect(
            text.contains("checked on device  : \(audit.checkedTables)"),
            "the report must state the exact checked-on-device denominator"
        )
    }
}
