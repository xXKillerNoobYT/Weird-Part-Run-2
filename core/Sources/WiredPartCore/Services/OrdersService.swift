import Foundation
import GRDB

/// Orders & Procurement Service — full CRUD for JPOs, purchase orders, returns,
/// staging, and order statistics.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Orders & Procurement feature area (Phases 5, 7A–7D, 17)
public final class OrdersService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum OrdersError: LocalizedError, Sendable {
        case jpoNotFound(Int64)
        case purchaseOrderNotFound(Int64)
        case returnNotFound(Int64)
        case invalidStatusTransition(entity: String, from: String, to: String)
        case invalidStatus(String)

        public var errorDescription: String? {
            switch self {
            case .jpoNotFound(let id): "JPO #\(id) not found"
            case .purchaseOrderNotFound(let id): "PO #\(id) not found"
            case .returnNotFound(let id): "Return #\(id) not found"
            case .invalidStatusTransition(let entity, let from, let to):
                "Cannot change \(entity) from \(from) to \(to)"
            case .invalidStatus(let msg): msg
            }
        }
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A JPO row for list views with summary counts.
    public struct JPOListItem: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let requestedByName: String
        public let status: String
        public let priority: String
        public let lineCount: Int
        public let holdCount: Int
        public let createdAt: String?

