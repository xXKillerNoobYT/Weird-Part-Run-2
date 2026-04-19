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

    @Test("getRecentActivity shows Unknown Part and Unknown for soft-deleted part and user")
    func testGetRecentActivityHidesDeletedPartAndUser() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "RA_Cat")
        let partId = try E2ETestHelpers.seedPart(env, name: "RA_Part", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let activity = try env.warehouse.getRecentActivity()
        let entry = activity.first(where: { $0.description.contains("RA_Part") == false })
        let anyEntry = activity.first
        #expect(anyEntry != nil)
        #expect(anyEntry?.performedByName == "Unknown")
        #expect(anyEntry?.description.contains("Unknown Part") == true || anyEntry?.description.contains("RA_Part") == false)
    }

    @Test("getInventoryGrid shows nil categoryName for soft-deleted category")
    func testGetInventoryGridHidesDeletedCategoryName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DelCat_IG")
        let partId = try E2ETestHelpers.seedPart(env, name: "IG_Part", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 3)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE part_categories SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [catId])
        }
        let grid = try env.warehouse.getInventoryGrid(search: "IG_Part")
        #expect(grid.isEmpty == false)
        #expect(grid.first?.categoryName == nil)
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

    // MARK: - Multi-User Audit Consensus

    @Test("Multi-user audit: two counters agree → consensus resolves")
    func testMultiUserAuditConsensusAgree() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let session = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let sessionId = session.id!

        // Create a second user so flagForMultiUserAudit can assign 2 counters
        _ = try env.auth.createUser(displayName: "Counter2", pin: "5678")

        let assignments = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 10,
            sessionId: sessionId,
            flaggedBy: nil,
            requiredCounts: 2
        )
        guard assignments.count >= 2 else { return }

        // Both counters submit the same quantity
        try env.warehouse.submitMultiUserCount(assignmentId: assignments[0].id!, quantity: 10, userId: assignments[0].assignedUserId)
        try env.warehouse.submitMultiUserCount(assignmentId: assignments[1].id!, quantity: 10, userId: assignments[1].assignedUserId)

        let finalQty = try env.warehouse.resolveMultiUserAudit(partId: partId, sessionId: sessionId, resolvedBy: env.adminUserId)
        #expect(finalQty == 10)
    }

    @Test("Multi-user audit: two counters disagree → no consensus")
    func testMultiUserAuditConsensusDisagree() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let session = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let sessionId = session.id!

        _ = try env.auth.createUser(displayName: "Counter2", pin: "5678")

        let assignments = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 10,
            sessionId: sessionId,
            flaggedBy: nil,
            requiredCounts: 2
        )
        guard assignments.count >= 2 else { return }

        // Counters disagree
        try env.warehouse.submitMultiUserCount(assignmentId: assignments[0].id!, quantity: 8, userId: assignments[0].assignedUserId)
        try env.warehouse.submitMultiUserCount(assignmentId: assignments[1].id!, quantity: 12, userId: assignments[1].assignedUserId)

        let finalQty = try env.warehouse.resolveMultiUserAudit(partId: partId, sessionId: sessionId, resolvedBy: env.adminUserId)
        #expect(finalQty == nil)
    }

    @Test("Multi-user audit: fewer than 2 counted → no consensus")
    func testMultiUserAuditInsufficientCounts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let session = try env.warehouse.startAuditSession(startedBy: env.adminUserId)
        let sessionId = session.id!

        _ = try env.auth.createUser(displayName: "Counter2", pin: "5678")

        let assignments = try env.warehouse.flagForMultiUserAudit(
            partId: partId,
            expectedQty: 10,
            sessionId: sessionId,
            flaggedBy: nil,
            requiredCounts: 2
        )
        guard let first = assignments.first else { return }

        // Only one counter submits
        try env.warehouse.submitMultiUserCount(assignmentId: first.id!, quantity: 10, userId: first.assignedUserId)

        let finalQty = try env.warehouse.resolveMultiUserAudit(partId: partId, sessionId: sessionId, resolvedBy: env.adminUserId)
        #expect(finalQty == nil)
    }

    // MARK: - Zone & Progress Tests (PE-030)

    @Test("Zone CRUD lifecycle: create, list, update, delete")
    func testZoneCRUDLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        // Create a floor plan to host zones
        let fp = try env.warehouse.createFloorPlan(
            name: "Zone Test", widthInches: 480, lengthInches: 360
        )
        let fpId = fp.id!

        // Create a zone
        let zone = try env.warehouse.addZone(
            floorPlanId: fpId, zoneType: "staging", label: "Staging A",
            colorHex: "#FF6600", gridX: 0, gridY: 0, gridWidth: 5, gridHeight: 3
        )
        #expect(zone.id != nil)
        #expect(zone.zoneType == "staging")
        #expect(zone.label == "Staging A")

        // List zones
        let zones = try env.warehouse.listZones(floorPlanId: fpId)
        #expect(zones.count == 1)
        #expect(zones[0].colorHex == "#FF6600")

        // Update the zone
        try env.warehouse.updateZone(id: zone.id!, zoneType: "storage", label: "Storage B")
        let updated = try env.warehouse.listZones(floorPlanId: fpId)
        #expect(updated[0].zoneType == "storage")
        #expect(updated[0].label == "Storage B")

        // Delete the zone (soft delete)
        try env.warehouse.deleteZone(id: zone.id!)
        let afterDelete = try env.warehouse.listZones(floorPlanId: fpId)
        #expect(afterDelete.isEmpty)
    }

    @Test("Zone-unit relationship: assign unit to zone")
    func testZoneUnitRelationship() throws {
        let env = try E2ETestHelpers.setUp()

        let fp = try env.warehouse.createFloorPlan(
            name: "Zone Unit Test", widthInches: 600, lengthInches: 480
        )
        let fpId = fp.id!

        // Create a zone
        let zone = try env.warehouse.addZone(
            floorPlanId: fpId, zoneType: "storage", label: "Main Storage"
        )
        let zoneId = zone.id!

        // Create a storage unit (no zone initially)
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: fpId, name: "Rack A", unitType: "rack"
        )
        let unitId = unit.id!

        // Assign unit to zone via update
        try env.warehouse.updateStorageUnit(id: unitId, zoneId: zoneId)

        // Verify the unit has the zone
        let units = try env.warehouse.listStorageUnits(floorPlanId: fpId)
        let found = units.first(where: { $0.id == unitId })
        #expect(found?.zoneId == zoneId)
    }

    @Test("Setup tier detection returns correct tier for each state")
    func testSetupTierDetection() throws {
        let env = try E2ETestHelpers.setUp()

        // With no data, tier should be .none
        let tierNone = try env.warehouse.getSetupProgress()
        #expect(tierNone == .none)

        // Add a part with a shelf location → .partsOnly
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        try env.parts.updatePart(id: partId, shelfLocation: "A-1")
        let tierParts = try env.warehouse.getSetupProgress()
        #expect(tierParts == .partsOnly)

        // Create a floor plan → .floorPlanInProgress
        _ = try env.warehouse.createFloorPlan(
            name: "Test Plan", widthInches: 360, lengthInches: 240
        )
        let tierInProgress = try env.warehouse.getSetupProgress()
        #expect(tierInProgress == .floorPlanInProgress)

        // Complete onboarding → .complete
        let progress = try env.warehouse.startOnboarding()
        try env.warehouse.completeOnboarding(id: progress.id!)
        let tierComplete = try env.warehouse.getSetupProgress()
        #expect(tierComplete == .complete)
    }

    @Test("Flow onboarding progress: start, update steps, complete")
    func testFlowOnboardingProgress() throws {
        let env = try E2ETestHelpers.setUp()

        // Start a flow onboarding with 3 steps (parts flow)
        let progress = try env.warehouse.startFlowOnboarding(
            flowType: "parts_only", totalSteps: 3
        )
        #expect(progress.id != nil)
        #expect(progress.flowType == "parts_only")
        #expect(progress.totalSteps == 3)
        #expect(progress.currentStep == 1)

        // Update progress to step 2 with JSON data
        let stepData = "{\"step1\":{\"partsSelected\":[1,2,3]}}"
        try env.warehouse.updateFlowProgress(
            id: progress.id!, currentStep: 2, stepData: stepData
        )

        // Verify the progress was saved
        let fetched = try env.warehouse.getOnboardingProgress()
        #expect(fetched?.currentStep == 2)
        #expect(fetched?.stepsProgress == stepData)

        // Complete the flow
        try env.warehouse.completeOnboarding(id: progress.id!)
        let afterComplete = try env.warehouse.getOnboardingProgress()
        // getOnboardingProgress filters for completed_at == nil, so it should be nil
        #expect(afterComplete == nil)
    }

    @Test("getReceivingSession and getActiveSessions show Unknown for soft-deleted starter")
    func testReceivingSessionHidesDeletedUser() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "RecvSupplier")
        var sessionId: Int64 = 0
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status)
                VALUES ('PO-RECV-DEL', ?, 'submitted')
                """, arguments: [supplierId])
            let poId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO receiving_sessions (po_id, started_by, mode, status, created_at)
                VALUES (?, ?, 'packing_slip', 'in_progress', datetime('now'))
                """, arguments: [poId, env.adminUserId])
            sessionId = db.lastInsertedRowID
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let session = try env.warehouse.getReceivingSession(sessionId: sessionId)
        #expect(session != nil)
        #expect(session?.startedByName == "Unknown",
                "Soft-deleted starter must degrade to 'Unknown' in getReceivingSession")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = NULL WHERE id = ?",
                           arguments: [env.adminUserId])
        }
    }

    @Test("getSessionItems shows Unknown Part for soft-deleted part")
    func testGetSessionItemsHidesDeletedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "RecvCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "RecvPart", categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "RecvSupplier2")
        var sessionId: Int64 = 0
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status)
                VALUES ('PO-SI-DEL', ?, 'submitted')
                """, arguments: [supplierId])
            let poId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, qty_received, unit_cost)
                VALUES (?, ?, 3, 0, 9.99)
                """, arguments: [poId, partId])
            let lineId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO receiving_sessions (po_id, started_by, mode, status, created_at)
                VALUES (?, ?, 'packing_slip', 'in_progress', datetime('now'))
                """, arguments: [poId, env.adminUserId])
            sessionId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO receiving_session_items (session_id, po_line_id, expected_qty, created_at)
                VALUES (?, ?, 3, datetime('now'))
                """, arguments: [sessionId, lineId])
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let items = try env.warehouse.getSessionItems(sessionId: sessionId)
        #expect(items.isEmpty == false)
        #expect(items.first?.partName == "Unknown Part",
                "Soft-deleted part must degrade to 'Unknown Part' in getSessionItems")
    }

    @Test("getReturnItems shows Unknown Part and Unknown for soft-deleted part and user")
    func testGetReturnItemsHidesDeletedPartAndUser() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "RetCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "RetPart", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5)
        _ = try env.warehouse.processReturn(
            partId: partId, qty: 1,
            fromLocationType: "warehouse", fromLocationId: 1,
            performedBy: env.adminUserId
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let returns = try env.warehouse.getReturnItems(limit: 10)
        let entry = returns.first(where: { $0.partId == partId })
        #expect(entry != nil)
        #expect(entry?.partName == "Unknown Part",
                "Soft-deleted part must degrade to 'Unknown Part' in getReturnItems")
    }

    @Test("getAuditDiscrepancies shows Unknown Part for soft-deleted part")
    func testGetAuditDiscrepanciesHidesDeletedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "AudCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "AudPart", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE stock SET counted_qty = 8, last_counted = datetime('now')
                WHERE part_id = ? AND location_type = 'warehouse'
                """, arguments: [partId])
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let discrepancies = try env.warehouse.getAuditDiscrepancies()
        let entry = discrepancies.first(where: { $0.partId == partId })
        #expect(entry != nil)
        #expect(entry?.partName == "Unknown Part",
                "Soft-deleted part must degrade to 'Unknown Part' in getAuditDiscrepancies")
    }

    @Test("listTrailers and getTrailer show nil driver for soft-deleted user")
    func testTrailersHideDeletedDriverName() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.warehouse.createTrailer(trailerCode: "TR-DEL", name: "Del Trailer")
        try env.warehouse.updateTrailer(id: trailerId, assignedDriverUserId: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let list = try env.warehouse.listTrailers()
        let listed = list.first(where: { $0.id == trailerId })
        #expect(listed != nil)
        #expect(listed?.assignedDriverName == nil,
                "Soft-deleted driver must produce nil assignedDriverName in listTrailers")

        let detail = try env.warehouse.getTrailer(id: trailerId)
        #expect(detail?.assignedDriverName == nil,
                "Soft-deleted driver must produce nil assignedDriverName in getTrailer")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = NULL WHERE id = ?",
                           arguments: [env.adminUserId])
        }
    }

    @Test("getTrailerLocationHistory shows Unknown for soft-deleted recorder")
    func testTrailerLocationHistoryHidesDeletedRecorder() throws {
        let env = try E2ETestHelpers.setUp()
        let trailerId = try env.warehouse.createTrailer(trailerCode: "TR-LOC", name: "Loc Trailer")
        _ = try env.warehouse.recordTrailerLocation(
            trailerId: trailerId, recordedBy: env.adminUserId
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let history = try env.warehouse.getTrailerLocationHistory(trailerId: trailerId)
        #expect(history.isEmpty == false)
        let recorderName = history.first?["recorder_name"] as String?
        #expect(recorderName == "Unknown",
                "Soft-deleted recorder must degrade to 'Unknown' in getTrailerLocationHistory")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = NULL WHERE id = ?",
                           arguments: [env.adminUserId])
        }
    }

    @Test("listStagingBoxes shows nil jobName for soft-deleted job")
    func testListStagingBoxesHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-STG-DEL", name: "StagingDelJob")
        _ = try env.warehouse.createStagingBox(jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        let boxes = try env.warehouse.listStagingBoxes()
        let box = boxes.first(where: { $0.jobId == jobId })
        #expect(box != nil)
        #expect(box?.jobName == nil,
                "Soft-deleted job must produce nil jobName in listStagingBoxes")
    }
}
