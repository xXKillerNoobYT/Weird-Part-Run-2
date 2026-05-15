import Foundation
import GRDB

// MARK: - Walking Path

/// A named audit walking path for a warehouse floor plan.
public struct WarehouseWalkingPath: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_walking_paths"
    public var id: Int64?
    public var floorPlanId: Int64
    public var name: String
    public var isDefault: Bool
    public var createdBy: Int64
    public var createdAt: String?
    public var updatedAt: String?
    public var deletedAt: String?
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case floorPlanId = "floor_plan_id"
        case isDefault = "is_default"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case isActive = "is_active"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A single ordered stop in an audit walking path.
public struct WarehouseWalkingPathStop: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "warehouse_walking_path_stops"
    public var id: Int64?
    public var pathId: Int64
    public var areaId: Int64
    public var sortOrder: Int
    public var note: String?
    public var deletedAt: String?
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, note
        case pathId = "path_id"
        case areaId = "area_id"
        case sortOrder = "sort_order"
        case deletedAt = "deleted_at"
        case isActive = "is_active"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A walking path and its active stops in traversal order.
public struct WalkingPathWithStops: Sendable, Identifiable {
    public var path: WarehouseWalkingPath
    public var stops: [WarehouseWalkingPathStop]

    public var id: Int64? { path.id }
}
