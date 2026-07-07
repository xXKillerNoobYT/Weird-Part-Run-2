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
}
