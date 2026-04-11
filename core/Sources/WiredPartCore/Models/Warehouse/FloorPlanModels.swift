import Foundation
import GRDB

// MARK: - Warehouse Floor Plan

/// A warehouse floor plan defining the physical layout dimensions.
public struct WarehouseFloorPlan: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_floor_plans"
    public var id: Int64?
    public var name: String
    public var widthInches: Int
    public var lengthInches: Int
    public var isActive: Bool
    /// User-defined grid rows (PE-040). Nil = not yet set (wizard uses dimensions form).
    public var gridRows: Int?
    /// User-defined grid columns (PE-040). Nil = not yet set (wizard uses dimensions form).
    public var gridCols: Int?
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case widthInches = "width_inches"
        case lengthInches = "length_inches"
        case isActive = "is_active"
        case gridRows = "grid_rows"
        case gridCols = "grid_cols"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Floor Feature

/// A non-storage feature on the floor plan (doors, walkways, offices, etc.)
public struct WarehouseFloorFeature: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_floor_features"
    public var id: Int64?
    public var floorPlanId: Int64
    public var featureType: String
    public var label: String?
    public var gridX: Int
    public var gridY: Int
    public var gridWidth: Int
    public var gridHeight: Int
    public var rotation: Int
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, label, rotation
        case floorPlanId = "floor_plan_id"
        case featureType = "feature_type"
        case gridX = "grid_x"
        case gridY = "grid_y"
        case gridWidth = "grid_width"
        case gridHeight = "grid_height"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Warehouse Zone

/// A logical zone on the floor plan (staging, storage, receiving, etc.)
public struct WarehouseZone: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_zones"
    public var id: Int64?
    public var floorPlanId: Int64
    public var zoneType: String
    public var label: String?
    public var colorHex: String?
    public var gridX: Int
    public var gridY: Int
    public var gridWidth: Int
    public var gridHeight: Int
    public var rotation: Int
    public var zoneOrder: Int
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, label, rotation
        case floorPlanId = "floor_plan_id"
        case zoneType = "zone_type"
        case colorHex = "color_hex"
        case gridX = "grid_x"
        case gridY = "grid_y"
        case gridWidth = "grid_width"
        case gridHeight = "grid_height"
        case zoneOrder = "zone_order"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Storage Unit

/// A physical storage device placed on the floor plan (shelving, rack, gang box, etc.)
public struct WarehouseStorageUnit: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_storage_units"
    public var id: Int64?
    public var floorPlanId: Int64
    public var name: String
    public var unitType: String
    public var rowNumber: String?
    public var unitNumber: String?
    public var widthInches: Int?
    public var depthInches: Int?
    public var heightInches: Int?
    public var gridX: Int?
    public var gridY: Int?
    public var gridWidth: Int?
    public var gridHeight: Int?
    public var rotation: Int
    public var frontFace: String?
    public var isMovable: Bool
    public var isJobReady: Bool
    public var homeAreaId: Int64?
    public var currentLocationType: String?
    public var currentLocationId: Int64?
    public var assignedTo: Int64?
    public var zoneId: Int64?
    public var isConfigured: Bool
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, rotation
        case floorPlanId = "floor_plan_id"
        case unitType = "unit_type"
        case rowNumber = "row_number"
        case unitNumber = "unit_number"
        case widthInches = "width_inches"
        case depthInches = "depth_inches"
        case heightInches = "height_inches"
        case gridX = "grid_x"
        case gridY = "grid_y"
        case gridWidth = "grid_width"
        case gridHeight = "grid_height"
        case frontFace = "front_face"
        case isMovable = "is_movable"
        case isJobReady = "is_job_ready"
        case homeAreaId = "home_area_id"
        case currentLocationType = "current_location_type"
        case currentLocationId = "current_location_id"
        case assignedTo = "assigned_to"
        case zoneId = "zone_id"
        case isConfigured = "is_configured"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Storage Level

/// A level within a storage unit (shelf, tray, drawer, etc.)
public struct WarehouseStorageLevel: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_storage_levels"
    public var id: Int64?
    public var unitId: Int64
    public var levelCode: String
    public var levelName: String?
    public var levelOrder: Int
    public var heightInches: Int?
    public var areaCount: Int
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case unitId = "unit_id"
        case levelCode = "level_code"
        case levelName = "level_name"
        case levelOrder = "level_order"
        case heightInches = "height_inches"
        case areaCount = "area_count"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Storage Area

/// An individual area within a level — where parts actually live.
public struct WarehouseStorageArea: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_storage_areas"
    public var id: Int64?
    public var levelId: Int64
    public var areaCode: String
    public var areaNumber: Int
    public var widthInches: Int?
    public var hasQrCode: Bool
    public var hasSticker: Bool
    public var fullLocationCode: String?
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case levelId = "level_id"
        case areaCode = "area_code"
        case areaNumber = "area_number"
        case widthInches = "width_inches"
        case hasQrCode = "has_qr_code"
        case hasSticker = "has_sticker"
        case fullLocationCode = "full_location_code"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Bin

/// An optional bin within an area — one part type per bin.
public struct WarehouseBin: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_bins"
    public var id: Int64?
    public var areaId: Int64
    public var binCode: String
    public var binNumber: Int
    public var isFixed: Bool
    public var assignedPartId: Int64?
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case areaId = "area_id"
        case binCode = "bin_code"
        case binNumber = "bin_number"
        case isFixed = "is_fixed"
        case assignedPartId = "assigned_part_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Part Assignment

/// Links a part to a storage area (home or secondary location).
public struct WarehousePartAssignment: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_part_assignments"
    public var id: Int64?
    public var partId: Int64
    public var areaId: Int64
    public var isHome: Bool
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case areaId = "area_id"
        case isHome = "is_home"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Onboarding Progress

/// Tracks warehouse onboarding wizard progress.
public struct WarehouseOnboardingProgress: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_onboarding_progress"
    public var id: Int64?
    public var floorPlanId: Int64?
    public var currentStep: Int
    public var step1Complete: Bool
    public var step2Complete: Bool
    public var step3Complete: Bool
    public var step4Progress: String?
    public var step5Progress: String?
    public var step6Progress: String?
    public var flowType: String
    public var totalSteps: Int
    public var stepsProgress: String?
    public var startedAt: String?
    public var completedAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case floorPlanId = "floor_plan_id"
        case currentStep = "current_step"
        case step1Complete = "step1_complete"
        case step2Complete = "step2_complete"
        case step3Complete = "step3_complete"
        case step4Progress = "step4_progress"
        case step5Progress = "step5_progress"
        case step6Progress = "step6_progress"
        case flowType = "flow_type"
        case totalSteps = "total_steps"
        case stepsProgress = "steps_progress"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
