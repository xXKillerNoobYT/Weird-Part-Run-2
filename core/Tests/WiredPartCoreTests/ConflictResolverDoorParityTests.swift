import Testing
import Foundation
import GRDB
@testable import WiredPartCore

/// #1765 AC-1 — DIFFERENTIAL test across ConflictResolver's apply doors.
///
/// THE QUESTION: given byte-identical peer input and byte-identical starting
/// rows, does the `.perRow` door (`resolveAndApplyChanges`, LAN/HTTP) reach the
/// SAME final state as the `.batched` delta door
/// (`resolveAndApplyChangesAtomically`, Bluetooth)?
///
/// "Same final state" is defined here as BOTH of:
///   (a) every row of the affected table, every column, and
///   (b) every row of `_conflict_log`.
///
/// Counters are deliberately NOT the oracle. `keyCollisions` and
/// `supersededMerges` have no consumer anywhere in the app, so a counter-only
/// comparison is weak coverage. Rows and `_conflict_log` are what a user and an
/// admin actually see.
///
/// TABLE CHOICE — `part_categories.name`, an INLINE column `UNIQUE`:
///   * not partial, so `pragma_index_info` can see it and the in-place ladder's
///     reduced-retry rung genuinely fires (on `job_stage_templates` the partial
///     predicate hides `archived_at`, the ladder falls to the attempt-3 give-up
///     rung, and that rung writes NOTHING — the `_conflict_log` axis would be
///     invisible);
///   * `job_stages` is excluded on purpose: the `.batched` doors call
///     `suspendJobStageSortIndex` and drop its unique index for the whole
///     apply while the `.perRow` door does not, so a `job_stages` swap would
///     compare two doors running against DIFFERENT schemas.
///
/// ARRIVAL ORDER IS LOAD-BEARING. The array is COLLISION-FIRST: the row that
/// wants the slot arrives before the row that vacates it. Under the reverse
/// (vacate-first) order both doors trivially converge and an AC-1 test would
/// pass vacuously.
///
/// If the doors diverge, this test FAILS. That is the finding, not a defect in
/// the test. Do not relax the assertion.
///
/// SCOPE NOTE: all three apply doors live in the CORE package
/// (`core/Sources/WiredPartCore/Sync/ConflictResolver.swift`), so `swift test`
/// on the core package is the complete and correct runner for this test — the
/// iOS target contains no ConflictResolver coverage at all.
@Suite("ConflictResolver door parity (#1765 AC-1)")
struct ConflictResolverDoorParityTests {

