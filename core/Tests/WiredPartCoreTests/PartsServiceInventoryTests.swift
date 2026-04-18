import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests for previously-untested PartsService methods:
/// `returnInventoryLIFO`, `checkInventoryForDeletion`,
/// `getLocationStockTarget`, `setLocationStockTarget`,
/// `getSupplierPartCount`, `getSupplierRecentPOs`,
/// `calculateSupplierScores`, `updateSupplierScores`.

@Suite("PartsService Inventory Tests")
struct PartsServiceInventoryTests {

    // MARK: - Helpers

    /// Insert a cost layer via raw SQL and return its ID.
    /// (No public API exists for creating cost layers directly —
    ///  they are normally created through inventory receiving.)
    @discardableResult
    private func insertCostLayer(
        _ env: E2ETestHelpers.TestEnvironment,
        partId: Int64,
        originalQty: Int = 10,
        remainingQty: Int = 10,
        unitCost: Double = 5.0
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO cost_layers
                    (part_id, purchase_date, original_qty, remaining_qty, unit_cost, created_at)
                VALUES (?, datetime('now'), ?, ?, ?, datetime('now'))
                """,
                arguments: [partId, originalQty, remainingQty, unitCost])
            return db.lastInsertedRowID
        }
    }

    /// Insert a consumption record via raw SQL and return its ID.
    @discardableResult
    private func insertConsumption(
        _ env: E2ETestHelpers.TestEnvironment,
        costLayerId: Int64,
        partId: Int64,
        jobId: Int64? = nil,
        qtyConsumed: Int = 5,
        unitCostAtSale: Double = 5.0,
        isReturned: Int = 0
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO cost_layer_consumptions
                    (cost_layer_id, part_id, job_id, qty_consumed, unit_cost_at_sale, is_returned, created_at)
                VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
                """,
                arguments: [costLayerId, partId, jobId, qtyConsumed, unitCostAtSale, isReturned])
            return db.lastInsertedRowID
        }
    }

    // MARK: - returnInventoryLIFO

    @Test("returnInventoryLIFO fully returns consumption and restores cost layer")
    func testReturnInventoryLIFO_fullReturn() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Seed a cost layer that is fully consumed (remaining = 0)
        let layerId = try insertCostLayer(env, partId: partId, originalQty: 5, remainingQty: 0)
        let consumptionId = try insertConsumption(env, costLayerId: layerId, partId: partId, qtyConsumed: 5)

        // Return all 5 units
        let returned = try env.parts.returnInventoryLIFO(partId: partId, qty: 5)

        #expect(returned.count == 1, "Expected one consumption record in the result")
        #expect(returned[0].id == consumptionId, "Result should reference the inserted consumption")

        // Verify consumption is now marked returned
        let consumption = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT is_returned FROM cost_layer_consumptions WHERE id = ?",
                             arguments: [consumptionId])
        }
        let isReturned: Int = try #require(consumption)?["is_returned"] ?? 0
        #expect(isReturned == 1, "Consumption should be marked is_returned = 1 after full return")

        // Verify cost layer remaining qty was restored
        let layer = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT remaining_qty FROM cost_layers WHERE id = ?",
                             arguments: [layerId])
        }
        let remaining: Int = try #require(layer)?["remaining_qty"] ?? -1
        #expect(remaining == 5, "Cost layer remaining_qty should be restored to 5")
    }

    @Test("returnInventoryLIFO throws insufficientReturns when qty exceeds available")
    func testReturnInventoryLIFO_insufficientThrows() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "InsufficientReturnCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "InsufficientPart", categoryId: catId)

        // Only 3 units available, attempt to return 10
        let layerId = try insertCostLayer(env, partId: partId, originalQty: 3, remainingQty: 0)
        try insertConsumption(env, costLayerId: layerId, partId: partId, qtyConsumed: 3)

        #expect(throws: (any Error).self) {
            try env.parts.returnInventoryLIFO(partId: partId, qty: 10)
        }
    }

    // MARK: - checkInventoryForDeletion

    @Test("checkInventoryForDeletion returns zero for unknown entityType")
    func testCheckInventoryForDeletion_unknownType() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.parts.checkInventoryForDeletion(entityType: "unknown", entityId: 1)
        #expect(result.totalStock == 0, "Unknown entityType should match nothing, producing zero stock")
        #expect(result.partsWithStock.isEmpty)
    }

    @Test("checkInventoryForDeletion returns total stock for category with stocked parts")
    func testCheckInventoryForDeletion_categoryWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "CheckInvCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "CheckInvPart", categoryId: catId)

        // Add 7 units of stock to a warehouse location
        try E2ETestHelpers.seedStock(env, partId: partId, qty: 7)

        let result = try env.parts.checkInventoryForDeletion(entityType: "category", entityId: catId)
        #expect(result.totalStock == 7, "Total stock should equal the 7 units seeded")
        #expect(result.partsWithStock.count == 1, "Exactly one part has stock")
        #expect(result.partsWithStock[0].partId == partId)
    }

    @Test("checkInventoryForDeletion returns zero for category with no stocked parts")
    func testCheckInventoryForDeletion_categoryNoStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "EmptyInvCat")
        _ = try E2ETestHelpers.seedPart(env, name: "UnstockedPart", categoryId: catId)

        // No stock seeded
        let result = try env.parts.checkInventoryForDeletion(entityType: "category", entityId: catId)
        #expect(result.totalStock == 0, "Category with parts but no stock should return zero")
        #expect(result.partsWithStock.isEmpty, "No parts with stock should be reported")
    }

    // MARK: - getLocationStockTarget / setLocationStockTarget

    @Test("getLocationStockTarget returns unsaved default when no target exists for a part")
    func testGetLocationStockTarget_returnsFallbackDefault() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "LocTargetCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "LocTargetPart", categoryId: catId)

        // No setLocationStockTarget called — should return a fallback with id == nil
        let target = try env.parts.getLocationStockTarget(partId: partId, locationType: "warehouse", locationId: 1)
        #expect(target.id == nil, "Fallback target should not have a persisted ID")
        #expect(target.partId == partId)
        #expect(target.locationType == "warehouse")
        // Part was created with default (nil) min/target/max, so all should be 0
        #expect(target.minStock == 0)
        #expect(target.targetStock == 0)
        #expect(target.maxStock == 0)
    }

    @Test("setLocationStockTarget persists values that getLocationStockTarget then reads back")
    func testSetAndGetLocationStockTarget_roundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "SetLocCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "SetLocPart", categoryId: catId)

        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "truck", locationId: 42,
            minStock: 5, targetStock: 10, maxStock: 20
        )

        let target = try env.parts.getLocationStockTarget(partId: partId, locationType: "truck", locationId: 42)
        #expect(target.id != nil, "Persisted target should have a non-nil ID")
        #expect(target.minStock == 5)
        #expect(target.targetStock == 10)
        #expect(target.maxStock == 20)
        #expect(target.locationType == "truck")
        #expect(target.locationId == 42)
    }

    @Test("setLocationStockTarget upserts updated values when record already exists")
    func testSetLocationStockTarget_upsert() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "UpsertLocCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "UpsertLocPart", categoryId: catId)

        // Create initial target
        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 1, targetStock: 5, maxStock: 10
        )
        let firstId = try env.parts.getLocationStockTarget(partId: partId, locationType: "warehouse", locationId: 1).id

        // Upsert with new values
        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 2, targetStock: 8, maxStock: 15
        )

        let updated = try env.parts.getLocationStockTarget(partId: partId, locationType: "warehouse", locationId: 1)
        #expect(updated.id == firstId, "Upsert should update the same row, not create a new one")
        #expect(updated.minStock == 2)
        #expect(updated.targetStock == 8)
        #expect(updated.maxStock == 15)
    }

    // MARK: - getSupplierPartCount

    @Test("getSupplierPartCount returns zero for supplier with no linked parts")
    func testGetSupplierPartCount_zero() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "PartCountZeroSupplier")

        let count = try env.parts.getSupplierPartCount(supplierId: supplierId)
        #expect(count == 0, "Fresh supplier should have zero linked parts")
    }

    @Test("getSupplierPartCount returns correct count after linking parts")
    func testGetSupplierPartCount_afterLinking() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PartCountCat")
        let partA = try E2ETestHelpers.seedPart(env, name: "PartCountA", categoryId: catId)
        let partB = try E2ETestHelpers.seedPart(env, name: "PartCountB", categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "PartCountSupplier")

        try env.parts.addPartSupplierLink(partId: partA, supplierId: supplierId)
        try env.parts.addPartSupplierLink(partId: partB, supplierId: supplierId)

        let count = try env.parts.getSupplierPartCount(supplierId: supplierId)
        #expect(count == 2, "Supplier should report 2 linked parts")
    }

    // MARK: - getSupplierRecentPOs

    @Test("getSupplierRecentPOs returns empty list for supplier with no POs")
    func testGetSupplierRecentPOs_empty() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "RecentPOSupplier")

        let pos = try env.parts.getSupplierRecentPOs(supplierId: supplierId)
        #expect(pos.isEmpty, "Supplier with no purchase orders should return empty list")
    }

    // MARK: - calculateSupplierScores / updateSupplierScores

    @Test("calculateSupplierScores computes non-zero on-time rate for completed receiving session")
    func testCalculateSupplierScores_onTimeRateWithCompletedSession() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "OnTimeRateSupplier")

        // Insert a purchase order in received state (5 days ago → within 14-day delivery window)
        let poId: Int64 = try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders
                    (supplier_id, po_number, status, created_at, updated_at, deleted_at)
                VALUES (?, 'PO-ONTIME-001', 'received', datetime('now', '-5 days'), datetime('now'), NULL)
                """, arguments: [supplierId])
            return db.lastInsertedRowID
        }

        // Insert a receiving session with status 'completed' — the correct status string.
        // Regression: was querying 'complete' (without 'd'), which always produced 0 on-time rate.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO receiving_sessions
                    (po_id, started_by, status, completed_at, created_at, deleted_at)
                VALUES (?, ?, 'completed', datetime('now'), datetime('now', '-5 days'), NULL)
                """, arguments: [poId, env.adminUserId])
        }

        let scores = try env.parts.calculateSupplierScores(supplierId: supplierId)
        // On-time rate must be > 0 — delivery was 5 days, within the default 14-day window
        #expect(scores.totalOrderCount == 1, "Should count the one received PO")
        #expect(scores.onTimeRate > 0, "On-time rate must be non-zero when a completed receiving session exists")
    }

    @Test("calculateSupplierScores returns zero scores for supplier with no PO history")
    func testCalculateSupplierScores_zeroes() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "ScoresZeroSupplier")

        let scores = try env.parts.calculateSupplierScores(supplierId: supplierId)
        #expect(scores.totalOrderCount == 0, "No POs → totalOrderCount should be 0")
        #expect(scores.qualityScore == 0, "No receipts → quality score should be 0")
        #expect(scores.reliabilityScore == 0, "No POs → reliability score should be 0")
        #expect(scores.onTimeRate == 0, "No received POs → on-time rate should be 0")
        #expect(scores.avgDeliveryDays == nil, "No completed deliveries → avgDeliveryDays should be nil")
    }

    @Test("updateSupplierScores persists calculated scores to suppliers table")
    func testUpdateSupplierScores_persisted() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "PersistScoresSupplier")

        // The supplier has no POs, so all scores will be 0.
        // What we're testing here is that the UPDATE actually runs without error
        // and that quality_score/on_time_rate/reliability_score are written back.
        try env.parts.updateSupplierScores(supplierId: supplierId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT quality_score, on_time_rate, reliability_score
                FROM suppliers WHERE id = ?
                """, arguments: [supplierId])
        }
        let r = try #require(row)
        // Scores are calculated from actual data (none), so all are 0.
        // The important thing is the columns were written — no NULL, no throw.
        let quality: Double = r["quality_score"] ?? -1
        let onTime: Double  = r["on_time_rate"]    ?? -1
        let reliability: Double = r["reliability_score"] ?? -1
        #expect(quality >= 0 && quality <= 100, "quality_score must be in [0, 100]")
        #expect(onTime >= 0 && onTime <= 100,   "on_time_rate must be in [0, 100]")
        #expect(reliability >= 0 && reliability <= 100, "reliability_score must be in [0, 100]")
    }

    // MARK: - recalculateAllSupplierScores

    @Test("recalculateAllSupplierScores completes without error on empty DB")
    func testRecalculateAllScoresEmptyDB() throws {
        let env = try E2ETestHelpers.setUp()
        // No suppliers exist — should return without throwing
        #expect(throws: Never.self) {
            try env.parts.recalculateAllSupplierScores()
        }
    }

    @Test("recalculateAllSupplierScores writes scores for all active suppliers")
    func testRecalculateAllScoresUpdatesAllSuppliers() throws {
        let env = try E2ETestHelpers.setUp()
        let s1 = try env.parts.createSupplier(name: "Supplier Alpha")
        let s2 = try env.parts.createSupplier(name: "Supplier Beta")

        try env.parts.recalculateAllSupplierScores()

        let rows = try env.db.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, quality_score FROM suppliers
                WHERE id IN (?, ?) AND deleted_at IS NULL
                """, arguments: [s1, s2])
        }
        #expect(rows.count == 2)
        for row in rows {
            let score: Double = row["quality_score"] ?? -1
            #expect(score >= 0)
        }
    }

    // MARK: - buildSupplierAIContext

    @Test("buildSupplierAIContext returns SUPPLIER DATA header on empty DB")
    func testBuildSupplierAIContextEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let ctx = try env.parts.buildSupplierAIContext()
        #expect(ctx.hasPrefix("SUPPLIER DATA:"))
        #expect(ctx.contains("Total suppliers: 0"))
    }

    @Test("buildSupplierAIContext includes supplier name in output")
    func testBuildSupplierAIContextIncludesName() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.parts.createSupplier(name: "Acme Widgets")

        let ctx = try env.parts.buildSupplierAIContext()
        #expect(ctx.contains("Acme Widgets"))
        #expect(ctx.contains("Total suppliers: 1"))
    }

    // MARK: - getActiveUsersWithVotePower

    @Test("getActiveUsersWithVotePower returns seeded admin user")
    func testGetActiveUsersWithVotePower() throws {
        let env = try E2ETestHelpers.setUp()
        // E2ETestHelpers.setUp seeds the admin as "TestAdmin"
        let users = try env.parts.getActiveUsersWithVotePower()
        #expect(!users.isEmpty)
        let admin = users.first(where: { $0.displayName == "TestAdmin" })
        #expect(admin != nil)
    }

    @Test("getActiveUsersWithVotePower excludes inactive users")
    func testGetActiveUsersWithVotePowerExcludesInactive() throws {
        let env = try E2ETestHelpers.setUp()
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO users (display_name, is_active, pin_hash, deleted_at, created_at, updated_at)
                VALUES ('Inactive User', 0, 'placeholder', NULL, datetime('now'), datetime('now'))
                """)
        }
        let users = try env.parts.getActiveUsersWithVotePower()
        #expect(!users.contains(where: { $0.displayName == "Inactive User" }))
    }

    // MARK: - getPollHistory

    @Test("getPollHistory returns empty array when no finalized polls exist")
    func testGetPollHistoryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let history = try env.parts.getPollHistory()
        #expect(history.isEmpty)
    }

    // MARK: - getCompanionRuleStats

    @Test("getCompanionRuleStats returns zero counts on fresh database")
    func testGetCompanionRuleStatsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.parts.getCompanionRuleStats()
        #expect(stats.manual == 0)
        #expect(stats.autoDiscovered == 0)
    }

    @Test("getCompanionRuleStats counts manual rules correctly")
    func testGetCompanionRuleStatsManualRule() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a manual companion rule (not linked to any poll)
        _ = try env.parts.createCompanionRule(name: "Steel + Bracket Bundle")

        let stats = try env.parts.getCompanionRuleStats()
        #expect(stats.manual >= 1)
    }

    // MARK: - getJobsWithCategoryCoOccurrence

    @Test("getJobsWithCategoryCoOccurrence returns empty for empty category list")
    func testGetJobsWithCategoryCoOccurrenceEmptyInput() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.parts.getJobsWithCategoryCoOccurrence(categoryIds: [])
        #expect(result.isEmpty)
    }

    @Test("getJobsWithCategoryCoOccurrence returns empty when no jobs have matching parts")
    func testGetJobsWithCategoryCoOccurrenceNoMatch() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "CoOccurrenceCat")
        let result = try env.parts.getJobsWithCategoryCoOccurrence(categoryIds: [catId])
        #expect(result.isEmpty)
    }
}
