import Foundation
import GRDB

// =============================================================================
// CostsModels.swift — Usage Audit (2026-03-24)
//
// Struct usage categories:
//   ACTIVE   — Struct type used directly in service methods or UI pages
//   TABLE    — Table referenced via raw SQL in services, but struct type not
//              used for GRDB record operations (potential future upgrade to
//              type-safe queries)
//   SCHEMA   — Migration/sync schema reference only. Retained because these map
//              to real DB tables and may be needed for future GRDB record-based
//              queries or sync conflict resolution. Do NOT remove.
//
// No structs were removed. All map to active migration tables and are retained
// per project policy on migration-related types.
// =============================================================================

// MARK: - BillingPeriod
// Usage: TABLE — ReportsService.getReportsStats() (raw SQL COUNT on billing_periods)

public struct BillingPeriod: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "billing_periods"
    public var id: Int64?
    public var jobId: Int64
    public var periodStart: String
    public var periodEnd: String
    public var lockedAt: String?
    public var lockedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case jobId = "job_id"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case lockedAt = "locked_at"
        case lockedBy = "locked_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PricingTier
// Used by: PartsService.getSellPrice(), PartsService.savePricingTier(),
//          PartsService.previewPricingTier(), PartsService.batchApplyPricingTier(),
//          PartsService.getPricingTiers()

