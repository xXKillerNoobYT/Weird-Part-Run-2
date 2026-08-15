import Foundation
import GRDB

/// Fleet diagnostics — a bounded, self-pruning technical log that replicates
/// its important entries.
///
/// Owner request 2026-08-03: *"let's get the devices syncing and storing the
/// other devices' logs, self-clean old logs in 30 days, then the TestFlight
/// version on this computer syncs with the ones in the field so you have logs
/// to work with."* Field failures reached the developer only as screenshots
/// and recollection; this makes them first-class data.
///
/// Owner follow-up 2026-08-15, after builds 67/47: *"we need as much info as
/// we can … devloper, erros, worning's, time stamps, all, filters so we can
/// find the info then work are way out if needed … full loging"* — hence the
/// `debug`/`trace` levels, millisecond timestamps, the richer filters, and
/// `context(around:)`.
///
/// ## What replicates, and why not everything
///
/// Owner-approved 2026-08-15: **full verbose logging stays on the device that
/// produced it; only `warn` and above replicates.** `device_logs` rides the
/// same Bluetooth path as company records, so N devices cross-replicating
/// verbose logs is N² traffic over the transport #1684 is trying to stabilise
/// — the diagnostic would degrade the thing it diagnoses. Deep local entries
/// are *pulled* on demand (the `logs_recall` MCP tool, #1746) rather than
/// broadcast. The gate is in migration 126's triggers, not here, so it cannot
/// be bypassed by a caller.
///
/// Relationship to `activity_log`: that records what **users** did (business
/// audit). This records what the **app** did — sync outcomes, pairing
/// failures, startup errors — and is safe to prune.
public final class DeviceLogService: Sendable {
    /// Entries at or above this severity replicate to peers. Referenced by
    /// migration 126's triggers so the SQL and Swift cannot drift apart.
    public static let replicationMinSeverity = 40  // .warn

    /// Per-level retention, in days. A `debug` flood must never be able to
    /// evict an `error`: migration 121's single global newest-wins cap allowed
    /// exactly that, and would also let one noisy device erase quieter
    /// devices' entries out of the shared table.
    public static func retentionDays(for level: Level) -> Int {
        switch level {
        case .trace, .debug: return 1
        case .info: return 7
        case .warn, .error, .critical: return 30
        }
    }

    /// Per-level row caps, applied newest-wins *within* the level.
    public static func maxRows(for level: Level) -> Int {
        switch level {
        case .trace, .debug: return 20_000  // local-only, so it can be generous
        case .info: return 5_000
        case .warn, .error, .critical: return 5_000
        }
    }

    /// Retained so existing callers/tests referring to the old global cap keep
    /// compiling; the effective caps are per level.
    public static let retentionDays = 30

    public enum Level: String, Sendable, CaseIterable, Comparable {
        case trace, debug, info, warn, error, critical

        /// Numeric rank. `level` is a string in the schema, so ordering has to
        /// be explicit — string comparison would put `error` < `info` < `warn`.
        public var severity: Int {
            switch self {
            case .trace: return 10
            case .debug: return 20
            case .info: return 30
            case .warn: return 40
            case .error: return 50
            case .critical: return 60
            }
        }

