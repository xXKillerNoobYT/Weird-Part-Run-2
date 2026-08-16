import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// #1737 — `ConflictResolver` never guarded natural (non-primary) UNIQUE keys.
///
/// Two defects, one root cause: both apply branches address rows **by id** and
/// neither accounted for the row's natural key already being held locally under
/// a *different* id.
///
/// - The merge branch's `UPDATE` had no conflict clause, so a collision threw
///   `UNIQUE constraint failed`, escaped `applyOneAtomically` (which catches
///   only `missingLocalRecord`) and rolled back the **entire batch**.
/// - `INSERT OR IGNORE` silently discarded the row while `applyOneAtomically`
///   credited `applied: 1` from a literal, so the loss was invisible to the
///   snapshot completeness gate, which inspects only `errors` and `skipped`.
///
/// Reachable on ordinary two-device use: both devices create a category named
/// "Switchgear" while offline, or one renames a shared row into a name the
/// other just used.
@Suite("Conflict resolver — natural UNIQUE keys")
struct ConflictResolverNaturalKeyTests {

    /// `part_categories.name` is a natural key (inline `.unique()`, realised as
    /// an undroppable `sqlite_autoindex`) on a replicated table with children.
    private func seedCategory(_ db: AppDatabase, id: Int64, name: String) throws {
        try db.writer.write { dbc in
            try dbc.execute(
                sql: "INSERT INTO part_categories (id, name) VALUES (?, ?)",
                arguments: [id, name]
            )
        }
    }

    private func change(
        table: String,
        recordId: String,
        operation: String,
        recordData: String?,
        changedFields: String? = nil
    ) -> IncomingChange {
        IncomingChange(
            deviceId: "peer-device",
            tableName: table,
            recordId: recordId,
            operation: operation,
            changedFields: changedFields,
            recordData: recordData,
            timestamp: "2026-08-15T22:00:00Z"
        )
    }

    // MARK: - Defect B: the silent drop

    @Test("A dropped INSERT is reported as skipped, not applied")
    func silentDropIsVisible() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Switchgear")

