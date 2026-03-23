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
    // MARK: - Internal Helpers
    // =========================================================================

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
