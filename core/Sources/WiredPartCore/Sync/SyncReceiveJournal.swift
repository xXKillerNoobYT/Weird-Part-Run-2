import Foundation
import GRDB

/// Durable receipt ledger for LAN receive paths.
///
/// Receipt is deliberately separate from application: a transport acknowledgement
/// is allowed only after a row is committed here, while application may wait for a
/// parent that arrives in a later delivery. Rows stay auditable after every terminal
/// disposition; only their payload is never re-queued behind a newer arrival.
enum SyncReceiveJournal {
    struct Entry: Codable, FetchableRecord {
        let id: Int64
        let sourcePeerId: String
        let sourceSequence: Int64?
        let payload: String
        let state: String

        enum CodingKeys: String, CodingKey {
            case id
            case sourcePeerId = "source_peer_id"
            case sourceSequence = "source_sequence"
            case payload
            case state
        }
    }

    struct ApplyResult {
        var applied = 0
        var deferred = 0
        var refused = 0
        var retryable = 0
    }

    static func record(
        db: AppDatabase,
        sourcePeerId: String,
        changes: [IncomingChange],
        auditMetadata: String
    ) throws {
        guard !changes.isEmpty else { return }
        try db.writer.write { connection in
            for change in changes {
                let payload = try String(decoding: JSONEncoder().encode(change), as: UTF8.self)
                if let sequence = change.id {
                    try connection.execute(
                        sql: """
                        INSERT OR IGNORE INTO _sync_receive_journal
                            (source_peer_id, source_sequence, payload, state, audit_metadata)
                        VALUES (?, ?, ?, 'received', ?)
                        """,
                        arguments: [sourcePeerId, sequence, payload, auditMetadata]
                    )
                } else {
                    try connection.execute(
                        sql: """
                        INSERT INTO _sync_receive_journal
                            (source_peer_id, payload, state, audit_metadata)
                        VALUES (?, ?, 'received', ?)
                        """,
                        arguments: [sourcePeerId, payload, auditMetadata]
                    )
                }
            }
        }
    }

    static func applyPending(db: AppDatabase, localDeviceId: String) throws -> ApplyResult {
        var result = ApplyResult()
        var appliedThisPass: Int

        // A child can precede its parent in durable source order. Run bounded
        // fixed-point passes: every pass preserves that order, and only a newly
        // applied row permits another pass. This is neither head-only requeueing
        // nor a hot loop for a missing parent / transient failure.
        repeat {
            appliedThisPass = 0
            let entries = try pendingEntries(db: db)
            for entry in entries {
                let change = try JSONDecoder().decode(IncomingChange.self, from: Data(entry.payload.utf8))
                let merge = try ConflictResolver.resolveAndApplyChanges(
                    db: db,
                    changes: [change],
                    localDeviceId: localDeviceId
                )
                if merge.errors > 0 {
                    try update(db: db, id: entry.id, state: "retry", reason: "transient_apply_failure", attempted: true)
                    result.retryable += 1
                } else if merge.foreignKeyDeferrals > 0 {
                    try update(db: db, id: entry.id, state: "deferred", reason: "foreign_key_parent_unavailable", attempted: true)
                    result.deferred += 1
                } else if merge.permanentRefusals > 0 || merge.schemaDrops > 0 {
                    try update(db: db, id: entry.id, state: "refused", reason: "irreconcilable_apply_refusal", attempted: true)
                    result.refused += 1
                } else {
                    try update(db: db, id: entry.id, state: "applied", reason: nil, attempted: true)
                    result.applied += 1
                    appliedThisPass += 1
                }
            }
        } while appliedThisPass > 0
        return result
    }

    private static func pendingEntries(db: AppDatabase) throws -> [Entry] {
        try db.writer.read { connection in
            try Entry.fetchAll(
                connection,
                sql: """
                SELECT id, source_peer_id, source_sequence, payload, state
                FROM _sync_receive_journal
                WHERE state IN ('received', 'deferred', 'retry')
                ORDER BY id ASC
                """
            )
        }
    }

    private static func update(db: AppDatabase, id: Int64, state: String, reason: String?, attempted: Bool) throws {
        try db.writer.write { connection in
            try connection.execute(
                sql: """
                UPDATE _sync_receive_journal
                SET state = ?, disposition_reason = ?, retry_count = retry_count + ?,
                    last_attempt_at = datetime('now'), applied_at = CASE WHEN ? = 'applied' THEN datetime('now') ELSE applied_at END,
                    updated_at = datetime('now')
                WHERE id = ?
                """,
                arguments: [state, reason, attempted ? 1 : 0, state, id]
            )
        }
    }
}