        public init(
            id: Int64, jobId: Int64 = 0, jobName: String, requestedByName: String,
            status: String, priority: String, lineCount: Int, holdCount: Int = 0, createdAt: String?
        ) {
            self.id = id
            self.jobId = jobId
            self.jobName = jobName
            self.requestedByName = requestedByName
            self.status = status
            self.priority = priority
            self.lineCount = lineCount
            self.holdCount = holdCount
            self.createdAt = createdAt
        }
    }

    /// A single demand source contributing to a part's procurement need.
    public struct DemandSource: Sendable, Identifiable {
        public let id: String
        public let sourceType: String
        public let sourceId: Int64?
        public let sourceName: String
        public let quantity: Int
        public let lineIds: [Int64]  // JPO line IDs for this source

        public init(sourceType: String, sourceId: Int64?, sourceName: String, quantity: Int, lineIds: [Int64] = []) {
            self.id = "\(sourceType)-\(sourceId ?? 0)-\(quantity)"
            self.sourceType = sourceType
            self.sourceId = sourceId
            self.sourceName = sourceName
            self.quantity = quantity
            self.lineIds = lineIds
        }
    }

    /// Supplier option for a procurement part.
    public struct PartSupplierOption: Sendable, Identifiable {
        public let id: Int64           // supplier_id
        public let name: String
        public let unitPrice: Double?
        public let reliabilityScore: Double?
        public let processingDays: Int?
        public let isToday2PM: Bool    // can make today's cutoff?
        public let isPreferred: Bool
        public let tag: String?        // "cheapest", "rated", "fastest", or nil
    }

    /// A single part's consolidated demand across all sources.
    public struct ProcurementItem: Sendable, Identifiable {
        public let id: Int64
        public let partName: String
        public let partCode: String?
        public let brandName: String?
        public let isGeneric: Bool
        public let totalDemand: Int
        public let shopStock: Int
        public let minStock: Int
        public let targetStock: Int
        public let maxStock: Int
        public let deltaToTarget: Int
        public let sources: [DemandSource]
        public let suppliers: [PartSupplierOption]
        public let urgency: String

        public init(id: Int64, partName: String, partCode: String?, brandName: String?,
                    isGeneric: Bool = false, totalDemand: Int, shopStock: Int,
                    minStock: Int, targetStock: Int, maxStock: Int, deltaToTarget: Int,
                    sources: [DemandSource], suppliers: [PartSupplierOption] = [],
                    urgency: String) {
            self.id = id
            self.partName = partName
            self.partCode = partCode
            self.brandName = brandName
            self.isGeneric = isGeneric
            self.totalDemand = totalDemand
            self.shopStock = shopStock
            self.minStock = minStock
            self.targetStock = targetStock
            self.maxStock = maxStock
            self.deltaToTarget = deltaToTarget
            self.sources = sources
            self.suppliers = suppliers
            self.urgency = urgency
        }
    }

    /// Full JPO detail with nested lines.
    public struct JPODetail: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let requestedBy: Int64
        public let requestedByName: String
        public let status: String
        public let priority: String
        public let notes: String?
        public let approvedBy: Int64?
        public let approvedByName: String?
        public let approvedAt: String?
        public let deletedAt: String?
        public let createdAt: String?
        public let updatedAt: String?
        public let deliveryOption: String?
        public let deliveryLocked: Bool
        public let lines: [JPOLineRow]

        public init(
            id: Int64, jobId: Int64, jobName: String,
            requestedBy: Int64, requestedByName: String,
            status: String, priority: String, notes: String?,
            approvedBy: Int64?, approvedByName: String?, approvedAt: String?,
            deletedAt: String?, createdAt: String?, updatedAt: String?,
            lines: [JPOLineRow],
            deliveryOption: String? = "partial", deliveryLocked: Bool = false
        ) {
            self.id = id
            self.jobId = jobId
            self.jobName = jobName
            self.requestedBy = requestedBy
            self.requestedByName = requestedByName
            self.status = status
            self.priority = priority
            self.notes = notes
            self.approvedBy = approvedBy
            self.approvedByName = approvedByName
            self.approvedAt = approvedAt
            self.deletedAt = deletedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deliveryOption = deliveryOption
            self.deliveryLocked = deliveryLocked
            self.lines = lines
        }
    }

    /// A single JPO line with part name.
    public struct JPOLineRow: Sendable, Identifiable {
        public let id: Int64
        public let jpoId: Int64
        public let partId: Int64?
        public let partName: String?
        public let description: String?
        public let quantity: Int
        public let unitPrice: Double?
        public let notes: String?
        public let priority: String
        public let lineStatus: String
        public let holdReason: String?
        public let rejectReason: String?
        public let chatThreadId: Int64?
        public let poLineId: Int64?
        public let transferId: Int64?
        public let createdAt: String?

        public init(
            id: Int64, jpoId: Int64, partId: Int64?, partName: String?,
            description: String?, quantity: Int, unitPrice: Double?,
            notes: String?, priority: String, createdAt: String?,
            lineStatus: String = "pending", holdReason: String? = nil,
            rejectReason: String? = nil, chatThreadId: Int64? = nil,
            poLineId: Int64? = nil, transferId: Int64? = nil
        ) {
            self.id = id
            self.jpoId = jpoId
            self.partId = partId
            self.partName = partName
            self.description = description
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.notes = notes
            self.priority = priority
            self.lineStatus = lineStatus
            self.holdReason = holdReason
            self.rejectReason = rejectReason
            self.chatThreadId = chatThreadId
            self.poLineId = poLineId
            self.transferId = transferId
            self.createdAt = createdAt
        }
    }

    /// A purchase order row for list views with summary data.
    public struct POListItem: Sendable, Identifiable {
        public let id: Int64
        public let poNumber: String
        public let supplierName: String
        public let status: String
        public let totalCost: Double?
        public let lineCount: Int
        public let orderDate: String?

        public init(
            id: Int64, poNumber: String, supplierName: String,
            status: String, totalCost: Double?, lineCount: Int, orderDate: String?
        ) {
            self.id = id
            self.poNumber = poNumber
            self.supplierName = supplierName
            self.status = status
            self.totalCost = totalCost
            self.lineCount = lineCount
            self.orderDate = orderDate
        }
    }

    /// Full purchase order detail with nested lines.
    public struct PODetail: Sendable, Identifiable {
        public let id: Int64
        public let poNumber: String
        public let supplierId: Int64
        public let supplierName: String
        public let status: String
        public let orderDate: String?
        public let expectedDelivery: String?
        public let actualDelivery: String?
        public let shippingMethod: String?
        public let trackingNumber: String?
        public let subtotal: Double?
        public let taxAmount: Double?
        public let shippingCost: Double?
        public let totalCost: Double?
        public let notes: String?
        public let internalNotes: String?
        public let supplierNotes: String?
        public let submittedBy: Int64?
        public let submittedByName: String?
        public let deletedAt: String?
        public let createdAt: String?
        public let updatedAt: String?
        public let lines: [POLineRow]
        public let linkedJPOIds: [Int64]

        public init(
            id: Int64, poNumber: String, supplierId: Int64, supplierName: String,
            status: String, orderDate: String?, expectedDelivery: String?,
            actualDelivery: String?, shippingMethod: String?, trackingNumber: String?,
            subtotal: Double?, taxAmount: Double?, shippingCost: Double?, totalCost: Double?,
            notes: String?, internalNotes: String?, supplierNotes: String?,
            submittedBy: Int64?, submittedByName: String?,
            deletedAt: String?, createdAt: String?, updatedAt: String?,
            lines: [POLineRow], linkedJPOIds: [Int64]
        ) {
            self.id = id
            self.poNumber = poNumber
            self.supplierId = supplierId
            self.supplierName = supplierName
            self.status = status
            self.orderDate = orderDate
            self.expectedDelivery = expectedDelivery
            self.actualDelivery = actualDelivery
            self.shippingMethod = shippingMethod
            self.trackingNumber = trackingNumber
            self.subtotal = subtotal
            self.taxAmount = taxAmount
            self.shippingCost = shippingCost
            self.totalCost = totalCost
            self.notes = notes
            self.internalNotes = internalNotes
            self.supplierNotes = supplierNotes
            self.submittedBy = submittedBy
            self.submittedByName = submittedByName
            self.deletedAt = deletedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.lines = lines
            self.linkedJPOIds = linkedJPOIds
        }
    }

    /// A single PO line with part name, job info, and source type.
    public struct POLineRow: Sendable, Identifiable {
        public let id: Int64
        public let poId: Int64
        public let jpoLineId: Int64?
        public let partId: Int64?
        public let partName: String?
        public let description: String?
        public let quantityOrdered: Int
        public let quantityReceived: Int
        public let unitPrice: Double?
        public let status: String
        public let notes: String?
        public let createdAt: String?
        public let jobId: Int64?
        public let jobName: String?
        public let source: String?  // "job", "forecast", "wishlist", "general"

        // Computed line-level status for display
        public var lineStatus: String { status }

        public init(
            id: Int64, poId: Int64, jpoLineId: Int64?, partId: Int64?,
            partName: String?, description: String?,
            quantityOrdered: Int, quantityReceived: Int, unitPrice: Double?,
            status: String, notes: String?, createdAt: String?,
            jobId: Int64? = nil, jobName: String? = nil, source: String? = nil
        ) {
            self.id = id
            self.poId = poId
            self.jpoLineId = jpoLineId
            self.partId = partId
            self.partName = partName
            self.description = description
            self.quantityOrdered = quantityOrdered
            self.quantityReceived = quantityReceived
            self.unitPrice = unitPrice
            self.status = status
            self.notes = notes
            self.createdAt = createdAt
            self.jobId = jobId
            self.jobName = jobName
            self.source = source
        }
    }

    /// A return row for list views with summary data.
    public struct ReturnListItem: Sendable, Identifiable {
        public let id: Int64
        public let returnType: String
        public let status: String
        public let supplierName: String?
        public let reason: String?
        public let lineCount: Int
        public let creditAmount: Double?
        public let createdAt: String?

        public init(
            id: Int64, returnType: String, status: String, supplierName: String?,
            reason: String?, lineCount: Int, creditAmount: Double?, createdAt: String?
        ) {
            self.id = id
            self.returnType = returnType
            self.status = status
            self.supplierName = supplierName
            self.reason = reason
            self.lineCount = lineCount
            self.creditAmount = creditAmount
            self.createdAt = createdAt
        }
    }

    /// Aggregate statistics for the orders dashboard.
    public struct OrderStats: Sendable {
        public let pendingJPOs: Int
        public let activePOs: Int
        public let pendingReturns: Int
        public let totalSpend30Days: Double

        public init(pendingJPOs: Int, activePOs: Int, pendingReturns: Int, totalSpend30Days: Double) {
            self.pendingJPOs = pendingJPOs
            self.activePOs = activePOs
            self.pendingReturns = pendingReturns
            self.totalSpend30Days = totalSpend30Days
        }
    }

    // =========================================================================
    // MARK: - 1. JPO CRUD
    // =========================================================================

    /// List JPOs with optional status filter.
    public func listJPOs(
        status: String? = nil,
        limit: Int = 50
    ) throws -> [JPOListItem] {
        do {
            return try db.writer.read { dbConn -> [JPOListItem] in
                var whereClauses = ["jp.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("jp.status = ?")
                    args.append(status)
                }

                args.append(limit)

                let sql = """
                    SELECT jp.id, jp.job_id, jp.status, jp.priority, jp.created_at,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS requested_by_name,
                           COALESCE((SELECT COUNT(*) FROM jpo_line_items jl
                                     WHERE jl.jpo_id = jp.id AND jl.deleted_at IS NULL), 0) AS line_count,
                           COALESCE((SELECT COUNT(*) FROM jpo_line_items jl2
                                     WHERE jl2.jpo_id = jp.id AND jl2.line_status = 'on_hold'
                                     AND jl2.deleted_at IS NULL), 0) AS hold_count
                    FROM job_parts_orders jp
                    LEFT JOIN jobs j ON j.id = jp.job_id
                    LEFT JOIN users u ON u.id = jp.requested_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY jp.created_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    JPOListItem(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "Unknown Job",
                        requestedByName: row["requested_by_name"] ?? "Unknown",
                        status: row["status"] ?? "draft",
                        priority: row["priority"] ?? "normal",
                        lineCount: row["line_count"] ?? 0,
                        holdCount: row["hold_count"] ?? 0,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// List JPOs for a specific job with optional status filter.
    public func listJPOs(
        jobId: Int64,
        status: String? = nil,
        limit: Int = 50
    ) throws -> [JPOListItem] {
        do {
            return try db.writer.read { dbConn -> [JPOListItem] in
                var whereClauses = ["jp.deleted_at IS NULL", "jp.job_id = ?"]
                var args: [DatabaseValueConvertible?] = [jobId]

                if let status, !status.isEmpty {
                    whereClauses.append("jp.status = ?")
                    args.append(status)
                }

                args.append(limit)

                let sql = """
                    SELECT jp.id, jp.job_id, jp.status, jp.priority, jp.created_at,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS requested_by_name,
                           COALESCE((SELECT COUNT(*) FROM jpo_line_items jl
                                     WHERE jl.jpo_id = jp.id AND jl.deleted_at IS NULL), 0) AS line_count,
                           COALESCE((SELECT COUNT(*) FROM jpo_line_items jl2
                                     WHERE jl2.jpo_id = jp.id AND jl2.line_status = 'on_hold'
                                     AND jl2.deleted_at IS NULL), 0) AS hold_count
                    FROM job_parts_orders jp
                    LEFT JOIN jobs j ON j.id = jp.job_id
                    LEFT JOIN users u ON u.id = jp.requested_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY jp.created_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    JPOListItem(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "Unknown Job",
                        requestedByName: row["requested_by_name"] ?? "Unknown",
                        status: row["status"] ?? "draft",
                        priority: row["priority"] ?? "normal",
                        lineCount: row["line_count"] ?? 0,
                        holdCount: row["hold_count"] ?? 0,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single JPO by ID with full detail and nested lines.
    public func getJPODetail(id: Int64) throws -> JPODetail {
        let result: JPODetail? = try db.writer.read { dbConn -> JPODetail? in
            let sql = """
                SELECT jp.*,
                       COALESCE(j.job_name, 'Unknown Job') AS job_name,
                       COALESCE(u_req.display_name, u_req.email, 'Unknown') AS requested_by_name,
                       COALESCE(u_app.display_name, u_app.email) AS approved_by_name
                FROM job_parts_orders jp
                LEFT JOIN jobs j ON j.id = jp.job_id
                LEFT JOIN users u_req ON u_req.id = jp.requested_by
                LEFT JOIN users u_app ON u_app.id = jp.approved_by
                WHERE jp.id = ?
                """
            guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [id]) else {
                return nil
            }

            // Fetch the JPO lines
            let linesSql = """
                SELECT jl.*,
                       p.name AS part_name
                FROM jpo_line_items jl
                LEFT JOIN parts p ON p.id = jl.part_id
                WHERE jl.jpo_id = ? AND jl.deleted_at IS NULL
                ORDER BY jl.created_at ASC
                """
            let lineRows = try Row.fetchAll(dbConn, sql: linesSql, arguments: [id])
            let lines = lineRows.map { lr in
                JPOLineRow(
                    id: lr["id"] ?? 0,
                    jpoId: lr["jpo_id"] ?? 0,
                    partId: lr["part_id"] as Int64?,
                    partName: lr["part_name"] as String?,
                    description: nil,
                    quantity: lr["qty_requested"] ?? 0,
                    unitPrice: nil,
                    notes: lr["notes"] as String?,
                    priority: lr["priority"] ?? "normal",
                    createdAt: lr["created_at"] as String?,
                    lineStatus: lr["line_status"] ?? "pending",
                    holdReason: lr["hold_reason"] as String?,
                    rejectReason: lr["reject_reason"] as String?,
                    chatThreadId: lr["chat_thread_id"] as Int64?,
                    poLineId: lr["po_line_id"] as Int64?,
                    transferId: lr["transfer_id"] as Int64?
                )
            }

            return JPODetail(
                id: row["id"] ?? 0,
                jobId: row["job_id"] ?? 0,
                jobName: row["job_name"] ?? "Unknown Job",
                requestedBy: row["requested_by"] ?? 0,
                requestedByName: row["requested_by_name"] ?? "Unknown",
                status: row["status"] ?? "draft",
                priority: row["priority"] ?? "normal",
                notes: row["notes"] as String?,
                approvedBy: row["approved_by"] as Int64?,
                approvedByName: row["approved_by_name"] as String?,
                approvedAt: row["approved_at"] as String?,
                deletedAt: row["deleted_at"] as String?,
                createdAt: row["created_at"] as String?,
                updatedAt: row["updated_at"] as String?,
                lines: lines,
                deliveryOption: row["delivery_option"] as String? ?? "partial",
                deliveryLocked: (row["delivery_locked"] as Int? ?? 0) != 0
            )
        }
        guard let result else { throw OrdersError.jpoNotFound(id) }
        return result
    }

    /// Create a new JPO. Returns the inserted row ID.
    @discardableResult
    public func createJPO(
        jobId: Int64,
        requestedBy: Int64,
        priority: String = "normal",
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            let orderNumber = "JPO-\(jobId)-\(Int(Date().timeIntervalSince1970))"
            try dbConn.execute(
                sql: """
                    INSERT INTO job_parts_orders
                    (job_id, order_number, requested_by, status, priority, notes,
                     created_at, updated_at)
                    VALUES (?, ?, ?, 'draft', ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, orderNumber, requestedBy, priority, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update the status of a JPO and record the transition in status_history.
    /// - Parameters:
    ///   - id: The JPO row ID.
    ///   - status: New status string (e.g. "approved", "rejected").
    ///   - reason: Optional reason stored in `order_status_history.notes` (e.g. rejection reason).
    public func updateJPOStatus(id: Int64, status: String, reason: String? = nil) throws {
        try db.writer.write { dbConn in
            // Verify the JPO exists
            guard let row = try Row.fetchOne(
                dbConn,
                sql: "SELECT id, status FROM job_parts_orders WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            ) else {
                throw OrdersError.jpoNotFound(id)
            }

            let oldStatus: String = row["status"] ?? "draft"

            // Update the JPO status
            try dbConn.execute(
                sql: """
                    UPDATE job_parts_orders
                    SET status = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [status, id]
            )

            // Record status transition in history (best-effort — table may not exist yet)
            do {
                try dbConn.execute(
                    sql: """
                        INSERT INTO order_status_history
                        (entity_type, entity_id, old_status, new_status, notes, created_at)
                        VALUES ('jpo', ?, ?, ?, ?, datetime('now'))
                        """,
                    arguments: [id, oldStatus, status, reason]
                )
            } catch {
                // order_status_history table may not exist; status update still succeeds
            }
        }
    }

    /// Add a line item to a JPO. Auto-routes via smart routing if partId is provided.
    @discardableResult
    public func addJPOLineItem(
        jpoId: Int64,
        partId: Int64,
        quantity: Int,
        notes: String? = nil,
        userId: Int64? = nil
    ) throws -> Int64 {
        let lineId = try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO jpo_line_items
                    (jpo_id, part_id, qty_requested, notes, created_at)
                    VALUES (?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [jpoId, partId, quantity, notes]
            )
            return dbConn.lastInsertedRowID
        }
        // Smart route the new line
        _ = try smartRouteJPOLine(lineId: lineId, partId: partId, userId: userId ?? 0)
        return lineId
    }

    // MARK: - 1c. JPO Per-Line Status

    /// Update a single JPO line item's status, with optional hold/reject reason.
    /// Automatically re-derives the parent JPO's overall status.
    public func updateJPOLineStatus(lineId: Int64, status: String, reason: String? = nil, updatedBy: Int64? = nil) throws {
        try db.writer.write { dbConn in
            var setClauses = ["line_status = ?", "status_updated_at = datetime('now')"]
            var args: [DatabaseValueConvertible?] = [status]

            if let by = updatedBy {
                setClauses.append("status_updated_by = ?")
                args.append(by)
            }
            if status == "on_hold", let reason {
                setClauses.append("hold_reason = ?")
                args.append(reason)
            }
            if status == "rejected", let reason {
                setClauses.append("reject_reason = ?")
                args.append(reason)
            }
            args.append(lineId)

            try dbConn.execute(
                sql: "UPDATE jpo_line_items SET \(setClauses.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(args)
            )

            // Re-derive parent JPO status from all its lines
            if let jpoId = try Int64.fetchOne(dbConn, sql: "SELECT jpo_id FROM jpo_line_items WHERE id = ?", arguments: [lineId]) {
                let allStatuses = try String.fetchAll(dbConn, sql: """
                    SELECT line_status FROM jpo_line_items WHERE jpo_id = ? AND deleted_at IS NULL
                    """, arguments: [jpoId])
                let derived = deriveJPOStatusFromLineStatuses(allStatuses)
                try dbConn.execute(
                    sql: "UPDATE job_parts_orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
                    arguments: [derived, jpoId]
                )
            }
        }
    }

    /// Put a JPO line on hold and create a chat channel for Q&A.
    /// Both the manager (who held) and the requester (who created the JPO) are auto-added.
    /// The hold reason becomes the first message in the thread.
    /// Returns the chat channel ID.
    public func holdJPOLineWithChat(
        lineId: Int64,
        holdReason: String,
        userId: Int64,
        partName: String,
        jpoId: Int64
    ) throws -> Int64 {
        return try db.writer.write { dbConn -> Int64 in
            // Create a chat channel for this Q&A
            let channelName = "JPO #\(jpoId) — \(partName)"
            try dbConn.execute(
                sql: """
                    INSERT INTO chat_channels (name, channel_type, created_by, is_active, created_at, updated_at)
                    VALUES (?, 'jpo_qa', ?, 1, datetime('now'), datetime('now'))
                    """,
                arguments: [channelName, userId]
            )
            let channelId = dbConn.lastInsertedRowID

            // Add the manager (who held) as admin
            try dbConn.execute(
                sql: """
                    INSERT OR IGNORE INTO chat_channel_members (channel_id, user_id, role, joined_at)
                    VALUES (?, ?, 'admin', datetime('now'))
                    """,
                arguments: [channelId, userId]
            )

            // Add the JPO requester as member
            let requesterId = try Int64.fetchOne(dbConn, sql: """
                SELECT requested_by FROM job_parts_orders WHERE id = ?
                """, arguments: [jpoId])
            if let reqId = requesterId, reqId != userId {
                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO chat_channel_members (channel_id, user_id, role, joined_at)
                        VALUES (?, ?, 'member', datetime('now'))
                        """,
                    arguments: [channelId, reqId]
                )
            }

            // Send the hold reason as the first message
            try dbConn.execute(
                sql: """
                    INSERT INTO chat_messages (channel_id, sender_id, message_type, content, created_at)
                    VALUES (?, ?, 'text', ?, datetime('now'))
                    """,
                arguments: [channelId, userId, holdReason]
            )

            // Update the JPO line to on_hold with chat thread link
            try dbConn.execute(
                sql: """
                    UPDATE jpo_line_items SET
                        line_status = 'on_hold',
                        hold_reason = ?,
                        chat_thread_id = ?,
                        status_updated_at = datetime('now'),
                        status_updated_by = ?
                    WHERE id = ?
                    """,
                arguments: [holdReason, channelId, userId, lineId]
            )

            // Re-derive parent JPO status
            let allStatuses = try String.fetchAll(dbConn, sql: """
                SELECT line_status FROM jpo_line_items WHERE jpo_id = ? AND deleted_at IS NULL
                """, arguments: [jpoId])
            let derived = deriveJPOStatusFromLineStatuses(allStatuses)
            try dbConn.execute(
                sql: "UPDATE job_parts_orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [derived, jpoId]
            )

            return channelId
        }
    }

    /// Derive the overall JPO status from its line items' per-line statuses.
    public func deriveJPOStatusFromLineStatuses(_ statuses: [String]) -> String {
        let unique = Set(statuses)
        if unique.isEmpty { return "draft" }
        if unique == ["pending"] { return "pending" }
        if unique == ["rejected"] { return "rejected" }
        if unique.allSatisfy({ $0 == "delivered" }) { return "complete" }
        if unique.allSatisfy({ ["ordered", "received", "backorder", "staged", "delivered", "in_procurement"].contains($0) }) { return "ordered" }
        if unique.allSatisfy({ ["approved", "transfer", "in_procurement", "ordered", "received", "backorder", "staged", "delivered"].contains($0) }) { return "approved" }
        return "in_review"
    }

    /// Check stock and auto-route a JPO line item.
    /// Returns "transfer" if stock is available at the shop, "pending" if it needs ordering.
    @discardableResult
    public func smartRouteJPOLine(lineId: Int64, partId: Int64, userId: Int64) throws -> String {
        try db.writer.write { dbConn -> String in
            // Check shop stock (sum across all locations)
            let shopStock = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(qty), 0) FROM stock
                WHERE part_id = ? AND deleted_at IS NULL
                """, arguments: [partId]) ?? 0

            let requestedQty = try Int.fetchOne(dbConn, sql: """
                SELECT qty_requested FROM jpo_line_items WHERE id = ?
                """, arguments: [lineId]) ?? 0

            if shopStock >= requestedQty {
                // In stock — auto-create transfer, no approval needed
                try dbConn.execute(
                    sql: """
                        UPDATE jpo_line_items SET line_status = 'transfer',
                        status_updated_at = datetime('now'), status_updated_by = ?
                        WHERE id = ?
                        """,
                    arguments: [userId, lineId]
                )
                return "transfer"
            } else {
                // Needs ordering — requires approval
                try dbConn.execute(
                    sql: """
                        UPDATE jpo_line_items SET line_status = 'pending',
                        status_updated_at = datetime('now'), status_updated_by = ?
                        WHERE id = ?
                        """,
                    arguments: [userId, lineId]
                )
                return "pending"
            }
        }
    }

    /// Link a stock movement (transfer) ID to a JPO line item.
    public func setJPOLineTransferId(lineId: Int64, transferId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE jpo_line_items SET transfer_id = ?
                    WHERE id = ?
                    """,
                arguments: [transferId, lineId]
            )
        }
    }

    /// Cancel a pending transfer linked to a JPO line.
    /// Reverses the stock movement and clears the transfer_id on the line.
    public func cancelJPOLineTransfer(lineId: Int64, reversedBy: Int64, warehouseService: WarehouseService) throws {
        try db.writer.write { dbConn in
            // Find the linked transfer movement
            guard let row = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT transfer_id, part_id, qty_requested
                    FROM jpo_line_items WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [lineId]
            ) else { return }

            let transferId: Int64? = row["transfer_id"]
            let partId: Int64? = row["part_id"]
            let qty: Int = row["qty_requested"] ?? 0

            // Clear the transfer link and reset to on_hold
            try dbConn.execute(
                sql: """
                    UPDATE jpo_line_items SET transfer_id = NULL
                    WHERE id = ?
                    """,
                arguments: [lineId]
            )

            // If there's a linked movement and a part, create a reverse movement
            // to return stock from pulled back to warehouse
            if transferId != nil, let partId, qty > 0 {
                try warehouseService.createMovement(
                    partId: partId,
                    qty: qty,
                    fromLocationType: "pulled",
                    fromLocationId: 1,
                    toLocationType: "warehouse",
                    toLocationId: 1,
                    movementType: "transfer",
                    reason: "JPO line hold — reversing transfer",
                    notes: "Reversed transfer for JPO line #\(lineId)",
                    performedBy: reversedBy
                )
            }
        }
    }

    /// Update the delivery option for a JPO. Fails if delivery is already locked.
    public func updateJPODeliveryOption(jpoId: Int64, option: String) throws {
        try db.writer.write { dbConn in
            let locked = try Int.fetchOne(dbConn, sql: """
                SELECT delivery_locked FROM job_parts_orders WHERE id = ?
                """, arguments: [jpoId]) ?? 0
            guard locked == 0 else {
                throw OrdersError.invalidStatus("Delivery option is locked — parts already delivered")
            }
            try dbConn.execute(
                sql: """
                    UPDATE job_parts_orders SET delivery_option = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [option, jpoId]
            )
        }
    }

    /// Create a JPO with all line items in one transaction. Smart-routes each line.
    /// Returns the new JPO ID.
    @discardableResult
    public func createJPOWithLines(
        jobId: Int64,
        requestedBy: Int64,
        priority: String,
        deliveryOption: String,
        notes: String?,
        lines: [(partId: Int64, quantity: Int)]
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // 1. Create the JPO
            let orderNumber = "JPO-\(jobId)-\(Int(Date().timeIntervalSince1970))"
            try dbConn.execute(sql: """
                INSERT INTO job_parts_orders
                (job_id, order_number, requested_by, status, priority, delivery_option, notes,
                 created_at, updated_at)
                VALUES (?, ?, ?, 'pending', ?, ?, ?, datetime('now'), datetime('now'))
                """, arguments: [jobId, orderNumber, requestedBy, priority, deliveryOption, notes])
            let jpoId = dbConn.lastInsertedRowID

            // 2. Insert each line and smart-route
            for line in lines {
                try dbConn.execute(sql: """
                    INSERT INTO jpo_line_items
                    (jpo_id, part_id, qty_requested, priority, notes, created_at)
                    VALUES (?, ?, ?, ?, NULL, datetime('now'))
                    """, arguments: [jpoId, line.partId, line.quantity, priority])
                let lineId = dbConn.lastInsertedRowID

                // Check shop stock for smart routing
                let shopStock = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(qty), 0) FROM stock
                    WHERE part_id = ? AND deleted_at IS NULL
                    """, arguments: [line.partId]) ?? 0

                let lineStatus = shopStock >= line.quantity ? "transfer" : "pending"
                try dbConn.execute(sql: """
                    UPDATE jpo_line_items SET line_status = ?,
                    status_updated_at = datetime('now'), status_updated_by = ?
                    WHERE id = ?
                    """, arguments: [lineStatus, requestedBy, lineId])
            }

            // 3. Derive overall JPO status from line statuses
            let statuses = try String.fetchAll(dbConn, sql:
                "SELECT line_status FROM jpo_line_items WHERE jpo_id = ?", arguments: [jpoId])
            let derived = self.deriveJPOStatusFromLineStatuses(statuses)
            try dbConn.execute(sql:
                "UPDATE job_parts_orders SET status = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [derived, jpoId])

            return jpoId
        }
    }

    // MARK: - 1d. Procurement Aggregation

    /// Get all consolidated procurement demand, grouped by part.
    /// Aggregates approved JPO lines + overstock detection.
    public func getProcurementDemand() throws -> [ProcurementItem] {
        do {
            return try db.writer.read { dbConn in
                // 2 PM cutoff calculation
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: Date())
                let isPre2PM = hour < 14

                // 1. Get approved JPO lines not yet in procurement/ordered
                let jpoLines = try Row.fetchAll(dbConn, sql: """
                    SELECT jl.part_id, p.name AS part_name, p.code AS part_code,
                           b.name AS brand_name,
                           CASE WHEN b.name IS NULL OR b.name = 'General' THEN 1 ELSE 0 END AS is_generic,
                           jl.qty_requested AS quantity, jl.id AS line_id,
                           jpo.id AS jpo_id, j.job_name
                    FROM jpo_line_items jl
                    JOIN job_parts_orders jpo ON jpo.id = jl.jpo_id
                    LEFT JOIN jobs j ON j.id = jpo.job_id
                    LEFT JOIN parts p ON p.id = jl.part_id
                    LEFT JOIN brands b ON b.id = p.brand_id
                    WHERE jl.line_status = 'approved'
                      AND jl.deleted_at IS NULL
                      AND jpo.deleted_at IS NULL
                    """)

                // Group by part_id, tracking JPO line IDs per source
                var partDemand: [Int64: (partRow: Row, sources: [DemandSource], totalQty: Int)] = [:]
                // Track line IDs per (partId, jpoId) for merging lines from same JPO
                var lineIdTracker: [Int64: [Int64: [Int64]]] = [:]  // [partId: [jpoId: [lineIds]]]

                for row in jpoLines {
                    guard let partId: Int64 = row["part_id"] else { continue }
                    let jpoId: Int64 = row["jpo_id"] ?? 0
                    let jobName: String = row["job_name"] ?? ""
                    let qty: Int = row["quantity"] ?? 0
                    let lineId: Int64 = row["line_id"] ?? 0

                    lineIdTracker[partId, default: [:]][jpoId, default: []].append(lineId)

                    let source = DemandSource(
                        sourceType: "jpo",
                        sourceId: jpoId,
                        sourceName: "JPO #\(jpoId) (\(jobName))",
                        quantity: qty,
                        lineIds: [lineId]
                    )

                    if partDemand[partId] != nil {
                        partDemand[partId]!.sources.append(source)
                        partDemand[partId]!.totalQty += qty
                    } else {
                        partDemand[partId] = (partRow: row, sources: [source], totalQty: qty)
                    }
                }

                // Build final items with stock info and suppliers
                var items: [ProcurementItem] = []
                for (partId, data) in partDemand {
                    let shopStock = try Int.fetchOne(dbConn, sql: """
                        SELECT COALESCE(SUM(qty), 0) FROM stock
                        WHERE part_id = ? AND deleted_at IS NULL
                        """, arguments: [partId]) ?? 0

                    let stockInfo = try Row.fetchOne(dbConn, sql: """
                        SELECT COALESCE(min_stock_level, 0) AS min_stock,
                               COALESCE(target_stock_level, 0) AS target_stock,
                               COALESCE(max_stock_level, 0) AS max_stock
                        FROM parts WHERE id = ?
                        """, arguments: [partId])

                    let minStock: Int = stockInfo?["min_stock"] ?? 0
                    let targetStock: Int = stockInfo?["target_stock"] ?? 0
                    let maxStock: Int = stockInfo?["max_stock"] ?? 0
                    let delta = targetStock - shopStock

                    let urgency: String
                    if shopStock > maxStock && maxStock > 0 { urgency = "overstock" }
                    else if shopStock < minStock { urgency = "understock" }
                    else if shopStock < targetStock { urgency = "below_target" }
                    else { urgency = "good" }

                    // Fetch suppliers for this part
                    let supplierRows = try Row.fetchAll(dbConn, sql: """
                        SELECT s.id, s.name, psl.supplier_cost_price, s.reliability_score,
                               COALESCE(CAST(s.delivery_days AS INTEGER), 14) AS processing_days,
                               psl.is_preferred
                        FROM part_supplier_links psl
                        JOIN suppliers s ON s.id = psl.supplier_id
                        WHERE psl.part_id = ? AND psl.deleted_at IS NULL AND s.deleted_at IS NULL
                        ORDER BY psl.is_preferred DESC, s.name ASC
                        """, arguments: [partId])

                    var supplierOptions: [PartSupplierOption] = supplierRows.map { sRow in
                        let suppId: Int64 = sRow["id"] ?? 0
                        let price: Double? = sRow["supplier_cost_price"]
                        let reliability: Double? = sRow["reliability_score"]
                        let procDays: Int = sRow["processing_days"] ?? 14
                        let preferred: Int = sRow["is_preferred"] ?? 0
                        let canMakeToday = isPre2PM && procDays == 0

                        return PartSupplierOption(
                            id: suppId,
                            name: sRow["name"] ?? "Unknown",
                            unitPrice: price,
                            reliabilityScore: reliability,
                            processingDays: procDays,
                            isToday2PM: canMakeToday,
                            isPreferred: preferred == 1,
                            tag: nil // assigned below
                        )
                    }

                    // Assign tags: cheapest, rated, fastest
                    if supplierOptions.count > 1 {
                        // Cheapest by unit price
                        if let cheapestIdx = supplierOptions.enumerated()
                            .filter({ $0.element.unitPrice != nil })
                            .min(by: { ($0.element.unitPrice ?? .infinity) < ($1.element.unitPrice ?? .infinity) })?.offset {
                            supplierOptions[cheapestIdx] = PartSupplierOption(
                                id: supplierOptions[cheapestIdx].id,
                                name: supplierOptions[cheapestIdx].name,
                                unitPrice: supplierOptions[cheapestIdx].unitPrice,
                                reliabilityScore: supplierOptions[cheapestIdx].reliabilityScore,
                                processingDays: supplierOptions[cheapestIdx].processingDays,
                                isToday2PM: supplierOptions[cheapestIdx].isToday2PM,
                                isPreferred: supplierOptions[cheapestIdx].isPreferred,
                                tag: "cheapest"
                            )
                        }
                        // Highest rated by reliability
                        if let ratedIdx = supplierOptions.enumerated()
                            .filter({ $0.element.reliabilityScore != nil })
                            .max(by: { ($0.element.reliabilityScore ?? 0) < ($1.element.reliabilityScore ?? 0) })?.offset,
                           supplierOptions[ratedIdx].tag == nil {
                            supplierOptions[ratedIdx] = PartSupplierOption(
                                id: supplierOptions[ratedIdx].id,
                                name: supplierOptions[ratedIdx].name,
                                unitPrice: supplierOptions[ratedIdx].unitPrice,
                                reliabilityScore: supplierOptions[ratedIdx].reliabilityScore,
                                processingDays: supplierOptions[ratedIdx].processingDays,
                                isToday2PM: supplierOptions[ratedIdx].isToday2PM,
                                isPreferred: supplierOptions[ratedIdx].isPreferred,
                                tag: "rated"
                            )
                        }
                        // Fastest by processing days
                        if let fastestIdx = supplierOptions.enumerated()
                            .filter({ $0.element.processingDays != nil })
                            .min(by: { ($0.element.processingDays ?? 999) < ($1.element.processingDays ?? 999) })?.offset,
                           supplierOptions[fastestIdx].tag == nil {
                            supplierOptions[fastestIdx] = PartSupplierOption(
                                id: supplierOptions[fastestIdx].id,
                                name: supplierOptions[fastestIdx].name,
                                unitPrice: supplierOptions[fastestIdx].unitPrice,
                                reliabilityScore: supplierOptions[fastestIdx].reliabilityScore,
                                processingDays: supplierOptions[fastestIdx].processingDays,
                                isToday2PM: supplierOptions[fastestIdx].isToday2PM,
                                isPreferred: supplierOptions[fastestIdx].isPreferred,
                                tag: "fastest"
                            )
                        }
                    }

                    let isGeneric = (data.partRow["is_generic"] as Int?) == 1

                    items.append(ProcurementItem(
                        id: partId,
                        partName: data.partRow["part_name"] ?? "Unknown",
                        partCode: data.partRow["part_code"],
                        brandName: data.partRow["brand_name"],
                        isGeneric: isGeneric,
                        totalDemand: data.totalQty,
                        shopStock: shopStock,
                        minStock: minStock,
                        targetStock: targetStock,
                        maxStock: maxStock,
                        deltaToTarget: delta,
                        sources: data.sources,
                        suppliers: supplierOptions,
                        urgency: urgency
                    ))
                }

                // Check for overstock items (above MAX, no existing demand)
                let overstockParts = try Row.fetchAll(dbConn, sql: """
                    SELECT p.id, p.name, p.code, COALESCE(SUM(s.qty), 0) AS stock,
                           p.max_stock_level
                    FROM parts p
                    LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL
                    WHERE p.deleted_at IS NULL AND p.max_stock_level > 0
                    GROUP BY p.id
                    HAVING stock > p.max_stock_level
                    """)
                for row in overstockParts {
                    let partId: Int64 = row["id"] ?? 0
                    if partDemand[partId] == nil {
                        let stock: Int = row["stock"] ?? 0
                        let maxS: Int = row["max_stock_level"] ?? 0
                        items.append(ProcurementItem(
                            id: partId,
                            partName: row["name"] ?? "Unknown",
                            partCode: row["code"],
                            brandName: nil,
                            totalDemand: 0,
                            shopStock: stock,
                            minStock: 0, targetStock: 0, maxStock: maxS,
                            deltaToTarget: -(stock - maxS),
                            sources: [DemandSource(sourceType: "overstock", sourceId: nil,
                                                   sourceName: "Overstock (above MAX)", quantity: stock - maxS)],
                            urgency: "overstock"
                        ))
                    }
                }

                // Sort: overstock first, then understock, then below_target, then good
                let urgencyOrder = ["overstock": 0, "understock": 1, "below_target": 2, "good": 3]
                items.sort { (urgencyOrder[$0.urgency] ?? 99) < (urgencyOrder[$1.urgency] ?? 99) }
                return items
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Input item for bulk PO generation from procurement.
    public struct ProcurementGenerateItem: Sendable {
        public let partId: Int64
        public let supplierId: Int64
        public let quantity: Int
        public let unitCost: Double?
        public let jpoLineIds: [Int64]

        public init(partId: Int64, supplierId: Int64, quantity: Int, unitCost: Double? = nil, jpoLineIds: [Int64]) {
            self.partId = partId
            self.supplierId = supplierId
            self.quantity = quantity
            self.unitCost = unitCost
            self.jpoLineIds = jpoLineIds
        }
    }

    /// Result of PO generation from procurement.
    public struct ProcurementGenerateResult: Sendable {
        public let createdPOs: [(poId: Int64, poNumber: String, supplierId: Int64)]
        public let totalLineItems: Int
    }

    /// Generate draft POs from procurement selections, grouped by supplier.
    /// Each supplier gets one PO with all their selected parts as line items.
    /// JPO line items are linked and their status set to 'in_procurement'.
    @discardableResult
    public func generatePOsFromProcurement(items: [ProcurementGenerateItem]) throws -> ProcurementGenerateResult {
        try db.writer.write { dbConn in
            // Group items by supplier
            var bySupplier: [Int64: [ProcurementGenerateItem]] = [:]
            for item in items {
                bySupplier[item.supplierId, default: []].append(item)
            }

            var createdPOs: [(poId: Int64, poNumber: String, supplierId: Int64)] = []
            var totalLines = 0

            for (supplierId, supplierItems) in bySupplier {
                // Generate PO number (MAX-based to prevent duplicates after deletions)
                let maxNum = try Int.fetchOne(
                    dbConn,
                    sql: "SELECT COALESCE(MAX(CAST(SUBSTR(po_number, 4) AS INTEGER)), 0) FROM purchase_orders"
                ) ?? 0
                let poNumber = String(format: "PO-%05d", maxNum + 1)

                // Create PO
                try dbConn.execute(
                    sql: """
                        INSERT INTO purchase_orders
                        (po_number, supplier_id, status, order_date, created_at, updated_at)
                        VALUES (?, ?, 'draft', date('now'), datetime('now'), datetime('now'))
                        """,
                    arguments: [poNumber, supplierId]
                )
                let poId = dbConn.lastInsertedRowID

                // Create line items for each part
                for item in supplierItems {
                    try dbConn.execute(
                        sql: """
                            INSERT INTO po_line_items
                            (po_id, part_id, qty_ordered, unit_cost, created_at)
                            VALUES (?, ?, ?, ?, datetime('now'))
                            """,
                        arguments: [poId, item.partId, item.quantity, item.unitCost]
                    )
                    let poLineId = dbConn.lastInsertedRowID
                    totalLines += 1

                    // Link JPO line items to this PO line and update their status
                    for jpoLineId in item.jpoLineIds {
                        try dbConn.execute(
                            sql: """
                                UPDATE po_line_items SET jpo_line_id = ?
                                WHERE id = ? AND jpo_line_id IS NULL
                                """,
                            arguments: [jpoLineId, poLineId]
                        )
                        try dbConn.execute(
                            sql: """
                                UPDATE jpo_line_items
                                SET line_status = 'in_procurement',
                                    po_line_id = ?,
                                    status_updated_at = datetime('now')
                                WHERE id = ? AND deleted_at IS NULL
                                """,
                            arguments: [poLineId, jpoLineId]
                        )
                    }

                    // Also link JPO line IDs to the PO line for traceability
                    // (first jpo_line_id goes on the po_line_items row)
                    if let firstJPOLineId = item.jpoLineIds.first {
                        try dbConn.execute(
                            sql: "UPDATE po_line_items SET jpo_line_id = ? WHERE id = ?",
                            arguments: [firstJPOLineId, poLineId]
                        )
                    }
                }

                // Link POs to JPOs via po_jpo_links
                let uniqueJPOIds = Set(supplierItems.flatMap { item in
                    // Resolve JPO IDs from jpo_line_items
                    item.jpoLineIds.compactMap { lineId -> Int64? in
                        try? Int64.fetchOne(dbConn,
                            sql: "SELECT jpo_id FROM jpo_line_items WHERE id = ?",
                            arguments: [lineId])
                    }
                })
                for jpoId in uniqueJPOIds {
                    try? dbConn.execute(
                        sql: """
                            INSERT OR IGNORE INTO po_jpo_links (po_id, jpo_id, created_at)
                            VALUES (?, ?, datetime('now'))
                            """,
                        arguments: [poId, jpoId]
                    )
                }

                createdPOs.append((poId: poId, poNumber: poNumber, supplierId: supplierId))
            }

            return ProcurementGenerateResult(createdPOs: createdPOs, totalLineItems: totalLines)
        }
    }

    // =========================================================================
    // MARK: - 1c. Job Stage Planner
    // =========================================================================

    /// A job stage with its sort order.
    public struct JobStage: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let sortOrder: Int
    }

    /// A part within a job stage grouping.
    public struct StagePart: Sendable, Identifiable {
        public let id: Int64          // jpo_line_item id
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let quantity: Int
        public let lineStatus: String
        public let stageId: Int64?
        public let stageName: String?
        public let jpoId: Int64
        public let jpoNumber: String  // "JPO #N"
        public let isHeld: Bool       // true if in a future stage
    }

    /// Get all job stages in order.
    public func getJobStages() throws -> [JobStage] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, name, sort_order FROM job_stages
                WHERE deleted_at IS NULL
                ORDER BY sort_order ASC
                """)
            return rows.map {
                JobStage(id: $0["id"] ?? 0, name: $0["name"] ?? "", sortOrder: $0["sort_order"] ?? 0)
            }
        }
    }

    /// Get all JPO parts for a job, grouped by stage via category→stage mapping.
    /// Parts in stages after the job's current stage are marked as "held".
    public func getJobStageParts(jobId: Int64) throws -> [StagePart] {
        try db.writer.read { dbConn in
            // Get the job's current stage
            let currentStageId: Int64? = try Int64.fetchOne(dbConn, sql: """
                SELECT current_stage_id FROM jobs WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId])

            // Get current stage sort_order (default to 0 = all stages active)
            let currentSortOrder: Int = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(sort_order, 0) FROM job_stages WHERE id = ?
                """, arguments: [currentStageId ?? 0]) ?? 0

            // Fetch all JPO line items for this job with stage info
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT jl.id, jl.part_id, p.name AS part_name, p.code AS part_code,
                       jl.qty_requested, jl.line_status,
                       COALESCE(jl.stage_id, jscm.stage_id) AS resolved_stage_id,
                       js.name AS stage_name, js.sort_order AS stage_sort_order,
                       jpo.id AS jpo_id
                FROM jpo_line_items jl
                JOIN job_parts_orders jpo ON jpo.id = jl.jpo_id
                LEFT JOIN parts p ON p.id = jl.part_id
                LEFT JOIN job_stage_category_map jscm ON jscm.category_id = p.category_id
                LEFT JOIN job_stages js ON js.id = COALESCE(jl.stage_id, jscm.stage_id)
                WHERE jpo.job_id = ?
                  AND jl.deleted_at IS NULL
                  AND jpo.deleted_at IS NULL
                ORDER BY COALESCE(js.sort_order, 999) ASC, p.name ASC
                """, arguments: [jobId])

            return rows.map { row in
                let stageSortOrder: Int = row["stage_sort_order"] ?? 999
                let resolvedStageId: Int64? = row["resolved_stage_id"]
                let isHeld = currentSortOrder > 0 && stageSortOrder > currentSortOrder

                return StagePart(
                    id: row["id"] ?? 0,
                    partId: row["part_id"] ?? 0,
                    partName: row["part_name"] ?? "Unknown",
                    partCode: row["part_code"],
                    quantity: row["qty_requested"] ?? 1,
                    lineStatus: row["line_status"] ?? "pending",
                    stageId: resolvedStageId,
                    stageName: row["stage_name"],
                    jpoId: row["jpo_id"] ?? 0,
                    jpoNumber: "JPO #\(row["jpo_id"] as Int64? ?? 0)",
                    isHeld: isHeld
                )
            }
        }
    }

    /// Mark a stage as complete for a job. Sets the job's current_stage_id to this stage
    /// and auto-releases held parts in the next stage to procurement.
    public func markStageComplete(jobId: Int64, stageId: Int64) throws {
        try db.writer.write { dbConn in
            // Get the completed stage's sort_order
            let completedOrder = try Int.fetchOne(dbConn, sql: """
                SELECT sort_order FROM job_stages WHERE id = ?
                """, arguments: [stageId]) ?? 0

            // Find the next stage
            let nextStageId: Int64? = try Int64.fetchOne(dbConn, sql: """
                SELECT id FROM job_stages
                WHERE sort_order > ? AND deleted_at IS NULL
                ORDER BY sort_order ASC LIMIT 1
                """, arguments: [completedOrder])

            // Update job's current stage to the next stage (or keep at completed if last)
            try dbConn.execute(sql: """
                UPDATE jobs SET current_stage_id = ?, updated_at = datetime('now')
                WHERE id = ?
                """, arguments: [nextStageId ?? stageId, jobId])

            // If there's a next stage, auto-release held parts for that stage
            if let nextId = nextStageId {
                // Get category IDs for the next stage
                let categoryIds = try Int64.fetchAll(dbConn, sql: """
                    SELECT category_id FROM job_stage_category_map WHERE stage_id = ?
                    """, arguments: [nextId])

                if !categoryIds.isEmpty {
                    // Release JPO line items whose part category matches the next stage
                    let placeholders = categoryIds.map { _ in "?" }.joined(separator: ",")
                    var args = StatementArguments()
                    args += [jobId]
                    for catId in categoryIds { args += [catId] }
                    try dbConn.execute(sql: """
                        UPDATE jpo_line_items
                        SET line_status = 'approved',
                            status_updated_at = datetime('now')
                        WHERE line_status = 'held'
                          AND deleted_at IS NULL
                          AND jpo_id IN (SELECT id FROM job_parts_orders WHERE job_id = ? AND deleted_at IS NULL)
                          AND part_id IN (SELECT id FROM parts WHERE category_id IN (\(placeholders)))
                        """, arguments: args)
                }
            }
        }
    }

    /// Request early release for a held JPO line item — overrides the hold.
    public func requestEarlyRelease(jpoLineId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE jpo_line_items
                SET line_status = 'approved',
                    status_updated_at = datetime('now')
                WHERE id = ? AND line_status = 'held' AND deleted_at IS NULL
                """, arguments: [jpoLineId])
        }
    }

    /// Update which category belongs to which stage.
    public func updateCategoryStageMapping(categoryId: Int64, stageId: Int64?) throws {
        try db.writer.write { dbConn in
            // Remove existing mapping for this category
            try dbConn.execute(sql: """
                DELETE FROM job_stage_category_map WHERE category_id = ?
                """, arguments: [categoryId])

            // Add new mapping if a stage was provided
            if let stageId = stageId {
                try dbConn.execute(sql: """
                    INSERT INTO job_stage_category_map (stage_id, category_id)
                    VALUES (?, ?)
                    """, arguments: [stageId, categoryId])
            }
        }
    }

    /// Get the category→stage mapping for all categories.
    public func getCategoryStageMappings() throws -> [(categoryId: Int64, categoryName: String, stageId: Int64?, stageName: String?)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT pc.id AS category_id, pc.name AS category_name,
                       jscm.stage_id, js.name AS stage_name
                FROM part_categories pc
                LEFT JOIN job_stage_category_map jscm ON jscm.category_id = pc.id
                LEFT JOIN job_stages js ON js.id = jscm.stage_id
                WHERE pc.deleted_at IS NULL
                ORDER BY pc.name ASC
                """)
            return rows.map { row in
                (
                    categoryId: row["category_id"] as Int64? ?? 0,
                    categoryName: row["category_name"] as String? ?? "",
                    stageId: row["stage_id"] as Int64?,
                    stageName: row["stage_name"] as String?
                )
            }
        }
    }

    /// Generate a Purchase Order from an approved JPO. Creates a new PO and links its
    /// line items to the JPO line items, then marks the JPO as "ordered".
    @discardableResult
    public func generatePOFromJPO(jpoId: Int64, supplierId: Int64) throws -> Int64 {
        try db.writer.write { dbConn in
            // Verify JPO exists and is approved
            guard let jpoRow = try Row.fetchOne(
                dbConn,
                sql: "SELECT id, status FROM job_parts_orders WHERE id = ? AND deleted_at IS NULL",
                arguments: [jpoId]
            ) else {
                throw OrdersError.jpoNotFound(jpoId)
            }

            let status: String = jpoRow["status"] ?? ""
            guard status == "approved" else {
                throw OrdersError.invalidStatus("JPO must be approved to generate a PO")
            }

            // Generate PO number (MAX-based to prevent duplicates after deletions)
            let maxNum = try Int.fetchOne(
                dbConn,
                sql: "SELECT COALESCE(MAX(CAST(SUBSTR(po_number, 4) AS INTEGER)), 0) FROM purchase_orders"
            ) ?? 0
            let poNumber = String(format: "PO-%05d", maxNum + 1)

            // Create PO
            try dbConn.execute(
                sql: """
                    INSERT INTO purchase_orders
                    (po_number, supplier_id, status, order_date, created_at, updated_at)
                    VALUES (?, ?, 'draft', date('now'), datetime('now'), datetime('now'))
                    """,
                arguments: [poNumber, supplierId]
            )
            let poId = dbConn.lastInsertedRowID

            // Copy JPO line items to PO line items
            let lines = try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT id, part_id, qty_requested
                    FROM jpo_line_items
                    WHERE jpo_id = ? AND deleted_at IS NULL
                    """,
                arguments: [jpoId]
            )
            for line in lines {
                let partId: Int64 = line["part_id"] ?? 0
                let qty: Int = line["qty_requested"] ?? 1
                let jpoLineId: Int64 = line["id"] ?? 0
                try dbConn.execute(
                    sql: """
                        INSERT INTO po_line_items
                        (po_id, jpo_line_id, part_id, qty_ordered, created_at)
                        VALUES (?, ?, ?, ?, datetime('now'))
                        """,
                    arguments: [poId, jpoLineId, partId, qty]
                )
            }

            // Link PO to JPO
            try? dbConn.execute(
                sql: """
                    INSERT INTO po_jpo_links (po_id, jpo_id, created_at)
                    VALUES (?, ?, datetime('now'))
                    """,
                arguments: [poId, jpoId]
            )

            // Mark JPO as ordered
            try dbConn.execute(
                sql: "UPDATE job_parts_orders SET status = 'ordered', updated_at = datetime('now') WHERE id = ?",
                arguments: [jpoId]
            )

            return poId
        }
    }

    // =========================================================================
    // MARK: - 2. Purchase Order CRUD
    // =========================================================================

    /// List purchase orders with optional status filter.
    public func listPurchaseOrders(
        status: String? = nil,
        limit: Int = 50
    ) throws -> [POListItem] {
        do {
            return try db.writer.read { dbConn -> [POListItem] in
                var whereClauses = ["po.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("po.status = ?")
                    args.append(status)
                }

                args.append(limit)

                let sql = """
                    SELECT po.id, po.po_number, po.status, po.total_cost, po.order_date,
                           COALESCE(s.name, 'Unknown Supplier') AS supplier_name,
                           COALESCE((SELECT COUNT(*) FROM po_line_items pl
                                     WHERE pl.po_id = po.id AND pl.deleted_at IS NULL), 0) AS line_count
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY po.created_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    POListItem(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown Supplier",
                        status: row["status"] ?? "draft",
                        totalCost: row["total_cost"] as Double?,
                        lineCount: row["line_count"] ?? 0,
                        orderDate: row["order_date"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single purchase order by ID with full detail, nested lines, and linked JPO IDs.
    public func getPODetail(id: Int64) throws -> PODetail {
        let result: PODetail? = try db.writer.read { dbConn -> PODetail? in
            let sql = """
                SELECT po.*,
                       COALESCE(s.name, 'Unknown Supplier') AS supplier_name,
                       COALESCE(u.display_name, u.email) AS submitted_by_name
                FROM purchase_orders po
                LEFT JOIN suppliers s ON s.id = po.supplier_id
                LEFT JOIN users u ON u.id = po.submitted_by
                WHERE po.id = ?
                """
            guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [id]) else {
                return nil
            }

            // Fetch PO lines with job info via JPO chain
            let linesSql = """
                SELECT pl.*,
                       p.name AS part_name,
                       j.id AS job_id,
                       COALESCE(j.job_name,
                           CASE WHEN pl.notes LIKE '%forecast%' THEN 'Forecast Restock'
                                WHEN pl.notes LIKE '%wishlist%' THEN 'Wishlist'
                                ELSE 'General Stock'
                           END
                       ) AS job_name,
                       CASE WHEN j.id IS NOT NULL THEN 'job'
                            WHEN pl.notes LIKE '%forecast%' THEN 'forecast'
                            WHEN pl.notes LIKE '%wishlist%' THEN 'wishlist'
                            ELSE 'general'
                       END AS source
                FROM po_line_items pl
                LEFT JOIN parts p ON p.id = pl.part_id
                LEFT JOIN jpo_line_items jli ON jli.id = pl.jpo_line_id
                LEFT JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
                LEFT JOIN jobs j ON j.id = jpo.job_id
                WHERE pl.po_id = ? AND pl.deleted_at IS NULL
                ORDER BY job_name ASC, pl.id ASC
                """
            let lineRows = try Row.fetchAll(dbConn, sql: linesSql, arguments: [id])
            let lines = lineRows.map { lr in
                POLineRow(
                    id: lr["id"] ?? 0,
                    poId: lr["po_id"] ?? 0,
                    jpoLineId: lr["jpo_line_id"] as Int64?,
                    partId: lr["part_id"] as Int64?,
                    partName: lr["part_name"] as String?,
                    description: lr["description"] as String?,
                    quantityOrdered: lr["qty_ordered"] ?? 0,
                    quantityReceived: lr["qty_received"] ?? 0,
                    unitPrice: lr["unit_cost"] as Double?,
                    status: lr["status"] ?? "pending",
                    notes: lr["notes"] as String?,
                    createdAt: lr["created_at"] as String?,
                    jobId: lr["job_id"] as Int64?,
                    jobName: lr["job_name"] as String?,
                    source: lr["source"] as String?
                )
            }

            // Fetch linked JPO IDs
            let linksSql = """
                SELECT jpo_id FROM po_jpo_links
                WHERE po_id = ?
                ORDER BY created_at ASC
                """
            let linkRows = try Row.fetchAll(dbConn, sql: linksSql, arguments: [id])
            let linkedJPOIds: [Int64] = linkRows.compactMap { lr in lr["jpo_id"] as Int64? }

            return PODetail(
                id: row["id"] ?? 0,
                poNumber: row["po_number"] ?? "",
                supplierId: row["supplier_id"] ?? 0,
                supplierName: row["supplier_name"] ?? "Unknown Supplier",
                status: row["status"] ?? "draft",
                orderDate: row["order_date"] as String?,
                expectedDelivery: row["expected_delivery"] as String?,
                actualDelivery: row["actual_delivery"] as String?,
                shippingMethod: row["shipping_method"] as String?,
                trackingNumber: row["tracking_number"] as String?,
                subtotal: row["subtotal"] as Double?,
                taxAmount: row["tax_amount"] as Double?,
                shippingCost: row["shipping_cost"] as Double?,
                totalCost: row["total_cost"] as Double?,
                notes: row["notes"] as String?,
                internalNotes: row["internal_notes"] as String?,
                supplierNotes: row["supplier_notes"] as String?,
                submittedBy: row["submitted_by"] as Int64?,
                submittedByName: row["submitted_by_name"] as String?,
                deletedAt: row["deleted_at"] as String?,
                createdAt: row["created_at"] as String?,
                updatedAt: row["updated_at"] as String?,
                lines: lines,
                linkedJPOIds: linkedJPOIds
            )
        }
        guard let result else { throw OrdersError.purchaseOrderNotFound(id) }
        return result
    }

    /// Create a new purchase order. Returns the inserted row ID.
    @discardableResult
    public func createPurchaseOrder(
        poNumber: String,
        supplierId: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO purchase_orders
                    (po_number, supplier_id, status, notes,
                     order_date, created_at, updated_at)
                    VALUES (?, ?, 'draft', ?, date('now'), datetime('now'), datetime('now'))
                    """,
                arguments: [poNumber, supplierId, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update the status of a purchase order.
    public func updatePOStatus(id: Int64, status: String) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE purchase_orders
                    SET status = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [status, id]
            )
            // Record in status history
            try dbConn.execute(
                sql: """
                    INSERT INTO order_status_history (entity_type, entity_id, old_status, new_status, changed_by, created_at)
                    VALUES ('purchase_order', ?, (SELECT status FROM purchase_orders WHERE id = ?), ?, 1, datetime('now'))
                    """,
                arguments: [id, id, status]
            )
        }
    }

    /// Update the expected delivery date of a purchase order.
    public func updatePOExpectedDelivery(id: Int64, expectedDelivery: String) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE purchase_orders
                    SET expected_delivery = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [expectedDelivery, id]
            )
        }
    }

    /// Soft-delete a draft purchase order.
    public func deletePO(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE purchase_orders
                    SET deleted_at = datetime('now'), updated_at = datetime('now')
                    WHERE id = ? AND status = 'draft'
                    """,
                arguments: [id]
            )
        }
    }

    /// Append a timestamped note to a purchase order's notes field.
    public func addPONote(poId: Int64, note: String, author: String) throws {
        try db.writer.write { dbConn in
            let existing = try String.fetchOne(
                dbConn,
                sql: "SELECT notes FROM purchase_orders WHERE id = ?",
                arguments: [poId]
            ) ?? ""
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let newNote = "\(timestamp) [\(author)]: \(note)"
            let combined = existing.isEmpty ? newNote : "\(existing)\n\(newNote)"
            try dbConn.execute(
                sql: "UPDATE purchase_orders SET notes = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [combined, poId]
            )
        }
    }

    // MARK: - 2b. PO Line Item Editing + Receipt History

    /// Update a draft PO line item's quantity and/or unit price.
    /// Only works on draft POs — throws if the PO is not in draft status.
    public func updatePOLineItem(lineId: Int64, quantity: Int, unitPrice: Double?) throws {
        try db.writer.write { dbConn in
            // Verify the parent PO is in draft status
            let statusCheck = try String.fetchOne(dbConn, sql: """
                SELECT po.status FROM purchase_orders po
                JOIN po_line_items li ON li.po_id = po.id
                WHERE li.id = ?
                """, arguments: [lineId])
            guard statusCheck == "draft" else {
                throw OrdersError.invalidStatusTransition(entity: "PO line", from: statusCheck ?? "unknown", to: "edit")
            }
            var setClauses = ["qty_ordered = ?"]
            var args: [DatabaseValueConvertible?] = [quantity]
            if let price = unitPrice {
                setClauses.append("unit_cost = ?")
                args.append(price)
            }
            args.append(lineId)
            try dbConn.execute(
                sql: "UPDATE po_line_items SET \(setClauses.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(args)
            )
        }
    }

    /// Add a new line item to an existing PO.
    @discardableResult
    public func addPOLineItem(
        poId: Int64,
        partId: Int64,
        quantity: Int,
        unitPrice: Double?
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO po_line_items
                    (po_id, part_id, qty_ordered, unit_cost, status, created_at)
                    VALUES (?, ?, ?, ?, 'pending', datetime('now'))
                    """,
                arguments: [poId, partId, quantity, unitPrice]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// A receipt batch from order status history.
    public struct ReceiptBatch: Sendable, Identifiable {
        public let id: Int64
        public let receivedDate: String
        public let receivedBy: String?
        public let itemCount: Int
        public let totalReceived: Int
    }

    /// Get receipt history from order_status_history for a PO (transitions to partial/received).
    public func getReceiptHistory(poId: Int64) throws -> [ReceiptBatch] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT osh.id, osh.created_at, osh.new_status,
                       COALESCE(u.display_name, u.email, 'System') AS changed_by,
                       (SELECT COUNT(*) FROM po_line_items li
                        WHERE li.po_id = ? AND li.qty_received > 0 AND li.deleted_at IS NULL) AS item_count,
                       (SELECT COALESCE(SUM(li.qty_received), 0) FROM po_line_items li
                        WHERE li.po_id = ? AND li.deleted_at IS NULL) AS total_received
                FROM order_status_history osh
                LEFT JOIN users u ON u.id = osh.changed_by
                WHERE osh.entity_type = 'purchase_order'
                  AND osh.entity_id = ?
                  AND osh.new_status IN ('partial', 'received')
                ORDER BY osh.created_at ASC
                """, arguments: [poId, poId, poId])
            return rows.map { row in
                ReceiptBatch(
                    id: row["id"] ?? 0,
                    receivedDate: row["created_at"] ?? "",
                    receivedBy: row["changed_by"] as String?,
                    itemCount: row["item_count"] ?? 0,
                    totalReceived: row["total_received"] ?? 0
                )
            }
        }
    }

    // MARK: - Receipt History Entries (from receiving_sessions)

    /// A detailed receipt history entry sourced from actual receiving sessions.
    public struct ReceiptHistoryEntry: Identifiable, Sendable, Codable {
        public let id: Int64
        public let sessionDate: String
        public let receivedBy: String
        public let totalItemsReceived: Int
        public let hasDiscrepancies: Bool
        public let notes: String?
        public let status: String

        public init(
            id: Int64, sessionDate: String, receivedBy: String,
            totalItemsReceived: Int, hasDiscrepancies: Bool,
            notes: String?, status: String
        ) {
            self.id = id
            self.sessionDate = sessionDate
            self.receivedBy = receivedBy
            self.totalItemsReceived = totalItemsReceived
            self.hasDiscrepancies = hasDiscrepancies
            self.notes = notes
            self.status = status
        }
    }

    /// A single item within a receipt history entry, showing per-line detail.
    public struct ReceiptHistoryItem: Identifiable, Sendable, Codable {
        public let id: Int64
        public let partName: String
        public let partCode: String?
        public let expectedQty: Int
        public let receivedQty: Int
        public let hasDiscrepancy: Bool
        public let notes: String?

        public init(
            id: Int64, partName: String, partCode: String?,
            expectedQty: Int, receivedQty: Int,
            hasDiscrepancy: Bool, notes: String?
        ) {
            self.id = id
            self.partName = partName
            self.partCode = partCode
            self.expectedQty = expectedQty
            self.receivedQty = receivedQty
            self.hasDiscrepancy = hasDiscrepancy
            self.notes = notes
        }
    }

    /// Get receipt history entries from receiving_sessions for a PO.
    /// Returns completed sessions with summary info including discrepancy detection.
    public func getReceiptHistoryEntries(poId: Int64) throws -> [ReceiptHistoryEntry] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT rs.id,
                       rs.created_at AS session_date,
                       COALESCE(u.display_name, u.email, 'Unknown') AS received_by,
                       rs.notes,
                       rs.status,
                       COALESCE(
                           (SELECT SUM(rsi.received_qty)
                            FROM receiving_session_items rsi
                            WHERE rsi.session_id = rs.id AND rsi.deleted_at IS NULL), 0
                       ) AS total_items_received,
                       COALESCE(
                           (SELECT COUNT(*)
                            FROM receiving_session_items rsi
                            WHERE rsi.session_id = rs.id
                              AND rsi.deleted_at IS NULL
                              AND rsi.received_qty != rsi.expected_qty), 0
                       ) AS discrepancy_count
                FROM receiving_sessions rs
                LEFT JOIN users u ON u.id = rs.started_by
                WHERE rs.po_id = ?
                  AND rs.deleted_at IS NULL
                  AND rs.status = 'completed'
                ORDER BY rs.created_at DESC
                """, arguments: [poId])
            return rows.map { row in
                ReceiptHistoryEntry(
                    id: row["id"] ?? 0,
                    sessionDate: row["session_date"] ?? "",
                    receivedBy: row["received_by"] ?? "Unknown",
                    totalItemsReceived: row["total_items_received"] ?? 0,
                    hasDiscrepancies: (row["discrepancy_count"] as Int? ?? 0) > 0,
                    notes: row["notes"] as String?,
                    status: row["status"] ?? "completed"
                )
            }
        }
    }

    /// Get per-item details for a specific receiving session.
    public func getReceiptHistoryItems(sessionId: Int64) throws -> [ReceiptHistoryItem] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT rsi.id,
                       COALESCE(p.name, 'Unknown Part') AS part_name,
                       p.code AS part_code,
                       rsi.expected_qty,
                       rsi.received_qty,
                       rsi.notes
                FROM receiving_session_items rsi
                LEFT JOIN po_line_items pli ON pli.id = rsi.po_line_id
                LEFT JOIN parts p ON p.id = pli.part_id
                WHERE rsi.session_id = ? AND rsi.deleted_at IS NULL
                ORDER BY p.name
                """, arguments: [sessionId])
            return rows.map { row in
                let expected: Int = row["expected_qty"] ?? 0
                let received: Int = row["received_qty"] ?? 0
                return ReceiptHistoryItem(
                    id: row["id"] ?? 0,
                    partName: row["part_name"] ?? "Unknown Part",
                    partCode: row["part_code"] as String?,
                    expectedQty: expected,
                    receivedQty: received,
                    hasDiscrepancy: expected != received,
                    notes: row["notes"] as String?
                )
            }
        }
    }

    // MARK: - 2c. Parts Order Management

    /// A part across POs for the parts management page.
    public struct PartsManagementRow: Sendable, Identifiable {
        public let id: Int64          // po_line_items.id
        public let poId: Int64
        public let poNumber: String
        public let poStatus: String
        public let jobId: Int64?
        public let jobName: String?
        public let partId: Int64?
        public let partName: String
        public let partCode: String?
        public let quantityOrdered: Int
        public let quantityReceived: Int
        public let unitPrice: Double?
        public let lineStatus: String  // "pending", "received", "backorder", "cancelled"
        public let expectedDelivery: String?
        public let orderDate: String?
    }

    /// Get all parts across all POs for a specific supplier.
    public func getPartsForSupplier(supplierId: Int64, poStatuses: [String]? = nil) throws -> [PartsManagementRow] {
        try db.writer.read { dbConn in
            var whereClauses = ["po.supplier_id = ?", "po.deleted_at IS NULL", "li.deleted_at IS NULL"]
            var args: [DatabaseValueConvertible] = [supplierId]

            if let statuses = poStatuses, !statuses.isEmpty {
                let placeholders = statuses.map { _ in "?" }.joined(separator: ", ")
                whereClauses.append("po.status IN (\(placeholders))")
                args.append(contentsOf: statuses)
            }

            let sql = """
                SELECT li.id, li.po_id, po.po_number, po.status AS po_status,
                       li.part_id, COALESCE(p.name, 'Item') AS part_name,
                       p.code AS part_code,
                       li.qty_ordered, li.qty_received, li.unit_cost,
                       li.status AS line_status,
                       po.expected_delivery, po.order_date,
                       jpo.job_id, j.job_name AS job_name
                FROM po_line_items li
                JOIN purchase_orders po ON po.id = li.po_id
                LEFT JOIN parts p ON p.id = li.part_id
                LEFT JOIN jpo_line_items jli ON jli.id = li.jpo_line_id
                LEFT JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
                LEFT JOIN jobs j ON j.id = jpo.job_id
                WHERE \(whereClauses.joined(separator: " AND "))
                ORDER BY po.po_number ASC, li.id ASC
                """

            return try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args)).map { row in
                PartsManagementRow(
                    id: row["id"],
                    poId: row["po_id"],
                    poNumber: row["po_number"],
                    poStatus: row["po_status"],
                    jobId: row["job_id"],
                    jobName: row["job_name"],
                    partId: row["part_id"],
                    partName: row["part_name"] ?? "Item",
                    partCode: row["part_code"],
                    quantityOrdered: row["qty_ordered"] ?? 0,
                    quantityReceived: row["qty_received"] ?? 0,
                    unitPrice: row["unit_cost"] as Double?,
                    lineStatus: row["line_status"] ?? "pending",
                    expectedDelivery: row["expected_delivery"],
                    orderDate: row["order_date"]
                )
            }
        }
    }

    /// Get list of suppliers that have active POs.
    public func getSuppliersWithActivePOs() throws -> [(id: Int64, name: String, poCount: Int)] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT s.id, s.name, COUNT(DISTINCT po.id) AS po_count
                FROM suppliers s
                JOIN purchase_orders po ON po.supplier_id = s.id
                WHERE po.deleted_at IS NULL AND po.status NOT IN ('received', 'cancelled')
                GROUP BY s.id
                ORDER BY s.name ASC
                """)
            return rows.map { (id: $0["id"] as Int64, name: $0["name"] as String, poCount: $0["po_count"] as Int) }
        }
    }

    // =========================================================================
    // MARK: - 3. Returns
    // =========================================================================

    /// List returns with optional status filter.
    public func listReturns(
        status: String? = nil,
        limit: Int = 50
    ) throws -> [ReturnListItem] {
        do {
            return try db.writer.read { dbConn -> [ReturnListItem] in
                var whereClauses = ["r.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let status, !status.isEmpty {
                    whereClauses.append("r.status = ?")
                    args.append(status)
                }

                args.append(limit)

                let sql = """
                    SELECT r.id, r.return_type, r.status, r.reason,
                           r.credit_amount, r.created_at,
                           s.name AS supplier_name,
                           COALESCE((SELECT COUNT(*) FROM return_line_items rli
                                     WHERE rli.return_id = r.id AND rli.deleted_at IS NULL), 0) AS line_count
                    FROM returns r
                    LEFT JOIN suppliers s ON s.id = r.supplier_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY r.created_at DESC
                    LIMIT ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    ReturnListItem(
                        id: row["id"] ?? 0,
                        returnType: row["return_type"] ?? "supplier",
                        status: row["status"] ?? "pending",
                        supplierName: row["supplier_name"] as String?,
                        reason: row["reason"] as String?,
                        lineCount: row["line_count"] ?? 0,
                        creditAmount: row["credit_amount"] as Double?,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new return.
    @discardableResult
    public func createReturn(
        returnType: String,
        reason: String,
        supplierId: Int64? = nil,
        poId: Int64? = nil,
        jobId: Int64? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // MAX-based to prevent duplicates after deletions
            let maxNum = try Int.fetchOne(
                dbConn,
                sql: "SELECT COALESCE(MAX(CAST(SUBSTR(return_number, 5) AS INTEGER)), 0) FROM returns"
            ) ?? 0
            let returnNumber = String(format: "RET-%05d", maxNum + 1)

            try dbConn.execute(
                sql: """
                    INSERT INTO returns
                    (return_number, return_type, reason, supplier_id, po_id, job_id,
                     status, initiated_by, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'pending', 1, datetime('now'), datetime('now'))
                    """,
                arguments: [returnNumber, returnType, reason, supplierId, poId, jobId]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update the status of a return.
    public func updateReturnStatus(returnId: Int64, status: String) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE returns SET status = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [status, returnId]
            )
        }
    }

    // =========================================================================
    // MARK: - 4. Order Statistics
    // =========================================================================

    /// Get aggregate order statistics for the dashboard.
    public func getOrderStats() throws -> OrderStats {
        let pendingJPOs = try safeCount(
            sql: "SELECT COUNT(*) FROM job_parts_orders WHERE status IN ('draft', 'pending', 'submitted') AND deleted_at IS NULL"
        )

        let activePOs = try safeCount(
            sql: "SELECT COUNT(*) FROM purchase_orders WHERE status IN ('draft', 'submitted', 'ordered', 'partial') AND deleted_at IS NULL"
        )

        let pendingReturns = try safeCount(
            sql: "SELECT COUNT(*) FROM returns WHERE status IN ('pending', 'requested', 'approved') AND deleted_at IS NULL"
        )

        let totalSpend30Days = try safeCountDouble(
            sql: """
                SELECT COALESCE(SUM(total_cost), 0)
                FROM purchase_orders
                WHERE order_date >= date('now', '-30 days')
                  AND status NOT IN ('cancelled', 'draft')
                  AND deleted_at IS NULL
                """
        )

        return OrderStats(
            pendingJPOs: pendingJPOs,
            activePOs: activePOs,
            pendingReturns: pendingReturns,
            totalSpend30Days: totalSpend30Days
        )
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) or SELECT COALESCE(SUM(...), 0) query returning an Int.
    /// Returns 0 if the table does not exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Execute a SELECT COALESCE(SUM(...), 0) query returning a Double.
    /// Returns 0.0 if the table does not exist.
    private func safeCountDouble(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Double {
        do {
            return try db.writer.read { dbConn in
                try Double.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0.0
            }
        } catch {
            if isTableNotFoundError(error) { return 0.0 }
            throw error
        }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }
}
