import Foundation
import GRDB

// MARK: - DefaultSchedule

public struct DefaultSchedule: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "employee_default_schedules"
    public var id: Int64?
    public var userId: Int64
    public var dayOfWeek: Int
    public var startTime: String?
    public var endTime: String?
    public var lunchStart: String?
    public var lunchEnd: String?
    public var isWorkingDay: Int
    public var notes: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case userId = "user_id"
        case dayOfWeek = "day_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
        case lunchStart = "lunch_start"
        case lunchEnd = "lunch_end"
        case isWorkingDay = "is_working_day"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ShiftTemplate

public struct ShiftTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "shift_templates"
    public var id: Int64?
    public var name: String
    public var hatId: Int64?
    public var workDays: String       // JSON: ["mon","tue","wed","thu","fri"]
    public var startTime: String      // "HH:MM"
    public var endTime: String        // "HH:MM"
    public var breakMinutes: Int
    public var breakPaid: Int         // 0=unpaid, 1=paid
    public var overtimeRule: String   // "company_default" or custom
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case hatId = "hat_id"
        case workDays = "work_days"
        case startTime = "start_time"
        case endTime = "end_time"
        case breakMinutes = "break_minutes"
        case breakPaid = "break_paid"
        case overtimeRule = "overtime_rule"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanyHoliday

public struct CompanyHoliday: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "company_holidays"
    public var id: Int64?
    public var name: String
    public var date: String           // "YYYY-MM-DD"
    public var isPaid: Int            // 1=paid, 0=unpaid
    public var isRecurring: Int       // 1=recurring annually, 0=one-time
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, date
        case isPaid = "is_paid"
        case isRecurring = "is_recurring"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ScheduleException

public struct ScheduleException: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "schedule_exceptions"
    public var id: Int64?
    public var userId: Int64
    public var exceptionDate: String
    public var exceptionType: String
    public var startTime: String?
    public var endTime: String?
    public var lunchStart: String?
    public var lunchEnd: String?
    public var isApproved: Int
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var reason: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason, notes
        case userId = "user_id"
        case exceptionDate = "exception_date"
        case exceptionType = "exception_type"
        case startTime = "start_time"
        case endTime = "end_time"
        case lunchStart = "lunch_start"
        case lunchEnd = "lunch_end"
        case isApproved = "is_approved"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Dispatch

public struct Dispatch: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_dispatch"
    public var id: Int64?
    public var jobId: Int64
    public var userId: Int64
    public var dispatchDate: String
    public var shiftStart: String?
    public var shiftEnd: String?
    public var lunchStart: String?
    public var lunchEnd: String?
    public var roleOnJob: String
    public var status: String
    public var dispatchedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case jobId = "job_id"
        case userId = "user_id"
        case dispatchDate = "dispatch_date"
        case shiftStart = "shift_start"
        case shiftEnd = "shift_end"
        case lunchStart = "lunch_start"
        case lunchEnd = "lunch_end"
        case roleOnJob = "role_on_job"
        case dispatchedBy = "dispatched_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - SubcontractorSchedule

public struct SubcontractorSchedule: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "subcontractor_schedules"
    public var id: Int64?
    public var jobId: Int64
    public var gcId: Int64
    public var scheduledDate: String
    public var arrivalTime: String?
    public var departureTime: String?
    public var scopeOfWork: String?
    public var status: String
    public var notes: String?
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case jobId = "job_id"
        case gcId = "gc_id"
        case scheduledDate = "scheduled_date"
        case arrivalTime = "arrival_time"
        case departureTime = "departure_time"
        case scopeOfWork = "scope_of_work"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - DispatchTemplate

public struct DispatchTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "dispatch_templates"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - DispatchTemplateMember

public struct DispatchTemplateMember: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "dispatch_template_members"
    public var id: Int64?
    public var templateId: Int64
    public var userId: Int64
    public var role: String
    public var sortOrder: Int
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case templateId = "template_id"
        case userId = "user_id"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ShiftPattern

public struct ShiftPattern: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "shift_patterns"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var rotationDays: Int
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case rotationDays = "rotation_days"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ShiftPatternDay

public struct ShiftPatternDay: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "shift_pattern_days"
    public var id: Int64?
    public var patternId: Int64
    public var dayOffset: Int
    public var startTime: String?
    public var endTime: String?
    public var isOff: Int
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case patternId = "pattern_id"
        case dayOffset = "day_offset"
        case startTime = "start_time"
        case endTime = "end_time"
        case isOff = "is_off"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - FlexPoolJob

/// A job available for workers to self-assign from the flex pool.
/// Returned by `SchedulingService.fetchFlexPool(userId:)`.
public struct FlexPoolJob: Identifiable, Sendable {
    public let id: Int64
    public let jobName: String
    public let jobNumber: String
    public let address: String?
    public let description: String?
    public let estimatedHours: Double?
    /// True when the company setting `flex_pool_requires_approval` is enabled.
    /// Claiming shows "Pending Approval" instead of immediately assigning.
    public let isApprovalRequired: Bool

    public init(
        id: Int64,
        jobName: String,
        jobNumber: String,
        address: String?,
        description: String?,
        estimatedHours: Double?,
        isApprovalRequired: Bool
    ) {
        self.id = id
        self.jobName = jobName
        self.jobNumber = jobNumber
        self.address = address
        self.description = description
        self.estimatedHours = estimatedHours
        self.isApprovalRequired = isApprovalRequired
    }
}
