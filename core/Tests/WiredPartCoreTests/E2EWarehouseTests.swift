import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// End-to-end tests for warehouse operations.
///
/// Covers: stock movements → inventory tracking → staging → receiving → returns → audit.
@Suite("E2E: Warehouse & Movements")
struct E2EWarehouseTests {

    // MARK: - Stock Movements

    @Test("Receive stock into warehouse increases quantity")
    func testReceiveStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Receive 50 units
        let movementId = try env.warehouse.createMovement(
            partId: partId,
            qty: 50,
            fromLocationType: nil,
            fromLocationId: nil,
            toLocationType: "warehouse",
            toLocationId: 1,
            movementType: "receive",
            reason: "Purchase order delivery",
            performedBy: env.adminUserId
        )
        #expect(movementId > 0)

        // Verify stock
        let qty = try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1)
        #expect(qty == 50)
    }

    @Test("Move stock between locations updates both")
    func testMoveStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Receive 100 into warehouse
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 100)

        // Move 30 to truck (locationId=2 as a truck)
        _ = try env.warehouse.executeMovement(
            partId: partId,
            qty: 30,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            toLocationType: "truck",
            toLocationId: 2,
            reason: "Load truck",
            performedBy: env.adminUserId
        )

        // Verify warehouse reduced
        let warehouseQty = try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1)
        #expect(warehouseQty == 70)

        // Verify truck increased
        let truckQty = try env.warehouse.getStockQty(partId: partId, locationType: "truck", locationId: 2)
        #expect(truckQty == 30)
    }

    @Test("Movement validation rejects invalid moves")
    func testMovementValidation() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Receive 10 units
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        // Try to move 50 (more than available)
        let validation = try env.warehouse.validateMovement(
            partId: partId,
            qty: 50,
            fromLocationType: "warehouse",
            fromLocationId: 1,
            toLocationType: "truck",
            toLocationId: 2
        )
        #expect(!validation.isValid)
    }

    // MARK: - Movement History

    @Test("Movement history tracks all operations")
    func testMovementHistory() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 100)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 50)

        let movements = try env.warehouse.listMovements()
        #expect(movements.count >= 2)
    }

    // MARK: - Inventory Grid

    @Test("Inventory grid shows stocked items")
    func testInventoryGrid() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 25)

        let grid = try env.warehouse.getInventoryGrid()
        #expect(!grid.isEmpty)
    }

    // MARK: - Location Stock

    @Test("Location stock query returns items at location")
    func testLocationStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 40)

        let stock = try env.warehouse.getStockAtLocation(locationType: "warehouse", locationId: 1)
        #expect(!stock.isEmpty)
    }

    // MARK: - KPIs & Dashboard

    @Test("Warehouse KPIs reflect stock state")
    func testWarehouseKPIs() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 100)

        let kpis = try env.warehouse.getWarehouseKPIs()
        #expect(kpis.totalStock > 0)
    }

    @Test("Dashboard KPIs return valid data")
    func testDashboardKPIs() throws {
        let env = try E2ETestHelpers.setUp()
        let kpis = try env.warehouse.getDashboardKPIs()
        // Just verify it doesn't throw and returns structured data
        #expect(kpis.kpis.totalStock >= 0)
    }

    // MARK: - Staging

    @Test("Staging tag lifecycle: create and clear")
    func testStagingLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20)

        // Get a stock ID to tag
        let stockRows = try env.parts.getPartStock(partId: partId)
        guard let stockRow = stockRows.first else {
            Issue.record("No stock rows found")
            return
        }
        let stockId = stockRow["id"] as Int64

        let tagId = try env.warehouse.createStagingTag(
            stockId: stockId,
            destinationType: "truck",
            destinationId: 5,
            destinationLabel: "Truck 5",
            taggedBy: env.adminUserId
        )
        #expect(tagId > 0)

        let staged = try env.warehouse.getStagedItems()
        #expect(!staged.isEmpty)

        try env.warehouse.clearStagingTag(id: tagId)
        let afterClear = try env.warehouse.getStagedItems()
        #expect(afterClear.isEmpty)
    }

    // MARK: - Recent Activity

    @Test("Recent activity captures movements")
    func testRecentActivity() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let activity = try env.warehouse.getRecentActivity()
        #expect(!activity.isEmpty)
    }

    // MARK: - Trailers

    @Test("Trailer lifecycle: create and update")
    func testTrailerLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        let trailerId = try env.warehouse.createTrailer(
            trailerCode: "TR-001",
            name: "Main Trailer",
            status: "active"
        )
        #expect(trailerId > 0)

        let trailer = try env.warehouse.getTrailer(id: trailerId)
        #expect(trailer?.trailerCode == "TR-001")

        try env.warehouse.updateTrailer(id: trailerId, status: "maintenance")

        let trailers = try env.warehouse.listTrailers()
        #expect(!trailers.isEmpty)
    }
}
