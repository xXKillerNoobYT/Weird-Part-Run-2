import Foundation
import GRDB

enum BluetoothPeerActivationError: Error {
    case injectedFailureBeforeCommit
}

struct PeerDeviceTrustSnapshot: Sendable {
    let deviceName: String?
    let platform: String?
    let role: String?
    let certificate: String?
    let lastSeenAt: String?
    let lastSyncAt: String?
    let isTrusted: Int
    let isDeactivated: Int
    let createdAt: String
}

/// Change Tracker — logs all local writes for sync.
///
/// Every INSERT, UPDATE, DELETE on the local SQLite database is
/// logged to the `_change_log` table. The sync engine reads this
/// log to know what changes to push to the shop server or peers.
///
/// The change log is append-only. Entries are marked as synced
/// (but never deleted) so we have a full audit trail.
///
/// Vector clocks: Each change gets a monotonically increasing `sequence`
/// number (via SQLite trigger in migration 008). The `_vector_clock` table
/// tracks what each peer has seen, enabling efficient delta sync — only
/// sending changes the other device hasn't received yet.
///
/// Ported from: `src/local/change-tracker.ts`
public enum ChangeTracker {

    /// The type of write operation being tracked.
    public enum Operation: String, Sendable {
        case insert = "INSERT"
        case update = "UPDATE"
        case delete = "DELETE"
    }

    // MARK: - Track Changes

    /// Log a write operation for future sync.
    ///
    /// Call this after every INSERT, UPDATE, or DELETE in a local service.
    /// The sync engine will pick up unsynced entries and push them to the shop.
    public static func trackChange(
        db: AppDatabase,
        tableName: String,
        recordId: Int64,
        operation: Operation,
        changedFields: [String: Any]? = nil,
        oldValues: [String: Any]? = nil,
        deviceId: String? = nil
    ) throws {
        let resolvedDeviceId = deviceId ?? DeviceIdentity.current
        let changedJSON: String? = changedFields.flatMap { try? jsonEncode($0) }
        let oldJSON: String? = oldValues.flatMap { try? jsonEncode($0) }

        try db.writer.write { dbConnection in
            // The migration-112 triggers already log a bare entry (device_id = '',
            // no field detail) for every write. When a caller ALSO tracks manually
            // (richer: changed_fields/old_values), UPGRADE the trigger's bare row
            // instead of inserting a duplicate — otherwise every reader of
            // _change_log (sync push, notebook history, audit log) sees doubles.
            // Plain UPDATE + changesCount (not RETURNING — unsupported on older
            // system SQLite builds; Copilot review on PR #1422).
            //
            // Claims the NEWEST matching bare row (MAX(id)). NOTE (#1795): this is a
            // heuristic and is not reliable when a stale bare row already exists for the
            // same (table, record, op) from a write that never calls trackChange
            // (BaseRepository track:false, rawRun, direct db.execute — all still fire the
            // migration-112 trigger). The correct fix binds the upgrade to the specific
            // bare row THIS write created (upgrade inside the write's own transaction, or
            // capture last_insert_rowid), which is out of scope here and tracked in #1795.
            // MAX is kept as the safer status quo: for a normal track:true write it claims
            // that write's own newest bare row; MIN would instead claim the stale older
            // row and mislabel it with the new write's field detail under the old timestamp.
            try dbConnection.execute(
                sql: """
                    UPDATE _change_log
                    SET device_id = ?, changed_fields = ?, old_values = ?
                    WHERE id = (
                        SELECT MAX(id) FROM _change_log
                        WHERE table_name = ? AND record_id = ? AND operation = ?
                          AND synced = 0 AND device_id = '' AND changed_fields IS NULL
                    )
                    """,
                arguments: [
                    resolvedDeviceId, changedJSON, oldJSON,
                    tableName, recordId, operation.rawValue,
                ]
            )
            guard dbConnection.changesCount == 0 else { return }

            try dbConnection.execute(
                sql: """
                    INSERT INTO _change_log
                        (device_id, table_name, record_id, operation, changed_fields, old_values)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    resolvedDeviceId,
                    tableName,
                    recordId,
                    operation.rawValue,
                    changedJSON,
                    oldJSON,
                ]
            )
        }
    }

    // MARK: - Pending Changes

    /// Get unsynced changes, ordered by timestamp. Capped at `limit` rows to prevent OOM on
    /// long-offline devices with large backlogs.
    public static func getPendingChanges(db: AppDatabase, limit: Int = 500) throws -> [ChangeLogEntry] {
        let entries = try db.writer.read { dbConnection in
            try ChangeLogEntry.fetchAll(
                dbConnection,
                sql: "SELECT * FROM _change_log WHERE synced = 0 ORDER BY timestamp ASC LIMIT ?",
                arguments: [limit]
            )
        }
        return Self.fillingLocalDeviceId(entries)
    }

    /// The change-tracking triggers (migration 112) write device_id as '' — SQL
    /// triggers cannot know the device identity. Substitute this device's id at
    /// read time so pushed changes are correctly attributed for LWW merging.
    static func fillingLocalDeviceId(_ entries: [ChangeLogEntry]) -> [ChangeLogEntry] {
        let localId = DeviceIdentity.current
        return entries.map { entry in
            guard entry.deviceId.isEmpty else { return entry }
            var filled = entry
            filled.deviceId = localId
            return filled
        }
    }

    /// Get count of unsynced changes (for UI badge).
    public static func getPendingChangeCount(db: AppDatabase) throws -> Int {
        try db.writer.read { dbConnection in
            try Int.fetchOne(
                dbConnection,
                sql: "SELECT COUNT(*) FROM _change_log WHERE synced = 0"
            ) ?? 0
        }
    }

    /// Mark changes as synced after successful push to shop.
    public static func markSynced(db: AppDatabase, ids: [Int64], batchId: String) throws {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        var args: [any DatabaseValueConvertible] = [batchId]
        args.append(contentsOf: ids)

        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    UPDATE _change_log SET synced = 1, sync_batch_id = ?
                    WHERE id IN (\(placeholders))
                    """,
                arguments: StatementArguments(args)
            )
        }
    }

