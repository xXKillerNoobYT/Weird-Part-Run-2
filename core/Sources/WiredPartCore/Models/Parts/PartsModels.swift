import Foundation
import GRDB

// MARK: - PartCategory

public struct PartCategory: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "part_categories"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var sortOrder: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - LocationStockTarget

/// Per-location stock level targets and forecast data.
/// Overrides the part's global min/target/max for a specific location.
public struct LocationStockTarget: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "location_stock_targets"

    public var id: Int64?
    public var partId: Int64
    public var locationType: String       // "warehouse", "truck", "trailer"
    public var locationId: Int64
    public var minStock: Int
    public var targetStock: Int
    public var maxStock: Int
    public var forecastAdu30: Double?
    public var forecastAdu90: Double?
    public var forecastDaysUntilLow: Int?
    public var forecastSuggestedOrder: Int?
    public var forecastLastRun: String?
    public var certaintyRating: Double?
    public var partCategory: String?       // "common" or "critical" per part per location
    public var doNotRestock: Int?           // 1 = deplete naturally then remove
    public var deletedAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case locationType = "location_type"
        case locationId = "location_id"
        case minStock = "min_stock"
        case targetStock = "target_stock"
        case maxStock = "max_stock"
        case forecastAdu30 = "forecast_adu_30"
        case forecastAdu90 = "forecast_adu_90"
        case forecastDaysUntilLow = "forecast_days_until_low"
        case forecastSuggestedOrder = "forecast_suggested_order"
        case forecastLastRun = "forecast_last_run"
        case certaintyRating = "certainty_rating"
        case partCategory = "part_category"
        case doNotRestock = "do_not_restock"
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PartStyle

public struct PartStyle: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "part_styles"
    public var id: Int64?
    public var categoryId: Int64
    public var name: String
    public var description: String?
    public var sortOrder: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case categoryId = "category_id"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PartType

public struct PartType: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "part_types"
    public var id: Int64?
    public var styleId: Int64
    public var name: String
    public var description: String?
    public var sortOrder: Int
    public var defaultUnitCost: Double?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case styleId = "style_id"
        case sortOrder = "sort_order"
        case defaultUnitCost = "default_unit_cost"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PartColor

