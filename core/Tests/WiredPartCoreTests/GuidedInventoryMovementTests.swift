import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("Guided Inventory Movement Ledger Tests")
struct GuidedInventoryMovementTests {
    @Test("guided warehouse to truck movement writes one ledger row and updates both locations")
    func guidedWarehouseToTruckWritesLedger() throws {
        let env = try E2ETestHelpers.setUp()
        let partId = try seedPartWithWarehouseStock(env, qty: 10)

        let movementId = try env.warehouse.executeGuidedMovement(
            WarehouseService.GuidedMovementInput(
                partId: partId,
                qty: 4,
                fromLocationType: .warehouse,
                fromLocationId: 1,
                toLocationType: .truck,
                toLocationId: 7,
                performedBy: env.adminUserId,
                reason: "Load service truck",
                notes: "WEI-3862 guided move",
                scanConfirmed: true
            )
        )

        #expect(movementId > 0)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 6)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "truck", locationId: 7) == 4)

        let ledger = try #require(try env.warehouse.getInventoryLedger(partId: partId))
        #expect(ledger.totalQty == 10)
        #expect(ledger.movements.contains { movement in
            movement.id == movementId &&
            movement.fromLocationType == "warehouse" &&
            movement.toLocationType == "truck" &&
            movement.movementType == StockMovement.MovementType.transfer.rawValue &&
            movement.scanConfirmed
        })
    }

    @Test("guided warehouse to job movement links the job and preserves quantity history")
    func guidedWarehouseToJobLinksJob() throws {
        let env = try E2ETestHelpers.setUp()
        let partId = try seedPartWithWarehouseStock(env, qty: 8)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "WEI-3862-JOB", name: "Ledger Job")

        let movementId = try env.warehouse.executeGuidedMovement(
            WarehouseService.GuidedMovementInput(
                partId: partId,
                qty: 3,
                fromLocationType: .warehouse,
                fromLocationId: 1,
                toLocationType: .job,
                toLocationId: jobId,
                performedBy: env.adminUserId,
                jobId: jobId,
                reason: "Issue to job"
            )
        )

        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 5)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "job", locationId: jobId) == 3)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT job_id, qty, movement_type FROM stock_movements WHERE id = ?", arguments: [movementId])
        }
        #expect((row?["job_id"] as Int64?) == jobId)
        #expect((row?["qty"] as Int?) == 3)
        #expect((row?["movement_type"] as String?) == StockMovement.MovementType.transfer.rawValue)
    }

    @Test("guided job return moves stock into return holding before restock to warehouse")
    func guidedJobReturnAndRestockUseReturnLocation() throws {
        let env = try E2ETestHelpers.setUp()
        let partId = try seedPartWithWarehouseStock(env, qty: 5)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "WEI-3862-RET", name: "Return Job")

        _ = try env.warehouse.executeGuidedMovement(
            WarehouseService.GuidedMovementInput(
                partId: partId,
                qty: 2,
                fromLocationType: .warehouse,
                fromLocationId: 1,
                toLocationType: .job,
                toLocationId: jobId,
                performedBy: env.adminUserId,
                jobId: jobId,
                reason: "Issue to job"
            )
        )

        let returnMovementId = try env.warehouse.executeGuidedMovement(
            WarehouseService.GuidedMovementInput(
                partId: partId,
                qty: 1,
                fromLocationType: .job,
                fromLocationId: jobId,
                toLocationType: .returnHolding,
                toLocationId: jobId,
                performedBy: env.adminUserId,
                jobId: jobId,
                reason: "Usable return from job"
            )
        )
        let restockMovementId = try env.warehouse.executeGuidedMovement(
            WarehouseService.GuidedMovementInput(
                partId: partId,
                qty: 1,
                fromLocationType: .returnHolding,
                fromLocationId: jobId,
                toLocationType: .warehouse,
                toLocationId: 1,
                performedBy: env.adminUserId,
                jobId: jobId,
                reason: "Restock usable return"
            )
        )

        #expect(returnMovementId > 0)
        #expect(restockMovementId > 0)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "job", locationId: jobId) == 1)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "return", locationId: jobId) == 0)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 4)

        let returnRows = try env.warehouse.listMovements(movementType: StockMovement.MovementType.stockReturn.rawValue)
        #expect(returnRows.contains { $0.id == returnMovementId && $0.toLocationType == "return" })
        #expect(returnRows.contains { $0.id == restockMovementId && $0.fromLocationType == "return" })
    }

    @Test("guided invalid movement rolls back without stock or ledger side effects")
    func guidedInvalidMovementRollsBack() throws {
        let env = try E2ETestHelpers.setUp()
        let partId = try seedPartWithWarehouseStock(env, qty: 2)
        let beforeCount = try movementCount(env, partId: partId)

        do {
            _ = try env.warehouse.executeGuidedMovement(
                WarehouseService.GuidedMovementInput(
                    partId: partId,
                    qty: 5,
                    fromLocationType: .warehouse,
                    fromLocationId: 1,
                    toLocationType: .truck,
                    toLocationId: 9,
                    performedBy: env.adminUserId,
                    reason: "Should fail"
                )
            )
            Issue.record("Expected insufficient stock to fail")
        } catch WarehouseService.WarehouseError.insufficientStock(let available, let requested) {
            #expect(available == 2)
            #expect(requested == 5)
        }

        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1) == 2)
        #expect(try env.warehouse.getStockQty(partId: partId, locationType: "truck", locationId: 9) == 0)
        #expect(try movementCount(env, partId: partId) == beforeCount)
    }

    private func seedPartWithWarehouseStock(_ env: E2ETestHelpers.TestEnvironment, qty: Int) throws -> Int64 {
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "WEI-3862 Inventory")
        let partId = try E2ETestHelpers.seedPart(env, name: "WEI-3862 Ledger Part", categoryId: categoryId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: qty)
        return partId
    }

    private func movementCount(_ env: E2ETestHelpers.TestEnvironment, partId: Int64) throws -> Int {
        try env.db.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM stock_movements WHERE part_id = ? AND deleted_at IS NULL",
                arguments: [partId]
            ) ?? 0
        }
    }
}
