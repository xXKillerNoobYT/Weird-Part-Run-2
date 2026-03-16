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
        public let partName: String
        public let partCode: String?
        public let expectedQty: Int
        public let receivedQty: Int
        public let actualCost: Double?
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
                    SELECT ?, id, qty, datetime('now')
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
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        expectedQty: row["expected_qty"] ?? 0,
                        receivedQty: row["received_qty"] ?? 0,
                        actualCost: row["actual_cost"] as Double?,
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
                """
        )

        let discrepancies = try safeCount(
            sql: """
                SELECT COUNT(*) FROM stock
                WHERE location_type = 'warehouse' AND deleted_at IS NULL
                  AND last_counted IS NOT NULL
                  AND date(last_counted) = date('now')
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
            lastAuditDate: lastDate ?? nil
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
                    UPDATE stock SET last_counted = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [stockId]
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
                        SELECT s.part_id, s.location_type, s.location_id, s.qty,
                               s.last_counted,
                               p.name AS part_name, p.code AS part_code
                        FROM stock s
                        LEFT JOIN parts p ON p.id = s.part_id
                        WHERE s.location_type = 'warehouse'
                          AND s.deleted_at IS NULL
                          AND s.last_counted IS NOT NULL
                          AND date(s.last_counted) = date('now')
                        ORDER BY p.name
                        """
                )
                return rows.compactMap { row -> AuditDiscrepancy? in
                    let partId: Int64 = row["part_id"] ?? 0
                    let qty: Int = row["qty"] ?? 0

                    return AuditDiscrepancy(
                        partId: partId,
                        partName: (row["part_name"] as String?) ?? "Unknown Part",
                        partCode: row["part_code"] as String?,
                        locationType: row["location_type"] ?? "warehouse",
                        locationId: row["location_id"] ?? 1,
                        systemQty: qty,
                        countedQty: qty, // Will be updated when actual count integration is added
                        difference: 0,
                        lastCounted: row["last_counted"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
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
        return message.contains("no such table")
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
            return "Warehouse #\(id)"
        case "truck":
            return "Truck #\(id)"
        case "trailer":
            return "Trailer #\(id)"
        case "job":
            return "Job #\(id)"
        case "pulled":
            return "Pulled Staging"
        default:
            return "\(type) #\(id)"
        }
    }
}
