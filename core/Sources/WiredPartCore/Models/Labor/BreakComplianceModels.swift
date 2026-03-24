import Foundation
import GRDB

// MARK: - Break Policy

/// State or company break/lunch policy defining required breaks per work day.
public struct BreakPolicy: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var stateCode: String?
    public var policyType: String
    public var workDayHours: Int
    public var lunchMinutes: Int
    public var breakCount: Int
    public var breakMinutes: Int
    public var dataSource: String?
    public var dataDate: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "break_policies"

    enum CodingKeys: String, CodingKey {
        case id
        case stateCode = "state_code"
        case policyType = "policy_type"
        case workDayHours = "work_day_hours"
        case lunchMinutes = "lunch_minutes"
        case breakCount = "break_count"
        case breakMinutes = "break_minutes"
        case dataSource = "data_source"
        case dataDate = "data_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Break Bonus

/// Bonus for sticking to state-minimum break schedule.
public struct BreakBonus: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var policyId: Int64
    public var bonusType: String
    public var bonusAmount: Double
    public var description: String?
    public var isEnabled: Bool
    public var createdAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "break_bonuses"

    enum CodingKeys: String, CodingKey {
        case id
        case policyId = "policy_id"
        case bonusType = "bonus_type"
        case bonusAmount = "bonus_amount"
        case description
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Break Record

/// Individual break/lunch/supply-run record for a user on a given day.
public struct BreakRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var userId: Int64
    public var laborEntryId: Int64?
    public var breakType: String
    public var startedAt: String
    public var endedAt: String?
    public var durationMinutes: Int?
    public var isPaid: Bool
    public var autoFilled: Bool
    public var timerDurationMinutes: Int?
    public var createdAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "break_records"

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case laborEntryId = "labor_entry_id"
        case breakType = "break_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationMinutes = "duration_minutes"
        case isPaid = "is_paid"
        case autoFilled = "auto_filled"
        case timerDurationMinutes = "timer_duration_minutes"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Company Break Settings

/// Company-wide break/lunch timing and rounding settings.
public struct CompanyBreakSettings: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    public var id: Int64?
    public var stateCode: String
    public var roundingMinutes: Int
    public var roundingEnabled: Bool
    public var autoFillBreaks: Bool
    public var defaultMorningBreak: String?
    public var defaultLunch: String?
    public var defaultAfternoonBreak: String?
    public var updatedAt: String?

    public static let databaseTableName = "company_break_settings"

    enum CodingKeys: String, CodingKey {
        case id
        case stateCode = "state_code"
        case roundingMinutes = "rounding_minutes"
        case roundingEnabled = "rounding_enabled"
        case autoFillBreaks = "auto_fill_breaks"
        case defaultMorningBreak = "default_morning_break"
        case defaultLunch = "default_lunch"
        case defaultAfternoonBreak = "default_afternoon_break"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Break Compliance Summary

/// Summary of a user's break compliance for a day.
public struct BreakComplianceSummary: Sendable {
    public let requiredBreaks: Int
    public let takenBreaks: Int
    public let requiredLunchMinutes: Int
    public let takenLunchMinutes: Int
    public let isCompliant: Bool
    public let autoFilled: Bool
    public let bonusEligible: Bool
}
