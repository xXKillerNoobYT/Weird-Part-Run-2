import Foundation
import GRDB

/// Local-only debug telemetry for the first-launch checklist.
///
/// This service intentionally has no networking imports or endpoints. It writes
/// only to SQLite, and only after the beta setting is explicitly enabled.
public final class OnboardingTelemetryService: Sendable {
    public static let enabledSettingKey = "onboarding_telemetry_enabled"
    public static let settingsCategory = "privacy"

    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public struct Event: Codable, FetchableRecord, Sendable, Identifiable {
        public let id: Int64
        public let eventType: String
        public let payloadJSON: String?
        public let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case eventType = "event_type"
            case payloadJSON = "payload_json"
            case createdAt = "created_at"
        }
    }

    public enum EventType: String, Sendable {
        case welcomeShown = "onboarding.welcome_shown"
        case welcomeDismissed = "onboarding.welcome_dismissed"
        case cardShown = "onboarding.card_shown"
        case stepTapped = "onboarding.step_tapped"
        case stepCompleted = "onboarding.step_completed"
        case cardDismissed = "onboarding.card_dismissed"
        case checklistRestarted = "onboarding.checklist_restarted"
    }

    public var isEnabled: Bool {
        get throws {
            try db.writer.read { dbConnection in
                let value = try String.fetchOne(
                    dbConnection,
                    sql: "SELECT value FROM settings WHERE key = ?",
                    arguments: [Self.enabledSettingKey]
                )
                return value == "true"
            }
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO settings (key, value, category, updated_at)
                    VALUES (?, ?, ?, datetime('now'))
                    ON CONFLICT(key) DO UPDATE SET value = ?, category = ?, updated_at = datetime('now')
                    """,
                arguments: [Self.enabledSettingKey, enabled ? "true" : "false", Self.settingsCategory, enabled ? "true" : "false", Self.settingsCategory]
            )
        }
    }

    public func record(_ eventType: EventType, payload: [String: TelemetryValue] = [:]) throws {
        try record(eventType.rawValue, payload: payload)
    }

    public func record(_ eventType: String, payload: [String: TelemetryValue] = [:]) throws {
        let payloadJSON = try encodePayload(payload)

        try db.writer.write { dbConnection in
            let enabled = try String.fetchOne(
                dbConnection,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [Self.enabledSettingKey]
            ) == "true"
            guard enabled else { return }

            try dbConnection.execute(
                sql: """
                    INSERT INTO onboarding_events (event_type, payload_json, created_at)
                    VALUES (?, ?, datetime('now'))
                    """,
                arguments: [eventType, payloadJSON]
            )
        }
    }

    public func listEvents(limit: Int = 100) throws -> [Event] {
        let boundedLimit = max(1, min(limit, 500))
        return try db.writer.read { dbConnection in
            try Event.fetchAll(
                dbConnection,
                sql: """
                    SELECT id, event_type, payload_json, created_at
                    FROM onboarding_events
                    ORDER BY datetime(created_at) DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [boundedLimit]
            )
        }
    }

    public func deleteAllEvents() throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(sql: "DELETE FROM onboarding_events")
        }
    }

    private func encodePayload(_ payload: [String: TelemetryValue]) throws -> String? {
        guard !payload.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8)
    }
}

public enum TelemetryValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}
