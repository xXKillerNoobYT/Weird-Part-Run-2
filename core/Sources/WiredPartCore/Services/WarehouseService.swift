import Foundation
import GRDB

/// Warehouse Service — full CRUD for stock, movements, staging, receiving,
/// returns, audit, and trailers.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Warehouse & Movements feature area (Phase 6)
public final class WarehouseService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum WarehouseError: Error, Sendable {
        case invalidMovementPath(from: String, to: String)
        case insufficientStock(available: Int, requested: Int)
        case partNotFound(Int64)
        case sessionNotFound(Int64)
        case sessionAlreadyCompleted
        case trailerNotFound(Int64)
    }

    // =========================================================================
    // MARK: - 1. Dashboard KPIs
    // =========================================================================

    /// Warehouse dashboard KPI values.
    public struct WarehouseKPI: Sendable {
        public let totalStock: Int
        public let stockHealthPercent: Int
        public let shortfallCount: Int
        public let todayMovements: Int

        public init(totalStock: Int, stockHealthPercent: Int, shortfallCount: Int, todayMovements: Int) {
            self.totalStock = totalStock
            self.stockHealthPercent = stockHealthPercent
            self.shortfallCount = shortfallCount
            self.todayMovements = todayMovements
        }
    }

    /// Dashboard KPI summary with activity and pending tasks.
    public struct DashboardKPIs: Sendable {
        public let kpis: WarehouseKPI
        public let pendingStagingCount: Int
        public let activeReceivingSessions: Int
        public let pendingReturns: Int
    }

    /// A single recent activity entry for the dashboard feed.
    public struct ActivityEntry: Sendable {
        public let id: Int64
        public let description: String
        public let performedByName: String
        public let createdAt: String
    }

    /// Fetch warehouse dashboard KPIs.
    public func getWarehouseKPIs() throws -> WarehouseKPI {
        let totalStock = try safeCount(
            sql: "SELECT COALESCE(SUM(qty), 0) FROM stock WHERE deleted_at IS NULL"
        )

        let shortfallCount = try safeCount(
            sql: """
                SELECT COUNT(*) FROM parts p
                WHERE p.deleted_at IS NULL
                  AND p.min_stock_level > 0
                  AND (
                    SELECT COALESCE(SUM(s.qty), 0)
                    FROM stock s
                    WHERE s.part_id = p.id AND s.deleted_at IS NULL
                  ) < p.min_stock_level
                """
        )

        let totalWithMin = try safeCount(
            sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL AND min_stock_level > 0"
        )

        let healthPercent: Int
        if totalWithMin > 0 {
            healthPercent = max(0, min(100, ((totalWithMin - shortfallCount) * 100) / totalWithMin))
        } else {
            healthPercent = 100
        }

        let todayMovements = try safeCount(
            sql: """
                SELECT COUNT(*) FROM stock_movements
                WHERE date(created_at) = date('now')
                  AND deleted_at IS NULL
                """
        )

        return WarehouseKPI(
            totalStock: totalStock,
            stockHealthPercent: healthPercent,
            shortfallCount: shortfallCount,
            todayMovements: todayMovements
        )
    }

    /// Fetch full dashboard KPIs including pending tasks.
    public func getDashboardKPIs() throws -> DashboardKPIs {
        let kpis = try getWarehouseKPIs()

        let pendingStaging = try safeCount(
            sql: "SELECT COUNT(*) FROM pulled_staging_tags WHERE deleted_at IS NULL"
        )

        let activeReceiving = try safeCount(
            sql: "SELECT COUNT(*) FROM receiving_sessions WHERE status = 'in_progress' AND deleted_at IS NULL"
        )

        let pendingReturns = try safeCount(
            sql: """
                SELECT COUNT(*) FROM stock_movements
                WHERE movement_type = 'return'
                  AND date(created_at) = date('now')
                  AND deleted_at IS NULL
                """
        )

        return DashboardKPIs(
            kpis: kpis,
            pendingStagingCount: pendingStaging,
            activeReceivingSessions: activeReceiving,
            pendingReturns: pendingReturns
        )
    }

    /// Get recent activity entries for the dashboard feed.
    public func getRecentActivity(limit: Int = 20) throws -> [ActivityEntry] {
        do {
            return try db.writer.read { dbConn -> [ActivityEntry] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT sm.id, sm.movement_type, sm.qty,
                               p.name AS part_name,
                               COALESCE(u.display_name, u.email, 'Unknown') AS performed_by_name,
                               sm.created_at,
                               sm.from_location_type, sm.to_location_type
                        FROM stock_movements sm
                        LEFT JOIN parts p ON p.id = sm.part_id
                        LEFT JOIN users u ON u.id = sm.performed_by
                        WHERE sm.deleted_at IS NULL
                        ORDER BY sm.created_at DESC
                        LIMIT ?
                        """,
                    arguments: [limit]
                )

                return rows.map { row in
                    let partName = (row["part_name"] as String?) ?? "Unknown Part"
                    let qty: Int = row["qty"] ?? 0
                    let moveType = (row["movement_type"] as String?) ?? "transfer"
                    let fromType = (row["from_location_type"] as String?) ?? ""
                    let toType = (row["to_location_type"] as String?) ?? ""
                    let desc = "\(moveType.capitalized): \(qty)× \(partName) (\(fromType) → \(toType))"

                    return ActivityEntry(
                        id: row["id"] ?? 0,
                        description: desc,
                        performedByName: row["performed_by_name"] ?? "Unknown",
                        createdAt: row["created_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Inventory Grid
    // =========================================================================

    /// Inventory item for the grid view.
    public struct InventoryItem: Sendable {
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let categoryName: String?
        public let totalQty: Int
        public let minStock: Int
        public let maxStock: Int
        public let locationCount: Int
        public let status: String  // "ok", "low", "critical", "overstocked"
    }

    /// Fetch inventory grid with stock status.
    public func getInventoryGrid(
        search: String? = nil,
        statusFilter: String? = nil,
        limit: Int = 200,
        offset: Int = 0
    ) throws -> [InventoryItem] {
        do {
            return try db.writer.read { dbConn -> [InventoryItem] in
                var whereClauses = ["p.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                }

                let sql = """
                    SELECT p.id, p.name, p.code,
                           pc.name AS category_name,
                           COALESCE(p.min_stock_level, 0) AS min_stock,
                           COALESCE(p.max_stock_level, 0) AS max_stock,
                           COALESCE(sq.total_qty, 0) AS total_qty,
                           COALESCE(sq.loc_count, 0) AS loc_count
                    FROM parts p
                    LEFT JOIN part_categories pc ON pc.id = p.category_id
                    LEFT JOIN (
                        SELECT part_id,
                               SUM(qty) AS total_qty,
                               COUNT(DISTINCT location_type || '-' || location_id) AS loc_count
                        FROM stock
                        WHERE deleted_at IS NULL AND qty > 0
                        GROUP BY part_id
                    ) sq ON sq.part_id = p.id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY p.name ASC
                    LIMIT ? OFFSET ?
                    """

                args.append(limit)
                args.append(offset)

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                var items = rows.map { row -> InventoryItem in
                    let totalQty: Int = row["total_qty"] ?? 0
                    let minStock: Int = row["min_stock"] ?? 0
                    let maxStock: Int = row["max_stock"] ?? 0

                    let status: String
                    if minStock > 0 && totalQty <= 0 {
                        status = "critical"
                    } else if minStock > 0 && totalQty < minStock {
                        status = "low"
                    } else if maxStock > 0 && totalQty > maxStock {
                        status = "overstocked"
                    } else {
                        status = "ok"
                    }

                    return InventoryItem(
                        partId: row["id"] ?? 0,
                        partName: row["name"] ?? "",
                        partCode: row["code"] as String?,
                        categoryName: row["category_name"] as String?,
                        totalQty: totalQty,
                        minStock: minStock,
                        maxStock: maxStock,
                        locationCount: row["loc_count"] ?? 0,
                        status: status
                    )
                }

                // Apply status filter after computation
                if let statusFilter, !statusFilter.isEmpty {
                    items = items.filter { $0.status == statusFilter }
                }

                return items
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Stock Movements
    // =========================================================================

    /// Valid movement paths: (from_location_type, to_location_type).
    private static let validPaths: Set<String> = [
        "warehouse→pulled",
        "pulled→truck", "pulled→trailer",
        "warehouse→truck", "warehouse→trailer",
        "truck→trailer", "trailer→truck",
        "truck→job", "trailer→job",
        "job→truck", "job→trailer",
        "truck→warehouse", "trailer→warehouse",
        "pulled→warehouse",
        "warehouse→job",
    ]

    /// Paths that require a photo.
    private static let photoRequiredPaths: Set<String> = [
        "truck→job", "trailer→job",
        "job→truck", "job→trailer",
    ]

    /// A single movement row enriched with the part name for display.
    public struct MovementRow: Sendable {
        public let id: Int64
        public let partId: Int64
        public let partName: String
        public let qty: Int
        public let fromLocationType: String?
        public let fromLocationId: Int64?
        public let toLocationType: String?
        public let toLocationId: Int64?
        public let movementType: String
        public let reason: String?
        public let notes: String?
        public let performedBy: Int64
        public let performedByName: String?
        public let createdAt: String?

        public init(
            id: Int64, partId: Int64, partName: String, qty: Int,
            fromLocationType: String?, fromLocationId: Int64?,
            toLocationType: String?, toLocationId: Int64?,
            movementType: String, reason: String?, notes: String?,
            performedBy: Int64, performedByName: String?, createdAt: String?
        ) {
            self.id = id
            self.partId = partId
            self.partName = partName
            self.qty = qty
            self.fromLocationType = fromLocationType
            self.fromLocationId = fromLocationId
            self.toLocationType = toLocationType
            self.toLocationId = toLocationId
            self.movementType = movementType
            self.reason = reason
            self.notes = notes
            self.performedBy = performedBy
            self.performedByName = performedByName
            self.createdAt = createdAt
        }
    }

    /// Movement validation result.
    public struct ValidationResult: Sendable {
        public let isValid: Bool
        public let errors: [String]
        public let photoRequired: Bool
    }

    /// Movement preview line for confirmation.
    public struct PreviewLine: Sendable {
        public let partName: String
        public let qty: Int
        public let fromLabel: String
        public let toLabel: String
        public let movementType: String
    }

    /// Validate a proposed movement.
    public func validateMovement(
        partId: Int64,
        qty: Int,
        fromLocationType: String,
        fromLocationId: Int64,
        toLocationType: String,
        toLocationId: Int64
    ) throws -> ValidationResult {
        var errors: [String] = []

        // Check path validity
        let pathKey = "\(fromLocationType)→\(toLocationType)"
        if !Self.validPaths.contains(pathKey) {
            errors.append("Invalid path: \(fromLocationType) → \(toLocationType)")
        }

        // Check quantity
        if qty <= 0 {
            errors.append("Quantity must be greater than zero")
        }

        // Check source stock (skip for external sources like 'pulled')
        if fromLocationType != "pulled" {
            let available = try getStockQty(
                partId: partId,
                locationType: fromLocationType,
                locationId: fromLocationId
            )
            if available < qty {
                errors.append("Insufficient stock: \(available) available, \(qty) requested")
            }
        }

        let photoRequired = Self.photoRequiredPaths.contains(pathKey)

        return ValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            photoRequired: photoRequired
        )
    }

    /// Generate a preview for a proposed movement.
    public func previewMovement(
        partId: Int64,
        qty: Int,
        fromLocationType: String,
        fromLocationId: Int64,
        toLocationType: String,
        toLocationId: Int64
    ) throws -> PreviewLine {
        let partName: String = try db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: "SELECT name FROM parts WHERE id = ? AND deleted_at IS NULL",
                arguments: [partId]
            ) ?? "Unknown Part"
        }

        let movementType = Self.determineMovementType(from: fromLocationType, to: toLocationType)

        return PreviewLine(
            partName: partName,
            qty: qty,
            fromLabel: Self.locationDisplayName(type: fromLocationType, id: fromLocationId),
            toLabel: Self.locationDisplayName(type: toLocationType, id: toLocationId),
            movementType: movementType
        )
    }

    /// List recent movements with part name join, optionally filtered by type and search.
    public func listMovements(
        search: String? = nil,
        movementType: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) throws -> [MovementRow] {
        do {
            return try db.writer.read { dbConn -> [MovementRow] in
                var whereClauses = ["sm.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                }
                if let movementType, !movementType.isEmpty {
                    whereClauses.append("sm.movement_type = ?")
                    args.append(movementType)
                }

                args.append(limit)
                args.append(offset)

                let sql = """
                    SELECT sm.*,
                           p.name AS part_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS performed_by_name
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id
                    LEFT JOIN users u ON u.id = sm.performed_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY sm.created_at DESC
                    LIMIT ? OFFSET ?
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    MovementRow(
                        id: row["id"] as Int64,
                        partId: row["part_id"] as Int64,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        qty: row["qty"] as Int,
                        fromLocationType: row["from_location_type"] as String?,
                        fromLocationId: row["from_location_id"] as Int64?,
                        toLocationType: row["to_location_type"] as String?,
                        toLocationId: row["to_location_id"] as Int64?,
                        movementType: row["movement_type"] as String,
                        reason: row["reason"] as String?,
                        notes: row["notes"] as String?,
                        performedBy: row["performed_by"] as Int64,
                        performedByName: row["performed_by_name"] as String?,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Fetch a single movement by ID with part name and performer name.
    public func getMovement(id: Int64) throws -> MovementRow? {
        try db.writer.read { dbConn -> MovementRow? in
            let sql = """
                SELECT sm.*,
                       p.name AS part_name,
                       COALESCE(u.display_name, u.email, 'Unknown') AS performed_by_name
                FROM stock_movements sm
                LEFT JOIN parts p ON p.id = sm.part_id
                LEFT JOIN users u ON u.id = sm.performed_by
                WHERE sm.id = ? AND sm.deleted_at IS NULL
                """
            guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [id]) else {
                return nil
            }
            return MovementRow(
                id: row["id"] as Int64,
                partId: row["part_id"] as Int64,
                partName: (row["part_name"] as String?) ?? "Unknown Part",
                qty: row["qty"] as Int,
                fromLocationType: row["from_location_type"] as String?,
                fromLocationId: row["from_location_id"] as Int64?,
                toLocationType: row["to_location_type"] as String?,
                toLocationId: row["to_location_id"] as Int64?,
                movementType: row["movement_type"] as String,
                reason: row["reason"] as String?,
                notes: row["notes"] as String?,
                performedBy: row["performed_by"] as Int64,
                performedByName: row["performed_by_name"] as String?,
                createdAt: row["created_at"] as String?
            )
        }
    }

    /// Record a new stock movement and adjust stock accordingly.
    ///
    /// - Returns: The new movement's row ID.
    @discardableResult
    public func createMovement(
        partId: Int64,
        qty: Int,
        fromLocationType: String?,
        fromLocationId: Int64?,
        toLocationType: String?,
        toLocationId: Int64?,
        movementType: String,
        reason: String? = nil,
        notes: String? = nil,
        performedBy: Int64,
        jobId: Int64? = nil,
        photoPath: String? = nil,
        referenceNumber: String? = nil,
        unitCostAtMove: Double? = nil,
        unitSellAtMove: Double? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO stock_movements
                    (part_id, qty, from_location_type, from_location_id,
                     to_location_type, to_location_id, movement_type,
                     reason, notes, performed_by, job_id, photo_path,
                     reference_number, unit_cost_at_move, unit_sell_at_move,
                     created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [partId, qty, fromLocationType, fromLocationId,
                            toLocationType, toLocationId, movementType,
                            reason, notes, performedBy, jobId, photoPath,
                            referenceNumber, unitCostAtMove, unitSellAtMove]
            )
            let movementId = dbConn.lastInsertedRowID

            // Decrement source stock
            if let fromType = fromLocationType, let fromId = fromLocationId {
                try dbConn.execute(
                    sql: """
                        UPDATE stock SET qty = qty - ?, updated_at = datetime('now')
                        WHERE part_id = ? AND location_type = ? AND location_id = ?
                          AND deleted_at IS NULL
                        """,
                    arguments: [qty, partId, fromType, fromId]
                )
            }

            // Increment destination stock
            if let toType = toLocationType, let toId = toLocationId {
                try dbConn.execute(
                    sql: """
                        UPDATE stock SET qty = qty + ?, updated_at = datetime('now')
                        WHERE part_id = ? AND location_type = ? AND location_id = ?
                          AND deleted_at IS NULL
                        """,
                    arguments: [qty, partId, toType, toId]
                )
                if dbConn.changesCount == 0 {
                    try dbConn.execute(
                        sql: """
                            INSERT INTO stock (part_id, location_type, location_id, qty, updated_at)
                            VALUES (?, ?, ?, ?, datetime('now'))
                            """,
                        arguments: [partId, toType, toId, qty]
                    )
                }
            }

            return movementId
        }
    }

    /// Execute a validated movement with automatic type determination.
    @discardableResult
    public func executeMovement(
        partId: Int64,
        qty: Int,
        fromLocationType: String,
        fromLocationId: Int64,
        toLocationType: String,
        toLocationId: Int64,
        reason: String? = nil,
        notes: String? = nil,
        performedBy: Int64,
        jobId: Int64? = nil,
        photoPath: String? = nil
    ) throws -> Int64 {
        let validation = try validateMovement(
            partId: partId, qty: qty,
            fromLocationType: fromLocationType, fromLocationId: fromLocationId,
            toLocationType: toLocationType, toLocationId: toLocationId
        )

        guard validation.isValid else {
            throw WarehouseError.invalidMovementPath(from: fromLocationType, to: toLocationType)
        }

        let movementType = Self.determineMovementType(from: fromLocationType, to: toLocationType)

        return try createMovement(
            partId: partId, qty: qty,
            fromLocationType: fromLocationType, fromLocationId: fromLocationId,
            toLocationType: toLocationType, toLocationId: toLocationId,
            movementType: movementType, reason: reason, notes: notes,
            performedBy: performedBy, jobId: jobId, photoPath: photoPath
        )
    }

    // =========================================================================
    // MARK: - 4. Location Stock
    // =========================================================================

    /// A stock entry grouped by location for the locations page.
    public struct LocationStock: Sendable {
        public let locationType: String
        public let locationId: Int64
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let qty: Int

        public init(locationType: String, locationId: Int64, partId: Int64, partName: String, partCode: String?, qty: Int) {
            self.locationType = locationType
            self.locationId = locationId
            self.partId = partId
            self.partName = partName
            self.partCode = partCode
            self.qty = qty
        }
    }

    /// Fetch all stock grouped by location type, with part names.
    public func getLocationStock(search: String? = nil) throws -> [LocationStock] {
        do {
            return try db.writer.read { dbConn -> [LocationStock] in
                var whereClauses = ["s.deleted_at IS NULL", "s.qty > 0"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(p.name LIKE ? OR p.code LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                }

                let sql = """
                    SELECT s.location_type, s.location_id, s.part_id, s.qty,
                           p.name AS part_name, p.code AS part_code
                    FROM stock s
                    LEFT JOIN parts p ON p.id = s.part_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY s.location_type, s.location_id, p.name
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    LocationStock(
                        locationType: row["location_type"] as String,
                        locationId: row["location_id"] as Int64,
                        partId: row["part_id"] as Int64,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        qty: row["qty"] as Int
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get stock quantity for a specific part at a specific location.
    public func getStockQty(partId: Int64, locationType: String, locationId: Int64) throws -> Int {
        try safeCount(
            sql: """
                SELECT COALESCE(SUM(qty), 0) FROM stock
                WHERE part_id = ? AND location_type = ? AND location_id = ?
                  AND deleted_at IS NULL
                """,
            arguments: StatementArguments([partId as DatabaseValueConvertible, locationType as DatabaseValueConvertible, locationId as DatabaseValueConvertible])
        )
    }

    /// Get stock at a specific location.
    public func getStockAtLocation(locationType: String, locationId: Int64) throws -> [LocationStock] {
        do {
            return try db.writer.read { dbConn -> [LocationStock] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT s.location_type, s.location_id, s.part_id, s.qty,
                               p.name AS part_name, p.code AS part_code
                        FROM stock s
                        LEFT JOIN parts p ON p.id = s.part_id
                        WHERE s.location_type = ? AND s.location_id = ?
                          AND s.qty > 0 AND s.deleted_at IS NULL
                        ORDER BY p.name
                        """,
                    arguments: [locationType, locationId]
                )
                return rows.map { row in
                    LocationStock(
                        locationType: row["location_type"] as String,
                        locationId: row["location_id"] as Int64,
                        partId: row["part_id"] as Int64,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        qty: row["qty"] as Int
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Staging (Pulled Items)
    // =========================================================================

    /// A staging tag with part and destination info.
    public struct StagedItem: Sendable {
        public let id: Int64
        public let stockId: Int64
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let qty: Int
        public let destinationType: String?
        public let destinationId: Int64?
        public let destinationLabel: String?
        public let taggedByName: String?
        public let taggedAt: String?
    }

    /// Fetch all pulled staging tags.
    public func getStagedItems() throws -> [StagedItem] {
        do {
            return try db.writer.read { dbConn -> [StagedItem] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT pst.id, pst.stock_id,
                               s.part_id, s.qty,
                               p.name AS part_name, p.code AS part_code,
                               pst.destination_type, pst.destination_id, pst.destination_label,
                               COALESCE(u.display_name, u.email, 'Unknown') AS tagged_by_name,
                               pst.tagged_at
                        FROM pulled_staging_tags pst
                        JOIN stock s ON s.id = pst.stock_id
                        LEFT JOIN parts p ON p.id = s.part_id
                        LEFT JOIN users u ON u.id = pst.tagged_by
                        WHERE pst.deleted_at IS NULL
                        ORDER BY pst.tagged_at DESC
                        """
                )
                return rows.map { row in
                    StagedItem(
                        id: row["id"] ?? 0,
                        stockId: row["stock_id"] ?? 0,
                        partId: row["part_id"] ?? 0,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        qty: row["qty"] ?? 0,
                        destinationType: row["destination_type"] as String?,
                        destinationId: row["destination_id"] as Int64?,
                        destinationLabel: row["destination_label"] as String?,
                        taggedByName: row["tagged_by_name"] as String?,
                        taggedAt: row["tagged_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a staging tag for a stock entry.
    @discardableResult
    public func createStagingTag(
        stockId: Int64,
        destinationType: String? = nil,
        destinationId: Int64? = nil,
        destinationLabel: String? = nil,
        taggedBy: Int64
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR REPLACE INTO pulled_staging_tags
                    (stock_id, destination_type, destination_id, destination_label, tagged_by, tagged_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [stockId, destinationType, destinationId, destinationLabel, taggedBy]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Clear a staging tag (mark as deleted).
    public func clearStagingTag(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE pulled_staging_tags SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    /// Clear all staging tags.
    public func clearAllStagingTags() throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE pulled_staging_tags SET deleted_at = datetime('now') WHERE deleted_at IS NULL"
            )
        }
    }

    // =========================================================================
    // MARK: - 6. Receiving Sessions
    // =========================================================================

    /// Receiving session info for display.
    public struct ReceivingSessionInfo: Sendable {
        public let id: Int64
        public let poId: Int64
        public let startedByName: String
        public let mode: String
        public let status: String
        public let completedAt: String?
        public let notes: String?
        public let createdAt: String
        public let itemCount: Int
    }

    /// Receiving session item info for display.
    public struct ReceivingItemInfo: Sendable {
        public let id: Int64
        public let sessionId: Int64
        public let poLineId: Int64
        public let partId: Int64?
        public let partName: String
        public let partCode: String?
        public let expectedQty: Int
        public let receivedQty: Int
        public let actualCost: Double?
        public let unitPrice: Double?
        public let scannedAt: String?
        public let notes: String?
    }

    /// Start a new receiving session for a PO.
    @discardableResult
    public func startReceivingSession(
        poId: Int64,
        startedBy: Int64,
        mode: String = "packing_slip"
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO receiving_sessions (po_id, started_by, mode, status, created_at)
                    VALUES (?, ?, ?, 'in_progress', datetime('now'))
                    """,
                arguments: [poId, startedBy, mode]
            )
            let sessionId = dbConn.lastInsertedRowID

            // Pre-populate items from PO line items
            try dbConn.execute(
                sql: """
                    INSERT INTO receiving_session_items (session_id, po_line_id, expected_qty, created_at)
                    SELECT ?, id, qty_ordered, datetime('now')
                    FROM po_line_items
                    WHERE po_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionId, poId]
            )

            return sessionId
        }
    }

    /// Get a receiving session with its items.
    public func getReceivingSession(sessionId: Int64) throws -> ReceivingSessionInfo? {
        do {
            return try db.writer.read { dbConn -> ReceivingSessionInfo? in
                guard let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT rs.*,
                               COALESCE(u.display_name, u.email, 'Unknown') AS started_by_name,
                               (SELECT COUNT(*) FROM receiving_session_items
                                WHERE session_id = rs.id AND deleted_at IS NULL) AS item_count
                        FROM receiving_sessions rs
                        LEFT JOIN users u ON u.id = rs.started_by
                        WHERE rs.id = ? AND rs.deleted_at IS NULL
                        """,
                    arguments: [sessionId]
                ) else { return nil }

                return ReceivingSessionInfo(
                    id: row["id"] ?? 0,
                    poId: row["po_id"] ?? 0,
                    startedByName: row["started_by_name"] ?? "Unknown",
                    mode: row["mode"] ?? "packing_slip",
                    status: row["status"] ?? "in_progress",
                    completedAt: row["completed_at"] as String?,
                    notes: row["notes"] as String?,
                    createdAt: row["created_at"] ?? "",
                    itemCount: row["item_count"] ?? 0
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Get active receiving sessions.
    public func getActiveSessions() throws -> [ReceivingSessionInfo] {
        do {
            return try db.writer.read { dbConn -> [ReceivingSessionInfo] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT rs.*,
                               COALESCE(u.display_name, u.email, 'Unknown') AS started_by_name,
                               (SELECT COUNT(*) FROM receiving_session_items
                                WHERE session_id = rs.id AND deleted_at IS NULL) AS item_count
                        FROM receiving_sessions rs
                        LEFT JOIN users u ON u.id = rs.started_by
                        WHERE rs.status = 'in_progress' AND rs.deleted_at IS NULL
                        ORDER BY rs.created_at DESC
                        """
                )
                return rows.map { row in
                    ReceivingSessionInfo(
                        id: row["id"] ?? 0,
                        poId: row["po_id"] ?? 0,
                        startedByName: row["started_by_name"] ?? "Unknown",
                        mode: row["mode"] ?? "packing_slip",
                        status: row["status"] ?? "in_progress",
                        completedAt: row["completed_at"] as String?,
                        notes: row["notes"] as String?,
                        createdAt: row["created_at"] ?? "",
                        itemCount: row["item_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get items for a receiving session.
    public func getSessionItems(sessionId: Int64) throws -> [ReceivingItemInfo] {
        do {
            return try db.writer.read { dbConn -> [ReceivingItemInfo] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT rsi.*,
                               pli.part_id,
                               pli.unit_cost,
                               p.name AS part_name,
                               p.code AS part_code
                        FROM receiving_session_items rsi
                        LEFT JOIN po_line_items pli ON pli.id = rsi.po_line_id
                        LEFT JOIN parts p ON p.id = pli.part_id
                        WHERE rsi.session_id = ? AND rsi.deleted_at IS NULL
                        ORDER BY p.name
                        """,
                    arguments: [sessionId]
                )
                return rows.map { row in
                    ReceivingItemInfo(
                        id: row["id"] ?? 0,
                        sessionId: row["session_id"] ?? 0,
                        poLineId: row["po_line_id"] ?? 0,
                        partId: row["part_id"] as Int64?,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        expectedQty: row["expected_qty"] ?? 0,
                        receivedQty: row["received_qty"] ?? 0,
                        actualCost: row["actual_cost"] as Double?,
                        unitPrice: row["unit_cost"] as Double?,
                        scannedAt: row["scanned_at"] as String?,
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Update a receiving session item's received quantity.
    public func updateSessionItem(itemId: Int64, receivedQty: Int, notes: String? = nil) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE receiving_session_items
                    SET received_qty = ?, notes = COALESCE(?, notes), scanned_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [receivedQty, notes, itemId]
            )
        }
    }

    /// Record a scan for a receiving session item.
    public func recordScan(itemId: Int64, qty: Int = 1) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE receiving_session_items
                    SET received_qty = received_qty + ?, scanned_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [qty, itemId]
            )
        }
    }

    /// Complete a receiving session: update status and create stock movements.
    public func completeSession(sessionId: Int64, completedBy: Int64) throws {
        try db.writer.write { dbConn in
            // Verify session exists and is in progress
            guard let statusStr = try String.fetchOne(
                dbConn,
                sql: "SELECT status FROM receiving_sessions WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionId]
            ) else {
                throw WarehouseError.sessionNotFound(sessionId)
            }

            if statusStr != "in_progress" {
                throw WarehouseError.sessionAlreadyCompleted
            }

            // Mark session as completed
            try dbConn.execute(
                sql: """
                    UPDATE receiving_sessions
                    SET status = 'completed', completed_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [sessionId]
            )

            // Create stock movements for each received item
            let items = try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT rsi.received_qty, rsi.actual_cost,
                           pli.part_id
                    FROM receiving_session_items rsi
                    JOIN po_line_items pli ON pli.id = rsi.po_line_id
                    WHERE rsi.session_id = ? AND rsi.received_qty > 0 AND rsi.deleted_at IS NULL
                    """,
                arguments: [sessionId]
            )

            for item in items {
                let partId: Int64 = item["part_id"] ?? 0
                let receivedQty: Int = item["received_qty"] ?? 0
                let unitCost: Double? = item["actual_cost"] as Double?

                // Insert movement
                try dbConn.execute(
                    sql: """
                        INSERT INTO stock_movements
                        (part_id, qty, to_location_type, to_location_id,
                         movement_type, reason, performed_by, unit_cost_at_move, created_at)
                        VALUES (?, ?, 'warehouse', 1, 'receiving', 'PO receiving', ?, ?, datetime('now'))
                        """,
                    arguments: [partId, receivedQty, completedBy, unitCost]
                )

                // Add to warehouse stock
                try dbConn.execute(
                    sql: """
                        UPDATE stock SET qty = qty + ?, updated_at = datetime('now')
                        WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1
                          AND deleted_at IS NULL
                        """,
                    arguments: [receivedQty, partId]
                )
                if dbConn.changesCount == 0 {
                    try dbConn.execute(
                        sql: """
                            INSERT INTO stock (part_id, location_type, location_id, qty, updated_at)
                            VALUES (?, 'warehouse', 1, ?, datetime('now'))
                            """,
                        arguments: [partId, receivedQty]
                    )
                }
            }
        }
    }

    /// Cancel a receiving session.
    public func cancelSession(sessionId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE receiving_sessions
                    SET status = 'cancelled', completed_at = datetime('now')
                    WHERE id = ? AND status = 'in_progress'
                    """,
                arguments: [sessionId]
            )
        }
    }

    // =========================================================================
    // MARK: - 7. Returns
    // =========================================================================

    /// Get recent return movements.
    public func getReturnItems(limit: Int = 50) throws -> [MovementRow] {
        do {
            return try db.writer.read { dbConn -> [MovementRow] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT sm.*,
                               p.name AS part_name,
                               COALESCE(u.display_name, u.email, 'Unknown') AS performed_by_name
                        FROM stock_movements sm
                        LEFT JOIN parts p ON p.id = sm.part_id
                        LEFT JOIN users u ON u.id = sm.performed_by
                        WHERE sm.movement_type = 'return' AND sm.deleted_at IS NULL
                        ORDER BY sm.created_at DESC
                        LIMIT ?
                        """,
                    arguments: [limit]
                )
                return rows.map { row in
                    MovementRow(
                        id: row["id"] as Int64,
                        partId: row["part_id"] as Int64,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        qty: row["qty"] as Int,
                        fromLocationType: row["from_location_type"] as String?,
                        fromLocationId: row["from_location_id"] as Int64?,
                        toLocationType: row["to_location_type"] as String?,
                        toLocationId: row["to_location_id"] as Int64?,
                        movementType: row["movement_type"] as String,
                        reason: row["reason"] as String?,
                        notes: row["notes"] as String?,
                        performedBy: row["performed_by"] as Int64,
                        performedByName: row["performed_by_name"] as String?,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Process a return: create a return movement and update stock.
    @discardableResult
    public func processReturn(
        partId: Int64,
        qty: Int,
        fromLocationType: String,
        fromLocationId: Int64,
        toLocationType: String = "warehouse",
        toLocationId: Int64 = 1,
        reason: String? = nil,
        notes: String? = nil,
        performedBy: Int64,
        isDamaged: Bool = false
    ) throws -> Int64 {
        try createMovement(
            partId: partId,
            qty: qty,
            fromLocationType: fromLocationType,
            fromLocationId: fromLocationId,
            toLocationType: toLocationType,
            toLocationId: toLocationId,
            movementType: "return",
            reason: isDamaged ? "damaged" : (reason ?? "return"),
            notes: notes,
            performedBy: performedBy
        )
    }

    // =========================================================================
    // MARK: - 8. Audit
    // =========================================================================

    /// Audit summary info.
    public struct AuditSummary: Sendable {
        public let totalParts: Int
        public let countedParts: Int
        public let discrepancies: Int
        public let lastAuditDate: String?
    }

    /// Audit discrepancy item.
    public struct AuditDiscrepancy: Sendable {
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let locationType: String
        public let locationId: Int64
        public let systemQty: Int
        public let countedQty: Int
        public let difference: Int
        public let lastCounted: String?
    }

    /// Get audit summary for the warehouse.
    public func getAuditSummary() throws -> AuditSummary {
        let totalParts = try safeCount(
            sql: """
                SELECT COUNT(DISTINCT part_id) FROM stock
                WHERE location_type = 'warehouse' AND deleted_at IS NULL AND qty > 0
                """
        )

        let countedParts = try safeCount(
            sql: """
                SELECT COUNT(DISTINCT part_id) FROM stock
                WHERE location_type = 'warehouse' AND deleted_at IS NULL
                  AND last_counted IS NOT NULL
                  AND date(last_counted) = date('now')
                  AND counted_qty IS NOT NULL
                """
        )

        let discrepancies = try safeCount(
            sql: """
                SELECT COUNT(*) FROM stock
                WHERE location_type = 'warehouse' AND deleted_at IS NULL
                  AND last_counted IS NOT NULL
                  AND date(last_counted) = date('now')
                  AND counted_qty IS NOT NULL
                  AND counted_qty != qty
                """
        )

        let lastDate: String? = try? db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: """
                    SELECT MAX(last_counted) FROM stock
                    WHERE last_counted IS NOT NULL AND deleted_at IS NULL
                    """
            )
        }

        return AuditSummary(
            totalParts: totalParts,
            countedParts: countedParts,
            discrepancies: discrepancies,
            lastAuditDate: lastDate
        )
    }

    /// Record a physical count for an audit.
    public func recordAuditCount(
        stockId: Int64,
        countedQty: Int
    ) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE stock
                    SET last_counted = datetime('now'),
                        counted_qty  = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [countedQty, stockId]
            )
        }
    }

    /// Get audit discrepancies between system and counted quantities.
    public func getAuditDiscrepancies() throws -> [AuditDiscrepancy] {
        do {
            return try db.writer.read { dbConn -> [AuditDiscrepancy] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT s.part_id, s.location_type, s.location_id,
                               s.qty, s.counted_qty, s.last_counted,
                               p.name AS part_name, p.code AS part_code
                        FROM stock s
                        LEFT JOIN parts p ON p.id = s.part_id
                        WHERE s.location_type = 'warehouse'
                          AND s.deleted_at IS NULL
                          AND s.last_counted IS NOT NULL
                          AND date(s.last_counted) = date('now')
                          AND s.counted_qty IS NOT NULL
                        ORDER BY p.name
                        """
                )
                return rows.compactMap { row -> AuditDiscrepancy? in
                    let partId: Int64 = row["part_id"] ?? 0
                    let systemQty: Int = row["qty"] ?? 0
                    let countedQty: Int = row["counted_qty"] ?? systemQty

                    return AuditDiscrepancy(
                        partId: partId,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        locationType: row["location_type"] ?? "warehouse",
                        locationId: row["location_id"] ?? 1,
                        systemQty: systemQty,
                        countedQty: countedQty,
                        difference: countedQty - systemQty,
                        lastCounted: row["last_counted"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - 8b. Audit Session Management

    /// Create a new audit session and return its ID.
    ///
    /// The session tracks scope, zone, and options. Audit counts are recorded
    /// against stock entries via `recordAuditCount`.
    @discardableResult
    public func createAuditSession(
        scope: String,
        zone: String?,
        sampleSize: Int?,
        includeZeroStock: Bool,
        notes: String?,
        userId: Int64 = 1
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO audit_sessions_v2
                        (session_type, started_by, zone, sample_size, include_zero_stock, notes, status, started_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'active', datetime('now'))
                    """,
                arguments: [scope, userId, zone, sampleSize, includeZeroStock ? 1 : 0, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Finalize (close) an audit session.
    public func finalizeAuditSession(sessionId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE audit_sessions_v2 SET status = 'completed', completed_at = datetime('now')
                    WHERE id = ?
                    """,
                arguments: [sessionId]
            )
        }
    }

    /// Adjust system stock to match the physical count for a specific part at a location.
    public func adjustAuditCount(
        partId: Int64,
        locationType: String,
        locationId: Int64,
        newQty: Int,
        reason: String?,
        performedBy: Int64?
    ) throws {
        try db.writer.write { dbConn in
            // Update the stock record
            try dbConn.execute(
                sql: """
                    UPDATE stock SET qty = ?, last_counted = datetime('now'), updated_at = datetime('now')
                    WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                    """,
                arguments: [newQty, partId, locationType, locationId]
            )

            // Record the adjustment as a movement
            try dbConn.execute(
                sql: """
                    INSERT INTO stock_movements (part_id, qty, from_location_type, from_location_id, to_location_type, to_location_id, movement_type, reason, notes, performed_by, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'adjustment', ?, 'Audit count adjustment', ?, datetime('now'))
                    """,
                arguments: [partId, newQty, locationType, locationId, locationType, locationId, reason ?? "Audit adjustment", performedBy]
            )
        }
    }

    /// Record an audit recount for a part at a specific location.
    public func recordAuditRecount(partId: Int64, locationType: String, locationId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE stock SET last_counted = datetime('now')
                    WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                    """,
                arguments: [partId, locationType, locationId]
            )
        }
    }

    /// Calculate audit accuracy percentage from the summary.
    public func getAuditAccuracy() throws -> Double {
        let summary = try getAuditSummary()
        guard summary.totalParts > 0 else { return 100.0 }
        return Double(summary.totalParts - summary.discrepancies) / Double(summary.totalParts) * 100.0
    }

    // =========================================================================
    // MARK: - 9. Trailers
    // =========================================================================

    /// Trailer info for display.
    public struct TrailerInfo: Sendable {
        public let id: Int64
        public let trailerCode: String
        public let name: String
        public let status: String
        public let currentJobId: Int64?
        public let assignedDriverName: String?
        public let notes: String?
        public let isActive: Bool
    }

    /// List all active trailers.
    public func listTrailers() throws -> [TrailerInfo] {
        do {
            return try db.writer.read { dbConn -> [TrailerInfo] in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT jt.*,
                               COALESCE(u.display_name, u.email) AS driver_name
                        FROM job_trailers jt
                        LEFT JOIN users u ON u.id = jt.assigned_driver_user_id
                        WHERE jt.deleted_at IS NULL
                        ORDER BY jt.name
                        """
                )
                return rows.map { row in
                    TrailerInfo(
                        id: row["id"] ?? 0,
                        trailerCode: row["trailer_code"] ?? "",
                        name: row["name"] ?? "",
                        status: row["status"] ?? "active",
                        currentJobId: row["current_job_id"] as Int64?,
                        assignedDriverName: row["driver_name"] as String?,
                        notes: row["notes"] as String?,
                        isActive: (row["is_active"] as Int?) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a single trailer by ID.
    public func getTrailer(id: Int64) throws -> TrailerInfo? {
        do {
            return try db.writer.read { dbConn -> TrailerInfo? in
                guard let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT jt.*,
                               COALESCE(u.display_name, u.email) AS driver_name
                        FROM job_trailers jt
                        LEFT JOIN users u ON u.id = jt.assigned_driver_user_id
                        WHERE jt.id = ? AND jt.deleted_at IS NULL
                        """,
                    arguments: [id]
                ) else { return nil }

                return TrailerInfo(
                    id: row["id"] ?? 0,
                    trailerCode: row["trailer_code"] ?? "",
                    name: row["name"] ?? "",
                    status: row["status"] ?? "active",
                    currentJobId: row["current_job_id"] as Int64?,
                    assignedDriverName: row["driver_name"] as String?,
                    notes: row["notes"] as String?,
                    isActive: (row["is_active"] as Int?) == 1
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Create a new trailer.
    @discardableResult
    public func createTrailer(
        trailerCode: String,
        name: String,
        status: String = "active",
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO job_trailers (trailer_code, name, status, notes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [trailerCode, name, status, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update a trailer's fields.
    public func updateTrailer(
        id: Int64,
        status: String? = nil,
        currentJobId: Int64? = nil,
        assignedDriverUserId: Int64? = nil,
        notes: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            var setClauses: [String] = []
            var args: [DatabaseValueConvertible?] = []

            if let status { setClauses.append("status = ?"); args.append(status) }
            if let currentJobId { setClauses.append("current_job_id = ?"); args.append(currentJobId) }
            if let assignedDriverUserId { setClauses.append("assigned_driver_user_id = ?"); args.append(assignedDriverUserId) }
            if let notes { setClauses.append("notes = ?"); args.append(notes) }

            guard !setClauses.isEmpty else { return }
            setClauses.append("updated_at = datetime('now')")
            args.append(id)

            let sql = "UPDATE job_trailers SET \(setClauses.joined(separator: ", ")) WHERE id = ?"
            try dbConn.execute(sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Record a trailer location event.
    @discardableResult
    public func recordTrailerLocation(
        trailerId: Int64,
        eventType: String = "manual_update",
        locationKind: String = "other",
        jobId: Int64? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        recordedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO trailer_location_events
                    (trailer_id, event_type, location_kind, job_id, lat, lng, recorded_by, recorded_at, notes)
                    VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
                    """,
                arguments: [trailerId, eventType, locationKind, jobId, lat, lng, recordedBy, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Get recent location events for a trailer.
    public func getTrailerLocationHistory(trailerId: Int64, limit: Int = 50) throws -> [Row] {
        do {
            return try db.writer.read { dbConn -> [Row] in
                try Row.fetchAll(
                    dbConn,
                    sql: """
                        SELECT tle.*,
                               COALESCE(u.display_name, u.email, 'Unknown') AS recorder_name
                        FROM trailer_location_events tle
                        LEFT JOIN users u ON u.id = tle.recorded_by
                        WHERE tle.trailer_id = ?
                        ORDER BY tle.recorded_at DESC
                        LIMIT ?
                        """,
                    arguments: [trailerId, limit]
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 10. Staging Boxes
    // =========================================================================

    /// Physical staging box info for display.
    public struct StagingBox: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String?
        public let jobNumber: String?
        public let boxNumber: String       // e.g. "0412-01"
        public let boxSize: String         // small / normal / large
        public let labelText: String       // e.g. "SMITH RES 0412-01"
        public let isFull: Bool
        public let areaId: Int64?
        public let createdAt: String?
    }

    /// Create a new staging box for a job, auto-generating box_number and label_text.
    ///
    /// Box number format: `<jobNumber>-<seq>` where seq auto-increments
    /// per job (01, 02, 03...). Label text shows a short human-readable string
    /// suitable for writing on the physical box with a marker.
    @discardableResult
    public func createStagingBox(
        jobId: Int64,
        size: String = "normal",
        areaId: Int64? = nil
    ) throws -> StagingBox {
        try db.writer.write { dbConn in
            // Fetch job info for label generation
            let jobRow = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT j.job_number, j.job_name
                    FROM jobs j WHERE j.id = ? AND j.deleted_at IS NULL
                    """,
                arguments: [jobId]
            )

            let jobNumber = (jobRow?["job_number"] as String?) ?? "\(jobId)"
            let jobName = (jobRow?["job_name"] as String?) ?? ""

            // Count existing boxes for this job to determine sequence
            let existingCount = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*) FROM staging_boxes
                    WHERE job_id = ? AND deleted_at IS NULL
                    """,
                arguments: [jobId]
            ) ?? 0

            let seq = existingCount + 1
            let seqStr = String(format: "%02d", seq)
            let boxNumber = "\(jobNumber)-\(seqStr)"

            // Build short label: first word of job name (uppercase) + box number
            let shortName = buildShortLabel(jobName: jobName)
            let labelText = "\(shortName) \(boxNumber)"

            try dbConn.execute(
                sql: """
                    INSERT INTO staging_boxes
                    (job_id, box_number, box_size, label_text, is_full, area_id, created_at)
                    VALUES (?, ?, ?, ?, 0, ?, datetime('now'))
                    """,
                arguments: [jobId, boxNumber, size, labelText, areaId]
            )

            let newId = dbConn.lastInsertedRowID

            return StagingBox(
                id: newId,
                jobId: jobId,
                jobName: jobName,
                jobNumber: jobNumber,
                boxNumber: boxNumber,
                boxSize: size,
                labelText: labelText,
                isFull: false,
                areaId: areaId,
                createdAt: nil
            )
        }
    }

    /// List staging boxes, optionally filtered by job.
    public func listStagingBoxes(jobId: Int64? = nil) throws -> [StagingBox] {
        do {
            return try db.writer.read { dbConn -> [StagingBox] in
                var whereClauses = ["sb.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let jobId {
                    whereClauses.append("sb.job_id = ?")
                    args.append(jobId)
                }

                let sql = """
                    SELECT sb.*,
                           j.job_name, j.job_number
                    FROM staging_boxes sb
                    LEFT JOIN jobs j ON j.id = sb.job_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY j.job_number, sb.box_number
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    StagingBox(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] as String?,
                        jobNumber: row["job_number"] as String?,
                        boxNumber: row["box_number"] ?? "",
                        boxSize: row["box_size"] ?? "normal",
                        labelText: row["label_text"] ?? "",
                        isFull: (row["is_full"] as Int?) == 1,
                        areaId: row["area_id"] as Int64?,
                        createdAt: row["created_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Mark a box as full. Automatically creates the next box for the same job.
    ///
    /// - Returns: The newly created next box (auto-incremented).
    @discardableResult
    public func markBoxFull(boxId: Int64) throws -> StagingBox {
        // First mark the box as full
        let (jobId, areaId, size): (Int64, Int64?, String) = try db.writer.read { dbConn in
            guard let row = try Row.fetchOne(
                dbConn,
                sql: "SELECT job_id, area_id, box_size FROM staging_boxes WHERE id = ? AND deleted_at IS NULL",
                arguments: [boxId]
            ) else {
                throw WarehouseError.partNotFound(boxId)
            }
            return (row["job_id"] as Int64, row["area_id"] as Int64?, (row["box_size"] as String?) ?? "normal")
        }

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE staging_boxes SET is_full = 1 WHERE id = ?",
                arguments: [boxId]
            )
        }

        // Auto-create the next box
        return try createStagingBox(jobId: jobId, size: size, areaId: areaId)
    }

    /// Mark a box as open (not full).
    public func markBoxOpen(boxId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE staging_boxes SET is_full = 0 WHERE id = ?",
                arguments: [boxId]
            )
        }
    }

    /// Soft-delete a staging box.
    public func deleteStagingBox(boxId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE staging_boxes SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [boxId]
            )
        }
    }

    /// Build a short label from a job name for box labeling.
    ///
    /// Takes the first meaningful words of the job name (up to ~15 chars)
    /// and uppercases them. Examples:
    ///   "Smith Residence Remodel" → "SMITH RES"
    ///   "Johnson Office Build" → "JOHNSON OFF"
    private func buildShortLabel(jobName: String) -> String {
        let words = jobName.split(separator: " ")
        guard !words.isEmpty else { return "JOB" }

        var label = ""
        for word in words {
            let candidate = label.isEmpty ? String(word) : "\(label) \(word)"
            if candidate.count > 15 {
                // If we haven't added anything yet, take the first word truncated
                if label.isEmpty {
                    label = String(word.prefix(12))
                }
                break
            }
            label = candidate
        }
        return label.uppercased()
    }

    // =========================================================================
    // MARK: - 11. Receiving Routing
    // =========================================================================

    /// Stock level info for a part, used during receiving routing decisions.
    public struct PartStockLevels: Sendable {
        public let partId: Int64
        public let partName: String
        public let currentShelfQty: Int
        public let minStock: Int
        public let targetStock: Int
        public let maxStock: Int

        public init(partId: Int64, partName: String, currentShelfQty: Int, minStock: Int, targetStock: Int, maxStock: Int) {
            self.partId = partId
            self.partName = partName
            self.currentShelfQty = currentShelfQty
            self.minStock = minStock
            self.targetStock = targetStock
            self.maxStock = maxStock
        }

        /// True when shelf stock is below target level.
        public var isBelowTarget: Bool { currentShelfQty < targetStock }
        /// True when shelf stock is at or above max level.
        public var isAtOrAboveMax: Bool { maxStock > 0 && currentShelfQty >= maxStock }
        /// True when shelf stock is above target but below max.
        public var isAboveTargetBelowMax: Bool {
            currentShelfQty >= targetStock && (maxStock <= 0 || currentShelfQty < maxStock)
        }
        /// Quantity needed to reach target.
        public var qtyToTarget: Int { max(0, targetStock - currentShelfQty) }
    }

    /// Job link info for a PO line item, discovered via jpo_line_id -> jpo -> job.
    public struct POLineJobLink: Sendable {
        public let jobId: Int64
        public let jobName: String
        public let jpoId: Int64
    }

    /// An active JPO line that wants a specific part (for cross-job staging suggestions).
    public struct ActiveJPODemand: Sendable {
        public let jpoId: Int64
        public let jpoLineId: Int64
        public let jobId: Int64
        public let jobName: String
        public let qtyRequested: Int
        public let qtyFulfilled: Int

        /// Remaining unfulfilled quantity.
        public var qtyNeeded: Int { max(0, qtyRequested - qtyFulfilled) }
    }

    /// The routing decision for a single received item.
    public enum ReceivingRoute: Sendable {
        /// Part is good and linked to a job — send to staging.
        case stageForJob(jobId: Int64, jobName: String, jpoId: Int64)
        /// Part is good, another active JPO wants it — suggest staging.
        case suggestStaging(demands: [ActiveJPODemand])
        /// Part is good, below target — restock shelf.
        case restockShelf(levels: PartStockLevels)
        /// Part is good, above target but below max — recommend return.
        case recommendReturn(levels: PartStockLevels)
        /// Part is good, at or above max — return to supplier.
        case returnOverstock(levels: PartStockLevels)
        /// Part is used, below target — shelf it.
        case usedToShelf(levels: PartStockLevels)
        /// Part is used, not needed — write off.
        case usedWriteOff(levels: PartStockLevels)
        /// Part is damaged — return to supplier for replacement or refund.
        case damagedReturn
        /// Wrong part received.
        case wrongPart
    }

    /// Get shelf stock levels for a part (warehouse location_type only).
    public func getPartStockLevels(partId: Int64) throws -> PartStockLevels {
        try db.writer.read { dbConn -> PartStockLevels in
            let partRow = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT p.id, p.name,
                           COALESCE(p.min_stock_level, 0) AS min_stock,
                           COALESCE(p.target_stock_level, 0) AS target_stock,
                           COALESCE(p.max_stock_level, 0) AS max_stock
                    FROM parts p
                    WHERE p.id = ? AND p.deleted_at IS NULL
                    """,
                arguments: [partId]
            )

            let shelfQty = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COALESCE(SUM(qty), 0) FROM stock
                    WHERE part_id = ? AND location_type = 'warehouse'
                      AND deleted_at IS NULL
                    """,
                arguments: [partId]
            ) ?? 0

            return PartStockLevels(
                partId: partId,
                partName: (partRow?["name"] as String?) ?? "Unknown Part",
                currentShelfQty: shelfQty,
                minStock: partRow?["min_stock"] ?? 0,
                targetStock: partRow?["target_stock"] ?? 0,
                maxStock: partRow?["max_stock"] ?? 0
            )
        }
    }

    /// Check if a PO line item is linked to a job via JPO.
    /// Returns the job link info if found.
    public func getJobLinkForPOLine(poLineId: Int64) throws -> POLineJobLink? {
        do {
            return try db.writer.read { dbConn -> POLineJobLink? in
                let row = try Row.fetchOne(
                    dbConn,
                    sql: """
                        SELECT jpo.job_id, j.job_name, jpo.id AS jpo_id
                        FROM po_line_items pl
                        JOIN jpo_line_items jli ON jli.id = pl.jpo_line_id
                        JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id
                        JOIN jobs j ON j.id = jpo.job_id
                        WHERE pl.id = ? AND pl.jpo_line_id IS NOT NULL
                        """,
                    arguments: [poLineId]
                )
                guard let row else { return nil }
                return POLineJobLink(
                    jobId: row["job_id"] ?? 0,
                    jobName: row["job_name"] ?? "Unknown Job",
                    jpoId: row["jpo_id"] ?? 0
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Find active JPO lines that want a specific part (for cross-job staging suggestions).
    /// Excludes the given PO line's own JPO to avoid double-counting.
    public func getActiveJPODemandForPart(
        partId: Int64,
        excludeJPOId: Int64? = nil
    ) throws -> [ActiveJPODemand] {
        do {
            return try db.writer.read { dbConn -> [ActiveJPODemand] in
                var whereClauses = [
                    "jl.part_id = ?",
                    "jl.line_status IN ('approved', 'pending')",
                    "jl.deleted_at IS NULL",
                    "jpo.deleted_at IS NULL",
                    "jpo.status NOT IN ('completed', 'cancelled')",
                ]
                var args: [DatabaseValueConvertible?] = [partId]

                if let excludeJPOId {
                    whereClauses.append("jpo.id != ?")
                    args.append(excludeJPOId)
                }

                let sql = """
                    SELECT jl.id AS jpo_line_id, jl.qty_requested,
                           COALESCE(jl.qty_received, 0) AS qty_fulfilled,
                           jpo.id AS jpo_id, jpo.job_id,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name
                    FROM jpo_line_items jl
                    JOIN job_parts_orders jpo ON jpo.id = jl.jpo_id
                    LEFT JOIN jobs j ON j.id = jpo.job_id
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY jpo.priority DESC, jpo.created_at ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.compactMap { row -> ActiveJPODemand? in
                    let qtyRequested: Int = row["qty_requested"] ?? 0
                    let qtyFulfilled: Int = row["qty_fulfilled"] ?? 0
                    guard qtyRequested > qtyFulfilled else { return nil }

                    return ActiveJPODemand(
                        jpoId: row["jpo_id"] ?? 0,
                        jpoLineId: row["jpo_line_id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "Unknown Job",
                        qtyRequested: qtyRequested,
                        qtyFulfilled: qtyFulfilled
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Move received parts to staging for a job (does NOT count toward shelf inventory).
    @discardableResult
    public func stageReceivedPartsForJob(
        partId: Int64,
        qty: Int,
        jobId: Int64,
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        try createMovement(
            partId: partId,
            qty: qty,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "pulled",
            toLocationId: jobId,
            movementType: "receiving_staged",
            reason: "Received and staged for job",
            notes: notes,
            performedBy: performedBy,
            jobId: jobId
        )
    }

    /// Record a write-off for used/damaged parts that won't go on shelf.
    @discardableResult
    public func writeOffReceivedPart(
        partId: Int64,
        qty: Int,
        reason: String,
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        try createMovement(
            partId: partId,
            qty: qty,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: nil,
            toLocationId: nil,
            movementType: "write_off",
            reason: reason,
            notes: notes,
            performedBy: performedBy
        )
    }

    /// Record a supplier return for damaged parts.
    @discardableResult
    public func returnDamagedToSupplier(
        partId: Int64,
        qty: Int,
        returnType: String,  // "replacement" or "refund"
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        try createMovement(
            partId: partId,
            qty: qty,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: nil,
            toLocationId: nil,
            movementType: "return_to_supplier",
            reason: "Damaged: \(returnType)",
            notes: notes,
            performedBy: performedBy
        )
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) or SELECT COALESCE(SUM(...), 0) query.
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

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }

    /// Determine the movement_type based on from/to location types.
    private static func determineMovementType(from: String, to: String) -> String {
        if to == "warehouse" && (from == "truck" || from == "trailer") {
            return "return"
        }
        if from == "job" {
            return "return"
        }
        return "transfer"
    }

    /// Build a human-readable display name for a location.
    private static func locationDisplayName(type: String, id: Int64) -> String {
        switch type {
        case "warehouse":
            return "Warehouse \(id)"
        case "truck":
            return "Truck \(id)"
        case "trailer":
            return "Trailer \(id)"
        case "job":
            return "Job \(id)"
        case "pulled":
            return "Pulled Staging"
        default:
            return "\(type) #\(id)"
        }
    }

    // =========================================================================
    // MARK: - Floor Plans
    // =========================================================================

    /// Create a new warehouse floor plan.
    public func createFloorPlan(name: String, widthInches: Int, lengthInches: Int) throws -> WarehouseFloorPlan {
        try db.writer.write { dbConn in
            var plan = WarehouseFloorPlan(
                name: name,
                widthInches: widthInches,
                lengthInches: lengthInches,
                isActive: true
            )
            try plan.insert(dbConn)
            return plan
        }
    }

    /// Get a floor plan by ID.
    public func getFloorPlan(id: Int64) throws -> WarehouseFloorPlan? {
        try db.writer.read { dbConn in
            try WarehouseFloorPlan
                .filter(Column("id") == id && Column("deleted_at") == nil)
                .fetchOne(dbConn)
        }
    }

    /// Save user-defined grid dimensions to a floor plan (PE-040 — wizard dimensions form).
    public func updateFloorPlanGrid(floorPlanId: Int64, rows: Int, cols: Int) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_floor_plans SET grid_rows = ?, grid_cols = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [rows, cols, floorPlanId]
            )
        }
    }

    /// List all active floor plans.
    public func listFloorPlans() throws -> [WarehouseFloorPlan] {
        try db.writer.read { dbConn in
            try WarehouseFloorPlan
                .filter(Column("deleted_at") == nil)
                .order(Column("name"))
                .fetchAll(dbConn)
        }
    }

    /// Soft delete a floor plan.
    public func deleteFloorPlan(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_floor_plans SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Floor Features
    // =========================================================================

    /// Add a non-storage feature to a floor plan (door, walkway, office, etc.)
    public func addFloorFeature(
        floorPlanId: Int64, featureType: String, label: String?,
        gridX: Int, gridY: Int, gridWidth: Int = 1, gridHeight: Int = 1, rotation: Int = 0
    ) throws -> WarehouseFloorFeature {
        try db.writer.write { dbConn in
            var feature = WarehouseFloorFeature(
                floorPlanId: floorPlanId,
                featureType: featureType,
                label: label,
                gridX: gridX, gridY: gridY,
                gridWidth: gridWidth, gridHeight: gridHeight,
                rotation: rotation
            )
            try feature.insert(dbConn)
            return feature
        }
    }

    /// List features for a floor plan.
    public func listFloorFeatures(floorPlanId: Int64) throws -> [WarehouseFloorFeature] {
        try db.writer.read { dbConn in
            try WarehouseFloorFeature
                .filter(Column("floor_plan_id") == floorPlanId && Column("deleted_at") == nil)
                .fetchAll(dbConn)
        }
    }

    /// Soft delete a floor feature.
    public func deleteFloorFeature(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_floor_features SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Warehouse Zones
    // =========================================================================

    /// Add a zone to a floor plan.
    public func addZone(
        floorPlanId: Int64, zoneType: String, label: String? = nil, colorHex: String? = nil,
        gridX: Int = 0, gridY: Int = 0, gridWidth: Int = 4, gridHeight: Int = 4,
        rotation: Int = 0, zoneOrder: Int = 0
    ) throws -> WarehouseZone {
        try db.writer.write { dbConn in
            var zone = WarehouseZone(
                floorPlanId: floorPlanId,
                zoneType: zoneType,
                label: label,
                colorHex: colorHex,
                gridX: gridX,
                gridY: gridY,
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                rotation: rotation,
                zoneOrder: zoneOrder
            )
            try zone.insert(dbConn)
            return zone
        }
    }

    /// List all active zones for a floor plan.
    public func listZones(floorPlanId: Int64) throws -> [WarehouseZone] {
        try db.writer.read { dbConn in
            try WarehouseZone
                .filter(Column("floor_plan_id") == floorPlanId && Column("deleted_at") == nil)
                .order(Column("zone_order").asc, Column("id").asc)
                .fetchAll(dbConn)
        }
    }

    /// Update a zone's properties.
    public func updateZone(
        id: Int64, zoneType: String? = nil, label: String? = nil, colorHex: String? = nil,
        gridX: Int? = nil, gridY: Int? = nil, gridWidth: Int? = nil, gridHeight: Int? = nil,
        rotation: Int? = nil, zoneOrder: Int? = nil
    ) throws {
        try db.writer.write { dbConn in
            guard var zone = try WarehouseZone.fetchOne(dbConn, key: id) else { return }
            if let v = zoneType { zone.zoneType = v }
            if let v = label { zone.label = v }
            if let v = colorHex { zone.colorHex = v }
            if let v = gridX { zone.gridX = v }
            if let v = gridY { zone.gridY = v }
            if let v = gridWidth { zone.gridWidth = v }
            if let v = gridHeight { zone.gridHeight = v }
            if let v = rotation { zone.rotation = v }
            if let v = zoneOrder { zone.zoneOrder = v }
            try zone.update(dbConn)
        }
    }

    /// Soft delete a zone.
    public func deleteZone(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_zones SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Setup Tier Detection
    // =========================================================================

    /// The warehouse setup tier, from none to complete.
    public enum WarehouseSetupTier: String, Sendable {
        case none               // No warehouse data at all
        case partsOnly          // Parts have locations/stock but no floor plan
        case floorPlanInProgress // Floor plan exists but onboarding not complete
        case complete           // Full warehouse setup done
    }

    /// Detect current warehouse setup tier based on existing data.
    public func getSetupProgress() throws -> WarehouseSetupTier {
        try db.writer.read { dbConn in
            // Check if any completed onboarding exists
            let completedCount = try WarehouseOnboardingProgress
                .filter(Column("completed_at") != nil)
                .fetchCount(dbConn)
            if completedCount > 0 { return .complete }

            // Check if floor plans exist
            let floorPlanCount = try WarehouseFloorPlan
                .filter(Column("deleted_at") == nil)
                .fetchCount(dbConn)
            if floorPlanCount > 0 { return .floorPlanInProgress }

            // Check if any parts have shelf/bin locations or stock entries
            let partsWithLocations = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM parts
                WHERE deleted_at IS NULL
                  AND (shelf_location IS NOT NULL OR bin_location IS NOT NULL)
                """) ?? 0
            let stockCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM stock WHERE deleted_at IS NULL
                """) ?? 0
            if partsWithLocations > 0 || stockCount > 0 { return .partsOnly }

            return .none
        }
    }

    // =========================================================================
    // MARK: - Flow Onboarding Progress
    // =========================================================================

    /// Start a new flow-based onboarding session.
    public func startFlowOnboarding(
        flowType: String, totalSteps: Int, floorPlanId: Int64? = nil
    ) throws -> WarehouseOnboardingProgress {
        try db.writer.write { dbConn in
            var progress = WarehouseOnboardingProgress(
                floorPlanId: floorPlanId,
                currentStep: 1,
                step1Complete: false,
                step2Complete: false,
                step3Complete: false,
                flowType: flowType,
                totalSteps: totalSteps
            )
            try progress.insert(dbConn)
            return progress
        }
    }

    /// Update flow onboarding progress with JSON step data.
    public func updateFlowProgress(
        id: Int64, currentStep: Int, stepData: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            guard var progress = try WarehouseOnboardingProgress.fetchOne(dbConn, key: id) else { return }
            progress.currentStep = currentStep
            if let data = stepData { progress.stepsProgress = data }
            try progress.update(dbConn)
        }
    }

    // =========================================================================
    // MARK: - Storage Units
    // =========================================================================

    /// Add a storage unit to a floor plan.
    public func addStorageUnit(
        floorPlanId: Int64, name: String, unitType: String,
        rowNumber: String? = nil, unitNumber: String? = nil,
        widthInches: Int? = nil, depthInches: Int? = nil, heightInches: Int? = nil,
        gridX: Int? = nil, gridY: Int? = nil,
        gridWidth: Int? = nil, gridHeight: Int? = nil,
        rotation: Int = 0, frontFace: String? = "south",
        isMovable: Bool = false, isJobReady: Bool = false
    ) throws -> WarehouseStorageUnit {
        try db.writer.write { dbConn in
            var unit = WarehouseStorageUnit(
                floorPlanId: floorPlanId,
                name: name,
                unitType: unitType,
                rowNumber: rowNumber,
                unitNumber: unitNumber,
                widthInches: widthInches,
                depthInches: depthInches,
                heightInches: heightInches,
                gridX: gridX,
                gridY: gridY,
                gridWidth: gridWidth,
                gridHeight: gridHeight,
                rotation: rotation,
                frontFace: frontFace,
                isMovable: isMovable,
                isJobReady: isJobReady,
                isConfigured: false
            )
            try unit.insert(dbConn)
            return unit
        }
    }

    /// List storage units for a floor plan.
    public func listStorageUnits(floorPlanId: Int64) throws -> [WarehouseStorageUnit] {
        try db.writer.read { dbConn in
            try WarehouseStorageUnit
                .filter(Column("floor_plan_id") == floorPlanId && Column("deleted_at") == nil)
                .order(Column("row_number"), Column("unit_number"))
                .fetchAll(dbConn)
        }
    }

    /// Update a storage unit's properties.
    public func updateStorageUnit(
        id: Int64, name: String? = nil, unitType: String? = nil,
        rowNumber: String? = nil, unitNumber: String? = nil,
        gridX: Int? = nil, gridY: Int? = nil,
        gridWidth: Int? = nil, gridHeight: Int? = nil,
        rotation: Int? = nil, frontFace: String? = nil,
        isConfigured: Bool? = nil, zoneId: Int64? = nil
    ) throws {
        try db.writer.write { dbConn in
            guard var unit = try WarehouseStorageUnit.fetchOne(dbConn, key: id) else { return }
            if let name = name { unit.name = name }
            if let unitType = unitType { unit.unitType = unitType }
            if let rowNumber = rowNumber { unit.rowNumber = rowNumber }
            if let unitNumber = unitNumber { unit.unitNumber = unitNumber }
            if let gridX = gridX { unit.gridX = gridX }
            if let gridY = gridY { unit.gridY = gridY }
            if let gridWidth = gridWidth { unit.gridWidth = gridWidth }
            if let gridHeight = gridHeight { unit.gridHeight = gridHeight }
            if let rotation = rotation { unit.rotation = rotation }
            if let frontFace = frontFace { unit.frontFace = frontFace }
            if let isConfigured = isConfigured { unit.isConfigured = isConfigured }
            if let zoneId = zoneId { unit.zoneId = zoneId }
            try unit.update(dbConn)
        }
    }

    /// Convenience: create a storage unit with all levels and areas in one call.
    ///
    /// Creates the unit record, then `levels` level records, each with
    /// `areasPerLevel` area records. Location codes are auto-generated.
    @discardableResult
    public func createStorageUnit(
        floorPlanId: Int64,
        name: String,
        unitType: String,
        levels: Int,
        areasPerLevel: Int
    ) throws -> WarehouseStorageUnit {
        let existingUnits = try listStorageUnits(floorPlanId: floorPlanId)
        let unitIndex = existingUnits.count + 1
        let rowNumber = String(format: "R%02d", 1)
        let unitNumber = String(format: "U%02d", unitIndex)

        let unit = try addStorageUnit(
            floorPlanId: floorPlanId,
            name: name,
            unitType: unitType,
            rowNumber: rowNumber,
            unitNumber: unitNumber
        )

        guard let unitId = unit.id else { return unit }

        for levelIdx in 1...levels {
            let levelCode = String(format: "S%02d", levelIdx)
            let level = try addStorageLevel(
                unitId: unitId,
                levelCode: levelCode,
                levelName: "Level \(levelIdx)",
                order: levelIdx,
                areaCount: areasPerLevel
            )

            guard let levelId = level.id else { continue }

            for areaIdx in 1...areasPerLevel {
                _ = try addStorageArea(levelId: levelId, areaNumber: areaIdx)
            }
        }

        try updateStorageUnit(id: unitId, isConfigured: true)

        return unit
    }

    /// Soft delete a storage unit.
    public func deleteStorageUnit(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_storage_units SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Storage Levels
    // =========================================================================

    /// Add a level to a storage unit.
    public func addStorageLevel(
        unitId: Int64, levelCode: String, levelName: String? = nil,
        order: Int = 0, heightInches: Int? = nil, areaCount: Int = 1
    ) throws -> WarehouseStorageLevel {
        try db.writer.write { dbConn in
            var level = WarehouseStorageLevel(
                unitId: unitId,
                levelCode: levelCode,
                levelName: levelName,
                levelOrder: order,
                heightInches: heightInches,
                areaCount: areaCount
            )
            try level.insert(dbConn)
            return level
        }
    }

    /// List levels for a storage unit, ordered bottom to top.
    public func listLevelsForUnit(unitId: Int64) throws -> [WarehouseStorageLevel] {
        try db.writer.read { dbConn in
            try WarehouseStorageLevel
                .filter(Column("unit_id") == unitId && Column("deleted_at") == nil)
                .order(Column("level_order"))
                .fetchAll(dbConn)
        }
    }

    /// Soft delete a storage level.
    public func deleteStorageLevel(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_storage_levels SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Storage Areas
    // =========================================================================

    /// Add an area to a storage level.
    public func addStorageArea(
        levelId: Int64, areaNumber: Int, widthInches: Int? = nil
    ) throws -> WarehouseStorageArea {
        try db.writer.write { dbConn in
            let areaCode = String(format: "A%02d", areaNumber)
            var area = WarehouseStorageArea(
                levelId: levelId,
                areaCode: areaCode,
                areaNumber: areaNumber,
                widthInches: widthInches,
                hasQrCode: false,
                hasSticker: false
            )
            try area.insert(dbConn)

            // Auto-generate full location code
            if let areaId = area.id {
                let code = try generateFullLocationCode(areaId: areaId, dbConn: dbConn)
                try dbConn.execute(
                    sql: "UPDATE warehouse_storage_areas SET full_location_code = ? WHERE id = ?",
                    arguments: [code, areaId]
                )
                area.fullLocationCode = code
            }
            return area
        }
    }

    /// List areas for a storage level.
    public func listAreasForLevel(levelId: Int64) throws -> [WarehouseStorageArea] {
        try db.writer.read { dbConn in
            try WarehouseStorageArea
                .filter(Column("level_id") == levelId && Column("deleted_at") == nil)
                .order(Column("area_number"))
                .fetchAll(dbConn)
        }
    }

    /// Soft delete a storage area.
    public func deleteStorageArea(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_storage_areas SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Bins
    // =========================================================================

    /// Add a bin to an area.
    public func addBin(areaId: Int64, binNumber: Int, isFixed: Bool = false) throws -> WarehouseBin {
        try db.writer.write { dbConn in
            let binCode = String(format: "B%02d", binNumber)
            var bin = WarehouseBin(
                areaId: areaId,
                binCode: binCode,
                binNumber: binNumber,
                isFixed: isFixed
            )
            try bin.insert(dbConn)
            return bin
        }
    }

    /// List bins for an area.
    public func listBinsForArea(areaId: Int64) throws -> [WarehouseBin] {
        try db.writer.read { dbConn in
            try WarehouseBin
                .filter(Column("area_id") == areaId && Column("deleted_at") == nil)
                .order(Column("bin_number"))
                .fetchAll(dbConn)
        }
    }

    /// Assign a part to a bin.
    public func assignPartToBin(binId: Int64, partId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_bins SET assigned_part_id = ? WHERE id = ?",
                arguments: [partId, binId]
            )
        }
    }

    /// Move multiple bins to a target area in a single transaction (Cart Mode multi-bin transfer).
    ///
    /// Updates `area_id` for each bin in `binIds`. Bins not found in the database are silently
    /// skipped so partial-cart moves don't abort on a stale ID.
    public func moveBinsToArea(binIds: [Int64], targetAreaId: Int64) throws {
        guard !binIds.isEmpty else { return }
        try db.writer.write { dbConn in
            for binId in binIds {
                try dbConn.execute(
                    sql: "UPDATE warehouse_bins SET area_id = ? WHERE id = ? AND deleted_at IS NULL",
                    arguments: [targetAreaId, binId]
                )
            }
        }
    }

    /// Save a storage unit's grid placement and zone assignment (Cart Mode placement step).
    ///
    /// Thin, intent-named wrapper over `updateStorageUnit` for use by Cart mode UI.
    public func saveUnitPlacement(unitId: Int64, gridX: Int, gridY: Int, zoneId: Int64?) throws {
        try updateStorageUnit(id: unitId, gridX: gridX, gridY: gridY, zoneId: zoneId)
    }

    // =========================================================================
    // MARK: - Part Assignments
    // =========================================================================

    /// Assign a part to a storage area.
    public func assignPartToArea(partId: Int64, areaId: Int64, isHome: Bool = false) throws -> WarehousePartAssignment {
        try db.writer.write { dbConn in
            var assignment = WarehousePartAssignment(
                partId: partId,
                areaId: areaId,
                isHome: isHome
            )
            try assignment.insert(dbConn)
            return assignment
        }
    }

    /// Row type for part assignment query results.
    public struct PartAssignmentInfo: Sendable {
        public let assignmentId: Int64
        public let areaId: Int64
        public let areaCode: String
        public let fullLocationCode: String?
        public let isHome: Bool
        public let unitName: String
        public let levelCode: String
    }

    /// Get all assignments for a part with location info.
    public func getPartAssignments(partId: Int64) throws -> [PartAssignmentInfo] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT pa.id as assignment_id, pa.area_id, pa.is_home,
                       sa.area_code, sa.full_location_code,
                       su.name as unit_name, sl.level_code
                FROM warehouse_part_assignments pa
                JOIN warehouse_storage_areas sa ON sa.id = pa.area_id
                JOIN warehouse_storage_levels sl ON sl.id = sa.level_id
                JOIN warehouse_storage_units su ON su.id = sl.unit_id
                WHERE pa.part_id = ? AND pa.deleted_at IS NULL
                ORDER BY pa.is_home DESC, su.name, sl.level_order, sa.area_number
                """, arguments: [partId])

            return rows.map { row in
                PartAssignmentInfo(
                    assignmentId: row["assignment_id"],
                    areaId: row["area_id"],
                    areaCode: row["area_code"] ?? "",
                    fullLocationCode: row["full_location_code"],
                    isHome: (row["is_home"] as Int?) == 1,
                    unitName: row["unit_name"] ?? "",
                    levelCode: row["level_code"] ?? ""
                )
            }
        }
    }

    /// Remove a part assignment (soft delete).
    public func removePartAssignment(assignmentId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_part_assignments SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [assignmentId]
            )
        }
    }

    /// Row type for area contents query.
    public struct AreaContentsItem: Sendable {
        public let partId: Int64
        public let partName: String
        public let partNumber: String?
        public let isHome: Bool
    }

    /// Get the parts assigned to an area.
    public func getAreaContents(areaId: Int64) throws -> [AreaContentsItem] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT pa.part_id, pa.is_home,
                       COALESCE(p.name, '') as part_name,
                       p.code as part_number
                FROM warehouse_part_assignments pa
                JOIN parts p ON p.id = pa.part_id
                WHERE pa.area_id = ? AND pa.deleted_at IS NULL AND p.deleted_at IS NULL
                ORDER BY p.name
                """, arguments: [areaId])

            return rows.map { row in
                AreaContentsItem(
                    partId: row["part_id"] ?? 0,
                    partName: row["part_name"] ?? "",
                    partNumber: row["part_number"],
                    isHome: (row["is_home"] as Int?) == 1
                )
            }
        }
    }

    // =========================================================================
    // MARK: - Location Code Generation
    // =========================================================================

    /// Generate a full location code for a storage area (e.g. R01-U01-S02-A04).
    public func generateFullLocationCode(areaId: Int64) throws -> String {
        try db.writer.read { dbConn in
            try generateFullLocationCode(areaId: areaId, dbConn: dbConn)
        }
    }

    /// Internal location code generator — usable inside a transaction.
    private func generateFullLocationCode(areaId: Int64, dbConn: Database) throws -> String {
        let row = try Row.fetchOne(dbConn, sql: """
            SELECT su.row_number, su.unit_number, sl.level_code, sa.area_code
            FROM warehouse_storage_areas sa
            JOIN warehouse_storage_levels sl ON sl.id = sa.level_id
            JOIN warehouse_storage_units su ON su.id = sl.unit_id
            WHERE sa.id = ?
            """, arguments: [areaId])

        let rowNum = (row?["row_number"] as String?) ?? "R00"
        let unitNum = (row?["unit_number"] as String?) ?? "U00"
        let levelCode = (row?["level_code"] as String?) ?? "S00"
        let areaCode = (row?["area_code"] as String?) ?? "A00"

        return "\(rowNum)-\(unitNum)-\(levelCode)-\(areaCode)"
    }

    // =========================================================================
    // MARK: - Navigation & QR Integration
    // =========================================================================

    /// Directional guidance between two areas.
    public struct DirectionResult: Sendable {
        public let fromCode: String
        public let toCode: String
        public let rowDiff: Int
        public let unitDiff: Int
        public let instructions: String
    }

    /// Get directions from one area to another.
    public func getDirections(fromAreaId: Int64, toAreaId: Int64) throws -> DirectionResult {
        try db.writer.read { dbConn in
            let fromRow = try Row.fetchOne(dbConn, sql: """
                SELECT su.row_number, su.unit_number, su.grid_x, su.grid_y,
                       sa.full_location_code
                FROM warehouse_storage_areas sa
                JOIN warehouse_storage_levels sl ON sl.id = sa.level_id
                JOIN warehouse_storage_units su ON su.id = sl.unit_id
                WHERE sa.id = ?
                """, arguments: [fromAreaId])

            let toRow = try Row.fetchOne(dbConn, sql: """
                SELECT su.row_number, su.unit_number, su.grid_x, su.grid_y,
                       sa.full_location_code, sl.level_code, sa.area_code
                FROM warehouse_storage_areas sa
                JOIN warehouse_storage_levels sl ON sl.id = sa.level_id
                JOIN warehouse_storage_units su ON su.id = sl.unit_id
                WHERE sa.id = ?
                """, arguments: [toAreaId])

            let fromCode = (fromRow?["full_location_code"] as String?) ?? "?"
            let toCode = (toRow?["full_location_code"] as String?) ?? "?"

            let fromX = (fromRow?["grid_x"] as Int?) ?? 0
            let toX = (toRow?["grid_x"] as Int?) ?? 0
            let fromY = (fromRow?["grid_y"] as Int?) ?? 0
            let toY = (toRow?["grid_y"] as Int?) ?? 0

            let dx = toX - fromX
            let dy = toY - fromY

            // Parse row numbers as integers for difference
            let fromRowNum = Self.parseRowNumber(fromRow?["row_number"] as String?)
            let toRowNum = Self.parseRowNumber(toRow?["row_number"] as String?)
            let rowDiff = toRowNum - fromRowNum

            let fromUnitNum = Self.parseUnitNumber(fromRow?["unit_number"] as String?)
            let toUnitNum = Self.parseUnitNumber(toRow?["unit_number"] as String?)
            let unitDiff = toUnitNum - fromUnitNum

            // Build human-readable instructions
            var parts: [String] = []
            if dx > 0 { parts.append("Go RIGHT \(dx) columns") }
            else if dx < 0 { parts.append("Go LEFT \(-dx) columns") }
            if dy > 0 { parts.append("Go DOWN \(dy) rows") }
            else if dy < 0 { parts.append("Go UP \(-dy) rows") }

            let toUnit = (toRow?["unit_number"] as String?) ?? "?"
            let toLevel = (toRow?["level_code"] as String?) ?? "?"
            let toArea = (toRow?["area_code"] as String?) ?? "?"
            parts.append("Unit \(toUnit), \(toLevel), \(toArea)")

            let instructions = parts.joined(separator: ", ")

            return DirectionResult(
                fromCode: fromCode, toCode: toCode,
                rowDiff: rowDiff, unitDiff: unitDiff,
                instructions: instructions
            )
        }
    }

    /// Update user's last known position from a scan.
    public func setUserCurrentPosition(userId: Int64, areaId: Int64) throws {
        // Store in a lightweight way — user_settings or a dedicated table.
        // For now, use a simple key-value approach via the change log.
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT OR REPLACE INTO warehouse_user_positions (user_id, area_id, updated_at)
                    VALUES (?, ?, datetime('now'))
                    """,
                arguments: [userId, areaId]
            )
        }
    }

    /// Get user's last known warehouse position.
    public func getUserCurrentPosition(userId: Int64) throws -> Int64? {
        try db.writer.read { dbConn in
            try Int64.fetchOne(dbConn, sql: """
                SELECT area_id FROM warehouse_user_positions WHERE user_id = ?
                """, arguments: [userId])
        }
    }

    /// Location info from a QR code scan.
    public struct LocationScanInfo: Sendable {
        public let areaId: Int64
        public let fullLocationCode: String
        public let unitName: String
        public let levelName: String
        public let areaCode: String
        public let parts: [AreaContentsItem]
    }

    /// Look up a location by its full QR code string.
    public func getLocationByQR(qrCode: String) throws -> LocationScanInfo? {
        try db.writer.read { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT sa.id as area_id, sa.full_location_code, sa.area_code,
                       su.name as unit_name,
                       COALESCE(sl.level_name, sl.level_code) as level_name
                FROM warehouse_storage_areas sa
                JOIN warehouse_storage_levels sl ON sl.id = sa.level_id
                JOIN warehouse_storage_units su ON su.id = sl.unit_id
                WHERE sa.full_location_code = ? AND sa.deleted_at IS NULL
                """, arguments: [qrCode]) else { return nil }

            let areaId: Int64 = row["area_id"]
            let parts = try getAreaContentsList(areaId: areaId, dbConn: dbConn)

            return LocationScanInfo(
                areaId: areaId,
                fullLocationCode: row["full_location_code"] ?? qrCode,
                unitName: row["unit_name"] ?? "",
                levelName: row["level_name"] ?? "",
                areaCode: row["area_code"] ?? "",
                parts: parts
            )
        }
    }

    /// Reusable area contents fetch inside a read transaction.
    private func getAreaContentsList(areaId: Int64, dbConn: Database) throws -> [AreaContentsItem] {
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT pa.part_id, pa.is_home,
                   COALESCE(p.name, '') as part_name,
                   p.code as part_number
            FROM warehouse_part_assignments pa
            JOIN parts p ON p.id = pa.part_id
            WHERE pa.area_id = ? AND pa.deleted_at IS NULL AND p.deleted_at IS NULL
            ORDER BY p.name
            """, arguments: [areaId])

        return rows.map { row in
            AreaContentsItem(
                partId: row["part_id"] ?? 0,
                partName: row["part_name"] ?? "",
                partNumber: row["part_number"],
                isHome: (row["is_home"] as Int?) == 1
            )
        }
    }

    /// Parse row number from string (e.g. "R01" → 1).
    private static func parseRowNumber(_ str: String?) -> Int {
        guard let s = str, s.count > 1 else { return 0 }
        return Int(s.dropFirst()) ?? 0
    }

    /// Parse unit number from string (e.g. "U01" → 1).
    private static func parseUnitNumber(_ str: String?) -> Int {
        guard let s = str, s.count > 1 else { return 0 }
        return Int(s.dropFirst()) ?? 0
    }

    // =========================================================================
    // MARK: - Onboarding Wizard
    // =========================================================================

    /// Get current onboarding progress, or nil if none exists.
    public func getOnboardingProgress() throws -> WarehouseOnboardingProgress? {
        try db.writer.read { dbConn in
            try WarehouseOnboardingProgress
                .filter(Column("completed_at") == nil)
                .order(Column("id").desc)
                .fetchOne(dbConn)
        }
    }

    /// Start a new onboarding session.
    public func startOnboarding(floorPlanId: Int64? = nil) throws -> WarehouseOnboardingProgress {
        try db.writer.write { dbConn in
            var progress = WarehouseOnboardingProgress(
                floorPlanId: floorPlanId,
                currentStep: 1,
                step1Complete: false,
                step2Complete: false,
                step3Complete: false,
                flowType: "floor_plan",
                totalSteps: 6
            )
            try progress.insert(dbConn)
            return progress
        }
    }

    /// Update onboarding step progress.
    public func updateOnboardingStep(
        id: Int64, currentStep: Int,
        step1Complete: Bool? = nil, step2Complete: Bool? = nil, step3Complete: Bool? = nil,
        step4Progress: String? = nil, step5Progress: String? = nil, step6Progress: String? = nil,
        floorPlanId: Int64? = nil
    ) throws {
        try db.writer.write { dbConn in
            guard var progress = try WarehouseOnboardingProgress.fetchOne(dbConn, key: id) else { return }
            progress.currentStep = currentStep
            if let s1 = step1Complete { progress.step1Complete = s1 }
            if let s2 = step2Complete { progress.step2Complete = s2 }
            if let s3 = step3Complete { progress.step3Complete = s3 }
            if let s4 = step4Progress { progress.step4Progress = s4 }
            if let s5 = step5Progress { progress.step5Progress = s5 }
            if let s6 = step6Progress { progress.step6Progress = s6 }
            if let fp = floorPlanId { progress.floorPlanId = fp }
            try progress.update(dbConn)
        }
    }

    /// Complete the onboarding process.
    public func completeOnboarding(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE warehouse_onboarding_progress SET completed_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Audit Confidence System
    // =========================================================================

    // MARK: Confidence CRUD

    /// Get the confidence record for a part at a specific area.
    public func getPartConfidence(partId: Int64, areaId: Int64) throws -> PartConfidence? {
        try db.writer.read { dbConn in
            try PartConfidence
                .filter(Column("part_id") == partId && Column("area_id") == areaId)
                .fetchOne(dbConn)
        }
    }

    /// Set or create the confidence percentage for a part at an area.
    public func setPartConfidence(partId: Int64, areaId: Int64, percent: Double) throws {
        try db.writer.write { dbConn in
            if var existing = try PartConfidence
                .filter(Column("part_id") == partId && Column("area_id") == areaId)
                .fetchOne(dbConn) {
                existing.confidencePercent = min(100, max(0, percent))
                existing.updatedAt = Self.nowString()
                try existing.update(dbConn)
            } else {
                var record = PartConfidence(
                    id: nil, partId: partId, areaId: areaId,
                    confidencePercent: min(100, max(0, percent)),
                    reliabilityLevel: 0,
                    lastAuditDate: nil, lastAuditBy: nil, lastAuditCount: nil,
                    systemCount: 0, decayRate: 0.066, movementDecayFactor: 1.0,
                    cleanAuditStreak: 0, misplacementCount: 0, lastMisplacementDate: nil,
                    totalAuditCount: 0, totalVarianceDollars: 0.0,
                    createdAt: nil, updatedAt: nil
                )
                try record.insert(dbConn)
            }
        }
    }

    /// Apply daily decay to all confidence scores. Called by a scheduled job.
    public func decayAllConfidence() throws {
        try db.writer.write { dbConn in
            // confidence_percent -= decay_rate * movement_decay_factor, clamped to 0
            try dbConn.execute(sql: """
                UPDATE part_confidence
                SET confidence_percent = MAX(0, confidence_percent - (decay_rate * movement_decay_factor)),
                    updated_at = datetime('now')
                WHERE confidence_percent > 0
                """)
        }
    }

    /// Record an individual audit count and update confidence accordingly.
    @discardableResult
    public func recordAuditCount(
        sessionId: Int64,
        partId: Int64,
        areaId: Int64,
        systemCount: Int,
        userCount: Int,
        countedBy: Int64,
        unitCostDollars: Double = 0
    ) throws -> AuditCount {
        try db.writer.write { dbConn in
            let variance = userCount - systemCount
            let varianceDollars = Double(abs(variance)) * unitCostDollars
            let variancePercent: Double = systemCount > 0 ? (Double(abs(variance)) / Double(systemCount)) * 100.0 : (variance == 0 ? 0 : 100)
            let result: String
            if variance == 0 { result = "exact" }
            else if abs(variance) == 1 { result = "neutral" }
            else if variance > 0 { result = "over" }
            else { result = "under" }

            var count = AuditCount(
                id: nil, sessionId: sessionId, partId: partId, areaId: areaId,
                systemCount: systemCount, userCount: userCount,
                variance: variance, varianceDollars: varianceDollars,
                variancePercent: variancePercent, result: result,
                countedBy: countedBy, countedAt: nil
            )
            try count.insert(dbConn)

            // Update session totals
            try dbConn.execute(sql: """
                UPDATE audit_sessions_v2
                SET parts_counted = parts_counted + 1,
                    discrepancies_found = discrepancies_found + CASE WHEN ? != 0 THEN 1 ELSE 0 END
                WHERE id = ?
                """, arguments: [variance, sessionId])

            // Update or create confidence record
            if var conf = try PartConfidence
                .filter(Column("part_id") == partId && Column("area_id") == areaId)
                .fetchOne(dbConn) {
                let isClean = (variance == 0)
                conf.confidencePercent = isClean ? min(100, conf.confidencePercent + 25) : max(0, conf.confidencePercent - 15)
                conf.lastAuditDate = Self.nowString()
                conf.lastAuditBy = countedBy
                conf.lastAuditCount = userCount
                conf.systemCount = userCount // Reconcile to user count
                conf.totalAuditCount += 1
                conf.totalVarianceDollars += varianceDollars
                conf.cleanAuditStreak = isClean ? conf.cleanAuditStreak + 1 : 0
                conf.movementDecayFactor = 1.0 // Reset after audit
                conf.reliabilityLevel = Self.computeReliabilityLevel(conf)
                conf.updatedAt = Self.nowString()
                try conf.update(dbConn)
            } else {
                let isClean = (variance == 0)
                var conf = PartConfidence(
                    id: nil, partId: partId, areaId: areaId,
                    confidencePercent: isClean ? 75 : 50,
                    reliabilityLevel: isClean ? 3 : 1,
                    lastAuditDate: Self.nowString(), lastAuditBy: countedBy,
                    lastAuditCount: userCount, systemCount: userCount,
                    decayRate: 0.066, movementDecayFactor: 1.0,
                    cleanAuditStreak: isClean ? 1 : 0, misplacementCount: 0,
                    lastMisplacementDate: nil, totalAuditCount: 1,
                    totalVarianceDollars: varianceDollars,
                    createdAt: nil, updatedAt: nil
                )
                try conf.insert(dbConn)
            }

            return count
        }
    }

    /// Calculate movement-based decay factor for a part at an area.
    /// More movements since last audit = faster confidence decay.
    public func calculateMovementDecayFactor(partId: Int64, areaId: Int64) throws -> Double {
        try db.writer.read { dbConn in
            let lastAudit = try String?.fetchOne(dbConn, sql: """
                SELECT last_audit_date FROM part_confidence
                WHERE part_id = ? AND area_id = ?
                """, arguments: [partId, areaId]) ?? nil

            let sinceDate = lastAudit ?? "2000-01-01"
            let moveCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM stock_movements
                WHERE part_id = ? AND created_at > ?
                  AND (from_location_type = 'area' OR to_location_type = 'area')
                """, arguments: [partId, sinceDate]) ?? 0

            // 1.0 base + 0.2 per movement, capped at 3.0
            return min(3.0, 1.0 + Double(moveCount) * 0.2)
        }
    }

    // MARK: Reliability Level

    /// Compute reliability level 0-10 from a confidence record.
    private static func computeReliabilityLevel(_ conf: PartConfidence) -> Int {
        var score = 0.0
        // Confidence contributes up to 4 points
        score += (conf.confidencePercent / 100.0) * 4.0
        // Clean audit streak contributes up to 3 points
        score += min(3.0, Double(conf.cleanAuditStreak) * 0.5)
        // Low misplacement contributes up to 2 points
        if conf.misplacementCount == 0 { score += 2.0 }
        else if conf.misplacementCount < 3 { score += 1.0 }
        // Audit frequency contributes up to 1 point
        if conf.totalAuditCount >= 5 { score += 1.0 }
        else if conf.totalAuditCount >= 2 { score += 0.5 }
        return min(10, max(0, Int(score.rounded())))
    }

    /// Calculate and return the reliability level for a part at an area.
    public func calculateReliabilityLevel(partId: Int64, areaId: Int64) throws -> Int {
        guard let conf = try getPartConfidence(partId: partId, areaId: areaId) else { return 0 }
        return Self.computeReliabilityLevel(conf)
    }

    /// Get all part confidence records at a given reliability level.
    public func getPartsAtLevel(level: Int) throws -> [PartConfidence] {
        try db.writer.read { dbConn in
            try PartConfidence
                .filter(Column("reliability_level") == level)
                .order(Column("confidence_percent").desc)
                .fetchAll(dbConn)
        }
    }

    // MARK: Audit Sessions

    /// Start a new audit session.
    @discardableResult
    public func startAuditSession(
        sessionType: String = "count",
        startedBy: Int64,
        floorPlanId: Int64? = nil,
        targetAreaId: Int64? = nil,
        targetUnitId: Int64? = nil
    ) throws -> AuditSessionV2 {
        try db.writer.write { dbConn in
            var session = AuditSessionV2(
                id: nil, sessionType: sessionType, startedBy: startedBy,
                floorPlanId: floorPlanId, targetAreaId: targetAreaId,
                targetUnitId: targetUnitId, status: "active",
                partsCounted: 0, discrepanciesFound: 0, misplacedFound: 0,
                startedAt: nil, completedAt: nil, deletedAt: nil
            )
            try session.insert(dbConn)
            return session
        }
    }

    /// Complete an audit session.
    public func completeAuditSession(sessionId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE audit_sessions_v2
                SET status = 'completed', completed_at = datetime('now')
                WHERE id = ? AND status = 'active'
                """, arguments: [sessionId])
        }
    }

    /// Get an audit session by ID.
    public func getAuditSession(sessionId: Int64) throws -> AuditSessionV2? {
        try db.writer.read { dbConn in
            try AuditSessionV2.fetchOne(dbConn, key: sessionId)
        }
    }

    /// List audit sessions with optional filters.
    public func listAuditSessions(
        sessionType: String? = nil,
        status: String? = nil,
        limit: Int = 50
    ) throws -> [AuditSessionV2] {
        try db.writer.read { dbConn in
            var query = AuditSessionV2.filter(Column("deleted_at") == nil)
            if let st = sessionType { query = query.filter(Column("session_type") == st) }
            if let s = status { query = query.filter(Column("status") == s) }
            return try query.order(Column("started_at").desc).limit(limit).fetchAll(dbConn)
        }
    }

    /// Get audit counts for a session.
    public func getAuditCounts(sessionId: Int64) throws -> [AuditCount] {
        try db.writer.read { dbConn in
            try AuditCount
                .filter(Column("session_id") == sessionId)
                .order(Column("counted_at").desc)
                .fetchAll(dbConn)
        }
    }

    // MARK: User Ratings

    /// Get the warehouse rating for a user, creating a default if needed.
    public func getUserWarehouseRating(userId: Int64) throws -> UserWarehouseRating {
        try db.writer.write { dbConn in
            if let existing = try UserWarehouseRating
                .filter(Column("user_id") == userId)
                .fetchOne(dbConn) {
                return existing
            }
            var rating = UserWarehouseRating(
                id: nil, userId: userId,
                overallRating: 5.0, accuracyRating: 5.0, effortRating: 5.0,
                placementRating: 5.0, wizardCompliance: 5.0, speedRating: 5.0,
                proactiveRating: 5.0, totalAudits: 0, totalAccurate: 0,
                totalMisplacementsFound: 0, totalProactiveFixes: 0, updatedAt: nil
            )
            try rating.insert(dbConn)
            return rating
        }
    }

    /// Update a user's warehouse rating after an action.
    /// action: "audit", "misplacement_find", "proactive_fix"
    /// result: "accurate", "inaccurate" (for audits)
    public func updateUserRating(userId: Int64, action: String, result: String? = nil) throws {
        try db.writer.write { dbConn in
            // Ensure record exists
            var rating: UserWarehouseRating
            if let existing = try UserWarehouseRating
                .filter(Column("user_id") == userId)
                .fetchOne(dbConn) {
                rating = existing
            } else {
                rating = UserWarehouseRating(
                    id: nil, userId: userId,
                    overallRating: 5.0, accuracyRating: 5.0, effortRating: 5.0,
                    placementRating: 5.0, wizardCompliance: 5.0, speedRating: 5.0,
                    proactiveRating: 5.0, totalAudits: 0, totalAccurate: 0,
                    totalMisplacementsFound: 0, totalProactiveFixes: 0, updatedAt: nil
                )
                try rating.insert(dbConn)
            }

            switch action {
            case "audit":
                rating.totalAudits += 1
                rating.effortRating = min(10, rating.effortRating + 0.1)
                if result == "accurate" {
                    rating.totalAccurate += 1
                    rating.accuracyRating = min(10, rating.accuracyRating + 0.2)
                } else {
                    rating.accuracyRating = max(0, rating.accuracyRating - 0.1)
                }
            case "misplacement_find":
                rating.totalMisplacementsFound += 1
                rating.placementRating = min(10, rating.placementRating + 0.3)
            case "proactive_fix":
                rating.totalProactiveFixes += 1
                rating.proactiveRating = min(10, rating.proactiveRating + 0.3)
            default:
                break
            }

            // Recalculate overall as weighted average
            rating.overallRating = (
                rating.accuracyRating * 0.30 +
                rating.effortRating * 0.15 +
                rating.placementRating * 0.20 +
                rating.wizardCompliance * 0.10 +
                rating.speedRating * 0.10 +
                rating.proactiveRating * 0.15
            )
            rating.updatedAt = Self.nowString()
            try rating.update(dbConn)
        }
    }

    /// Get the warehouse leaderboard sorted by overall rating.
    public func getWarehouseLeaderboard() throws -> [UserWarehouseRating] {
        try db.writer.read { dbConn in
            try UserWarehouseRating
                .order(Column("overall_rating").desc)
                .fetchAll(dbConn)
        }
    }

    // MARK: Organization Ratings

    /// Get or create the organization rating for an area.
    public func getOrganizationRating(areaId: Int64) throws -> OrganizationRating {
        try db.writer.write { dbConn in
            if let existing = try OrganizationRating
                .filter(Column("area_id") == areaId)
                .fetchOne(dbConn) {
                return existing
            }
            var rating = OrganizationRating(
                id: nil, areaId: areaId,
                overallRating: 5.0,
                labelsAccurate: false, partsInHome: false, noDuplicates: false,
                notOvercrowded: false, binsAssigned: false, similarPartsNearby: false,
                cleanAuditCount: 0, lastOrgCheck: nil, lastOrgCheckBy: nil, updatedAt: nil
            )
            try rating.insert(dbConn)
            return rating
        }
    }

    /// Record an organization check for an area, updating the area's org rating.
    public func recordOrgCheck(
        areaId: Int64,
        checkedBy: Int64,
        labelsAccurate: Bool,
        partsInHome: Bool,
        noDuplicates: Bool,
        notOvercrowded: Bool,
        binsAssigned: Bool,
        similarPartsNearby: Bool = false
    ) throws {
        try db.writer.write { dbConn in
            var rating: OrganizationRating
            if let existing = try OrganizationRating
                .filter(Column("area_id") == areaId)
                .fetchOne(dbConn) {
                rating = existing
            } else {
                rating = OrganizationRating(
                    id: nil, areaId: areaId, overallRating: 5.0,
                    labelsAccurate: false, partsInHome: false, noDuplicates: false,
                    notOvercrowded: false, binsAssigned: false, similarPartsNearby: false,
                    cleanAuditCount: 0, lastOrgCheck: nil, lastOrgCheckBy: nil, updatedAt: nil
                )
                try rating.insert(dbConn)
            }

            rating.labelsAccurate = labelsAccurate
            rating.partsInHome = partsInHome
            rating.noDuplicates = noDuplicates
            rating.notOvercrowded = notOvercrowded
            rating.binsAssigned = binsAssigned
            rating.similarPartsNearby = similarPartsNearby
            rating.lastOrgCheck = Self.nowString()
            rating.lastOrgCheckBy = checkedBy

            // Calculate overall as fraction of checks passed (0-10 scale)
            let checks: [Bool] = [labelsAccurate, partsInHome, noDuplicates, notOvercrowded, binsAssigned, similarPartsNearby]
            let passed = checks.filter { $0 }.count
            rating.overallRating = (Double(passed) / Double(checks.count)) * 10.0

            if passed == checks.count {
                rating.cleanAuditCount += 1
            }

            rating.updatedAt = Self.nowString()
            try rating.update(dbConn)
        }
    }

    /// Get the composite warehouse score (0-10) across all areas.
    public func getWarehouseOverallScore() throws -> Double {
        try db.writer.read { dbConn in
            let avg = try Double.fetchOne(dbConn, sql: """
                SELECT AVG(overall_rating) FROM organization_ratings
                """) ?? 5.0
            return avg
        }
    }

    // MARK: Consolidation

    /// Suggest consolidation for a part spread across multiple areas.
    @discardableResult
    public func suggestConsolidation(partId: Int64) throws -> ConsolidationVote? {
        try db.writer.write { dbConn in
            // Find all areas this part is assigned to
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT area_id FROM warehouse_part_assignments
                WHERE part_id = ? AND deleted_at IS NULL AND is_home = 1
                """, arguments: [partId])

            let areaIds = rows.compactMap { $0["area_id"] as Int64? }
            guard areaIds.count > 1 else { return nil }

            // Check if there's already an active vote
            if let existing = try ConsolidationVote
                .filter(Column("part_id") == partId && Column("status") == "voting" && Column("deleted_at") == nil)
                .fetchOne(dbConn) {
                return existing
            }

            let areasJSON = try JSONEncoder().encode(areaIds)
            let areasString = String(data: areasJSON, encoding: .utf8) ?? "[]"

            var vote = ConsolidationVote(
                id: nil, partId: partId, currentAreas: areasString,
                chosenAreaId: nil, status: "voting", managerOverride: false,
                dismissReason: nil, ignoreCount: 0,
                createdAt: nil, decidedAt: nil, deletedAt: nil
            )
            try vote.insert(dbConn)
            return vote
        }
    }

    /// Cast a user's vote on a consolidation suggestion.
    public func castConsolidationVote(voteId: Int64, userId: Int64, chosenAreaId: Int64) throws {
        try db.writer.write { dbConn in
            var entry = ConsolidationVoteEntry(
                id: nil, voteId: voteId, userId: userId,
                chosenAreaId: chosenAreaId, votedAt: nil
            )
            try entry.insert(dbConn)
        }
    }

    /// Manager overrides a consolidation vote, choosing the final area.
    public func managerOverrideConsolidation(voteId: Int64, chosenAreaId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE consolidation_votes
                SET chosen_area_id = ?, status = 'decided', manager_override = 1,
                    decided_at = datetime('now')
                WHERE id = ?
                """, arguments: [chosenAreaId, voteId])
        }
    }

    /// Apply a decided consolidation — marks it as applied.
    /// The actual movement should be created separately via the movement wizard.
    public func applyConsolidation(voteId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE consolidation_votes
                SET status = 'applied'
                WHERE id = ? AND status = 'decided'
                """, arguments: [voteId])
        }
    }

    /// Dismiss a consolidation suggestion.
    public func dismissConsolidation(voteId: Int64, reason: String?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE consolidation_votes
                SET status = 'dismissed', dismiss_reason = ?,
                    ignore_count = ignore_count + 1
                WHERE id = ?
                """, arguments: [reason, voteId])
        }
    }

    /// Get active consolidation votes.
    public func getActiveConsolidationVotes() throws -> [ConsolidationVote] {
        try db.writer.read { dbConn in
            try ConsolidationVote
                .filter(Column("status") == "voting" && Column("deleted_at") == nil)
                .order(Column("created_at").desc)
                .fetchAll(dbConn)
        }
    }

    // MARK: Misplaced Parts

    /// Log a part found in the wrong location.
    @discardableResult
    public func logMisplacedPart(
        partId: Int64,
        foundAtAreaId: Int64,
        homeAreaId: Int64?,
        qtyFound: Int,
        foundBy: Int64
    ) throws -> MisplacedPartsLog {
        try db.writer.write { dbConn in
            var log = MisplacedPartsLog(
                id: nil, partId: partId,
                foundAtAreaId: foundAtAreaId, homeAreaId: homeAreaId,
                qtyFound: qtyFound, resolution: "pending",
                resolvedBy: nil, resolvedAt: nil,
                foundBy: foundBy, foundAt: nil
            )
            try log.insert(dbConn)

            // Update confidence misplacement count
            if var conf = try PartConfidence
                .filter(Column("part_id") == partId && Column("area_id") == foundAtAreaId)
                .fetchOne(dbConn) {
                conf.misplacementCount += 1
                conf.lastMisplacementDate = Self.nowString()
                conf.confidencePercent = max(0, conf.confidencePercent - 10)
                conf.reliabilityLevel = Self.computeReliabilityLevel(conf)
                conf.updatedAt = Self.nowString()
                try conf.update(dbConn)
            }

            // Update audit session if active
            try dbConn.execute(sql: """
                UPDATE audit_sessions_v2
                SET misplaced_found = misplaced_found + 1
                WHERE status = 'active' AND started_by = ?
                ORDER BY started_at DESC LIMIT 1
                """, arguments: [foundBy])

            return log
        }
    }

    /// Resolve a misplaced part entry.
    public func resolveMisplacedPart(logId: Int64, resolution: String, resolvedBy: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE misplaced_parts_log
                SET resolution = ?, resolved_by = ?, resolved_at = datetime('now')
                WHERE id = ?
                """, arguments: [resolution, resolvedBy, logId])
        }
    }

    /// Get pending misplaced parts.
    public func getPendingMisplacedParts() throws -> [MisplacedPartsLog] {
        try db.writer.read { dbConn in
            try MisplacedPartsLog
                .filter(Column("resolution") == "pending")
                .order(Column("found_at").desc)
                .fetchAll(dbConn)
        }
    }

    // MARK: - Part Name Lookup

    /// Get a part's display name by ID.
    public func getPartName(partId: Int64) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: """
                SELECT COALESCE(name, description, 'Part #' || id) FROM parts WHERE id = ?
                """, arguments: [partId])
        }
    }

    /// Get a part's code by ID.
    public func getPartCode(partId: Int64) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: """
                SELECT code FROM parts WHERE id = ?
                """, arguments: [partId])
        }
    }

    // =========================================================================
    // MARK: - Report Queries
    // =========================================================================

    /// Inventory value grouped by category.
    public struct InventoryValueRow: Sendable, Identifiable {
        public let id: Int64
        public let categoryName: String
        public let itemCount: Int
        public let onHandValue: Double
        public let onOrderValue: Double
    }

    /// Backorder status row.
    public struct BackorderRow: Sendable, Identifiable {
        public let id: Int64
        public let partName: String
        public let partCode: String?
        public let qtyOrdered: Int
        public let qtyReceived: Int
        public let qtyBackordered: Int
        public let expectedDate: String?
        public let supplierName: String?
    }

    /// Inventory turnover row — movement activity per part.
    public struct TurnoverRow: Sendable, Identifiable {
        public let id: Int64
        public let partName: String
        public let partCode: String?
        public let movementCount: Int
        public let totalQtyMoved: Int
        public let currentStock: Int
    }

    /// Get inventory value grouped by category.
    public func getInventoryValueReport() throws -> [InventoryValueRow] {
        do {
            return try db.writer.read { dbConn -> [InventoryValueRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT pc.id, pc.name AS category_name,
                           COUNT(DISTINCT p.id) AS item_count,
                           COALESCE(SUM(s.qty * p.weighted_avg_cost), 0) AS on_hand_value,
                           COALESCE(
                               (SELECT SUM(pol.qty_ordered - pol.qty_received) * COALESCE(pol.unit_cost, p.company_cost_price)
                                FROM po_line_items pol
                                JOIN purchase_orders po ON po.id = pol.po_id
                                WHERE pol.part_id = p.id AND pol.deleted_at IS NULL
                                  AND po.deleted_at IS NULL AND po.status IN ('sent', 'partial')
                                  AND pol.qty_received < pol.qty_ordered), 0) AS on_order_value
                    FROM part_categories pc
                    LEFT JOIN parts p ON p.category_id = pc.id AND p.deleted_at IS NULL AND p.is_active = 1
                    LEFT JOIN stock s ON s.part_id = p.id AND s.deleted_at IS NULL AND s.location_type = 'warehouse'
                    WHERE pc.deleted_at IS NULL
                    GROUP BY pc.id
                    ORDER BY on_hand_value DESC
                    """)
                return rows.map { row in
                    InventoryValueRow(
                        id: row["id"] ?? 0,
                        categoryName: row["category_name"] ?? "Uncategorized",
                        itemCount: row["item_count"] ?? 0,
                        onHandValue: row["on_hand_value"] ?? 0,
                        onOrderValue: row["on_order_value"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get backorder status — PO line items not fully received.
    public func getBackorderReport() throws -> [BackorderRow] {
        do {
            return try db.writer.read { dbConn -> [BackorderRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT pol.id, COALESCE(p.name, 'Unknown Part') AS part_name,
                           p.code AS part_code,
                           pol.qty_ordered, pol.qty_received,
                           (pol.qty_ordered - pol.qty_received) AS qty_backordered,
                           pol.backorder_expected_date AS expected_date,
                           sup.name AS supplier_name
                    FROM po_line_items pol
                    JOIN purchase_orders po ON po.id = pol.po_id
                    LEFT JOIN parts p ON p.id = pol.part_id
                    LEFT JOIN suppliers sup ON sup.id = po.supplier_id
                    WHERE pol.deleted_at IS NULL AND po.deleted_at IS NULL
                      AND pol.qty_received < pol.qty_ordered
                      AND po.status IN ('sent', 'partial')
                    ORDER BY qty_backordered DESC
                    """)
                return rows.map { row in
                    BackorderRow(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] as String?,
                        qtyOrdered: row["qty_ordered"] ?? 0,
                        qtyReceived: row["qty_received"] ?? 0,
                        qtyBackordered: row["qty_backordered"] ?? 0,
                        expectedDate: row["expected_date"] as String?,
                        supplierName: row["supplier_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get inventory turnover — parts with the most movement activity.
    public func getTurnoverReport(startDate: Date, endDate: Date) throws -> [TurnoverRow] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)
        do {
            return try db.writer.read { dbConn -> [TurnoverRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT p.id, COALESCE(p.name, 'Unknown') AS part_name, p.code AS part_code,
                           COUNT(sm.id) AS movement_count,
                           COALESCE(SUM(ABS(sm.qty)), 0) AS total_qty_moved,
                           COALESCE((SELECT SUM(s.qty) FROM stock s
                                     WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS current_stock
                    FROM parts p
                    JOIN stock_movements sm ON sm.part_id = p.id
                        AND sm.deleted_at IS NULL
                        AND date(sm.created_at) >= ? AND date(sm.created_at) <= ?
                    WHERE p.deleted_at IS NULL
                    GROUP BY p.id
                    ORDER BY movement_count DESC
                    LIMIT 50
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    TurnoverRow(
                        id: row["id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] as String?,
                        movementCount: row["movement_count"] ?? 0,
                        totalQtyMoved: row["total_qty_moved"] ?? 0,
                        currentStock: row["current_stock"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Stock by Location Type

    /// Aggregate stock summary for a part grouped by location_type.
    public struct PartStockByLocationType: Sendable {
        public let locationType: String
        public let totalQty: Int

        public init(locationType: String, totalQty: Int) {
            self.locationType = locationType
            self.totalQty = totalQty
        }
    }

    /// Returns stock quantities for a part grouped by location_type (warehouse, truck, etc.).
    public func getPartStockByLocationType(partId: Int64) throws -> [PartStockByLocationType] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT s.location_type, SUM(s.qty) AS total_qty
                FROM stock s
                WHERE s.part_id = ? AND s.qty > 0 AND s.deleted_at IS NULL
                GROUP BY s.location_type
                ORDER BY total_qty DESC
                """, arguments: [partId])
            return rows.map { row in
                PartStockByLocationType(
                    locationType: row["location_type"] ?? "unknown",
                    totalQty: row["total_qty"] ?? 0
                )
            }
        }
    }

    // MARK: - Distinct Stock Locations

    /// A distinct stock location (e.g. "warehouse #1", "truck #3").
    public struct DistinctStockLocation: Sendable, Identifiable {
        public let id: String
        public let locationType: String
        public let locationId: Int64
        public let name: String

        public init(locationType: String, locationId: Int64, name: String) {
            self.id = "\(locationType)_\(locationId)"
            self.locationType = locationType
            self.locationId = locationId
            self.name = name
        }
    }

    /// Returns all distinct stock locations that currently hold stock.
    public func listDistinctStockLocations() throws -> [DistinctStockLocation] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT DISTINCT s.location_type, s.location_id,
                    COALESCE(wl.name, v.vehicle_name, 'Location ' || s.location_id) AS name
                FROM stock s
                LEFT JOIN warehouse_locations wl ON s.location_type = 'warehouse' AND wl.id = s.location_id
                LEFT JOIN vehicles v ON s.location_type IN ('truck', 'trailer') AND v.id = s.location_id
                WHERE s.deleted_at IS NULL AND s.qty > 0
                GROUP BY s.location_type, s.location_id
                ORDER BY s.location_type, name
                """)
            return rows.map { row in
                DistinctStockLocation(
                    locationType: row["location_type"] ?? "warehouse",
                    locationId: row["location_id"] ?? 1,
                    name: row["name"] ?? "Unknown"
                )
            }
        }
    }

    // MARK: - Warehouse Location Name Lookup

    /// Look up the human-readable name for a single warehouse location.
    /// Returns `nil` if the location doesn't exist or has been soft-deleted.
    public func getWarehouseLocationName(id: Int64) throws -> String? {
        try db.writer.read { dbConn in
            try String.fetchOne(dbConn, sql: """
                SELECT name FROM warehouse_locations WHERE id = ? AND deleted_at IS NULL
                """, arguments: [id])
        }
    }

    /// Batch-lookup human-readable names for multiple warehouse locations.
    /// Returns a dictionary mapping location ID to name. Missing or deleted locations are omitted.
    public func getWarehouseLocationNames(ids: [Int64]) throws -> [Int64: String] {
        guard !ids.isEmpty else { return [:] }
        return try db.writer.read { dbConn in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT id, name FROM warehouse_locations
                WHERE id IN (\(placeholders)) AND deleted_at IS NULL
                """, arguments: StatementArguments(ids))
            var result: [Int64: String] = [:]
            for row in rows {
                if let id: Int64 = row["id"], let name: String = row["name"] {
                    result[id] = name
                }
            }
            return result
        }
    }

    // =========================================================================
    // MARK: - Multi-User Audit Verification
    // =========================================================================

    /// Summary row for displaying multi-user audit assignments grouped by part.
    public struct MultiUserAuditPartSummary: Sendable {
        public let partId: Int64
        public let partName: String
        public let binLocation: String?
        public let expectedQuantity: Int?
        public let assignments: [MultiUserAuditAssignment]
        public let consensusQuantity: Int?
        public let isResolved: Bool

        public init(
            partId: Int64, partName: String, binLocation: String?,
            expectedQuantity: Int?, assignments: [MultiUserAuditAssignment],
            consensusQuantity: Int?, isResolved: Bool
        ) {
            self.partId = partId
            self.partName = partName
            self.binLocation = binLocation
            self.expectedQuantity = expectedQuantity
            self.assignments = assignments
            self.consensusQuantity = consensusQuantity
            self.isResolved = isResolved
        }
    }

    /// Flag a low-confidence part for multi-user audit verification.
    ///
    /// Creates 2-3 assignments for different active users (excluding the user
    /// who originally flagged it). Assignments are distributed among users who
    /// have the highest warehouse accuracy ratings.
    ///
    /// - Parameters:
    ///   - partId: The part to verify.
    ///   - expectedQty: The system's expected quantity (from stock records).
    ///   - sessionId: The audit session this verification belongs to.
    ///   - flaggedBy: The user who flagged the discrepancy (excluded from assignments).
    ///   - requiredCounts: Number of independent counts needed (default 2, max 3).
    /// - Returns: The created assignments.
    @discardableResult
    public func flagForMultiUserAudit(
        partId: Int64,
        expectedQty: Int,
        sessionId: Int64? = nil,
        flaggedBy: Int64? = nil,
        requiredCounts: Int = 2
    ) throws -> [MultiUserAuditAssignment] {
        try db.writer.write { dbConn in
            // Get part info
            let partRow = try Row.fetchOne(dbConn, sql: """
                SELECT p.name, COALESCE(wpa.area_id, 0) AS area_id,
                       wsa.full_location_code AS bin_location
                FROM parts p
                LEFT JOIN warehouse_part_assignments wpa ON wpa.part_id = p.id
                    AND wpa.is_home = 1 AND wpa.deleted_at IS NULL
                LEFT JOIN warehouse_storage_areas wsa ON wsa.id = wpa.area_id
                    AND wsa.deleted_at IS NULL
                WHERE p.id = ? AND p.deleted_at IS NULL
                """, arguments: [partId])

            let partName = (partRow?["name"] as String?) ?? "Unknown Part"
            let binLocation = partRow?["bin_location"] as String?

            // Get active users, excluding the flagger, ordered by accuracy rating
            var userArgs: [DatabaseValueConvertible?] = []
            var excludeClause = ""
            if let flaggedBy {
                excludeClause = "AND u.id != ?"
                userArgs.append(flaggedBy)
            }

            let userRows = try Row.fetchAll(dbConn, sql: """
                SELECT u.id, COALESCE(u.display_name, u.email, 'User') AS name,
                       COALESCE(uwr.accuracy_rating, 5.0) AS accuracy
                FROM users u
                LEFT JOIN user_warehouse_ratings uwr ON uwr.user_id = u.id
                WHERE u.is_active = 1 AND u.deleted_at IS NULL
                    \(excludeClause)
                ORDER BY COALESCE(uwr.accuracy_rating, 5.0) DESC
                LIMIT ?
                """, arguments: StatementArguments(userArgs + [min(requiredCounts, 3)]))

            var assignments: [MultiUserAuditAssignment] = []

            for userRow in userRows {
                let userId: Int64 = userRow["id"] ?? 0
                let userName: String = userRow["name"] ?? "User"

                var assignment = MultiUserAuditAssignment(
                    id: nil,
                    partId: partId,
                    partName: partName,
                    binLocation: binLocation,
                    assignedUserId: userId,
                    assignedUserName: userName,
                    countedQuantity: nil,
                    countedAt: nil,
                    status: "pending",
                    auditSessionId: sessionId,
                    expectedQuantity: expectedQty,
                    notes: nil,
                    createdAt: nil
                )
                try assignment.insert(dbConn)
                assignments.append(assignment)
            }

            return assignments
        }
    }

    /// Submit a user's count for a multi-user audit assignment.
    ///
    /// - Parameters:
    ///   - assignmentId: The assignment to update.
    ///   - quantity: The physical count by this user.
    ///   - userId: The user submitting the count (verified against assignment).
    ///   - notes: Optional notes about the count.
    public func submitMultiUserCount(
        assignmentId: Int64,
        quantity: Int,
        userId: Int64,
        notes: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            // Verify the assignment exists and belongs to this user
            guard var assignment = try MultiUserAuditAssignment.fetchOne(dbConn, key: assignmentId) else {
                throw WarehouseError.sessionNotFound(assignmentId)
            }
            guard assignment.assignedUserId == userId else {
                throw WarehouseError.sessionNotFound(assignmentId)
            }
            guard assignment.status == "pending" else {
                throw WarehouseError.sessionAlreadyCompleted
            }

            assignment.countedQuantity = quantity
            assignment.countedAt = Self.nowString()
            assignment.status = "counted"
            assignment.notes = notes
            try assignment.update(dbConn)
        }
    }

    /// Get all multi-user audit assignments for a session, grouped by part.
    ///
    /// - Parameter sessionId: The audit session ID (nil returns all unresolved).
    /// - Returns: Assignments grouped by part with consensus info.
    public func getMultiUserAuditAssignments(sessionId: Int64? = nil) throws -> [MultiUserAuditPartSummary] {
        do {
            return try db.writer.read { dbConn -> [MultiUserAuditPartSummary] in
                var whereClauses = ["1=1"]
                var args: [DatabaseValueConvertible?] = []

                if let sessionId {
                    whereClauses.append("audit_session_id = ?")
                    args.append(sessionId)
                }

                let assignments = try MultiUserAuditAssignment
                    .filter(sql: whereClauses.joined(separator: " AND "), arguments: StatementArguments(args))
                    .order(Column("part_id"), Column("created_at"))
                    .fetchAll(dbConn)

                // Group by partId
                let grouped = Dictionary(grouping: assignments) { $0.partId }

                return grouped.map { (partId, partAssignments) -> MultiUserAuditPartSummary in
                    let first = partAssignments[0]
                    let countedAssignments = partAssignments.filter { $0.status == "counted" }
                    let isResolved = partAssignments.allSatisfy { $0.status == "resolved" }

                    // Calculate consensus: if all counted quantities agree, that's consensus
                    let consensus: Int?
                    if countedAssignments.count >= 2 {
                        let counts = countedAssignments.compactMap { $0.countedQuantity }
                        let uniqueCounts = Set(counts)
                        if uniqueCounts.count == 1 {
                            consensus = counts.first
                        } else {
                            // Find the most common count (mode)
                            let countFreq = counts.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
                            let maxFreq = countFreq.values.max() ?? 0
                            if maxFreq >= 2 {
                                consensus = countFreq.first { $0.value == maxFreq }?.key
                            } else {
                                consensus = nil // No clear consensus
                            }
                        }
                    } else {
                        consensus = nil
                    }

                    return MultiUserAuditPartSummary(
                        partId: partId,
                        partName: first.partName,
                        binLocation: first.binLocation,
                        expectedQuantity: first.expectedQuantity,
                        assignments: partAssignments,
                        consensusQuantity: consensus,
                        isResolved: isResolved
                    )
                }.sorted { $0.partName < $1.partName }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get pending multi-user audit assignments for a specific user.
    ///
    /// - Parameter userId: The user to fetch assignments for.
    /// - Returns: Pending assignments for this user.
    public func getMyMultiUserAuditAssignments(userId: Int64) throws -> [MultiUserAuditAssignment] {
        do {
            return try db.writer.read { dbConn in
                try MultiUserAuditAssignment
                    .filter(Column("assigned_user_id") == userId && Column("status") == "pending")
                    .order(Column("created_at").desc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Resolve a multi-user audit for a part within a session.
    ///
    /// Compares all submitted counts, picks consensus (majority count),
    /// adjusts the system stock to match, updates part confidence, and
    /// adjusts user warehouse ratings based on accuracy.
    ///
    /// - Parameters:
    ///   - partId: The part being resolved.
    ///   - sessionId: The audit session.
    ///   - resolvedBy: The user performing the resolution.
    /// - Returns: The consensus quantity that was applied, or nil if no consensus.
    @discardableResult
    public func resolveMultiUserAudit(
        partId: Int64,
        sessionId: Int64,
        resolvedBy: Int64
    ) throws -> Int? {
        try db.writer.write { dbConn in
            // Get all assignments for this part in this session
            let assignments = try MultiUserAuditAssignment
                .filter(Column("part_id") == partId && Column("audit_session_id") == sessionId)
                .fetchAll(dbConn)

            let countedAssignments = assignments.filter { $0.status == "counted" }
            guard countedAssignments.count >= 2 else { return nil }

            let counts = countedAssignments.compactMap { $0.countedQuantity }
            // If any counted assignment is missing a quantity, consensus is impossible
            guard counts.count == countedAssignments.count else { return nil }
            let countFreq = counts.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }

            // Find consensus: the count with the most votes
            guard let (consensusQty, maxVotes) = countFreq.max(by: { $0.value < $1.value }),
                  maxVotes >= 2 || counts.count == 2 else {
                return nil // No consensus possible
            }

            // For 2 counters, they must agree
            if counts.count == 2 && counts[0] != counts[1] {
                return nil
            }

            // Use the consensus quantity (or if 2 counters agree, use their count)
            let finalQty: Int
            if counts.count == 2 {
                finalQty = counts[0]
            } else {
                finalQty = consensusQty
            }

            // Mark all assignments as resolved
            for var assignment in assignments {
                assignment.status = "resolved"
                try assignment.update(dbConn)
            }

            // Update stock to match consensus
            let expectedQty = assignments.first?.expectedQuantity ?? 0
            if finalQty != expectedQty {
                try dbConn.execute(sql: """
                    UPDATE stock SET qty = ?, last_counted = datetime('now'), updated_at = datetime('now')
                    WHERE part_id = ? AND location_type = 'warehouse' AND deleted_at IS NULL
                    """, arguments: [finalQty, partId])

                // Record adjustment movement
                try dbConn.execute(sql: """
                    INSERT INTO stock_movements
                    (part_id, qty, from_location_type, to_location_type,
                     movement_type, reason, notes, performed_by, created_at)
                    VALUES (?, ?, 'warehouse', 'warehouse', 'adjustment',
                            'Multi-user audit consensus', ?, ?, datetime('now'))
                    """, arguments: [
                        partId, finalQty,
                        "Consensus from \(countedAssignments.count) independent counts",
                        resolvedBy
                    ])
            }

            // Update user warehouse ratings based on accuracy
            for assignment in countedAssignments {
                let wasAccurate = assignment.countedQuantity == finalQty
                let userId = assignment.assignedUserId

                if var rating = try UserWarehouseRating
                    .filter(Column("user_id") == userId)
                    .fetchOne(dbConn) {
                    rating.totalAudits += 1
                    if wasAccurate {
                        rating.totalAccurate += 1
                        rating.accuracyRating = min(10, rating.accuracyRating + 0.3)
                    } else {
                        rating.accuracyRating = max(0, rating.accuracyRating - 0.5)
                    }
                    rating.overallRating = (rating.accuracyRating + rating.effortRating +
                        rating.placementRating + rating.wizardCompliance +
                        rating.speedRating + rating.proactiveRating) / 6.0
                    rating.updatedAt = Self.nowString()
                    try rating.update(dbConn)
                }
            }

            // Boost part confidence after multi-user verification
            if var conf = try PartConfidence
                .filter(Column("part_id") == partId)
                .fetchOne(dbConn) {
                conf.confidencePercent = min(100, conf.confidencePercent + 35)
                conf.lastAuditDate = Self.nowString()
                conf.lastAuditBy = resolvedBy
                conf.lastAuditCount = finalQty
                conf.systemCount = finalQty
                conf.totalAuditCount += 1
                conf.cleanAuditStreak = (finalQty == expectedQty) ? conf.cleanAuditStreak + 1 : 0
                conf.movementDecayFactor = 1.0
                conf.reliabilityLevel = Self.computeReliabilityLevel(conf)
                conf.updatedAt = Self.nowString()
                try conf.update(dbConn)
            }

            return finalQty
        }
    }

    /// Get low-confidence parts that should be flagged for multi-user verification.
    ///
    /// Returns parts where confidence is below the threshold and that haven't
    /// already been flagged in the current session.
    ///
    /// - Parameters:
    ///   - threshold: Confidence percentage threshold (default 40%).
    ///   - sessionId: Current session to check for existing assignments.
    ///   - limit: Maximum number of parts to return.
    /// - Returns: Part confidence records below threshold.
    public func getLowConfidencePartsForVerification(
        threshold: Double = 40.0,
        sessionId: Int64? = nil,
        limit: Int = 20
    ) throws -> [PartConfidence] {
        do {
            return try db.writer.read { dbConn in
                var sql = """
                    SELECT pc.* FROM part_confidence pc
                    WHERE pc.confidence_percent < ?
                """
                var args: [DatabaseValueConvertible?] = [threshold]

                // Exclude parts already flagged in this session
                if let sessionId {
                    sql += """
                         AND pc.part_id NOT IN (
                            SELECT DISTINCT part_id FROM multi_user_audit_assignments
                            WHERE audit_session_id = ?
                         )
                        """
                    args.append(sessionId)
                }

                sql += " ORDER BY pc.confidence_percent ASC LIMIT ?"
                args.append(limit)

                return try PartConfidence.fetchAll(
                    dbConn,
                    sql: sql,
                    arguments: StatementArguments(args)
                )
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Helpers (Audit)

    private static func nowString() -> String { CoreFormatters.nowISO() }
}
