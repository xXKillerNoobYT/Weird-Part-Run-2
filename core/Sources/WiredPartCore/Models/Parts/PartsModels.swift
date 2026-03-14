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
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case hexCode = "hex_code"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
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
    public var isDefault: Int

    enum CodingKeys: String, CodingKey {
        case id
        case typeId = "type_id"
        case colorId = "color_id"
        case isDefault = "is_default"
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
    public var isPreferred: Int

    enum CodingKeys: String, CodingKey {
        case id
        case typeId = "type_id"
        case brandId = "brand_id"
        case isPreferred = "is_preferred"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Supplier

public struct Supplier: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "suppliers"
    public var id: Int64?
    public var name: String
    public var code: String?
    public var phone: String?
    public var email: String?
    public var website: String?
    public var address: String?
    public var accountNumber: String?
    public var paymentTerms: String?
    public var notes: String?
    public var deliveryMethod: String
    public var minOrderAmount: Double?
    public var freeFreightMinimum: Double?
    public var avgDeliveryDays: Int?
    public var repName: String?
    public var repPhone: String?
    public var repEmail: String?
    public var driverName: String?
    public var driverPhone: String?
    public var reliabilityScore: Double?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, code, phone, email, website, address, notes
        case accountNumber = "account_number"
        case paymentTerms = "payment_terms"
        case deliveryMethod = "delivery_method"
        case minOrderAmount = "min_order_amount"
        case freeFreightMinimum = "free_freight_minimum"
        case avgDeliveryDays = "avg_delivery_days"
        case repName = "rep_name"
        case repPhone = "rep_phone"
        case repEmail = "rep_email"
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
        case reliabilityScore = "reliability_score"
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
    public var isPreferred: Int

    enum CodingKeys: String, CodingKey {
        case id
        case brandId = "brand_id"
        case supplierId = "supplier_id"
        case isPreferred = "is_preferred"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Part

public struct Part: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "parts"
    public var id: Int64?
    public var partNumber: String?
    public var categoryId: Int64?
    public var styleId: Int64?
    public var typeId: Int64?
    public var colorId: Int64?
    public var brandId: Int64?
    public var description: String?
    public var unit: String
    public var sellPrice: Double?
    public var costPrice: Double?
    public var minStock: Int
    public var maxStock: Int?
    public var reorderPoint: Int?
    public var reorderQty: Int?
    public var location: String?
    public var barcode: String?
    public var notes: String?
    public var isActive: Int
    public var weightedAvgCost: Double?
    public var customMarginPercent: Double?
    public var costLastUpdated: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, unit, location, barcode, notes
        case partNumber = "part_number"
        case categoryId = "category_id"
        case styleId = "style_id"
        case typeId = "type_id"
        case colorId = "color_id"
        case brandId = "brand_id"
        case sellPrice = "sell_price"
        case costPrice = "cost_price"
        case minStock = "min_stock"
        case maxStock = "max_stock"
        case reorderPoint = "reorder_point"
        case reorderQty = "reorder_qty"
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
    public var costPrice: Double?
    public var leadTimeDays: Int?
    public var isPreferred: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case partId = "part_id"
        case supplierId = "supplier_id"
        case supplierPartNumber = "supplier_part_number"
        case costPrice = "cost_price"
        case leadTimeDays = "lead_time_days"
        case isPreferred = "is_preferred"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
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
    public var sourceType: String
    public var sourceId: Int64
    public var targetType: String
    public var targetId: Int64
    public var relationship: String
    public var defaultQty: Int
    public var isActive: Int
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, relationship, notes
        case sourceType = "source_type"
        case sourceId = "source_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case defaultQty = "default_qty"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
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
    public var priority: Int
    public var notes: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, relationship, priority, notes
        case partId = "part_id"
        case alternativePartId = "alternative_part_id"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
