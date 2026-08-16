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

    private func insert(
        _ table: String,
        _ recordId: String,
        _ recordDataJSON: String,
        timestamp: String = "2026-08-16T10:00:00Z"
    ) -> IncomingChange {
        IncomingChange(
            deviceId: "remote-device",
            tableName: table,
            recordId: recordId,
            operation: "INSERT",
            recordData: recordDataJSON,
            timestamp: timestamp
        )
    }

    private func delete(
        _ table: String,
        _ recordId: String,
        timestamp: String = "2026-08-16T10:00:00Z"
    ) -> IncomingChange {
        IncomingChange(
            deviceId: "remote-device",
            tableName: table,
            recordId: recordId,
            operation: "DELETE",
            timestamp: timestamp
        )
    }

    private func categoryDeletedAt(_ db: AppDatabase, _ id: Int) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn, sql: "SELECT deleted_at FROM part_categories WHERE id = ?", arguments: [id]
            )
        }
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

    // MARK: - T-15/T-16/T-17 — deferral must not RE-ORDER a record's history

    /// T-15. A parked merge replayed at the END of the batch is applied after a
    /// DELETE that arrived AFTER it — and the record comes back from the dead.
    ///
    /// A delta batch is the raw `_change_log` ordered by timestamp/sequence with
    /// no per-record dedup (`ChangeTracker.getPendingChanges`), so several
    /// changes to one record in one batch is the ORDINARY shape. Within a batch
    /// nothing consults timestamps for a field the peer alone changed —
    /// `fieldLevelMerge` accepts the remote value outright when the field is not
    /// in `getLocalChangedFields` — so arrival order IS the merge semantics, and
    /// deferral inverts it.
    ///
    /// The bug this pins was invisible to every existing signal: the replay
    /// SUCCEEDS, so `applied`, `keyCollisions`, `errors` and `skipped` all read
    /// exactly as they do on a clean batch, and the replay runs under
    /// `_sync_apply_guard`, so the corrupted row is never tracked or pushed
    /// back. Two devices diverge permanently with nothing in any ledger.
    ///
    /// MUTATION CHECK: delete the `context.isSuperseded(entry)` arm from
    /// `replayDeferredMerges` and this goes red — `deleted_at` becomes NULL,
    /// `supersededMerges` becomes 0, and the record is back.
    @Test("T-15 a later DELETE is not undone by a replayed merge — the record stays deleted")
    func testDeferredMergeDoesNotResurrectARecordDeletedLaterInTheBatch() throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        let result = try applyStreamed(db, [
            // Wants 'THHN', which id 9 still holds → parked at position 1.
            insert(
                "part_categories", "5",
                #"{"id":"5","name":"THHN","deleted_at":null}"#,
                timestamp: "2026-08-16T10:00:00Z"
            ),
            // Vacates the slot, so the parked merge WOULD succeed on replay.
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            // …but the peer deleted the record after that.
            delete("part_categories", "5", timestamp: "2026-08-16T10:00:02Z"),
        ])

        #expect(try categoryDeletedAt(db, 5) != nil,
                "the DELETE must stick — a replayed merge may not resurrect the record")
        #expect(try categoryName(db, 5) == "Romex",
                "the superseded payload must not be written at all")
        #expect(try categoryName(db, 9) == "Zebra", "the change that vacated the slot still applied")

        // Visible, not silent: its own cause, and never a gate input.
        #expect(result.supersededMerges == 1, "the discard must be counted")
        #expect(result.keyCollisions == 0,
                "no index refused anything here — this is not a collision outcome")
        #expect(result.skipped == 0, "a discard may NEVER produce a gate input (#1749)")
        #expect(result.errors == 0)

        // The matched control: the same batch, with the parked change aimed at a
        // FREE name so nothing defers. The DELETE sticks there too — which is
        // what makes the assertion above about DEFERRAL and not about DELETE.
        let control = try freshDB()
        try seedTwoCategories(control)
        _ = try applyStreamed(control, [
            insert(
                "part_categories", "5",
                #"{"id":"5","name":"Unclaimed","deleted_at":null}"#,
                timestamp: "2026-08-16T10:00:00Z"
            ),
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            delete("part_categories", "5", timestamp: "2026-08-16T10:00:02Z"),
        ])
        #expect(try categoryDeletedAt(control, 5) != nil)
        #expect(try categoryName(control, 5) == "Unclaimed", "nothing was deferred in the control")
    }

    /// T-16. The same re-ordering, one step less dramatic and one step more
    /// corrosive: a parked merge replayed after a NEWER update to the same
    /// record overwrites the newer values with older ones.
    ///
    /// It also rewrites `updated_at`, which is the LWW authority for every
    /// FUTURE merge of that row — so one silent replay keeps deciding later
    /// conflicts wrongly long after the batch is forgotten.
    ///
    /// The discarded payload's `name` is NOT applied either, and that is the
    /// deliberate choice: the change is dropped whole. Applying a subset would
    /// be inventing a third version of the record that neither device ever had.
    ///
    /// MUTATION CHECK: delete the `context.isSuperseded(entry)` arm and the
    /// description assertion goes red with "from C1 (older)".
    @Test("T-16 a replayed merge does not overwrite a newer change to the same record")
    func testDeferredMergeDoesNotOverwriteANewerChangeInTheSameBatch() throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        let result = try applyStreamed(db, [
            // Collides on 'THHN' → parked at position 1, carrying the OLD description.
            update("part_categories", "5", #"{"name":"THHN","description":"from C1 (older)"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            // Vacates the slot.
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            // The NEWER description for the same record.
            update("part_categories", "5", #"{"description":"from C3 (newer)"}"#,
                   timestamp: "2026-08-16T10:00:02Z"),
        ])

        #expect(try categoryDescription(db, 5) == "from C3 (newer)",
                "the newest change to the record must win")
        #expect(try categoryName(db, 5) == "Romex", "the superseded payload is dropped whole")

        #expect(result.supersededMerges == 1)
        #expect(result.keyCollisions == 0)
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        // Matched control: nothing collides, so nothing is parked, and the same
        // final description is reached by plain in-order application.
        let control = try freshDB()
        try seedTwoCategories(control)
        _ = try applyStreamed(control, [
            update("part_categories", "5", #"{"name":"Unclaimed","description":"from C1 (older)"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            update("part_categories", "5", #"{"description":"from C3 (newer)"}"#,
                   timestamp: "2026-08-16T10:00:02Z"),
        ])
        #expect(try categoryDescription(control, 5) == "from C3 (newer)")
        #expect(try categoryName(control, 5) == "Unclaimed")
    }

    /// T-17. The convergence LOOP, not just the fixed point.
    ///
    /// T-8b converges in a single pass, so until this test existed the `while`
    /// loop in `drainDeferredMerges` was dead weight as far as the suite knew:
    /// deleting it and keeping one drain left everything green. A mutation pass
    /// found that, and this is the answer.
    ///
    /// The chain is FOUR deep: id 4 wants the name id 3 holds, id 3 wants id 2's,
    /// id 2 wants id 1's, and only id 1's rename is free to land immediately.
    /// A pass replays the buffer in arrival order, so each pass can free exactly
    /// one more link — the entry ahead of it in the buffer is always retried
    /// BEFORE the row it is waiting on has moved. Three replay passes are
    /// required, and the head change makes four changes in the batch.
    ///
    /// FOUR deep, not three, and the reason is worth recording: the drain is
    /// `while`-loop passes PLUS one final draining pass, and that final pass is
    /// itself a fully effective retry (it merely may not re-park). A three-deep
    /// chain therefore still converges with the cap set to 1, and the first
    /// draft of this test passed that mutation. Depth four is the shallowest
    /// chain that needs more passes than "one loop iteration plus the drain".
    ///
    /// MUTATION CHECKS, both must go red here:
    /// - delete the `while` loop and keep the single draining pass →
    ///   `keyCollisions == 2`, ids 3 and 4 keep their old names;
    /// - set `ApplyContext.maxReplayPasses = 1` → `keyCollisions == 1` and id 4
    ///   keeps its old name.
    @Test("T-17 a four-deep vacancy chain needs more than one replay pass")
    func testDeepChainRequiresMultipleReplayPasses() throws {
        let db = try freshDB()
        try seed(db) { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO part_categories (id, name, updated_at)
                VALUES (1, 'N1', '2020-01-01T00:00:00Z'),
                       (2, 'N2', '2020-01-01T00:00:00Z'),
                       (3, 'N3', '2020-01-01T00:00:00Z'),
                       (4, 'N4', '2020-01-01T00:00:00Z')
                """)
        }

        let result = try applyStreamed(db, [
            // Blocked by id 3, and still blocked in passes 1 and 2.
            update("part_categories", "4", #"{"name":"N3"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            // Blocked by id 2; lands in pass 2.
            update("part_categories", "3", #"{"name":"N2"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            // Blocked by id 1; lands in pass 1.
            update("part_categories", "2", #"{"name":"N1"}"#,
                   timestamp: "2026-08-16T10:00:02Z"),
            // Free immediately — the head of the chain.
            update("part_categories", "1", #"{"name":"Vacated"}"#,
                   timestamp: "2026-08-16T10:00:03Z"),
        ])

        #expect(result.keyCollisions == 0, "every link in the chain must resolve")
        #expect(result.supersededMerges == 0, "each record is touched exactly once")
        #expect(result.skipped == 0)
        #expect(result.errors == 0)

        #expect(try categoryName(db, 1) == "Vacated")
        #expect(try categoryName(db, 2) == "N1", "freed by pass 1")
        #expect(try categoryName(db, 3) == "N2", "freed by pass 2")
        #expect(try categoryName(db, 4) == "N3", "freed only by pass 3 — this is the loop")
    }

    // MARK: - T-18 — a change that WRITES NOTHING supersedes nothing

    /// Apply through the in-memory batched path — one transaction for the whole
    /// batch, and NO completeness gate.
    ///
    /// Used for exactly one sub-case below: an unrecognised operation verb is a
    /// pre-existing producer of `skipped` (`applyOneAtomically`'s `default:`
    /// arm, unchanged by this commit), and the SNAPSHOT gate throws on `skipped`
    /// by design. Running that shape through `applyStreamed` would test the
    /// gate, not the supersession rule.
    private func applyAtomicBatch(
        _ db: AppDatabase,
        _ changes: [IncomingChange]
    ) throws -> MergeResult {
        try ConflictResolver.resolveAndApplyChangesAtomically(db: db, changes: changes)
    }

    /// The first two changes of T-18's batch: a merge that collides on `name`
    /// and parks at position 1, then the change that vacates the slot — so the
    /// parked merge is guaranteed to land on replay unless something discards it.
    private var parkedThenVacated: [IncomingChange] {
        [
            update("part_categories", "5",
                   #"{"name":"THHN","description":"parked payload"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
        ]
    }

    /// Run `parkedThenVacated` + `trailer`, and require the trailer to have
    /// changed NOTHING about the parked merge's fate.
    ///
    /// The matched control is the identical batch with the trailer REMOVED.
    /// That equality is the entire discrimination: the trailer is a change that
    /// writes nothing, so a batch with it and a batch without it must reach the
    /// same rows. If they differ, something that wrote nothing was counted as a
    /// write — which is the regression this pins.
    private func expectWriteNothingTrailerChangesNothing(
        _ trailer: IncomingChange,
        applying apply: (AppDatabase, [IncomingChange]) throws -> MergeResult,
        andAlso extraChecks: (MergeResult) throws -> Void = { _ in }
    ) throws {
        let db = try freshDB()
        try seedTwoCategories(db)
        let result = try apply(db, parkedThenVacated + [trailer])

        #expect(try categoryName(db, 5) == "THHN",
                "the parked merge must still land on replay")
        #expect(try categoryDescription(db, 5) == "parked payload",
                "…with its payload — the write the parent commit applied successfully")
        #expect(result.supersededMerges == 0,
                "nothing superseded it: the trailing change wrote nothing at all")
        #expect(result.errors == 0)
        try extraChecks(result)

        // MATCHED CONTROL — same batch, trailer removed.
        let control = try freshDB()
        try seedTwoCategories(control)
        let controlResult = try apply(control, parkedThenVacated)
        #expect(try categoryName(control, 5) == "THHN")
        #expect(try categoryDescription(control, 5) == "parked payload")
        #expect(controlResult.supersededMerges == 0)
    }

    /// T-18. The supersession rule (#1737, second commit) counted ARRIVAL, not
    /// writing: `noteChangeArriving` ran before the allowed-table guard and
    /// before dispatch, and refreshed the record's ordinal for ANY change
    /// naming an already-parked record. A trailing change that wrote nothing
    /// therefore discarded the parked merge, and BOTH changes were lost —
    /// permanently, because the discard runs under `_sync_apply_guard` so
    /// nothing is re-broadcast and the peer's watermark advances anyway.
    ///
    /// Three shapes reach the dispatcher and write nothing. Each gets its own
    /// test because each takes a different route to "nothing happened", and a
    /// single fix that only covered one of them would still ship the bug.
    ///
    /// MUTATION CHECK for all three: call
    /// `context.noteRecordMutated(table:recordId:)` unconditionally from
    /// `applyOneAtomically`, right after `noteChangeArriving()` — that is
    /// literally the reverted behaviour — and all three go red with
    /// `supersededMerges == 1` and the record left at `Romex` / `local five`.
    @Test("T-18a a NOT NULL refusal writes nothing, so it supersedes nothing")
    func testSchemaDropTrailerDoesNotSupersedeAParkedMerge() throws {
        // `part_categories.name` is NOT NULL, so this merge is refused outright
        // and the row is left exactly as it was (`schemaDrop`, no ladder).
        try expectWriteNothingTrailerChangesNothing(
            update("part_categories", "5", #"{"name":null}"#,
                   timestamp: "2026-08-16T10:00:02Z"),
            applying: applyStreamed
        ) { result in
            #expect(result.schemaDrops == 1,
                    "the trailer really was refused — the shape is what it claims to be")
            #expect(result.skipped == 0, "a refusal may NEVER produce a gate input (#1749)")
        }
    }

    @Test("T-18b an unrecognised operation verb writes nothing, so it supersedes nothing")
    func testUnknownOperationTrailerDoesNotSupersedeAParkedMerge() throws {
        try expectWriteNothingTrailerChangesNothing(
            IncomingChange(
                deviceId: "remote-device",
                tableName: "part_categories",
                recordId: "5",
                operation: "PURGE",
                timestamp: "2026-08-16T10:00:02Z"
            ),
            applying: applyAtomicBatch
        ) { result in
            // Pre-existing behaviour, asserted so the test cannot silently stop
            // exercising the shape: an unknown verb is `skipped` and always was.
            // This commit adds no producer of `skipped` or `errors`.
            #expect(result.skipped == 1, "the unknown verb is the pre-existing skip")
        }
    }

    @Test("T-18c an UPDATE carrying no fields at all writes nothing, so it supersedes nothing")
    func testFieldlessUpdateTrailerDoesNotSupersedeAParkedMerge() throws {
        // The sharpest shape: `applyUpdate` returns before touching the database
        // (no `changed_fields` AND no `record_data`), the change is counted
        // `applied: 1`, it produces no gate input — and at HEAD it still killed
        // the parked merge.
        try expectWriteNothingTrailerChangesNothing(
            IncomingChange(
                deviceId: "remote-device",
                tableName: "part_categories",
                recordId: "5",
                operation: "UPDATE",
                timestamp: "2026-08-16T10:00:02Z"
            ),
            applying: applyStreamed
        ) { result in
            #expect(result.applied == 3, "it is counted applied — that is what made it invisible")
            #expect(result.skipped == 0, "and it passes the snapshot gate, so nothing warns")
        }
    }

    // MARK: - T-19 — supersession keys on the ROW, not on the peer's spelling

    /// T-19. `IncomingChange` is peer-controlled wire input, and two spellings
    /// of one row reach the SAME row: `isAllowedTable` lowercases before
    /// checking the whitelist (and SQLite identifiers are case-insensitive), and
    /// `WHERE id = ?` bound with `'05'` matches row 5 by INTEGER affinity.
    ///
    /// If the supersession key does not normalise both, the later change writes
    /// the record, the lookup misses, and the parked merge replays over it —
    /// the original #1737 BLOCKING defect, verbatim.
    ///
    /// Both cases are T-16's batch with ONLY the trailing change respelled, so
    /// the canonical run (T-16 itself, plus the control here) is the matched
    /// comparison.
    ///
    /// MUTATION CHECK: revert `ApplyContext.recordKey` to
    /// `"\(table)\u{1}\(recordId)"` and both go red — `description` becomes
    /// "from C1 (older)" and `supersededMerges` becomes 0.
    @Test("T-19a a case-variant table name still supersedes — the ROW decides, not the spelling")
    func testSupersessionSurvivesACaseVariantTableName() throws {
        try expectNewerChangeWins(
            trailer: update("Part_Categories", "5", #"{"description":"from C3 (newer)"}"#,
                            timestamp: "2026-08-16T10:00:02Z")
        )
    }

    @Test("T-19b a zero-padded record id still supersedes — INTEGER affinity decides")
    func testSupersessionSurvivesAZeroPaddedRecordId() throws {
        try expectNewerChangeWins(
            trailer: update("part_categories", "05", #"{"description":"from C3 (newer)"}"#,
                            timestamp: "2026-08-16T10:00:02Z")
        )
    }

    /// The third spelling `recordKey` normalises, and the reason it is here
    /// rather than assumed: `WHERE id = ?` was MEASURED to match row 5 for
    /// `' 5'`, `'5 '`, `'\n5'` and `'\t5'` as well as `'05'`. Untested
    /// normalisation is just an untested guess.
    @Test("T-19c a whitespace-padded record id still supersedes")
    func testSupersessionSurvivesAWhitespacePaddedRecordId() throws {
        try expectNewerChangeWins(
            trailer: update("part_categories", " 5", #"{"description":"from C3 (newer)"}"#,
                            timestamp: "2026-08-16T10:00:02Z")
        )
    }

    /// T-16's batch with a substituted trailing change: the NEWER change must
    /// win, i.e. supersession must still fire.
    private func expectNewerChangeWins(trailer: IncomingChange) throws {
        let db = try freshDB()
        try seedTwoCategories(db)

        let result = try applyStreamed(db, [
            // Collides on 'THHN' → parked at position 1, carrying the OLD description.
            update("part_categories", "5", #"{"name":"THHN","description":"from C1 (older)"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            // Vacates the slot, so the parked merge WOULD land on replay.
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            trailer,
        ])

        #expect(try categoryDescription(db, 5) == "from C3 (newer)",
                "the newest write to the record must win, however the peer spelled it")
        #expect(try categoryName(db, 5) == "Romex", "the superseded payload is dropped whole")
        #expect(result.supersededMerges == 1, "the discard must be counted")
        #expect(result.keyCollisions == 0)
        #expect(result.skipped == 0, "a discard may NEVER produce a gate input (#1749)")
        #expect(result.errors == 0)

        // MATCHED CONTROL — the canonical spelling, same batch, same assertions.
        let control = try freshDB()
        try seedTwoCategories(control)
        let controlResult = try applyStreamed(control, [
            update("part_categories", "5", #"{"name":"THHN","description":"from C1 (older)"}"#,
                   timestamp: "2026-08-16T10:00:00Z"),
            update("part_categories", "9", #"{"name":"Zebra"}"#,
                   timestamp: "2026-08-16T10:00:01Z"),
            update("part_categories", "5", #"{"description":"from C3 (newer)"}"#,
                   timestamp: "2026-08-16T10:00:02Z"),
        ])
        #expect(try categoryDescription(control, 5) == "from C3 (newer)")
        #expect(controlResult.supersededMerges == 1)
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
    /// produce one, so the poisoned entry is never consulted. What this test
    /// pins is the two facts that make the rule real: the enumeration genuinely
    /// differs inside and outside the window, and the cache is STICKY, so a
    /// future refactor that hoists the read has a named hazard to fail against.
    ///
    /// CORRECTION (this commit): the sentence that used to follow — "the
    /// ordering rule is therefore structurally satisfied" — overclaimed. It
    /// holds on the two BATCHED paths only. `resolveAndApplyChanges`, the
    /// per-row delta path, never calls `suspendJobStageSortIndex` at all, so
    /// there the enumeration DOES report `sort_order`, the ladder withholds it,
    /// and a `job_stages` merge can land half-applied with a `_conflict_log` row
    /// claiming a local edit won when in fact an index refused the write. See
    /// the caveat on `ConflictResolver.ApplyContext`; unfixed here on purpose.
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
