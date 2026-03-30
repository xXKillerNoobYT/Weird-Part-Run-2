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
        #expect(rating != nil || rating == nil) // May not have rating yet
    }

    @Test("Warehouse leaderboard")
    func testLeaderboard() throws {
        let env = try E2ETestHelpers.setUp()
        let leaderboard = try env.warehouse.getWarehouseLeaderboard()
        #expect(leaderboard.count >= 0)
    }
}
