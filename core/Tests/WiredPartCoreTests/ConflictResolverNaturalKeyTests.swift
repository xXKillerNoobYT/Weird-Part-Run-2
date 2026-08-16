import Testing
import Foundation
import GRDB
@testable import WiredPartCore

/// #1737 — a unique index refusing ONE row must never roll back a batch.
///
/// Every test here that matters runs on the SNAPSHOT path
/// (`resolveAndApplyStreamedChangesAtomically`), because that is the only path
/// where the failure mode lives: it is one transaction for a whole company, and
/// its completeness gate runs INSIDE that transaction. A delta-only test cannot
/// detect the #1749 class at all — #1749 routed a constraint outcome into
/// `skipped`, the gate threw on it, and the whole join rolled back, forever,
/// because the residue is a deterministic function of (payload, local schema,
/// local rows).
@Suite("ConflictResolver natural-key collisions (#1737)")
struct ConflictResolverNaturalKeyTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    /// Seed rows the way an earlier sync would have: inside
    /// `_sync_apply_guard`, so migration 112's change-tracking triggers do not
    /// record them as local UNSYNCED edits.
    ///
    /// This is not tidiness. Without the guard, every seeded column looks
    /// locally modified, `getLocalChangedFields` returns it, and the merge takes
    /// the LWW branch instead of the accept-remote branch these tests are about.
    private func seed(_ db: AppDatabase, _ body: (Database) throws -> Void) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "INSERT OR IGNORE INTO _sync_apply_guard (id) VALUES (1)")
            try body(dbConn)
            try dbConn.execute(sql: "DELETE FROM _sync_apply_guard")
        }
    }

    /// Byte-copy of `PeerManager.applyStagedSnapshot`'s `validate:` closure
    /// (`PeerManager.swift`, the `resolveAndApplyStreamedChangesAtomically`
    /// call). It runs INSIDE the write transaction, so anything it throws rolls
    /// the entire company snapshot back.
    ///
    /// It is copied rather than paraphrased on purpose: the assertion these
    /// tests make is not "the counters look right", it is "the real gate does
    /// not fire". A paraphrase that drifted would pass while the shipped gate
    /// still bricked the join.
    private func snapshotGate(_ result: MergeResult) throws {
        guard result.errors == 0 else {
            throw MultipeerSnapshotError.batchApplyFailed(errorCount: result.errors)
        }
        guard result.skipped == 0 else {
            throw MultipeerSnapshotError.snapshotIncomplete(
                applied: result.applied,
                skipped: result.skipped
            )
        }
    }

    /// Apply through the REAL streamed entry point, with a cursor held open on
    /// the transaction's own connection across every emit — the shape
    /// `PeerManager.applyStagedSnapshot` uses when it walks `_snapshot_staging`.
    private func applyStreamed(
        _ db: AppDatabase,
        _ changes: [IncomingChange]
    ) throws -> MergeResult {
        let gate: (MergeResult) throws -> Void = { result in
            try self.snapshotGate(result)
        }
        return try ConflictResolver.resolveAndApplyStreamedChangesAtomically(
            db: db,
            produceChanges: { dbConn, emit in
                let cursor = try Row.fetchCursor(
                    dbConn,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY rowid"
                )
                var index = 0
                while index < changes.count, try cursor.next() != nil {
                    try emit(changes[index])
                    index += 1
                }
            },
            validate: gate
        )
    }

    private func update(
        _ table: String,
        _ recordId: String,
        _ changedFieldsJSON: String,
        timestamp: String = "2026-08-16T10:00:00Z"
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

    private func seedTwoCategories(_ db: AppDatabase) throws {
        try seed(db) { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO part_categories (id, name, description, updated_at)
                VALUES (5, 'Romex', 'local five', '2020-01-01T00:00:00Z'),
                       (9, 'THHN', 'local nine', '2020-01-01T00:00:00Z')
                """)
        }
    }

    private func categoryName(_ db: AppDatabase, _ id: Int) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn, sql: "SELECT name FROM part_categories WHERE id = ?", arguments: [id]
            )
        }
    }

    private func categoryDescription(_ db: AppDatabase, _ id: Int) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn, sql: "SELECT description FROM part_categories WHERE id = ?", arguments: [id]
            )
        }
    }

    // MARK: - T-2 — the snapshot must COMMIT

    /// T-2. The load-bearing regression test for the #1749 class.
    ///
    /// Two devices independently own the natural key `part_categories.name =
    /// 'Romex'` under different ids. The incoming merge would move id 9 onto
    /// that name, and the UNIQUE index refuses it.
    ///
    /// The assertion is not "the row was skipped". It is that the TRANSACTION
    /// COMMITS: the real gate closure sees `errors == 0` and `skipped == 0`, the
    /// bystander row in the same batch is present afterwards, and the cause is
    /// recorded in its own counter.
    ///
    /// MUTATION CHECK: route `context.keyCollisions` into `skipped` (the literal
    /// #1749 mutation) and this test must go red with `snapshotIncomplete`.
    @Test("T-2 a natural-key collision commits the snapshot instead of rolling it back")
    func testSnapshotCommitsThroughANaturalKeyCollision() throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        let result = try applyStreamed(db, [
            update("part_categories", "9", #"{"name":"Romex","description":"from A"}"#),
            IncomingChange(
                deviceId: "remote-device",
                tableName: "part_categories",
                recordId: "77",
                operation: "INSERT",
                recordData: #"{"id":"77","name":"Bystander"}"#,
                timestamp: "2026-08-16T10:00:01Z"
            ),
        ])

        #expect(result.keyCollisions == 1, "the cause must be named")
        #expect(result.skipped == 0, "a constraint outcome may NEVER produce a gate input")
        #expect(result.errors == 0)

        #expect(try categoryName(db, 9) == "THHN", "the contested key column was withheld")
        #expect(try categoryDescription(db, 9) == "from A",
                "the non-key column from the SAME change still landed")
        #expect(try categoryName(db, 77) == "Bystander",
                "a bystander row in the same batch must survive the collision")
    }

    // MARK: - T-3 — rename vs create

    /// T-3. Device A renamed its id 5 'Romex' → 'THHN'; device B independently
    /// created id 9 'THHN' while offline. B receives A's rename.
    ///
    /// The point is that the SET clause is REDUCED, not abandoned: `name` is
    /// withheld, but the `description` carried by the very same change lands.
    ///
    /// MUTATION CHECK: delete the reduced-retry (attempt 2) block in
    /// `resolveKeyCollisionInPlace` and the description assertion must go red.
    @Test("T-3 rename-vs-create keeps the non-key fields of the losing change")
    func testRenameVersusCreateReducesRatherThanAbandons() throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        let result = try applyStreamed(db, [
            update("part_categories", "5", #"{"name":"THHN","description":"renamed on A"}"#),
        ])

        #expect(result.keyCollisions == 1)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)
        #expect(try categoryName(db, 5) == "Romex")
        #expect(try categoryDescription(db, 5) == "renamed on A")
        #expect(try categoryName(db, 9) == "THHN", "exactly one row still holds the key")
    }

    // MARK: - T-4 — composite key, and the conflict-log row

    /// T-4. `part_types` carries `UNIQUE(style_id, name)` as an inline table
    /// constraint, so it exists only as `sqlite_autoindex_part_types_1` — a
    /// `CREATE UNIQUE INDEX` grep over the migrations cannot see it, which is
    /// why the column enumeration is read from the live database.
    ///
    /// This is also the exact case #1749's pre-flight `allSatisfy` guard could
    /// not see: a merge UPDATE carries only `changed_fields`, minus `id`, minus
    /// every LWW local-wins field, so the key column is frequently absent from
    /// the payload the guard inspected.
    ///
    /// The `_conflict_log` row must carry a REAL local value and a REAL,
    /// non-empty `localTs`. #1749 wrote `localTs: ""`; the column is a
    /// non-optional `String`, so that compiles and only fails in the admin UI.
    @Test("T-4 a composite unique key is withheld and recorded honestly")
    func testCompositeUniqueKeyIsWithheldAndLogged() throws {
        let db = try freshDB()
        try seed(db) { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO part_categories (id, name) VALUES (1, 'Wire')
                """)
            try dbConn.execute(sql: """
                INSERT INTO part_styles (id, category_id, name) VALUES (1, 1, 'Romex')
                """)
            try dbConn.execute(sql: """
                INSERT INTO part_types (id, style_id, name, sort_order, updated_at)
                VALUES (10, 1, '12-2', 1, '2020-01-01T00:00:00Z'),
                       (11, 1, '12-3', 2, '2020-01-01T00:00:00Z')
                """)
        }

        let result = try applyStreamed(db, [
            update("part_types", "11", #"{"name":"12-2","sort_order":"7"}"#),
        ])

        #expect(result.keyCollisions == 1)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        let row = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT name, sort_order FROM part_types WHERE id = 11")
        }
        #expect(row?["name"] == "12-3", "the key column was withheld")
        #expect(row?["sort_order"] == 7, "the non-key column from the same change landed")

        let conflicts = try ConflictResolver.getUnreviewedConflicts(db: db)
        let nameConflict = try #require(
            conflicts.first { $0.tableName == "part_types" && $0.fieldName == "name" }
        )
        #expect(nameConflict.winner == "local")
        #expect(nameConflict.localValue == "12-3", "the REAL local value, not a placeholder")
        #expect(nameConflict.remoteValue == "12-2")
        #expect(nameConflict.localTs.isEmpty == false, "#1749 wrote an empty localTs here")
        #expect(nameConflict.localTs == "2020-01-01T00:00:00Z")
        #expect(nameConflict.remoteTs == "2026-08-16T10:00:00Z")
        #expect(result.conflicts == 1)
    }

    // MARK: - T-8 — the give-up rung, and the fixed point that avoids it

    private func seedArchivedTemplate(_ db: AppDatabase) throws {
        // id 1 ('Default', is_default = 1, archived_at NULL) is migration-seeded
        // on EVERY device, which is what makes this shape reachable in the field.
        try seed(db) { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO job_stage_templates (id, name, is_default, archived_at, updated_at)
                VALUES (2, 'Old', 1, '2026-01-01T00:00:00Z', '2020-01-01T00:00:00Z')
                """)
        }
    }

    /// T-8a. The probe that refutes "attempt 2 cannot collide again".
    ///
    /// `idx_job_stage_templates_one_default` is
    /// `ON (is_default) WHERE is_default = 1 AND archived_at IS NULL`. The
    /// incoming change writes ONLY `archived_at = NULL`, which moves the row
    /// INTO the index — and `pragma_index_info` reports only `is_default`, so
    /// the enumeration cannot see `archived_at` and there is nothing to
    /// withhold. Attempt 2 is byte-identical to attempt 1.
    ///
    /// MUTATION CHECK: delete the attempt-3 give-up rung at the end of
    /// `resolveKeyCollisionInPlace` and this test must go red with a thrown
    /// `DatabaseError` — the whole snapshot rolling back.
    @Test("T-8a a partial index's predicate column defeats the reduced retry, and it still commits")
    func testPartialIndexPredicateColumnReachesTheGiveUpRung() throws {
        let db = try freshDB()
        try seedArchivedTemplate(db)

        let result = try applyStreamed(db, [
            update("job_stage_templates", "2", #"{"archived_at":null}"#),
        ])

        #expect(result.keyCollisions == 1)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        let stillArchived = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn, sql: "SELECT archived_at FROM job_stage_templates WHERE id = 2"
            )
        }
        #expect(stillArchived != nil, "the row is left exactly as it was")
    }

    /// T-8b. The same collision, recoverable — because the row holding the slot
    /// moves later in the SAME batch. Arrival order is the un-archive first,
    /// which is the ordering the host's rowid-ordered stream routinely produces.
    ///
    /// MUTATION CHECK: delete the `drainDeferredMerges` call from
    /// `resolveAndApplyStreamedChangesAtomically` and this test must go red —
    /// `keyCollisions` becomes 1 and the row stays archived.
    @Test("T-8b the fixed-point replay resolves an ordering-induced collision")
    func testFixedPointReplayResolvesAnOrderingCollision() throws {
        let db = try freshDB()
        try seedArchivedTemplate(db)

        let result = try applyStreamed(db, [
            // Wants the slot, but it is still occupied when it arrives.
            update("job_stage_templates", "2", #"{"archived_at":null}"#),
            // Vacates it, one row too late.
            update("job_stage_templates", "1", #"{"is_default":"0"}"#),
        ])

        #expect(result.keyCollisions == 0, "ordering is not corruption")
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        let (archivedAt, defaultFlag) = try db.writer.read { dbConn -> (String?, Int?) in
            (
                try String.fetchOne(
                    dbConn, sql: "SELECT archived_at FROM job_stage_templates WHERE id = 2"
                ),
                try Int.fetchOne(
                    dbConn, sql: "SELECT is_default FROM job_stage_templates WHERE id = 1"
                )
            )
        }
        #expect(archivedAt == nil, "the deferred row landed on replay")
        #expect(defaultFlag == 0, "and the row that vacated the slot landed too")
    }

    // MARK: - T-9 — an un-delete into an occupied partial-index slot

    /// Seed the FK chain `warehouse_walking_path_stops` needs, then two stops
    /// contesting one `(path_id, area_id)` slot.
    private func seedWalkingPathStops(_ db: AppDatabase, otherStopDeleted: Bool) throws {
        try seed(db) { dbConn in
            try dbConn.execute(sql: """
                INSERT OR IGNORE INTO users (id, display_name, pin_hash)
                VALUES (1, 'Seed', 'x')
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_floor_plans (id, name, width_inches, length_inches)
                VALUES (1, 'Shop', 100, 100)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_units (id, floor_plan_id, name, unit_type)
                VALUES (1, 1, 'Rack', 'rack')
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_levels (id, unit_id, level_code)
                VALUES (1, 1, 'A')
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_areas (id, level_id, area_code, area_number)
                VALUES (1, 1, 'A1', 1)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_walking_paths (id, floor_plan_id, name, created_by)
                VALUES (1, 1, 'Main', 1)
                """)
            try dbConn.execute(
                sql: """
                    INSERT INTO warehouse_walking_path_stops
                        (id, path_id, area_id, sort_order, deleted_at)
                    VALUES (1, 1, 1, 1, ?),
                           (2, 1, 1, 2, '2026-01-01T00:00:00Z')
                    """,
                arguments: [otherStopDeleted ? "2026-01-01T00:00:00Z" : nil]
            )
        }
    }

    /// T-9. `UNIQUE(path_id, area_id) WHERE deleted_at IS NULL`. An un-delete
    /// carries NO index column in its SET clause, so the reduced statement is
    /// byte-identical to the one that just failed — the second shape that makes
    /// the give-up rung mandatory.
    @Test("T-9 an un-delete into an occupied partial-index slot commits and records the cause")
    func testUnDeleteIntoAnOccupiedSlotRecordsAKeyCollision() throws {
        let db = try freshDB()
        try seedWalkingPathStops(db, otherStopDeleted: false)

        let result = try applyStreamed(db, [
            update("warehouse_walking_path_stops", "2", #"{"deleted_at":null}"#),
        ])

        #expect(result.keyCollisions == 1)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        let deletedAt = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn, sql: "SELECT deleted_at FROM warehouse_walking_path_stops WHERE id = 2"
            )
        }
        #expect(deletedAt != nil, "the row is left unmodified")
    }

    /// T-9 companion. The slot's other occupant is itself soft-deleted, so
    /// SQLite's OWN partial predicate exempts it and there is no collision at
    /// all. If this ever fails, someone has hand-rolled a predicate in Swift —
    /// which is precisely the reimplementation this design refuses to do.
    @Test("T-9b a soft-deleted occupant is not a collision — SQLite's predicate decides, not us")
    func testSoftDeletedOccupantProducesNoCollision() throws {
        let db = try freshDB()
        try seedWalkingPathStops(db, otherStopDeleted: true)

        let result = try applyStreamed(db, [
            update("warehouse_walking_path_stops", "2", #"{"deleted_at":null}"#),
        ])

        #expect(result.keyCollisions == 0)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        let deletedAt = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn, sql: "SELECT deleted_at FROM warehouse_walking_path_stops WHERE id = 2"
            )
        }
        #expect(deletedAt == nil, "the un-delete landed")
    }

    // MARK: - T-11 — the index cache is read INSIDE the suspension window

    /// T-11. `suspendJobStageSortIndex` drops
    /// `idx_job_stages_template_sort_active` for the duration of an apply, so
    /// "which columns are unique on `job_stages`" has a different answer inside
    /// the apply than outside it. The enumeration must be read lazily, inside.
    ///
    /// If it were read before the drop, the ladder would withhold
    /// `job_stages.sort_order` and the #1729 seeded-permutation path — which
    /// depends on the host's ordering landing EXACTLY — would silently break.
    ///
    /// NOTE ON MUTATION TESTING, recorded honestly: priming the cache before
    /// `suspendJobStageSortIndex` does NOT turn any test red, and that is a
    /// property of the implementation rather than a gap in the tests. The cache
    /// is read from exactly one place — `resolveKeyCollisionInPlace`, i.e. only
    /// after a refusal — and while the index is suspended `job_stages` cannot
    /// produce one, so the poisoned entry is never consulted. The ordering rule
    /// is therefore structurally satisfied, not merely observed. What this test
    /// pins is the two facts that make the rule real: the enumeration genuinely
    /// differs inside and outside the window, and the cache is STICKY, so a
    /// future refactor that hoists the read has a named hazard to fail against.
    @Test("T-11 the unique-column enumeration is taken with the ordering index suspended")
    func testUniqueColumnEnumerationRunsInsideTheSuspensionWindow() throws {
        let db = try freshDB()

        var duringApply: Set<String>?
        _ = try ConflictResolver.resolveAndApplyStreamedChangesAtomically(
            db: db,
            produceChanges: { dbConn, _ in
                duringApply = try ConflictResolver.uniqueParticipatingColumns(dbConn, "job_stages")
            }
        )

        let observed = try #require(duringApply)
        #expect(!observed.contains("sort_order"),
                "the ordering index is suspended during the apply, so its key is not unique here")
        #expect(!observed.contains("template_id"))

        // …and the index came back, byte-identical, with its partial predicate.
        let after = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: """
                    SELECT sql FROM sqlite_master
                    WHERE type = 'index' AND name = 'idx_job_stages_template_sort_active'
                    """
            )
        }
        #expect(after?.contains("WHERE deleted_at IS NULL") == true,
                "restoreJobStageSortIndex must replay the captured DDL")

        // Outside the apply the same enumeration DOES see it — proving the
        // difference above is the suspension and not a broken query.
        let outsideApply = try db.writer.read { dbConn in
            try ConflictResolver.uniqueParticipatingColumns(dbConn, "job_stages")
        }
        #expect(outsideApply.contains("sort_order"))
        #expect(outsideApply.contains("template_id"))

        // The cache is STICKY: whatever it is asked first is the answer it keeps
        // for the whole apply. That is exactly why it must be created after the
        // suspension — and why it must never become a `static var`, which would
        // carry one apply's schema snapshot into the next.
        let context = ConflictResolver.ApplyContext(disposition: .batched)
        try db.writer.write { dbConn in
            let primedEarly = try context.uniqueParticipatingColumns(dbConn, "job_stages")
            #expect(primedEarly.contains("sort_order"), "outside the window it IS unique")
            try dbConn.execute(sql: "DROP INDEX idx_job_stages_template_sort_active")
            let afterDrop = try context.uniqueParticipatingColumns(dbConn, "job_stages")
            #expect(afterDrop == primedEarly,
                    "the cached answer survives the drop — so the read ORDER is load-bearing")
        }
    }

    /// Positive control for the classifier. If a future GRDB bump ever stopped
    /// activating extended result codes, every constraint failure would arrive
    /// as the primary code 19, every `case` in `classifyingRowRefusal` would
    /// fall through to `default: throw`, and the entire ladder would ship dead
    /// while all the mutation tests above still looked meaningful.
    @Test("the extended result code a UNIQUE violation actually raises")
    func testUniqueViolationRaisesTheExtendedResultCode() throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        var observed: ResultCode?
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(sql: "UPDATE part_categories SET name = 'Romex' WHERE id = 9")
            }
        } catch let error as DatabaseError {
            observed = error.extendedResultCode
        }
        #expect(observed == .SQLITE_CONSTRAINT_UNIQUE,
                "extended codes must be on, or the classifier can never match")
    }

    // MARK: - T-12 — GRDB mechanics, on the real streamed path

    /// T-12. The claim the whole design rests on, converted from a sqlite3-CLI
    /// probe into a GRDB guarantee: catching a statement-level constraint
    /// refusal leaves the transaction USABLE.
    ///
    /// Everything here happens on the real streamed path, with a cursor held
    /// open on the transaction's own connection: the refusal is raised and
    /// caught mid-walk, three further rows are then applied and COMMITTED, the
    /// refused row is byte-unchanged, and the reads after `write` returns prove
    /// the commit actually happened.
    ///
    /// If GRDB ever aborts the transaction on a caught constraint error, this is
    /// the test that says so, and the fix is `dbConn.inSavepoint { … .commit }`
    /// around each attempt — the classification does not depend on it either way.
    @Test("T-12 a caught constraint refusal leaves the transaction usable and committing")
    func testCaughtRefusalLeavesTheTransactionUsable() throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        // Only the key column, so the reduced retry has nothing left to write
        // and the row must come out completely untouched.
        let result = try applyStreamed(db, [
            update("part_categories", "9", #"{"name":"Romex"}"#),
            IncomingChange(
                deviceId: "remote-device",
                tableName: "part_categories",
                recordId: "80",
                operation: "INSERT",
                recordData: #"{"id":"80","name":"After One"}"#,
                timestamp: "2026-08-16T10:00:01Z"
            ),
            IncomingChange(
                deviceId: "remote-device",
                tableName: "part_categories",
                recordId: "81",
                operation: "INSERT",
                recordData: #"{"id":"81","name":"After Two"}"#,
                timestamp: "2026-08-16T10:00:02Z"
            ),
            update("part_categories", "5", #"{"description":"still writable"}"#),
        ])

        #expect(result.keyCollisions == 1)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        // Read AFTER the write block returned — these rows are committed.
        #expect(try categoryName(db, 9) == "THHN")
        #expect(try categoryDescription(db, 9) == "local nine",
                "the refused row must be byte-unchanged, not partially written")
        #expect(try categoryName(db, 80) == "After One")
        #expect(try categoryName(db, 81) == "After Two")
        #expect(try categoryDescription(db, 5) == "still writable",
                "a write issued after the refusal must still land")
    }

    // MARK: - The delta path records immediately, by design

    /// The per-row path has one transaction PER ROW, so there is no later row
    /// inside the transaction that could vacate the slot and no batch to replay
    /// against. A collision is therefore resolved or recorded immediately. The
    /// asymmetry with the batched paths is deliberate; this test pins it.
    @Test("the per-row delta path records a collision immediately, without a fixed point")
    func testDeltaPathRecordsCollisionsImmediately() throws {
        let db = try freshDB()
        try seedArchivedTemplate(db)

        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: [
            update("job_stage_templates", "2", #"{"archived_at":null}"#),
            update("job_stage_templates", "1", #"{"is_default":"0"}"#),
        ])

        // Same two changes in the same order that T-8b resolves to zero: with no
        // batch transaction there is nothing to replay, so it stands as residue.
        #expect(result.keyCollisions == 1)
        #expect(result.errors == 0, "a collision must not land in `errors` either")
        #expect(result.skipped == 0)
    }
}