    // MARK: - Fixtures (shapes copied from ConflictResolverNaturalKeyTests)

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    /// Seed the way an earlier sync would have: inside `_sync_apply_guard`, so
    /// migration 112's change-tracking triggers do not record the seed as local
    /// UNSYNCED edits. Without the guard every seeded column looks locally
    /// modified, `getLocalChangedFields` returns it, and the merge takes the LWW
    /// branch instead of the accept-remote branch this test is about.
    private func seed(_ db: AppDatabase, _ body: (Database) throws -> Void) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            try body(dbConn)
            try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")
        }
    }

    /// Byte-identical starting state for both doors.
    ///
    /// `created_at` is pinned explicitly (rather than left to the
    /// `datetime('now')` default) so the two databases cannot differ merely by
    /// having been created on either side of a second boundary — a difference
    /// that would be a test artifact, not a door difference.
    private func seedTwoCategories(_ db: AppDatabase) throws {
        try seed(db) { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO part_categories
                    (id, name, description, sort_order, is_active, created_at, updated_at)
                VALUES
                    (5, 'Romex', 'local five', 0, 1, '2020-01-01T00:00:00Z', '2020-01-01T00:00:00Z'),
                    (9, 'THHN',  'local nine', 0, 1, '2020-01-01T00:00:00Z', '2020-01-01T00:00:00Z')
                """)
        }
    }

    private func update(
        _ table: String,
        _ recordId: String,
        _ changedFieldsJSON: String,
        timestamp: String
    ) -> IncomingChange {
        IncomingChange(
            deviceId: "remote-device",
            tableName: table,
            recordId: recordId,
            operation: "UPDATE",
            changedFields: changedFieldsJSON,
            timestamp: timestamp
        )
    }

    /// THE SWAP, collision-first.
    ///
    /// Entry 1: row 5 takes the `'THHN'` slot — still owned by row 9 when it
    ///          arrives, so the UNIQUE index refuses it. It also carries a
    ///          NON-key column (`description`), which is what makes the
    ///          divergence observable in row bytes and in `_conflict_log`
    ///          rather than only in a counter.
    /// Entry 2: row 9 vacates the slot, one entry too late.
    ///
    /// Rebuilt fresh for each door so neither run can mutate the other's input.
    private var swap: [IncomingChange] {
        [
            update("part_categories", "5",
                   #"{"name":"THHN","description":"incoming five"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            update("part_categories", "9",
                   #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
        ]
    }

    // MARK: - State capture

    /// Every row of `part_categories`, every column, rendered deterministically.
    private func categoryRows(_ db: AppDatabase) throws -> [String] {
        try db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: "SELECT * FROM part_categories ORDER BY id")
                .map { row in
                    row.columnNames.sorted().map { column in
                        "\(column)=\(Self.render(row[column] as DatabaseValue))"
                    }.joined(separator: " | ")
                }
        }
    }

    /// Every `_conflict_log` row, rendered deterministically.
    ///
    /// `id` and `resolved_at` are excluded from the RENDERED comparison text:
    /// `id` is an autoincrement and `resolved_at` is `datetime('now')` at write
    /// time, so both are wall-clock/insertion artifacts rather than door
    /// behaviour. Everything a door actually decides — which field, which
    /// winner, which values, which timestamps — is compared.
    private func conflictLogRows(_ db: AppDatabase) throws -> [String] {
        try db.writer.read { dbConn in
            try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT * FROM _conflict_log
                    ORDER BY table_name, record_id, field_name, winner
                    """
            ).map { row in
                row.columnNames
                    .filter { $0 != "id" && $0 != "resolved_at" }
                    .sorted()
                    .map { column in "\(column)=\(Self.render(row[column] as DatabaseValue))" }
                    .joined(separator: " | ")
            }
        }
    }

    private static func render(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .null:            return "NULL"
        case .string(let s):   return "'\(s)'"
        case .int64(let i):    return "\(i)"
        case .double(let d):   return "\(d)"
        case .blob(let b):     return "<blob \(b.count)B>"
        }
    }

    private func dump(_ label: String, _ result: MergeResult, _ rows: [String], _ log: [String]) {
        print("""

        ================ \(label) ================
        MergeResult: applied=\(result.applied) conflicts=\(result.conflicts) \
        skipped=\(result.skipped) errors=\(result.errors) \
        keyCollisions=\(result.keyCollisions) schemaDrops=\(result.schemaDrops) \
        supersededMerges=\(result.supersededMerges)

        part_categories (\(rows.count) row(s)):
        \(rows.isEmpty ? "  <none>" : rows.map { "  " + $0 }.joined(separator: "\n"))

        _conflict_log (\(log.count) row(s)):
        \(log.isEmpty ? "  <none>" : log.map { "  " + $0 }.joined(separator: "\n"))
        ==========================================
        """)
    }

    // MARK: - AC-1

    /// AC-1. Identical input, identical starting rows, two doors — diff the
    /// final state.
    ///
    /// MUTATION CHECK: if this ever passes, make `canDefer` return `true` for
    /// `.perRow` (or `false` for `.batched`) and it must go red — otherwise the
    /// test is not discriminating between the doors at all.
    @Test("AC-1 the perRow and batched doors reach the same final state for one UNIQUE-slot swap")
    func testPerRowAndBatchedDoorsConvergeOnAUniqueSlotSwap() throws {
        // --- Door A: .perRow (resolveAndApplyChanges) — LAN/HTTP ------------
        let perRowDB = try freshDB()
        try seedTwoCategories(perRowDB)
        let perRowResult = try ConflictResolver.resolveAndApplyChanges(
            db: perRowDB,
            changes: swap,
            localDeviceId: "local-device"
        )
        let perRowRows = try categoryRows(perRowDB)
        let perRowLog = try conflictLogRows(perRowDB)
        dump("DOOR .perRow — resolveAndApplyChanges (LAN/HTTP)",
             perRowResult, perRowRows, perRowLog)

        // --- Door B: .batched delta (resolveAndApplyChangesAtomically) — BT -
        let batchedDB = try freshDB()
        try seedTwoCategories(batchedDB)
        let batchedResult = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: batchedDB,
            changes: swap,
            localDeviceId: "local-device"
        )
        let batchedRows = try categoryRows(batchedDB)
        let batchedLog = try conflictLogRows(batchedDB)
        dump("DOOR .batched — resolveAndApplyChangesAtomically (Bluetooth DELTA)",
             batchedResult, batchedRows, batchedLog)

        // --- Positive control: the scenario really is the one claimed --------
        // If the seed or the payload ever drifts so that no collision is
        // possible, both doors would converge trivially and this test would
        // pass while testing nothing. Pin that the slot really was contested.
        #expect(perRowResult.errors == 0, "a UNIQUE refusal must never land in errors")
        #expect(batchedResult.errors == 0)
        #expect(perRowResult.keyCollisions + batchedResult.keyCollisions > 0,
                "positive control: the swap must actually collide on at least one door; if neither collides, this test is vacuous")

        // --- (a) DIFF THE ROWS ----------------------------------------------
        #expect(perRowRows == batchedRows, """
            DOOR DIVERGENCE — part_categories differs for identical input.
            .perRow  : \(perRowRows)
            .batched : \(batchedRows)
            """)

        // --- (b) DIFF THE CONFLICT LOG --------------------------------------
        #expect(perRowLog == batchedLog, """
            DOOR DIVERGENCE — _conflict_log differs for identical input.
            .perRow  : \(perRowLog)
            .batched : \(batchedLog)
            """)
    }
}
