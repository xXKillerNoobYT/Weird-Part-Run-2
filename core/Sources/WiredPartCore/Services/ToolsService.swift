import Foundation
import GRDB

/// Tools & Kits Service — read queries for tools, kits, checkouts, and dashboard stats.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Tools & Kits feature area (Phase 9)
public final class ToolsService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A tool row for list views with assignment info.
    public struct ToolListItem: Sendable, Identifiable {
        public let id: Int64
        public let toolNumber: String
        public let name: String
        public let toolType: String
        public let status: String
        public let serialNumber: String?
        public let assignedToName: String?
        public let currentValue: Double?

        public init(
            id: Int64, toolNumber: String, name: String, toolType: String,
            status: String, serialNumber: String?, assignedToName: String?,
            currentValue: Double?
        ) {
            self.id = id
            self.toolNumber = toolNumber
            self.name = name
            self.toolType = toolType
            self.status = status
            self.serialNumber = serialNumber
            self.assignedToName = assignedToName
            self.currentValue = currentValue
        }
    }

    /// A kit row for list views with item count.
    public struct KitListItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let isActive: Bool
        public let itemCount: Int

        public init(id: Int64, name: String, description: String?, isActive: Bool, itemCount: Int) {
            self.id = id
            self.name = name
            self.description = description
            self.isActive = isActive
            self.itemCount = itemCount
        }
    }

    /// A checkout row with tool and user names.
    public struct CheckoutRow: Sendable, Identifiable {
        public let id: Int64
        public let toolName: String
        public let checkedOutByName: String
        public let checkedOutAt: String
        public let expectedReturn: String?
        public let returnedAt: String?

        public init(
            id: Int64, toolName: String, checkedOutByName: String,
            checkedOutAt: String, expectedReturn: String?, returnedAt: String?
        ) {
            self.id = id
            self.toolName = toolName
            self.checkedOutByName = checkedOutByName
            self.checkedOutAt = checkedOutAt
            self.expectedReturn = expectedReturn
            self.returnedAt = returnedAt
        }
    }

    /// Dashboard stats for the tools overview.
    public struct ToolsStats: Sendable {
        public let totalTools: Int
        public let checkedOut: Int
        public let inMaintenance: Int
        public let totalKits: Int

        public init(totalTools: Int, checkedOut: Int, inMaintenance: Int, totalKits: Int) {
            self.totalTools = totalTools
            self.checkedOut = checkedOut
            self.inMaintenance = inMaintenance
            self.totalKits = totalKits
        }
    }

    // =========================================================================
    // MARK: - 1. Tools List
    // =========================================================================

    /// List tools with optional search and status filter.
    ///
    /// Joins to `users` to resolve the `assigned_to` user name.
    /// Returns tools sorted by creation date (newest first).
    ///
    /// - Parameters:
    ///   - search: Optional text to match against tool name, tool number, or serial number.
    ///   - status: Optional status filter (e.g., "available", "checked_out", "maintenance").
    /// - Returns: An array of `ToolListItem` rows.
    public func listTools(search: String? = nil, status: String? = nil) throws -> [ToolListItem] {
        do {
            return try db.writer.read { dbConn -> [ToolListItem] in
                var whereClauses = ["t.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let search, !search.isEmpty {
                    whereClauses.append("(t.name LIKE ? OR t.tool_number LIKE ? OR t.serial_number LIKE ?)")
                    let pattern = "%\(search)%"
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                }
                if let status, !status.isEmpty {
                    whereClauses.append("t.status = ?")
                    args.append(status)
                }

                let sql = """
                    SELECT t.id, t.tool_number, t.name, t.category AS tool_type,
                           t.status, t.serial_number, t.purchase_cost AS current_value,
                           COALESCE(u.display_name, u.email) AS assigned_to_name
                    FROM tools t
                    LEFT JOIN users u ON u.id = t.assigned_to
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY t.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    ToolListItem(
                        id: row["id"] ?? 0,
                        toolNumber: row["tool_number"] ?? "",
                        name: row["name"] ?? "",
                        toolType: row["tool_type"] ?? "",
                        status: row["status"] ?? "available",
                        serialNumber: row["serial_number"] as String?,
                        assignedToName: row["assigned_to_name"] as String?,
                        currentValue: row["current_value"] as Double?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Kits List
    // =========================================================================

    /// List all tool kits with their item counts.
    ///
    /// Uses a correlated subquery to count items per kit from `tool_kit_items`.
    /// Returns kits sorted by name ascending.
    ///
    /// - Returns: An array of `KitListItem` rows.
    public func listKits() throws -> [KitListItem] {
        do {
            return try db.writer.read { dbConn -> [KitListItem] in
                let sql = """
                    SELECT t.id, t.name, '' AS description, 1 AS is_active,
                           COUNT(kt.id) AS item_count
                    FROM tools t
                    INNER JOIN kit_templates kt ON kt.tool_id = t.id AND kt.deleted_at IS NULL
                    WHERE t.deleted_at IS NULL
                    GROUP BY t.id
                    ORDER BY t.name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    KitListItem(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?,
                        isActive: (row["is_active"] as Int?) == 1,
                        itemCount: row["item_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2b. Tool Kits List
    // =========================================================================

    /// A tool kit row for list views showing kit info and tool count.
    public struct ToolKitListItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let toolCount: Int
        public let status: String

        public init(id: Int64, name: String, description: String?, toolCount: Int, status: String) {
            self.id = id
            self.name = name
            self.description = description
            self.toolCount = toolCount
            self.status = status
        }
    }

    /// List all tool kits with their item counts.
    ///
    /// Queries the `tool_kits` table with a LEFT JOIN to `tool_kit_items`
    /// to count tools per kit. Returns kits sorted by name ascending.
    ///
    /// - Returns: An array of `ToolKitListItem` rows.
    public func listToolKits() throws -> [ToolKitListItem] {
        do {
            return try db.writer.read { dbConn -> [ToolKitListItem] in
                let sql = """
                    SELECT tk.id, tk.name,
                           tk.description,
                           COALESCE(tk.status, 'available') AS status,
                           COUNT(tki.id) AS tool_count
                    FROM tool_kits tk
                    LEFT JOIN tool_kit_items tki ON tki.kit_id = tk.id AND tki.deleted_at IS NULL
                    WHERE tk.deleted_at IS NULL
                    GROUP BY tk.id
                    ORDER BY tk.name
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    ToolKitListItem(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?,
                        toolCount: row["tool_count"] ?? 0,
                        status: row["status"] ?? "available"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Checkouts List
    // =========================================================================

    /// List tool checkouts, optionally filtered by tool and/or active status.
    ///
    /// Joins to `tools` and `users` to resolve tool name and user name.
    /// When `active` is true, only returns checkouts where `returned_at IS NULL`.
    ///
    /// - Parameters:
    ///   - toolId: Optional tool ID to filter by.
    ///   - active: When true, only return currently active (unreturned) checkouts.
    /// - Returns: An array of `CheckoutRow` rows.
    public func listCheckouts(toolId: Int64? = nil, active: Bool = false) throws -> [CheckoutRow] {
        do {
            return try db.writer.read { dbConn -> [CheckoutRow] in
                var whereClauses = ["tm.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let toolId {
                    whereClauses.append("tm.tool_id = ?")
                    args.append(toolId)
                }
                if active {
                    whereClauses.append("tm.movement_type = 'checkout'")
                }

                let sql = """
                    SELECT tm.id, tm.created_at AS checked_out_at,
                           NULL AS expected_return, NULL AS returned_at,
                           t.name AS tool_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS checked_out_by_name
                    FROM tool_movements tm
                    LEFT JOIN tools t ON t.id = tm.tool_id
                    LEFT JOIN users u ON u.id = tm.performed_by
                    WHERE \(whereClauses.joined(separator: " AND "))
                    ORDER BY tm.created_at DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    CheckoutRow(
                        id: row["id"] ?? 0,
                        toolName: row["tool_name"] ?? "",
                        checkedOutByName: row["checked_out_by_name"] ?? "Unknown",
                        checkedOutAt: row["checked_out_at"] ?? "",
                        expectedReturn: row["expected_return"] as String?,
                        returnedAt: row["returned_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3b. Tool Actions
    // =========================================================================

    /// Check out a tool to a user.
    public func checkoutTool(toolId: Int64, userId: Int64, notes: String? = nil) throws {
        try db.writer.write { dbConn in
            // Update tool status
            try dbConn.execute(
                sql: """
                    UPDATE tools SET status = 'checked_out', updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [toolId]
            )
            // Create checkout record
            try dbConn.execute(
                sql: """
                    INSERT INTO tool_checkouts (tool_id, checked_out_by, checked_out_at, notes, created_at)
                    VALUES (?, ?, datetime('now'), ?, datetime('now'))
                    """,
                arguments: [toolId, userId, notes]
            )
        }
    }

    /// Return a checked-out tool.
    public func returnTool(toolId: Int64, userId: Int64, notes: String? = nil) throws {
        try db.writer.write { dbConn in
            // Update tool status
            try dbConn.execute(
                sql: """
                    UPDATE tools SET status = 'available', updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [toolId]
            )
            // Close the checkout record
            try dbConn.execute(
                sql: """
                    UPDATE tool_checkouts SET checked_in_at = datetime('now'), checked_in_by = ?
                    WHERE tool_id = ? AND checked_in_at IS NULL
                    """,
                arguments: [userId, toolId]
            )
        }
    }

    /// Mark a tool for maintenance.
    public func markToolMaintenance(toolId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE tools SET status = 'maintenance', updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [toolId]
            )
        }
    }

    // =========================================================================
    // MARK: - 4. Tools Stats
    // =========================================================================

    /// Get aggregate tools statistics: total tools, checked out, in maintenance, total kits.
    public func getToolsStats() throws -> ToolsStats {
        let totalTools = try safeCount(
            sql: "SELECT COUNT(*) FROM tools WHERE deleted_at IS NULL"
        )

        let checkedOut = try safeCount(
            sql: """
                SELECT COUNT(DISTINCT tm.tool_id) FROM tool_movements tm
                WHERE tm.movement_type = 'checkout' AND tm.deleted_at IS NULL
                AND NOT EXISTS (
                    SELECT 1 FROM tool_movements ret
                    WHERE ret.tool_id = tm.tool_id
                    AND ret.movement_type = 'return'
                    AND ret.deleted_at IS NULL
                    AND ret.created_at > tm.created_at
                )
                """
        )

        let inMaintenance = try safeCount(
            sql: "SELECT COUNT(*) FROM tools WHERE status = 'maintenance' AND deleted_at IS NULL"
        )

        let totalKits = try safeCount(
            sql: "SELECT COUNT(DISTINCT tool_id) FROM kit_templates WHERE deleted_at IS NULL"
        )

        return ToolsStats(
            totalTools: totalTools,
            checkedOut: checkedOut,
            inMaintenance: inMaintenance,
            totalKits: totalKits
        )
    }

    // =========================================================================
    // MARK: - 5. Tool Detail
    // =========================================================================

    /// Full tool detail row with joined assignment and location info.
    public struct ToolDetail: Sendable, Identifiable {
        public let id: Int64
        public let toolNumber: String
        public let name: String
        public let category: String
        public let brand: String?
        public let modelNumber: String?
        public let serialNumber: String?
        public let purchaseDate: String?
        public let purchaseCost: Double?
        public let warrantyExpiry: String?
        public let locationType: String
        public let status: String
        public let conditionRating: Int?
        public let hasKit: Bool
        public let notes: String?
        public let barcode: String?
        public let assignedToName: String?
        public let assignedTo: Int64?
        public let lastKnownCondition: String?
        public let calibrationDueDate: String?
        public let depreciationMethod: String?
        public let salvageValue: Double?
        public let usefulLifeYears: Int?
        public let confidenceScore: Double?
        public let totalUsageHours: Double?
        public let lastMaintenanceDate: String?

        public init(
            id: Int64, toolNumber: String, name: String, category: String,
            brand: String?, modelNumber: String?, serialNumber: String?,
            purchaseDate: String?, purchaseCost: Double?, warrantyExpiry: String?,
            locationType: String, status: String, conditionRating: Int?,
            hasKit: Bool, notes: String?, barcode: String?,
            assignedToName: String?, assignedTo: Int64?,
            lastKnownCondition: String?, calibrationDueDate: String?,
            depreciationMethod: String?, salvageValue: Double?, usefulLifeYears: Int?,
            confidenceScore: Double? = nil, totalUsageHours: Double? = nil,
            lastMaintenanceDate: String? = nil
        ) {
            self.id = id; self.toolNumber = toolNumber; self.name = name
            self.category = category; self.brand = brand; self.modelNumber = modelNumber
            self.serialNumber = serialNumber; self.purchaseDate = purchaseDate
            self.purchaseCost = purchaseCost; self.warrantyExpiry = warrantyExpiry
            self.locationType = locationType; self.status = status
            self.conditionRating = conditionRating; self.hasKit = hasKit
            self.notes = notes; self.barcode = barcode
            self.assignedToName = assignedToName; self.assignedTo = assignedTo
            self.lastKnownCondition = lastKnownCondition
            self.calibrationDueDate = calibrationDueDate
            self.depreciationMethod = depreciationMethod
            self.salvageValue = salvageValue; self.usefulLifeYears = usefulLifeYears
            self.confidenceScore = confidenceScore
            self.totalUsageHours = totalUsageHours
            self.lastMaintenanceDate = lastMaintenanceDate
        }
    }

    /// Get full tool detail by ID.
    public func getToolDetail(toolId: Int64) throws -> ToolDetail? {
        do {
            return try db.writer.read { dbConn -> ToolDetail? in
                let sql = """
                    SELECT t.*,
                           COALESCE(u.display_name, u.email) AS assigned_to_name,
                           (SELECT checkout_condition FROM tool_checkouts
                            WHERE tool_id = t.id AND deleted_at IS NULL
                            ORDER BY created_at DESC LIMIT 1) AS last_known_condition
                    FROM tools t
                    LEFT JOIN users u ON u.id = t.assigned_to
                    WHERE t.id = ? AND t.deleted_at IS NULL
                    """
                guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [toolId]) else {
                    return nil
                }
                return ToolDetail(
                    id: row["id"],
                    toolNumber: row["tool_number"] ?? "",
                    name: row["name"] ?? "",
                    category: row["category"] ?? "general",
                    brand: row["brand"] as String?,
                    modelNumber: row["model_number"] as String?,
                    serialNumber: row["serial_number"] as String?,
                    purchaseDate: row["purchase_date"] as String?,
                    purchaseCost: row["purchase_cost"] as Double?,
                    warrantyExpiry: row["warranty_expiry"] as String?,
                    locationType: row["location_type"] ?? "warehouse",
                    status: row["status"] ?? "available",
                    conditionRating: row["condition_rating"] as Int?,
                    hasKit: (row["has_kit"] as Int?) == 1,
                    notes: row["notes"] as String?,
                    barcode: row["barcode"] as String?,
                    assignedToName: row["assigned_to_name"] as String?,
                    assignedTo: row["assigned_to"] as Int64?,
                    lastKnownCondition: row["last_known_condition"] as String?,
                    calibrationDueDate: row["calibration_due_date"] as String?,
                    depreciationMethod: row["depreciation_method"] as String?,
                    salvageValue: row["salvage_value"] as Double?,
                    usefulLifeYears: row["useful_life_years"] as Int?,
                    confidenceScore: row["confidence_score"] as Double?,
                    totalUsageHours: row["total_usage_hours"] as Double?,
                    lastMaintenanceDate: row["last_maintenance_date"] as String?
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 6. Kit Contents
    // =========================================================================

    /// A kit content item showing component status and quantity.
    public struct KitContentItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let itemType: String
        public let requiredQty: Int
        public let currentQty: Int
        public let status: String
        public let lastChecked: String?

        public init(id: Int64, name: String, itemType: String,
                    requiredQty: Int, currentQty: Int, status: String, lastChecked: String?) {
            self.id = id; self.name = name; self.itemType = itemType
            self.requiredQty = requiredQty; self.currentQty = currentQty
            self.status = status; self.lastChecked = lastChecked
        }
    }

    /// Get kit contents for a tool (from kit_templates + latest verification).
    public func getKitContents(toolId: Int64) throws -> [KitContentItem] {
        do {
            return try db.writer.read { dbConn -> [KitContentItem] in
                let sql = """
                    SELECT kt.id, kt.component_name, kt.component_type, kt.qty_required,
                           COALESCE(kvi.is_present, 1) AS is_present,
                           kvi.condition_rating,
                           kvs.created_at AS last_checked
                    FROM kit_templates kt
                    LEFT JOIN (
                        SELECT kvi2.template_item_id, kvi2.is_present, kvi2.condition_rating, kvi2.id AS kvi_id
                        FROM kit_verification_items kvi2
                        INNER JOIN kit_verification_sessions kvs2
                            ON kvs2.id = kvi2.session_id AND kvs2.tool_id = ?
                        WHERE kvi2.deleted_at IS NULL
                        ORDER BY kvs2.created_at DESC
                        LIMIT 1
                    ) kvi ON kvi.template_item_id = kt.id
                    LEFT JOIN kit_verification_sessions kvs
                        ON kvs.tool_id = ? AND kvs.deleted_at IS NULL
                    WHERE kt.tool_id = ? AND kt.deleted_at IS NULL
                    ORDER BY kt.sort_order ASC, kt.component_name ASC
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [toolId, toolId, toolId])
                return rows.map { row in
                    let isPresent = (row["is_present"] as Int?) == 1
                    let reqQty: Int = row["qty_required"] ?? 1
                    let componentType: String = row["component_type"] ?? "accessory"
                    let curQty = isPresent ? reqQty : 0

                    let status: String
                    if !isPresent {
                        status = "missing"
                    } else if componentType == "consumable" && curQty < reqQty {
                        status = "low"
                    } else {
                        status = "present"
                    }

                    return KitContentItem(
                        id: row["id"] ?? 0,
                        name: row["component_name"] ?? "",
                        itemType: componentType,
                        requiredQty: reqQty,
                        currentQty: curQty,
                        status: status,
                        lastChecked: row["last_checked"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. Version History
    // =========================================================================

    /// A change record for tool version history.
    public struct ToolChangeRecord: Sendable, Identifiable {
        public let id: Int64
        public let changedBy: Int64
        public let changedByName: String?
        public let fieldName: String?
        public let oldValue: String?
        public let newValue: String?
        public let changedAt: String
        public let changeType: String
        public let verificationStatus: String

        public init(id: Int64, changedBy: Int64, changedByName: String?,
                    fieldName: String?, oldValue: String?, newValue: String?,
                    changedAt: String, changeType: String, verificationStatus: String) {
            self.id = id; self.changedBy = changedBy
            self.changedByName = changedByName; self.fieldName = fieldName
            self.oldValue = oldValue; self.newValue = newValue
            self.changedAt = changedAt; self.changeType = changeType
            self.verificationStatus = verificationStatus
        }
    }

    /// Get tool version history (default 24 months).
    public func getToolVersionHistory(toolId: Int64, months: Int = 24) throws -> [ToolChangeRecord] {
        do {
            return try db.writer.read { dbConn -> [ToolChangeRecord] in
                let sql = """
                    SELECT tcl.id, tcl.changed_by, tcl.field_name, tcl.old_value, tcl.new_value,
                           tcl.changed_at, tcl.change_type, tcl.verification_status,
                           COALESCE(u.display_name, u.email, 'Unknown') AS changed_by_name
                    FROM tool_change_log tcl
                    LEFT JOIN users u ON tcl.changed_by = u.id
                    WHERE tcl.tool_id = ? AND tcl.deleted_at IS NULL
                    AND tcl.changed_at >= date('now', '-' || ? || ' months')
                    ORDER BY tcl.changed_at DESC
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [toolId, months])
                return rows.map { row in
                    ToolChangeRecord(
                        id: row["id"] ?? 0,
                        changedBy: row["changed_by"] ?? 0,
                        changedByName: row["changed_by_name"] as String?,
                        fieldName: row["field_name"] as String?,
                        oldValue: row["old_value"] as String?,
                        newValue: row["new_value"] as String?,
                        changedAt: row["changed_at"] ?? "",
                        changeType: row["change_type"] ?? "edit",
                        verificationStatus: row["verification_status"] ?? "approved"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get pending edits for a tool that need verification.
    public func getPendingEdits(toolId: Int64) throws -> [ToolChangeRecord] {
        do {
            return try db.writer.read { dbConn -> [ToolChangeRecord] in
                let sql = """
                    SELECT tcl.id, tcl.changed_by, tcl.field_name, tcl.old_value, tcl.new_value,
                           tcl.changed_at, tcl.change_type, tcl.verification_status,
                           COALESCE(u.display_name, u.email, 'Unknown') AS changed_by_name
                    FROM tool_change_log tcl
                    LEFT JOIN users u ON tcl.changed_by = u.id
                    WHERE tcl.tool_id = ? AND tcl.verification_status = 'pending_verification'
                    AND tcl.deleted_at IS NULL
                    ORDER BY tcl.changed_at DESC
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [toolId])
                return rows.map { row in
                    ToolChangeRecord(
                        id: row["id"] ?? 0,
                        changedBy: row["changed_by"] ?? 0,
                        changedByName: row["changed_by_name"] as String?,
                        fieldName: row["field_name"] as String?,
                        oldValue: row["old_value"] as String?,
                        newValue: row["new_value"] as String?,
                        changedAt: row["changed_at"] ?? "",
                        changeType: row["change_type"] ?? "edit",
                        verificationStatus: row["verification_status"] ?? "pending_verification"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 8. Checkout/Return with Condition
    // =========================================================================

    /// Checkout a tool with REQUIRED condition check.
    public func checkoutToolWithCondition(
        toolId: Int64, userId: Int64, condition: String, notes: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            // Update tool status + condition rating
            let conditionRating = Self.conditionToRating(condition)
            try dbConn.execute(sql: """
                UPDATE tools SET status = 'checked_out', assigned_to = ?,
                       condition_rating = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [userId, conditionRating, toolId])

            // Create checkout record with condition
            try dbConn.execute(sql: """
                INSERT INTO tool_checkouts
                (tool_id, checked_out_by, checked_out_at, checkout_condition, checkout_notes, created_at)
                VALUES (?, ?, datetime('now'), ?, ?, datetime('now'))
                """, arguments: [toolId, userId, condition, notes])

            // Log the change
            try dbConn.execute(sql: """
                INSERT INTO tool_change_log
                (tool_id, changed_by, change_type, field_name, new_value, changed_at, verification_status)
                VALUES (?, ?, 'checkout', 'status', 'checked_out', datetime('now'), 'approved')
                """, arguments: [toolId, userId])
        }
    }

    /// Return a tool with REQUIRED condition check.
    public func returnToolWithCondition(
        toolId: Int64, userId: Int64, condition: String, notes: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            let conditionRating = Self.conditionToRating(condition)
            try dbConn.execute(sql: """
                UPDATE tools SET status = 'available', assigned_to = NULL,
                       condition_rating = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [conditionRating, toolId])

            // Close open checkout with return condition
            try dbConn.execute(sql: """
                UPDATE tool_checkouts SET checked_in_at = datetime('now'),
                       checked_in_by = ?, return_condition = ?, return_notes = ?
                WHERE tool_id = ? AND checked_in_at IS NULL AND deleted_at IS NULL
                """, arguments: [userId, condition, notes, toolId])

            // Log the change
            try dbConn.execute(sql: """
                INSERT INTO tool_change_log
                (tool_id, changed_by, change_type, field_name, new_value, changed_at, verification_status)
                VALUES (?, ?, 'return', 'status', 'available', datetime('now'), 'approved')
                """, arguments: [toolId, userId])
        }
    }

    // =========================================================================
    // MARK: - 9. Edit with Verification
    // =========================================================================

    /// Result of an edit operation.
    public struct ToolEditResult: Sendable {
        public let status: String
        public let requiresVerification: Bool

        public init(status: String, requiresVerification: Bool) {
            self.status = status
            self.requiresVerification = requiresVerification
        }
    }

    /// Edit tool fields with optional verification requirement.
    /// If hasPermission is false, changes go to pending_verification state.
    @discardableResult
    public func editToolWithVerification(
        toolId: Int64, userId: Int64, changes: [String: String], hasPermission: Bool
    ) throws -> ToolEditResult {
        let status = hasPermission ? "approved" : "pending_verification"
        try db.writer.write { dbConn in
            // Allowed editable fields (prevents SQL injection)
            let allowedFields: Set<String> = [
                "name", "category", "brand", "model_number", "serial_number",
                "notes", "barcode", "location_type", "warranty_expiry",
                "calibration_due_date", "depreciation_method"
            ]

            for (field, value) in changes {
                guard allowedFields.contains(field) else { continue }

                // Get old value for the log
                let oldRow = try Row.fetchOne(dbConn, sql:
                    "SELECT \(field) FROM tools WHERE id = ?", arguments: [toolId])
                let oldValue = oldRow?[field] as String?

                // Log the change
                try dbConn.execute(sql: """
                    INSERT INTO tool_change_log
                    (tool_id, changed_by, change_type, field_name, old_value, new_value,
                     changed_at, verification_status)
                    VALUES (?, ?, 'edit', ?, ?, ?, datetime('now'), ?)
                    """, arguments: [toolId, userId, field, oldValue, value, status])

                if hasPermission {
                    // Direct update
                    try dbConn.execute(sql:
                        "UPDATE tools SET \(field) = ?, updated_at = datetime('now') WHERE id = ?",
                        arguments: [value, toolId])
                }
            }
        }
        return ToolEditResult(status: status, requiresVerification: !hasPermission)
    }

    /// Approve a pending tool edit (manager QR scan verification).
    public func approveToolEdit(editId: Int64, approverId: Int64) throws {
        try db.writer.write { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT tool_id, field_name, new_value FROM tool_change_log
                WHERE id = ? AND verification_status = 'pending_verification'
                AND deleted_at IS NULL
                """, arguments: [editId]) else {
                return
            }

            let toolId: Int64 = row["tool_id"]
            let field: String = row["field_name"] ?? ""
            let value: String = row["new_value"] ?? ""

            // Allowed editable fields
            let allowedFields: Set<String> = [
                "name", "category", "brand", "model_number", "serial_number",
                "notes", "barcode", "location_type", "warranty_expiry",
                "calibration_due_date", "depreciation_method"
            ]
            guard allowedFields.contains(field) else { return }

            // Apply the edit
            try dbConn.execute(sql:
                "UPDATE tools SET \(field) = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [value, toolId])

            // Mark as approved
            try dbConn.execute(sql: """
                UPDATE tool_change_log SET verification_status = 'approved',
                verified_by = ?, verified_at = datetime('now')
                WHERE id = ?
                """, arguments: [approverId, editId])
        }
    }

    /// A pending tool edit awaiting approval (includes tool name for display).
    public struct PendingToolEdit: Sendable, Identifiable {
        public let id: Int64
        public let toolId: Int64
        public let toolName: String
        public let changedByName: String
        public let fieldName: String
        public let oldValue: String?
        public let newValue: String?
        public let changedAt: String

        public init(id: Int64, toolId: Int64, toolName: String, changedByName: String,
                    fieldName: String, oldValue: String?, newValue: String?, changedAt: String) {
            self.id = id; self.toolId = toolId; self.toolName = toolName
            self.changedByName = changedByName; self.fieldName = fieldName
            self.oldValue = oldValue; self.newValue = newValue; self.changedAt = changedAt
        }
    }

    /// List all pending tool edit verifications across all tools.
    public func listPendingToolEdits() throws -> [PendingToolEdit] {
        do {
            return try db.writer.read { dbConn -> [PendingToolEdit] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT tcl.id, tcl.tool_id, tcl.field_name, tcl.old_value, tcl.new_value,
                           tcl.changed_at,
                           COALESCE(t.name, 'Unknown Tool') AS tool_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS changed_by_name
                    FROM tool_change_log tcl
                    LEFT JOIN tools t ON t.id = tcl.tool_id
                    LEFT JOIN users u ON u.id = tcl.changed_by
                    WHERE tcl.verification_status = 'pending_verification'
                      AND tcl.deleted_at IS NULL
                    ORDER BY tcl.changed_at ASC
                    """)
                return rows.map { row in
                    PendingToolEdit(
                        id: row["id"] ?? 0,
                        toolId: row["tool_id"] ?? 0,
                        toolName: row["tool_name"] ?? "Unknown Tool",
                        changedByName: row["changed_by_name"] ?? "Unknown",
                        fieldName: row["field_name"] ?? "",
                        oldValue: row["old_value"],
                        newValue: row["new_value"],
                        changedAt: row["changed_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Reject a pending tool edit verification.
    public func rejectToolEdit(editId: Int64, rejectedBy: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE tool_change_log SET verification_status = 'rejected',
                verified_by = ?, verified_at = datetime('now')
                WHERE id = ? AND verification_status = 'pending_verification'
                """, arguments: [rejectedBy, editId])
        }
    }

    // =========================================================================
    // MARK: - 10. Tool Trades
    // =========================================================================

    /// Trade info row with tool and user names.
    public struct ToolTradeInfo: Sendable, Identifiable {
        public let id: Int64
        public let toolId: Int64
        public let toolName: String
        public let serialNumber: String?
        public let fromUserId: Int64
        public let fromName: String
        public let toUserId: Int64
        public let toName: String
        public let conditionAtSend: String
        public let conditionAtReceive: String?
        public let sendNotes: String?
        public let receiveNotes: String?
        public let status: String
        public let createdAt: String
        public let expiresAt: String

        public init(id: Int64, toolId: Int64, toolName: String, serialNumber: String?,
                    fromUserId: Int64, fromName: String, toUserId: Int64, toName: String,
                    conditionAtSend: String, conditionAtReceive: String?,
                    sendNotes: String?, receiveNotes: String?,
                    status: String, createdAt: String, expiresAt: String) {
            self.id = id; self.toolId = toolId; self.toolName = toolName
            self.serialNumber = serialNumber; self.fromUserId = fromUserId
            self.fromName = fromName; self.toUserId = toUserId; self.toName = toName
            self.conditionAtSend = conditionAtSend; self.conditionAtReceive = conditionAtReceive
            self.sendNotes = sendNotes; self.receiveNotes = receiveNotes
            self.status = status; self.createdAt = createdAt; self.expiresAt = expiresAt
        }
    }

    /// Initiate a tool trade. The tool must be checked out to the sender.
    @discardableResult
    public func initiateTrade(
        toolId: Int64, fromUserId: Int64, toUserId: Int64,
        condition: String, notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // Verify tool is currently assigned to sender
            let assigned = try Row.fetchOne(dbConn, sql: """
                SELECT id FROM tools
                WHERE id = ? AND assigned_to = ? AND status = 'checked_out' AND deleted_at IS NULL
                """, arguments: [toolId, fromUserId])

            guard assigned != nil else {
                throw ToolsServiceError.toolNotCheckedOutToUser
            }

            // Check no pending trades for this tool
            let pending = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM tool_trades
                WHERE tool_id = ? AND status = 'pending' AND deleted_at IS NULL
                """, arguments: [toolId]) ?? 0

            guard pending == 0 else {
                throw ToolsServiceError.tradePending
            }

            // 7-day expiry
            let calendar = Calendar.current
            let expiresDate = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            let expiresStr = isoFormatter.string(from: expiresDate)

            try dbConn.execute(sql: """
                INSERT INTO tool_trades
                (tool_id, from_user_id, to_user_id, condition_at_send, send_notes, status, expires_at, created_at)
                VALUES (?, ?, ?, ?, ?, 'pending', ?, datetime('now'))
                """, arguments: [toolId, fromUserId, toUserId, condition, notes, expiresStr])

            return dbConn.lastInsertedRowID
        }
    }

    /// Respond to a pending trade (accept or decline).
    public func respondToTrade(
        tradeId: Int64, accepted: Bool, condition: String?, notes: String?
    ) throws {
        try db.writer.write { dbConn in
            guard let trade = try Row.fetchOne(dbConn, sql: """
                SELECT * FROM tool_trades WHERE id = ? AND status = 'pending' AND deleted_at IS NULL
                """, arguments: [tradeId]) else {
                throw ToolsServiceError.tradeNotFound
            }

            let toolId: Int64 = trade["tool_id"]
            let fromUserId: Int64 = trade["from_user_id"]
            let toUserId: Int64 = trade["to_user_id"]
            let newStatus = accepted ? "accepted" : "declined"

            try dbConn.execute(sql: """
                UPDATE tool_trades SET status = ?, condition_at_receive = ?,
                receive_notes = ?, responded_at = datetime('now')
                WHERE id = ?
                """, arguments: [newStatus, condition, notes, tradeId])

            if accepted {
                // Close sender's checkout
                try dbConn.execute(sql: """
                    UPDATE tool_checkouts SET checked_in_at = datetime('now'),
                    checked_in_by = ?, return_condition = ?
                    WHERE tool_id = ? AND checked_in_at IS NULL AND deleted_at IS NULL
                    """, arguments: [fromUserId, trade["condition_at_send"] as String?, toolId])

                // Create new checkout for receiver
                try dbConn.execute(sql: """
                    INSERT INTO tool_checkouts
                    (tool_id, checked_out_by, checked_out_at, checkout_condition, created_at)
                    VALUES (?, ?, datetime('now'), ?, datetime('now'))
                    """, arguments: [toolId, toUserId, condition ?? "Good"])

                // Update tool assignment
                try dbConn.execute(sql: """
                    UPDATE tools SET assigned_to = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [toUserId, toolId])

                // Log in change log
                try dbConn.execute(sql: """
                    INSERT INTO tool_change_log
                    (tool_id, changed_by, change_type, field_name, old_value, new_value,
                     changed_at, verification_status)
                    VALUES (?, ?, 'trade', 'assigned_to', ?, ?, datetime('now'), 'approved')
                    """, arguments: [toolId, toUserId,
                                     String(fromUserId), String(toUserId)])
            }
        }
    }

    /// Expire old trades that passed 7-day window.
    @discardableResult
    public func expireOldTrades() throws -> Int {
        do {
            return try db.writer.write { dbConn in
                let count = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM tool_trades
                    WHERE status = 'pending' AND expires_at < datetime('now') AND deleted_at IS NULL
                    """) ?? 0

                if count > 0 {
                    try dbConn.execute(sql: """
                        UPDATE tool_trades SET status = 'expired', responded_at = datetime('now')
                        WHERE status = 'pending' AND expires_at < datetime('now') AND deleted_at IS NULL
                        """)
                }
                return count
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Get pending trades for a user (incoming + outgoing).
    public func getPendingTradesForUser(userId: Int64) throws -> [ToolTradeInfo] {
        do {
            return try db.writer.read { dbConn -> [ToolTradeInfo] in
                let sql = """
                    SELECT tt.*, t.name AS tool_name, t.serial_number,
                           COALESCE(fu.display_name, fu.email) AS from_name,
                           COALESCE(tu.display_name, tu.email) AS to_name
                    FROM tool_trades tt
                    JOIN tools t ON tt.tool_id = t.id
                    JOIN users fu ON tt.from_user_id = fu.id
                    JOIN users tu ON tt.to_user_id = tu.id
                    WHERE (tt.to_user_id = ? OR tt.from_user_id = ?)
                    AND tt.status = 'pending' AND tt.deleted_at IS NULL
                    ORDER BY tt.created_at DESC
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [userId, userId])
                return rows.map { row in
                    ToolTradeInfo(
                        id: row["id"] ?? 0,
                        toolId: row["tool_id"] ?? 0,
                        toolName: row["tool_name"] ?? "",
                        serialNumber: row["serial_number"] as String?,
                        fromUserId: row["from_user_id"] ?? 0,
                        fromName: row["from_name"] ?? "Unknown",
                        toUserId: row["to_user_id"] ?? 0,
                        toName: row["to_name"] ?? "Unknown",
                        conditionAtSend: row["condition_at_send"] ?? "Good",
                        conditionAtReceive: row["condition_at_receive"] as String?,
                        sendNotes: row["send_notes"] as String?,
                        receiveNotes: row["receive_notes"] as String?,
                        status: row["status"] ?? "pending",
                        createdAt: row["created_at"] ?? "",
                        expiresAt: row["expires_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 11. Lost/Stolen Reporting
    // =========================================================================

    /// Report a tool as lost or stolen.
    public func reportToolLostOrStolen(
        toolId: Int64, reportedBy: Int64, reportType: String,
        description: String, lastKnownLocation: String? = nil
    ) throws {
        try db.writer.write { dbConn in
            // Update tool status
            try dbConn.execute(sql: """
                UPDATE tools SET status = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [reportType, toolId])

            // Log the report in tool_change_log
            try dbConn.execute(sql: """
                INSERT INTO tool_change_log
                (tool_id, changed_by, change_type, field_name, old_value, new_value,
                 notes, changed_at, verification_status)
                VALUES (?, ?, ?, 'status', NULL, ?, ?, datetime('now'), 'approved')
                """, arguments: [toolId, reportedBy, "report_\(reportType)", reportType,
                                 "\(description)\(lastKnownLocation.map { " | Location: \($0)" } ?? "")"])

            // Close active checkout if any
            try dbConn.execute(sql: """
                UPDATE tool_checkouts SET checked_in_at = datetime('now'),
                return_condition = ?, return_notes = ?
                WHERE tool_id = ? AND checked_in_at IS NULL AND deleted_at IS NULL
                """, arguments: [reportType, description, toolId])
        }
    }

    // =========================================================================
    // MARK: - 12. Maintenance Configs
    // =========================================================================

    /// Maintenance config row with all strategy fields.
    public struct MaintenanceConfigInfo: Sendable, Identifiable {
        public let id: Int64
        public let toolId: Int64
        public let maintenanceType: String
        public let intervalDays: Int?
        public let usageThreshold: Double?
        public let scheduleCron: String?
        public let decayRate: Double?
        public let decayFloor: Double?
        public let conditionTriggers: String?
        public let description: String?
        public let isActive: Bool

        public init(id: Int64, toolId: Int64, maintenanceType: String,
                    intervalDays: Int?, usageThreshold: Double?,
                    scheduleCron: String?, decayRate: Double?, decayFloor: Double?,
                    conditionTriggers: String?, description: String?, isActive: Bool) {
            self.id = id; self.toolId = toolId; self.maintenanceType = maintenanceType
            self.intervalDays = intervalDays; self.usageThreshold = usageThreshold
            self.scheduleCron = scheduleCron; self.decayRate = decayRate
            self.decayFloor = decayFloor; self.conditionTriggers = conditionTriggers
            self.description = description; self.isActive = isActive
        }
    }

    /// Create a maintenance config for a tool.
    @discardableResult
    public func createMaintenanceConfig(
        toolId: Int64, type: String, intervalDays: Int? = nil,
        usageThreshold: Double? = nil, decayRate: Double? = nil,
        decayFloor: Double? = nil, conditionTriggers: [String]? = nil,
        description: String? = nil
    ) throws -> Int64 {
        let triggersJSON = conditionTriggers.map { triggers -> String in
            let items = triggers.map { "\"\($0)\"" }.joined(separator: ",")
            return "[\(items)]"
        }
        return try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO tool_maintenance_configs
                (tool_id, maintenance_type, interval_days, usage_threshold,
                 decay_rate, decay_floor, condition_triggers, description, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [toolId, type, intervalDays, usageThreshold,
                                 decayRate, decayFloor, triggersJSON, description])
            return dbConn.lastInsertedRowID
        }
    }

    /// Get all maintenance configs for a tool.
    public func getMaintenanceConfigs(toolId: Int64) throws -> [MaintenanceConfigInfo] {
        do {
            return try db.writer.read { dbConn -> [MaintenanceConfigInfo] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM tool_maintenance_configs
                    WHERE tool_id = ? AND deleted_at IS NULL
                    ORDER BY created_at DESC
                    """, arguments: [toolId])
                return rows.map { row in
                    MaintenanceConfigInfo(
                        id: row["id"] ?? 0,
                        toolId: row["tool_id"] ?? 0,
                        maintenanceType: row["maintenance_type"] ?? "time_based",
                        intervalDays: row["interval_days"] as Int?,
                        usageThreshold: row["usage_threshold"] as Double?,
                        scheduleCron: row["schedule_cron"] as String?,
                        decayRate: row["decay_rate"] as Double?,
                        decayFloor: row["decay_floor"] as Double?,
                        conditionTriggers: row["condition_triggers"] as String?,
                        description: row["description"] as String?,
                        isActive: (row["is_active"] as Int?) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Toggle a maintenance config active/inactive.
    public func toggleMaintenanceConfig(configId: Int64, isActive: Bool) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE tool_maintenance_configs SET is_active = ?
                WHERE id = ?
                """, arguments: [isActive ? 1 : 0, configId])
        }
    }

    /// Record maintenance performed on a tool.
    @discardableResult
    public func recordMaintenance(
        toolId: Int64, configId: Int64?, maintenanceType: String,
        performedBy: Int64, conditionBefore: String?, conditionAfter: String?,
        notes: String?, cost: Double?
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            // Ensure a default maintenance type exists for the FK constraint
            let typeCount = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM tool_maintenance_types") ?? 0
            if typeCount == 0 {
                try dbConn.execute(sql: """
                    INSERT OR IGNORE INTO tool_maintenance_types (name, description, sort_order)
                    VALUES ('General', 'General maintenance', 0)
                    """)
            }

            // Resolve the maintenance_type_id from the config or default
            let typeId: Int64
            if let cId = configId {
                typeId = try Int64.fetchOne(dbConn, sql: """
                    SELECT id FROM tool_maintenance_types LIMIT 1
                    """) ?? cId
            } else {
                typeId = try Int64.fetchOne(dbConn, sql: """
                    SELECT id FROM tool_maintenance_types LIMIT 1
                    """) ?? 1
            }

            // Insert record into the existing tool_maintenance_records table
            try dbConn.execute(sql: """
                INSERT INTO tool_maintenance_records
                (tool_id, maintenance_type_id, service_date, cost, description, performed_by, notes, created_at)
                VALUES (?, ?, date('now'), ?, ?, ?, ?, datetime('now'))
                """, arguments: [toolId, typeId, cost,
                                 "\(conditionBefore ?? "—") → \(conditionAfter ?? "—")",
                                 performedBy, notes])

            let recordId = dbConn.lastInsertedRowID

            // Update tool's maintenance tracking
            if maintenanceType == "decreasing_based" {
                try dbConn.execute(sql: """
                    UPDATE tools SET confidence_score = 1.0,
                    last_maintenance_date = date('now'),
                    updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [toolId])
            } else {
                try dbConn.execute(sql: """
                    UPDATE tools SET last_maintenance_date = date('now'),
                    updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [toolId])
            }

            return recordId
        }
    }

    /// Calculate the next maintenance due date considering all active configs.
    public func calculateNextMaintenanceDate(toolId: Int64) throws -> String? {
        do {
            return try db.writer.read { dbConn -> String? in
                let configs = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM tool_maintenance_configs
                    WHERE tool_id = ? AND is_active = 1 AND deleted_at IS NULL
                    """, arguments: [toolId])

                let tool = try Row.fetchOne(dbConn, sql: """
                    SELECT total_usage_hours, confidence_score, last_maintenance_date
                    FROM tools WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [toolId])

                guard let tool else { return nil }

                let calendar = Calendar.current
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                var earliestDue: Date?

                let lastMaintStr = tool["last_maintenance_date"] as String?
                let lastMaint = lastMaintStr.flatMap { dateFormatter.date(from: $0) }

                for config in configs {
                    let type: String = config["maintenance_type"] ?? ""
                    var dueDate: Date?

                    switch type {
                    case "time_based", "schedule_based":
                        if let intervalDays = config["interval_days"] as Int?,
                           let last = lastMaint {
                            dueDate = calendar.date(byAdding: .day, value: intervalDays, to: last)
                        }

                    case "usage_based":
                        if let threshold = config["usage_threshold"] as Double?,
                           let currentUsage = tool["total_usage_hours"] as Double? {
                            // Check last maintenance usage
                            let lastRecord = try Row.fetchOne(dbConn, sql: """
                                SELECT cost FROM tool_maintenance_records
                                WHERE tool_id = ? ORDER BY created_at DESC LIMIT 1
                                """, arguments: [toolId])
                            let lastUsage = lastRecord?["cost"] as Double? ?? 0
                            let remaining = threshold - (currentUsage - lastUsage)
                            if remaining <= 0 {
                                dueDate = Date() // overdue
                            }
                        }

                    case "decreasing_based":
                        if let decayRate = config["decay_rate"] as Double?,
                           let floor = config["decay_floor"] as Double?,
                           let currentConf = tool["confidence_score"] as Double?,
                           currentConf > floor && decayRate > 0 && decayRate < 1 {
                            let daysUntil = log(floor / currentConf) / log(1.0 - decayRate)
                            dueDate = calendar.date(byAdding: .day, value: Int(ceil(daysUntil)), to: Date())
                        } else if let currentConf = tool["confidence_score"] as Double?,
                                  let floor = config["decay_floor"] as Double?,
                                  currentConf <= floor {
                            dueDate = Date() // already below floor
                        }

                    default:
                        break
                    }

                    if let due = dueDate {
                        if earliestDue == nil || due < earliestDue! {
                            earliestDue = due
                        }
                    }
                }

                return earliestDue.map { dateFormatter.string(from: $0) }
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Update confidence scores for all tools with decreasing-based configs.
    /// Call on app launch.
    @discardableResult
    public func updateConfidenceScores() throws -> Int {
        do {
            return try db.writer.write { dbConn in
                let configs = try Row.fetchAll(dbConn, sql: """
                    SELECT tmc.tool_id, tmc.decay_rate, t.confidence_score
                    FROM tool_maintenance_configs tmc
                    JOIN tools t ON tmc.tool_id = t.id
                    WHERE tmc.maintenance_type = 'decreasing_based'
                    AND tmc.is_active = 1 AND tmc.deleted_at IS NULL
                    """)

                var updated = 0
                for config in configs {
                    let toolId: Int64 = config["tool_id"] ?? 0
                    let decayRate = config["decay_rate"] as Double? ?? 0.01
                    let currentScore = config["confidence_score"] as Double? ?? 1.0
                    let newScore = max(0, currentScore * (1.0 - decayRate))

                    try dbConn.execute(sql: """
                        UPDATE tools SET confidence_score = ?,
                        updated_at = datetime('now')
                        WHERE id = ?
                        """, arguments: [newScore, toolId])
                    updated += 1
                }
                return updated
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Get maintenance records for a tool.
    public func getMaintenanceHistory(toolId: Int64) throws -> [MaintenanceRecordInfo] {
        do {
            return try db.writer.read { dbConn -> [MaintenanceRecordInfo] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT tmr.id, tmr.service_date, tmr.cost, tmr.description,
                           tmr.notes, tmr.created_at,
                           COALESCE(u.display_name, u.email, 'Unknown') AS performed_by_name
                    FROM tool_maintenance_records tmr
                    LEFT JOIN users u ON tmr.performed_by = u.id
                    WHERE tmr.tool_id = ? AND tmr.deleted_at IS NULL
                    ORDER BY tmr.service_date DESC
                    """, arguments: [toolId])
                return rows.map { row in
                    MaintenanceRecordInfo(
                        id: row["id"] ?? 0,
                        serviceDate: row["service_date"] ?? "",
                        cost: row["cost"] as Double?,
                        description: row["description"] as String?,
                        notes: row["notes"] as String?,
                        performedByName: row["performed_by_name"] ?? "Unknown"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Maintenance record for display.
    public struct MaintenanceRecordInfo: Sendable, Identifiable {
        public let id: Int64
        public let serviceDate: String
        public let cost: Double?
        public let description: String?
        public let notes: String?
        public let performedByName: String

        public init(id: Int64, serviceDate: String, cost: Double?,
                    description: String?, notes: String?, performedByName: String) {
            self.id = id; self.serviceDate = serviceDate; self.cost = cost
            self.description = description; self.notes = notes
            self.performedByName = performedByName
        }
    }

    // =========================================================================
    // MARK: - Service Errors
    // =========================================================================

    public enum ToolsServiceError: LocalizedError {
        case toolNotCheckedOutToUser
        case tradePending
        case tradeNotFound
        case editNotFound

        public var errorDescription: String? {
            switch self {
            case .toolNotCheckedOutToUser: return "Tool is not checked out to you"
            case .tradePending: return "This tool already has a pending trade"
            case .tradeNotFound: return "Trade not found or already resolved"
            case .editNotFound: return "Edit not found or already approved"
            }
        }
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Convert condition string to numeric rating (1-5).
    private static func conditionToRating(_ condition: String) -> Int {
        switch condition {
        case "Excellent": return 5
        case "Good": return 4
        case "Fair": return 3
        case "Poor": return 2
        case "Damaged": return 1
        default: return 4
        }
    }

    /// Convert numeric rating to condition string.
    public static func ratingToCondition(_ rating: Int?) -> String {
        switch rating {
        case 5: return "Excellent"
        case 4: return "Good"
        case 3: return "Fair"
        case 2: return "Poor"
        case 1: return "Damaged"
        default: return "Unknown"
        }
    }

    /// Execute a SELECT COUNT(*) query returning an Int.
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
}
