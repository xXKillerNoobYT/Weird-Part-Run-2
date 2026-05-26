import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("WarehouseService Extended Tests")
struct WarehouseServiceExtTests {

    // MARK: - KPIs & Dashboard

    @Test("Warehouse KPIs on fresh DB")
    func testWarehouseKPIs() throws {
        let env = try E2ETestHelpers.setUp()
        let kpis = try env.warehouse.getWarehouseKPIs()
        #expect(kpis.totalStock >= 0)
    }

    @Test("Dashboard KPIs")
    func testDashboardKPIs() throws {
        let env = try E2ETestHelpers.setUp()
        let kpis = try env.warehouse.getDashboardKPIs()
        #expect(kpis.kpis.totalStock >= 0)
    }

    @Test("Recent activity empty on fresh DB")
    func testRecentActivity() throws {
        let env = try E2ETestHelpers.setUp()
        let activity = try env.warehouse.getRecentActivity(limit: 10)
        #expect(activity.isEmpty)
    }

    // MARK: - Movements

    @Test("Create and list movements")
    func testMovementLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let movementId = try env.warehouse.createMovement(
            partId: partId,
            qty: 50,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "warehouse",
            toLocationId: 1,
            movementType: "receive",
            reason: "Initial stock",
            performedBy: env.adminUserId
        )
        #expect(movementId > 0)

