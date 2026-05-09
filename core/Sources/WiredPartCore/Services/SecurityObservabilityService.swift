import Foundation
import GRDB

/// Security observability event recorder for auth/sync incident triage.
public struct SecurityObservabilityService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public enum EventType: String, Sendable {
        case authFailed = "auth_failed"
        case authLockout = "auth_lockout"
        case tokenRejected = "token_rejected"
        case replayRejected = "sync_replay_rejected"
        case syncAuthRejected = "sync_auth_rejected"
        case syncDeadLetter = "sync_dead_letter"
    }

    public struct Event: Sendable {
        public let id: Int64
        public let eventType: String
        public let source: String
        public let severity: String
        public let outcome: String
        public let traceId: String?
        public let detailsJSON: String
        public let createdAt: String
    }

    public func record(
        eventType: EventType,
        source: String,
        severity: String = "warning",
        outcome: String = "detected",
        traceId: String? = nil,
        details: [String: String] = [:]
    ) {
        let detailsJSON = (try? String(data: JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]), encoding: .utf8)) ?? "{}"
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: """
                    INSERT INTO security_observability_events
                        (event_type, source, severity, outcome, trace_id, details_json)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [eventType.rawValue, source, severity, outcome, traceId, detailsJSON]
                )
            }
        } catch {
            // Best-effort observability must not break auth/sync request handling.
        }
    }

    public func listRecent(limit: Int = 200) throws -> [Event] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(
                dbConn,
                sql: """
                SELECT id, event_type, source, severity, outcome, trace_id, details_json, created_at
                FROM security_observability_events
                ORDER BY id DESC
                LIMIT ?
                """,
                arguments: [max(1, limit)]
            )
            return rows.map {
                Event(
                    id: $0["id"],
                    eventType: $0["event_type"],
                    source: $0["source"],
                    severity: $0["severity"],
                    outcome: $0["outcome"],
                    traceId: $0["trace_id"],
                    detailsJSON: $0["details_json"],
                    createdAt: $0["created_at"]
                )
            }
        }
    }

    public func count(eventType: EventType, since: Date) throws -> Int {
        let sinceStamp = Self.sqliteDateTimeString(from: since)
        return try db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: """
                SELECT COUNT(*)
                FROM security_observability_events
                WHERE event_type = ?
                  AND created_at >= ?
                """,
                arguments: [eventType.rawValue, sinceStamp]
            ) ?? 0
        }
    }

    static func sqliteDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
