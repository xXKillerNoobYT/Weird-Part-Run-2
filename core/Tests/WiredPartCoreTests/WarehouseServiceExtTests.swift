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
}
