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
        let nextAttemptAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case sourcePeerId = "source_peer_id"
            case sourceSequence = "source_sequence"
            case payload
            case state
            case nextAttemptAt = "next_attempt_at"
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
        let normalizedAuditMetadata = normalizedAuditLabel(auditMetadata)
        try db.writer.write { connection in
            // Receipt is a lifecycle boundary, so it also performs bounded cleanup.
            // It is one idempotent UPDATE, not a timer or a replay loop.
            _ = try redactExpiredTerminalPayloads(connection: connection, now: nil)
            for change in changes {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let payload = try String(decoding: encoder.encode(change), as: UTF8.self)
                if let sequence = change.id {
                    // Migration 131 makes payload identity part of the receipt key.
                    // A restored sender may reuse a sequence, but only an identical
                    // encoded change is a duplicate that may be ignored.
                    try connection.execute(
                        sql: """
                        INSERT OR IGNORE INTO _sync_receive_journal
                            (source_peer_id, source_sequence, payload, state, audit_metadata)
                        VALUES (?, ?, ?, 'received', ?)
                        """,
                        arguments: [sourcePeerId, sequence, payload, normalizedAuditMetadata]
                    )
                } else {
                    try connection.execute(
                        sql: """
                        INSERT INTO _sync_receive_journal
                            (source_peer_id, payload, state, audit_metadata)
                        VALUES (?, ?, 'received', ?)
                        """,
                        arguments: [sourcePeerId, payload, normalizedAuditMetadata]
                    )
                }
            }
        }
    }

    /// Irreversibly remove an expired terminal payload while retaining the receipt's
    /// identity and disposition evidence. Pending rows are intentionally excluded:
    /// their payload is required for ordered replay.
    @discardableResult
    static func redactExpiredTerminalPayloads(db: AppDatabase, now: String? = nil) throws -> Int {
        try db.writer.write { connection in
            try redactExpiredTerminalPayloads(connection: connection, now: now)
        }
    }

    static func hasPendingEntries(db: AppDatabase) throws -> Bool {
        try db.writer.read { connection in
            try Bool.fetchOne(
                connection,
                sql: "SELECT EXISTS(SELECT 1 FROM _sync_receive_journal WHERE state IN ('received', 'deferred', 'retry'))"
            ) ?? false
        }
    }

    static func applyPending(
        db: AppDatabase,
        localDeviceId: String,
        sourcePeerId: String? = nil
    ) throws -> ApplyResult {
        // Applying pending work is the other deterministic lifecycle boundary.
        // This remains a single bounded cleanup query even when fixed-point replay
        // takes multiple passes.
        _ = try redactExpiredTerminalPayloads(db: db)
        var result = ApplyResult()
        var appliedThisPass: Int
        var retryDeferredAfterApply = false

        // A child can precede its parent in durable source order. Run bounded
        // fixed-point passes: every pass preserves that order, and only a newly
        // applied row permits another pass. A deferred row may be retried in that
        // next pass only because the new apply could have supplied its parent.
        // Calls with no new receipt respect next_attempt_at, preventing hot writes
        // for an orphaned parent or a persistent transient failure.
        repeat {
            appliedThisPass = 0
            let entries = try pendingEntries(
                db: db,
                sourcePeerId: sourcePeerId,
                includingDeferredImmediately: retryDeferredAfterApply
            )
            retryDeferredAfterApply = false
            for entry in entries {
                let change = try JSONDecoder().decode(IncomingChange.self, from: Data(entry.payload.utf8))
                let merge = try db.writer.write { connection in
                    let merge = try ConflictResolver.resolveAndApplyChange(
                        in: connection,
                        change: change,
                        localDeviceId: localDeviceId
                    )
                    let disposition = disposition(for: merge)
                    try update(
                        connection: connection,
                        id: entry.id,
                        state: disposition.state,
                        reason: disposition.reason,
                        attempted: true
                    )
                    return merge
                }
                if merge.errors > 0 {
                    result.retryable += 1
                } else if merge.foreignKeyDeferrals > 0 {
                    result.deferred += 1
                } else if merge.permanentRefusals > 0 || merge.schemaDrops > 0 {
                    result.refused += 1
                } else if merge.applied == 0 {
                    // A deterministic dispatch/no-op (for example a disallowed
                    // table) has not applied. Keep it as terminal evidence instead
                    // of falsely reporting it as an applied receipt.
                    result.refused += 1
                } else {
                    result.applied += 1
                    appliedThisPass += 1
                }
            }
            retryDeferredAfterApply = appliedThisPass > 0
        } while appliedThisPass > 0
        return result
    }

    private static func pendingEntries(
        db: AppDatabase,
        sourcePeerId: String?,
        includingDeferredImmediately: Bool
    ) throws -> [Entry] {
        let deferredPredicate = includingDeferredImmediately
            ? "state IN ('deferred', 'retry')"
            : "0"
        return try db.writer.read { connection in
            try Entry.fetchAll(
                connection,
                sql: """
                SELECT id, source_peer_id, source_sequence, payload, state, next_attempt_at
                FROM _sync_receive_journal
                WHERE (
                    state = 'received'
                    OR (state IN ('deferred', 'retry') AND next_attempt_at <= datetime('now'))
                    OR \(deferredPredicate)
                )
                  AND (? IS NULL OR source_peer_id = ?)
                ORDER BY id ASC
                """,
                arguments: [sourcePeerId, sourcePeerId]
            )
        }
    }

    private static func disposition(for merge: MergeResult) -> (state: String, reason: String?) {
        if merge.errors > 0 { return ("retry", "transient_apply_failure") }
        if merge.foreignKeyDeferrals > 0 { return ("deferred", "foreign_key_parent_unavailable") }
        if merge.permanentRefusals > 0 || merge.schemaDrops > 0 {
            return ("refused", "irreconcilable_apply_refusal")
        }
        if merge.applied == 0 { return ("refused", "deterministic_non_apply") }
        return ("applied", nil)
    }

    /// Caller owns the receive-journal transaction. The next retry is bounded so
    /// an unresolved dependency is not decoded, applied, and written every inbox
    /// timer tick. Entries newly deferred in a pass are explicitly replayed only
    /// when another row applied and could have satisfied that dependency.
    private static func update(
        connection: Database,
        id: Int64,
        state: String,
        reason: String?,
        attempted: Bool
    ) throws {
        try connection.execute(
            sql: """
            UPDATE _sync_receive_journal
            SET state = ?, disposition_reason = ?, retry_count = retry_count + ?,
                last_attempt_at = datetime('now'),
                next_attempt_at = CASE
                    WHEN ? IN ('deferred', 'retry') THEN datetime(
                        'now',
                        '+' || MIN(300, 5 * (1 << MIN(retry_count, 6))) || ' seconds'
                    )
                    ELSE NULL
                END,
                applied_at = CASE WHEN ? = 'applied' THEN datetime('now') ELSE applied_at END,
                updated_at = datetime('now')
            WHERE id = ?
            """,
            arguments: [state, reason, attempted ? 1 : 0, state, state, id]
        )
    }

    private static func redactExpiredTerminalPayloads(connection: Database, now: String?) throws -> Int {
        try connection.execute(
            sql: """
            UPDATE _sync_receive_journal
            SET payload = '', redacted_at = COALESCE(?, datetime('now'))
            WHERE redacted_at IS NULL
              AND (
                  (state = 'applied' AND applied_at IS NOT NULL
                   AND datetime(applied_at, '+30 days') <= datetime(COALESCE(?, 'now')))
                  OR
                  (state = 'refused'
                   AND datetime(updated_at, '+30 days') <= datetime(COALESCE(?, 'now')))
              )
            """,
            arguments: [now, now, now]
        )
        return connection.changesCount
    }

    /// The receive journal records transport provenance, not business payloads.
    /// Unknown values collapse to a stable test/audit label rather than being stored.
    private static func normalizedAuditLabel(_ value: String) -> String {
        switch value {
        case "lan_push", "lan_pull", "legacy_inbox", "test":
            return value
        default:
            return "test"
        }
    }
}