        // The peer ships the same natural key under a different id.
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [change(
                table: "part_categories",
                recordId: "600",
                operation: "INSERT",
                recordData: #"{"id":"600","name":"Switchgear"}"#
            )],
            localDeviceId: "local-device"
        )

        let landed = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: "SELECT COUNT(*) FROM part_categories WHERE id = 600") ?? 0
        }
        #expect(landed == 0, "the row genuinely cannot land — the key is taken")
        // The point of the fix: the caller is TOLD.
        #expect(result.applied == 0, "a dropped row must not be credited as applied")
        #expect(result.skipped == 1, "it must register where the completeness gate can see it")
    }

    /// The `applyUpdate` no-local-record branch is the sibling builder. The #196
    /// NULL fix landed in `applyInsert` first and left this copy broken for five
    /// weeks, so it gets its own test.
    @Test("The sibling builder in applyUpdate reports its drop too")
    func siblingBuilderAlsoReports() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Panelboard")

        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [change(
                table: "part_categories",
                recordId: "700",
                operation: "UPDATE",
                recordData: #"{"id":"700","name":"Panelboard"}"#
            )],
            localDeviceId: "local-device"
        )

        #expect(result.applied == 0)
        #expect(result.skipped == 1)
    }

    @Test("A non-colliding INSERT still applies normally")
    func nonCollidingInsertStillWorks() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Switchgear")

        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [change(
                table: "part_categories",
                recordId: "600",
                operation: "INSERT",
                recordData: #"{"id":"600","name":"Conduit"}"#
            )],
            localDeviceId: "local-device"
        )

        #expect(result.applied == 1)
        #expect(result.skipped == 0)
        let landed = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: "SELECT COUNT(*) FROM part_categories WHERE id = 600") ?? 0
        }
        #expect(landed == 1)
    }

    // MARK: - Defect A: the batch-killing merge UPDATE

    /// The headline fix. Before #1737 this threw `UNIQUE constraint failed` out
    /// of the merge branch and took every other row in the batch with it.
    @Test("A colliding rename does not abort the batch, and bystanders survive")
    func collidingRenameDoesNotKillTheBatch() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Switchgear")
        try seedCategory(db, id: 501, name: "Conduit")

        // Peer renames 501 to "Switchgear" — a name 500 already holds locally.
        // A second, innocent change rides in the same batch.
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [
                change(
                    table: "part_categories",
                    recordId: "501",
                    operation: "UPDATE",
                    recordData: #"{"id":"501","name":"Switchgear"}"#,
                    changedFields: #"{"name":"Switchgear"}"#
                ),
                change(
                    table: "part_categories",
                    recordId: "502",
                    operation: "INSERT",
                    recordData: #"{"id":"502","name":"Wire"}"#
                ),
            ],
            localDeviceId: "local-device"
        )

        #expect(result.errors == 0, "a collided field must not error the batch")

        try db.writer.read { dbc in
            // The local name is kept: it already owns the unique key.
            let name501 = try String.fetchOne(
                dbc, sql: "SELECT name FROM part_categories WHERE id = 501"
            )
            #expect(name501 == "Conduit", "local wins the unique key")

            // The bystander landed — this is what used to be destroyed.
            let bystander = try Int.fetchOne(
                dbc, sql: "SELECT COUNT(*) FROM part_categories WHERE id = 502"
            ) ?? 0
            #expect(bystander == 1, "an unrelated row in the same batch must survive")

            // And 500 is untouched.
            let name500 = try String.fetchOne(
                dbc, sql: "SELECT name FROM part_categories WHERE id = 500"
            )
            #expect(name500 == "Switchgear")
        }
    }

    @Test("A refused field is recorded in the conflict log, not silently dropped")
    func refusedFieldIsLogged() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Switchgear")
        try seedCategory(db, id: 501, name: "Conduit")

        _ = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [change(
                table: "part_categories",
                recordId: "501",
                operation: "UPDATE",
                recordData: #"{"id":"501","name":"Switchgear"}"#,
                changedFields: #"{"name":"Switchgear"}"#
            )],
            localDeviceId: "local-device"
        )

        let logged = try db.writer.read { dbc in
            try Int.fetchOne(dbc, sql: """
                SELECT COUNT(*) FROM _conflict_log
                WHERE table_name = 'part_categories' AND record_id = '501' AND field_name = 'name'
                """) ?? 0
        }
        #expect(logged >= 1, "the refusal must leave a trail an admin can review")
    }

    /// A merge that changes only non-key fields must be unaffected — the guard
    /// must not become a general write blocker.
    @Test("A non-colliding merge still applies every field")
    func nonCollidingMergeUnaffected() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Switchgear")

        _ = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [change(
                table: "part_categories",
                recordId: "500",
                operation: "UPDATE",
                recordData: #"{"id":"500","name":"Switchgear MV"}"#,
                changedFields: #"{"name":"Switchgear MV"}"#
            )],
            localDeviceId: "local-device"
        )

        let name = try db.writer.read { dbc in
            try String.fetchOne(dbc, sql: "SELECT name FROM part_categories WHERE id = 500")
        }
        #expect(name == "Switchgear MV", "renaming a row to a free name must still work")
    }

    /// The guard asks the database rather than hardcoding a table list, so it
    /// must not fire on the primary key — an id match is the merge branch's
    /// ordinary case.
    @Test("The primary key is not treated as a natural key")
    func primaryKeyIsNotANaturalKey() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try seedCategory(db, id: 500, name: "Switchgear")

        _ = try ConflictResolver.resolveAndApplyChanges(
            db: db,
            changes: [change(
                table: "part_categories",
                recordId: "500",
                operation: "UPDATE",
                recordData: #"{"id":"500","name":"Renamed"}"#,
                changedFields: #"{"id":"500","name":"Renamed"}"#
            )],
            localDeviceId: "local-device"
        )

        let name = try db.writer.read { dbc in
            try String.fetchOne(dbc, sql: "SELECT name FROM part_categories WHERE id = 500")
        }
        #expect(name == "Renamed", "a row updating itself must not be blocked by its own id")
    }
}
