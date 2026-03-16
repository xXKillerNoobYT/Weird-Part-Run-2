import Foundation
import GRDB

// MARK: - Tool

public struct Tool: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tools"
    public var id: Int64?
    public var toolNumber: String
    public var name: String
    public var category: String
    public var brand: String?
    public var modelNumber: String?
    public var serialNumber: String?
    public var purchaseDate: String?
    public var purchaseCost: Double?
    public var warrantyExpiry: String?
    public var locationType: String
    public var locationId: Int64?
    public var assignedTo: Int64?
    public var status: String
    public var conditionRating: Int?
    public var hasKit: Int
    public var notes: String?
    public var photoPath: String?
    public var barcode: String?
    public var isActive: Int
    public var depreciationMethod: String?
    public var salvageValue: Double?
    public var usefulLifeYears: Int?
    public var calibrationDueDate: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, brand, status, notes, barcode
        case toolNumber = "tool_number"
        case modelNumber = "model_number"
        case serialNumber = "serial_number"
        case purchaseDate = "purchase_date"
        case purchaseCost = "purchase_cost"
        case warrantyExpiry = "warranty_expiry"
        case locationType = "location_type"
        case locationId = "location_id"
        case assignedTo = "assigned_to"
        case conditionRating = "condition_rating"
        case hasKit = "has_kit"
        case photoPath = "photo_path"
        case isActive = "is_active"
        case depreciationMethod = "depreciation_method"
        case salvageValue = "salvage_value"
        case usefulLifeYears = "useful_life_years"
        case calibrationDueDate = "calibration_due_date"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - KitTemplate (kit component definitions per tool)

public struct KitTemplate: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "kit_templates"
    public var id: Int64?
    public var toolId: Int64
    public var componentName: String
    public var componentType: String
    public var qtyRequired: Int
    public var brand: String?
    public var modelNumber: String?
    public var isCritical: Int
    public var sortOrder: Int?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, brand, notes
        case toolId = "tool_id"
        case componentName = "component_name"
        case componentType = "component_type"
        case qtyRequired = "qty_required"
        case modelNumber = "model_number"
        case isCritical = "is_critical"
        case sortOrder = "sort_order"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ToolMovement

public struct ToolMovement: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tool_movements"
    public var id: Int64?
    public var toolId: Int64
    public var fromLocationType: String?
    public var fromLocationId: Int64?
    public var toLocationType: String?
    public var toLocationId: Int64?
    public var movementType: String
    public var reason: String?
    public var jobId: Int64?
    public var performedBy: Int64
    public var verifiedBy: Int64?
    public var conditionAtMove: Int?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reason
        case toolId = "tool_id"
        case fromLocationType = "from_location_type"
        case fromLocationId = "from_location_id"
        case toLocationType = "to_location_type"
        case toLocationId = "to_location_id"
        case movementType = "movement_type"
        case jobId = "job_id"
        case performedBy = "performed_by"
        case verifiedBy = "verified_by"
        case conditionAtMove = "condition_at_move"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - KitVerificationSession

public struct KitVerificationSession: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "kit_verification_sessions"
    public var id: Int64?
    public var toolId: Int64
    public var movementId: Int64?
    public var verifiedBy: Int64
    public var triggerType: String
    public var isComplete: Int
    public var missingCount: Int
    public var notes: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case toolId = "tool_id"
        case movementId = "movement_id"
        case verifiedBy = "verified_by"
        case triggerType = "trigger_type"
        case isComplete = "is_complete"
        case missingCount = "missing_count"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - KitVerificationItem

public struct KitVerificationItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "kit_verification_items"
    public var id: Int64?
    public var sessionId: Int64
    public var templateItemId: Int64
    public var isPresent: Int
    public var conditionRating: Int?
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case sessionId = "session_id"
        case templateItemId = "template_item_id"
        case isPresent = "is_present"
        case conditionRating = "condition_rating"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ToolMaintenanceType

public struct ToolMaintenanceType: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tool_maintenance_types"
    public var id: Int64?
    public var name: String
    public var description: String?
    public var defaultIntervalDays: Int?
    public var sortOrder: Int?
    public var isActive: Int
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case defaultIntervalDays = "default_interval_days"
        case sortOrder = "sort_order"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ToolMaintenanceSchedule

public struct ToolMaintenanceSchedule: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tool_maintenance_schedules"
    public var id: Int64?
    public var toolId: Int64
    public var maintenanceTypeId: Int64
    public var intervalDays: Int?
    public var lastPerformedAt: String?
    public var nextDueDate: String?
    public var isEnabled: Int
    public var notes: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case toolId = "tool_id"
        case maintenanceTypeId = "maintenance_type_id"
        case intervalDays = "interval_days"
        case lastPerformedAt = "last_performed_at"
        case nextDueDate = "next_due_date"
        case isEnabled = "is_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ToolMaintenanceRecord

public struct ToolMaintenanceRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tool_maintenance_records"
    public var id: Int64?
    public var toolId: Int64
    public var maintenanceTypeId: Int64
    public var serviceDate: String
    public var cost: Double?
    public var vendor: String?
    public var description: String?
    public var performedBy: Int64?
    public var notes: String?
    public var calibrationCertificate: String?
    public var calibrationProvider: String?
    public var calibrationStandard: String?
    public var calibrationResult: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, cost, vendor, description, notes
        case toolId = "tool_id"
        case maintenanceTypeId = "maintenance_type_id"
        case serviceDate = "service_date"
        case performedBy = "performed_by"
        case calibrationCertificate = "calibration_certificate"
        case calibrationProvider = "calibration_provider"
        case calibrationStandard = "calibration_standard"
        case calibrationResult = "calibration_result"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ToolDepreciationEntry

public struct ToolDepreciationEntry: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tool_depreciation_entries"
    public var id: Int64?
    public var toolId: Int64
    public var yearNumber: Int
    public var fiscalYear: String
    public var beginningValue: Double
    public var depreciationAmount: Double
    public var accumulated: Double
    public var endingValue: Double
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case toolId = "tool_id"
        case yearNumber = "year_number"
        case fiscalYear = "fiscal_year"
        case beginningValue = "beginning_value"
        case depreciationAmount = "depreciation_amount"
        case accumulated
        case endingValue = "ending_value"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
