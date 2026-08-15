import Testing
import Foundation
import GRDB
@testable import WiredPartCore

@Suite("ConflictResolver Tests")
struct ConflictResolverTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    private var now: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    /// Insert a user directly for testing merge scenarios.
    @discardableResult
    private func insertUser(
        db: AppDatabase,
        displayName: String = "Test User",
        email: String? = nil,
        phone: String? = nil
    ) throws -> Int64 {
        var user = User(displayName: displayName, pinHash: "fakehash", isActive: 1)
        user.email = email
        user.phone = phone
        try db.writer.write { dbConn in
            try user.insert(dbConn)
        }
        return user.id!
    }

    // MARK: - resolveAndApplyChanges

    @Test("Empty change list returns zero result")
    func testEmptyChanges() throws {
        let db = try freshDB()
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: [])
        #expect(result.applied == 0)
        #expect(result.conflicts == 0)
        #expect(result.errors == 0)
        #expect(result.skipped == 0)
    }

    // MARK: - INSERT Operations

    @Test("INSERT into empty table succeeds")
    func testInsertNew() throws {
        let db = try freshDB()
        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "1",
                operation: "INSERT",
                recordData: """
                {"id":"1","display_name":"Remote User","pin_hash":"hash","is_active":"1"}
                """,
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1)
        #expect(result.conflicts == 0)

        // Verify user was inserted
        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: 1)
        }
        #expect(user?.displayName == "Remote User")
    }

    @Test("INSERT merge: no local changes accepts all remote fields")
    func testInsertMergeNoLocalChanges() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Local User", email: "local@test.com")

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "INSERT",
                recordData: """
                {"id":"\(userId)","display_name":"Remote User","pin_hash":"hash","email":"remote@test.com","is_active":"1"}
                """,
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1)
        // No conflict because there are no unsynced local changes
        #expect(result.conflicts == 0)

        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        // Remote values should be applied since no local unsynced changes
        #expect(user?.email == "remote@test.com")
    }

    @Test("INSERT conflict: both modified same field, remote newer wins")
    func testInsertConflictRemoteWins() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original", email: "orig@test.com")

        // Simulate local unsynced change to email
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: userId,
            operation: .update,
            changedFields: ["email": "local@test.com"],
            deviceId: "local-device"
        )

        // Update the local row to match
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET email = ?, updated_at = ? WHERE id = ?",
                arguments: ["local@test.com", "2026-03-14T09:00:00Z", userId]
            )
        }

        // Remote change with LATER timestamp
        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "INSERT",
                recordData: """
                {"id":"\(userId)","display_name":"Original","pin_hash":"fakehash","email":"remote@test.com","is_active":"1"}
                """,
                timestamp: "2026-03-14T11:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-device"
        )
        #expect(result.applied == 1)
        #expect(result.conflicts > 0)

        // Remote wins because its timestamp is later
        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        #expect(user?.email == "remote@test.com")
    }

    @Test("INSERT conflict: both modified same field, local newer wins")
    func testInsertConflictLocalWins() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original", email: "orig@test.com")

        // Simulate local unsynced change to email
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: userId,
            operation: .update,
            changedFields: ["email": "local@test.com"],
            deviceId: "local-device"
        )

        // Update local row with LATER timestamp
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET email = ?, updated_at = ? WHERE id = ?",
                arguments: ["local@test.com", "2026-03-14T12:00:00Z", userId]
            )
        }

        // Remote change with EARLIER timestamp
        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "INSERT",
                recordData: """
                {"id":"\(userId)","display_name":"Original","pin_hash":"fakehash","email":"remote@test.com","is_active":"1"}
                """,
                timestamp: "2026-03-14T08:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-device"
        )
        #expect(result.applied == 1)
        #expect(result.conflicts > 0)

        // Local wins because its updated_at is later
        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        #expect(user?.email == "local@test.com")
    }

    // MARK: - UPDATE Operations

    @Test("UPDATE with changed_fields applies non-conflicting fields")
    func testUpdateNonConflicting() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original", email: "orig@test.com")

        // Local change to display_name (unsynced)
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: userId,
            operation: .update,
            changedFields: ["display_name": "Local Name"],
            deviceId: "local-device"
        )

        // Remote change to email (different field — no conflict)
        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                changedFields: "{\"email\":\"remote@test.com\"}",
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-device"
        )
        #expect(result.applied == 1)
        #expect(result.conflicts == 0)

        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        // Remote email accepted, local display_name preserved
        #expect(user?.email == "remote@test.com")
    }

    @Test("UPDATE conflict: remote wins")
    func testUpdateConflictRemoteWins() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original")

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: userId,
            operation: .update,
            changedFields: ["display_name": "Local"],
            deviceId: "local-device"
        )
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?",
                arguments: ["Local", "2026-03-14T09:00:00Z", userId]
            )
        }

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                changedFields: "{\"display_name\":\"Remote\"}",
                timestamp: "2026-03-14T11:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-device"
        )
        #expect(result.conflicts > 0)

        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        #expect(user?.displayName == "Remote")
    }

    @Test("UPDATE conflict: local wins")
    func testUpdateConflictLocalWins() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original")

        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: userId,
            operation: .update,
            changedFields: ["display_name": "Local"],
            deviceId: "local-device"
        )
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET display_name = ?, updated_at = ? WHERE id = ?",
                arguments: ["Local", "2026-03-14T12:00:00Z", userId]
            )
        }

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                changedFields: "{\"display_name\":\"Remote\"}",
                timestamp: "2026-03-14T08:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-device"
        )
        #expect(result.conflicts > 0)

        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        #expect(user?.displayName == "Local")
    }

    @Test("UPDATE missing record with record_data inserts it")
    func testUpdateMissingRecordWithData() throws {
        let db = try freshDB()
        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "999",
                operation: "UPDATE",
                changedFields: "{\"display_name\":\"Updated\"}",
                recordData: """
                {"id":"999","display_name":"Updated","pin_hash":"hash","is_active":"1"}
                """,
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1)

        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: 999)
        }
        #expect(user?.displayName == "Updated")
    }

    // MARK: - DELETE Operations

    @Test("DELETE soft-deletes when deleted_at column exists")
    func testSoftDelete() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "To Delete")

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "DELETE",
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1)

        // User should still exist but with deleted_at set
        let user = try db.writer.read { dbConn in
            try User.fetchOne(dbConn, key: userId)
        }
        #expect(user != nil)
        #expect(user?.deletedAt != nil)
    }

    @Test("DELETE hard-deletes when no deleted_at column")
    func testHardDelete() throws {
        let db = try freshDB()

        // _change_log has no deleted_at column — should fall back to hard DELETE
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO _change_log (device_id, table_name, record_id, operation)
                    VALUES ('test', 'test_table', 99, 'INSERT')
                    """
            )
        }

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "_change_log",
                recordId: "1",
                operation: "DELETE",
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1)
    }

    /// The soft-delete branch used to be chosen by TRYING the UPDATE and treating
    /// ANY thrown error as proof the table had no `deleted_at` column. SQLite reports
    /// a missing column as the generic result code 1, indistinguishable from a locked
    /// database or a trigger abort — so a transient failure on a table that DOES
    /// soft-delete was answered by permanently destroying the row.
    ///
    /// Here the table plainly has `deleted_at` and the UPDATE fails for an unrelated
    /// reason. The record must survive and the failure must be reported.
    @Test("a failing soft-delete UPDATE must not fall through to a hard delete")
    func testSoftDeleteFailureDoesNotHardDelete() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Must Survive")

        // Make the soft-delete UPDATE fail for a reason that is NOT a missing column.
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                CREATE TRIGGER users_block_soft_delete
                BEFORE UPDATE OF deleted_at ON users
                BEGIN
                    SELECT RAISE(ABORT, 'simulated transient failure');
                END
                """)
        }

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "DELETE",
                timestamp: "2026-03-14T10:00:00Z"
            )
        ]
        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)

        #expect(result.applied == 0, "a delete that could not be applied must not count as applied")
        #expect(result.errors == 1, "the failure must be reported, not swallowed")

        let user = try db.writer.read { dbConn in try User.fetchOne(dbConn, key: userId) }
        #expect(user != nil, "the row must NOT have been hard-deleted by the fallback")
        #expect(user?.deletedAt == nil, "and it must not appear soft-deleted either")
    }

    /// #1733. `clock_out_questions` had no `deleted_at`, so an inbound synced delete
    /// hard-deleted it — orphaning the receiver's `clock_out_responses`, whose
    /// `question_id` is NOT NULL REFERENCES with no ON DELETE clause.
    ///
    /// Reachable with no exotic state: the office device can only delete a question
    /// that has no answers *locally*, which is exactly the offline case where a field
    /// phone has answered it and the office has not received that answer yet.
    @Test("deleting a clock-out question a peer has answered soft-deletes and keeps the answer")
    func testClockOutQuestionDeleteDoesNotOrphanResponses() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Electrician")

        let (questionId, responseId) = try db.writer.write { dbConn -> (Int64, Int64) in
            try dbConn.execute(
                sql: "INSERT INTO jobs (job_number, job_name) VALUES ('J-1', 'Test Job')"
            )
            let jobId = dbConn.lastInsertedRowID
            try dbConn.execute(
                sql: "INSERT INTO labor_entries (user_id, job_id, clock_in) VALUES (?, ?, '2026-08-15T08:00:00Z')",
                arguments: [userId, jobId]
            )
            let entryId = dbConn.lastInsertedRowID
            try dbConn.execute(
                sql: """
                    INSERT INTO clock_out_questions (question_text, answer_type, is_required, sort_order)
                    VALUES ('What did you finish today?', 'text', 1, 1)
                    """
            )
            let qId = dbConn.lastInsertedRowID
            // The answer this device holds and the deleting device has never seen.
            try dbConn.execute(
                sql: """
                    INSERT INTO clock_out_responses (labor_entry_id, question_id, answer_text)
                    VALUES (?, ?, 'Pulled wire on the third floor')
                    """,
                arguments: [entryId, qId]
            )
            return (qId, dbConn.lastInsertedRowID)
        }

        // A co-travelling edit in the same batch. Before the fix the delete failed,
        // and on the atomic snapshot path that failure takes the whole batch with it.
        let changes = [
            IncomingChange(
                deviceId: "office-mac",
                tableName: "clock_out_questions",
                recordId: "\(questionId)",
                operation: "DELETE",
                timestamp: "2026-08-15T09:00:00Z"
            ),
            IncomingChange(
                deviceId: "office-mac",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                recordData: #"{"id":"\#(userId)","display_name":"Renamed By Office"}"#,
                timestamp: "2026-08-15T09:00:01Z"
            )
        ]

        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 2, "both changes must apply")
        #expect(result.errors == 0, "the delete must no longer fail against a live child row")

        try db.writer.read { dbConn in
            let deletedAt = try String.fetchOne(
                dbConn,
                sql: "SELECT deleted_at FROM clock_out_questions WHERE id = ?",
                arguments: [questionId]
            )
            #expect(deletedAt != nil, "the question must be soft-deleted, not destroyed")

            let answer = try String.fetchOne(
                dbConn,
                sql: "SELECT answer_text FROM clock_out_responses WHERE id = ?",
                arguments: [responseId]
            )
            #expect(answer == "Pulled wire on the third floor", "the electrician's answer must survive")

            let renamed = try String.fetchOne(
                dbConn,
                sql: "SELECT display_name FROM users WHERE id = ?",
                arguments: [userId]
            )
            #expect(renamed == "Renamed By Office", "the co-travelling change must not be lost")
        }
    }

    /// A retired question stops being asked, but the answers already given for it
    /// remain readable against the labor entries that carry them.
    @Test("a soft-deleted clock-out question is hidden from new clock-outs but kept in history")
    func testSoftDeletedQuestionHiddenGoingForwardOnly() throws {
        let db = try freshDB()
        let jobs = JobsService(db: db)
        let settings = SettingsService(db: db)
        let userId = try insertUser(db: db, displayName: "Electrician")

        let (questionId, entryId) = try db.writer.write { dbConn -> (Int64, Int64) in
            try dbConn.execute(
                sql: "INSERT INTO jobs (job_number, job_name) VALUES ('J-2', 'Test Job')"
            )
            let jobId = dbConn.lastInsertedRowID
            try dbConn.execute(
                sql: "INSERT INTO labor_entries (user_id, job_id, clock_in) VALUES (?, ?, '2026-08-15T08:00:00Z')",
                arguments: [userId, jobId]
            )
            let eId = dbConn.lastInsertedRowID
            try dbConn.execute(
                sql: """
                    INSERT INTO clock_out_questions (question_text, answer_type, is_required, sort_order)
                    VALUES ('Retired question', 'text', 1, 99)
                    """
            )
            let qId = dbConn.lastInsertedRowID
            try dbConn.execute(
                sql: """
                    INSERT INTO clock_out_responses (labor_entry_id, question_id, answer_text)
                    VALUES (?, ?, 'Answered before it was retired')
                    """,
                arguments: [eId, qId]
            )
            return (qId, eId)
        }

        #expect(try jobs.getActiveQuestions().contains { $0.questionId == questionId })

        try settings.deleteClockOutQuestion(id: "\(questionId)")

        #expect(
            try jobs.getActiveQuestions().allSatisfy { $0.questionId != questionId },
            "a retired question must not be asked again"
        )
        #expect(
            try settings.listClockOutQuestions().allSatisfy { $0.id != "\(questionId)" },
            "and must not appear in the admin list"
        )
        #expect(
            try jobs.getResponsesForEntry(laborEntryId: entryId).contains {
                $0.questionId == questionId
            },
            "but the answer already given for it must remain in history"
        )
    }

    // MARK: - Conflict Logging

    @Test("Conflict log entries have correct fields")
    func testConflictLogEntries() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original", email: "orig@test.com")

        // Create local unsynced change to email
        try ChangeTracker.trackChange(
            db: db,
            tableName: "users",
            recordId: userId,
            operation: .update,
            changedFields: ["email": "local@test.com"],
            deviceId: "local-dev"
        )
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE users SET email = ?, updated_at = ? WHERE id = ?",
                arguments: ["local@test.com", "2026-03-14T09:00:00Z", userId]
            )
        }

        // Remote change with later timestamp (remote wins)
        let changes = [
            IncomingChange(
                deviceId: "remote-dev",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                changedFields: "{\"email\":\"remote@test.com\"}",
                timestamp: "2026-03-14T11:00:00Z"
            )
        ]
        _ = try ConflictResolver.resolveAndApplyChanges(
            db: db, changes: changes, localDeviceId: "local-dev"
        )

        // Check _conflict_log
        let conflicts = try ConflictResolver.getUnreviewedConflicts(db: db)
        #expect(conflicts.count == 1)

        let entry = conflicts[0]
        #expect(entry.tableName == "users")
        #expect(entry.recordId == "\(userId)")
        #expect(entry.fieldName == "email")
        #expect(entry.winner == "remote")
        #expect(entry.localDevice == "local-dev")
        #expect(entry.remoteDevice == "remote-dev")
        #expect(entry.reviewed == 0)
    }

    // MARK: - Admin Review API

    @Test("getUnreviewedConflicts and markConflictReviewed")
    func testAdminReview() throws {
        let db = try freshDB()

        // Insert a conflict directly
        try db.writer.write { dbConn in
            var conflict = ConflictLogEntry(
                tableName: "users",
                recordId: "1",
                fieldName: "email",
                localValue: "a@test.com",
                remoteValue: "b@test.com",
                winner: "remote",
                localDevice: "dev-A",
                remoteDevice: "dev-B",
                localTs: "2026-03-14T09:00:00Z",
                remoteTs: "2026-03-14T10:00:00Z",
                resolvedAt: now
            )
            try conflict.insert(dbConn)
        }

        let unreviewed = try ConflictResolver.getUnreviewedConflicts(db: db)
        #expect(unreviewed.count == 1)

        let stats = try ConflictResolver.getConflictStats(db: db)
        #expect(stats.total == 1)
        #expect(stats.unreviewed == 1)

        try ConflictResolver.markConflictReviewed(db: db, conflictId: unreviewed[0].id!)

        let afterReview = try ConflictResolver.getUnreviewedConflicts(db: db)
        #expect(afterReview.count == 0)

        let statsAfter = try ConflictResolver.getConflictStats(db: db)
        #expect(statsAfter.total == 1)
        #expect(statsAfter.unreviewed == 0)

        #expect(throws: ConflictResolver.ConflictReviewError.self) {
            try ConflictResolver.markConflictReviewed(db: db, conflictId: unreviewed[0].id!)
        }
        #expect(throws: ConflictResolver.ConflictReviewError.self) {
            try ConflictResolver.markConflictReviewed(db: db, conflictId: Int64.max)
        }
    }

    // MARK: - applyConflictResolution (manual review must actually apply the choice)

    private func insertConflict(
        db: AppDatabase,
        recordId: Int64,
        winner: String
    ) throws {
        try db.writer.write { dbConn in
            var conflict = ConflictLogEntry(
                tableName: "users",
                recordId: String(recordId),
                fieldName: "email",
                localValue: "loser@local.com",
                remoteValue: "winner@remote.com",
                winner: winner,
                localDevice: "dev-A",
                remoteDevice: "dev-B",
                localTs: "2026-03-14T09:00:00Z",
                remoteTs: "2026-03-14T10:00:00Z",
                resolvedAt: now
            )
            try conflict.insert(dbConn)
        }
    }

    @Test("applyConflictResolution writes the chosen loser value and change-logs it")
    func testApplyResolutionWritesLoserValue() throws {
        let db = try freshDB()
        // LWW already applied the remote winner to the row.
        let userId = try insertUser(db: db, email: "winner@remote.com")
        try insertConflict(db: db, recordId: userId, winner: "remote")
        // Clear the trigger/backfill entries so the change-log assertions below
        // see only what applyConflictResolution itself records.
        try db.writer.write { try $0.execute(sql: "DELETE FROM _change_log") }
        let conflict = try ConflictResolver.getUnreviewedConflicts(db: db)[0]

        // Reviewer overrides LWW and keeps the LOCAL (losing) value.
        try ConflictResolver.applyConflictResolution(db: db, conflict: conflict, choice: .keepLocal)

        let email = try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT email FROM users WHERE id = ?", arguments: [userId])
        }
        #expect(email == "loser@local.com")

        // The human decision must propagate to peers like any local edit.
        let logged = try db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM _change_log WHERE table_name = 'users' AND record_id = ?",
                arguments: [userId]
            )
        } ?? 0
        #expect(logged >= 1)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: db).isEmpty)
    }

    @Test("applyConflictResolution keeping the LWW winner is review-only")
    func testApplyResolutionKeepingWinnerIsReviewOnly() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, email: "winner@remote.com")
        try insertConflict(db: db, recordId: userId, winner: "remote")
        // Clear the trigger/backfill entries so the change-log assertions below
        // see only what applyConflictResolution itself records.
        try db.writer.write { try $0.execute(sql: "DELETE FROM _change_log") }
        let conflict = try ConflictResolver.getUnreviewedConflicts(db: db)[0]

        // Reviewer confirms the value LWW already applied — no write, no change log.
        try ConflictResolver.applyConflictResolution(db: db, conflict: conflict, choice: .keepRemote)

        let email = try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT email FROM users WHERE id = ?", arguments: [userId])
        }
        #expect(email == "winner@remote.com")

        let logged = try db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM _change_log WHERE table_name = 'users' AND record_id = ?",
                arguments: [userId]
            )
        } ?? 0
        #expect(logged == 0)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: db).isEmpty)
    }

    @Test("Already-reviewed critical conflicts fail without side effects")
    func testApplyResolutionRejectsAlreadyReviewedConflictBeforeWrite() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, email: "winner@remote.com")
        try insertConflict(db: db, recordId: userId, winner: "remote")
        try db.writer.write { try $0.execute(sql: "DELETE FROM _change_log") }
        let conflict = try ConflictResolver.getUnreviewedConflicts(db: db)[0]
        try ConflictResolver.markConflictReviewed(db: db, conflictId: conflict.id!)

        #expect(throws: ConflictResolver.ConflictReviewError.self) {
            try ConflictResolver.applyConflictResolution(db: db, conflict: conflict, choice: .keepLocal)
        }

        let state = try db.writer.read { dbConn in
            let email = try String.fetchOne(dbConn, sql: "SELECT email FROM users WHERE id = ?", arguments: [userId])
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            return (email, changes)
        }
        #expect(state.0 == "winner@remote.com")
        #expect(state.1 == 0)
    }

    @Test("Critical resolution guard cleanup failure rolls back the chosen value")
    func testApplyResolutionCleanupFailureRollsBack() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, email: "winner@remote.com")
        try insertConflict(db: db, recordId: userId, winner: "remote")
        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _change_log")
            try dbConn.execute(sql: """
                CREATE TRIGGER reject_critical_sync_guard_cleanup
                BEFORE DELETE ON _sync_apply_guard
                BEGIN
                    SELECT RAISE(ABORT, 'forced critical sync guard cleanup failure');
                END
                """)
        }
        let conflict = try ConflictResolver.getUnreviewedConflicts(db: db)[0]

        #expect(throws: (any Error).self) {
            try ConflictResolver.applyConflictResolution(db: db, conflict: conflict, choice: .keepLocal)
        }

        let state = try db.writer.read { dbConn in
            let email = try String.fetchOne(dbConn, sql: "SELECT email FROM users WHERE id = ?", arguments: [userId])
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            let guardRows = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _sync_apply_guard") ?? -1
            return (email, changes, guardRows)
        }
        #expect(state.0 == "winner@remote.com")
        #expect(state.1 == 0)
        #expect(state.2 == 0)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: db).count == 1)
    }

    @Test("applyConflictResolution rejects deletion conflicts with a clear error")
    func testApplyResolutionRejectsDeletionConflicts() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, email: "kept@local.com")
        try db.writer.write { dbConn in
            var conflict = ConflictLogEntry(
                tableName: "users",
                recordId: String(userId),
                fieldName: "email",
                localValue: "kept@local.com",
                remoteValue: "(DELETED)",
                winner: "remote",
                localDevice: "dev-A",
                remoteDevice: "dev-B",
                localTs: "2026-03-14T09:00:00Z",
                remoteTs: "2026-03-14T10:00:00Z",
                resolvedAt: now
            )
            try conflict.insert(dbConn)
        }
        let conflict = try ConflictResolver.getUnreviewedConflicts(db: db)[0]

        #expect(throws: ConflictResolver.ConflictReviewError.self) {
            try ConflictResolver.applyConflictResolution(db: db, conflict: conflict, choice: .keepLocal)
        }
        // Still unreviewed — a failed apply must not silently dismiss the conflict.
        #expect(try ConflictResolver.getUnreviewedConflicts(db: db).count == 1)
    }

    // MARK: - applyTextConflictResolution

    private func textConflictDatabase() throws -> (db: AppDatabase, jobId: Int64, conflict: ConflictLogEntry) {
        let db = try freshDB()
        let jobId = try db.writer.write { dbConn -> Int64 in
            try dbConn.execute(
                sql: """
                    INSERT INTO jobs (job_number, job_name, status, notes, created_at, updated_at)
                    VALUES ('SYNC-TEXT-1', 'Text Conflict', 'active', 'Device B edit', ?, ?)
                    """,
                arguments: ["2000-01-01T00:00:00Z", "2000-01-01T00:00:00Z"]
            )
            let id = dbConn.lastInsertedRowID
            var conflict = ConflictLogEntry(
                tableName: "jobs",
                recordId: String(id),
                fieldName: "notes",
                localValue: "Device A edit",
                remoteValue: "Device B edit",
                winner: "remote",
                localDevice: "dev-A",
                remoteDevice: "dev-B",
                localTs: "2026-07-14T09:00:00Z",
                remoteTs: "2026-07-14T10:00:00Z",
                resolvedAt: now
            )
            try conflict.insert(dbConn)
            try dbConn.execute(sql: "DELETE FROM _change_log")
            return id
        }
        let conflict = try #require(ConflictResolver.getUnreviewedConflicts(db: db).first)
        return (db, jobId, conflict)
    }

    @Test("AI merge, losing device edit, and manual text persist and are audited")
    func testApplyTextConflictResolutionPersistsEverySelectionKind() throws {
        let selections = [
            "AI merge": "Device A edit plus Device B edit",
            "device A": "Device A edit",
            "manual": "Reviewer's exact rewrite",
        ]

        for (kind, selectedValue) in selections {
            let fixture = try textConflictDatabase()
            try ConflictResolver.applyTextConflictResolution(
                db: fixture.db,
                conflict: fixture.conflict,
                selectedValue: selectedValue
            )

            let result = try fixture.db.writer.read { dbConn in
                let notes = try String.fetchOne(
                    dbConn,
                    sql: "SELECT notes FROM jobs WHERE id = ?",
                    arguments: [fixture.jobId]
                )
                let updatedAt = try String.fetchOne(
                    dbConn,
                    sql: "SELECT updated_at FROM jobs WHERE id = ?",
                    arguments: [fixture.jobId]
                )
                let change = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT changed_fields, old_values FROM _change_log
                        WHERE table_name = 'jobs' AND record_id = ? AND operation = 'UPDATE'
                        ORDER BY id DESC LIMIT 1
                        """,
                    arguments: [fixture.jobId]
                )
                return (notes, updatedAt, change)
            }
            #expect(result.0 == selectedValue, "\(kind) selection was not persisted")
            #expect(result.1 != "2000-01-01T00:00:00Z", "\(kind) did not bump updated_at")
            #expect((result.2?["changed_fields"] as String?).map { $0.contains(selectedValue) } == true)
            #expect((result.2?["old_values"] as String?).map { $0.contains("Device B edit") } == true)
            #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).isEmpty)
        }
    }

    @Test("A failed text resolution rolls back the live write, audit, and reviewed flag")
    func testApplyTextConflictResolutionFailureLeavesConflictPending() throws {
        let fixture = try textConflictDatabase()
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                CREATE TRIGGER reject_conflict_review
                BEFORE UPDATE OF reviewed ON _conflict_log
                BEGIN
                    SELECT RAISE(ABORT, 'forced review failure');
                END
                """)
        }

        #expect(throws: (any Error).self) {
            try ConflictResolver.applyTextConflictResolution(
                db: fixture.db,
                conflict: fixture.conflict,
                selectedValue: "Must roll back"
            )
        }

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            return (notes, changes)
        }
        #expect(state.0 == "Device B edit")
        #expect(state.1 == 0)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).count == 1)
    }

    @Test("Selecting the live text winner is review-only")
    func testApplyTextConflictResolutionKeepingWinnerIsReviewOnly() throws {
        let fixture = try textConflictDatabase()

        try ConflictResolver.applyTextConflictResolution(
            db: fixture.db,
            conflict: fixture.conflict,
            selectedValue: "Device B edit"
        )

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let updatedAt = try String.fetchOne(
                dbConn,
                sql: "SELECT updated_at FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            return (notes, updatedAt, changes)
        }
        #expect(state.0 == "Device B edit")
        #expect(state.1 == "2000-01-01T00:00:00Z")
        #expect(state.2 == 0)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).isEmpty)
    }

    @Test("Sync guard cleanup failure rolls back text resolution")
    func testApplyTextConflictResolutionCleanupFailureRollsBack() throws {
        let fixture = try textConflictDatabase()
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                CREATE TRIGGER reject_sync_guard_cleanup
                BEFORE DELETE ON _sync_apply_guard
                BEGIN
                    SELECT RAISE(ABORT, 'forced sync guard cleanup failure');
                END
                """)
        }

        #expect(throws: (any Error).self) {
            try ConflictResolver.applyTextConflictResolution(
                db: fixture.db,
                conflict: fixture.conflict,
                selectedValue: "Must roll back"
            )
        }

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            let guardRows = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _sync_apply_guard") ?? -1
            return (notes, changes, guardRows)
        }
        #expect(state.0 == "Device B edit")
        #expect(state.1 == 0)
        #expect(state.2 == 0)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).count == 1)
    }

    @Test("Text resolution rejects a stale LWW winner without writing or reviewing")
    func testApplyTextConflictResolutionRejectsStaleLiveValue() throws {
        let fixture = try textConflictDatabase()
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE jobs SET notes = ? WHERE id = ?",
                arguments: ["Newer live edit", fixture.jobId]
            )
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }

        do {
            try ConflictResolver.applyTextConflictResolution(
                db: fixture.db,
                conflict: fixture.conflict,
                selectedValue: "Stale reviewer choice"
            )
            Issue.record("Expected the stale conflict resolution to be rejected")
        } catch let error as ConflictResolver.ConflictReviewError {
            guard case .staleConflict(let conflictId) = error else {
                Issue.record("Expected staleConflict, got \(error)")
                return
            }
            #expect(conflictId == fixture.conflict.id)
        }

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            let reviewed = try Int.fetchOne(
                dbConn,
                sql: "SELECT reviewed FROM _conflict_log WHERE id = ?",
                arguments: [fixture.conflict.id]
            )
            return (notes, changes, reviewed)
        }
        #expect(state.0 == "Newer live edit")
        #expect(state.1 == 0)
        #expect(state.2 == 0)
    }

    @Test("Text resolution accepts a persisted NULL winner only when the live field is NULL")
    func testApplyTextConflictResolutionMatchesNullWinner() throws {
        let fixture = try textConflictDatabase()
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE jobs SET notes = NULL WHERE id = ?",
                arguments: [fixture.jobId]
            )
            try dbConn.execute(
                sql: "UPDATE _conflict_log SET remote_value = NULL WHERE id = ?",
                arguments: [fixture.conflict.id]
            )
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }

        try ConflictResolver.applyTextConflictResolution(
            db: fixture.db,
            conflict: fixture.conflict,
            selectedValue: "Reviewer restored text"
        )

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            return (notes, changes)
        }
        #expect(state.0 == "Reviewer restored text")
        #expect(state.1 == 1)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).isEmpty)
    }

    @Test("Selecting the persisted NULL text winner is review-only")
    func testApplyTextConflictResolutionKeepingNullWinnerIsReviewOnly() throws {
        let fixture = try textConflictDatabase()
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(sql: "UPDATE jobs SET notes = NULL WHERE id = ?", arguments: [fixture.jobId])
            try dbConn.execute(sql: "UPDATE _conflict_log SET remote_value = NULL WHERE id = ?", arguments: [fixture.conflict.id])
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }
        let conflict = try ConflictResolver.getUnreviewedConflicts(db: fixture.db)[0]

        try ConflictResolver.applyTextConflictResolution(
            db: fixture.db,
            conflict: conflict,
            selectedValue: "(NULL)"
        )

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(dbConn, sql: "SELECT notes FROM jobs WHERE id = ?", arguments: [fixture.jobId])
            let updatedAt = try String.fetchOne(dbConn, sql: "SELECT updated_at FROM jobs WHERE id = ?", arguments: [fixture.jobId])
            let changes = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM _change_log") ?? -1
            return (notes, updatedAt, changes)
        }
        #expect(state.0 == nil)
        #expect(state.1 == "2000-01-01T00:00:00Z")
        #expect(state.2 == 0)
        #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).isEmpty)
    }

    @Test("Persisted conflict metadata controls the only write and audit target")
    func testApplyTextConflictResolutionIgnoresAllCallerMetadata() throws {
        let fixture = try textConflictDatabase()
        let otherUserId = try insertUser(
            db: fixture.db,
            displayName: "Untouched User",
            email: "untouched@example.com"
        )
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(sql: "DELETE FROM _change_log")
        }

        var tampered = fixture.conflict
        tampered.tableName = "users"
        tampered.recordId = String(otherUserId)
        tampered.fieldName = "email"

        try ConflictResolver.applyTextConflictResolution(
            db: fixture.db,
            conflict: tampered,
            selectedValue: "Persisted target only"
        )

        let state = try fixture.db.writer.read { dbConn in
            let notes = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM jobs WHERE id = ?",
                arguments: [fixture.jobId]
            )
            let email = try String.fetchOne(
                dbConn,
                sql: "SELECT email FROM users WHERE id = ?",
                arguments: [otherUserId]
            )
            let changes = try Row.fetchAll(
                dbConn,
                sql: "SELECT table_name, record_id, changed_fields FROM _change_log ORDER BY id"
            )
            return (notes, email, changes)
        }
        #expect(state.0 == "Persisted target only")
        #expect(state.1 == "untouched@example.com")
        #expect(state.2.count == 1)
        #expect(state.2.first?["table_name"] as String? == "jobs")
        #expect(state.2.first?["record_id"] as Int64? == fixture.jobId)
        #expect((state.2.first?["changed_fields"] as String?).map { $0.contains("notes") } == true)
    }

    @Test("Text resolution rejects non-whitelisted fields without dismissing the conflict")
    func testApplyTextConflictResolutionRejectsNonWhitelistedField() throws {
        let fixture = try textConflictDatabase()
        var tampered = fixture.conflict
        tampered.fieldName = "status"

        // The persisted conflict metadata wins over caller input, so tampering the
        // in-memory object cannot redirect the write. Replace the persisted field
        // to prove the explicit text-field whitelist itself rejects the request.
        try fixture.db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE _conflict_log SET field_name = 'status' WHERE id = ?",
                arguments: [fixture.conflict.id]
            )
        }
        #expect(throws: ConflictResolver.ConflictReviewError.self) {
            try ConflictResolver.applyTextConflictResolution(
                db: fixture.db,
                conflict: tampered,
                selectedValue: "closed"
            )
        }
        #expect(try ConflictResolver.getUnreviewedConflicts(db: fixture.db).count == 1)
    }

    // MARK: - NULL fields in a merged UPDATE (field reported from build 66/46)

    /// Field-level merge builds the SET clause and its bound arguments separately.
    /// They disagreed about NULL: every field got a `?` placeholder, but fields
    /// whose merged value was NULL contributed no argument. One null field was
    /// therefore enough to abort the whole apply with
    /// `SQLite error 21: wrong number of statement arguments`, which is what the
    /// owner's Mac reported while syncing `clock_out_questions` with an iPhone.
    @Test("a merged UPDATE carrying a NULL field applies instead of throwing error 21")
    func testMergedUpdateWithNullFieldApplies() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original", email: "orig@test.com")

        // `email` arrives as an explicit SQL NULL alongside a non-null field, so
        // the statement needs a NULL literal for one column and a bound argument
        // for the other. Getting that split wrong is the bug.
        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                recordData: """
                {"id":"\(userId)","display_name":"Renamed Remotely","email":null}
                """,
                timestamp: "2026-08-14T05:00:00Z"
            )
        ]

        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1, "a null field must not abort the apply")

        let user = try db.writer.read { dbConn in try User.fetchOne(dbConn, key: userId) }
        #expect(user?.displayName == "Renamed Remotely")
        #expect(user?.email == nil, "the null must be written as SQL NULL, not skipped")
    }

    /// The all-NULL case: every clause is a literal, so `args` holds only the
    /// record id. An off-by-one in the other direction would surface here.
    @Test("a merged UPDATE where every field is NULL still applies")
    func testMergedUpdateWithOnlyNullFieldsApplies() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Original", email: "orig@test.com")

        let changes = [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                recordData: """
                {"id":"\(userId)","email":null}
                """,
                timestamp: "2026-08-14T05:00:00Z"
            )
        ]

        let result = try ConflictResolver.resolveAndApplyChanges(db: db, changes: changes)
        #expect(result.applied == 1)

        let user = try db.writer.read { dbConn in try User.fetchOne(dbConn, key: userId) }
        #expect(user?.email == nil)
        #expect(user?.displayName == "Original", "untouched fields must survive")
    }

    // MARK: - #1728 — a child row arriving before its parent must not kill the join

    /// `notebooks.template_id` → `notebook_templates` is one of nine inverted
    /// edges: the host streams tables in `sqlite_master` creation order, and
    /// `notebook_templates` is DROPped and re-created by a later migration, so
    /// it is sent long AFTER the `notebooks` rows that point at it.
    ///
    /// This is the real pair from the schema rather than a synthetic one, so
    /// the test keeps testing the thing that actually broke.
    private func notebookBeforeItsTemplate(
        templateId: Int,
        createdBy: Int64
    ) -> [IncomingChange] {
        [
            IncomingChange(
                deviceId: "remote-device",
                tableName: "notebooks",
                recordId: "1",
                operation: "INSERT",
                recordData: """
                {"id":"1","title":"Job Notebook","template_id":"\(templateId)","created_by":"\(createdBy)"}
                """,
                timestamp: "2026-08-14T10:00:00Z"
            ),
            // `template_data` is NOT NULL with no default (migration 039
            // re-creates this table, which is also what pushes its
            // `sqlite_master` rowid after `notebooks`). Supplying it is not
            // incidental: `INSERT OR IGNORE` SILENTLY swallows a NOT NULL
            // violation, so a sparse record here would drop the parent row and
            // the test would fail at COMMIT for the wrong reason — looking
            // exactly like the deferral not working.
            IncomingChange(
                deviceId: "remote-device",
                tableName: "notebook_templates",
                recordId: "\(templateId)",
                operation: "INSERT",
                recordData: """
                {"id":"\(templateId)","name":"Residential Job","template_data":"{}"}
                """,
                timestamp: "2026-08-14T10:00:01Z"
            ),
        ]
    }

    /// The #1728 regression.
    ///
    /// Before the fix this threw `SQLite error 19: FOREIGN KEY constraint
    /// failed` out of `db.writer.write` and rolled back the ENTIRE company
    /// snapshot — one out-of-order row killing the whole join, deterministically,
    /// on every retry. The successor to #1723 and the same shape.
    ///
    /// MUTATION CHECK: delete the `deferForeignKeysForThisTransaction` call in
    /// `resolveAndApplyChangesAtomically` and this test must go red. A test
    /// that cannot fail is not coverage.
    @Test("#1728 atomic apply survives a child row arriving before its parent")
    func testAtomicApplyToleratesChildBeforeParent() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Owner")

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: notebookBeforeItsTemplate(templateId: 99, createdBy: userId)
        )

        #expect(result.applied == 2, "both rows must land; arrival order is not corruption")

        let (notebookTemplate, templateExists) = try db.writer.read { dbConn in
            (
                try Int.fetchOne(dbConn, sql: "SELECT template_id FROM notebooks WHERE id = 1"),
                try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM notebook_templates WHERE id = 99") ?? 0
            )
        }
        #expect(notebookTemplate == 99, "the child kept its reference")
        #expect(templateExists == 1, "the parent landed too")
    }

    /// The other half, and the reason this is a deferral rather than a
    /// weakening: a snapshot whose parent row genuinely does not exist
    /// anywhere is real referential corruption and must STILL be rejected —
    /// at COMMIT — rather than committing a dangling reference.
    ///
    /// If this ever starts passing, the fix has turned into
    /// `PRAGMA foreign_keys = OFF` by accident.
    @Test("#1728 a genuinely orphaned row still fails and rolls the batch back")
    func testAtomicApplyStillRejectsATrulyOrphanedRow() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Owner")

        // Only the child — no parent anywhere in the batch or the database.
        let orphan = Array(notebookBeforeItsTemplate(templateId: 12345, createdBy: userId).prefix(1))

        #expect(throws: (any Error).self) {
            try ConflictResolver.resolveAndApplyChangesAtomically(db: db, changes: orphan)
        }

        let notebooks = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM notebooks") ?? -1
        }
        #expect(notebooks == 0, "the batch must roll back rather than commit a dangling reference")
    }

    /// The streaming twin is the path the real Bluetooth join actually takes,
    /// so fixing only the array-based entry point would have left the field
    /// failure exactly as it was.
    @Test("#1728 the streaming apply defers foreign keys too")
    func testStreamedAtomicApplyToleratesChildBeforeParent() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Owner")
        let changes = notebookBeforeItsTemplate(templateId: 77, createdBy: userId)

        let result = try ConflictResolver.resolveAndApplyStreamedChangesAtomically(
            db: db,
            produceChanges: { _, emit in
                for change in changes { try emit(change) }
            }
        )

        #expect(result.applied == 2)

        let templateId = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT template_id FROM notebooks WHERE id = 1")
        }
        #expect(templateId == 77)
    }

    // MARK: - A newer sender's column must not kill the join

    /// The sender decides the payload's column set (`SELECT *` + a key per
    /// non-blob column), so a device on a newer build hands the receiver a
    /// column name it has never heard of. `is_flex_pool` stands in for the 96
    /// columns migration history has already added: it does not exist in any
    /// migration, which is exactly the point.
    ///
    /// MUTATION CHECK: remove the `filteredToLocalColumns` call from the
    /// statement builder each test names and that test must go red.
    private func rowWithAColumnThisDeviceLacks(
        table: String,
        recordId: String,
        knownFieldsJSON: String,
        operation: String = "INSERT"
    ) -> IncomingChange {
        IncomingChange(
            deviceId: "newer-device",
            tableName: table,
            recordId: recordId,
            operation: operation,
            recordData: "{\(knownFieldsJSON),\"is_flex_pool\":\"1\"}",
            timestamp: "2026-08-14T10:00:00Z"
        )
    }

    /// INSERT branch. `INSERT OR IGNORE` gives NO protection here: ON CONFLICT
    /// resolution only runs for a statement that PREPARES, and an unknown column
    /// fails at prepare. Before the fix this threw
    /// `table notebook_templates has no column named is_flex_pool` straight out
    /// of `db.writer.write` and rolled the entire company snapshot back.
    @Test("A newer sender's unknown column does not abort the atomic INSERT branch")
    func testAtomicApplyDropsUnknownColumnOnInsert() throws {
        let db = try freshDB()

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: [rowWithAColumnThisDeviceLacks(
                table: "notebook_templates",
                recordId: "42",
                knownFieldsJSON: #""id":"42","name":"Residential Job","template_data":"{}""#
            )]
        )

        #expect(result.applied == 1)

        let name = try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT name FROM notebook_templates WHERE id = 42")
        }
        #expect(name == "Residential Job", "the row lands, minus only the column this device cannot store")
    }

    /// Merge/UPDATE branch — the one with NO conflict clause at all, and the
    /// branch every migration-seeded row takes because its id matches on both
    /// devices. Before the fix the bare `UPDATE … SET "is_flex_pool" = ?` threw
    /// at prepare time and rolled the batch back.
    @Test("A newer sender's unknown column does not abort the atomic merge branch")
    func testAtomicApplyDropsUnknownColumnOnMerge() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Before", email: "before@example.com")

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: [rowWithAColumnThisDeviceLacks(
                table: "users",
                recordId: "\(userId)",
                knownFieldsJSON: #""id":"\#(userId)","display_name":"After""#,
                operation: "UPDATE"
            )]
        )

        #expect(result.applied == 1)

        let displayName = try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT display_name FROM users WHERE id = \(userId)")
        }
        #expect(displayName == "After", "the known field still merged; only the unknown one was dropped")
    }

    /// The THIRD statement builder: `applyUpdate`'s own missing-record INSERT.
    /// It is reached only when `changed_fields` is present AND the record is
    /// absent locally, so neither test above touches it — and it is the exact
    /// sibling that kept the #196 NULL bug alive after its twin was fixed.
    @Test("Unknown columns are dropped by applyUpdate's missing-record INSERT too")
    func testAtomicApplyDropsUnknownColumnOnUpdateInsertTwin() throws {
        let db = try freshDB()

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: [IncomingChange(
                deviceId: "newer-device",
                tableName: "notebook_templates",
                recordId: "44",
                operation: "UPDATE",
                changedFields: #"{"name":"Service Call"}"#,
                recordData: #"{"id":"44","name":"Service Call","template_data":"{}","is_flex_pool":"1"}"#,
                timestamp: "2026-08-14T10:00:00Z"
            )]
        )

        #expect(result.applied == 1)

        let name = try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT name FROM notebook_templates WHERE id = 44")
        }
        #expect(name == "Service Call", "the twin builder must filter too, or it stays broken alone")
    }

    /// The streaming entry point is the path a real Bluetooth join takes, so a
    /// fix that landed only on the array entry point would have changed nothing
    /// in the field — the mistake #1728 explicitly avoided.
    @Test("The streaming apply drops unknown columns too")
    func testStreamedAtomicApplyDropsUnknownColumn() throws {
        let db = try freshDB()
        let change = rowWithAColumnThisDeviceLacks(
            table: "notebook_templates",
            recordId: "43",
            knownFieldsJSON: #""id":"43","name":"Commercial Job","template_data":"{}""#
        )

        let result = try ConflictResolver.resolveAndApplyStreamedChangesAtomically(
            db: db,
            produceChanges: { _, emit in try emit(change) }
        )

        #expect(result.applied == 1)

        let name = try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: "SELECT name FROM notebook_templates WHERE id = 43")
        }
        #expect(name == "Commercial Job")
    }

    /// The filter must be narrow. A test proving unknown columns are dropped
    /// would also pass if the filter dropped EVERYTHING, so this pins the other
    /// side: a payload of entirely real columns must survive intact.
    @Test("The unknown-column filter does not drop columns this device has")
    func testKnownColumnsSurviveTheFilter() throws {
        let db = try freshDB()
        let userId = try insertUser(db: db, displayName: "Before", email: "before@example.com")

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: [IncomingChange(
                deviceId: "peer-device",
                tableName: "users",
                recordId: "\(userId)",
                operation: "UPDATE",
                recordData: #"{"id":"\#(userId)","display_name":"After","email":"after@example.com","phone":"555-0100"}"#,
                timestamp: "2026-08-14T10:00:00Z"
            )]
        )

        #expect(result.applied == 1)

        let row = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT display_name, email, phone FROM users WHERE id = \(userId)")
        }
        #expect(row?["display_name"] == "After")
        #expect(row?["email"] == "after@example.com")
        #expect(row?["phone"] == "555-0100", "every real column still applied")
    }

    // MARK: - #1729 — a reordered stage list must not kill the join

    /// The host's stage list after a drag-reorder: slots 1,2,3 become 3,1,2.
    ///
    /// Emitted as INSERT because a full snapshot ships every row as an INSERT.
    /// The rows already exist on this device — migration-seeded with the SAME
    /// ids — so each one lands on the clause-free merge `UPDATE` instead of the
    /// `INSERT OR IGNORE` branch. That routing is the whole cause: identical ids
    /// are what make this the merge path.
    private func reorderedJobStages() -> [IncomingChange] {
        [(1, 3), (2, 1), (3, 2)].map { id, sortOrder in
            IncomingChange(
                deviceId: "remote-device",
                tableName: "job_stages",
                recordId: "\(id)",
                operation: "INSERT",
                recordData: #"{"id":"\#(id)","sort_order":"\#(sortOrder)"}"#,
                timestamp: "2026-08-14T10:00:0\(id)Z"
            )
        }
    }

    private func liveStageOrder(_ db: AppDatabase) throws -> [Int: Int] {
        try db.writer.read { dbConn in
            var order: [Int: Int] = [:]
            for row in try Row.fetchAll(
                dbConn,
                sql: "SELECT id, sort_order FROM job_stages WHERE deleted_at IS NULL"
            ) {
                order[row["id"]] = row["sort_order"]
            }
            return order
        }
    }

    /// The #1729 regression.
    ///
    /// Before the fix the FIRST row of the permutation threw
    /// `UNIQUE constraint failed: job_stages.template_id, job_stages.sort_order`
    /// out of `db.writer.write` and rolled the ENTIRE company snapshot back —
    /// the same "one row kills the whole join" shape as #1723 and #1728, reached
    /// by simply having reordered the stage list once.
    ///
    /// MUTATION CHECK: remove the `suspendJobStageSortIndex` call from
    /// `resolveAndApplyChangesAtomically` and this test must go red.
    @Test("#1729 atomic apply survives a reordered job-stage list")
    func testAtomicApplySurvivesAReorderedStageList() throws {
        let db = try freshDB()

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: reorderedJobStages()
        )

        #expect(result.applied == 3, "a permutation is a legal state, not corruption")
        #expect(try liveStageOrder(db) == [1: 3, 2: 1, 3: 2],
                "the host's ordering must land exactly")
    }

    /// The streaming twin is the path the real Bluetooth join actually takes, so
    /// fixing only the array entry point would leave the field failure in place.
    ///
    /// The producer here holds a cursor open across every `emit`, mirroring the
    /// real one, so it also pins the placement rule: `DROP INDEX` fails with
    /// "database table is locked" while ANY statement is in flight on the
    /// connection — even a cursor over an unrelated table — which is why the lift
    /// happens before the producer runs and the recreate may safely happen after.
    /// (`CREATE INDEX` has no such restriction; the issue's design comment had
    /// this asymmetry backwards.)
    ///
    /// MUTATION CHECK: move the `suspendJobStageSortIndex` call below
    /// `produceChanges` and this test must go red. Note the failure arrives as
    /// the UNIQUE violation rather than the lock: the permutation collides while
    /// the index is still live, before the misplaced drop is ever reached.
    @Test("#1729 the streaming apply lifts the ordering index too")
    func testStreamedAtomicApplySurvivesAReorderedStageList() throws {
        let db = try freshDB()
        let changes = reorderedJobStages()

        let result = try ConflictResolver.resolveAndApplyStreamedChangesAtomically(
            db: db,
            produceChanges: { dbConn, emit in
                // Mirrors the real producer: a live cursor held open across every
                // `emit`, on the same connection the transaction owns.
                let cursor = try Row.fetchCursor(
                    dbConn,
                    sql: "SELECT id FROM job_stages WHERE deleted_at IS NULL ORDER BY id"
                )
                var index = 0
                while try cursor.next() != nil, index < changes.count {
                    try emit(changes[index])
                    index += 1
                }
            }
        )

        #expect(result.applied == 3)
        #expect(try liveStageOrder(db) == [1: 3, 2: 1, 3: 2])
    }

    /// The reconciliation pass is load-bearing, not defensive.
    ///
    /// A batch carrying only PART of a permutation — the host moved stage 1 into
    /// slot 3, but this device's stage 3 still holds slot 3 — leaves a genuine
    /// duplicate once the index is lifted. Without reconciliation the recreate
    /// throws and the bug simply relocates from the `UPDATE` to the `CREATE`.
    ///
    /// MUTATION CHECK: remove the `reconcileJobStageSortOrders` call from
    /// `restoreJobStageSortIndex` and this test must go red.
    @Test("#1729 a partially delivered reorder still commits")
    func testAtomicApplySurvivesAPartiallyDeliveredReorder() throws {
        let db = try freshDB()

        let result = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: [IncomingChange(
                deviceId: "remote-device",
                tableName: "job_stages",
                recordId: "1",
                operation: "INSERT",
                recordData: #"{"id":"1","sort_order":"3"}"#,
                timestamp: "2026-08-14T10:00:00Z"
            )]
        )

        #expect(result.applied == 1)

        // Deterministic renumber, ordered by (sort_order, id): stage 2 held slot
        // 2 so it sorts first, then the two rows contesting slot 3 break the tie
        // on id. Nothing is deleted — every stage is still live.
        #expect(try liveStageOrder(db) == [2: 1, 1: 2, 3: 3],
                "the contested slot is resolved by renumbering, not by dropping a stage")
    }

    /// The other half, and the reason this is a lift rather than a weakening: the
    /// index must come back EXACTLY, partial predicate included. A hand-retyped
    /// `CREATE` that lost `WHERE deleted_at IS NULL` would silently turn a
    /// partial unique index into a total one and start rejecting soft-deleted
    /// duplicates that were always legal.
    ///
    /// If this ever starts passing with the index absent, the fix has become a
    /// permanent silent loss of the invariant.
    ///
    /// MUTATION CHECK: replace the captured-DDL replay in
    /// `restoreJobStageSortIndex` with a hardcoded `CREATE UNIQUE INDEX` that
    /// omits the `WHERE` clause, and the soft-deleted-duplicate assertion below
    /// must go red.
    @Test("#1729 the ordering index is restored exactly, predicate and all")
    func testJobStageSortIndexIsRestoredWithItsPartialPredicate() throws {
        let db = try freshDB()

        let before = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: """
                    SELECT sql FROM sqlite_master
                    WHERE type = 'index' AND name = 'idx_job_stages_template_sort_active'
                    """
            )
        }
        #expect(before != nil, "the fixture must actually have the index under test")

        _ = try ConflictResolver.resolveAndApplyChangesAtomically(
            db: db,
            changes: reorderedJobStages()
        )

        let after = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: """
                    SELECT sql FROM sqlite_master
                    WHERE type = 'index' AND name = 'idx_job_stages_template_sort_active'
                    """
            )
        }
        #expect(after == before, "the index DDL must be byte-identical after the apply")

        let templateId = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT template_id FROM job_stages WHERE id = 1")
        }

        // Enforcement is live again: a duplicate ACTIVE slot is still rejected.
        #expect(throws: (any Error).self) {
            try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: """
                        INSERT INTO job_stages (name, sort_order, template_id)
                        VALUES ('Duplicate', 3, ?)
                        """,
                    arguments: [templateId]
                )
            }
        }

        // …but the PARTIAL predicate survived: a soft-deleted row sharing that
        // slot is exempt and must still be accepted.
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO job_stages (name, sort_order, template_id, deleted_at)
                    VALUES ('Archived', 3, ?, '2026-08-14T10:00:00Z')
                    """,
                arguments: [templateId]
            )
        }
    }
}
