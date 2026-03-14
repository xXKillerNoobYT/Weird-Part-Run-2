import Foundation
import GRDB

// MARK: - JPO (Job Purchase Order)

public struct JPO: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "jpos"
    public var id: Int64?
    public var jobId: Int64
    public var requestedBy: Int64
    public var status: String
    public var priority: String
    public var notes: String?
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, priority, notes
        case jobId = "job_id"
        case requestedBy = "requested_by"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - JPOLine

public struct JPOLine: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "jpo_lines"
    public var id: Int64?
    public var jpoId: Int64
    public var partId: Int64?
    public var description: String?
    public var quantity: Int
    public var unitPrice: Double?
    public var notes: String?
    public var priority: String
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, quantity, notes, priority
        case jpoId = "jpo_id"
        case partId = "part_id"
        case unitPrice = "unit_price"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PurchaseOrder

public struct PurchaseOrder: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "purchase_orders"
    public var id: Int64?
    public var poNumber: String?
    public var supplierId: Int64?
    public var status: String
    public var orderedBy: Int64?
    public var orderedAt: String?
    public var expectedDelivery: String?
    public var shippingCost: Double?
    public var taxAmount: Double?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case poNumber = "po_number"
        case supplierId = "supplier_id"
        case orderedBy = "ordered_by"
        case orderedAt = "ordered_at"
        case expectedDelivery = "expected_delivery"
        case shippingCost = "shipping_cost"
        case taxAmount = "tax_amount"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - POLine

public struct POLine: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "po_lines"
    public var id: Int64?
    public var poId: Int64
    public var jpoLineId: Int64?
    public var partId: Int64?
    public var description: String?
    public var quantityOrdered: Int
    public var quantityReceived: Int
    public var unitPrice: Double?
    public var status: String
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, status, notes
        case poId = "po_id"
        case jpoLineId = "jpo_line_id"
        case partId = "part_id"
        case quantityOrdered = "quantity_ordered"
        case quantityReceived = "quantity_received"
        case unitPrice = "unit_price"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - POJPOLink

public struct POJPOLink: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "po_jpo_links"
    public var id: Int64?
    public var poId: Int64
    public var jpoId: Int64
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case poId = "po_id"
        case jpoId = "jpo_id"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - Return

public struct PartReturn: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "returns"
    public var id: Int64?
    public var poId: Int64?
    public var supplierId: Int64?
    public var returnType: String
    public var status: String
    public var reason: String?
    public var requestedBy: Int64?
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var trackingNumber: String?
    public var creditAmount: Double?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, reason, notes
        case poId = "po_id"
        case supplierId = "supplier_id"
        case returnType = "return_type"
        case requestedBy = "requested_by"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case trackingNumber = "tracking_number"
        case creditAmount = "credit_amount"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - ReturnLineItem

public struct ReturnLineItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "return_line_items"
    public var id: Int64?
    public var returnId: Int64
    public var partId: Int64?
    public var poLineId: Int64?
    public var quantity: Int
    public var conditionStatus: String
    public var reason: String?
    public var notes: String?
    public var sortGroup: String?
    public var sortDisposition: String?
    public var sortNotes: String?
    public var sortedAt: String?
    public var sortedBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, quantity, reason, notes
        case returnId = "return_id"
        case partId = "part_id"
        case poLineId = "po_line_id"
        case conditionStatus = "condition_status"
        case sortGroup = "sort_group"
        case sortDisposition = "sort_disposition"
        case sortNotes = "sort_notes"
        case sortedAt = "sorted_at"
        case sortedBy = "sorted_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - StagingZone

public struct StagingZone: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "staging_zones"
    public var id: Int64?
    public var name: String
    public var zoneType: String
    public var warehouseId: Int64?
    public var description: String?
    public var isActive: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case zoneType = "zone_type"
        case warehouseId = "warehouse_id"
        case isActive = "is_active"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - StagingItem

public struct StagingItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "staging_items"
    public var id: Int64?
    public var stagingZoneId: Int64
    public var partId: Int64?
    public var poLineId: Int64?
    public var jobId: Int64?
    public var quantity: Int
    public var status: String
    public var notes: String?
    public var stagedBy: Int64?
    public var stagedAt: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, quantity, status, notes
        case stagingZoneId = "staging_zone_id"
        case partId = "part_id"
        case poLineId = "po_line_id"
        case jobId = "job_id"
        case stagedBy = "staged_by"
        case stagedAt = "staged_at"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - SpecialItem

public struct SpecialItem: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "special_items"
    public var id: Int64?
    public var jpoId: Int64?
    public var jpoLineId: Int64?
    public var description: String
    public var requestedBy: Int64?
    public var status: String
    public var resolution: String?
    public var resolvedBy: Int64?
    public var resolvedAt: String?
    public var createdPartId: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, status, resolution, notes
        case jpoId = "jpo_id"
        case jpoLineId = "jpo_line_id"
        case requestedBy = "requested_by"
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case createdPartId = "created_part_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - StatusHistory

public struct StatusHistory: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "status_history"
    public var id: Int64?
    public var entityType: String
    public var entityId: Int64
    public var oldStatus: String?
    public var newStatus: String
    public var changedBy: Int64?
    public var notes: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case entityType = "entity_type"
        case entityId = "entity_id"
        case oldStatus = "old_status"
        case newStatus = "new_status"
        case changedBy = "changed_by"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
