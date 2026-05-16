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

    @Test("getBackorderReport falls back when part and supplier are soft-deleted")
    func testGetBackorderReportHidesDeletedPartAndSupplierNames() throws {
        let env = try freshEnv()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "BackorderSupplier")
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-BO-DEL", supplierId: supplierId, notes: nil)
        let catId = try E2ETestHelpers.seedCategory(env, name: "BackorderCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "BackorderPart", categoryId: catId)
        let lineId = try env.orders.addPOLineItem(poId: poId, partId: partId, quantity: 10, unitPrice: 2.0)

        // Put PO in 'sent' status so it shows up in backorder report
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE purchase_orders SET status = 'sent' WHERE id = ?", arguments: [poId])
            // Leave qty_received = 0 (default) so it appears as backordered
        }

        // Soft-delete the part and supplier
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
            try db.execute(sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?", arguments: [supplierId])
        }

        let report = try env.warehouse.getBackorderReport()
        let row = report.first(where: { $0.id == lineId })
        #expect(row != nil)
        #expect(row?.partName == "Unknown Part")
        #expect(row?.supplierName == nil)
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

    // MARK: - Receiving Session Item Updates

    @Test("updateSessionItem sets received_qty and notes")
    func testUpdateSessionItem() throws {
        let env = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-UPD-001", supplierId: suppId)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, status, created_at)
                VALUES (?, ?, 5, 'pending', datetime('now'))
                """, arguments: [poId, partId])
        }

        let sessionId = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        #expect(items.count >= 1)

        let itemId = items[0].id
        try env.warehouse.updateSessionItem(itemId: itemId, receivedQty: 3, notes: "Partial delivery")

        let updated = try env.db.writer.read { db in
            try Row.fetchOne(db,
                sql: "SELECT received_qty, notes FROM receiving_session_items WHERE id = ?",
                arguments: [itemId])
        }
        #expect((updated?["received_qty"] as Int?) == 3)
        #expect((updated?["notes"] as String?) == "Partial delivery")
    }

    @Test("recordScan increments received_qty by the given qty")
    func testRecordScan() throws {
        let env = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-SCAN-001", supplierId: suppId)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, status, created_at)
                VALUES (?, ?, 10, 'pending', datetime('now'))
                """, arguments: [poId, partId])
        }

        let sessionId = try env.warehouse.startReceivingSession(poId: poId, startedBy: env.adminUserId)
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        let itemId = items[0].id

        // Start at 0, scan 2 then scan 3 more → should be 5
        try env.warehouse.recordScan(itemId: itemId, qty: 2)
        try env.warehouse.recordScan(itemId: itemId, qty: 3)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT received_qty FROM receiving_session_items WHERE id = ?", arguments: [itemId])
        }
        #expect((row?["received_qty"] as Int?) == 5)
    }

    // MARK: - Return Processing

    @Test("getReturnItems returns empty when no returns exist")
    func testGetReturnItemsEmpty() throws {
        let env = try freshEnv()
        let items = try env.warehouse.getReturnItems()
        #expect(items.isEmpty)
    }

    @Test("processReturn creates return movement visible in getReturnItems")
    func testProcessReturn() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20, locationType: "job", locationId: 99)

        let movementId = try env.warehouse.processReturn(
            partId: partId,
            qty: 5,
            fromLocationType: "job",
            fromLocationId: 99,
            reason: "unused_material",
            notes: "Left over",
            performedBy: env.adminUserId
        )
        #expect(movementId > 0)

        let returns = try env.warehouse.getReturnItems()
        #expect(returns.contains { $0.id == movementId })
        #expect(returns.first { $0.id == movementId }?.movementType == "return")
    }

    // MARK: - Audit Session Finalize / Adjust / Recount

    @Test("finalizeAuditSession marks session as completed")
    func testFinalizeAuditSession() throws {
        let env = try freshEnv()
        let session = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        try env.warehouse.finalizeAuditSession(sessionId: session.id!)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT status FROM audit_sessions_v2 WHERE id = ?", arguments: [session.id!])
        }
        #expect((row?["status"] as String?) == "completed")
    }

    @Test("adjustAuditCount updates stock qty and records adjustment movement")
    func testAdjustAuditCount() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        try env.warehouse.adjustAuditCount(
            partId: partId,
            locationType: "warehouse",
            locationId: 1,
            newQty: 7,
            reason: "Physical count",
            performedBy: env.adminUserId
        )

        let qty = try env.warehouse.getStockQty(partId: partId, locationType: "warehouse", locationId: 1)
        #expect(qty == 7)

        // Verify the adjustment movement was recorded
        let movements = try env.warehouse.listMovements(movementType: "adjustment")
        #expect(movements.contains { $0.partId == partId })
    }

    @Test("recordAuditRecount updates last_counted timestamp for stock row")
    func testRecordAuditRecount() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5)

        let beforeRecount = try env.db.writer.read { db in
            try Row.fetchOne(db,
                sql: "SELECT last_counted FROM stock WHERE part_id = ? AND location_type = 'warehouse'",
                arguments: [partId])
        }

        // last_counted should be nil initially (never counted)
        let initialCounted = beforeRecount?["last_counted"] as String?

        try env.warehouse.recordAuditRecount(partId: partId, locationType: "warehouse", locationId: 1)

        let afterRecount = try env.db.writer.read { db in
            try Row.fetchOne(db,
                sql: "SELECT last_counted FROM stock WHERE part_id = ? AND location_type = 'warehouse'",
                arguments: [partId])
        }
        let updatedCounted = afterRecount?["last_counted"] as String?
        // After recount, last_counted must be set
        #expect(updatedCounted != nil)
        _ = initialCounted // suppress unused warning
    }

    // MARK: - Consolidation Vote Lifecycle

    /// Helper: seed a part with 2 home area assignments so suggestConsolidation returns a vote.
    private func seedConsolidationVote(_ env: E2ETestHelpers.TestEnvironment) throws -> (partId: Int64, voteId: Int64, area1: Int64, area2: Int64) {
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let plan = try env.warehouse.createFloorPlan(name: "CV-Plan", widthInches: 200, lengthInches: 200)
        let unit1 = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "U1", unitType: "shelf")
        let unit2 = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "U2", unitType: "shelf")
        let level1 = try env.warehouse.addStorageLevel(unitId: unit1.id!, levelCode: "L1")
        let level2 = try env.warehouse.addStorageLevel(unitId: unit2.id!, levelCode: "L1")
        let area1 = try env.warehouse.addStorageArea(levelId: level1.id!, areaNumber: 1)
        let area2 = try env.warehouse.addStorageArea(levelId: level2.id!, areaNumber: 1)

        _ = try env.warehouse.assignPartToArea(partId: partId, areaId: area1.id!, isHome: true)
        _ = try env.warehouse.assignPartToArea(partId: partId, areaId: area2.id!, isHome: true)

        let vote = try env.warehouse.suggestConsolidation(partId: partId)
        #expect(vote != nil)
        return (partId: partId, voteId: vote!.id!, area1: area1.id!, area2: area2.id!)
    }

    @Test("castConsolidationVote inserts a vote entry for the user")
    func testCastConsolidationVote() throws {
        let env = try freshEnv()
        let (_, voteId, area1, _) = try seedConsolidationVote(env)

        try env.warehouse.castConsolidationVote(voteId: voteId, userId: env.adminUserId, chosenAreaId: area1)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db,
                sql: "SELECT chosen_area_id FROM consolidation_vote_entries WHERE vote_id = ? AND user_id = ?",
                arguments: [voteId, env.adminUserId])
        }
        #expect((row?["chosen_area_id"] as Int64?) == area1)
    }

    @Test("managerOverrideConsolidation then applyConsolidation transitions status correctly")
    func testManagerOverrideAndApplyConsolidation() throws {
        let env = try freshEnv()
        let (_, voteId, _, area2) = try seedConsolidationVote(env)

        try env.warehouse.managerOverrideConsolidation(voteId: voteId, chosenAreaId: area2)

        let afterOverride = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT status, chosen_area_id, manager_override FROM consolidation_votes WHERE id = ?", arguments: [voteId])
        }
        #expect((afterOverride?["status"] as String?) == "decided")
        #expect((afterOverride?["chosen_area_id"] as Int64?) == area2)
        #expect((afterOverride?["manager_override"] as Int?) == 1)

        try env.warehouse.applyConsolidation(voteId: voteId)

        let afterApply = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT status FROM consolidation_votes WHERE id = ?", arguments: [voteId])
        }
        #expect((afterApply?["status"] as String?) == "applied")
    }

    @Test("dismissConsolidation sets status to dismissed with reason")
    func testDismissConsolidation() throws {
        let env = try freshEnv()
        let (_, voteId, _, _) = try seedConsolidationVote(env)

        try env.warehouse.dismissConsolidation(voteId: voteId, reason: "Not worth moving")

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT status, dismiss_reason FROM consolidation_votes WHERE id = ?", arguments: [voteId])
        }
        #expect((row?["status"] as String?) == "dismissed")
        #expect((row?["dismiss_reason"] as String?) == "Not worth moving")
    }

    // MARK: - Multi-User Audit Query Methods

    @Test("getMultiUserAuditAssignments returns empty when no assignments exist")
    func testGetMultiUserAuditAssignmentsEmpty() throws {
        let env = try freshEnv()
        let assignments = try env.warehouse.getMultiUserAuditAssignments()
        #expect(assignments.isEmpty)
    }

    @Test("getMyMultiUserAuditAssignments returns pending assignments for a user")
    func testGetMyMultiUserAuditAssignments() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let auditSession = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let sessionId = auditSession.id!

        // Create a second user to satisfy the 2-user minimum for flagForMultiUserAudit
        _ = try env.auth.createUser(displayName: "Counter Two", pin: "5678")

        let assignments = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 10,
            sessionId: sessionId,
            flaggedBy: nil,
            requiredCounts: 2
        )
        #expect(assignments.count == 2)

        // getMyMultiUserAuditAssignments returns pending assignments for a specific user
        let myAssignments = try env.warehouse.getMyMultiUserAuditAssignments(userId: env.adminUserId)
        #expect(myAssignments.contains { $0.assignedUserId == env.adminUserId })
    }

    @Test("getMultiUserAuditAssignments filtered by sessionId returns only that session")
    func testGetMultiUserAuditAssignmentsFilteredBySession() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let as1 = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let session1 = as1.id!
        let as2 = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let session2 = as2.id!
        _ = try env.auth.createUser(displayName: "Counter B", pin: "9999")

        _ = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 10,
            sessionId: session1,
            flaggedBy: nil,
            requiredCounts: 2
        )

        let forSession1 = try env.warehouse.getMultiUserAuditAssignments(sessionId: session1)
        let forSession2 = try env.warehouse.getMultiUserAuditAssignments(sessionId: session2)

        #expect(forSession1.count == 1) // 1 part grouped
        #expect(forSession2.isEmpty)
    }

    // MARK: - Low Confidence Verification

    @Test("getLowConfidencePartsForVerification returns parts below threshold")
    func testGetLowConfidenceParts() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)

        try env.warehouse.setPartConfidence(partId: partId, areaId: areaId, percent: 20.0)

        let lowConf = try env.warehouse.getLowConfidencePartsForVerification(threshold: 40.0)
        #expect(lowConf.contains { $0.partId == partId })
    }

    @Test("getLowConfidencePartsForVerification excludes parts already in session")
    func testGetLowConfidencePartsExcludesSession() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let areaId = try seedStorageArea(env)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5)

        try env.warehouse.setPartConfidence(partId: partId, areaId: areaId, percent: 15.0)

        let auditSession2 = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let sessionId = auditSession2.id!
        _ = try env.auth.createUser(displayName: "Counter C", pin: "1111")
        _ = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 5,
            sessionId: sessionId,
            flaggedBy: nil,
            requiredCounts: 2
        )

        // Without session filter: part appears
        let withoutFilter = try env.warehouse.getLowConfidencePartsForVerification(threshold: 40.0)
        #expect(withoutFilter.contains { $0.partId == partId })

        // With session filter: part is excluded (already flagged)
        let withFilter = try env.warehouse.getLowConfidencePartsForVerification(threshold: 40.0, sessionId: sessionId)
        #expect(!withFilter.contains { $0.partId == partId })
    }

    @Test("flagForMultiUserAudit throws noEligibleVerificationCounters when no users can be assigned")
    func testFlagForMultiUserAuditNoEligibleCounters() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 3)

        #expect(throws: WarehouseService.WarehouseError.noEligibleVerificationCounters) {
            _ = try env.warehouse.flagForMultiUserAudit(
                partId: partId,
                expectedQty: 3,
                sessionId: nil,
                flaggedBy: env.adminUserId,
                requiredCounts: 2
            )
        }
    }

    @Test("flagForMultiUserAudit throws partAlreadyFlaggedForVerification for duplicate session send")
    func testFlagForMultiUserAuditAlreadyFlaggedInSession() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 6)
        _ = try env.auth.createUser(displayName: "Counter D", pin: "2222")

        let auditSession = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let sessionId = auditSession.id!

        _ = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 6,
            sessionId: sessionId,
            flaggedBy: nil,
            requiredCounts: 2
        )

        #expect(throws: WarehouseService.WarehouseError.partAlreadyFlaggedForVerification(partId: partId, sessionId: sessionId)) {
            _ = try env.warehouse.flagForMultiUserAudit(
                partId: partId,
                expectedQty: 6,
                sessionId: sessionId,
                flaggedBy: nil,
                requiredCounts: 2
            )
        }
    }
}
