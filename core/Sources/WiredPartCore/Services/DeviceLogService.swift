import Foundation
import GRDB

/// Fleet diagnostics — a bounded, self-pruning, **replicated** technical log.
///
/// Owner request 2026-08-03: *"let's get the devices syncing and storing the
/// other devices' logs, self-clean old logs in 30 days, then the TestFlight
/// version on this computer syncs with the ones in the field so you have logs
/// to work with."* Field failures currently reach the developer only as
/// screenshots and recollection; this makes them first-class data that travels
/// on the same sync path as company records.
///
/// Relationship to `activity_log`: that table records what **users** did
/// (business audit). This records what the **app** did — sync outcomes,
/// pairing failures, startup errors — and is safe to prune.
public final class DeviceLogService: Sendable {
    /// Retention window. Rows older than this are removed on `prune()`.
    public static let retentionDays = 30
    /// Hard cap so a pathological logger cannot bloat the database or the sync
    /// payload between prunes; the newest rows always win.
    public static let maxRows = 5_000

    public enum Level: String, Sendable, CaseIterable {
        case error, warn, info
    }

    public struct Entry: Sendable, Equatable {
        public let id: Int64
        public let deviceId: String
        public let deviceName: String?
        public let appVersion: String?
        public let level: Level
        public let category: String
        public let message: String
        public let detail: String?
        public let createdAt: String
    }

    private let db: AppDatabase
    private let deviceId: String
    private let deviceName: String?
    private let appVersion: String?

    public init(
        db: AppDatabase,
        deviceId: String = DeviceIdentity.current,
        deviceName: String? = nil,
        appVersion: String? = nil
    ) {
        self.db = db
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.appVersion = appVersion
    }

    // MARK: - Writing

    /// Record one diagnostic line. Never throws: a logger that can break the
    /// operation it is describing is worse than no logger.
    public func log(
        _ level: Level,
        category: String,
        message: String,
        detail: String? = nil
    ) {
        let safeMessage = Self.redact(message)
        let safeDetail = detail.map(Self.redact)
        do {
            try db.writer.write { dbc in
                try dbc.execute(
                    sql: """
                    INSERT INTO device_logs
                        (device_id, device_name, app_version, level, category, message, detail)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        deviceId, deviceName, appVersion,
                        level.rawValue, category, safeMessage, safeDetail,
                    ]
                )
            }
        } catch {
            // Deliberately silent — see doc comment.
        }
    }

    public func error(_ category: String, _ message: String, detail: String? = nil) {
        log(.error, category: category, message: message, detail: detail)
    }

    public func warn(_ category: String, _ message: String, detail: String? = nil) {
        log(.warn, category: category, message: message, detail: detail)
    }

    public func info(_ category: String, _ message: String, detail: String? = nil) {
        log(.info, category: category, message: message, detail: detail)
    }

    // MARK: - Reading (the point of the exercise)

    /// Most recent entries across ALL devices — the fleet view the shop Mac
    /// reads after field devices sync their logs in.
    public func recent(
        limit: Int = 200,
        level: Level? = nil,
        category: String? = nil,
        deviceId: String? = nil
    ) throws -> [Entry] {
        var conditions: [String] = []
        var args: [DatabaseValueConvertible] = []
        if let level { conditions.append("level = ?"); args.append(level.rawValue) }
        if let category { conditions.append("category = ?"); args.append(category) }
        if let deviceId { conditions.append("device_id = ?"); args.append(deviceId) }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        args.append(min(max(limit, 1), 1000))
        return try db.writer.read { dbc in
            try Row.fetchAll(
                dbc,
                sql: """
                SELECT * FROM device_logs \(whereClause)
                ORDER BY created_at DESC, id DESC LIMIT ?
                """,
                arguments: StatementArguments(args)
            ).map(Self.entry(from:))
        }
    }

    /// Devices that have reported logs, with counts — "who is out there and
    /// how noisy are they".
    public func deviceSummary() throws -> [(deviceId: String, deviceName: String?, errors: Int, total: Int, lastSeen: String?)] {
        try db.writer.read { dbc in
            try Row.fetchAll(dbc, sql: """
                SELECT device_id,
                       MAX(device_name) AS device_name,
                       SUM(CASE WHEN level = 'error' THEN 1 ELSE 0 END) AS errors,
                       COUNT(*) AS total,
                       MAX(created_at) AS last_seen
                FROM device_logs GROUP BY device_id ORDER BY last_seen DESC
                """).map {
                (
                    deviceId: $0["device_id"],
                    deviceName: $0["device_name"],
                    errors: $0["errors"] ?? 0,
                    total: $0["total"] ?? 0,
                    lastSeen: $0["last_seen"]
                )
            }
        }
    }

    // MARK: - Pruning

    /// Delete entries older than the retention window, then enforce the row
    /// cap. Call on launch; safe to call repeatedly. Returns rows removed.
    @discardableResult
    public func prune(retentionDays: Int = DeviceLogService.retentionDays) throws -> Int {
        let days = max(retentionDays, 1)
        return try db.writer.write { dbc in
            try dbc.execute(
                sql: "DELETE FROM device_logs WHERE created_at < datetime('now', ?)",
                arguments: ["-\(days) days"]
            )
            var removed = dbc.changesCount
            // Newest-wins cap.
            try dbc.execute(sql: """
                DELETE FROM device_logs WHERE id NOT IN (
                    SELECT id FROM device_logs ORDER BY created_at DESC, id DESC LIMIT \(Self.maxRows)
                )
                """)
            removed += dbc.changesCount
            return removed
        }
    }

    // MARK: - Safety

    /// Strip anything key-shaped before it reaches a replicated table. Logs
    /// travel between devices, so a leaked token would travel with them.
    static func redact(_ text: String) -> String {
        var out = text
        for pattern in [
            #"wpal_[A-Za-z0-9_-]{8,}"#,                  // Agent Link keys
            #"[A-Za-z0-9+/]{40,}={0,2}"#,                // base64 key material
            #"(?i)(token|secret|password|pin)\s*[:=]\s*\S+"#,
        ] {
            out = out.replacingOccurrences(
                of: pattern, with: "[redacted]", options: .regularExpression
            )
        }
        return String(out.prefix(2_000))
    }

    private static func entry(from row: Row) -> Entry {
        Entry(
            id: row["id"],
            deviceId: row["device_id"],
            deviceName: row["device_name"],
            appVersion: row["app_version"],
            level: Level(rawValue: row["level"] ?? "info") ?? .info,
            category: row["category"],
            message: row["message"],
            detail: row["detail"],
            createdAt: row["created_at"]
        )
    }
}
