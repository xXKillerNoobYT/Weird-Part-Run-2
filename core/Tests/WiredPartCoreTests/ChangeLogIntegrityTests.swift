import Testing
import GRDB
@testable import WiredPartCore

/// Cluster B — change-log integrity.
///
/// Covers #1796 (initial-sync bulk load must not self-log via the migration-112
/// triggers) and #1805 (the schema-version stamp must be id-stable and must not
/// churn `_change_log`). #1795 is intentionally not covered here: its MAX(id)
/// heuristic was reverted rather than replaced, and the correct fix (binding the
/// upgrade to the specific bare row) is tracked separately.
@Suite("Change-log integrity (#1796 / #1805)")
struct ChangeLogIntegrityTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    private func pending(_ db: AppDatabase) throws -> Int {
        try ChangeTracker.getPendingChangeCount(db: db)
    }

    private func settingsId(_ db: AppDatabase, key: String) throws -> Int64? {
        try db.writer.read { c in
            try Int64.fetchOne(c, sql: "SELECT id FROM settings WHERE key = ?", arguments: [key])
        }
    }

    // MARK: - #1796: the _sync_apply_guard suppresses the change-tracking triggers

    @Test("An unguarded write to a synced table logs a change; a guarded write does not")
    func guardSuppressesTracking() throws {
        let db = try freshDB()

        // settings is a synced table (in allowedSyncTables) with migration-112 triggers.
        let before = try pending(db)

        // Unguarded write → the trigger logs a bare _change_log row.
        try db.writer.write { c in
            try c.execute(
                sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('cb_unguarded', 'x', 'system', datetime('now'))"
            )
        }
        let afterUnguarded = try pending(db)
        #expect(afterUnguarded == before + 1)

        // Guarded write → the trigger's WHEN clause sees a row in _sync_apply_guard and skips.
        try db.writer.write { c in
            try c.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            defer { try? c.execute(sql: "DELETE FROM _sync_apply_guard") }
            try c.execute(
                sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('cb_guarded', 'x', 'system', datetime('now'))"
            )
        }
        let afterGuarded = try pending(db)
        // This is the #1796 fix's mechanism: initial-sync bulk load under the guard
        // produces ZERO new change-log rows, so it is never re-pushed.
        #expect(afterGuarded == afterUnguarded)
    }

    @Test("A guarded write that throws mid-transaction leaves no sticky guard row")
    func guardIsNotStickyOnThrow() throws {
        let db = try freshDB()

        // Simulate a bulk apply that fails partway: the guard is set, then a bad
        // statement throws. GRDB rolls the transaction back, undoing the guard row.
        #expect(throws: (any Error).self) {
            try db.writer.write { c in
                try c.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
                defer { try? c.execute(sql: "DELETE FROM _sync_apply_guard") }
                try c.execute(sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('cb_ok', 'x', 'system', datetime('now'))")
                try c.execute(sql: "INSERT INTO no_such_table_xyz (a) VALUES (1)") // throws
            }
        }

        // The guard must be empty (rolled back), so tracking is NOT silently disabled.
        let guardRows = try db.writer.read { c in
            try Int.fetchOne(c, sql: "SELECT COUNT(*) FROM _sync_apply_guard") ?? -1
        }
        #expect(guardRows == 0)

        // Proof tracking still works: a normal write is logged again.
        let before = try pending(db)
        try db.writer.write { c in
            try c.execute(sql: "INSERT INTO settings (key, value, category, updated_at) VALUES ('cb_after', 'x', 'system', datetime('now'))")
        }
        #expect(try pending(db) == before + 1)
    }

    // MARK: - #1805: schema-version stamp is id-stable and does not churn the change log

    @Test("Re-stamping the schema version keeps settings.id stable and logs nothing")
    func stampIsIdStableAndGuarded() throws {
        let db = try freshDB() // openInMemoryDatabase already stamped once during migrate()

        let id1 = try settingsId(db, key: "db_schema_version")
        #expect(id1 != nil)
        let clBefore = try pending(db)

        // Stamp again, as a subsequent launch would.
        try db.writer.write { c in
            try AppDatabase.stampSchemaVersion(c)
        }

        let id2 = try settingsId(db, key: "db_schema_version")
        // ON CONFLICT(key) DO UPDATE keeps the same row id; INSERT OR REPLACE would have
        // deleted + reinserted and handed it a fresh AUTOINCREMENT id (#1805).
        #expect(id2 == id1)
        // And the write is guarded, so it adds no _change_log churn to sync every launch.
        #expect(try pending(db) == clBefore)
    }
}
