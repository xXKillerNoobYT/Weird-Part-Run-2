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

    public enum OrdersError: Error, Sendable {
        case jpoNotFound(Int64)
        case purchaseOrderNotFound(Int64)
        case returnNotFound(Int64)
        case invalidStatusTransition(entity: String, from: String, to: String)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A JPO row for list views with summary counts.
    public struct JPOListItem: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let requestedByName: String
        public let status: String
        public let priority: String
        public let lineCount: Int
        public let createdAt: String?

        public init(
            id: Int64, jobName: String, requestedByName: String,
            status: String, priority: String, lineCount: Int, createdAt: String?
        ) {
            self.id = id
            self.jobName = jobName
            self.requestedByName = requestedByName
            self.status = status
            self.priority = priority
            self.lineCount = lineCount
            self.createdAt = createdAt
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
        public let lines: [JPOLineRow]

        public init(
            id: Int64, jobId: Int64, jobName: String,
            requestedBy: Int64, requestedByName: String,
            status: String, priority: String, notes: String?,
            approvedBy: Int64?, approvedByName: String?, approvedAt: String?,
            deletedAt: String?, createdAt: String?, updatedAt: String?,
            lines: [JPOLineRow]
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
        public let createdAt: String?

        public init(
            id: Int64, jpoId: Int64, partId: Int64?, partName: String?,
            description: String?, quantity: Int, unitPrice: Double?,
            notes: String?, priority: String, createdAt: String?
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

    /// A single PO line with part name.
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

        public init(
            id: Int64, poId: Int64, jpoLineId: Int64?, partId: Int64?,
            partName: String?, description: String?,
            quantityOrdered: Int, quantityReceived: Int, unitPrice: Double?,
            status: String, notes: String?, createdAt: String?
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
                    SELECT jp.id, jp.status, jp.priority, jp.created_at,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS requested_by_name,
                           COALESCE((SELECT COUNT(*) FROM jpo_lines jl
                                     WHERE jl.jpo_id = jp.id AND jl.deleted_at IS NULL), 0) AS line_count
                    FROM jpos jp
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
                        jobName: row["job_name"] ?? "Unknown Job",
                        requestedByName: row["requested_by_name"] ?? "Unknown",
                        status: row["status"] ?? "draft",
                        priority: row["priority"] ?? "normal",
                        lineCount: row["line_count"] ?? 0,
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
                FROM jpos jp
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
                FROM jpo_lines jl
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
                    description: lr["description"] as String?,
                    quantity: lr["quantity"] ?? 0,
                    unitPrice: lr["unit_price"] as Double?,
                    notes: lr["notes"] as String?,
                    priority: lr["priority"] ?? "normal",
                    createdAt: lr["created_at"] as String?
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
                lines: lines
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
            try dbConn.execute(
                sql: """
                    INSERT INTO jpos
                    (job_id, requested_by, status, priority, notes,
                     created_at, updated_at)
                    VALUES (?, ?, 'draft', ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, requestedBy, priority, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update the status of a JPO and record the transition in status_history.
    public func updateJPOStatus(id: Int64, status: String) throws {
        try db.writer.write { dbConn in
            // Verify the JPO exists
            guard let row = try Row.fetchOne(
                dbConn,
                sql: "SELECT id, status FROM jpos WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            ) else {
                throw OrdersError.jpoNotFound(id)
            }

            let oldStatus: String = row["status"] ?? "draft"

            // Update the JPO status
            try dbConn.execute(
                sql: """
                    UPDATE jpos
                    SET status = ?, updated_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [status, id]
            )

            // Record status transition in history
            try dbConn.execute(
                sql: """
                    INSERT INTO status_history
                    (entity_type, entity_id, old_status, new_status, created_at)
                    VALUES ('jpo', ?, ?, ?, datetime('now'))
                    """,
                arguments: [id, oldStatus, status]
            )
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
                           COALESCE((SELECT COUNT(*) FROM po_lines pl
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

            // Fetch PO lines
            let linesSql = """
                SELECT pl.*,
                       p.name AS part_name
                FROM po_lines pl
                LEFT JOIN parts p ON p.id = pl.part_id
                WHERE pl.po_id = ? AND pl.deleted_at IS NULL
                ORDER BY pl.created_at ASC
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
                    quantityOrdered: lr["quantity_ordered"] ?? 0,
                    quantityReceived: lr["quantity_received"] ?? 0,
                    unitPrice: lr["unit_price"] as Double?,
                    status: lr["status"] ?? "pending",
                    notes: lr["notes"] as String?,
                    createdAt: lr["created_at"] as String?
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

    // =========================================================================
    // MARK: - 4. Order Statistics
    // =========================================================================

    /// Get aggregate order statistics for the dashboard.
    public func getOrderStats() throws -> OrderStats {
        let pendingJPOs = try safeCount(
            sql: "SELECT COUNT(*) FROM jpos WHERE status IN ('draft', 'pending', 'submitted') AND deleted_at IS NULL"
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
