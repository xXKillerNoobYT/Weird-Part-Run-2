import Testing
import GRDB
@testable import WiredPartCore

@Suite("Ordered receive journal (#1807)")
struct OrderedReceiveJournalTests {
    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    private func child(sequence: Int64 = 10) -> IncomingChange {
        IncomingChange(id: sequence, deviceId: "peer-a", tableName: "part_styles", recordId: "77", operation: "INSERT", recordData: #"{"id":"77","category_id":"999999","name":"FK child"}"#, timestamp: "2026-08-22T00:00:00Z")
    }

    private func parent(sequence: Int64 = 11) -> IncomingChange {
        IncomingChange(id: sequence, deviceId: "peer-a", tableName: "part_categories", recordId: "999999", operation: "INSERT", recordData: #"{"id":"999999","name":"Late parent"}"#, timestamp: "2026-08-22T00:00:01Z")
    }

    private func count(_ db: AppDatabase, _ table: String) throws -> Int {
        try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM [\(table)]") ?? 0
        }
    }

    @Test("child-before-parent is durable, then converges without stale replay")
    func childBeforeLaterParentRemainsAuditableAndRetriesInSourceOrder() throws {
        let db = try freshDB()
        let first = try OrderedReceiveJournal.receive(db: db, changes: [child()], sourcePeerId: "peer-a", transport: "test", localDeviceId: "receiver")
        #expect(first.highestDurableSourceOrder == 10)
        #expect(first.appliedCount == 0)

        let deferred = try db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT source_order, state, retry_state, payload FROM _sync_receive_journal")
        }
        #expect(deferred?["source_order"] as Int64? == 10)
        #expect(deferred?["state"] as String? == "deferred")
        #expect(deferred?["retry_state"] as String? == "retryable")
        #expect((deferred?["payload"] as String?)?.contains("FK child") == true)
        #expect(try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM part_styles WHERE id = 77") ?? 0 } == 0)

        let second = try OrderedReceiveJournal.receive(db: db, changes: [parent()], sourcePeerId: "peer-a", transport: "test", localDeviceId: "receiver")
        #expect(second.highestDurableSourceOrder == 11)
        #expect(second.appliedCount == 2)
        #expect(try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM part_styles WHERE id = 77") ?? 0 } == 1)
        #expect(try count(db, "_sync_receive_journal") == 0)
        #expect(try count(db, "_sync_receive_journal_audit") == 2)

        // Mutation fence: dropping the audit-backed duplicate guard replays the
        // old child receipt after confirmed disposition and makes this fail.
        _ = try OrderedReceiveJournal.receive(db: db, changes: [child()], sourcePeerId: "peer-a", transport: "test", localDeviceId: "receiver")
        #expect(try count(db, "_sync_receive_journal") == 0)
        #expect(try count(db, "_sync_receive_journal_audit") == 2)
    }

    @Test("receive journal migration is registered local infrastructure")
    func migrationRegistrationAndAuditSchema() throws {
        let db = try freshDB()
        let tables = try db.writer.read { dbConn in
            try String.fetchAll(dbConn, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('_sync_receive_journal', '_sync_receive_journal_audit')")
        }
        #expect(Set(tables) == ["_sync_receive_journal", "_sync_receive_journal_audit"])
        let triggers = try db.writer.read { dbConn in
            try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type = 'trigger' AND tbl_name IN ('_sync_receive_journal', '_sync_receive_journal_audit')") ?? 0
        }
        #expect(triggers == 0)
        #expect(!ConflictResolver.isAllowedTable("_sync_receive_journal"))
    }
}
