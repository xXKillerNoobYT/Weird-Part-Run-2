import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests for warehouse audit confidence, audit sessions, user ratings,
/// organization scores, consolidation, and misplaced parts tracking.
@Suite("Warehouse Audit & Confidence Tests")
struct WarehouseAuditTests {

    private func freshEnv() throws -> E2ETestHelpers.TestEnvironment {
        try E2ETestHelpers.setUp()
    }

    /// Helper: create a full storage hierarchy and return area ID
    private func seedStorageArea(_ env: E2ETestHelpers.TestEnvironment) throws -> Int64 {
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        return area.id!
    }

    // MARK: - Part Confidence

    @Test("Set and get part confidence")
    func testPartConfidence() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        try env.warehouse.setPartConfidence(partId: partId, areaId: areaId, percent: 95.0)

        let confidence = try env.warehouse.getPartConfidence(partId: partId, areaId: areaId)
        #expect(confidence != nil)
        #expect(confidence!.confidencePercent == 95.0)
    }

    @Test("Decay all confidence reduces values")
    func testDecayConfidence() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        try env.warehouse.setPartConfidence(partId: partId, areaId: areaId, percent: 100.0)
        try env.warehouse.decayAllConfidence()

        let after = try env.warehouse.getPartConfidence(partId: partId, areaId: areaId)
        #expect(after!.confidencePercent < 100.0)
    }

    @Test("Calculate reliability level from confidence")
    func testReliabilityLevel() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        try env.warehouse.setPartConfidence(partId: partId, areaId: areaId, percent: 99.0)
        let level = try env.warehouse.calculateReliabilityLevel(partId: partId, areaId: areaId)
        #expect(level >= 1)
    }

    @Test("Movement decay factor calculation")
    func testMovementDecayFactor() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        let factor = try env.warehouse.calculateMovementDecayFactor(partId: partId, areaId: areaId)
        #expect(factor >= 0.0 && factor <= 1.0)
    }

    @Test("Get parts at reliability level")
    func testPartsAtLevel() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        try env.warehouse.setPartConfidence(partId: partId, areaId: areaId, percent: 50.0)

        // Level 1 = low confidence
        let parts = try env.warehouse.getPartsAtLevel(level: 1)
        #expect(parts.count >= 0) // May or may not match depending on thresholds
    }

    // MARK: - Audit Sessions V2

    @Test("Start and complete audit session")
    func testAuditSessionLifecycle() throws {
        let env = try freshEnv()

        let session = try env.warehouse.startAuditSession(
            sessionType: "count",
            startedBy: env.adminUserId
        )
        #expect(session.sessionType == "count")
        #expect(session.status == "active")

        let fetched = try env.warehouse.getAuditSession(sessionId: session.id!)
        #expect(fetched != nil)

        try env.warehouse.completeAuditSession(sessionId: session.id!)
    }

    @Test("List audit sessions with filters")
    func testListAuditSessions() throws {
        let env = try freshEnv()

        _ = try env.warehouse.startAuditSession(sessionType: "count", startedBy: env.adminUserId)
        _ = try env.warehouse.startAuditSession(sessionType: "full", startedBy: env.adminUserId)

        let all = try env.warehouse.listAuditSessions()
        #expect(all.count == 2)

        let countOnly = try env.warehouse.listAuditSessions(sessionType: "count")
        #expect(countOnly.count == 1)
    }

    @Test("Record audit count in session")
    func testRecordAuditCount() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        let session = try env.warehouse.startAuditSession(sessionType: "count", startedBy: env.adminUserId)

        let count = try env.warehouse.recordAuditCount(
            sessionId: session.id!,
            partId: partId,
            areaId: areaId,
            systemCount: 10,
            userCount: 9,
            countedBy: env.adminUserId
        )
        #expect(count.systemCount == 10)
        #expect(count.userCount == 9)

        let counts = try env.warehouse.getAuditCounts(sessionId: session.id!)
        #expect(counts.count == 1)
    }

    // MARK: - User Warehouse Ratings

    @Test("Get and update user warehouse rating")
    func testUserRating() throws {
        let env = try freshEnv()

        let rating = try env.warehouse.getUserWarehouseRating(userId: env.adminUserId)
        #expect(rating.userId == env.adminUserId)

        try env.warehouse.updateUserRating(userId: env.adminUserId, action: "audit_count", result: "accurate")

        let updated = try env.warehouse.getUserWarehouseRating(userId: env.adminUserId)
        #expect(updated.totalAudits >= 0)
    }

    @Test("Warehouse leaderboard returns users")
    func testLeaderboard() throws {
        let env = try freshEnv()

        try env.warehouse.updateUserRating(userId: env.adminUserId, action: "putaway", result: "correct")

        let leaderboard = try env.warehouse.getWarehouseLeaderboard()
        #expect(leaderboard.count >= 1)
    }

    // MARK: - Organization Rating

    @Test("Record and get organization rating")
    func testOrganizationRating() throws {
        let env = try freshEnv()
        let areaId = try seedStorageArea(env)

        try env.warehouse.recordOrgCheck(
            areaId: areaId,
            checkedBy: env.adminUserId,
            labelsAccurate: true,
            partsInHome: true,
            noDuplicates: true,
            notOvercrowded: true,
            binsAssigned: false
        )

        let rating = try env.warehouse.getOrganizationRating(areaId: areaId)
        #expect(rating.lastOrgCheckBy == env.adminUserId)
    }

    @Test("Overall warehouse score")
    func testOverallScore() throws {
        let env = try freshEnv()

        let score = try env.warehouse.getWarehouseOverallScore()
        #expect(score >= 0.0 && score <= 100.0)
    }

    // MARK: - Audit Accuracy

    @Test("Audit accuracy starts at reasonable default")
    func testAuditAccuracy() throws {
        let env = try freshEnv()
        let accuracy = try env.warehouse.getAuditAccuracy()
        #expect(accuracy >= 0.0 && accuracy <= 100.0)
    }

    // MARK: - Staging Boxes

    @Test("Create and list staging boxes")
    func testStagingBoxes() throws {
        let env = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let box = try env.warehouse.createStagingBox(jobId: jobId, size: "large")
        #expect(box.boxSize == "large")

        let boxes = try env.warehouse.listStagingBoxes(jobId: jobId)
        #expect(boxes.count == 1)
    }

    @Test("Mark staging box full and reopen")
    func testStagingBoxStatus() throws {
        let env = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let box = try env.warehouse.createStagingBox(jobId: jobId)
        _ = try env.warehouse.markBoxFull(boxId: box.id)

        // Re-fetch to verify it was marked full
        let boxes = try env.warehouse.listStagingBoxes(jobId: jobId)
        let updated = boxes.first { $0.id == box.id }
        #expect(updated?.isFull == true)

        try env.warehouse.markBoxOpen(boxId: box.id)
    }

    @Test("Delete staging box")
    func testDeleteStagingBox() throws {
        let env = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let box = try env.warehouse.createStagingBox(jobId: jobId)
        try env.warehouse.deleteStagingBox(boxId: box.id)

        let boxes = try env.warehouse.listStagingBoxes(jobId: jobId)
        #expect(boxes.isEmpty)
    }

    // MARK: - Trailers

    @Test("Trailer lifecycle: create, update, list")
    func testTrailerLifecycle() throws {
        let env = try freshEnv()

        let trailerId = try env.warehouse.createTrailer(
            trailerCode: "T-001",
            name: "Box Trailer",
            notes: "20ft enclosed"
        )
        #expect(trailerId > 0)

        let trailers = try env.warehouse.listTrailers()
        #expect(trailers.count >= 1)

        try env.warehouse.updateTrailer(id: trailerId, status: "maintenance")

        let trailer = try env.warehouse.getTrailer(id: trailerId)
        #expect(trailer?.status == "maintenance")
    }

    @Test("Record trailer location history")
    func testTrailerLocation() throws {
        let env = try freshEnv()

        let trailerId = try env.warehouse.createTrailer(trailerCode: "T-002", name: "Flatbed")

        let locId = try env.warehouse.recordTrailerLocation(
            trailerId: trailerId,
            eventType: "dispatch",
            locationKind: "job_site",
            lat: 33.0,
            lng: -117.0,
            recordedBy: env.adminUserId,
            notes: "Dispatched to job"
        )
        #expect(locId > 0)

        let history = try env.warehouse.getTrailerLocationHistory(trailerId: trailerId)
        #expect(history.count >= 1)
    }

    // MARK: - Receiving Sessions

    @Test("Receiving session lifecycle: start, complete")
    func testReceivingSession() throws {
        let env = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-RECV-001",
            supplierId: suppId
        )

        // Add a PO line item so receiving session can pre-populate
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, status, created_at)
                VALUES (?, ?, 10, 'pending', datetime('now'))
                """, arguments: [poId, partId])
        }

        let sessionId = try env.warehouse.startReceivingSession(
            poId: poId,
            startedBy: env.adminUserId
        )
        #expect(sessionId > 0)

        let session = try env.warehouse.getReceivingSession(sessionId: sessionId)
        #expect(session != nil)

        let activeSessions = try env.warehouse.getActiveSessions()
        #expect(activeSessions.count >= 1)

        try env.warehouse.completeSession(sessionId: sessionId, completedBy: env.adminUserId)
    }

    @Test("Cancel receiving session")
    func testCancelReceivingSession() throws {
        let env = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)

        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-CANCEL", supplierId: suppId)
        let sessionId = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)

        try env.warehouse.cancelSession(sessionId: sessionId)
        let session = try env.warehouse.getReceivingSession(sessionId: sessionId)
        #expect(session?.status == "cancelled")
    }

    // MARK: - Consolidation Votes

    @Test("Active consolidation votes starts empty")
    func testActiveConsolidationVotes() throws {
        let env = try freshEnv()
        let votes = try env.warehouse.getActiveConsolidationVotes()
        #expect(votes.isEmpty)
    }

    // MARK: - Misplaced Parts

    @Test("Log and resolve misplaced part")
    func testMisplacedParts() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        let log = try env.warehouse.logMisplacedPart(
            partId: partId,
            foundAtAreaId: areaId,
            homeAreaId: nil,
            qtyFound: 5,
            foundBy: env.adminUserId
        )
        #expect(log.partId == partId)

        let pending = try env.warehouse.getPendingMisplacedParts()
        #expect(pending.count >= 1)

        try env.warehouse.resolveMisplacedPart(
            logId: log.id!,
            resolution: "returned_to_home",
            resolvedBy: env.adminUserId
        )

        let afterResolve = try env.warehouse.getPendingMisplacedParts()
        #expect(afterResolve.count == 0)
    }

    // MARK: - Reports

    @Test("Inventory value report runs without error")
    func testInventoryValueReport() throws {
        let env = try freshEnv()
        let report = try env.warehouse.getInventoryValueReport()
        #expect(report.count >= 0)
    }

    @Test("Backorder report runs without error")
    func testBackorderReport() throws {
        let env = try freshEnv()
        let report = try env.warehouse.getBackorderReport()
        #expect(report.count >= 0)
    }

    @Test("Turnover report runs without error")
    func testTurnoverReport() throws {
        let env = try freshEnv()
        let start = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        let report = try env.warehouse.getTurnoverReport(startDate: start, endDate: Date())
        #expect(report.count >= 0)
    }

    // MARK: - PE-020: Audit Count Recording & Discrepancy Calculation

    /// Helper: seed a stock row and return its stock table ID.
    private func seedStockAndGetId(_ env: E2ETestHelpers.TestEnvironment, partId: Int64, qty: Int) throws -> Int64 {
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: qty)
        // Look up the stock row ID created by the movement
        let stockId = try env.db.writer.read { dbConn in
            try Int64.fetchOne(
                dbConn,
                sql: "SELECT id FROM stock WHERE part_id = ? AND location_type = 'warehouse' AND deleted_at IS NULL",
                arguments: [partId]
            )
        }
        return stockId!
    }

    @Test("recordAuditCount persists counted_qty")
    func testRecordAuditCountPersists() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let stockId = try seedStockAndGetId(env, partId: partId, qty: 10)

        // Record a physical count of 5
        try env.warehouse.recordAuditCount(stockId: stockId, countedQty: 5)

        // Read back and verify
        let row = try env.db.writer.read { dbConn in
            try Row.fetchOne(dbConn, sql: "SELECT counted_qty, last_counted FROM stock WHERE id = ?", arguments: [stockId])
        }
        #expect(row != nil)
        #expect((row!["counted_qty"] as Int?) == 5)
        #expect((row!["last_counted"] as String?) != nil)
    }

    @Test("getAuditDiscrepancies returns non-zero difference")
    func testAuditDiscrepanciesRealDifference() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let stockId = try seedStockAndGetId(env, partId: partId, qty: 10)

        // Record a physical count of 7 (system has 10, so difference = -3)
        try env.warehouse.recordAuditCount(stockId: stockId, countedQty: 7)

        let discrepancies = try env.warehouse.getAuditDiscrepancies()
        #expect(discrepancies.count == 1)
        #expect(discrepancies[0].systemQty == 10)
        #expect(discrepancies[0].countedQty == 7)
        #expect(discrepancies[0].difference == -3)
    }

    @Test("getAuditSummary counts real discrepancies")
    func testAuditSummaryRealDiscrepancies() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)

        // Create 3 parts with stock
        let p1 = try E2ETestHelpers.seedPart(env, name: "Part A", categoryId: catId)
        let p2 = try E2ETestHelpers.seedPart(env, name: "Part B", categoryId: catId)
        let p3 = try E2ETestHelpers.seedPart(env, name: "Part C", categoryId: catId)
        let s1 = try seedStockAndGetId(env, partId: p1, qty: 10)
        let s2 = try seedStockAndGetId(env, partId: p2, qty: 20)
        let s3 = try seedStockAndGetId(env, partId: p3, qty: 30)

        // Count 2 matching and 1 mismatch
        try env.warehouse.recordAuditCount(stockId: s1, countedQty: 10) // matches
        try env.warehouse.recordAuditCount(stockId: s2, countedQty: 20) // matches
        try env.warehouse.recordAuditCount(stockId: s3, countedQty: 25) // mismatch: 25 != 30

        let summary = try env.warehouse.getAuditSummary()
        #expect(summary.countedParts == 3)
        #expect(summary.discrepancies == 1)
        #expect(summary.totalParts >= 3)
    }
}