public struct PartColor: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "part_colors"
    public var id: Int64?
    public var name: String
    public var hexCode: String?
    public var partNumber: String?
    public var unitCost: Double?
    public var sortOrder: Int
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?

    public init(id: Int64? = nil, name: String = "", hexCode: String? = nil, partNumber: String? = nil, unitCost: Double? = nil, sortOrder: Int = 0, isActive: Int = 1, deletedAt: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.name = name
        self.hexCode = hexCode
        self.partNumber = partNumber
        self.unitCost = unitCost
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.deletedAt = deletedAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case hexCode = "hex_code"
        case partNumber = "part_number"
        case unitCost = "unit_cost"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ColorSupplierCost

public struct ColorSupplierCost: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "color_supplier_costs"
    public var id: Int64?
    public var colorId: Int64
    public var supplierId: Int64
    public var cost: Double
    public var notes: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, cost, notes
        case colorId = "color_id"
        case supplierId = "supplier_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TypeColorLink

public struct TypeColorLink: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "type_color_links"
    public var id: Int64?
    public var typeId: Int64
    public var colorId: Int64
    public var imageUrl: String?
    public var sortOrder: Int?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case typeId = "type_id"
        case colorId = "color_id"
        case imageUrl = "image_url"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Brand

public struct Brand: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "brands"
    public var id: Int64?
    public var name: String
    public var website: String?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, website, notes
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TypeBrandLink

public struct TypeBrandLink: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "type_brand_links"
    public var id: Int64?
    public var typeId: Int64
    public var brandId: Int64
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case typeId = "type_id"
        case brandId = "brand_id"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Supplier

public struct Supplier: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "suppliers"
    public var id: Int64?
    public var name: String
    public var contactName: String?
    public var email: String?
    public var phone: String?
    public var address: String?
    public var website: String?
    public var repName: String?
    public var repEmail: String?
    public var repPhone: String?
    public var notes: String?
    public var deliveryMethod: String?
    public var deliveryDays: String?
    public var specialOrderLeadDays: Int?
    public var deliveryNotes: String?
    public var driverName: String?
    public var driverPhone: String?
    public var driverEmail: String?
    public var onTimeRate: Double?
    public var qualityScore: Double?
    public var avgLeadDays: Int?
    public var reliabilityScore: Double?
    public var communicationScore: Double?
    public var accountNumber: String?
    public var isActive: Int?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, address, website, notes
        case accountNumber = "account_number"
        case contactName = "contact_name"
        case repName = "rep_name"
        case repEmail = "rep_email"
        case repPhone = "rep_phone"
        case deliveryMethod = "delivery_method"
        case deliveryDays = "delivery_days"
        case specialOrderLeadDays = "special_order_lead_days"
        case deliveryNotes = "delivery_notes"
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
        case driverEmail = "driver_email"
        case onTimeRate = "on_time_rate"
        case qualityScore = "quality_score"
        case avgLeadDays = "avg_lead_days"
        case reliabilityScore = "reliability_score"
        case communicationScore = "communication_score"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - BrandSupplierLink

public struct BrandSupplierLink: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "brand_supplier_links"
    public var id: Int64?
    public var brandId: Int64
    public var supplierId: Int64
    public var accountNumber: String?
    public var notes: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var carryStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case brandId = "brand_id"
        case supplierId = "supplier_id"
        case accountNumber = "account_number"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case carryStatus = "carry_status"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Part

public struct Part: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "parts"
    public var id: Int64?
    public var categoryId: Int64
    public var styleId: Int64?
    public var typeId: Int64?
    public var colorId: Int64?
    public var partType: String
    public var code: String?
    public var name: String
    public var description: String?
    public var brandId: Int64?
    public var manufacturerPartNumber: String?
    public var unitOfMeasure: String?
    public var weightLbs: Double?
    public var companyCostPrice: Double
    public var companyMarkupPercent: Double
    public var minStockLevel: Int?
    public var maxStockLevel: Int?
    public var targetStockLevel: Int?
    public var reorderPoint: Int?
    public var forecastLastRun: String?
    public var forecastAdu30: Double?
    public var forecastAdu90: Double?
    public var forecastReorderPoint: Int?
    public var forecastTargetQty: Int?
    public var forecastSuggestedOrder: Int?
    public var forecastDaysUntilLow: Int?
    public var isDeprecated: Int?
    public var deprecationReason: String?
    public var isQrTagged: Int?
    public var notes: String?
    public var imageUrl: String?
    public var pdfUrl: String?
    public var shelfLocation: String?
    public var binLocation: String?
    public var isActive: Int?
    public var weightedAvgCost: Double?
    public var customMarginPercent: Double?
    public var costLastUpdated: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, code, name, description, notes
        case categoryId = "category_id"
        case styleId = "style_id"
        case typeId = "type_id"
        case colorId = "color_id"
        case partType = "part_type"
        case brandId = "brand_id"
        case manufacturerPartNumber = "manufacturer_part_number"
        case unitOfMeasure = "unit_of_measure"
        case weightLbs = "weight_lbs"
        case companyCostPrice = "company_cost_price"
        case companyMarkupPercent = "company_markup_percent"
        case minStockLevel = "min_stock_level"
        case maxStockLevel = "max_stock_level"
        case targetStockLevel = "target_stock_level"
        case reorderPoint = "reorder_point"
        case forecastLastRun = "forecast_last_run"
        case forecastAdu30 = "forecast_adu_30"
        case forecastAdu90 = "forecast_adu_90"
        case forecastReorderPoint = "forecast_reorder_point"
        case forecastTargetQty = "forecast_target_qty"
        case forecastSuggestedOrder = "forecast_suggested_order"
        case forecastDaysUntilLow = "forecast_days_until_low"
        case isDeprecated = "is_deprecated"
        case deprecationReason = "deprecation_reason"
        case isQrTagged = "is_qr_tagged"
        case imageUrl = "image_url"
        case pdfUrl = "pdf_url"
        case shelfLocation = "shelf_location"
        case binLocation = "bin_location"
        case isActive = "is_active"
        case weightedAvgCost = "weighted_avg_cost"
        case customMarginPercent = "custom_margin_percent"
        case costLastUpdated = "cost_last_updated"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PartSupplierLink

public struct PartSupplierLink: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "part_supplier_links"
    public var id: Int64?
    public var partId: Int64
    public var supplierId: Int64
    public var supplierPartNumber: String?
    public var supplierCostPrice: Double?
    public var moq: Int?
    public var discountBrackets: String?
    public var lastPriceDate: String?
    public var isPreferred: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case supplierId = "supplier_id"
        case supplierPartNumber = "supplier_part_number"
        case supplierCostPrice = "supplier_cost_price"
        case moq
        case discountBrackets = "discount_brackets"
        case lastPriceDate = "last_price_date"
        case isPreferred = "is_preferred"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Stock (primary stock table — fixes #200)

/// Model for the primary `stock` table (migration 002).
/// Tracks current quantity of each part at each location.
public struct Stock: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "stock"
    public var id: Int64?
    public var partId: Int64
    public var locationType: String
    public var locationId: Int64
    public var qty: Int
    public var supplierId: Int64?
    public var lastCounted: String?
    public var deletedAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, qty
        case partId = "part_id"
        case locationType = "location_type"
        case locationId = "location_id"
        case supplierId = "supplier_id"
        case lastCounted = "last_counted"
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - StockEntry

public struct StockEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "stock_entries"
    public var id: Int64?
    public var partId: Int64
    public var warehouseId: Int64
    public var quantity: Int
    public var binLocation: String?
    public var lastCountedAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case partId = "part_id"
        case warehouseId = "warehouse_id"
        case binLocation = "bin_location"
        case lastCountedAt = "last_counted_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionRule

public struct CompanionRule: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_rules"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var styleMatch: String?
    public var qtyMode: String?
    public var qtyRatio: Double?
    public var isActive: Int
    public var tryMatchBrand: Int
    public var autoColorMatch: Int
    public var parentRuleId: Int64?
    public var autoDeleteAt: String?
    public var deletedAt: String?
    public var createdBy: Int64?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case styleMatch = "style_match"
        case qtyMode = "qty_mode"
        case qtyRatio = "qty_ratio"
        case isActive = "is_active"
        case tryMatchBrand = "try_match_brand"
        case autoColorMatch = "auto_color_match"
        case parentRuleId = "parent_rule_id"
        case autoDeleteAt = "auto_delete_at"
        case deletedAt = "deleted_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PartAlternative

public struct PartAlternative: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "part_alternatives"
    public var id: Int64?
    public var partId: Int64
    public var alternativePartId: Int64
    public var relationship: String
    public var preference: Int
    public var notes: String?
    public var createdBy: Int64?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, relationship, preference, notes
        case partId = "part_id"
        case alternativePartId = "alternative_part_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionPoll

public struct CompanionPoll: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_polls"
    public var id: Int64?
    public var coOccurrenceId: Int64
    public var proposedRuleName: String
    public var proposedRuleDescription: String?
    public var sourceCategoryId: Int64?
    public var sourceStyleId: Int64?
    public var sourceTypeId: Int64?
    public var targetCategoryId: Int64?
    public var targetStyleId: Int64?
    public var targetTypeId: Int64?
    public var matchLevel: String
    public var tryMatchBrand: Int
    public var autoColorMatch: Int
    public var status: String
    public var adminLockedResult: String?
    public var adminLockedBy: Int64?
    public var adminLockedAt: String?
    public var result: String?
    public var createdRuleId: Int64?
    public var startDate: String
    public var endDate: String
    public var completedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, result
        case coOccurrenceId = "co_occurrence_id"
        case proposedRuleName = "proposed_rule_name"
        case proposedRuleDescription = "proposed_rule_description"
        case sourceCategoryId = "source_category_id"
        case sourceStyleId = "source_style_id"
        case sourceTypeId = "source_type_id"
        case targetCategoryId = "target_category_id"
        case targetStyleId = "target_style_id"
        case targetTypeId = "target_type_id"
        case matchLevel = "match_level"
        case tryMatchBrand = "try_match_brand"
        case autoColorMatch = "auto_color_match"
        case adminLockedResult = "admin_locked_result"
        case adminLockedBy = "admin_locked_by"
        case adminLockedAt = "admin_locked_at"
        case createdRuleId = "created_rule_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionVote

public struct CompanionVote: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_votes"
    public var id: Int64?
    public var pollId: Int64
    public var userId: Int64
    public var vote: String
    public var hasPower: Int
    public var votedAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, vote
        case pollId = "poll_id"
        case userId = "user_id"
        case hasPower = "has_power"
        case votedAt = "voted_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionPollResult

public struct CompanionPollResult: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_poll_results"
    public var id: Int64?
    public var pollId: Int64
    public var passed: Int
    public var totalVotes: Int
    public var poweredAccept: Int
    public var poweredReject: Int
    public var allAccept: Int
    public var allReject: Int
    public var wasAdminLocked: Int
    public var finalizedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, passed
        case pollId = "poll_id"
        case totalVotes = "total_votes"
        case poweredAccept = "powered_accept"
        case poweredReject = "powered_reject"
        case allAccept = "all_accept"
        case allReject = "all_reject"
        case wasAdminLocked = "was_admin_locked"
        case finalizedAt = "finalized_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionAutoDiscoveryLog

public struct CompanionAutoDiscoveryLog: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_auto_discovery_log"
    public var id: Int64?
    public var analysisDate: String
    public var matchLevel: String
    public var dataWindowMonths: Int
    public var pairsAnalyzed: Int
    public var newPairsFound: Int
    public var pollCreatedId: Int64?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case analysisDate = "analysis_date"
        case matchLevel = "match_level"
        case dataWindowMonths = "data_window_months"
        case pairsAnalyzed = "pairs_analyzed"
        case newPairsFound = "new_pairs_found"
        case pollCreatedId = "poll_created_id"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ForecastSettings

/// Per-location-type (or per-individual-location) forecast calculation settings.
/// Shop uses ADU (parts/day). Trucks use APW (parts/X-weeks).
public struct ForecastSettings: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "forecast_settings"

    public var id: Int64?
    public var locationType: String
    public var locationId: Int64?
    public var usageUnit: String
    public var aduLookbackDays: Int
    public var windowWeeks: Int
    public var minDataDays: Int
    public var commonMinMultiplier: Double
    public var commonTargetMultiplier: Double
    public var commonMaxMultiplier: Double
    public var criticalMinMultiplier: Double
    public var criticalTargetMultiplier: Double
    public var criticalMaxMultiplier: Double
    public var freeSpaceSuppressThreshold: Int
    public var updatedAt: String?

    public init(
        id: Int64? = nil, locationType: String, locationId: Int64? = nil,
        usageUnit: String, aduLookbackDays: Int, windowWeeks: Int, minDataDays: Int,
        commonMinMultiplier: Double, commonTargetMultiplier: Double, commonMaxMultiplier: Double,
        criticalMinMultiplier: Double, criticalTargetMultiplier: Double, criticalMaxMultiplier: Double,
        freeSpaceSuppressThreshold: Int, updatedAt: String? = nil
    ) {
        self.id = id; self.locationType = locationType; self.locationId = locationId
        self.usageUnit = usageUnit; self.aduLookbackDays = aduLookbackDays
        self.windowWeeks = windowWeeks; self.minDataDays = minDataDays
        self.commonMinMultiplier = commonMinMultiplier
        self.commonTargetMultiplier = commonTargetMultiplier
        self.commonMaxMultiplier = commonMaxMultiplier
        self.criticalMinMultiplier = criticalMinMultiplier
        self.criticalTargetMultiplier = criticalTargetMultiplier
        self.criticalMaxMultiplier = criticalMaxMultiplier
        self.freeSpaceSuppressThreshold = freeSpaceSuppressThreshold
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case locationType = "location_type"
        case locationId = "location_id"
        case usageUnit = "usage_unit"
        case aduLookbackDays = "adu_lookback_days"
        case windowWeeks = "window_weeks"
        case minDataDays = "min_data_days"
        case commonMinMultiplier = "common_min_multiplier"
        case commonTargetMultiplier = "common_target_multiplier"
        case commonMaxMultiplier = "common_max_multiplier"
        case criticalMinMultiplier = "critical_min_multiplier"
        case criticalTargetMultiplier = "critical_target_multiplier"
        case criticalMaxMultiplier = "critical_max_multiplier"
        case freeSpaceSuppressThreshold = "free_space_suppress_threshold"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - LocationFreeSpace

/// Physical free space rating for a location (1=nearly full, 10=lots of room).
/// Updated monthly by notification prompt.
public struct LocationFreeSpace: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "location_free_space"

    public var id: Int64?
    public var locationType: String
    public var locationId: Int64
    public var freeSpaceRating: Int
    public var updatedBy: Int64?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case locationType = "location_type"
        case locationId = "location_id"
        case freeSpaceRating = "free_space_rating"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - TargetRecommendation

/// A system-generated recommendation to change stock levels at a location.
public struct TargetRecommendation: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "target_recommendations"

    public var id: Int64?
    public var partId: Int64
    public var locationType: String
    public var locationId: Int64
    public var recommendationType: String   // adjust, add, remove, category_change
    public var currentMin: Int?
    public var currentTarget: Int?
    public var currentMax: Int?
    public var recommendedMin: Int?
    public var recommendedTarget: Int?
    public var recommendedMax: Int?
    public var currentCategory: String?
    public var recommendedCategory: String?
    public var usageValue: Double
    public var usageUnit: String
    public var dataDays: Int
    public var impactScore: Double
    public var reason: String?
    public var status: String
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var dismissedBy: Int64?
    public var dismissedReason: String?
    public var cooldownUntil: String?
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case locationType = "location_type"
        case locationId = "location_id"
        case recommendationType = "recommendation_type"
        case currentMin = "current_min"
        case currentTarget = "current_target"
        case currentMax = "current_max"
        case recommendedMin = "recommended_min"
        case recommendedTarget = "recommended_target"
        case recommendedMax = "recommended_max"
        case currentCategory = "current_category"
        case recommendedCategory = "recommended_category"
        case usageValue = "usage_value"
        case usageUnit = "usage_unit"
        case dataDays = "data_days"
        case impactScore = "impact_score"
        case reason, status
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case dismissedBy = "dismissed_by"
        case dismissedReason = "dismissed_reason"
        case cooldownUntil = "cooldown_until"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
