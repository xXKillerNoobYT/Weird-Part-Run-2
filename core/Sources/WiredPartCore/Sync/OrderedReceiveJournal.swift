import Foundation
import GRDB

/// Durable receipt ledger for incremental peer changes.
///
/// Receipt and application are deliberately separate phases. A transport may
/// acknowledge a row once it is committed here; the row remains in this local,
/// non-replicated journal until a later apply transaction confirms its effects.
/// That makes an FK-dependent child survivable when its parent arrives in a
/// later frame, and keeps the sender's source ordering authoritative on retry.
public enum OrderedReceiveJournal {
    public struct Receipt: Sendable {
        public let acceptedCount: Int
        public let appliedCount: Int
        public let highestDurableSourceOrder: Int64?
    }

    private static let table = "_sync_receive_journal"

    /// Commit every accepted row before attempting application. This is the only
    /// method receive call sites may use before advancing a peer cursor/vector.
    @discardableResult
    public static func receive(
        db: AppDatabase,
        changes: [IncomingChange],
        sourcePeerId: String,
        transport: String,
        localDeviceId: String
    ) throws -> Receipt {
        guard !changes.isEmpty else {
            return Receipt(acceptedCount: 0, appliedCount: 0, highestDurableSourceOrder: nil)
        }

        let encoded = try changes.map { try JSONEncoder().encode($0) }
        let receivedAt = CoreFormatters.nowISO()
        let highest = try db.writer.write { dbConn -> Int64? in
            var nextOrder = (try Int64.fetchOne(
                dbConn,
                sql: "SELECT COALESCE(MAX(source_order), 0) FROM \(table) WHERE source_peer_id = ?",
                arguments: [sourcePeerId]
            ) ?? 0) + 1
            var highestOrder: Int64?

            for (index, change) in changes.enumerated() {
                // A sender's `_change_log.id` is its stable source order. Legacy
                // senders without one get a local monotonic order, still durable
                // and FIFO, but cannot be accidentally deduplicated as a known row.
                let sourceOrder = change.id ?? nextOrder
                nextOrder = max(nextOrder, sourceOrder + 1)
                highestOrder = max(highestOrder ?? sourceOrder, sourceOrder)
                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO _sync_receive_journal
                        (source_peer_id, source_order, transport, payload, state, retry_state,
                         received_at, updated_at)
                        SELECT ?, ?, ?, ?, 'received', 'pending', ?, ?
                        WHERE NOT EXISTS (
                            SELECT 1 FROM _sync_receive_journal_audit
                            WHERE source_peer_id = ? AND source_order = ?
                        )
                        """,
                    arguments: [
                        sourcePeerId,
                        sourceOrder,
                        transport,
                        String(decoding: encoded[index], as: UTF8.self),
                        receivedAt,
                        receivedAt,
                        sourcePeerId,
                        sourceOrder,
                    ]
                )
            }
            return highestOrder
        }

        let applied = try drain(db: db, sourcePeerId: sourcePeerId, localDeviceId: localDeviceId)
        return Receipt(acceptedCount: changes.count, appliedCount: applied, highestDurableSourceOrder: highest)
    }

    /// Retry every retained row in source order. A failure leaves its journal row
    /// intact and continues with later rows, so a parent in a later batch can land
    /// and unlock an earlier child on the next fixed-point pass. There is no
    /// tail-requeue and no retry-count eviction.
    @discardableResult
    public static func drain(
        db: AppDatabase,
        sourcePeerId: String? = nil,
        localDeviceId: String
    ) throws -> Int {
        var totalApplied = 0
        var madeProgress = true

        while madeProgress {
            madeProgress = false
            let rows: [(Int64, String, IncomingChange)] = try db.writer.read { dbConn in
                let sql: String
                let arguments: StatementArguments
                if let sourcePeerId {
                    sql = "SELECT id, source_peer_id, payload FROM _sync_receive_journal WHERE source_peer_id = ? ORDER BY source_peer_id, source_order, id"
                    arguments = StatementArguments([sourcePeerId])
                } else {
                    sql = "SELECT id, source_peer_id, payload FROM _sync_receive_journal ORDER BY source_peer_id, source_order, id"
                    arguments = StatementArguments()
                }
                return try Row.fetchAll(dbConn, sql: sql, arguments: arguments).compactMap { row in
                    guard let id: Int64 = row["id"],
                          let peer: String = row["source_peer_id"],
                          let payload: String = row["payload"],
                          let change = try? JSONDecoder().decode(IncomingChange.self, from: Data(payload.utf8))
                    else { return nil }
                    return (id, peer, change)
                }
            }

            for (journalID, _, change) in rows {
                do {
                    let result = try ConflictResolver.resolveAndApplyChangesAtomically(
                        db: db,
                        changes: [change],
                        localDeviceId: localDeviceId
                    )
                    // A committed conflict/supersession is a confirmed disposition.
                    // It cannot be retried into an apply, but the retained audit row
                    // records why the exact receipt left the journal.
                    let disposition = result.applied > 0 ? "applied" : "refused"
                    try finalize(
                        db: db,
                        journalID: journalID,
                        disposition: disposition,
                        reason: disposition == "refused" ? "deterministic_non_apply" : nil
                    )
                    totalApplied += result.applied
                    madeProgress = madeProgress || result.applied > 0
                } catch {
                    try retainForRetry(db: db, journalID: journalID, error: error)
                }
            }
        }
        return totalApplied
    }

    private static func finalize(db: AppDatabase, journalID: Int64, disposition: String, reason: String?) throws {
        try db.writer.write { dbConn in
            // Keep structured evidence in the audit table before removing the
            // active journal row. Application removal is allowed only after this
            // transaction confirms its terminal disposition.
            try dbConn.execute(
                sql: """
                    INSERT INTO _sync_receive_journal_audit
                    (journal_id, disposition, reason, payload, source_peer_id, source_order, recorded_at)
                    SELECT id, ?, ?, payload, source_peer_id, source_order, ?
                    FROM _sync_receive_journal WHERE id = ?
                    """,
                arguments: [disposition, reason, CoreFormatters.nowISO(), journalID]
            )
            try dbConn.execute(sql: "DELETE FROM _sync_receive_journal WHERE id = ?", arguments: [journalID])
        }
    }

    private static func retainForRetry(db: AppDatabase, journalID: Int64, error: Error) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE _sync_receive_journal
                    SET state = 'deferred', retry_state = 'retryable', last_error = ?,
                        retry_count = retry_count + 1, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [error.localizedDescription, CoreFormatters.nowISO(), journalID]
            )
        }
    }
}
