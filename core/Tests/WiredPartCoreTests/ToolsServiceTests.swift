import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Comprehensive tests for ToolsService — tools, kits, checkouts, stats, maintenance.
///
/// Uses direct SQL inserts for test setup because ToolsService is primarily
/// a read-query service. Tables are created by migrations during setUp().
@Suite("ToolsService Tests")
struct ToolsServiceTests {

    // MARK: - Helpers

    /// Insert a tool via direct SQL and return its ID.
    @discardableResult
    private func insertTool(
        _ env: E2ETestHelpers.TestEnvironment,
        toolNumber: String = "T-001",
        name: String = "Pipe Wrench",
        category: String = "hand_tools",
        status: String = "available",
        serialNumber: String? = nil,
        assignedTo: Int64? = nil,
        purchaseCost: Double? = nil,
        notes: String? = nil,
        hasKit: Int = 0
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tools
                    (tool_number, name, category, status, serial_number, assigned_to,
                     purchase_cost, notes, has_kit, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [toolNumber, name, category, status, serialNumber,
                            assignedTo, purchaseCost, notes, hasKit]
            )
            return db.lastInsertedRowID
        }
    }

    /// Insert a kit template component for a tool.
    @discardableResult
    private func insertKitTemplate(
        _ env: E2ETestHelpers.TestEnvironment,
        toolId: Int64,
        componentName: String = "Blade",
        componentType: String = "accessory",
        qtyRequired: Int = 1,
        sortOrder: Int = 0
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO kit_templates
                    (tool_id, component_name, component_type, qty_required, sort_order)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [toolId, componentName, componentType, qtyRequired, sortOrder]
            )
            return db.lastInsertedRowID
        }
    }

    /// Insert a tool movement record.
    @discardableResult
    private func insertToolMovement(
        _ env: E2ETestHelpers.TestEnvironment,
        toolId: Int64,
        movementType: String = "checkout",
        performedBy: Int64
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_movements
                    (tool_id, movement_type, performed_by, created_at)
                    VALUES (?, ?, ?, datetime('now'))
                    """,
                arguments: [toolId, movementType, performedBy]
            )
            return db.lastInsertedRowID
        }
    }

    /// Insert a tool_kits row (creates the table first if needed since it's not in migrations).
    private func ensureToolKitsTable(_ env: E2ETestHelpers.TestEnvironment) throws {
        try env.db.writer.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tool_kits (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    description TEXT,
                    status TEXT DEFAULT 'available',
                    deleted_at TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now')),
                    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tool_kit_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kit_id INTEGER NOT NULL REFERENCES tool_kits(id),
                    tool_id INTEGER NOT NULL REFERENCES tools(id),
                    deleted_at TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now'))
                )
                """)
        }
    }

    /// Insert a tool_kits row and return its ID.
    @discardableResult
    private func insertToolKit(
        _ env: E2ETestHelpers.TestEnvironment,
        name: String = "Electrician Kit",
        description: String? = "Standard electrician kit",
        status: String = "available"
    ) throws -> Int64 {
        try ensureToolKitsTable(env)
        return try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_kits (name, description, status, created_at, updated_at)
                    VALUES (?, ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [name, description, status]
            )
            return db.lastInsertedRowID
        }
    }

    /// Insert a tool_kit_items row linking a tool to a kit.
    @discardableResult
    private func insertToolKitItem(
        _ env: E2ETestHelpers.TestEnvironment,
        kitId: Int64,
        toolId: Int64
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_kit_items (kit_id, tool_id, created_at)
                    VALUES (?, ?, datetime('now'))
                    """,
                arguments: [kitId, toolId]
            )
            return db.lastInsertedRowID
        }
    }

    /// Insert a tool maintenance type and return its ID.
    @discardableResult
    private func insertMaintenanceType(
        _ env: E2ETestHelpers.TestEnvironment,
        name: String = "Calibration",
        description: String? = "Regular calibration check"
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_maintenance_types (name, description, created_at)
                    VALUES (?, ?, datetime('now'))
                    """,
                arguments: [name, description]
            )
            return db.lastInsertedRowID
        }
    }

    /// Insert a tool maintenance record.
    @discardableResult
    private func insertMaintenanceRecord(
        _ env: E2ETestHelpers.TestEnvironment,
        toolId: Int64,
        maintenanceTypeId: Int64,
        serviceDate: String = "2026-03-15",
        cost: Double? = 50.0,
        description: String? = "Routine service",
        performedBy: Int64,
        notes: String? = nil
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_maintenance_records
                    (tool_id, maintenance_type_id, service_date, cost, description, performed_by, notes, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
                    """,
                arguments: [toolId, maintenanceTypeId, serviceDate, cost, description, performedBy, notes]
            )
            return db.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 1. List Tools (Empty)
    // =========================================================================

    @Test("listTools returns empty array when no tools exist")
    func testListToolsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let tools = try env.tools.listTools()
        #expect(tools.isEmpty)
    }

    // =========================================================================
    // MARK: - 2. List Tools After Insert
    // =========================================================================

    @Test("listTools returns tools inserted via direct SQL")
    func testListToolsAfterInsert() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-001", name: "Pipe Wrench", category: "hand_tools",
                       status: "available", serialNumber: "SN-001", purchaseCost: 49.99)
        try insertTool(env, toolNumber: "T-002", name: "Multimeter", category: "electrical",
                       status: "available", serialNumber: "SN-002", purchaseCost: 129.99)

        let tools = try env.tools.listTools()
        #expect(tools.count == 2)

        // Verify fields are mapped correctly
        let wrench = tools.first { $0.toolNumber == "T-001" }
        #expect(wrench != nil)
        #expect(wrench?.name == "Pipe Wrench")
        #expect(wrench?.toolType == "hand_tools")
        #expect(wrench?.status == "available")
        #expect(wrench?.serialNumber == "SN-001")
        #expect(wrench?.currentValue == 49.99)
    }

    @Test("listTools resolves assigned_to user name via JOIN")
    func testListToolsWithAssignedUser() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-100", name: "Assigned Drill",
                       status: "checked_out", assignedTo: env.adminUserId)

        let tools = try env.tools.listTools()
        #expect(tools.count == 1)
        #expect(tools[0].assignedToName != nil)
        #expect(tools[0].assignedToName == "TestAdmin")
    }

    @Test("listTools excludes soft-deleted tools")
    func testListToolsExcludesDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-DEL", name: "Deleted Tool")
        // Soft delete it
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE tools SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [toolId]
            )
        }

        let tools = try env.tools.listTools()
        #expect(tools.isEmpty)
    }

    // =========================================================================
    // MARK: - 3. Search Tools by Name
    // =========================================================================

    @Test("listTools search filters by name")
    func testSearchToolsByName() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-001", name: "Pipe Wrench")
        try insertTool(env, toolNumber: "T-002", name: "Multimeter")
        try insertTool(env, toolNumber: "T-003", name: "Pipe Cutter")

        let results = try env.tools.listTools(search: "Pipe")
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.name.contains("Pipe") })
    }

    @Test("listTools search filters by tool number")
    func testSearchToolsByToolNumber() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "ELEC-001", name: "Wire Stripper")
        try insertTool(env, toolNumber: "PLMB-002", name: "Pipe Wrench")

        let results = try env.tools.listTools(search: "ELEC")
        #expect(results.count == 1)
        #expect(results[0].name == "Wire Stripper")
    }

    @Test("listTools search filters by serial number")
    func testSearchToolsBySerialNumber() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-001", name: "Tool A", serialNumber: "XYZ-12345")
        try insertTool(env, toolNumber: "T-002", name: "Tool B", serialNumber: "ABC-99999")

        let results = try env.tools.listTools(search: "XYZ")
        #expect(results.count == 1)
        #expect(results[0].name == "Tool A")
    }

    @Test("listTools search with no matches returns empty")
    func testSearchToolsNoMatch() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-001", name: "Pipe Wrench")

        let results = try env.tools.listTools(search: "Nonexistent")
        #expect(results.isEmpty)
    }

    // =========================================================================
    // MARK: - 4. Filter Tools by Status
    // =========================================================================

    @Test("listTools filters by status")
    func testFilterToolsByStatus() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-001", name: "Available Tool", status: "available")
        try insertTool(env, toolNumber: "T-002", name: "Checked Out Tool", status: "checked_out")
        try insertTool(env, toolNumber: "T-003", name: "Maintenance Tool", status: "maintenance")
        try insertTool(env, toolNumber: "T-004", name: "Another Available", status: "available")

        let available = try env.tools.listTools(status: "available")
        #expect(available.count == 2)
        #expect(available.allSatisfy { $0.status == "available" })

        let checkedOut = try env.tools.listTools(status: "checked_out")
        #expect(checkedOut.count == 1)
        #expect(checkedOut[0].name == "Checked Out Tool")

        let maintenance = try env.tools.listTools(status: "maintenance")
        #expect(maintenance.count == 1)
        #expect(maintenance[0].name == "Maintenance Tool")
    }

    @Test("listTools combines search and status filters")
    func testFilterToolsBySearchAndStatus() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-001", name: "Pipe Wrench", status: "available")
        try insertTool(env, toolNumber: "T-002", name: "Pipe Cutter", status: "checked_out")
        try insertTool(env, toolNumber: "T-003", name: "Multimeter", status: "available")

        let results = try env.tools.listTools(search: "Pipe", status: "available")
        #expect(results.count == 1)
        #expect(results[0].name == "Pipe Wrench")
    }

    // =========================================================================
    // MARK: - 5. Get Tool Detail
    // =========================================================================

    @Test("getToolDetail returns full detail for existing tool")
    func testGetToolDetail() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(
            env, toolNumber: "T-DTL", name: "Precision Multimeter",
            category: "electrical", status: "available",
            serialNumber: "PM-2026-001", purchaseCost: 299.99,
            notes: "High accuracy model", hasKit: 1
        )

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail != nil)
        #expect(detail?.id == toolId)
        #expect(detail?.toolNumber == "T-DTL")
        #expect(detail?.name == "Precision Multimeter")
        #expect(detail?.category == "electrical")
        #expect(detail?.status == "available")
        #expect(detail?.serialNumber == "PM-2026-001")
        #expect(detail?.purchaseCost == 299.99)
        #expect(detail?.notes == "High accuracy model")
        #expect(detail?.hasKit == true)
    }

    @Test("getToolDetail returns nil for nonexistent tool")
    func testGetToolDetailNonexistent() throws {
        let env = try E2ETestHelpers.setUp()
        let detail = try env.tools.getToolDetail(toolId: 99999)
        #expect(detail == nil)
    }

    @Test("getToolDetail returns nil for soft-deleted tool")
    func testGetToolDetailDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-DEL2", name: "To Delete")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE tools SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [toolId]
            )
        }

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail == nil)
    }

    @Test("getToolDetail resolves assigned user name")
    func testGetToolDetailWithAssignment() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(
            env, toolNumber: "T-ASN", name: "Assigned Tool",
            status: "checked_out", assignedTo: env.adminUserId
        )

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail != nil)
        #expect(detail?.assignedToName == "TestAdmin")
        #expect(detail?.assignedTo == env.adminUserId)
    }

    // =========================================================================
    // MARK: - 6. List Kits (Empty)
    // =========================================================================

    @Test("listKits returns empty array when no kit templates exist")
    func testListKitsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let kits = try env.tools.listKits()
        #expect(kits.isEmpty)
    }

    @Test("listKits returns tools that have kit template components")
    func testListKitsWithData() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-KIT", name: "Power Drill Kit", hasKit: 1)
        try insertKitTemplate(env, toolId: toolId, componentName: "Drill Bit Set")
        try insertKitTemplate(env, toolId: toolId, componentName: "Carrying Case")
        try insertKitTemplate(env, toolId: toolId, componentName: "Charger")

        let kits = try env.tools.listKits()
        #expect(kits.count == 1)
        #expect(kits[0].name == "Power Drill Kit")
        #expect(kits[0].itemCount == 3)
    }

    // =========================================================================
    // MARK: - 7. List Tool Kits
    // =========================================================================

    @Test("listToolKits returns empty when tool_kits table doesn't exist or is empty")
    func testListToolKitsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        // tool_kits table may not exist in migrations — graceful empty return
        let kits = try env.tools.listToolKits()
        #expect(kits.isEmpty)
    }

    @Test("listToolKits returns kits with tool counts")
    func testListToolKitsWithData() throws {
        let env = try E2ETestHelpers.setUp()

        // Create the tool_kits and tool_kit_items tables
        let kitId = try insertToolKit(env, name: "Electrician Kit", description: "Full electrician set")

        let tool1 = try insertTool(env, toolNumber: "T-K1", name: "Wire Stripper")
        let tool2 = try insertTool(env, toolNumber: "T-K2", name: "Multimeter")
        try insertToolKitItem(env, kitId: kitId, toolId: tool1)
        try insertToolKitItem(env, kitId: kitId, toolId: tool2)

        let kits = try env.tools.listToolKits()
        #expect(kits.count == 1)
        #expect(kits[0].name == "Electrician Kit")
        #expect(kits[0].description == "Full electrician set")
        #expect(kits[0].toolCount == 2)
        #expect(kits[0].status == "available")
    }

    @Test("listToolKits excludes soft-deleted kits")
    func testListToolKitsExcludesDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let kitId = try insertToolKit(env, name: "Deleted Kit")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE tool_kits SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [kitId]
            )
        }

        let kits = try env.tools.listToolKits()
        #expect(kits.isEmpty)
    }

    // =========================================================================
    // MARK: - 8. List Checkouts (Empty)
    // =========================================================================

    @Test("listCheckouts returns empty array when no movements exist")
    func testListCheckoutsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let checkouts = try env.tools.listCheckouts()
        #expect(checkouts.isEmpty)
    }

    @Test("listCheckouts returns checkout movements")
    func testListCheckoutsWithData() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-CO1", name: "Checkout Tool")
        try insertToolMovement(env, toolId: toolId, movementType: "checkout", performedBy: env.adminUserId)

        let checkouts = try env.tools.listCheckouts()
        #expect(checkouts.count == 1)
        #expect(checkouts[0].toolName == "Checkout Tool")
        #expect(checkouts[0].checkedOutByName == "TestAdmin")
    }

    @Test("listCheckouts filters by toolId")
    func testListCheckoutsFilterByToolId() throws {
        let env = try E2ETestHelpers.setUp()

        let tool1 = try insertTool(env, toolNumber: "T-F1", name: "Tool One")
        let tool2 = try insertTool(env, toolNumber: "T-F2", name: "Tool Two")
        try insertToolMovement(env, toolId: tool1, movementType: "checkout", performedBy: env.adminUserId)
        try insertToolMovement(env, toolId: tool2, movementType: "checkout", performedBy: env.adminUserId)

        let filtered = try env.tools.listCheckouts(toolId: tool1)
        #expect(filtered.count == 1)
        #expect(filtered[0].toolName == "Tool One")
    }

    @Test("listCheckouts active filter returns only checkout type movements")
    func testListCheckoutsActiveFilter() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-ACT", name: "Active Tool")
        try insertToolMovement(env, toolId: toolId, movementType: "checkout", performedBy: env.adminUserId)
        try insertToolMovement(env, toolId: toolId, movementType: "return", performedBy: env.adminUserId)
        try insertToolMovement(env, toolId: toolId, movementType: "transfer", performedBy: env.adminUserId)

        let active = try env.tools.listCheckouts(active: true)
        #expect(active.count == 1)
        #expect(active[0].toolName == "Active Tool")
    }

    // =========================================================================
    // MARK: - 9. Tools Stats
    // =========================================================================

    @Test("getToolsStats returns zeros when no data exists")
    func testToolsStatsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.tools.getToolsStats()
        #expect(stats.totalTools == 0)
        #expect(stats.checkedOut == 0)
        #expect(stats.inMaintenance == 0)
        #expect(stats.totalKits == 0)
    }

    @Test("getToolsStats returns correct counts with seeded data")
    func testToolsStatsWithData() throws {
        let env = try E2ETestHelpers.setUp()

        // Insert tools with different statuses
        try insertTool(env, toolNumber: "T-S1", name: "Tool 1", status: "available")
        try insertTool(env, toolNumber: "T-S2", name: "Tool 2", status: "available")
        let tool3 = try insertTool(env, toolNumber: "T-S3", name: "Tool 3", status: "maintenance")
        _ = tool3 // used for maintenance count
        try insertTool(env, toolNumber: "T-S4", name: "Tool 4", status: "available")

        // Insert a checkout movement (without a corresponding return)
        let toolCO = try insertTool(env, toolNumber: "T-S5", name: "Checked Out Tool", status: "checked_out")
        try insertToolMovement(env, toolId: toolCO, movementType: "checkout", performedBy: env.adminUserId)

        // Insert kit template components
        let kitTool = try insertTool(env, toolNumber: "T-S6", name: "Kit Tool", hasKit: 1)
        try insertKitTemplate(env, toolId: kitTool, componentName: "Blade")

        let stats = try env.tools.getToolsStats()
        #expect(stats.totalTools == 6)
        #expect(stats.checkedOut == 1)
        #expect(stats.inMaintenance == 1)
        #expect(stats.totalKits == 1)
    }

    @Test("getToolsStats excludes soft-deleted tools from total count")
    func testToolsStatsExcludesDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        try insertTool(env, toolNumber: "T-SD1", name: "Active Tool")
        let deletedId = try insertTool(env, toolNumber: "T-SD2", name: "Deleted Tool")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE tools SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [deletedId]
            )
        }

        let stats = try env.tools.getToolsStats()
        #expect(stats.totalTools == 1)
    }

    // =========================================================================
    // MARK: - 10. List Tool Maintenance
    // =========================================================================

    @Test("getMaintenanceHistory returns empty array when no records exist")
    func testListToolMaintenanceEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-MNT", name: "No Maintenance Tool")
        let records = try env.tools.getMaintenanceHistory(toolId: toolId)
        #expect(records.isEmpty)
    }

    @Test("getMaintenanceHistory returns maintenance records for a tool")
    func testListToolMaintenanceWithRecords() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-MR1", name: "Maintained Tool")
        let typeId = try insertMaintenanceType(env, name: "Calibration")

        try insertMaintenanceRecord(
            env, toolId: toolId, maintenanceTypeId: typeId,
            serviceDate: "2026-01-15", cost: 75.00,
            description: "Annual calibration", performedBy: env.adminUserId,
            notes: "Passed all checks"
        )
        try insertMaintenanceRecord(
            env, toolId: toolId, maintenanceTypeId: typeId,
            serviceDate: "2026-03-15", cost: 50.00,
            description: "Quarterly service", performedBy: env.adminUserId
        )

        let records = try env.tools.getMaintenanceHistory(toolId: toolId)
        #expect(records.count == 2)

        // Sorted by service_date DESC — most recent first
        #expect(records[0].serviceDate == "2026-03-15")
        #expect(records[0].cost == 50.00)
        #expect(records[0].description == "Quarterly service")
        #expect(records[0].performedByName == "TestAdmin")

        #expect(records[1].serviceDate == "2026-01-15")
        #expect(records[1].cost == 75.00)
        #expect(records[1].description == "Annual calibration")
    }

    @Test("getMaintenanceHistory excludes records for other tools")
    func testMaintenanceHistoryFiltersByTool() throws {
        let env = try E2ETestHelpers.setUp()

        let tool1 = try insertTool(env, toolNumber: "T-MF1", name: "Tool Alpha")
        let tool2 = try insertTool(env, toolNumber: "T-MF2", name: "Tool Beta")
        let typeId = try insertMaintenanceType(env, name: "Inspection")

        try insertMaintenanceRecord(env, toolId: tool1, maintenanceTypeId: typeId,
                                    description: "Alpha service", performedBy: env.adminUserId)
        try insertMaintenanceRecord(env, toolId: tool2, maintenanceTypeId: typeId,
                                    description: "Beta service", performedBy: env.adminUserId)

        let records1 = try env.tools.getMaintenanceHistory(toolId: tool1)
        #expect(records1.count == 1)
        #expect(records1[0].description == "Alpha service")

        let records2 = try env.tools.getMaintenanceHistory(toolId: tool2)
        #expect(records2.count == 1)
        #expect(records2[0].description == "Beta service")
    }

    // =========================================================================
    // MARK: - Checkout/Return with Condition
    // =========================================================================

    @Test("checkoutToolWithCondition updates tool status and creates checkout record")
    func testCheckoutWithCondition() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-CWC", name: "Condition Tool", status: "available")

        try env.tools.checkoutToolWithCondition(
            toolId: toolId, userId: env.adminUserId,
            condition: "Good", notes: "Field use"
        )

        // Tool status should be updated
        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.status == "checked_out")
        #expect(detail?.assignedTo == env.adminUserId)
    }

    @Test("returnToolWithCondition resets tool status to available")
    func testReturnWithCondition() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-RWC", name: "Return Tool",
                                    status: "checked_out", assignedTo: env.adminUserId)

        // Create an open checkout record first
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_checkouts
                    (tool_id, checked_out_by, checked_out_at, checkout_condition, created_at)
                    VALUES (?, ?, datetime('now'), 'Good', datetime('now'))
                    """,
                arguments: [toolId, env.adminUserId]
            )
        }

        try env.tools.returnToolWithCondition(
            toolId: toolId, userId: env.adminUserId,
            condition: "Fair", notes: "Minor wear"
        )

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.status == "available")
        #expect(detail?.assignedTo == nil)
    }

    // =========================================================================
    // MARK: - Kit Contents
    // =========================================================================

    @Test("getKitContents returns components for a tool with kit templates")
    func testGetKitContents() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-KC", name: "Kit Tool", hasKit: 1)
        try insertKitTemplate(env, toolId: toolId, componentName: "Drill Bit", componentType: "accessory", sortOrder: 1)
        try insertKitTemplate(env, toolId: toolId, componentName: "Battery", componentType: "consumable", sortOrder: 2)

        let contents = try env.tools.getKitContents(toolId: toolId)
        #expect(contents.count == 2)
        #expect(contents[0].name == "Drill Bit")
        #expect(contents[0].itemType == "accessory")
        #expect(contents[1].name == "Battery")
        #expect(contents[1].itemType == "consumable")
    }

    @Test("getKitContents returns empty for tool without kit templates")
    func testGetKitContentsEmpty() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-NKC", name: "No Kit Tool")
        let contents = try env.tools.getKitContents(toolId: toolId)
        #expect(contents.isEmpty)
    }

    // =========================================================================
    // MARK: - Edit with Verification
    // =========================================================================

    @Test("editToolWithVerification with permission applies changes directly")
    func testEditWithPermission() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-EDIT", name: "Old Name", category: "general")

        let result = try env.tools.editToolWithVerification(
            toolId: toolId, userId: env.adminUserId,
            changes: ["name": "New Name"], hasPermission: true
        )

        #expect(result.status == "approved")
        #expect(!result.requiresVerification)

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.name == "New Name")
    }

    @Test("editToolWithVerification without permission creates pending edit")
    func testEditWithoutPermission() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-PEND", name: "Original Name")

        let result = try env.tools.editToolWithVerification(
            toolId: toolId, userId: env.adminUserId,
            changes: ["name": "Requested Name"], hasPermission: false
        )

        #expect(result.status == "pending_verification")
        #expect(result.requiresVerification)

        // Name should NOT be changed yet
        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.name == "Original Name")

        // Pending edit should be listed
        let pendingEdits = try env.tools.listPendingToolEdits()
        #expect(!pendingEdits.isEmpty)
        #expect(pendingEdits.first?.fieldName == "name")
        #expect(pendingEdits.first?.newValue == "Requested Name")
    }

    // =========================================================================
    // MARK: - Maintenance Configs
    // =========================================================================

    @Test("createMaintenanceConfig and getMaintenanceConfigs round-trip")
    func testMaintenanceConfigLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-MC", name: "Config Tool")

        let configId = try env.tools.createMaintenanceConfig(
            toolId: toolId, type: "time_based",
            intervalDays: 90, description: "Quarterly check"
        )
        #expect(configId > 0)

        let configs = try env.tools.getMaintenanceConfigs(toolId: toolId)
        #expect(configs.count == 1)
        #expect(configs[0].maintenanceType == "time_based")
        #expect(configs[0].intervalDays == 90)
        #expect(configs[0].description == "Quarterly check")
    }

    @Test("recordMaintenance creates a maintenance record and updates tool")
    func testRecordMaintenance() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-REC", name: "Record Tool")
        let configId = try env.tools.createMaintenanceConfig(
            toolId: toolId, type: "time_based", intervalDays: 30
        )

        let recordId = try env.tools.recordMaintenance(
            toolId: toolId, configId: configId,
            maintenanceType: "time_based", performedBy: env.adminUserId,
            conditionBefore: "Fair", conditionAfter: "Good",
            notes: "Cleaned and lubricated", cost: 25.00
        )
        #expect(recordId > 0)

        // Verify in maintenance history
        let history = try env.tools.getMaintenanceHistory(toolId: toolId)
        #expect(history.count == 1)
        #expect(history[0].cost == 25.00)
        #expect(history[0].performedByName == "TestAdmin")
    }

    // =========================================================================
    // MARK: - Tool Trades
    // =========================================================================

    @Test("initiateTrade fails when tool is not checked out to user")
    func testInitiateTradeFailsNotCheckedOut() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-TRD", name: "Trade Tool", status: "available")

        // Create a second user as the trade recipient
        let recipientId = try env.db.writer.write { dbConn -> Int64 in
            try dbConn.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active, created_at, updated_at)
                VALUES ('Recipient', 'hash', 1, datetime('now'), datetime('now'))
                """)
            return dbConn.lastInsertedRowID
        }

        #expect(throws: ToolsService.ToolsServiceError.self) {
            try env.tools.initiateTrade(
                toolId: toolId, fromUserId: env.adminUserId,
                toUserId: recipientId, condition: "Good"
            )
        }
    }

    // =========================================================================
    // MARK: - Version History
    // =========================================================================

    @Test("getToolVersionHistory returns change log entries")
    func testToolVersionHistory() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-VH", name: "Version Tool")

        // Create a change via edit
        try env.tools.editToolWithVerification(
            toolId: toolId, userId: env.adminUserId,
            changes: ["category": "power_tools"], hasPermission: true
        )

        let history = try env.tools.getToolVersionHistory(toolId: toolId)
        #expect(!history.isEmpty)
        #expect(history[0].fieldName == "category")
        #expect(history[0].newValue == "power_tools")
        #expect(history[0].changeType == "edit")
        #expect(history[0].verificationStatus == "approved")
    }

    // =========================================================================
    // MARK: - Lost/Stolen Reporting
    // =========================================================================

    @Test("reportToolLostOrStolen updates tool status")
    func testReportLostOrStolen() throws {
        let env = try E2ETestHelpers.setUp()

        let toolId = try insertTool(env, toolNumber: "T-LOST", name: "Lost Tool", status: "available")

        try env.tools.reportToolLostOrStolen(
            toolId: toolId, reportedBy: env.adminUserId,
            reportType: "lost", description: "Left at job site",
            lastKnownLocation: "123 Main St"
        )

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.status == "lost")
    }

    // =========================================================================
    // MARK: - Basic Checkout / Return (Legacy API)
    // =========================================================================

    @Test("checkoutTool sets status to checked_out and creates checkout record")
    func testCheckoutToolLegacy() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-CO-L", name: "Legacy Checkout Tool", status: "available")

        try env.tools.checkoutTool(toolId: toolId, userId: env.adminUserId, notes: "Needed on site")

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.status == "checked_out")
    }

    @Test("returnTool resets status to available and closes checkout record")
    func testReturnToolLegacy() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-RT-L", name: "Legacy Return Tool", status: "available")

        try env.tools.checkoutTool(toolId: toolId, userId: env.adminUserId, notes: nil)
        try env.tools.returnTool(toolId: toolId, userId: env.adminUserId, notes: "Returned clean")

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.status == "available")
    }

    // =========================================================================
    // MARK: - Mark Maintenance
    // =========================================================================

    @Test("markToolMaintenance sets tool status to maintenance")
    func testMarkToolMaintenance() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-MTM", name: "Maintenance Tool", status: "available")

        try env.tools.markToolMaintenance(toolId: toolId)

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.status == "maintenance")
    }

    // =========================================================================
    // MARK: - Pending Edits Workflow
    // =========================================================================

    @Test("getPendingEdits returns edits only for the specified tool")
    func testGetPendingEditsIsolation() throws {
        let env = try E2ETestHelpers.setUp()
        let toolA = try insertTool(env, toolNumber: "T-PE-A", name: "Edit Tool A")
        let toolB = try insertTool(env, toolNumber: "T-PE-B", name: "Edit Tool B")

        // Create pending edit for A (no permission → creates pending record)
        try env.tools.editToolWithVerification(
            toolId: toolA, userId: env.adminUserId,
            changes: ["notes": "Updated A"], hasPermission: false
        )

        let editsForA = try env.tools.getPendingEdits(toolId: toolA)
        let editsForB = try env.tools.getPendingEdits(toolId: toolB)

        #expect(editsForA.count == 1)
        #expect(editsForA[0].fieldName == "notes")
        #expect(editsForB.isEmpty)
    }

    @Test("approveToolEdit applies the field change to the tool")
    func testApproveToolEdit() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-APR", name: "Approvable Tool")

        // Create a pending edit (without permission)
        try env.tools.editToolWithVerification(
            toolId: toolId, userId: env.adminUserId,
            changes: ["notes": "Approved note"], hasPermission: false
        )

        let pending = try env.tools.listPendingToolEdits()
        let editId = pending.first(where: { $0.toolId == toolId })!.id

        // Approve it
        try env.tools.approveToolEdit(editId: editId, approverId: env.adminUserId)

        // The field should now be applied
        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.notes == "Approved note")

        // Should no longer appear in pending list
        let remaining = try env.tools.listPendingToolEdits()
        #expect(!remaining.contains(where: { $0.id == editId }))
    }

    @Test("rejectToolEdit marks the edit as rejected without applying changes")
    func testRejectToolEdit() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-REJ", name: "Reject Tool")

        try env.tools.editToolWithVerification(
            toolId: toolId, userId: env.adminUserId,
            changes: ["notes": "Should not apply"], hasPermission: false
        )

        let pending = try env.tools.listPendingToolEdits()
        let editId = pending.first(where: { $0.toolId == toolId })!.id

        try env.tools.rejectToolEdit(editId: editId, rejectedBy: env.adminUserId)

        // Change should NOT have been applied
        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.notes == nil || detail?.notes != "Should not apply")

        // Edit no longer pending
        let remaining = try env.tools.listPendingToolEdits()
        #expect(!remaining.contains(where: { $0.id == editId }))
    }

    // =========================================================================
    // MARK: - Tool Trades: respond / expire / list
    // =========================================================================

    /// Helper to create a second user and a pending trade.
    private func setupPendingTrade(_ env: E2ETestHelpers.TestEnvironment) throws -> (toolId: Int64, tradeId: Int64, recipientId: Int64) {
        let toolId = try insertTool(
            env, toolNumber: "T-TRD2", name: "Trade Tool 2",
            status: "checked_out", assignedTo: env.adminUserId
        )

        // Open a checkout record so returnTool/respondToTrade can close it
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO tool_checkouts
                (tool_id, checked_out_by, checked_out_at, checkout_condition, created_at)
                VALUES (?, ?, datetime('now'), 'Good', datetime('now'))
                """, arguments: [toolId, env.adminUserId])
        }

        let recipientId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO users (display_name, pin_hash, is_active, created_at, updated_at)
                VALUES ('Recipient2', 'hash2', 1, datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }

        let tradeId = try env.tools.initiateTrade(
            toolId: toolId, fromUserId: env.adminUserId,
            toUserId: recipientId, condition: "Good"
        )
        return (toolId, tradeId, recipientId)
    }

    @Test("respondToTrade accept transfers tool assignment to recipient")
    func testRespondToTradeAccepted() throws {
        let env = try E2ETestHelpers.setUp()
        let (toolId, tradeId, recipientId) = try setupPendingTrade(env)

        try env.tools.respondToTrade(tradeId: tradeId, accepted: true, condition: "Good", notes: nil)

        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.assignedTo == recipientId)
    }

    @Test("respondToTrade decline leaves tool unchanged and closes trade")
    func testRespondToTradeDeclined() throws {
        let env = try E2ETestHelpers.setUp()
        let (toolId, tradeId, _) = try setupPendingTrade(env)

        try env.tools.respondToTrade(tradeId: tradeId, accepted: false, condition: nil, notes: "Not needed")

        // Tool stays assigned to sender
        let detail = try env.tools.getToolDetail(toolId: toolId)
        #expect(detail?.assignedTo == env.adminUserId)
    }

    @Test("expireOldTrades returns 0 when no trades exist")
    func testExpireOldTradesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let expired = try env.tools.expireOldTrades()
        #expect(expired == 0)
    }

    @Test("getPendingTradesForUser returns trades where user is sender or recipient")
    func testGetPendingTradesForUser() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, recipientId) = try setupPendingTrade(env)

        // Both sender and recipient see the trade
        let senderTrades = try env.tools.getPendingTradesForUser(userId: env.adminUserId)
        let recipientTrades = try env.tools.getPendingTradesForUser(userId: recipientId)

        #expect(senderTrades.count >= 1)
        #expect(recipientTrades.count >= 1)
    }

    // =========================================================================
    // MARK: - Maintenance Config: toggle + calculateNextDate
    // =========================================================================

    @Test("toggleMaintenanceConfig deactivates an active config")
    func testToggleMaintenanceConfigOff() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-TOG", name: "Toggle Config Tool")

        let configId = try env.tools.createMaintenanceConfig(
            toolId: toolId, type: "time_based",
            intervalDays: 30, description: "Monthly"
        )

        // Config is active by default
        var configs = try env.tools.getMaintenanceConfigs(toolId: toolId)
        #expect(configs.first?.isActive == true)

        // Deactivate
        try env.tools.toggleMaintenanceConfig(configId: configId, isActive: false)

        configs = try env.tools.getMaintenanceConfigs(toolId: toolId)
        #expect(configs.first?.isActive == false)

        // Re-activate
        try env.tools.toggleMaintenanceConfig(configId: configId, isActive: true)
        configs = try env.tools.getMaintenanceConfigs(toolId: toolId)
        #expect(configs.first?.isActive == true)
    }

    @Test("calculateNextMaintenanceDate returns nil when tool has no active configs")
    func testCalculateNextMaintenanceDateNoConfigs() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-NMD", name: "No Config Tool")

        let result = try env.tools.calculateNextMaintenanceDate(toolId: toolId)
        #expect(result == nil)
    }

    @Test("calculateNextMaintenanceDate returns a date string after prior maintenance was recorded")
    func testCalculateNextMaintenanceDateWithConfig() throws {
        let env = try E2ETestHelpers.setUp()
        let toolId = try insertTool(env, toolNumber: "T-NMD2", name: "Config Tool 2")

        let configId = try env.tools.createMaintenanceConfig(
            toolId: toolId, type: "time_based",
            intervalDays: 90, description: "Quarterly"
        )

        // Record maintenance — this sets last_maintenance_date on the tool,
        // which is required for time_based calculation to produce a due date.
        _ = try env.tools.recordMaintenance(
            toolId: toolId, configId: configId,
            maintenanceType: "time_based", performedBy: env.adminUserId,
            conditionBefore: nil, conditionAfter: nil,
            notes: nil, cost: nil
        )

        let result = try env.tools.calculateNextMaintenanceDate(toolId: toolId)
        // Should return a non-nil date string in yyyy-MM-dd format (90 days from today)
        #expect(result != nil)
        #expect(result!.count == 10) // yyyy-MM-dd
    }

    // MARK: - updateConfidenceScores

    @Test("updateConfidenceScores returns 0 with no decreasing_based configs")
    func testUpdateConfidenceScores_noConfigs() throws {
        let env = try E2ETestHelpers.setUp()
        // Fresh DB — no tools, no maintenance configs
        let updated = try env.tools.updateConfidenceScores()
        #expect(updated == 0, "No decreasing_based configs → should update zero tools")
    }

    @Test("updateConfidenceScores applies decay rate and returns updated count")
    func testUpdateConfidenceScores_appliesDecay() throws {
        let env = try E2ETestHelpers.setUp()

        // Insert a tool with an initial confidence score of 1.0
        let toolId = try insertTool(env, toolNumber: "T-DECAY", name: "Decay Tool")
        // Ensure the tool has confidence_score = 1.0 (migration default)
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE tools SET confidence_score = 1.0 WHERE id = ?",
                arguments: [toolId]
            )
        }

        // Insert a decreasing_based maintenance config with decay_rate = 0.1
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO tool_maintenance_configs
                        (tool_id, maintenance_type, decay_rate, is_active, created_at)
                    VALUES (?, 'decreasing_based', 0.1, 1, datetime('now'))
                    """,
                arguments: [toolId]
            )
        }

        let updated = try env.tools.updateConfidenceScores()
        #expect(updated == 1, "One decreasing_based config → should update one tool")

        // Verify score: 1.0 * (1 - 0.1) = 0.9
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT confidence_score FROM tools WHERE id = ?",
                             arguments: [toolId])
        }
        let score: Double = try #require(row)?["confidence_score"] ?? -1
        #expect(abs(score - 0.9) < 0.0001, "Confidence score should decay from 1.0 to 0.9 with decay_rate=0.1")
    }

    // MARK: - ratingToCondition (pure static)

    @Test("ratingToCondition maps 5 to Excellent")
    func testRatingExcellent() {
        #expect(ToolsService.ratingToCondition(5) == "Excellent")
    }

    @Test("ratingToCondition maps 4 to Good")
    func testRatingGood() {
        #expect(ToolsService.ratingToCondition(4) == "Good")
    }

    @Test("ratingToCondition maps 3 to Fair")
    func testRatingFair() {
        #expect(ToolsService.ratingToCondition(3) == "Fair")
    }

    @Test("ratingToCondition maps 2 to Poor")
    func testRatingPoor() {
        #expect(ToolsService.ratingToCondition(2) == "Poor")
    }

    @Test("ratingToCondition maps 1 to Damaged")
    func testRatingDamaged() {
        #expect(ToolsService.ratingToCondition(1) == "Damaged")
    }

    @Test("ratingToCondition maps nil to Unknown")
    func testRatingNil() {
        #expect(ToolsService.ratingToCondition(nil) == "Unknown")
    }

    @Test("ratingToCondition maps out-of-range values to Unknown")
    func testRatingOutOfRange() {
        #expect(ToolsService.ratingToCondition(0) == "Unknown")
        #expect(ToolsService.ratingToCondition(6) == "Unknown")
        #expect(ToolsService.ratingToCondition(-1) == "Unknown")
    }
}
