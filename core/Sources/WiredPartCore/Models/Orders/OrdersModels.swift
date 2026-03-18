import Foundation
import GRDB

// MARK: - JPO (Job Purchase Order)

public struct JPO: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "job_parts_orders"
    public var id: Int64?
    public var orderNumber: String
    public var orderType: String
    public var jobId: Int64
    public var requestedBy: Int64
    public var status: String
    public var priority: String
    public var hasSpecialItems: Int
    public var smartSuggestionsEnabled: Int
    public var notes: String?
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, priority, notes
        case orderNumber = "order_number"
        case orderType = "order_type"
        case jobId = "job_id"
        case requestedBy = "requested_by"
        case hasSpecialItems = "has_special_items"
        case smartSuggestionsEnabled = "smart_suggestions_enabled"
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
    public static let databaseTableName = "jpo_line_items"
    public var id: Int64?
    public var jpoId: Int64
    public var partId: Int64
    public var qtyRequested: Int
    public var qtyOrdered: Int
    public var qtyReceived: Int
    public var priority: String?
    public var entryId: Int64?
    public var suggestedSupplierId: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, priority, notes
        case jpoId = "jpo_id"
        case partId = "part_id"
        case qtyRequested = "qty_requested"
        case qtyOrdered = "qty_ordered"
        case qtyReceived = "qty_received"
        case entryId = "entry_id"
        case suggestedSupplierId = "suggested_supplier_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PurchaseOrder

public struct PurchaseOrder: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "purchase_orders"
    public var id: Int64?
    public var poNumber: String
    public var supplierId: Int64
    public var status: String
    public var orderDate: String?
    public var expectedDelivery: String?
    public var actualDelivery: String?
    public var shippingMethod: String?
    public var trackingNumber: String?
    public var subtotal: Double?
    public var taxAmount: Double?
    public var shippingCost: Double?
    public var totalCost: Double?
    public var notes: String?
    public var internalNotes: String?
    public var pdfPath: String?
    public var pdfGeneratedAt: String?
    public var confirmationChecklist: String?
    public var supplierNotes: String?
    public var submittedBy: Int64?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, subtotal, notes
        case poNumber = "po_number"
        case supplierId = "supplier_id"
        case orderDate = "order_date"
        case expectedDelivery = "expected_delivery"
        case actualDelivery = "actual_delivery"
        case shippingMethod = "shipping_method"
        case trackingNumber = "tracking_number"
        case taxAmount = "tax_amount"
        case shippingCost = "shipping_cost"
        case totalCost = "total_cost"
        case internalNotes = "internal_notes"
        case pdfPath = "pdf_path"
        case pdfGeneratedAt = "pdf_generated_at"
        case confirmationChecklist = "confirmation_checklist"
        case supplierNotes = "supplier_notes"
        case submittedBy = "submitted_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - POLine

public struct POLine: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "po_line_items"
    public var id: Int64?
    public var poId: Int64
    public var jpoLineId: Int64?
    public var partId: Int64
    public var qtyOrdered: Int
    public var qtyReceived: Int
    public var unitCost: Double?
    public var receivedUnitCost: Double?
    public var status: String?
    public var backorderExpectedDate: String?
    public var receivedAt: String?
    public var receivedBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, notes
        case poId = "po_id"
        case jpoLineId = "jpo_line_id"
        case partId = "part_id"
        case qtyOrdered = "qty_ordered"
        case qtyReceived = "qty_received"
        case unitCost = "unit_cost"
        case receivedUnitCost = "received_unit_cost"
        case backorderExpectedDate = "backorder_expected_date"
        case receivedAt = "received_at"
        case receivedBy = "received_by"
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
    public var returnNumber: String
    public var returnType: String
    public var poId: Int64?
    public var supplierId: Int64?
    public var jobId: Int64?
    public var status: String
    public var rmaNumber: String?
    public var reason: String
    public var shippingCarrier: String?
    public var trackingNumber: String?
    public var creditAmount: Double
    public var notes: String?
    public var initiatedBy: Int64
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, reason, notes
        case returnNumber = "return_number"
        case returnType = "return_type"
        case poId = "po_id"
        case supplierId = "supplier_id"
        case jobId = "job_id"
        case rmaNumber = "rma_number"
        case shippingCarrier = "shipping_carrier"
        case trackingNumber = "tracking_number"
        case creditAmount = "credit_amount"
        case initiatedBy = "initiated_by"
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
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
    public var partId: Int64
    public var poLineId: Int64?
    public var qty: Int
    public var condition: String
    public var disposition: String
    public var unitCost: Double?
    public var notes: String?
    public var returnableToSupplier: Int
    public var nonReturnReason: String?
    public var belowTargetFlag: Int
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, qty, condition, disposition, notes
        case returnId = "return_id"
        case partId = "part_id"
        case poLineId = "po_line_id"
        case unitCost = "unit_cost"
        case returnableToSupplier = "returnable_to_supplier"
        case nonReturnReason = "non_return_reason"
        case belowTargetFlag = "below_target_flag"
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
    public var jpoId: Int64
    public var description: String
    public var partNumber: String?
    public var quantity: Int
    public var unit: String
    public var estimatedCost: Double?
    public var notes: String?
    public var isFlagged: Int
    public var flagResolvedBy: Int64?
    public var flagResolvedAt: String?
    public var linkedPartId: Int64?
    public var deletedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, quantity, unit, notes
        case jpoId = "jpo_id"
        case partNumber = "part_number"
        case estimatedCost = "estimated_cost"
        case isFlagged = "is_flagged"
        case flagResolvedBy = "flag_resolved_by"
        case flagResolvedAt = "flag_resolved_at"
        case linkedPartId = "linked_part_id"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - StatusHistory

public struct StatusHistory: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "order_status_history"
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