        /// True when entries at this level leave the device.
        public var replicates: Bool { severity >= DeviceLogService.replicationMinSeverity }

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.severity < rhs.severity }
    }

    /// Identity of the device that produced an entry. Owner 2026-08-15: *"the
    /// log is suposed to be per a device with all the relvint info on the
    /// device … including the incompy device id"*.
    public struct DeviceInfo: Sendable, Equatable {
        public let deviceId: String
        /// Links to `devices.device_fingerprint` — the office-visible record.
        /// Deliberately not an FK; see migration 126.
        public let fingerprint: String?
        public let name: String?
        public let appVersion: String?
        public let buildNumber: String?
        public let osVersion: String?
        public let platform: String?
        public let model: String?

        public init(
            deviceId: String = DeviceIdentity.current,
            fingerprint: String? = nil,
            name: String? = nil,
            appVersion: String? = nil,
            buildNumber: String? = nil,
            osVersion: String? = nil,
            platform: String? = nil,
            model: String? = nil
        ) {
            self.deviceId = deviceId
            self.fingerprint = fingerprint
            self.name = name
            self.appVersion = appVersion
            self.buildNumber = buildNumber
            self.osVersion = osVersion
            self.platform = platform
            self.model = model
        }
    }

    public struct Entry: Sendable, Equatable {
        public let id: Int64
        public let deviceId: String
        public let deviceName: String?
        public let deviceFingerprint: String?
        public let appVersion: String?
        public let buildNumber: String?
        public let osVersion: String?
        public let platform: String?
        public let deviceModel: String?
        public let level: Level
        public let severity: Int
        public let category: String
        public let message: String
        public let detail: String?
        public let seq: Int64?
        public let utcOffsetMinutes: Int?
        public let createdAt: String
    }

    /// Filters for `recent()`. Grouped into a struct because the owner asked
    /// for several dimensions at once and a nine-argument function is worse.
    public struct Filter: Sendable {
        public var minLevel: Level?
        public var levels: [Level]
        public var categories: [String]
        public var deviceIds: [String]
        /// Inclusive lower bound, `YYYY-MM-DD HH:MM:SS[.SSS]`.
        public var since: String?
        /// Exclusive upper bound.
        public var until: String?
        /// Free-text, matched against message and detail.
        public var search: String?

        public init(
            minLevel: Level? = nil,
            levels: [Level] = [],
            categories: [String] = [],
            deviceIds: [String] = [],
            since: String? = nil,
            until: String? = nil,
            search: String? = nil
        ) {
            self.minLevel = minLevel
            self.levels = levels
            self.categories = categories
            self.deviceIds = deviceIds
            self.since = since
            self.until = until
            self.search = search
        }
    }

    private let db: AppDatabase
    private let device: DeviceInfo
    /// When false, `trace`/`debug` are dropped at the door. Off in the field so
    /// normal operation stays cheap; on when reproducing.
    private let verboseEnabled: Bool

    public init(db: AppDatabase, device: DeviceInfo = DeviceInfo(), verboseEnabled: Bool = false) {
        self.db = db
        self.device = device
        self.verboseEnabled = verboseEnabled
    }

    /// Convenience for the common case, kept so existing call sites and tests
    /// that pass loose fields keep working.
    public convenience init(
        db: AppDatabase,
        deviceId: String = DeviceIdentity.current,
        deviceName: String? = nil,
        appVersion: String? = nil
    ) {
        self.init(
            db: db,
            device: DeviceInfo(deviceId: deviceId, name: deviceName, appVersion: appVersion)
        )
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
        // Verbose entries are dropped before they touch the database, so the
        // developer toggle costs nothing when off.
        guard verboseEnabled || level.severity >= Level.info.severity else { return }

        let safeMessage = Self.redact(message)
        let safeDetail = detail.map(Self.redact)
        do {
            try db.writer.write { dbc in
                // Millisecond precision, written explicitly: SQLite's
                // `datetime('now')` default is whole-second, and whole seconds
                // cannot order two devices' entries against each other — which
                // is the one thing this table exists to support.
                let now = try String.fetchOne(
                    dbc, sql: "SELECT strftime('%Y-%m-%d %H:%M:%f','now')"
                ) ?? ISO8601DateFormatter().string(from: Date())
                // Monotonic per device, so ordering survives a clock change.
                let nextSeq = try Int64.fetchOne(
                    dbc,
                    sql: "SELECT COALESCE(MAX(seq), 0) + 1 FROM device_logs WHERE device_id = ?",
                    arguments: [device.deviceId]
                ) ?? 1
                try dbc.execute(
                    sql: """
                    INSERT INTO device_logs
                        (device_id, device_name, device_fingerprint, app_version,
                         build_number, os_version, platform, device_model,
                         level, severity, category, message, detail,
                         seq, utc_offset_minutes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        device.deviceId, device.name, device.fingerprint, device.appVersion,
                        device.buildNumber, device.osVersion, device.platform, device.model,
                        level.rawValue, level.severity, category, safeMessage, safeDetail,
                        nextSeq, TimeZone.current.secondsFromGMT() / 60, now, now,
                    ]
                )
            }
        } catch {
            // Deliberately silent — see doc comment.
        }
    }

    public func critical(_ category: String, _ message: String, detail: String? = nil) {
        log(.critical, category: category, message: message, detail: detail)
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

    public func debug(_ category: String, _ message: String, detail: String? = nil) {
        log(.debug, category: category, message: message, detail: detail)
    }

    public func trace(_ category: String, _ message: String, detail: String? = nil) {
        log(.trace, category: category, message: message, detail: detail)
    }

    // MARK: - Reading (the point of the exercise)

    /// Most recent entries across ALL devices — the fleet view the shop Mac
    /// reads after field devices sync their logs in.
    public func recent(limit: Int = 200, filter: Filter = Filter()) throws -> [Entry] {
        var conditions: [String] = []
        var args: [DatabaseValueConvertible] = []

        if let minLevel = filter.minLevel {
            // Expanded to a level set rather than `severity >= ?` on purpose.
            // `severity` was added by migration 126 with a DEFAULT of 30, so a
            // row written by an older sender — or by any raw INSERT — carries
            // 30 regardless of its actual level, and a numeric comparison would
            // silently drop that sender's errors. Filtering on the level string
            // is correct for every row ever written. (Sync payloads carry the
            // SENDER's columns; version skew is a first-class failure mode
            // here, not a hypothetical.)
            let atOrAbove = Level.allCases.filter { $0 >= minLevel }
            conditions.append("level IN (\(placeholders(atOrAbove.count)))")
            args.append(contentsOf: atOrAbove.map(\.rawValue))
        }
        if !filter.levels.isEmpty {
            conditions.append("level IN (\(placeholders(filter.levels.count)))")
            args.append(contentsOf: filter.levels.map(\.rawValue))
        }
        if !filter.categories.isEmpty {
            conditions.append("category IN (\(placeholders(filter.categories.count)))")
            args.append(contentsOf: filter.categories)
        }
        if !filter.deviceIds.isEmpty {
            conditions.append("device_id IN (\(placeholders(filter.deviceIds.count)))")
            args.append(contentsOf: filter.deviceIds)
        }
        if let since = filter.since { conditions.append("created_at >= ?"); args.append(since) }
        if let until = filter.until { conditions.append("created_at < ?"); args.append(until) }
        if let search = filter.search, !search.isEmpty {
            conditions.append("(message LIKE ? ESCAPE '\\' OR detail LIKE ? ESCAPE '\\')")
            let term = "%\(Self.escapeLike(search))%"
            args.append(term)
            args.append(term)
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        args.append(min(max(limit, 1), 1000))
        return try db.writer.read { dbc in
            try Row.fetchAll(
                dbc,
                sql: """
                SELECT * FROM device_logs \(whereClause)
                ORDER BY created_at DESC, seq DESC, id DESC LIMIT ?
                """,
                arguments: StatementArguments(args)
            ).map(Self.entry(from:))
        }
    }

    /// Owner 2026-08-15: *"filters so we can find the info then work are way
    /// out if needed"* — find the error, then see what surrounded it.
    ///
    /// Returns neighbours on the **same device**, which is what makes a causal
    /// story readable; `contextAcrossDevices` gives the interleaved fleet view
    /// of the same window.
    public func context(around entryId: Int64, before: Int = 50, after: Int = 50) throws -> [Entry] {
        try db.writer.read { dbc in
            guard let anchor = try Row.fetchOne(
                dbc, sql: "SELECT device_id, created_at, seq, id FROM device_logs WHERE id = ?",
                arguments: [entryId]
            ) else { return [] }

            let deviceId: String = anchor["device_id"]
            let createdAt: String = anchor["created_at"]
            let seq: Int64? = anchor["seq"]
            let anchorId: Int64 = anchor["id"]
            // Sort key: (created_at, seq, id). `seq` is NULL on rows written
            // before migration 126, so fall back to id for those.
            let ordering = "(created_at, COALESCE(seq, 0), id)"
            let anchorTuple = "(?, ?, ?)"

            let earlier = try Row.fetchAll(
                dbc,
                sql: """
                SELECT * FROM device_logs
                WHERE device_id = ? AND \(ordering) < \(anchorTuple)
                ORDER BY created_at DESC, COALESCE(seq, 0) DESC, id DESC LIMIT ?
                """,
                arguments: [deviceId, createdAt, seq ?? 0, anchorId, max(before, 0)]
            ).map(Self.entry(from:)).reversed()

            let anchorEntry = try Row.fetchOne(
                dbc, sql: "SELECT * FROM device_logs WHERE id = ?", arguments: [entryId]
            ).map(Self.entry(from:))

            let later = try Row.fetchAll(
                dbc,
                sql: """
                SELECT * FROM device_logs
                WHERE device_id = ? AND \(ordering) > \(anchorTuple)
                ORDER BY created_at ASC, COALESCE(seq, 0) ASC, id ASC LIMIT ?
                """,
                arguments: [deviceId, createdAt, seq ?? 0, anchorId, max(after, 0)]
            ).map(Self.entry(from:))

            return Array(earlier) + (anchorEntry.map { [$0] } ?? []) + later
        }
    }

    /// The same window as `context(around:)` but across every device, oldest
    /// first — for reading a two-device sync failure as one timeline.
    public func contextAcrossDevices(around entryId: Int64, seconds: Int = 30) throws -> [Entry] {
        try db.writer.read { dbc in
            guard let createdAt = try String.fetchOne(
                dbc, sql: "SELECT created_at FROM device_logs WHERE id = ?", arguments: [entryId]
            ) else { return [] }
            return try Row.fetchAll(
                dbc,
                sql: """
                SELECT * FROM device_logs
                WHERE created_at >= datetime(?, ?) AND created_at <= datetime(?, ?)
                ORDER BY created_at ASC, COALESCE(seq, 0) ASC, id ASC LIMIT 2000
                """,
                arguments: [createdAt, "-\(max(seconds, 1)) seconds", createdAt, "+\(max(seconds, 1)) seconds"]
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
                       SUM(CASE WHEN level IN ('error', 'critical') THEN 1 ELSE 0 END) AS errors,
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

    /// Delete entries past their level's retention window, then enforce each
    /// level's row cap. Call on launch and on the background pass; safe to
    /// call repeatedly. Returns rows removed.
    ///
    /// Retention and caps are **per level** so a `debug` flood cannot evict
    /// `error` rows — the failure mode of migration 121's single global
    /// newest-wins cap.
    @discardableResult
    public func prune() throws -> Int {
        try db.writer.write { dbc in
            var removed = 0
            for level in Level.allCases {
                try dbc.execute(
                    sql: "DELETE FROM device_logs WHERE level = ? AND created_at < datetime('now', ?)",
                    arguments: [level.rawValue, "-\(Self.retentionDays(for: level)) days"]
                )
                removed += dbc.changesCount

                try dbc.execute(
                    sql: """
                    DELETE FROM device_logs
                    WHERE level = ? AND id NOT IN (
                        SELECT id FROM device_logs WHERE level = ?
                        ORDER BY created_at DESC, COALESCE(seq, 0) DESC, id DESC LIMIT ?
                    )
                    """,
                    arguments: [level.rawValue, level.rawValue, Self.maxRows(for: level)]
                )
                removed += dbc.changesCount
            }
            return removed
        }
    }

    // MARK: - Safety

    /// Strip anything key-shaped before it reaches a replicated table. Logs
    /// travel between devices, so a leaked token would travel with them. This
    /// matters more under verbose logging, which pushes far more payload
    /// through this path.
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

    /// `LIKE` treats `%` and `_` as wildcards, so a user searching for a
    /// literal underscore (common here — `device_id`, `job_number`) would
    /// otherwise match far too much.
    static func escapeLike(_ term: String) -> String {
        term.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func entry(from row: Row) -> Entry {
        let level = Level(rawValue: row["level"] ?? "info") ?? .info
        return Entry(
            id: row["id"],
            deviceId: row["device_id"],
            deviceName: row["device_name"],
            deviceFingerprint: row["device_fingerprint"],
            appVersion: row["app_version"],
            buildNumber: row["build_number"],
            osVersion: row["os_version"],
            platform: row["platform"],
            deviceModel: row["device_model"],
            level: level,
            severity: row["severity"] ?? level.severity,
            category: row["category"],
            message: row["message"],
            detail: row["detail"],
            seq: row["seq"],
            utcOffsetMinutes: row["utc_offset_minutes"],
            createdAt: row["created_at"]
        )
    }
}
