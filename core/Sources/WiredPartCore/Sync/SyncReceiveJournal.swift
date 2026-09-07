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

        /// Attempt counters include earlier fixed-point passes. ACK decisions need
        /// the final durable state instead: a child deferred on pass one may have
        /// applied after its parent in a later pass.
        var hasUnresolvedEntries = false
    }

    static func record(
        db: AppDatabase,
        sourcePeerId: String,
        changes: [IncomingChange],
        auditMetadata: String
    ) throws {
        guard !changes.isEmpty else { return }
        let normalizedAuditMetadata = normalizedAuditLabel(auditMetadata)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try db.writer.write { connection in
            // Receipt is a lifecycle boundary, so it also performs bounded cleanup.
            // It is one idempotent UPDATE, not a timer or a replay loop.
            _ = try redactExpiredTerminalPayloads(connection: connection, now: nil)
            for change in changes {
                let payload = try String(decoding: encoder.encode(change), as: UTF8.self)
                if let sequence = change.id {
                    try connection.execute(
                        sql: """
                        INSERT OR IGNORE INTO _sync_receive_journal
                            (source_peer_id, source_sequence, payload, state, audit_metadata)
                        VALUES (?, ?, ?, 'received', ?)
                        """,
                        arguments: [sourcePeerId, sequence, payload, normalizedAuditMetadata]
                    )
                    // A sender restored from backup can reuse its sequence numbers.
                    // The old unique key must remain idempotent for an identical
                    // delivery, but it must never silently discard different data.
                    if connection.changesCount == 0 {
                        let existingPayload = try String.fetchOne(
                            connection,
                            sql: """
                            SELECT payload FROM _sync_receive_journal
                            WHERE source_peer_id = ? AND source_sequence = ?
                            """,
                            arguments: [sourcePeerId, sequence]
                        )
                        guard existingPayload == payload else {
                            throw SyncReceiveJournalError.sequencePayloadMismatch
                        }
                    }
                } else {
                    // Legacy/shop payloads can omit a source sequence. Their exact
                    // encoded payload is the available delivery identity: suppress a
                    // resend, but retain independently encoded changes as new rows.
                    let existingID = try Int64.fetchOne(
                        connection,
                        sql: """
                        SELECT id FROM _sync_receive_journal
                        WHERE source_peer_id = ? AND payload = ?
                        LIMIT 1
                        """,
                        arguments: [sourcePeerId, payload]
                    )
                    if existingID == nil {
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

    static func applyPending(
        db: AppDatabase,
        localDeviceId: String,
        sourcePeerId: String? = nil,
        resolving resolver: ((Database, IncomingChange, String) throws -> MergeResult)? = nil
    ) throws -> ApplyResult {
        // Applying pending work is the other deterministic lifecycle boundary.
        // This remains a single bounded cleanup query even when fixed-point replay
        // takes multiple passes.
        _ = try redactExpiredTerminalPayloads(db: db)
        var result = ApplyResult()
        var appliedThisPass: Int
        // A journal replay is a source-ordered batch even though each receipt's
        // mutation/disposition retains its own transaction. Share the collision
        // context across those transactions so a row that temporarily wants a
        // natural key can replay after a later receipt vacates it.
        let collisionContext = ConflictResolver.ApplyContext(disposition: .perRowDeferred)
        var parkedEntryIDs: [Int64] = []

        // A child can precede its parent in durable source order. Run bounded
        // fixed-point passes: every pass preserves that order, and only a newly
        // applied row permits another pass. This is neither head-only requeueing
        // nor a hot loop for a missing parent / transient failure.
        repeat {
            appliedThisPass = 0
            let entries = try pendingEntries(db: db, sourcePeerId: sourcePeerId)
            for entry in entries {
                let disposition = try db.writer.write { connection -> (applied: Int, deferred: Int, refused: Int, retryable: Int) in
                    let change = try JSONDecoder().decode(IncomingChange.self, from: Data(entry.payload.utf8))
                    // Production uses the connection-owned resolver so the business
                    // mutation and the durable journal disposition commit or roll back
                    // together. Test injection shares that connection, avoiding a
                    // nested GRDB writer while retaining deterministic classifications.
                    let deferredBefore = collisionContext.deferredCount
                    let merge = try resolver?(connection, change, localDeviceId)
                        ?? ConflictResolver.resolveAndApplyChange(
                            in: connection,
                            change: change,
                            localDeviceId: localDeviceId,
                            context: collisionContext
                        )
                    if merge.errors > 0 {
                        try update(connection: connection, id: entry.id, state: "retry", reason: "transient_apply_failure", attempted: true)
                        return (0, 0, 0, 1)
                    }
                    if merge.foreignKeyDeferrals > 0 {
                        try update(connection: connection, id: entry.id, state: "deferred", reason: "foreign_key_parent_unavailable", attempted: true)
                        return (0, 1, 0, 0)
                    }
                    if collisionContext.deferredCount > deferredBefore {
                        try update(connection: connection, id: entry.id, state: "deferred", reason: "natural_key_ordering_pending", attempted: true)
                        parkedEntryIDs.append(entry.id)
                        return (0, 1, 0, 0)
                    }
                    if merge.permanentRefusals > 0 || merge.schemaDrops > 0 || merge.applied == 0 {
                        // A clean resolver invocation is not proof that this entry
                        // applied. Keep deterministic skips/collisions/supersessions
                        // terminal and auditable without misreporting them as applies.
                        try update(connection: connection, id: entry.id, state: "refused", reason: "irreconcilable_apply_refusal", attempted: true)
                        return (0, 0, 1, 0)
                    }
                    try update(connection: connection, id: entry.id, state: "applied", reason: nil, attempted: true)
                    return (1, 0, 0, 0)
                }
                result.applied += disposition.applied
                result.deferred += disposition.deferred
                result.refused += disposition.refused
                result.retryable += disposition.retryable
                appliedThisPass += disposition.applied
            }
            // A later receipt may have vacated a key that an earlier receipt
            // parked. Drain it before deciding whether another source-order pass
            // is useful; otherwise the first receipt was terminally refused even
            // though the original delivery was replayable as a batch.
            let replayErrors = try ConflictResolver.drainDeferredMergesPerRow(db, collisionContext)
            if replayErrors > 0 {
                result.retryable += replayErrors
            } else if !parkedEntryIDs.isEmpty {
                let terminalState = collisionContext.keyCollisions > 0 ? "refused" : "applied"
                let terminalReason = terminalState == "refused" ? "irreconcilable_apply_refusal" : nil
                try db.writer.write { connection in
                    for id in parkedEntryIDs {
                        try update(connection: connection, id: id, state: terminalState, reason: terminalReason, attempted: false)
                    }
                }
                if terminalState == "applied" {
                    result.applied += parkedEntryIDs.count
                    appliedThisPass += parkedEntryIDs.count
                } else {
                    result.refused += parkedEntryIDs.count
                }
                parkedEntryIDs.removeAll()
            }
        } while appliedThisPass > 0
        result.hasUnresolvedEntries = try hasUnresolvedEntries(db: db, sourcePeerId: sourcePeerId)
        return result
    }

    static func hasUnresolvedEntries(db: AppDatabase, sourcePeerId: String?) throws -> Bool {
        try db.writer.read { connection in
            try Bool.fetchOne(
                connection,
                sql: """
                SELECT EXISTS(
                    SELECT 1 FROM _sync_receive_journal
                    WHERE state IN ('received', 'deferred', 'retry')
                      AND (? IS NULL OR source_peer_id = ?)
                )
                """,
                arguments: [sourcePeerId, sourcePeerId]
            ) ?? false
        }
    }

    private static func pendingEntries(db: AppDatabase, sourcePeerId: String?) throws -> [Entry] {
        try db.writer.read { connection in
            try Entry.fetchAll(
                connection,
                sql: """
                SELECT id, source_peer_id, source_sequence, payload, state
                FROM _sync_receive_journal
                WHERE (
                    state = 'received'
                    -- The first three attempts preserve a child-before-parent
                    -- fixed-point replay in one delivery. Thereafter, an
                    -- unresolved row is retried at most once per minute rather
                    -- than being rewritten by every five-second inbox sweep.
                    OR (state IN ('deferred', 'retry') AND (
                        retry_count < 3
                        OR last_attempt_at IS NULL
                        OR last_attempt_at <= datetime('now', '-60 seconds')
                    ))
                )
                  AND (? IS NULL OR source_peer_id = ?)
                ORDER BY id ASC
                """
                , arguments: [sourcePeerId, sourcePeerId]
            )
        }
    }

    private static func update(connection: Database, id: Int64, state: String, reason: String?, attempted: Bool) throws {
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
              -- Sequenced LAN receipts use their payload for duplicate and restore
              -- verification. Retain it until a payload digest is introduced;
              -- erasing it would turn a retransmit after response loss into a
              -- permanent sequence mismatch.
              AND source_sequence IS NULL
            """,
            arguments: [now, now, now]
        )
        return connection.changesCount
    }

    /// The receive journal records transport provenance, not business payloads.
    /// Unknown values collapse to a stable test/audit label rather than being stored.
    private static func normalizedAuditLabel(_ value: String) -> String {
        switch value {
        case "lan_push", "lan_pull", "shop_pull", "legacy_inbox", "test":
            return value
        default:
            return "test"
        }
    }
}

enum SyncReceiveJournalError: Error, Equatable {
    case sequencePayloadMismatch
}
