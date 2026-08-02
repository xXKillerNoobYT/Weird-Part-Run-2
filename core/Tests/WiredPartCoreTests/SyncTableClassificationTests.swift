import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// The gate that closes the 100%-sync gap for good (owner directive
/// 2026-08-01; audit on #1417): every table in the database must be
/// explicitly classified as synced (`allowedSyncTables`) or device-local
/// (`deviceLocalTables`). A new table without a classification fails here,
/// so it can never silently join the 22 that accumulated before 2026-08-02.
@Suite("Sync table classification")
struct SyncTableClassificationTests {

    private func allBusinessTables(_ db: AppDatabase) throws -> Set<String> {
        try db.writer.read { dbc in
            try Set(String.fetchAll(dbc, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'
                  AND name NOT LIKE '\\_%' ESCAPE '\\'
                  AND name != 'grdb_migrations'
                """))
        }
    }

    @Test("Every table is classified as synced or device-local — no third bucket")
    func everyTableClassified() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let tables = try allBusinessTables(db)
        let unclassified = tables
            .subtracting(ConflictResolver.allowedSyncTables)
            .subtracting(ConflictResolver.deviceLocalTables)
        #expect(
            unclassified.isEmpty,
            "Unclassified tables (add to allowedSyncTables — plus a trigger migration — or to deviceLocalTables with a reason): \(unclassified.sorted())"
        )
    }

    @Test("The two classifications never overlap")
    func classificationsDisjoint() {
        let overlap = ConflictResolver.allowedSyncTables
            .intersection(ConflictResolver.deviceLocalTables)
        #expect(overlap.isEmpty, "Tables in BOTH sets: \(overlap.sorted())")
    }

    @Test("Migration 119 installed change triggers for the gap tables")
    func gapTableTriggersExist() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        // Spot-check one table per affected area, all three operations.
        for table in ["wishlist_items", "job_stages", "company_holidays",
                      "warehouse_zones", "timesheet_correction_audits"] {
            for op in ["insert", "update", "delete"] {
                let exists = try db.writer.read { dbc in
                    try Bool.fetchOne(dbc, sql: """
                        SELECT EXISTS(
                            SELECT 1 FROM sqlite_master
                            WHERE type = 'trigger' AND name = ?
                        )
                        """, arguments: ["trg_sync_\(table)_\(op)"]) ?? false
                }
                #expect(exists, "missing trigger trg_sync_\(table)_\(op)")
            }
        }
    }

    @Test("Gap-table writes now land in the change log")
    func gapTableWriteIsTracked() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try db.writer.write { dbc in
            try dbc.execute(sql: """
                INSERT INTO company_holidays (name, date)
                VALUES ('Christmas', '2026-12-25')
                """)
        }
        let logged = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: """
                SELECT COUNT(*) FROM _change_log
                WHERE table_name = 'company_holidays' AND operation = 'INSERT'
                """) ?? 0
        }
        #expect(logged >= 1, "company_holidays INSERT was not change-tracked")
    }

    @Test("Migration 119 upgrades pre-gap stores without echoing sync-applied writes")
    func migration119BackfillsExistingRowsAndHonorsApplyGuard() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)

        // Reproduce a store that ran the historical migration 112 before these
        // tables were added to its allowlist: its schema and guard table exist,
        // but company_holidays has no change triggers or bootstrap row.
        var historicalMigrator = DatabaseMigrator()
        AppDatabase.registerMigrations(&historicalMigrator)
        try historicalMigrator.migrate(queue, upTo: "111_chat_attachment_storage_relative")
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE _sync_apply_guard (id INTEGER PRIMARY KEY)")
        }
        var appliedHistorical112 = DatabaseMigrator()
        appliedHistorical112.registerMigration("112_change_tracking_triggers") { _ in }
        try appliedHistorical112.migrate(queue)
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO company_holidays (name, date)
                VALUES ('Pre-migration holiday', '2026-12-25')
                """)
        }

        var currentMigrator = DatabaseMigrator()
        AppDatabase.registerMigrations(&currentMigrator)
        try currentMigrator.migrate(queue)

        let upgraded = try queue.read { db -> (bootstrapRows: Int, triggers: Set<String>) in
            let bootstrapRows = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM _change_log
                WHERE table_name = 'company_holidays'
                  AND operation = 'INSERT'
                  AND changed_fields = '{"__backfill__":1}'
                """) ?? 0
            let triggers = try Set(String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'trigger' AND name IN (?, ?, ?)
                """, arguments: [
                    "trg_sync_company_holidays_insert",
                    "trg_sync_company_holidays_update",
                    "trg_sync_company_holidays_delete",
                ]))
            return (bootstrapRows, triggers)
        }
        #expect(upgraded.bootstrapRows == 1, "migration 119 must backfill one existing gap-table row")
        #expect(upgraded.triggers == [
            "trg_sync_company_holidays_insert",
            "trg_sync_company_holidays_update",
            "trg_sync_company_holidays_delete",
        ])

        try queue.write { db in
            try db.execute(sql: "UPDATE company_holidays SET name = 'Local edit' WHERE id = 1")
        }
        let localUpdates = try queue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM _change_log
                WHERE table_name = 'company_holidays' AND operation = 'UPDATE'
                """) ?? 0
        }
        #expect(localUpdates == 1, "normal gap-table writes must be change-tracked")

        try queue.write { db in
            try db.execute(sql: "INSERT INTO _sync_apply_guard (id) VALUES (1)")
            try db.execute(sql: "UPDATE company_holidays SET name = 'Peer edit' WHERE id = 1")
            try db.execute(sql: "DELETE FROM _sync_apply_guard WHERE id = 1")
        }
        let guardedUpdates = try queue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM _change_log
                WHERE table_name = 'company_holidays' AND operation = 'UPDATE'
                """) ?? 0
        }
        #expect(guardedUpdates == localUpdates, "sync-applied writes must not echo into _change_log")
    }
}
