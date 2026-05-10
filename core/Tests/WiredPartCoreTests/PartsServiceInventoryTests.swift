import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests for previously-untested PartsService methods:
/// `returnInventoryLIFO`, `checkInventoryForDeletion`,
/// `getLocationStockTarget`, `setLocationStockTarget`,
/// `getSupplierPartCount`, `getSupplierRecentPOs`,
/// `calculateSupplierScores`, `updateSupplierScores`,
/// `getPartStock`, `generateDailyRecommendation`,
/// `listPendingRecommendations`, `approveRecommendation`,
/// `dismissRecommendation`.

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
        let isReturned: Int = try #require(consumption)["is_returned"]
        #expect(isReturned == 1, "Consumption should be marked is_returned = 1 after full return")

        // Verify cost layer remaining qty was restored
        let layer = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT remaining_qty FROM cost_layers WHERE id = ?",
                             arguments: [layerId])
        }
        let remaining: Int = try #require(layer)["remaining_qty"]
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
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 7)

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

    @Test("calculateSupplierScores excludes soft-deleted receiving_sessions from on-time and avg-days")
    func testCalculateSupplierScores_ignoresSoftDeletedReceivingSessions() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "SoftDeletedRSSupplier")

        // PO in received state — 5 days old, within default 14-day window
        let poId: Int64 = try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders
                    (supplier_id, po_number, status, created_at, updated_at, deleted_at)
                VALUES (?, 'PO-SOFT-RS-001', 'received', datetime('now', '-5 days'), datetime('now'), NULL)
                """, arguments: [supplierId])
            return db.lastInsertedRowID
        }

        // Completed receiving session — but soft-deleted.
        // Regression: the JOIN was `rs.status = 'completed'` with no guard on rs.deleted_at,
        // so a tombstoned session still contributed to the on-time numerator and avg-days.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO receiving_sessions
                    (po_id, started_by, status, completed_at, created_at, deleted_at)
                VALUES (?, ?, 'completed', datetime('now'), datetime('now', '-5 days'), datetime('now'))
                """, arguments: [poId, env.adminUserId])
        }

        let scores = try env.parts.calculateSupplierScores(supplierId: supplierId)
        #expect(scores.totalOrderCount == 1, "PO itself is still active")
        #expect(scores.onTimeRate == 0,
                "Soft-deleted receiving session must not count toward on-time rate — JOIN must guard rs.deleted_at IS NULL")
        #expect(scores.avgDeliveryDays == nil,
                "avgDeliveryDays should be nil when every receiving session is tombstoned")
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

    @Test("getActiveUsersWithVotePower reports has_power=false when user_hats row was revoked")
    func testGetActiveUsersWithVotePower_revokedHatLosesPower() throws {
        let env = try E2ETestHelpers.setUp()

        // Baseline: admin user has voting power via seeded Admin hat.
        let before = try env.parts.getActiveUsersWithVotePower()
        let adminBefore = try #require(before.first { $0.id == env.adminUserId })
        #expect(adminBefore.hasPower,
                "Seeded admin must start with companion_vote_power from their Admin hat")

        // Revoke the Admin hat assignment (soft-delete user_hats row).
        try env.db.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE user_hats SET deleted_at = datetime('now')
                    WHERE user_id = ? AND hat_id = (SELECT id FROM hats WHERE name = 'Admin')
                    """,
                arguments: [env.adminUserId]
            )
        }

        // After revocation: user still exists, but hasPower must be false.
        let after = try env.parts.getActiveUsersWithVotePower()
        let adminAfter = try #require(after.first { $0.id == env.adminUserId })
        #expect(!adminAfter.hasPower,
                "Revoked hat assignments (user_hats.deleted_at set) must not grant vote power")
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

    @Test("recordCompanionFeedback logs entry even without a suggestionId")
    func testRecordCompanionFeedback_logsWithoutSuggestionId() throws {
        let env = try E2ETestHelpers.setUp()
        let catA = try E2ETestHelpers.seedCategory(env, name: "FBCatA")
        let catB = try E2ETestHelpers.seedCategory(env, name: "FBCatB")
        let partA = try env.parts.createPart(categoryId: catA, name: "FBPartA", typeId: nil, colorId: nil, brandId: nil)
        let partB = try env.parts.createPart(categoryId: catB, name: "FBPartB", typeId: nil, colorId: nil, brandId: nil)

        // Call with no suggestionId — previously silently skipped the log entry
        try env.parts.recordCompanionFeedback(
            sourcePartId: partA, targetPartId: partB,
            suggestedQty: 2, acceptedQty: 1,
            source: "ai", userId: env.adminUserId,
            suggestionId: nil
        )

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM companion_feedback WHERE suggestion_id IS NULL") ?? 0
        }
        #expect(count == 1)
    }

    // MARK: - is_active defense: forecasting methods

    @Test("listForecastData excludes inactive parts")
    func testListForecastDataExcludesInactiveParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ForecastDataCat")
        let activeId = try E2ETestHelpers.seedPart(env, name: "ActiveForecastPart", categoryId: catId)
        let inactiveId = try E2ETestHelpers.seedPart(env, name: "InactiveForecastPart", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [inactiveId])
        }

        let results = try env.parts.listForecastData()
        #expect(results.contains { $0.id == activeId })
        #expect(!results.contains { $0.id == inactiveId })
    }

    @Test("listForecastDataWithStock excludes inactive parts")
    func testListForecastDataWithStockExcludesInactiveParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ForecastStockCat")
        let activeId = try E2ETestHelpers.seedPart(env, name: "ActiveStockForecast", categoryId: catId)
        let inactiveId = try E2ETestHelpers.seedPart(env, name: "InactiveStockForecast", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [inactiveId])
        }

        let rows = try env.parts.listForecastDataWithStock()
        #expect(rows.contains { $0.part.id == activeId })
        #expect(!rows.contains { $0.part.id == inactiveId })
    }

    @Test("recalculateForecasts skips inactive parts")
    func testRecalculateForecastsSkipsInactiveParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "RecalcForecastCat")
        let inactiveId = try E2ETestHelpers.seedPart(env, name: "InactiveRecalcPart", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0, forecast_adu_30 = 99.0 WHERE id = ?", arguments: [inactiveId])
        }

        try env.parts.recalculateForecasts()

        let adu: Double? = try env.db.writer.read { db in
            try Double.fetchOne(db, sql: "SELECT forecast_adu_30 FROM parts WHERE id = ?", arguments: [inactiveId])
        }
        #expect(adu == 99.0)
    }

    @Test("recalculateForecastsPerLocation skips inactive parts")
    func testRecalculateForecastsPerLocationSkipsInactiveParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PerLocForecastCat")
        let inactiveId = try E2ETestHelpers.seedPart(env, name: "InactivePerLocPart", categoryId: catId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [inactiveId])
            try db.execute(sql: """
                INSERT INTO stock_movements
                    (part_id, from_location_type, from_location_id, to_location_type, to_location_id,
                     qty, movement_type, performed_by, created_at, deleted_at)
                VALUES (?, 'truck', 1, NULL, NULL, -5, 'consume', 1, datetime('now'), NULL)
                """, arguments: [inactiveId])
        }

        try env.parts.recalculateForecastsPerLocation()

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM location_stock_targets WHERE part_id = ?",
                             arguments: [inactiveId]) ?? 0
        }
        #expect(count == 0)
    }

    // MARK: - Forecast Settings + Free Space coverage

    /// Build a valid ForecastSettings struct for tests.
    private func makeSettings(
        locationType: String = "warehouse",
        locationId: Int64? = nil,
        aduLookbackDays: Int = 90,
        commonMin: Double = 1.0,
        commonTarget: Double = 2.0,
        commonMax: Double = 3.0,
        criticalMin: Double = 1.5,
        criticalTarget: Double = 2.5,
        criticalMax: Double = 4.0
    ) -> ForecastSettings {
        ForecastSettings(
            locationType: locationType, locationId: locationId,
            usageUnit: "days", aduLookbackDays: aduLookbackDays,
            windowWeeks: 4, minDataDays: 7,
            commonMinMultiplier: commonMin, commonTargetMultiplier: commonTarget,
            commonMaxMultiplier: commonMax,
            criticalMinMultiplier: criticalMin, criticalTargetMultiplier: criticalTarget,
            criticalMaxMultiplier: criticalMax,
            freeSpaceSuppressThreshold: 3
        )
    }

    @Test("getForecastSettings returns nil for an unknown location type")
    func testGetForecastSettings_nilForUnknownType() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.parts.getForecastSettings(locationType: "nonexistent_type_xyz", locationId: nil)
        #expect(result == nil)
    }

    @Test("saveForecastSettings updates an existing default when reloaded with mutations")
    func testSaveAndGetForecastSettings_roundtrip() throws {
        let env = try E2ETestHelpers.setUp()
        guard var current = try env.parts.getForecastSettings(locationType: "warehouse", locationId: nil) else {
            Issue.record("Expected seeded default warehouse settings to exist")
            return
        }
        current.aduLookbackDays = 60
        try env.parts.saveForecastSettings(current)

        let loaded = try env.parts.getForecastSettings(locationType: "warehouse", locationId: nil)
        #expect(loaded?.aduLookbackDays == 60)
        #expect(loaded?.locationId == nil)
    }

    @Test("getForecastSettings prefers location-specific override over default")
    func testGetForecastSettings_specificBeatsDefault() throws {
        let env = try E2ETestHelpers.setUp()
        // Insert override for location 7 (default warehouse seed already exists with aduLookbackDays = 365).
        try env.parts.saveForecastSettings(makeSettings(locationId: 7, aduLookbackDays: 90))

        let loaded = try env.parts.getForecastSettings(locationType: "warehouse", locationId: 7)
        #expect(loaded?.aduLookbackDays == 90)
        #expect(loaded?.locationId == 7)
    }

    @Test("getForecastSettings falls back to default when no override exists for location")
    func testGetForecastSettings_fallbackToDefault() throws {
        let env = try E2ETestHelpers.setUp()
        // No override saved for location 99 — should return the seeded default row.
        let loaded = try env.parts.getForecastSettings(locationType: "warehouse", locationId: 99)
        #expect(loaded != nil)
        #expect(loaded?.locationId == nil) // returned the default row
    }

    @Test("saveForecastSettings rejects aduLookbackDays of 0")
    func testSaveForecastSettings_rejectsZeroLookback() throws {
        let env = try E2ETestHelpers.setUp()
        let bad = makeSettings(aduLookbackDays: 0)
        #expect(throws: PartsService.PartsError.self) {
            try env.parts.saveForecastSettings(bad)
        }
    }

    @Test("saveForecastSettings rejects out-of-order common multipliers")
    func testSaveForecastSettings_rejectsCommonMultiplierOrder() throws {
        let env = try E2ETestHelpers.setUp()
        let bad = makeSettings(commonMin: 5.0, commonTarget: 2.0, commonMax: 3.0)
        #expect(throws: PartsService.PartsError.self) {
            try env.parts.saveForecastSettings(bad)
        }
    }

    @Test("saveForecastSettings rejects out-of-order critical multipliers")
    func testSaveForecastSettings_rejectsCriticalMultiplierOrder() throws {
        let env = try E2ETestHelpers.setUp()
        let bad = makeSettings(criticalMin: 5.0, criticalTarget: 2.0, criticalMax: 3.0)
        #expect(throws: PartsService.PartsError.self) {
            try env.parts.saveForecastSettings(bad)
        }
    }

    @Test("getFreeSpaceRating returns 5 (middle) when not yet set")
    func testGetFreeSpaceRating_defaultsToFive() throws {
        let env = try E2ETestHelpers.setUp()
        let rating = try env.parts.getFreeSpaceRating(locationType: "warehouse", locationId: 1)
        #expect(rating == 5)
    }

    @Test("setFreeSpaceRating then getFreeSpaceRating round-trips a valid rating")
    func testSetFreeSpaceRating_roundtrip() throws {
        let env = try E2ETestHelpers.setUp()
        try env.parts.setFreeSpaceRating(
            locationType: "warehouse", locationId: 1, rating: 8, userId: env.adminUserId
        )

        let rating = try env.parts.getFreeSpaceRating(locationType: "warehouse", locationId: 1)
        #expect(rating == 8)
    }

    @Test("setFreeSpaceRating clamps below 1 to 1 and above 10 to 10")
    func testSetFreeSpaceRating_clampsRange() throws {
        let env = try E2ETestHelpers.setUp()
        try env.parts.setFreeSpaceRating(
            locationType: "warehouse", locationId: 2, rating: -3, userId: env.adminUserId
        )
        #expect(try env.parts.getFreeSpaceRating(locationType: "warehouse", locationId: 2) == 1)

        try env.parts.setFreeSpaceRating(
            locationType: "warehouse", locationId: 3, rating: 99, userId: env.adminUserId
        )
        #expect(try env.parts.getFreeSpaceRating(locationType: "warehouse", locationId: 3) == 10)
    }

    @Test("setFreeSpaceRating updates an existing row instead of inserting a duplicate")
    func testSetFreeSpaceRating_updatesExisting() throws {
        let env = try E2ETestHelpers.setUp()
        try env.parts.setFreeSpaceRating(
            locationType: "warehouse", locationId: 1, rating: 4, userId: env.adminUserId
        )
        try env.parts.setFreeSpaceRating(
            locationType: "warehouse", locationId: 1, rating: 7, userId: env.adminUserId
        )

        #expect(try env.parts.getFreeSpaceRating(locationType: "warehouse", locationId: 1) == 7)
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM location_free_space
                WHERE location_type = 'warehouse' AND location_id = 1
                """) ?? 0
        }
        #expect(count == 1)
    }

    @Test("listAllForecastSettings returns the three seeded defaults on a fresh DB")
    func testListAllForecastSettings_seededDefaults() throws {
        let env = try E2ETestHelpers.setUp()
        let all = try env.parts.listAllForecastSettings()
        #expect(all.count == 3)
        let types = Set(all.map { $0.locationType })
        #expect(types == ["warehouse", "truck", "trailer"])
        // All seeded rows are defaults (location_id IS NULL).
        #expect(all.allSatisfy { $0.locationId == nil })
    }

    @Test("listAllForecastSettings includes overrides alongside seeded defaults, ordered by location_type then location_id")
    func testListAllForecastSettings_returnsOrdered() throws {
        let env = try E2ETestHelpers.setUp()
        // Add 2 overrides on top of the 3 seeded defaults.
        try env.parts.saveForecastSettings(makeSettings(locationType: "warehouse", locationId: 2))
        try env.parts.saveForecastSettings(makeSettings(locationType: "truck", locationId: 5))

        let all = try env.parts.listAllForecastSettings()
        #expect(all.count == 5)
        // Ordering: location_type ASC, then location_id ASC (nulls first in SQLite).
        // Expected: trailer/null, truck/null, truck/5, warehouse/null, warehouse/2.
        #expect(all[0].locationType == "trailer" && all[0].locationId == nil)
        #expect(all[1].locationType == "truck" && all[1].locationId == nil)
        #expect(all[2].locationType == "truck" && all[2].locationId == 5)
        #expect(all[3].locationType == "warehouse" && all[3].locationId == nil)
        #expect(all[4].locationType == "warehouse" && all[4].locationId == 2)
    }

    // MARK: - Recommendation Pipeline Helpers

    /// Insert a pending `target_recommendations` row directly via SQL and return its ID.
    /// Used to set up test state for listPendingRecommendations, approveRecommendation,
    /// and dismissRecommendation tests without going through the full engine pipeline.
    @discardableResult
    private func insertPendingRecommendation(
        _ env: E2ETestHelpers.TestEnvironment,
        partId: Int64,
        locationType: String = "warehouse",
        locationId: Int64 = 1,
        recommendationType: String = "adjust",
        recommendedMin: Int = 2,
        recommendedTarget: Int = 5,
        recommendedMax: Int = 10,
        status: String = "pending"
    ) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO target_recommendations
                    (part_id, location_type, location_id, recommendation_type,
                     current_min, current_target, current_max,
                     recommended_min, recommended_target, recommended_max,
                     usage_value, usage_unit, data_days, impact_score,
                     reason, cooldown_until, status)
                VALUES (?, ?, ?, ?,  0, 0, 0,  ?, ?, ?,
                        1.0, 'daily', 90, 5.0,
                        'Test recommendation', datetime('now', '+60 days'), ?)
                """,
                arguments: [partId, locationType, locationId, recommendationType,
                            recommendedMin, recommendedTarget, recommendedMax, status])
            return db.lastInsertedRowID
        }
    }

    // MARK: - getPartStock

    @Test("getPartStock returns one row per active location where the part has stock")
    func test_getPartStock_aggregatesAcrossLocations() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PartStockCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "PartStockPart", categoryId: catId)

        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10, locationType: "warehouse", locationId: 1)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5, locationType: "truck", locationId: 1)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 3, locationType: "trailer", locationId: 1)

        let rows = try env.parts.getPartStock(partId: partId)
        #expect(rows.count == 3, "Expected one stock row per seeded location type")
        let locationTypes = Set(rows.map { $0["location_type"] as String })
        #expect(locationTypes.contains("warehouse"))
        #expect(locationTypes.contains("truck"))
        #expect(locationTypes.contains("trailer"))
    }

    @Test("getPartStock excludes soft-deleted stock rows")
    func test_getPartStock_excludesDeletedStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PartStockDeletedCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "PartStockDeletedPart", categoryId: catId)

        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10, locationType: "warehouse", locationId: 1)

        // Soft-delete the stock row directly — scope to the exact location row to prevent
        // order-dependent state if other tests create additional stock rows for this part.
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE stock SET deleted_at = datetime('now')
                WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1
                  AND deleted_at IS NULL
                """, arguments: [partId])
        }

        let rows = try env.parts.getPartStock(partId: partId)
        #expect(rows.isEmpty, "Soft-deleted stock rows must not be returned by getPartStock")
    }

    // MARK: - generateDailyRecommendation

    @Test("generateDailyRecommendation inserts a pending recommendation when sufficient consumption data exists")
    func test_generateDailyRecommendation_createsTargetRecommendation() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DailyRecCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "DailyRecPart", categoryId: catId)

        // Lower minDataDays to 7 so we can back-date movements by 10 days instead of 90.
        guard var settings = try env.parts.getForecastSettings(locationType: "warehouse", locationId: nil) else {
            Issue.record("Expected seeded default warehouse forecast_settings to exist")
            return
        }
        settings.minDataDays = 7
        try env.parts.saveForecastSettings(settings)

        // Create a location_stock_targets row — the engine scans this table.
        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 0, targetStock: 0, maxStock: 0
        )

        // Insert movements via raw SQL so we can set backdated created_at.
        // First movement satisfies the "first_movement >= minDataDays" guard (10 > 7).
        // Consume movement gives a non-trivial ADU for the recommendation engine.
        //
        // created_at must be ISO 8601 with a T-separator (e.g. 2026-01-01T12:00:00Z)
        // because generateDailyRecommendation parses MIN(created_at) via
        // CoreFormatters.parseISO, which only accepts ISO-8601 format.
        // SQLite's datetime('now') produces "YYYY-MM-DD HH:MM:SS" (space-separated),
        // which parseISO cannot parse — so we compute the timestamps in Swift.
        let receiveAt = CoreFormatters.iso8601.string(from: Date().addingTimeInterval(-10 * 86400))
        let consumeAt = CoreFormatters.iso8601.string(from: Date().addingTimeInterval(-5 * 86400))
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO stock_movements
                    (part_id, from_location_type, from_location_id,
                     to_location_type, to_location_id,
                     qty, movement_type, performed_by, created_at, deleted_at)
                VALUES (?, NULL, NULL, 'warehouse', 1,
                        500, 'receive', ?, ?, NULL)
                """, arguments: [partId, env.adminUserId, receiveAt])
            // qty is positive (300); direction is conveyed by from_location_type = 'warehouse'
            // matching the convention enforced by WarehouseService.createMovement (qty > 0).
            try db.execute(sql: """
                INSERT INTO stock_movements
                    (part_id, from_location_type, from_location_id,
                     to_location_type, to_location_id,
                     qty, movement_type, performed_by, created_at, deleted_at)
                VALUES (?, 'warehouse', 1, NULL, NULL,
                        300, 'consume', ?, ?, NULL)
                """, arguments: [partId, env.adminUserId, consumeAt])
        }

        try env.parts.generateDailyRecommendation()

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM target_recommendations
                WHERE part_id = ? AND status = 'pending' AND deleted_at IS NULL
                """, arguments: [partId]) ?? 0
        }
        #expect(count == 1, "Engine should produce exactly one pending recommendation when data exceeds minDataDays")
    }

    @Test("generateDailyRecommendation skips parts with no stock movement history")
    func test_generateDailyRecommendation_skipsWhenInsufficientData() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DailyRecSkipCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "DailyRecSkipPart", categoryId: catId)

        // Create a location_stock_targets row but do NOT insert any stock_movements.
        // Mark it critical so this test exercises the stock-level no-history guard
        // without also matching the separate "stale common" category-change rule.
        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 0, targetStock: 0, maxStock: 0
        )
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE location_stock_targets
                SET part_category = 'critical'
                WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1
                """, arguments: [partId])
        }

        try env.parts.generateDailyRecommendation()

        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM target_recommendations
                WHERE part_id = ? AND deleted_at IS NULL
                """, arguments: [partId]) ?? 0
        }
        #expect(count == 0, "Engine must not produce a recommendation when there is no movement history")
    }

    // MARK: - listPendingRecommendations

    @Test("listPendingRecommendations returns only pending status rows, excluding approved and dismissed")
    func test_listPendingRecommendations_returnsOnlyPending() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ListPendingCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "ListPendingPart", categoryId: catId)

        try insertPendingRecommendation(env, partId: partId, status: "pending")
        try insertPendingRecommendation(env, partId: partId, status: "approved")
        try insertPendingRecommendation(env, partId: partId, status: "dismissed")

        let results = try env.parts.listPendingRecommendations()
        let forPart = results.filter { $0.partId == partId }
        #expect(forPart.count == 1, "Only the pending row should be returned; approved/dismissed rows must be excluded")
        #expect(forPart[0].status == "pending")
    }

    @Test("listPendingRecommendations respects the limit parameter")
    func test_listPendingRecommendations_respectsLimit() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "LimitPendingCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "LimitPendingPart", categoryId: catId)

        // Insert 8 pending recommendations for the same part (SQL allows duplicates here).
        for _ in 1...8 {
            try insertPendingRecommendation(env, partId: partId)
        }

        let results = try env.parts.listPendingRecommendations(limit: 3)
        #expect(results.count <= 3, "listPendingRecommendations must honor the limit parameter")
    }

    // MARK: - approveRecommendation

    @Test("approveRecommendation updates location_stock_targets with recommended values")
    func test_approveRecommendation_appliesToLocationStockTargets() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ApproveLSTCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "ApproveLSTPartStock", categoryId: catId)

        // Seed a location_stock_targets row with zeroed values.
        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 0, targetStock: 0, maxStock: 0
        )

        // Insert a pending recommendation that suggests raising the levels.
        let recId = try insertPendingRecommendation(
            env, partId: partId,
            recommendationType: "adjust",
            recommendedMin: 3, recommendedTarget: 8, recommendedMax: 15
        )

        try env.parts.approveRecommendation(id: recId, byUserId: env.adminUserId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT min_stock, target_stock, max_stock
                FROM location_stock_targets
                WHERE part_id = ? AND location_type = 'warehouse' AND location_id = 1
                """, arguments: [partId])
        }
        let r = try #require(row)
        #expect((r["min_stock"] as Int) == 3,    "min_stock must be updated to the recommended value")
        #expect((r["target_stock"] as Int) == 8,  "target_stock must be updated to the recommended value")
        #expect((r["max_stock"] as Int) == 15,   "max_stock must be updated to the recommended value")
    }

    @Test("approveRecommendation records the approving userId in approved_by")
    func test_approveRecommendation_recordsApprover() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ApproverCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "ApproverPart", categoryId: catId)

        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 0, targetStock: 0, maxStock: 0
        )
        let recId = try insertPendingRecommendation(env, partId: partId)

        try env.parts.approveRecommendation(id: recId, byUserId: env.adminUserId)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, approved_by FROM target_recommendations WHERE id = ?
                """, arguments: [recId])
        }
        let r = try #require(row)
        #expect((r["status"] as String) == "approved",            "status must be 'approved' after approval")
        #expect((r["approved_by"] as Int64?) == env.adminUserId,  "approved_by must record the userId passed to approveRecommendation")
    }

    // MARK: - dismissRecommendation

    @Test("dismissRecommendation persists the dismiss reason in dismissed_reason")
    func test_dismissRecommendation_setsDismissReason() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DismissReasonCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "DismissReasonPart", categoryId: catId)

        let recId = try insertPendingRecommendation(env, partId: partId)

        let reason = "We are overstocked this quarter"
        try env.parts.dismissRecommendation(id: recId, byUserId: env.adminUserId, reason: reason)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT status, dismissed_reason FROM target_recommendations WHERE id = ?
                """, arguments: [recId])
        }
        let r = try #require(row)
        #expect((r["status"] as String) == "dismissed",   "status must be 'dismissed' after dismissal")
        #expect((r["dismissed_reason"] as String?) == reason, "dismissed_reason must store the provided reason string")
    }

    @Test("dismissRecommendation records the dismissing userId in dismissed_by")
    func test_dismissRecommendation_setsDismisser() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DismisserCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "DismisserPart", categoryId: catId)

        let recId = try insertPendingRecommendation(env, partId: partId)

        try env.parts.dismissRecommendation(
            id: recId, byUserId: env.adminUserId, reason: "Not needed right now"
        )

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT dismissed_by FROM target_recommendations WHERE id = ?
                """, arguments: [recId])
        }
        let r = try #require(row)
        #expect((r["dismissed_by"] as Int64?) == env.adminUserId,
                "dismissed_by must record the userId passed to dismissRecommendation")
    }

    // MARK: - Permission gates (#367)

    @Test("approveRecommendation throws insufficientPermissions for user without forecasting.approve_recommendation")
    func test_approveRecommendation_rejectsUnprivilegedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "GateApproveRejectCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "GateApproveRejectPart", categoryId: catId)
        let recId = try insertPendingRecommendation(env, partId: partId)

        // Create a plain user with no hats and therefore no forecasting permissions
        let unprivilegedId = try env.auth.createUser(displayName: "NoPermUser", pin: "9999")

        #expect(throws: PartsService.PartsError.insufficientPermissions(required: "forecasting.approve_recommendation")) {
            try env.parts.approveRecommendation(id: recId, byUserId: unprivilegedId)
        }
    }

    @Test("approveRecommendation succeeds for admin user who has forecasting.approve_recommendation")
    func test_approveRecommendation_succeedsWithPermission() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "GateApproveOKCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "GateApproveOKPart", categoryId: catId)
        try env.parts.setLocationStockTarget(
            partId: partId, locationType: "warehouse", locationId: 1,
            minStock: 0, targetStock: 0, maxStock: 0
        )
        let recId = try insertPendingRecommendation(env, partId: partId)

        // Admin has forecasting.approve_recommendation seeded by defaultPermissionMap
        #expect(throws: Never.self) {
            try env.parts.approveRecommendation(id: recId, byUserId: env.adminUserId)
        }
    }

    @Test("dismissRecommendation throws insufficientPermissions for user without forecasting.dismiss_recommendation")
    func test_dismissRecommendation_rejectsUnprivilegedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "GateDismissRejectCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "GateDismissRejectPart", categoryId: catId)
        let recId = try insertPendingRecommendation(env, partId: partId)

        let unprivilegedId = try env.auth.createUser(displayName: "NoDismissUser", pin: "8888")

        #expect(throws: PartsService.PartsError.insufficientPermissions(required: "forecasting.dismiss_recommendation")) {
            try env.parts.dismissRecommendation(id: recId, byUserId: unprivilegedId, reason: "Budget cut")
        }
    }

    @Test("dismissRecommendation succeeds for admin user who has forecasting.dismiss_recommendation")
    func test_dismissRecommendation_succeedsWithPermission() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "GateDismissOKCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "GateDismissOKPart", categoryId: catId)
        let recId = try insertPendingRecommendation(env, partId: partId)

        // Admin has forecasting.dismiss_recommendation seeded by defaultPermissionMap
        #expect(throws: Never.self) {
            try env.parts.dismissRecommendation(id: recId, byUserId: env.adminUserId, reason: "Not needed")
        }
    }
}
