import Foundation
import GRDB

// MARK: - BillRateType

public struct BillRateType: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "bill_rate_types"
    public var id: Int64?
    public var name: String
    public var rate: Double
    public var description: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, rate, description
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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
    public var quantityNeeded: Int
    public var quantityUsed: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case jobId = "job_id"
        case partId = "part_id"
        case quantityNeeded = "quantity_needed"
        case quantityUsed = "quantity_used"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
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
    public var status: String
    public var gpsLatIn: Double?
    public var gpsLngIn: Double?
    public var gpsLatOut: Double?
    public var gpsLngOut: Double?
    public var notes: String?
    public var billRateTypeId: Int64?
    public var onCallType: String?
    public var isPerDiem: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case userId = "user_id"
        case jobId = "job_id"
        case clockIn = "clock_in"
        case clockOut = "clock_out"
        case gpsLatIn = "gps_lat_in"
        case gpsLngIn = "gps_lng_in"
        case gpsLatOut = "gps_lat_out"
        case gpsLngOut = "gps_lng_out"
        case billRateTypeId = "bill_rate_type_id"
        case onCallType = "on_call_type"
        case isPerDiem = "is_per_diem"
        case deletedAt = "deleted_at"
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
    public var isActive: Int
    public var sortOrder: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case answerType = "answer_type"
        case isRequired = "is_required"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ClockOutAnswer

public struct ClockOutAnswer: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "clock_out_answers"
    public var id: Int64?
    public var laborEntryId: Int64
    public var questionId: Int64
    public var answerText: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case laborEntryId = "labor_entry_id"
        case questionId = "question_id"
        case answerText = "answer_text"
        case createdAt = "created_at"
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
    public var status: String
    public var reportData: String?
    public var generatedBy: Int64?
    public var generatedAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case jobId = "job_id"
        case reportDate = "report_date"
        case reportData = "report_data"
        case generatedBy = "generated_by"
        case generatedAt = "generated_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
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
    public var joinedAt: String?
    public var notes: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role, notes
        case jobId = "job_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
