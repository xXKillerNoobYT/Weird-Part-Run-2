import Foundation
import GRDB

// MARK: - BillRateType

public struct BillRateType: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "bill_rate_types"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var sortOrder: Int
    public var isActive: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Job

public struct Job: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "jobs"
    public var id: Int64?
    public var jobNumber: String
    public var jobName: String
    public var customerName: String?
    public var addressLine1: String?
    public var addressLine2: String?
    public var city: String?
    public var state: String?
    public var zip: String?
    public var gpsLat: Double?
    public var gpsLng: Double?
    public var status: String
    public var priority: String
    public var jobType: String
    public var billRateTypeId: Int64?
    public var billingRate: Double?
    public var estimatedHours: Double?
    public var leadUserId: Int64?
    public var onCallType: String?
    public var warrantyStartDate: String?
    public var warrantyEndDate: String?
    public var startDate: String?
    public var dueDate: String?
    public var completedDate: String?
    public var notes: String?
    public var budgetLimit: Double?
    public var budgetAlertPercent: Double?
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, priority, notes
        case jobNumber = "job_number"
        case jobName = "job_name"
        case customerName = "customer_name"
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case city, state, zip
        case gpsLat = "gps_lat"
        case gpsLng = "gps_lng"
        case jobType = "job_type"
        case billRateTypeId = "bill_rate_type_id"
        case billingRate = "billing_rate"
        case estimatedHours = "estimated_hours"
        case leadUserId = "lead_user_id"
        case onCallType = "on_call_type"
        case warrantyStartDate = "warranty_start_date"
        case warrantyEndDate = "warranty_end_date"
        case startDate = "start_date"
        case dueDate = "due_date"
        case completedDate = "completed_date"
        case budgetLimit = "budget_limit"
        case budgetAlertPercent = "budget_alert_percent"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - JobPart

public struct JobPart: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_parts"
    public var id: Int64?
    public var jobId: Int64
    public var partId: Int64
    public var qtyConsumed: Int
    public var qtyReturned: Int
    public var unitCostAtConsume: Double?
    public var unitSellAtConsume: Double?
    public var consumedBy: Int64?
    public var consumedAt: String?
    public var notes: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case jobId = "job_id"
        case partId = "part_id"
        case qtyConsumed = "qty_consumed"
        case qtyReturned = "qty_returned"
        case unitCostAtConsume = "unit_cost_at_consume"
        case unitSellAtConsume = "unit_sell_at_consume"
        case consumedBy = "consumed_by"
        case consumedAt = "consumed_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - LaborEntry

public struct LaborEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "labor_entries"
    public var id: Int64?
    public var userId: Int64
    public var jobId: Int64
    public var clockIn: String
    public var clockOut: String?
    public var regularHours: Double
    public var overtimeHours: Double
    public var driveTimeMinutes: Int
    public var clockInGpsLat: Double?
    public var clockInGpsLng: Double?
    public var clockOutGpsLat: Double?
    public var clockOutGpsLng: Double?
    public var clockInPhotoPath: String?
    public var clockOutPhotoPath: String?
    public var status: String
    public var editedBy: Int64?
    public var approvedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userId = "user_id"
        case jobId = "job_id"
        case clockIn = "clock_in"
        case clockOut = "clock_out"
        case regularHours = "regular_hours"
        case overtimeHours = "overtime_hours"
        case driveTimeMinutes = "drive_time_minutes"
        case clockInGpsLat = "clock_in_gps_lat"
        case clockInGpsLng = "clock_in_gps_lng"
        case clockOutGpsLat = "clock_out_gps_lat"
        case clockOutGpsLng = "clock_out_gps_lng"
        case clockInPhotoPath = "clock_in_photo_path"
        case clockOutPhotoPath = "clock_out_photo_path"
        case editedBy = "edited_by"
        case approvedBy = "approved_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - OvertimeSettings

public struct OvertimeSettings: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "overtime_settings"
    public var id: Int64?
    public var calculationRule: String
    public var dailyThresholdHours: Double
    public var weeklyThresholdHours: Double?
    public var weekStartWeekday: Int
    public var updatedBy: Int64?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case calculationRule = "calculation_rule"
        case dailyThresholdHours = "daily_threshold_hours"
        case weeklyThresholdHours = "weekly_threshold_hours"
        case weekStartWeekday = "week_start_weekday"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - LaborEntryCorrectionAudit

public struct LaborEntryCorrectionAudit: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "labor_entry_correction_audits"
    public var id: Int64?
    public var laborEntryId: Int64
    public var correctedBy: Int64
    public var reason: String
    public var oldClockIn: String
    public var newClockIn: String
    public var oldClockOut: String?
    public var newClockOut: String?
    public var oldRegularHours: Double
    public var newRegularHours: Double
    public var oldOvertimeHours: Double
    public var newOvertimeHours: Double
    public var oldStatus: String
    public var newStatus: String
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason
        case laborEntryId = "labor_entry_id"
        case correctedBy = "corrected_by"
        case oldClockIn = "old_clock_in"
        case newClockIn = "new_clock_in"
        case oldClockOut = "old_clock_out"
        case newClockOut = "new_clock_out"
        case oldRegularHours = "old_regular_hours"
        case newRegularHours = "new_regular_hours"
        case oldOvertimeHours = "old_overtime_hours"
        case newOvertimeHours = "new_overtime_hours"
        case oldStatus = "old_status"
        case newStatus = "new_status"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ClockOutQuestion

public struct ClockOutQuestion: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "clock_out_questions"
    public var id: Int64?
    public var questionText: String
    public var answerType: String
    public var isRequired: Int
    public var sortOrder: Int
    public var isActive: Int
    public var createdBy: Int64?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case answerType = "answer_type"
        case isRequired = "is_required"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ClockOutAnswer

public struct ClockOutAnswer: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "clock_out_responses"
    public var id: Int64?
    public var laborEntryId: Int64
    public var questionId: Int64
    public var answerText: String?
    public var answerBool: Int?
    public var photoPath: String?
    public var deletedAt: String?
    public var answeredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case laborEntryId = "labor_entry_id"
        case questionId = "question_id"
        case answerText = "answer_text"
        case answerBool = "answer_bool"
        case photoPath = "photo_path"
        case deletedAt = "deleted_at"
        case answeredAt = "answered_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - OneTimeQuestion

public struct OneTimeQuestion: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "one_time_questions"
    public var id: Int64?
    public var jobId: Int64
    public var questionText: String
    public var createdBy: Int64?
    public var status: String
    public var answerText: String?
    public var answeredBy: Int64?
    public var answeredAt: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case jobId = "job_id"
        case questionText = "question_text"
        case createdBy = "created_by"
        case answerText = "answer_text"
        case answeredBy = "answered_by"
        case answeredAt = "answered_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - DailyReport

public struct DailyReport: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "daily_reports"
    public var id: Int64?
    public var jobId: Int64
    public var reportDate: String
    public var reportJson: String
    public var status: String
    public var generatedAt: String?
    public var reviewedBy: Int64?
    public var reviewedAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status
        case jobId = "job_id"
        case reportDate = "report_date"
        case reportJson = "report_json"
        case generatedAt = "generated_at"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - JobTeamMember

public struct JobTeamMember: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_team_members"
    public var id: Int64?
    public var jobId: Int64
    public var userId: Int64
    public var role: String
    public var assignedAt: String?
    public var assignedBy: Int64?
    public var notes: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, notes
        case jobId = "job_id"
        case userId = "user_id"
        case assignedAt = "assigned_at"
        case assignedBy = "assigned_by"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