public struct PricingTier: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "pricing_tiers"
    public var id: Int64?
    public var categoryId: Int64?
    public var styleId: Int64?
    public var typeId: Int64?
    public var brandId: Int64?
    public var partId: Int64?
    public var markupPercent: Double?
    public var marginPercent: Double?
    public var fixedSellPrice: Double?
    public var setBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case categoryId = "category_id"
        case styleId = "style_id"
        case typeId = "type_id"
        case brandId = "brand_id"
        case partId = "part_id"
        case markupPercent = "markup_percent"
        case marginPercent = "margin_percent"
        case fixedSellPrice = "fixed_sell_price"
        case setBy = "set_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Human-readable tier level name
    public var tierLevel: String {
        if partId != nil { return "Part" }
        if brandId != nil { return "Brand" }
        if typeId != nil { return "Type" }
        if styleId != nil { return "Style" }
        if categoryId != nil { return "Category" }
        return "Unknown"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PriceHistory
// Used by: PartsService.recordPriceChange(), PartsService.getPriceHistory(),
//          PartsPricingPage (UI state)

public struct PriceHistory: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "price_history"
    public var id: Int64?
    public var partId: Int64?
    public var pricingTierId: Int64?
    public var changeType: String
    public var oldValue: Double?
    public var newValue: Double?
    public var oldSellPrice: Double?
    public var newSellPrice: Double?
    public var source: String?
    public var sourceId: Int64?
    public var changedBy: Int64?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case pricingTierId = "pricing_tier_id"
        case changeType = "change_type"
        case oldValue = "old_value"
        case newValue = "new_value"
        case oldSellPrice = "old_sell_price"
        case newSellPrice = "new_sell_price"
        case source
        case sourceId = "source_id"
        case changedBy = "changed_by"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CostLayerConsumption
// Used by: PartsService.consumeCostLayers(), PartsService.reverseCostLayerConsumptions(),
//          PartsService.getConsumptionHistory()

public struct CostLayerConsumption: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "cost_layer_consumptions"
    public var id: Int64?
    public var costLayerId: Int64
    public var partId: Int64
    public var jobId: Int64?
    public var qtyConsumed: Int
    public var unitCostAtSale: Double
    public var sellPriceCharged: Double?
    public var supplierId: Int64?
    public var isReturned: Int
    public var returnedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case costLayerId = "cost_layer_id"
        case partId = "part_id"
        case jobId = "job_id"
        case qtyConsumed = "qty_consumed"
        case unitCostAtSale = "unit_cost_at_sale"
        case sellPriceCharged = "sell_price_charged"
        case supplierId = "supplier_id"
        case isReturned = "is_returned"
        case returnedAt = "returned_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReceivingSession
// Usage: TABLE — WarehouseService (raw SQL INSERT/SELECT/UPDATE on receiving_sessions),
//        DashboardService.getWarehouseDashboardKPIs(), PartsService procurement queries

public struct ReceivingSession: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "receiving_sessions"
    public var id: Int64?
    public var poId: Int64?
    public var startedBy: Int64
    public var mode: String
    public var status: String
    public var completedAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, mode, status, notes
        case poId = "po_id"
        case startedBy = "started_by"
        case completedAt = "completed_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReceivingSessionItem
// Usage: TABLE — WarehouseService (raw SQL INSERT/SELECT/UPDATE on receiving_session_items)

public struct ReceivingSessionItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "receiving_session_items"
    public var id: Int64?
    public var sessionId: Int64
    public var poLineId: Int64?
    public var expectedQty: Int
    public var receivedQty: Int
    public var actualCost: Double?
    public var scannedAt: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case sessionId = "session_id"
        case poLineId = "po_line_id"
        case expectedQty = "expected_qty"
        case receivedQty = "received_qty"
        case actualCost = "actual_cost"
        case scannedAt = "scanned_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReportAnnotation
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

public struct ReportAnnotation: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "report_annotations"
    public var id: Int64?
    public var reportType: String
    public var contextKey: String
    public var content: String
    public var authorId: Int64
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content
        case reportType = "report_type"
        case contextKey = "context_key"
        case authorId = "author_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReportShareToken
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

public struct ReportShareToken: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "report_share_tokens"
    public var id: Int64?
    public var token: String
    public var reportType: String
    public var contextParams: String?
    public var label: String?
    public var createdBy: Int64
    public var expiresAt: String?
    public var lastAccessedAt: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, token, label
        case reportType = "report_type"
        case contextParams = "context_params"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
        case lastAccessedAt = "last_accessed_at"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReportTemplate
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

public struct ReportTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "report_templates"
    public var id: Int64?
    public var name: String
    public var reportType: String
    public var configJson: String?
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case reportType = "report_type"
        case configJson = "config_json"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PTOPolicy
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

public struct PTOPolicy: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "pto_policies"
    public var id: Int64?
    public var userId: Int64
    public var policyName: String
    public var accrualRate: Double
    public var accrualPeriod: String?
    public var maxBalance: Double?
    public var carryoverLimit: Double?
    public var startDate: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case policyName = "policy_name"
        case accrualRate = "accrual_rate"
        case accrualPeriod = "accrual_period"
        case maxBalance = "max_balance"
        case carryoverLimit = "carryover_limit"
        case startDate = "start_date"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PTOBalance
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

public struct SupplierPortalToken: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "supplier_portal_tokens"
    public var id: Int64?
    public var supplierId: Int64
    public var token: String
    public var note: String?
    public var isActive: Int
    public var expiresAt: String?
    public var lastUsedAt: String?
    public var createdBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, token, note
        case supplierId = "supplier_id"
        case isActive = "is_active"
        case expiresAt = "expires_at"
        case lastUsedAt = "last_used_at"
        case createdBy = "created_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CostLayer
// Used by: PartsService.addCostLayer(), PartsService.consumeCostLayers(),
//          PartsService.reverseCostLayerConsumptions(), PartsService.getCostLayers(),
//          PartsPricingPage (UI state)

public struct CostLayer: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "cost_layers"
    public var id: Int64?
    public var partId: Int64
    public var purchaseDate: String?
    public var poLineId: Int64?
    public var originalQty: Int
    public var remainingQty: Int
    public var unitCost: Double
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case purchaseDate = "purchase_date"
        case poLineId = "po_line_id"
        case originalQty = "original_qty"
        case remainingQty = "remaining_qty"
        case unitCost = "unit_cost"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanyCostSetting
// Usage: TABLE — PartsService.getCompanyCostSetting(), PartsService.updateCompanyCostSetting()
//        (raw SQL on company_cost_settings), PricingSettingsSheet, PricingOverrideFlow,
//        PricingBulkEditSheet, PartsCatalogPage, PartsPricingPage

public struct CompanyCostSetting: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "company_cost_settings"
    public var id: Int64?
    public var settingKey: String
    public var settingValue: String
    public var updatedBy: Int64?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case settingKey = "setting_key"
        case settingValue = "setting_value"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanyProfile
// Used by: SettingsService.listCompanyProfiles(), SettingsService.getCompanyProfile(),
//          SettingsService.createCompanyProfile(), SettingsService.updateCompanyProfile(),
//          CompanyProfilesPage (UI state + CRUD)

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
    public var logoPath: String?
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
        case companyName = "name"
        case addressStreet = "address_street"
        case addressCity = "address_city"
        case addressState = "address_state"
        case addressZip = "address_zip"
        case logoPath = "logo_path"
        case contractorLicense = "contractor_license"
        case insuranceInfo = "insurance_info"
        case taxId = "tax_id"
        case isPrimary = "is_primary"
        case branchName = "branch_name"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(id: Int64? = nil, companyName: String, addressStreet: String? = nil, addressCity: String? = nil, addressState: String? = nil, addressZip: String? = nil, phone: String? = nil, email: String? = nil, website: String? = nil, logoPath: String? = nil, contractorLicense: String? = nil, insuranceInfo: String? = nil, taxId: String? = nil, isPrimary: Int = 0, branchName: String? = nil, notes: String? = nil, deletedAt: String? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id; self.companyName = companyName; self.addressStreet = addressStreet
        self.addressCity = addressCity; self.addressState = addressState; self.addressZip = addressZip
        self.phone = phone; self.email = email; self.website = website; self.logoPath = logoPath
        self.contractorLicense = contractorLicense; self.insuranceInfo = insuranceInfo; self.taxId = taxId
        self.isPrimary = isPrimary; self.branchName = branchName; self.notes = notes
        self.deletedAt = deletedAt; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - NotificationPreference
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
        case id, sound
        case enabled = "is_enabled"
        case userId = "user_id"
        case notificationType = "notification_type"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - SupplierContactRating
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

public struct JobPreference: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_preferences"
    public var id: Int64?
    public var jobId: Int64
    public var preferenceType: String
    public var entityId: Int64?
    public var textValue: String?
    public var category: String?
    public var isActive: Int
    public var autoLearned: Int
    public var confidenceScore: Double?
    public var lastUsedAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, category
        case jobId = "job_id"
        case preferenceType = "preference_type"
        case entityId = "entity_id"
        case textValue = "text_value"
        case isActive = "is_active"
        case autoLearned = "auto_learned"
        case confidenceScore = "confidence_score"
        case lastUsedAt = "last_used_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CategorySupplierPreference
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
// Usage: SCHEMA — Migration + ConflictResolver only. No service or page references the struct type.

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
