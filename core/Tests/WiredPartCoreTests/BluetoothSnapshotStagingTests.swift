import Foundation
import GRDB
import Testing
@testable import WiredPartCore

@Suite("Bluetooth durable snapshot staging")
struct BluetoothSnapshotStagingTests {
    private func stage(db: AppDatabase, hostDeviceId: String, batch: SnapshotBatch) throws {
        try BluetoothSnapshotStaging.authorize(
            db: db,
            hostDeviceId: hostDeviceId,
            begin: SnapshotBegin(transferId: batch.transferId, authorizationToken: "token-\(batch.transferId)"),
            allowNewTransfer: true
        )
        try BluetoothSnapshotStaging.stage(db: db, hostDeviceId: hostDeviceId, batch: batch)
    }

    private func change(_ id: Int, invalid: Bool = false) -> IncomingChange {
        IncomingChange(
            deviceId: "host", tableName: "users", recordId: String(id), operation: "INSERT",
            recordData: invalid
                ? "{\"id\":\(id),\"not_a_column\":1}"
                : "{\"id\":\(id),\"display_name\":\"Staged \(id)\",\"pin_hash\":\"hash\",\"is_active\":1}",
            timestamp: "2026-08-09T00:00:00Z"
        )
    }

    @Test("Migration 122 is registered, private, and untracked")
    func migrationIsPrivate() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let facts = try db.writer.read { conn in
            let table = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('_snapshot_staging', '_snapshot_transfers')") ?? 0
            let triggers = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND tbl_name IN ('_snapshot_staging', '_snapshot_transfers')") ?? 0
            return (table, triggers)
        }
        #expect(facts.0 == 2)
        #expect(facts.1 == 0)
        #expect(!ConflictResolver.isAllowedTable("_snapshot_staging"))
    }

    @Test("Completion fails closed for disallowed tables and operations")
    func completionFailsClosed() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let disallowed = IncomingChange(
            deviceId: "host", tableName: "_snapshot_staging", recordId: "1",
            operation: "INSERT", recordData: "{}", timestamp: "2026-08-09T00:00:00Z"
        )
        try stage(db: db, hostDeviceId: "host", batch: .init(
            transferId: "disallowed-table", sequence: 0, changes: [disallowed]
        ))
        #expect(throws: SnapshotStagingError.self) {
            _ = try BluetoothSnapshotStaging.complete(
                db: db, hostDeviceId: "host",
                completion: .init(transferId: "disallowed-table", finalSequence: 0)
            )
        }

        var invalidOperation = change(8150)
        invalidOperation = IncomingChange(
            deviceId: invalidOperation.deviceId, tableName: invalidOperation.tableName,
            recordId: invalidOperation.recordId, operation: "UPSERT",
            recordData: invalidOperation.recordData, timestamp: invalidOperation.timestamp
        )
        try stage(db: db, hostDeviceId: "host", batch: .init(
            transferId: "disallowed-operation", sequence: 0, changes: [invalidOperation]
        ))
        #expect(throws: SnapshotStagingError.self) {
            _ = try BluetoothSnapshotStaging.complete(
                db: db, hostDeviceId: "host",
                completion: .init(transferId: "disallowed-operation", finalSequence: 0)
            )
        }
    }

    @Test("Equal duplicate is idempotent and mismatched duplicate fails closed")
    func duplicateDigestContract() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let first = SnapshotBatch(transferId: "t1", sequence: 0, changes: [change(8101)])
        try stage(db: db, hostDeviceId: "host", batch: first)
        try stage(db: db, hostDeviceId: "host", batch: first)
        let count = try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM _snapshot_staging") ?? 0 }
        #expect(count == 1)
        #expect(throws: SnapshotStagingError.self) {
            try stage(
                db: db, hostDeviceId: "host",
                batch: SnapshotBatch(transferId: "t1", sequence: 0, changes: [change(8102)])
            )
        }
    }

    @Test("Staging survives database and manager recreation before completion")
    func recreation() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("wei7025-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try AppDatabase.openDatabase(atPath: path)
            try stage(
                db: db, hostDeviceId: "host",
                batch: SnapshotBatch(transferId: "recreate", sequence: 0, changes: [change(8201)])
            )
            _ = PeerManager(db: db)
        }
        let reopened = try AppDatabase.openDatabase(atPath: path)
        _ = PeerManager(db: reopened)
        let staged = try reopened.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM _snapshot_staging") ?? 0 }
        #expect(staged == 1)
        let result = try BluetoothSnapshotStaging.complete(
            db: reopened, hostDeviceId: "host",
            completion: SnapshotComplete(transferId: "recreate", finalSequence: 0)
        )
        #expect(result.result.applied == 1)
    }

    @Test("Completion rejects sequence gaps")
    func gaps() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try stage(
            db: db, hostDeviceId: "host",
            batch: SnapshotBatch(transferId: "gap", sequence: 1, changes: [change(8301)])
        )
        #expect(throws: SnapshotStagingError.self) {
            _ = try BluetoothSnapshotStaging.complete(
                db: db, hostDeviceId: "host",
                completion: SnapshotComplete(transferId: "gap", finalSequence: 1)
            )
        }
    }

    @Test("Apply failure rolls back business writes and staging deletion")
    func rollback() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        var positiveAcknowledgementSent = false
        try stage(db: db, hostDeviceId: "host", batch: .init(transferId: "rollback", sequence: 0, changes: [change(8401)]))
        try stage(db: db, hostDeviceId: "host", batch: .init(transferId: "rollback", sequence: 1, changes: [change(8402, invalid: true)]))
        #expect(throws: (any Error).self) {
            _ = try BluetoothSnapshotStaging.complete(db: db, hostDeviceId: "host", completion: .init(transferId: "rollback", finalSequence: 1))
            positiveAcknowledgementSent = true
        }
        let facts = try db.writer.read { conn in
            let user = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM users WHERE id = 8401") ?? 0
            let staged = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM _snapshot_staging WHERE transfer_id='rollback'") ?? 0
            return (user, staged)
        }
        #expect(facts.0 == 0)
        #expect(facts.1 == 2)
        #expect(!positiveAcknowledgementSent)
    }

    @Test("Successful apply deletes staging before caller can send final acknowledgement")
    func finalAckOrder() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        try stage(db: db, hostDeviceId: "host", batch: .init(transferId: "done", sequence: 0, changes: [change(8501)]))
        _ = try BluetoothSnapshotStaging.complete(db: db, hostDeviceId: "host", completion: .init(transferId: "done", finalSequence: 0))
        let facts = try db.writer.read { conn in
            (try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM users WHERE id=8501") ?? 0,
             try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM _snapshot_staging WHERE transfer_id='done'") ?? 0)
        }
        #expect(facts == (1, 0))
    }

    @Test("Transport seam enforces window one and bounded same-sequence retry")
    func windowOneAndRetry() async throws {
        let changes = [change(8601), change(8602)]
        var page = 0
        var sentSequences: [Int] = []
        var acknowledged: Set<Int> = []
        var checks: [Int: Int] = [:]
        let result = try await BluetoothSnapshotTransfer.runStaged(
            transferId: "wire", batchSize: 1, maxAttempts: 3, sleep: { _ in },
            listTables: { ["users"] },
            readPage: { _, _, _ in
                defer { page += 1 }
                return page < changes.count
                    ? BluetoothSnapshotPage(changes: [changes[page]], sourceRowCount: 1)
                    : BluetoothSnapshotPage(changes: [], sourceRowCount: 0)
            },
            sendBatch: { batch in sentSequences.append(batch.sequence); return true },
            isStored: { sequence in
                checks[sequence, default: 0] += 1
                if sequence == 0 && checks[sequence] == 11 { acknowledged.insert(sequence) }
                if sequence == 1 { acknowledged.insert(sequence) }
                return acknowledged.contains(sequence)
            }
        )
        #expect(sentSequences == [0, 0, 1])
        #expect(result.rows == 2)
        #expect(result.finalSequence == 1)
    }
}