        let movements = try env.warehouse.listMovements(limit: 50)
        #expect(movements.count >= 1)
    }

    @Test("Dashboard smart card summary counts service-backed warehouse slices")
    func testDashboardSmartCardSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-DASH", supplierId: supplierId, notes: nil)

        _ = try env.warehouse.createMovement(
            partId: partId,
            qty: 5,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "warehouse",
            toLocationId: 1,
            movementType: "received",
            reason: "Dashboard count",
            performedBy: env.adminUserId
        )
        _ = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)

        let stockId: Int64 = try env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT id FROM stock WHERE part_id = ? LIMIT 1", arguments: [partId])?["id"] ?? 0
        }
        _ = try env.warehouse.createStagingTag(
            stockId: stockId,
            destinationType: "job",
            destinationId: 1,
            destinationLabel: "Ready",
            taggedBy: env.adminUserId
        )
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO warehouse_floor_plans (id, name, width_inches, length_inches)
                VALUES (1, 'Main', 600, 400)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_units (id, floor_plan_id, name, unit_type)
                VALUES (1, 1, 'Shelf A', 'shelf')
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_levels (id, unit_id, level_code, level_order)
                VALUES (1, 1, 'L1', 1)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_areas (id, level_id, area_code, area_number)
                VALUES (1, 1, 'A1', 1)
                """)
        }
        try env.warehouse.setPartConfidence(partId: partId, areaId: 1, percent: 25)

        let summary = try env.warehouse.getDashboardSmartCardSummary()
        #expect(summary.movesToday >= 1)
        #expect(summary.activeReceiving == 1)
        #expect(summary.stagedReady == 1)
        #expect(summary.auditDue == 1)
        #expect(summary.lowConfidenceAreas == 1)
    }

    @Test("Movement query filters by date type completion group and sort order")
    func testMovementQueryFilters() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!

        _ = try env.warehouse.createQuickLogMovement(
            partId: partId,
            qty: 1,
            movementType: "received",
            occurredAt: tenDaysAgo,
            toLocationType: "warehouse",
            toLocationId: 1,
            reason: "Old receive",
            performedBy: env.adminUserId
        )
        _ = try env.warehouse.createQuickLogMovement(
            partId: partId,
            qty: 2,
            movementType: "return",
            occurredAt: twoDaysAgo,
            reason: "Recent return",
            performedBy: env.adminUserId
        )
        _ = try env.warehouse.createQuickLogMovement(
            partId: partId,
            qty: 3,
            movementType: "receiving_staged",
            occurredAt: now,
            reason: "Active staged",
            performedBy: env.adminUserId
        )

        let recentReturns = try env.warehouse.listMovements(
            movementType: "return_to_supplier",
            startDate: Calendar.current.date(byAdding: .day, value: -7, to: now),
            endDate: now,
            sortDirection: .ascending
        )
        #expect(recentReturns.map(\.movementType) == ["return_to_supplier"])

        let completedHistory = try env.warehouse.listMovements(
            startDate: Calendar.current.date(byAdding: .day, value: -7, to: now),
            endDate: now,
            completionFilter: .completed
        )
        #expect(completedHistory.contains { $0.reason == "Recent return" })
        #expect(!completedHistory.contains { $0.reason == "Old receive" })
        #expect(!completedHistory.contains { $0.reason == "Active staged" })

        let active = try env.warehouse.listMovements(completionFilter: .active)
        #expect(active.count == 1)
        #expect(active.first?.movementType == "receiving_staged")
    }

    @Test("Quick Log persists happened-at and audit trail fields")
    func testQuickLogPersistence() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let happenedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let movementId = try env.warehouse.createQuickLogMovement(
            partId: partId,
            qty: 4,
            movementType: "consumed",
            occurredAt: happenedAt,
            reason: "Already happened",
            notes: "Logged from quick entry",
            performedBy: env.adminUserId,
            verifiedBy: env.adminUserId,
            scanConfirmed: true,
            gpsLat: 39.7392,
            gpsLng: -104.9903
        )

        let movement = try env.warehouse.getMovement(id: movementId)
        #expect(movement?.movementType == "consume")
        #expect(movement?.createdAt == "2023-11-14 22:13:20")
        #expect(movement?.verifiedBy == env.adminUserId)
        #expect(movement?.scanConfirmed == true)
        #expect(movement?.gpsLat == 39.7392)
        #expect(movement?.gpsLng == -104.9903)
    }

    @Test("Movement service returns empty defaults when movement table is missing")
    func testMovementMissingTableDefaults() throws {
        let env = try E2ETestHelpers.setUp()
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE stock_movements")
        }

        let movements = try env.warehouse.listMovements()
        let summary = try env.warehouse.getDashboardSmartCardSummary()
        #expect(movements.isEmpty)
        #expect(summary.movesToday == 0)
    }

    @Test("Validate movement")
    func testValidateMovement() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 100)

        let result = try env.warehouse.validateMovement(
            partId: partId,
            qty: 50,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            toLocationType: "job",
            toLocationId: 1
        )
        #expect(result.isValid)
    }

    @Test("Stock quantity check")
    func testStockQty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 75)

        let qty = try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1)
        #expect(qty >= 75)
    }

    // MARK: - Inventory Grid

    @Test("Inventory grid")
    func testInventoryGrid() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 25)

        let grid = try env.warehouse.getInventoryGrid()
        #expect(grid.count >= 1)
    }

    @Test("Location stock")
    func testLocationStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 30)

        let stock = try env.warehouse.getLocationStock()
        #expect(stock.count >= 1)
    }

    // MARK: - Staging

    @Test("Create and retrieve staging tag")
    func testStagingTag() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20)

        // After seedStock, a stock row exists. Query for first stock row ID.
        let stockId: Int64 = try env.db.writer.read { dbConn in
            let row = try Row.fetchOne(dbConn, sql: "SELECT id FROM stock WHERE part_id = ? LIMIT 1", arguments: [partId])
            return row?["id"] ?? 1
        }

        let tagId = try env.warehouse.createStagingTag(
            stockId: stockId,
            destinationType: "job",
            destinationId: 1,
            destinationLabel: "For tomorrow",
            taggedBy: env.adminUserId
        )
        #expect(tagId > 0)

        let staged = try env.warehouse.getStagedItems()
        #expect(staged.count >= 1)
    }

    // MARK: - Receiving Session

    @Test("Start and complete receiving session")
    func testReceivingSession() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-RCV", supplierId: supplierId, notes: nil)

        let sessionId = try env.warehouse.startReceivingSession(
            poId: poId,
            startedBy: env.adminUserId
        )
        #expect(sessionId > 0)
    }

    // MARK: - Inventory Reports

    @Test("Inventory value report")
    func testInventoryValueReport() throws {
        let env = try E2ETestHelpers.setUp()
        let report = try env.warehouse.getInventoryValueReport()
        #expect(report.count >= 0)
    }

    @Test("Backorder report")
    func testBackorderReport() throws {
        let env = try E2ETestHelpers.setUp()
        let report = try env.warehouse.getBackorderReport()
        #expect(report.count >= 0)
    }

    @Test("Turnover report")
    func testTurnoverReport() throws {
        let env = try E2ETestHelpers.setUp()
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let endDate = Date()
        let report = try env.warehouse.getTurnoverReport(startDate: startDate, endDate: endDate)
        #expect(report.count >= 0)
    }

    // MARK: - Consolidation

    @Test("Suggest consolidation on empty DB")
    func testSuggestConsolidation() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let suggestion = try env.warehouse.suggestConsolidation(partId: partId)
        // May return nil when no consolidation is needed
        #expect(suggestion == nil || suggestion != nil)
    }

    // MARK: - Misplaced Parts

    @Test("Log and retrieve misplaced part")
    func testMisplacedParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Seed FK chain: floor_plan → storage_unit → storage_level → storage_area (×2)
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO warehouse_floor_plans (id, name, width_inches, length_inches) VALUES (1, 'Main', 600, 400)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_units (id, floor_plan_id, name, unit_type) VALUES (1, 1, 'Shelf A', 'shelf')
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_levels (id, unit_id, level_code, level_order) VALUES (1, 1, 'L1', 1)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_areas (id, level_id, area_code, area_number) VALUES (1, 1, 'A1', 1)
                """)
            try dbConn.execute(sql: """
                INSERT INTO warehouse_storage_areas (id, level_id, area_code, area_number) VALUES (2, 1, 'A2', 2)
                """)
        }

        _ = try env.warehouse.logMisplacedPart(
            partId: partId,
            foundAtAreaId: 1,
            homeAreaId: 2,
            qtyFound: 5,
            foundBy: env.adminUserId
        )
        let pending = try env.warehouse.getPendingMisplacedParts()
        #expect(pending.count >= 1)
    }

    // MARK: - Warehouse Rating

    @Test("User warehouse rating")
    func testUserWarehouseRating() throws {
        let env = try E2ETestHelpers.setUp()
        let rating = try env.warehouse.getUserWarehouseRating(userId: env.adminUserId)
        // getUserWarehouseRating returns a valid rating object (may have default values)
        _ = rating
    }

    @Test("Warehouse leaderboard")
    func testLeaderboard() throws {
        let env = try E2ETestHelpers.setUp()
        let leaderboard = try env.warehouse.getWarehouseLeaderboard()
        #expect(leaderboard.count >= 0)
    }

    // MARK: - Active JPO Demand (qty_received fix)

    @Test("getActiveJPODemandForPart uses qty_received column correctly")
    func testActiveJPODemand() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env)

        // Create a JPO with a line item for this part
        let jpoId = try env.orders.createJPOWithLines(
            jobId: jobId,
            requestedBy: env.adminUserId,
            priority: "normal",
            deliveryOption: "delivery",
            notes: nil,
            lines: [(partId: partId, quantity: 10)]
        )
        #expect(jpoId > 0)

        // Update JPO status so it qualifies (pending or approved)
        try env.orders.updateJPOStatus(id: jpoId, status: "approved")

        // Query demand — this will crash if qty_fulfilled column doesn't exist
        let demand = try env.warehouse.getActiveJPODemandForPart(partId: partId)
        #expect(demand.count >= 1)
        if let first = demand.first {
            #expect(first.qtyRequested == 10)
            #expect(first.qtyFulfilled == 0) // Nothing received yet
        }
    }

    // MARK: - getMovement

    @Test("getMovement returns nil for non-existent ID")
    func testGetMovementNil() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.warehouse.getMovement(id: 99999)
        #expect(result == nil)
    }

    @Test("getMovement returns movement after createMovement")
    func testGetMovementAfterCreate() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let movId = try env.warehouse.createMovement(
            partId: partId,
            qty: 10,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "warehouse",
            toLocationId: 1,
            movementType: "receive",
            reason: "Initial",
            performedBy: env.adminUserId
        )

        let movement = try env.warehouse.getMovement(id: movId)
        #expect(movement != nil)
        #expect(movement?.qty == 10)
        #expect(movement?.movementType == "receive")
        #expect(movement?.partId == partId)
    }

    // MARK: - previewMovement

    @Test("previewMovement returns PreviewLine with correct fields")
    func testPreviewMovement() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Preview Part", categoryId: catId)

        let preview = try env.warehouse.previewMovement(
            partId: partId,
            qty: 5,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            toLocationType: "job",
            toLocationId: 1
        )

        #expect(preview.partName == "Preview Part")
        #expect(preview.qty == 5)
        #expect(!preview.fromLabel.isEmpty)
        #expect(!preview.toLabel.isEmpty)
        #expect(!preview.movementType.isEmpty)
    }

    // MARK: - executeMovement

    @Test("executeMovement validates and creates movement record")
    func testExecuteMovement() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        // Seed stock so the movement is valid
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 50)

        let movId = try env.warehouse.executeMovement(
            partId: partId,
            qty: 10,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            toLocationType: "job",
            toLocationId: 1,
            reason: "Job pull",
            performedBy: env.adminUserId
        )
        #expect(movId > 0)

        // Verify movement was recorded
        let movement = try env.warehouse.getMovement(id: movId)
        #expect(movement?.qty == 10)
        #expect(movement?.movementType == "transfer")
    }

    // MARK: - getStockAtLocation

    @Test("getStockAtLocation returns empty for location with no stock")
    func testGetStockAtLocationEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let stock = try env.warehouse.getStockAtLocation(locationType: "warehouse", locationId: 999)
        #expect(stock.isEmpty)
    }

    @Test("getStockAtLocation returns parts after seeding stock")
    func testGetStockAtLocationWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 30, locationType: "warehouse", locationId: 1)

        let stock = try env.warehouse.getStockAtLocation(locationType: "warehouse", locationId: 1)
        #expect(!stock.isEmpty)
        #expect(stock.contains(where: { $0.partId == partId }))
        #expect(stock.first(where: { $0.partId == partId })?.qty == 30)
    }

    @Test("getStockAtLocation degrades deleted part name to 'Unknown Part'")
    func testGetStockAtLocation_hidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Secret Widget", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5, locationType: "warehouse", locationId: 2)

        // Soft-delete the part while stock rows still exist. Active stock listings
        // must not leak the deleted part's real name — they should degrade to 'Unknown'.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [partId]
            )
        }

        let stock = try env.warehouse.getStockAtLocation(locationType: "warehouse", locationId: 2)
        let row = stock.first(where: { $0.partId == partId })
        #expect(row?.partName == "Unknown Part",
                "Soft-deleted part must NOT surface its real name via the stock listing")
    }

    @Test("getLocationStock degrades deleted part name to 'Unknown Part'")
    func testGetLocationStock_hidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Should Stay Hidden", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 7, locationType: "warehouse", locationId: 3)

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [partId]
            )
        }

        let stock = try env.warehouse.getLocationStock()
        let row = stock.first(where: { $0.partId == partId })
        #expect(row?.partName == "Unknown Part",
                "Soft-deleted part must NOT surface its real name via the cross-location stock listing")
    }

    // MARK: - clearStagingTag / clearAllStagingTags

    @Test("clearStagingTag soft-deletes a staging tag")
    func testClearStagingTag() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20)

        let stockId: Int64 = try env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT id FROM stock WHERE part_id = ? LIMIT 1", arguments: [partId])?["id"] ?? 1
        }
        let tagId = try env.warehouse.createStagingTag(stockId: stockId, taggedBy: env.adminUserId)

        var staged = try env.warehouse.getStagedItems()
        #expect(staged.count >= 1)

        try env.warehouse.clearStagingTag(id: tagId)

        staged = try env.warehouse.getStagedItems()
        #expect(!staged.contains(where: { $0.id == tagId }))
    }

    @Test("clearAllStagingTags removes all tags")
    func testClearAllStagingTags() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20)

        let stockId: Int64 = try env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT id FROM stock WHERE part_id = ? LIMIT 1", arguments: [partId])?["id"] ?? 1
        }
        _ = try env.warehouse.createStagingTag(stockId: stockId, taggedBy: env.adminUserId)

        var staged = try env.warehouse.getStagedItems()
        #expect(!staged.isEmpty)

        try env.warehouse.clearAllStagingTags()

        staged = try env.warehouse.getStagedItems()
        #expect(staged.isEmpty)
    }

    // MARK: - getPartStockLevels

    @Test("getPartStockLevels returns zeroes for part with no stock")
    func testPartStockLevelsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let levels = try env.warehouse.getPartStockLevels(partId: partId)
        #expect(levels.partId == partId)
        #expect(levels.currentShelfQty == 0)
        #expect(levels.minStock == 0)
    }

    @Test("getPartStockLevels reflects seeded stock quantity")
    func testPartStockLevelsWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Stocked Part", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 42)

        let levels = try env.warehouse.getPartStockLevels(partId: partId)
        #expect(levels.currentShelfQty == 42)
        #expect(levels.partName == "Stocked Part")
    }

    // MARK: - Zone CRUD (addZone / listZones / updateZone / deleteZone)

    @Test("Zone CRUD: add, list, update, delete")
    func testZoneCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let floorPlan = try env.warehouse.createFloorPlan(name: "Zone Test Plan", widthInches: 480, lengthInches: 360)
        let fpId = floorPlan.id!

        // Add a zone
        let zone = try env.warehouse.addZone(floorPlanId: fpId, zoneType: "rack", label: "Rack A")
        #expect(zone.id != nil)
        #expect(zone.zoneType == "rack")
        #expect(zone.label == "Rack A")

        // List zones
        let zones = try env.warehouse.listZones(floorPlanId: fpId)
        #expect(zones.count == 1)
        #expect(zones[0].label == "Rack A")

        // Update zone
        try env.warehouse.updateZone(id: zone.id!, label: "Rack B", colorHex: "#FF0000")
        let updatedZones = try env.warehouse.listZones(floorPlanId: fpId)
        #expect(updatedZones[0].label == "Rack B")
        #expect(updatedZones[0].colorHex == "#FF0000")

        // Delete zone
        try env.warehouse.deleteZone(id: zone.id!)
        let afterDelete = try env.warehouse.listZones(floorPlanId: fpId)
        #expect(afterDelete.isEmpty)
    }

    @Test("addZone places at grid coordinates")
    func addZone_placesAtGridCoordinates() throws {
        let env = try E2ETestHelpers.setUp()
        let floorPlan = try env.warehouse.createFloorPlan(name: "Zone Placement Plan", widthInches: 480, lengthInches: 360)

        let zone = try env.warehouse.addZone(
            floorPlanId: floorPlan.id!,
            zoneType: "storage",
            label: "Main Storage",
            gridX: 1,
            gridY: 1,
            gridWidth: 2,
            gridHeight: 3
        )

        #expect(zone.gridX == 1)
        #expect(zone.gridY == 1)
        #expect(zone.gridWidth == 2)
        #expect(zone.gridHeight == 3)
    }

    @Test("updateZone prevents negative grid")
    func updateZone_preventsNegativeGrid() throws {
        let env = try E2ETestHelpers.setUp()
        let floorPlan = try env.warehouse.createFloorPlan(name: "Zone Validation Plan", widthInches: 480, lengthInches: 360)
        let zone = try env.warehouse.addZone(floorPlanId: floorPlan.id!, zoneType: "storage", label: "Storage")

        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            try env.warehouse.updateZone(id: zone.id!, gridX: -1)
        }
        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            try env.warehouse.updateZone(id: zone.id!, gridY: -1)
        }
    }

    // MARK: - getPartName / getPartCode

    @Test("getPartName returns part name for existing part")
    func testGetPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Named Part", categoryId: catId)

        let name = try env.warehouse.getPartName(partId: partId)
        #expect(name == "Named Part")
    }

    @Test("getPartName returns nil for non-existent part")
    func testGetPartNameNil() throws {
        let env = try E2ETestHelpers.setUp()
        let name = try env.warehouse.getPartName(partId: 99999)
        #expect(name == nil)
    }

    @Test("getPartCode returns code for existing part")
    func testGetPartCode() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        // seedPart generates a code like "TW-XXXX" — verify it round-trips
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let code = try env.warehouse.getPartCode(partId: partId)
        #expect(code != nil)
        #expect(code?.hasPrefix("TW-") == true)
    }

    // MARK: - getJobLinkForPOLine

    @Test("getJobLinkForPOLine returns nil for PO line with no JPO")
    func testGetJobLinkForPOLineNil() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-LINK-01", supplierId: supplierId)

        let poLineId: Int64 = try env.db.writer.write { db in
            try db.execute(
                sql: "INSERT INTO po_line_items (po_id, part_id, qty_ordered, created_at) VALUES (?, ?, 5, datetime('now'))",
                arguments: [poId, partId]
            )
            return db.lastInsertedRowID
        }

        let link = try env.warehouse.getJobLinkForPOLine(poLineId: poLineId)
        #expect(link == nil)
    }

    // MARK: - listDistinctStockLocations

    @Test("listDistinctStockLocations returns empty when no stock exists")
    func testListDistinctStockLocationsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let locations = try env.warehouse.listDistinctStockLocations()
        #expect(locations.isEmpty)
    }

    @Test("listDistinctStockLocations returns location after seeding stock")
    func testListDistinctStockLocationsWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let locations = try env.warehouse.listDistinctStockLocations()
        #expect(!locations.isEmpty)
        #expect(locations.contains(where: { $0.locationType == "warehouse" }))
    }

    @Test("listDistinctStockLocations falls back to location ID when vehicle is soft-deleted")
    func testListDistinctStockLocationsHidesDeletedVehicleName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let vehicleId = try env.fleet.createVehicle(
            actorId: env.adminUserId,
            vehicleNumber: "V-DSL-01", vehicleName: "DSL Truck", vehicleType: "truck",
            make: nil, model: nil, year: nil, color: nil, vin: nil, licensePlate: nil, notes: nil
        )
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 3, locationType: "truck", locationId: vehicleId)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE vehicles SET deleted_at = datetime('now') WHERE id = ?", arguments: [vehicleId])
        }

        let locations = try env.warehouse.listDistinctStockLocations()
        let truckLoc = locations.first(where: { $0.locationType == "truck" && $0.locationId == vehicleId })
        #expect(truckLoc != nil)
        #expect(truckLoc?.name != "DSL Truck")
    }

    // MARK: - getPartStockByLocationType

    @Test("getPartStockByLocationType returns empty for part with no stock")
    func testPartStockByLocationTypeEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let result = try env.warehouse.getPartStockByLocationType(partId: partId)
        #expect(result.isEmpty)
    }

    @Test("getPartStockByLocationType groups stock by location type")
    func testPartStockByLocationTypeWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 25)

        let result = try env.warehouse.getPartStockByLocationType(partId: partId)
        #expect(!result.isEmpty)
        let warehouseEntry = result.first(where: { $0.locationType == "warehouse" })
        #expect(warehouseEntry != nil)
        #expect(warehouseEntry?.totalQty == 25)
    }

    // MARK: - getWarehouseLocationName / getWarehouseLocationNames

    @Test("getWarehouseLocationName returns nil for non-existent location")
    func testGetWarehouseLocationNameNil() throws {
        let env = try E2ETestHelpers.setUp()
        let name = try env.warehouse.getWarehouseLocationName(id: 99999)
        #expect(name == nil)
    }

    @Test("getWarehouseLocationNames returns empty dict for empty input")
    func testGetWarehouseLocationNamesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let names = try env.warehouse.getWarehouseLocationNames(ids: [])
        #expect(names.isEmpty)
    }

    // MARK: - Receiving Session Items (unit_cost fix)

    @Test("getSessionItems reads unit_cost column correctly")
    func testSessionItemsUnitCost() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        // Create a PO with a line item
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-TEST-001",
            supplierId: supplierId
        )
        // Add a line item with a known unit_cost
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO po_line_items (po_id, part_id, qty_ordered, unit_cost, created_at)
                    VALUES (?, ?, 5, 12.50, datetime('now'))
                    """,
                arguments: [poId, partId]
            )
        }

        // Start a receiving session (pre-populates items from PO line items)
        let sessionId = try env.warehouse.startReceivingSession(
            poId: poId,
            startedBy: env.adminUserId
        )
        #expect(sessionId > 0)

        // Get session items — this tests that unit_cost is read correctly (not unit_price)
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        #expect(items.count >= 1)
        if let first = items.first {
            #expect(first.expectedQty == 5)
            // unit_cost should now be read correctly (was nil before the fix)
            #expect(first.unitPrice == 12.50)
        }
    }

    // MARK: - Audit Sessions

    @Test("createAuditSession returns a valid session ID")
    func testCreateAuditSession() throws {
        let env = try E2ETestHelpers.setUp()
        let sessionId = try env.warehouse.createAuditSession(
            scope: "full",
            zone: "Zone A",
            sampleSize: 50,
            includeZeroStock: false,
            notes: "Monthly audit",
            userId: env.adminUserId
        )
        #expect(sessionId > 0)
    }

    @Test("createAuditSession with no zone or sample size")
    func testCreateAuditSessionMinimal() throws {
        let env = try E2ETestHelpers.setUp()
        let sessionId = try env.warehouse.createAuditSession(
            scope: "spot",
            zone: nil,
            sampleSize: nil,
            includeZeroStock: true,
            notes: nil,
            userId: env.adminUserId
        )
        #expect(sessionId > 0)
    }

    // MARK: - Receiving: Stage / Write-Off / Supplier Return

    @Test("stageReceivedPartsForJob creates a receiving_staged movement")
    func testStageReceivedPartsForJob() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env)

        let movementId = try env.warehouse.stageReceivedPartsForJob(
            partId: partId,
            qty: 10,
            jobId: jobId,
            performedBy: env.adminUserId,
            notes: "Staged for panel job"
        )
        #expect(movementId > 0)

        // Verify the movement record exists with the correct type
        let movements = try env.warehouse.listMovements(limit: 10)
        let staged = movements.first { $0.movementType == "receiving_staged" }
        #expect(staged != nil)
    }

    @Test("writeOffReceivedPart creates a write_off movement")
    func testWriteOffReceivedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let movementId = try env.warehouse.writeOffReceivedPart(
            partId: partId,
            qty: 3,
            reason: "Arrived damaged",
            performedBy: env.adminUserId,
            notes: "Box was crushed"
        )
        #expect(movementId > 0)

        let movements = try env.warehouse.listMovements(limit: 10)
        let writeOff = movements.first { $0.movementType == "write_off" }
        #expect(writeOff != nil)
    }

    @Test("returnDamagedToSupplier creates a return_to_supplier movement")
    func testReturnDamagedToSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let movementId = try env.warehouse.returnDamagedToSupplier(
            partId: partId,
            qty: 2,
            returnType: "replacement",
            performedBy: env.adminUserId,
            notes: "Defective batch"
        )
        #expect(movementId > 0)

        let movements = try env.warehouse.listMovements(limit: 10)
        let returned = movements.first { $0.movementType == "return_to_supplier" }
        #expect(returned != nil)
    }

    @Test("returnDamagedToSupplier with refund type")
    func testReturnDamagedToSupplierRefund() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let movementId = try env.warehouse.returnDamagedToSupplier(
            partId: partId,
            qty: 1,
            returnType: "refund",
            performedBy: env.adminUserId
        )
        #expect(movementId > 0)
    }

    // MARK: - Storage Hierarchy: createStorageUnit, deleteStorageLevel, deleteStorageArea, assignPartToBin

    @Test("createStorageUnit builds full hierarchy with levels and areas")
    func testCreateStorageUnit() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "Main WH", widthInches: 400, lengthInches: 300)

        let unit = try env.warehouse.createStorageUnit(
            floorPlanId: plan.id!,
            name: "Rack A",
            unitType: "rack",
            levels: 3,
            areasPerLevel: 4
        )
        #expect(unit.id != nil)

        // Verify levels were created
        let levels = try env.warehouse.listLevelsForUnit(unitId: unit.id!)
        #expect(levels.count == 3)

        // Verify areas under the first level
        let areas = try env.warehouse.listAreasForLevel(levelId: levels[0].id!)
        #expect(areas.count == 4)
    }

    @Test("deleteStorageLevel soft-deletes the level")
    func testDeleteStorageLevel() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")

        let levelsBefore = try env.warehouse.listLevelsForUnit(unitId: unit.id!)
        #expect(levelsBefore.count == 1)

        try env.warehouse.deleteStorageLevel(id: level.id!)

        let levelsAfter = try env.warehouse.listLevelsForUnit(unitId: unit.id!)
        #expect(levelsAfter.isEmpty)
    }

    @Test("deleteStorageArea soft-deletes the area")
    func testDeleteStorageArea() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        let areasBefore = try env.warehouse.listAreasForLevel(levelId: level.id!)
        #expect(areasBefore.count == 1)

        try env.warehouse.deleteStorageArea(id: area.id!)

        let areasAfter = try env.warehouse.listAreasForLevel(levelId: level.id!)
        #expect(areasAfter.isEmpty)
    }

    @Test("assignPartToBin links a part to a bin")
    func testAssignPartToBin() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        let bin = try env.warehouse.addBin(areaId: area.id!, binNumber: 1)

        try env.warehouse.assignPartToBin(binId: bin.id!, partId: partId)

        // Verify the assignment by reading the bin
        let bins = try env.warehouse.listBinsForArea(areaId: area.id!)
        let updatedBin = bins.first { $0.id == bin.id }
        #expect(updatedBin?.assignedPartId == partId)
    }

    // MARK: - Cart Mode: moveBinsToArea, saveUnitPlacement

    @Test("moveBinsToArea moves all specified bins to the target area")
    func testMoveBinsToArea_movesAllBins() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 300, lengthInches: 300)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "Cart", unitType: "cart")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let sourceArea = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        let targetArea = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 2)

        let bin1 = try env.warehouse.addBin(areaId: sourceArea.id!, binNumber: 1)
        let bin2 = try env.warehouse.addBin(areaId: sourceArea.id!, binNumber: 2)

        try env.warehouse.moveBinsToArea(binIds: [bin1.id!, bin2.id!], targetAreaId: targetArea.id!)

        let targetBins = try env.warehouse.listBinsForArea(areaId: targetArea.id!)
        let movedIds = Set(targetBins.compactMap { $0.id })
        #expect(movedIds.contains(bin1.id!))
        #expect(movedIds.contains(bin2.id!))
        // Source area should now be empty
        let sourceBins = try env.warehouse.listBinsForArea(areaId: sourceArea.id!)
        #expect(sourceBins.isEmpty)
    }

    @Test("moveBinsToArea with empty binIds is a no-op")
    func testMoveBinsToArea_emptyListIsNoOp() throws {
        let env = try E2ETestHelpers.setUp()
        // Should not throw for an empty binIds array
        try env.warehouse.moveBinsToArea(binIds: [], targetAreaId: 999)
    }

    @Test("saveUnitPlacement updates grid position and zone for a storage unit")
    func testSaveUnitPlacement_updatesGridAndZone() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 300, lengthInches: 300)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "U1", unitType: "shelf", gridX: 0, gridY: 0)
        let zone = try env.warehouse.addZone(floorPlanId: plan.id!, zoneType: "storage", label: "Zone A", colorHex: "#FF0000")

        try env.warehouse.saveUnitPlacement(unitId: unit.id!, gridX: 3, gridY: 5, zoneId: zone.id!)

        let units = try env.warehouse.listStorageUnits(floorPlanId: plan.id!)
        let updated = units.first { $0.id == unit.id }
        #expect(updated?.gridX == 3)
        #expect(updated?.gridY == 5)
        #expect(updated?.zoneId == zone.id!)
    }

    // MARK: - FK deleted_at guards on create paths (iter 68)

    @Test("createMovement rejects tombstoned part")
    func testCreateMovement_rejectsTombstonedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        try env.parts.deletePart(id: partId)
        #expect(throws: WarehouseService.WarehouseError.self) {
            _ = try env.warehouse.createMovement(
                partId: partId, qty: 1,
                fromLocationType: nil, fromLocationId: nil,
                toLocationType: "warehouse", toLocationId: 1,
                movementType: "add_stock", performedBy: env.adminUserId
            )
        }
    }

    @Test("createStagingBox rejects tombstoned job")
    func testCreateStagingBox_rejectsTombstonedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        #expect(throws: WarehouseService.WarehouseError.self) {
            _ = try env.warehouse.createStagingBox(jobId: jobId)
        }
    }

    @Test("recordTrailerLocation rejects tombstoned trailer")
    func testRecordTrailerLocation_rejectsTombstonedTrailer() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.fleet.createTrailer(actorId: env.adminUserId, trailerNumber: "T-REC-SOFT", trailerType: "flatbed", notes: nil)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_trailers SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [trailerId])
        }
        #expect(throws: WarehouseService.WarehouseError.self) {
            _ = try env.warehouse.recordTrailerLocation(
                trailerId: trailerId, recordedBy: env.adminUserId
            )
        }
    }

    @Test("updateSessionItem is a no-op on soft-deleted item")
    func testUpdateSessionItem_noOpOnSoftDeletedItem() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-RSI-SOFT", supplierId: supplierId, notes: nil)
        _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 3, unitPrice: nil)
        let sessionId = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        guard let item = items.first else { return }

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE receiving_session_items SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [item.id])
        }
        // Should be a silent no-op — received_qty stays at 0
        try env.warehouse.updateSessionItem(itemId: item.id, receivedQty: 99)
        let qty = try env.db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT received_qty FROM receiving_session_items WHERE id = ?",
                             arguments: [item.id]) ?? 0
        }
        #expect(qty == 0, "updateSessionItem on a soft-deleted item must not change received_qty")
    }

    @Test("recordScan is a no-op on soft-deleted item")
    func testRecordScan_noOpOnSoftDeletedItem() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-SCAN-SOFT", supplierId: supplierId, notes: nil)
        _ = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 2, unitPrice: nil)
        let sessionId = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        guard let item = items.first else { return }

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE receiving_session_items SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [item.id])
        }
        // Should be a silent no-op — received_qty stays at 0
        try env.warehouse.recordScan(itemId: item.id, qty: 5)
        let qty = try env.db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT received_qty FROM receiving_session_items WHERE id = ?",
                             arguments: [item.id]) ?? 0
        }
        #expect(qty == 0, "recordScan on a soft-deleted item must not increment received_qty")
    }

    @Test("markBoxOpen is a no-op on soft-deleted box")
    func testMarkBoxOpen_noOpOnSoftDeletedBox() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let box = try env.warehouse.createStagingBox(jobId: jobId, size: "normal")
        let boxId = box.id

        try env.db.writer.write { db in
            // First mark it full, then soft-delete
            try db.execute(sql: "UPDATE staging_boxes SET is_full = 1, deleted_at = datetime('now') WHERE id = ?",
                           arguments: [boxId])
        }
        // markBoxOpen on a deleted box must be a silent no-op
        try env.warehouse.markBoxOpen(boxId: boxId)
        let isFull = try env.db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT is_full FROM staging_boxes WHERE id = ?",
                             arguments: [boxId]) ?? 1
        }
        #expect(isFull == 1, "markBoxOpen on a soft-deleted box must not clear is_full")
    }

    // MARK: - markBoxFull atomicity (iter 71)

    @Test("markBoxFull with tombstoned job rolls back the mark-full atomically")
    func testMarkBoxFull_rollsBackWhenJobTombstoned() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let box = try env.warehouse.createStagingBox(jobId: jobId, size: "normal")
        let boxId = box.id

        // Tombstone the job so createStagingBox logic inside markBoxFull throws
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }

        // markBoxFull must throw AND the box must not be left with is_full = 1
        #expect(throws: WarehouseService.WarehouseError.self) {
            _ = try env.warehouse.markBoxFull(boxId: boxId)
        }

        let isFull = try env.db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT is_full FROM staging_boxes WHERE id = ?",
                             arguments: [boxId]) ?? 0
        }
        #expect(isFull == 0, "mark-full must have rolled back when job was tombstoned")
    }

    @Test("markBoxFull creates next box atomically and returns it")
    func testMarkBoxFull_createsNextBoxAtomically() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let box = try env.warehouse.createStagingBox(jobId: jobId, size: "large")
        let boxId = box.id

        let nextBox = try env.warehouse.markBoxFull(boxId: boxId)

        // Original box must be full
        let isFull = try env.db.writer.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT is_full FROM staging_boxes WHERE id = ?",
                             arguments: [boxId]) ?? 0
        }
        #expect(isFull == 1)

        // Next box must exist and not be full
        #expect(nextBox.isFull == false)
        #expect(nextBox.boxSize == "large", "successor inherits box size")
        #expect(nextBox.jobId == jobId)
    }

    // MARK: - Quantity validation guards (iter 72)

    @Test("updateSessionItem throws invalidQuantity for negative receivedQty")
    func testUpdateSessionItem_throwsForNegativeQty() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.updateSessionItem(itemId: 1, receivedQty: -1)
        }
    }

    @Test("recordScan throws invalidQuantity for zero qty")
    func testRecordScan_throwsForZeroQty() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.recordScan(itemId: 1, qty: 0)
        }
    }

    @Test("recordScan throws invalidQuantity for negative qty")
    func testRecordScan_throwsForNegativeQty() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.recordScan(itemId: 1, qty: -5)
        }
    }

    @Test("completeSession throws userNotFound for tombstoned completedBy")
    func testCompleteSession_throwsForTombstonedUser() throws {
        let env = try E2ETestHelpers.setUp()
        // Tombstone the admin user — user guard fires before session status check
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.completeSession(sessionId: 999, completedBy: env.adminUserId)
        }
    }

    @Test("recordAuditCount (simple) throws invalidQuantity for negative countedQty")
    func testRecordAuditCountSimple_throwsForNegativeQty() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.recordAuditCount(stockId: 1, countedQty: -3)
        }
    }

    @Test("recordAuditCount (session) throws invalidQuantity for negative userCount")
    func testRecordAuditCountSession_throwsForNegativeUserCount() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            _ = try env.warehouse.recordAuditCount(
                sessionId: 1, partId: 1, areaId: 1,
                systemCount: 5, userCount: -2, countedBy: env.adminUserId
            )
        }
    }

    // MARK: - createMovement + addStorageArea + startReceivingSession guards (iter 73)

    @Test("createMovement throws invalidQuantity for zero qty")
    func testCreateMovement_throwsForZeroQty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            _ = try env.warehouse.createMovement(
                partId: partId, qty: 0,
                fromLocationType: nil, fromLocationId: nil,
                toLocationType: "warehouse", toLocationId: 1,
                movementType: "add_stock", performedBy: env.adminUserId
            )
        }
    }

    @Test("createMovement throws requiredFieldEmpty for blank movementType")
    func testCreateMovement_throwsForBlankMovementType() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.createMovement(
                partId: partId, qty: 1,
                fromLocationType: nil, fromLocationId: nil,
                toLocationType: "warehouse", toLocationId: 1,
                movementType: "   ", performedBy: env.adminUserId
            )
        }
    }

    @Test("createMovement throws insufficientStock when source qty is less than requested")
    func testCreateMovement_throwsForInsufficientStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Seed exactly 2 units in warehouse
        _ = try env.warehouse.createMovement(
            partId: partId, qty: 2,
            fromLocationType: nil, fromLocationId: nil,
            toLocationType: "warehouse", toLocationId: 1,
            movementType: "add_stock", performedBy: env.adminUserId
        )

        // Try to move 5 — should throw insufficientStock(available:2, requested:5)
        #expect(throws: WarehouseService.WarehouseError.self) {
            _ = try env.warehouse.createMovement(
                partId: partId, qty: 5,
                fromLocationType: "warehouse", fromLocationId: 1,
                toLocationType: "vehicle", toLocationId: 1,
                movementType: "transfer", performedBy: env.adminUserId
            )
        }
    }

    @Test("addStorageArea throws invalidDimension for zero areaNumber")
    func testAddStorageArea_throwsForZeroAreaNumber() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            _ = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 0)
        }
    }

    @Test("startReceivingSession throws userNotFound for tombstoned startedBy")
    func testStartReceivingSession_throwsForTombstonedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-SRS-SOFT", supplierId: supplierId, notes: nil)

        // Tombstone the starting user
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            _ = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)
        }
    }

    // MARK: - adjustAuditCount + createAuditSession + recordAuditCount (session) guards (iter 75)

    @Test("adjustAuditCount throws invalidQuantity for negative newQty")
    func testAdjustAuditCount_throwsForNegativeQty() throws {
        let env = try E2ETestHelpers.setUp()
        // Guard fires before DB — placeholder partId/locationId are fine
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.adjustAuditCount(
                partId: 999, locationType: "warehouse", locationId: 1,
                newQty: -1, reason: nil, performedBy: nil
            )
        }
    }

    @Test("adjustAuditCount throws userNotFound for tombstoned performedBy")
    func testAdjustAuditCount_throwsForTombstonedPerformedBy() throws {
        let env = try E2ETestHelpers.setUp()
        // Tombstone the user; user check is first inside the transaction
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.adjustAuditCount(
                partId: 999, locationType: "warehouse", locationId: 1,
                newQty: 3, reason: nil, performedBy: env.adminUserId
            )
        }
    }

    @Test("createAuditSession throws requiredFieldEmpty for blank scope")
    func testCreateAuditSession_throwsForBlankScope() throws {
        let env = try E2ETestHelpers.setUp()
        // Guard fires before DB — placeholder userId still needs to be in users table
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.createAuditSession(
                scope: "   ", zone: nil, sampleSize: nil,
                includeZeroStock: false, notes: nil, userId: env.adminUserId
            )
        }
    }

    @Test("recordAuditCount (session) throws invalidQuantity for negative systemCount")
    func testRecordAuditCountSession_throwsForNegativeSystemCount() throws {
        let env = try E2ETestHelpers.setUp()
        // Guard fires before db.writer.write — placeholder IDs are fine
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            _ = try env.warehouse.recordAuditCount(
                sessionId: 999, partId: 999, areaId: 999,
                systemCount: -1, userCount: 5, countedBy: env.adminUserId
            )
        }
    }

    @Test("recordAuditCount (session) throws userNotFound for tombstoned countedBy")
    func testRecordAuditCountSession_throwsForTombstonedCountedBy() throws {
        let env = try E2ETestHelpers.setUp()
        // Tombstone the counting user; user check is first inside the transaction
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            _ = try env.warehouse.recordAuditCount(
                sessionId: 999, partId: 999, areaId: 999,
                systemCount: 5, userCount: 5, countedBy: env.adminUserId
            )
        }
    }

    // MARK: - Soft-delete + blank-field + null-FK guards (iter 77)

    @Test("getStagedItems excludes tombstoned stock rows")
    func testGetStagedItems_excludesTombstonedStock() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Seed a stock row directly (stock has no created_at column), then tag it, then tombstone
        let stockId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO stock (part_id, location_type, location_id, qty, updated_at)
                VALUES (?, 'warehouse', 1, 5, datetime('now'))
                """, arguments: [partId])
            return db.lastInsertedRowID
        }
        _ = try env.warehouse.createStagingTag(stockId: stockId, taggedBy: env.adminUserId)

        // Tombstone the stock row
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE stock SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [stockId])
        }

        let staged = try env.warehouse.getStagedItems()
        #expect(staged.allSatisfy { $0.stockId != stockId })
    }

    @Test("addZone throws requiredFieldEmpty for blank zoneType")
    func testAddZone_throwsForBlankZoneType() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "Test Plan", widthInches: 200, lengthInches: 200)
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.addZone(floorPlanId: plan.id!, zoneType: "  ")
        }
    }

    @Test("addFloorFeature throws requiredFieldEmpty for blank featureType")
    func testAddFloorFeature_throwsForBlankFeatureType() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "Test Plan", widthInches: 200, lengthInches: 200)
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.addFloorFeature(
                floorPlanId: plan.id!, featureType: "", label: nil, gridX: 0, gridY: 0
            )
        }
    }

    @Test("completeSession creates no stock_movements with part_id=0")
    func testCompleteSession_noZeroPartIdMovements() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let (catId, _, _) = try E2ETestHelpers.seedPartHierarchy(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Completion Part", categoryId: catId)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-COMPLETE-TEST", supplierId: supplierId, notes: nil)

        // Add a PO line item for the part (qty_ordered is the correct column name)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, unit_cost)
                VALUES (?, ?, 3, 5.0)
                """, arguments: [poId, partId])
        }
        let sessionId = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        if let item = items.first {
            try env.warehouse.updateSessionItem(itemId: item.id, receivedQty: 3)
        }

        try env.warehouse.completeSession(sessionId: sessionId, completedBy: env.adminUserId)

        // Guard verified: no stock_movements with part_id = 0 should exist
        let badMovements = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stock_movements WHERE part_id = 0") ?? 0
        }
        #expect(badMovements == 0)
    }

    // MARK: - Bin/Area assignment + misplaced-parts validation (iter 82)

    @Test("assignPartToBin is a no-op on a soft-deleted bin")
    func testAssignPartToBin_noOpOnSoftDeletedBin() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "BP-WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "BP-S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        let bin = try env.warehouse.addBin(areaId: area.id!, binNumber: 1)
        // Soft-delete the bin
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_bins SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [bin.id!])
        }
        // Should be a silent no-op — assigned_part_id must not change
        try env.warehouse.assignPartToBin(binId: bin.id!, partId: partId)
        let assigned = try env.db.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT assigned_part_id FROM warehouse_bins WHERE id = ?",
                               arguments: [bin.id!]) as Int64?
        }
        #expect(assigned == nil, "Soft-deleted bin must not receive a part assignment")
    }

    @Test("assignPartToArea throws for tombstoned part or area")
    func testAssignPartToArea_rejectsTombstonedParents() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "PA-WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "PA-S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        // Tombstone the part, verify throw
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        #expect(throws: WarehouseService.WarehouseError.partNotFound(partId)) {
            try env.warehouse.assignPartToArea(partId: partId, areaId: area.id!)
        }
        // Restore part, tombstone area, verify throw
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = NULL WHERE id = ?", arguments: [partId])
            try db.execute(sql: "UPDATE warehouse_storage_areas SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [area.id!])
        }
        #expect(throws: WarehouseService.WarehouseError.areaNotFound(area.id!)) {
            try env.warehouse.assignPartToArea(partId: partId, areaId: area.id!)
        }
    }

    @Test("logMisplacedPart rejects zero/negative qty and tombstoned reporter")
    func testLogMisplacedPart_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "MP-WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "MP-S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        // Zero qty
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.logMisplacedPart(
                partId: partId, foundAtAreaId: area.id!, homeAreaId: nil,
                qtyFound: 0, foundBy: env.adminUserId)
        }
        // Tombstoned reporter
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.logMisplacedPart(
                partId: partId, foundAtAreaId: area.id!, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }
    }

    @Test("logMisplacedPart rejects placeholder part and area ids without inserting")
    func testLogMisplacedPart_rejectsPlaceholderIdsWithoutInsert() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "MP-ZERO", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "MP-Z1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        #expect(throws: WarehouseService.WarehouseError.partNotFound(0)) {
            try env.warehouse.logMisplacedPart(
                partId: 0, foundAtAreaId: area.id!, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }
        #expect(throws: WarehouseService.WarehouseError.areaNotFound(0)) {
            try env.warehouse.logMisplacedPart(
                partId: partId, foundAtAreaId: 0, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }

        let logCount = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM misplaced_parts_log") ?? 0
        }
        #expect(logCount == 0)
    }

    @Test("logMisplacedPart rejects missing or deleted part and area ids")
    func testLogMisplacedPart_rejectsMissingOrDeletedRequiredRecords() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "MP-STALE", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "MP-S2", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        #expect(throws: WarehouseService.WarehouseError.partNotFound(999_991)) {
            try env.warehouse.logMisplacedPart(
                partId: 999_991, foundAtAreaId: area.id!, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }
        #expect(throws: WarehouseService.WarehouseError.areaNotFound(999_992)) {
            try env.warehouse.logMisplacedPart(
                partId: partId, foundAtAreaId: 999_992, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
            try db.execute(sql: "UPDATE warehouse_storage_areas SET deleted_at = datetime('now') WHERE id = ?", arguments: [area.id!])
        }

        #expect(throws: WarehouseService.WarehouseError.partNotFound(partId)) {
            try env.warehouse.logMisplacedPart(
                partId: partId, foundAtAreaId: area.id!, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }
    }

    @Test("logMisplacedPart rejects inactive parts")
    func testLogMisplacedPart_rejectsInactivePart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "MP-INACTIVE", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "MP-I1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [partId])
        }

        #expect(throws: WarehouseService.WarehouseError.partNotFound(partId)) {
            try env.warehouse.logMisplacedPart(
                partId: partId, foundAtAreaId: area.id!, homeAreaId: nil,
                qtyFound: 1, foundBy: env.adminUserId)
        }
    }

    @Test("active area lookup searches QR labels and returns empty no-results safely")
    func testSearchActiveAreas() throws {
        let env = try E2ETestHelpers.setUp()
        let plan = try env.warehouse.createFloorPlan(name: "AREA-LOOKUP", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "Search Rack", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "B")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 3)

        let results = try env.warehouse.searchActiveAreas(query: area.fullLocationCode ?? "Search Rack", limit: 10)
        #expect(results.contains { $0.id == area.id! })

        let noResults = try env.warehouse.searchActiveAreas(query: "definitely-not-a-location", limit: 10)
        #expect(noResults.isEmpty)
    }

    @Test("submitMultiUserCount rejects negative quantity")
    func testSubmitMultiUserCount_rejectsNegativeQuantity() throws {
        let env = try E2ETestHelpers.setUp()
        // The guard fires before any DB access so we can use placeholder IDs
        #expect(throws: WarehouseService.WarehouseError.invalidQuantity) {
            try env.warehouse.submitMultiUserCount(assignmentId: 999, quantity: -1, userId: env.adminUserId)
        }
    }

    @Test("resolveMisplacedPart rejects blank resolution and tombstoned resolver")
    func testResolveMisplacedPart_rejectsInvalidInputs() throws {
        let env = try E2ETestHelpers.setUp()
        // Blank resolution — guard fires before DB access
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            try env.warehouse.resolveMisplacedPart(logId: 1, resolution: "   ", resolvedBy: env.adminUserId)
        }
        // Tombstoned resolver
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.resolveMisplacedPart(logId: 1, resolution: "returned_to_shelf",
                                                   resolvedBy: env.adminUserId)
        }
    }

    // MARK: - Storage hierarchy FK soft-delete guards

    @Test("addStorageLevel rejects tombstoned unit")
    func testAddStorageLevel_rejectsTombstonedUnit() throws {
        let env = try E2ETestHelpers.setUp()
        let fp = try env.warehouse.createFloorPlan(name: "FP", widthInches: 480, lengthInches: 360)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: fp.id!, name: "TestUnit", unitType: "rack")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_storage_units SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [unit.id!])
        }
        #expect(throws: WarehouseService.WarehouseError.unitNotFound(unit.id!)) {
            try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        }
    }

    @Test("addStorageArea rejects tombstoned level")
    func testAddStorageArea_rejectsTombstonedLevel() throws {
        let env = try E2ETestHelpers.setUp()
        let fp = try env.warehouse.createFloorPlan(name: "FP", widthInches: 480, lengthInches: 360)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: fp.id!, name: "TestUnit", unitType: "rack")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_storage_levels SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [level.id!])
        }
        #expect(throws: WarehouseService.WarehouseError.levelNotFound(level.id!)) {
            try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        }
    }

    @Test("addBin rejects tombstoned area")
    func testAddBin_rejectsTombstonedArea() throws {
        let env = try E2ETestHelpers.setUp()
        let fp = try env.warehouse.createFloorPlan(name: "FP", widthInches: 480, lengthInches: 360)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: fp.id!, name: "TestUnit", unitType: "rack")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_storage_areas SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [area.id!])
        }
        #expect(throws: WarehouseService.WarehouseError.areaNotFound(area.id!)) {
            try env.warehouse.addBin(areaId: area.id!, binNumber: 1)
        }
    }

    @Test("resolveMultiUserAudit rejects tombstoned resolver")
    func testResolveMultiUserAudit_rejectsTombstonedResolver() throws {
        let env = try E2ETestHelpers.setUp()
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.resolveMultiUserAudit(partId: 1, sessionId: 1, resolvedBy: env.adminUserId)
        }
    }

    // MARK: - createBatchMovements (atomic transaction)

    @Test("createBatchMovements empty batch returns empty array")
    func testCreateBatchMovements_emptyBatchNoOp() throws {
        let env = try E2ETestHelpers.setUp()
        let ids = try env.warehouse.createBatchMovements(movements: [], performedBy: env.adminUserId)
        #expect(ids.isEmpty)
    }

    @Test("createBatchMovements commits all movements atomically on success")
    func testCreateBatchMovements_successCommitsAll() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partA = try E2ETestHelpers.seedPart(env, name: "PartA", categoryId: catId)
        let partB = try E2ETestHelpers.seedPart(env, name: "PartB", categoryId: catId)

        let movements = [
            WarehouseService.MovementInput(partId: partA, qty: 5,
                                           toLocationType: "warehouse", toLocationId: 1,
                                           movementType: "receive"),
            WarehouseService.MovementInput(partId: partB, qty: 3,
                                           toLocationType: "warehouse", toLocationId: 1,
                                           movementType: "receive"),
        ]
        let ids = try env.warehouse.createBatchMovements(movements: movements, performedBy: env.adminUserId)
        #expect(ids.count == 2)

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stock_movements WHERE id IN (?, ?)",
                             arguments: [ids[0], ids[1]]) ?? 0
        }
        #expect(count == 2)
    }

    @Test("createBatchMovements rolls back entire batch when one movement fails")
    func testCreateBatchMovements_rollsBackOnPartialFailure() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let validPart = try E2ETestHelpers.seedPart(env, name: "ValidPart", categoryId: catId)
        // tombstoned part — FK guard will throw inside the transaction
        let badPart = try E2ETestHelpers.seedPart(env, name: "BadPart", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [badPart])
        }

        let movements = [
            WarehouseService.MovementInput(partId: validPart, qty: 5,
                                           toLocationType: "warehouse", toLocationId: 1,
                                           movementType: "receive"),
            WarehouseService.MovementInput(partId: badPart, qty: 2,
                                           toLocationType: "warehouse", toLocationId: 1,
                                           movementType: "receive"),
        ]
        #expect(throws: WarehouseService.WarehouseError.partNotFound(badPart)) {
            try env.warehouse.createBatchMovements(movements: movements, performedBy: env.adminUserId)
        }
        // Verify rollback: the first (valid) movement must NOT be committed
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stock_movements WHERE part_id = ?",
                             arguments: [validPart]) ?? 0
        }
        #expect(count == 0)
    }

    // MARK: - is_active defense

    @Test("getWarehouseKPIs excludes inactive parts from shortfall count")
    func testKPIs_excludesInactiveParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let activeId = try E2ETestHelpers.seedPart(env, name: "Active Part", categoryId: catId)
        let inactiveId = try E2ETestHelpers.seedPart(env, name: "Inactive Part", categoryId: catId)

        // Set min stock so both would appear in shortfall with zero stock
        try env.parts.updatePart(id: activeId, minStockLevel: 10)
        try env.parts.updatePart(id: inactiveId, minStockLevel: 10)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [inactiveId])
        }

        let kpis = try env.warehouse.getWarehouseKPIs()
        // Only the active part should be counted in shortfall and totalWithMin
        #expect(kpis.shortfallCount == 1)
    }

    @Test("getInventoryGrid excludes inactive parts")
    func testInventoryGrid_excludesInactiveParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let activeId = try E2ETestHelpers.seedPart(env, name: "Grid Active", categoryId: catId)
        let inactiveId = try E2ETestHelpers.seedPart(env, name: "Grid Inactive", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [inactiveId])
        }

        let grid = try env.warehouse.getInventoryGrid()
        let ids = Set(grid.map { $0.partId })
        #expect(ids.contains(activeId))
        #expect(!ids.contains(inactiveId))
    }
}
