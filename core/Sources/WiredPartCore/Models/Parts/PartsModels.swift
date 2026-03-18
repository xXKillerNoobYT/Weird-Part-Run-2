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
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case styleId = "style_id"
        case sortOrder = "sort_order"
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
    public var sortOrder: Int
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case hexCode = "hex_code"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
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
    public var isActive: Int?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, address, website, notes
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

    enum CodingKeys: String, CodingKey {
        case id, notes
        case brandId = "brand_id"
        case supplierId = "supplier_id"
        case accountNumber = "account_number"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
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
    public var createdBy: Int64?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case styleMatch = "style_match"
        case qtyMode = "qty_mode"
        case qtyRatio = "qty_ratio"
        case isActive = "is_active"
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
