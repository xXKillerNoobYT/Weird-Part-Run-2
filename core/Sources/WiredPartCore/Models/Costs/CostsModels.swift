import Foundation
import GRDB

// MARK: - BillingPeriod

public struct BillingPeriod: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "billing_periods"
    public var id: Int64?
    public var periodType: String
    public var startDate: String
    public var endDate: String
    public var status: String
    public var lockedBy: Int64?
    public var lockedAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case periodType = "period_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case lockedBy = "locked_by"
        case lockedAt = "locked_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReceivingSession

public struct ReceivingSession: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "receiving_sessions"
    public var id: Int64?
    public var poId: Int64?
    public var mode: String
    public var status: String
    public var startedBy: Int64
    public var startedAt: String?
    public var completedAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, mode, status, notes
        case poId = "po_id"
        case startedBy = "started_by"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReceivingSessionItem

public struct ReceivingSessionItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "receiving_session_items"
    public var id: Int64?
    public var sessionId: Int64
    public var poLineId: Int64?
    public var partId: Int64?
    public var expectedQty: Int
    public var receivedQty: Int
    public var conditionStatus: String
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case sessionId = "session_id"
        case poLineId = "po_line_id"
        case partId = "part_id"
        case expectedQty = "expected_qty"
        case receivedQty = "received_qty"
        case conditionStatus = "condition_status"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReportAnnotation

public struct ReportAnnotation: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "report_annotations"
    public var id: Int64?
    public var reportType: String
    public var reportId: Int64
    public var userId: Int64
    public var content: String
    public var annotationType: String
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case reportType = "report_type"
        case reportId = "report_id"
        case userId = "user_id"
        case annotationType = "annotation_type"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReportShareToken

public struct ReportShareToken: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "report_share_tokens"
    public var id: Int64?
    public var reportType: String
    public var reportId: Int64
    public var token: String
    public var createdBy: Int64
    public var expiresAt: String?
    public var isActive: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, token
        case reportType = "report_type"
        case reportId = "report_id"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReportTemplate

public struct ReportTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "report_templates"
    public var id: Int64?
    public var name: String
    public var reportType: String
    public var config: String?
    public var isDefault: Int
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, config
        case reportType = "report_type"
        case isDefault = "is_default"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PTOPolicy

public struct PTOPolicy: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "pto_policies"
    public var id: Int64?
    public var name: String
    public var accrualRate: Double
    public var maxBalance: Double?
    public var carryOverLimit: Double?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case accrualRate = "accrual_rate"
        case maxBalance = "max_balance"
        case carryOverLimit = "carry_over_limit"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PTOBalance

public struct PTOBalance: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "pto_balances"
    public var id: Int64?
    public var userId: Int64
    public var policyId: Int64
    public var balance: Double
    public var used: Double
    public var year: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, balance, used, year
        case userId = "user_id"
        case policyId = "policy_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - SupplierPortalToken

public struct SupplierPortalToken: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "supplier_portal_tokens"
    public var id: Int64?
    public var supplierId: Int64
    public var token: String
    public var label: String?
    public var permissions: String
    public var expiresAt: String?
    public var isActive: Int
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, token, label, permissions
        case supplierId = "supplier_id"
        case expiresAt = "expires_at"
        case isActive = "is_active"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CostLayer

public struct CostLayer: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "cost_layers"
    public var id: Int64?
    public var partId: Int64
    public var poLineId: Int64?
    public var quantity: Int
    public var unitCost: Double
    public var remainingQty: Int
    public var receivedAt: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case partId = "part_id"
        case poLineId = "po_line_id"
        case unitCost = "unit_cost"
        case remainingQty = "remaining_qty"
        case receivedAt = "received_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanyCostSetting

public struct CompanyCostSetting: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "company_cost_settings"
    public var id: Int64?
    public var settingKey: String
    public var settingValue: String
    public var description: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description
        case settingKey = "setting_key"
        case settingValue = "setting_value"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanyProfile

public struct CompanyProfile: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "company_profiles"
    public var id: Int64?
    public var companyName: String
    public var addressStreet: String?
    public var addressCity: String?
    public var addressState: String?
    public var addressZip: String?
    public var phone: String?
    public var email: String?
    public var website: String?
    public var contractorLicense: String?
    public var insuranceInfo: String?
    public var taxId: String?
    public var isPrimary: Int
    public var branchName: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, phone, email, website, notes
        case companyName = "company_name"
        case addressStreet = "address_street"
        case addressCity = "address_city"
        case addressState = "address_state"
        case addressZip = "address_zip"
        case contractorLicense = "contractor_license"
        case insuranceInfo = "insurance_info"
        case taxId = "tax_id"
        case isPrimary = "is_primary"
        case branchName = "branch_name"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotificationPreference

public struct NotificationPreference: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "notification_preferences"
    public var id: Int64?
    public var userId: Int64
    public var notificationType: String
    public var enabled: Int
    public var sound: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, enabled, sound
        case userId = "user_id"
        case notificationType = "notification_type"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - SupplierContactRating

public struct SupplierContactRating: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "supplier_contact_ratings"
    public var id: Int64?
    public var supplierId: Int64
    public var contactType: String
    public var raterId: Int64
    public var category: String
    public var rating: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category, rating, notes
        case supplierId = "supplier_id"
        case contactType = "contact_type"
        case raterId = "rater_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - POConversation

public struct POConversation: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "po_conversations"
    public var id: Int64?
    public var poId: Int64
    public var entryType: String
    public var authorId: Int64
    public var content: String
    public var isInternal: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case poId = "po_id"
        case entryType = "entry_type"
        case authorId = "author_id"
        case isInternal = "is_internal"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - POGroup

public struct POGroup: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "po_groups"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var createdBy: Int64
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - POGroupMember

public struct POGroupMember: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "po_group_members"
    public var id: Int64?
    public var groupId: Int64
    public var poId: Int64
    public var addedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId = "group_id"
        case poId = "po_id"
        case addedAt = "added_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - JobPreference

public struct JobPreference: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_preferences"
    public var id: Int64?
    public var jobId: Int64
    public var preferenceType: String
    public var preferenceValue: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case jobId = "job_id"
        case preferenceType = "preference_type"
        case preferenceValue = "preference_value"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CategorySupplierPreference

public struct CategorySupplierPreference: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "category_supplier_preferences"
    public var id: Int64?
    public var categoryId: Int64
    public var supplierId: Int64
    public var priority: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, priority, notes
        case categoryId = "category_id"
        case supplierId = "supplier_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - JobSupplierPreference

public struct JobSupplierPreference: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_supplier_preferences"
    public var id: Int64?
    public var jobId: Int64
    public var supplierId: Int64
    public var isExcluded: Int
    public var priority: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, priority, notes
        case jobId = "job_id"
        case supplierId = "supplier_id"
        case isExcluded = "is_excluded"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