    /// Clean up old synced entries (keep last 30 days). Returns number deleted.
    ///
    /// The two extra predicates exist because a per-peer watermark makes naive
    /// pruning lossy in two distinct ways:
    ///
    /// 1. `synced = 1` means "pushed at least once", NOT "pushed to everyone".
    ///    Deleting on it alone would discard rows a peer still has coming, which
    ///    is the #1645 defect wearing a different hat. Stop at the slowest peer.
    /// 2. The sequence trigger derives the next value from `MAX(sequence)` over
    ///    the SURVIVING rows, so pruning the row that holds the maximum makes the
    ///    counter fall back and REUSE sequence values. Any watermark parked above
    ///    the reused range would then skip every new row, silently and forever.
    ///    Keeping the high-water row is what makes the counter monotonic.
    @discardableResult
    public static func pruneOldChanges(db: AppDatabase) throws -> Int {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    DELETE FROM _change_log
                    WHERE synced = 1 AND timestamp < datetime('now', '-30 days')
                      AND sequence < COALESCE(
                            (SELECT MIN(last_sent_sequence) FROM _peer_send_watermark), 0
                          )
                      AND sequence < (SELECT COALESCE(MAX(sequence), 0) FROM _change_log)
                    """
            )
            return dbConnection.changesCount
        }
    }

    // MARK: - Per-Peer Send Watermark (#1645 P1 finding 9)

    /// One below the oldest change that has never been pushed anywhere.
    ///
    /// `synced = 1` is set by every successful push — shop, Bluetooth, or LAN —
    /// so `synced = 0` identifies work no peer can possibly have. A watermark
    /// seeded here therefore strands nothing pending, while treating everything
    /// older as already delivered so it is never replayed. When nothing is
    /// pending this collapses to `MAX(sequence)`, i.e. "start from now".
    static let deliveredFloorSQL = """
        COALESCE(
            (SELECT MIN(sequence) - 1 FROM _change_log WHERE synced = 0 AND sequence IS NOT NULL),
            (SELECT COALESCE(MAX(sequence), 0) FROM _change_log)
        )
        """

    /// Create this peer's cursor if it has none, at the delivered floor.
    ///
    /// Runs on the CALLER's connection so it commits or rolls back with the
    /// pairing transaction that registers the peer. `INSERT OR IGNORE`, never an
    /// upsert: peer registration is idempotent and re-runs on every re-pair, and
    /// overwriting a healthy peer's cursor would burn its unsent backlog.
    static func seedSendWatermark(dbConnection: Database, peerId: String) throws {
        try dbConnection.execute(
            sql: """
                INSERT OR IGNORE INTO _peer_send_watermark (peer_id, last_sent_sequence, updated_at)
                VALUES (?, \(deliveredFloorSQL), datetime('now'))
                """,
            arguments: [peerId]
        )
    }

    /// This peer's cursor, or nil when it has none.
    public static func getSendWatermark(db: AppDatabase, peerId: String) throws -> Int64? {
        try db.writer.read { dbConnection in
            try Int64.fetchOne(
                dbConnection,
                sql: "SELECT last_sent_sequence FROM _peer_send_watermark WHERE peer_id = ?",
                arguments: [peerId]
            )
        }
    }

    /// Changes this specific peer has not received, oldest first.
    ///
    /// Replaces `getPendingChanges` on the peer paths. Ordering by `sequence`
    /// rather than `timestamp` is required, not cosmetic: a cursor advanced to
    /// the highest sequence sent would skip any row that sorted earlier by
    /// timestamp but later by sequence.
    ///
    /// A peer with no cursor is seeded here rather than defaulting to 0. The two
    /// error directions are not symmetric — defaulting low replays historical
    /// deletes against a converged peer, while defaulting to the floor can only
    /// omit history that peer already holds from its snapshot.
    public static func getChangesForPeer(
        db: AppDatabase,
        peerId: String,
        limit: Int = 500
    ) throws -> [ChangeLogEntry] {
        let entries = try db.writer.write { dbConnection -> [ChangeLogEntry] in
            try seedSendWatermark(dbConnection: dbConnection, peerId: peerId)
            let since = try Int64.fetchOne(
                dbConnection,
                sql: "SELECT last_sent_sequence FROM _peer_send_watermark WHERE peer_id = ?",
                arguments: [peerId]
            ) ?? 0
            return try ChangeLogEntry.fetchAll(
                dbConnection,
                sql: """
                    SELECT * FROM _change_log
                    WHERE sequence IS NOT NULL AND sequence > ?
                    ORDER BY sequence ASC LIMIT ?
                    """,
                arguments: [since, limit]
            )
        }
        return Self.fillingLocalDeviceId(entries)
    }

    /// Record that this peer has received everything through `lastSequence`.
    ///
    /// `MAX()` so the cursor only ever moves forward — mirrors `updateVectorClock`
    /// on the receive side.
    public static func advanceSendWatermark(
        db: AppDatabase,
        peerId: String,
        lastSequence: Int64
    ) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _peer_send_watermark (peer_id, last_sent_sequence, updated_at)
                    VALUES (?, ?, datetime('now'))
                    ON CONFLICT(peer_id)
                    DO UPDATE SET last_sent_sequence = MAX(last_sent_sequence, ?),
                                  updated_at = datetime('now')
                    """,
                arguments: [peerId, lastSequence, lastSequence]
            )
        }
    }

    // MARK: - Vector Clock Operations

    /// Get this device's vector clock — what sequence number we last received
    /// from each known peer. Used in pull requests so peers only send new changes.
    public static func getVectorClock(db: AppDatabase, deviceId: String? = nil) throws -> [String: Int64] {
        let resolvedDeviceId = deviceId ?? DeviceIdentity.current
        return try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: "SELECT peer_id, last_sequence FROM _vector_clock WHERE device_id = ?",
                arguments: [resolvedDeviceId]
            )
            var vc: [String: Int64] = [:]
            for row in rows {
                let peerId: String = row["peer_id"]
                let lastSeq: Int64 = row["last_sequence"]
                vc[peerId] = lastSeq
            }
            return vc
        }
    }

    /// Update the vector clock after receiving changes from a peer.
    /// Records the highest sequence number we've seen from that peer.
    public static func updateVectorClock(
        db: AppDatabase,
        peerId: String,
        lastSequence: Int64,
        deviceId: String? = nil
    ) throws {
        let resolvedDeviceId = deviceId ?? DeviceIdentity.current
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _vector_clock (device_id, peer_id, last_sequence, updated_at)
                    VALUES (?, ?, ?, datetime('now'))
                    ON CONFLICT(device_id, peer_id)
                    DO UPDATE SET last_sequence = MAX(last_sequence, ?), updated_at = datetime('now')
                    """,
                arguments: [resolvedDeviceId, peerId, lastSequence, lastSequence]
            )
        }
    }

    /// Get changes since a specific sequence number. Capped at `limit` rows to prevent OOM on
    /// long-offline peers with large backlogs. Callers should check if the batch is full and
    /// re-request with the last returned sequence to paginate.
    public static func getChangesSince(db: AppDatabase, sinceSequence: Int64, limit: Int = 500) throws -> [ChangeLogEntry] {
        let entries = try db.writer.read { dbConnection in
            try ChangeLogEntry.fetchAll(
                dbConnection,
                sql: "SELECT * FROM _change_log WHERE sequence > ? ORDER BY sequence ASC LIMIT ?",
                arguments: [sinceSequence, limit]
            )
        }
        return Self.fillingLocalDeviceId(entries)
    }

    /// Get the current maximum sequence number in our change log.
    /// Peers store this to know where to resume next sync.
    public static func getMaxSequence(db: AppDatabase) throws -> Int64 {
        try db.writer.read { dbConnection in
            try Int64.fetchOne(
                dbConnection,
                sql: "SELECT COALESCE(MAX(sequence), 0) FROM _change_log"
            ) ?? 0
        }
    }

    // MARK: - Device Registry

    /// Register or update a peer device we've synced with.
    /// Builds a local registry of known devices in the company.
    public static func registerPeerDevice(
        db: AppDatabase,
        peerId: String,
        peerName: String,
        platform: String? = nil,
        keyAgreementPublicKey: String? = nil
    ) throws {
        try db.writer.write { dbConnection in
            try registerPeerDevice(
                dbConnection: dbConnection,
                peerId: peerId,
                peerName: peerName,
                platform: platform,
                keyAgreementPublicKey: keyAgreementPublicKey
            )
        }
    }

    /// Activate Bluetooth host trust inside one SQLite transaction. The injected
    /// failure seam runs after the write but before commit so regressions can prove
    /// that GRDB restores the exact prior row rather than relying on compensation.
    static func activateBluetoothPeerTrust(
        db: AppDatabase,
        peerId: String,
        peerName: String,
        platform: String?,
        keyAgreementPublicKey: String,
        injectFailureBeforeCommit: Bool = false
    ) throws {
        try db.writer.write { dbConnection in
            try registerPeerDevice(
                dbConnection: dbConnection,
                peerId: peerId,
                peerName: peerName,
                platform: platform,
                keyAgreementPublicKey: keyAgreementPublicKey
            )
            if injectFailureBeforeCommit {
                throw BluetoothPeerActivationError.injectedFailureBeforeCommit
            }
        }
    }

    private static func registerPeerDevice(
        dbConnection: Database,
        peerId: String,
        peerName: String,
        platform: String?,
        keyAgreementPublicKey: String?
    ) throws {
        let encodedKey = keyAgreementPublicKey.map { "x25519:\($0)" }
        let replicatedKey = try DeviceRegistryCertificateCodec.production.store(encodedKey)
        try dbConnection.execute(
            sql: """
                INSERT INTO _device_registry (device_id, device_name, platform, certificate, last_seen_at, is_trusted)
                VALUES (?, ?, ?, ?, datetime('now'), CASE WHEN ? IS NOT NULL THEN 1 ELSE 0 END)
                ON CONFLICT(device_id)
                DO UPDATE SET device_name = ?,
                              platform = COALESCE(?, platform),
                              certificate = COALESCE(?, certificate),
                              is_trusted = CASE WHEN ? IS NOT NULL THEN 1 ELSE is_trusted END,
                              is_deactivated = CASE WHEN ? IS NOT NULL THEN 0 ELSE is_deactivated END,
                              last_seen_at = datetime('now')
                """,
            arguments: [
                peerId, peerName, platform, replicatedKey,
                replicatedKey, peerName, platform, replicatedKey, replicatedKey, replicatedKey,
            ]
        )
        // Give the peer a delivery cursor in the same transaction that registers
        // it, so trust and delivery state can never disagree. This writes only
        // `_peer_send_watermark` — it must not touch `is_trusted` or
        // `is_deactivated` above, and `INSERT OR IGNORE` cannot throw on a
        // re-pair, because a throw here would roll back the pairing itself.
        try seedSendWatermark(dbConnection: dbConnection, peerId: peerId)
    }

    static func capturePeerDeviceTrust(
        db: AppDatabase,
        peerId: String
    ) throws -> PeerDeviceTrustSnapshot? {
        try db.writer.read { dbConnection in
            guard let row = try Row.fetchOne(
                dbConnection,
                sql: """
                    SELECT device_name, platform, role, certificate, last_seen_at,
                           last_sync_at, is_trusted, is_deactivated, created_at
                    FROM _device_registry WHERE device_id = ?
                    """,
                arguments: [peerId]
            ) else { return nil }
            let certificate: String? = row["certificate"]
            try DeviceRegistryCertificateCodec.production.validateStored(certificate)
            return PeerDeviceTrustSnapshot(
                deviceName: row["device_name"],
                platform: row["platform"],
                role: row["role"],
                // Preserve the durable representation exactly. A rollback must not
                // turn a valid legacy record into a new envelope, and must never
                // launder invalid ciphertext into a plaintext-looking value.
                certificate: certificate,
                lastSeenAt: row["last_seen_at"],
                lastSyncAt: row["last_sync_at"],
                isTrusted: row["is_trusted"],
                isDeactivated: row["is_deactivated"],
                createdAt: row["created_at"]
            )
        }
    }

    static func restorePeerDeviceTrust(
        db: AppDatabase,
        peerId: String,
        snapshot: PeerDeviceTrustSnapshot?
    ) throws {
        if let snapshot {
            try DeviceRegistryCertificateCodec.production.validateStored(snapshot.certificate)
        }
        try db.writer.write { dbConnection in
            guard let snapshot else {
                try dbConnection.execute(
                    sql: "DELETE FROM _device_registry WHERE device_id = ?",
                    arguments: [peerId]
                )
                // The peer never existed before this pairing, so its delivery
                // cursor must not outlive it either. Leaving one behind is not
                // lossy (a stale floor only over-sends), but it would let a
                // rolled-back pairing leave state that a later re-pair inherits.
                try dbConnection.execute(
                    sql: "DELETE FROM _peer_send_watermark WHERE peer_id = ?",
                    arguments: [peerId]
                )
                return
            }
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (
                        device_id, device_name, platform, role, certificate,
                        last_seen_at, last_sync_at, is_trusted, is_deactivated, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(device_id) DO UPDATE SET
                        device_name = excluded.device_name,
                        platform = excluded.platform,
                        role = excluded.role,
                        certificate = excluded.certificate,
                        last_seen_at = excluded.last_seen_at,
                        last_sync_at = excluded.last_sync_at,
                        is_trusted = excluded.is_trusted,
                        is_deactivated = excluded.is_deactivated,
                        created_at = excluded.created_at
                    """,
                arguments: [
                    peerId,
                    snapshot.deviceName,
                    snapshot.platform,
                    snapshot.role,
                    snapshot.certificate,
                    snapshot.lastSeenAt,
                    snapshot.lastSyncAt,
                    snapshot.isTrusted,
                    snapshot.isDeactivated,
                    snapshot.createdAt,
                ]
            )
        }
    }

    /// Update the last sync time for a peer in the device registry.
    public static func updatePeerSyncTime(db: AppDatabase, peerId: String) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    UPDATE _device_registry SET last_sync_at = datetime('now'), last_seen_at = datetime('now')
                    WHERE device_id = ?
                    """,
                arguments: [peerId]
            )
        }
    }

    // MARK: - Private

    private static func jsonEncode(_ dict: [String: Any]) throws -> String? {
        // Filter out NSNull values for cleaner JSON
        let cleaned = dict.compactMapValues { value -> Any? in
            if value is NSNull { return nil }
            return value
        }
        guard !cleaned.isEmpty else { return nil }

        // Convert to JSON-safe types
        var jsonDict: [String: Any] = [:]
        for (key, value) in cleaned {
            switch value {
            case let v as String: jsonDict[key] = v
            case let v as Int: jsonDict[key] = v
            case let v as Int64: jsonDict[key] = v
            case let v as Double: jsonDict[key] = v
            case let v as Bool: jsonDict[key] = v
            case Optional<Any>.none: continue
            default: jsonDict[key] = "\(value)"
            }
        }

        let data = try JSONSerialization.data(withJSONObject: jsonDict, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - DeviceIdentity

/// Persistent device identity provider.
/// Stores a stable UUID in UserDefaults so the same device ID
/// is used across app launches. Falls back to a new UUID on first use.
public enum DeviceIdentity: Sendable {
    private static let userDefaultsKey = "com.wiredpart.deviceId"

    /// The current device's unique identifier.
    /// Reads from UserDefaults on first access; generates and persists a new UUID
    /// if none exists. This ensures the same device ID survives app restarts.
    ///
    /// Fix #225: `let` instead of `var` — nothing reassigns this, and Swift's
    /// lazy static-let initialization is already thread-safe.
    public static let current: String = {
        if let stored = UserDefaults.standard.string(forKey: userDefaultsKey) {
            return stored
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: userDefaultsKey)
        return newId
    }()
}
