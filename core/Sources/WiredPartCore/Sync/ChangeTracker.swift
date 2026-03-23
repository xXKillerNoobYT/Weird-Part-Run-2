import Foundation
import GRDB

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

    /// Get all unsynced changes, ordered by timestamp.
    public static func getPendingChanges(db: AppDatabase) throws -> [ChangeLogEntry] {
        try db.writer.read { dbConnection in
            try ChangeLogEntry.fetchAll(
                dbConnection,
                sql: "SELECT * FROM _change_log WHERE synced = 0 ORDER BY timestamp ASC"
            )
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
    @discardableResult
    public static func pruneOldChanges(db: AppDatabase) throws -> Int {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    DELETE FROM _change_log
                    WHERE synced = 1 AND timestamp < datetime('now', '-30 days')
                    """
            )
            return dbConnection.changesCount
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

    /// Get changes since a specific sequence number.
    /// Used when a peer requests our changes — we only send what they haven't seen.
    public static func getChangesSince(db: AppDatabase, sinceSequence: Int64) throws -> [ChangeLogEntry] {
        try db.writer.read { dbConnection in
            try ChangeLogEntry.fetchAll(
                dbConnection,
                sql: "SELECT * FROM _change_log WHERE sequence > ? ORDER BY sequence ASC",
                arguments: [sinceSequence]
            )
        }
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
        platform: String? = nil
    ) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO _device_registry (device_id, device_name, platform, last_seen_at, is_trusted)
                    VALUES (?, ?, ?, datetime('now'), 1)
                    ON CONFLICT(device_id)
                    DO UPDATE SET device_name = ?, last_seen_at = datetime('now')
                    """,
                arguments: [peerId, peerName, platform, peerName]
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
    nonisolated(unsafe) public static var current: String = {
        if let stored = UserDefaults.standard.string(forKey: userDefaultsKey) {
            return stored
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: userDefaultsKey)
        return newId
    }()
}
