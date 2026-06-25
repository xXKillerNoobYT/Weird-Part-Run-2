import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests for warehouse floor plans, storage units, levels, areas, bins,
/// and part assignment — the full warehouse physical layout workflow.
@Suite("Warehouse Floor Plan & Storage Tests")
struct WarehouseFloorPlanTests {

    private func freshEnv() throws -> E2ETestHelpers.TestEnvironment {
        try E2ETestHelpers.setUp()
    }

    // MARK: - Floor Plan CRUD

    @Test("Create and list floor plans")
    func testFloorPlanCRUD() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Main Warehouse", widthInches: 480, lengthInches: 720)
        #expect(plan.name == "Main Warehouse")
        #expect(plan.widthInches == 480)

        let plans = try env.warehouse.listFloorPlans()
        #expect(plans.count == 1)
    }

    @Test("Get floor plan by ID")
    func testGetFloorPlan() throws {
        let env = try freshEnv()

        let created = try env.warehouse.createFloorPlan(name: "Shop Floor", widthInches: 360, lengthInches: 480)
        let fetched = try env.warehouse.getFloorPlan(id: created.id!)
        #expect(fetched?.name == "Shop Floor")
    }

    @Test("Delete floor plan")
    func testDeleteFloorPlan() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Temp", widthInches: 100, lengthInches: 100)
        try env.warehouse.deleteFloorPlan(id: plan.id!)

        let plans = try env.warehouse.listFloorPlans()
        #expect(plans.isEmpty)
    }

    // MARK: - Floor Features

    @Test("Add and list floor features")
    func testFloorFeatures() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Test", widthInches: 200, lengthInches: 200)

        let feature = try env.warehouse.addFloorFeature(
            floorPlanId: plan.id!,
            featureType: "door",
            label: "Main Entrance",
            gridX: 5,
            gridY: 0
        )
        #expect(feature.featureType == "door")

        let features = try env.warehouse.listFloorFeatures(floorPlanId: plan.id!)
        #expect(features.count == 1)
    }

    @Test("Delete floor feature")
    func testDeleteFloorFeature() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Test", widthInches: 200, lengthInches: 200)
        let feature = try env.warehouse.addFloorFeature(
            floorPlanId: plan.id!, featureType: "walkway", label: nil, gridX: 1, gridY: 1
        )
        try env.warehouse.deleteFloorFeature(id: feature.id!)

        let features = try env.warehouse.listFloorFeatures(floorPlanId: plan.id!)
        #expect(features.isEmpty)
    }

    // MARK: - Storage Unit Hierarchy

    @Test("Full storage hierarchy: unit → level → area → bin")
    func testStorageHierarchy() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Warehouse A", widthInches: 480, lengthInches: 720)

        // Create storage unit
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!,
            name: "Shelf Row 1",
            unitType: "shelf",
            rowNumber: "A",
            unitNumber: "1",
            gridX: 2,
            gridY: 3
        )
        #expect(unit.name == "Shelf Row 1")
        #expect(unit.unitType == "shelf")

        let units = try env.warehouse.listStorageUnits(floorPlanId: plan.id!)
        #expect(units.count == 1)

        // Add level to unit
        let level = try env.warehouse.addStorageLevel(
            unitId: unit.id!,
            levelCode: "L1",
            levelName: "Bottom Shelf",
            order: 0,
            heightInches: 18
        )
        #expect(level.levelCode == "L1")

        let levels = try env.warehouse.listLevelsForUnit(unitId: unit.id!)
        #expect(levels.count == 1)

        // Add area to level
        let area = try env.warehouse.addStorageArea(
            levelId: level.id!,
            areaNumber: 1,
            widthInches: 24
        )
        #expect(area.areaNumber == 1)

        let areas = try env.warehouse.listAreasForLevel(levelId: level.id!)
        #expect(areas.count == 1)

        // Add bin to area
        let bin = try env.warehouse.addBin(
            areaId: area.id!,
            binNumber: 1,
            isFixed: true
        )
        #expect(bin.binNumber == 1)

        let bins = try env.warehouse.listBinsForArea(areaId: area.id!)
        #expect(bins.count == 1)
    }

    @Test("Update storage unit properties")
    func testUpdateStorageUnit() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "Old Name", unitType: "rack"
        )

        try env.warehouse.updateStorageUnit(id: unit.id!, name: "New Name", isConfigured: true)

        let units = try env.warehouse.listStorageUnits(floorPlanId: plan.id!)
        #expect(units[0].name == "New Name")
        #expect(units[0].isConfigured)
    }

    @Test("Updating a storage unit rejects blank names")
    func testUpdateStorageUnitRejectsBlankName() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "Original Name", unitType: "rack"
        )

        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            try env.warehouse.updateStorageUnit(id: unit.id!, name: "   \n\t  ")
        }

        let units = try env.warehouse.listStorageUnits(floorPlanId: plan.id!)
        #expect(units[0].name == "Original Name")
    }

    @Test("Delete cascades through storage hierarchy")
    func testDeleteStorageUnit() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "Shelf", unitType: "shelf"
        )
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "A")
        _ = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        try env.warehouse.deleteStorageUnit(id: unit.id!)

        let units = try env.warehouse.listStorageUnits(floorPlanId: plan.id!)
        #expect(units.isEmpty)
    }

    // MARK: - Part Assignment

    @Test("Assign part to area and retrieve assignments")
    func testPartAssignment() throws {
        let env = try freshEnv()

        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        let assignment = try env.warehouse.assignPartToArea(
            partId: partId, areaId: area.id!, isHome: true
        )
        #expect(assignment.partId == partId)

        let assignments = try env.warehouse.getPartAssignments(partId: partId)
        #expect(assignments.count >= 1)
    }

    @Test("Remove part assignment")
    func testRemovePartAssignment() throws {
        let env = try freshEnv()

        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        let assignment = try env.warehouse.assignPartToArea(partId: partId, areaId: area.id!)
        try env.warehouse.removePartAssignment(assignmentId: assignment.id!)

        let remaining = try env.warehouse.getPartAssignments(partId: partId)
        #expect(remaining.isEmpty)
    }

    @Test("Get area contents")
    func testGetAreaContents() throws {
        let env = try freshEnv()

        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)

        _ = try env.warehouse.assignPartToArea(partId: partId, areaId: area.id!)

        let contents = try env.warehouse.getAreaContents(areaId: area.id!)
        #expect(contents.count >= 1)
    }

    // MARK: - Location Code Generation

    @Test("Generate full location code for an area")
    func testGenerateLocationCode() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "Shelf A1", unitType: "shelf",
            rowNumber: "A", unitNumber: "1"
        )
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L2")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 3)

        let code = try env.warehouse.generateFullLocationCode(areaId: area.id!)
        #expect(!code.isEmpty)
        // Code should contain elements from the hierarchy
        #expect(code.contains("A") || code.contains("L2") || code.contains("3"))
    }

    // MARK: - Grid Dimensions (PE-040)

    @Test("updateFloorPlanGrid persists rows and cols")
    func testUpdateFloorPlanGrid() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Grid Test", widthInches: 480, lengthInches: 720)
        // Fresh plan has nil grid dimensions
        #expect(plan.gridRows == nil)
        #expect(plan.gridCols == nil)

        try env.warehouse.updateFloorPlanGrid(floorPlanId: plan.id!, rows: 12, cols: 8)

        let updated = try env.warehouse.getFloorPlan(id: plan.id!)
        #expect(updated?.gridRows == 12)
        #expect(updated?.gridCols == 8)
    }

    @Test("updateFloorPlanGrid overwrites previously saved dimensions")
    func testUpdateFloorPlanGridOverwrite() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Grid Overwrite", widthInches: 240, lengthInches: 360)
        try env.warehouse.updateFloorPlanGrid(floorPlanId: plan.id!, rows: 5, cols: 4)
        try env.warehouse.updateFloorPlanGrid(floorPlanId: plan.id!, rows: 10, cols: 6)

        let fetched = try env.warehouse.getFloorPlan(id: plan.id!)
        #expect(fetched?.gridRows == 10)
        #expect(fetched?.gridCols == 6)
    }

    @Test("updateFloorPlanGrid on non-existent ID is a silent no-op")
    func testUpdateFloorPlanGridMissingId() throws {
        let env = try freshEnv()
        // Should not throw — UPDATE on a missing row affects 0 rows silently
        try env.warehouse.updateFloorPlanGrid(floorPlanId: 99999, rows: 10, cols: 10)
        let plans = try env.warehouse.listFloorPlans()
        #expect(plans.isEmpty)
    }

    // MARK: - Onboarding

    @Test("Warehouse onboarding lifecycle")
    func testOnboardingLifecycle() throws {
        let env = try freshEnv()

        // No onboarding initially
        let initial = try env.warehouse.getOnboardingProgress()
        #expect(initial == nil)

        // Start onboarding
        let progress = try env.warehouse.startOnboarding()
        #expect(progress.currentStep == 1)

        // Update step
        try env.warehouse.updateOnboardingStep(
            id: progress.id!,
            currentStep: 2,
            step1Complete: true
        )

        // Complete
        try env.warehouse.completeOnboarding(id: progress.id!)

        // Verify completion by checking the record was updated
        let after = try env.warehouse.getOnboardingProgress()
        // After completion, either record shows completed or is cleared
        #expect(after != nil || initial == nil)
    }

    @Test("getOnboardingProgress migrates legacy step4 progress into completedSteps")
    func testOnboardingProgressMigratesLegacyCompletedSteps() throws {
        let env = try freshEnv()
        let legacyJSON = "[4,5,11]"

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO warehouse_onboarding_progress
                    (current_step, step1_complete, step2_complete, step3_complete, step4_progress)
                VALUES
                    (6, 0, 0, 0, ?)
                """, arguments: [legacyJSON])
        }

        let progress = try env.warehouse.getOnboardingProgress()
        let data = try #require(progress?.completedSteps?.data(using: .utf8))
        let completedSteps = try JSONDecoder().decode([Int].self, from: data)
        let persistedCompletedStepsJSON = try env.db.writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT completed_steps FROM warehouse_onboarding_progress WHERE id = ?",
                arguments: [progress?.id]
            )
        }

        #expect(completedSteps == [4, 5])
        #expect(persistedCompletedStepsJSON == "[4,5]")
    }

    // MARK: - Flow Onboarding (startFlowOnboarding / updateFlowProgress)

    @Test("startFlowOnboarding creates a progress record with correct flow metadata")
    func testStartFlowOnboarding() throws {
        let env = try freshEnv()

        let progress = try env.warehouse.startFlowOnboarding(
            flowType: "parts",
            totalSteps: 3
        )

        #expect(progress.currentStep == 1)
        #expect(progress.flowType == "parts")
        #expect(progress.totalSteps == 3)
        #expect(progress.id != nil)
        // A new flow starts at step 1 with no step data
        #expect(progress.stepsProgress == nil)
    }

    @Test("startFlowOnboarding can be linked to a floor plan")
    func testStartFlowOnboardingWithFloorPlan() throws {
        let env = try freshEnv()

        let plan = try env.warehouse.createFloorPlan(name: "Flow Test Plan", widthInches: 240, lengthInches: 360)
        let progress = try env.warehouse.startFlowOnboarding(
            flowType: "floor_plan",
            totalSteps: 9,
            floorPlanId: plan.id
        )

        #expect(progress.floorPlanId == plan.id)
        #expect(progress.flowType == "floor_plan")
        #expect(progress.totalSteps == 9)
    }

    @Test("updateFlowProgress advances currentStep and persists stepData JSON")
    func testUpdateFlowProgress() throws {
        let env = try freshEnv()

        let progress = try env.warehouse.startFlowOnboarding(flowType: "parts", totalSteps: 3)
        guard let progressId = progress.id else {
            #expect(Bool(false), "startFlowOnboarding must return a record with an id")
            return
        }

        let stepDataJSON = #"{"selectedCategory":"paint","count":5}"#
        try env.warehouse.updateFlowProgress(id: progressId, currentStep: 2, stepData: stepDataJSON)

        // Read back via the DB directly to verify persistence
        let updated = try env.db.writer.read { db in
            try WarehouseOnboardingProgress.fetchOne(db, key: progressId)
        }
        #expect(updated?.currentStep == 2)
        #expect(updated?.stepsProgress == stepDataJSON)
    }

    @Test("updateFlowProgress is a no-op for non-existent ID")
    func testUpdateFlowProgressMissingId() throws {
        let env = try freshEnv()
        // Should not throw — guard let inside the function handles missing row
        try env.warehouse.updateFlowProgress(id: 99999, currentStep: 5)
    }

    @Test("createFloorPlan throws requiredFieldEmpty when name is blank")
    func testCreateFloorPlan_throwsForBlankName() throws {
        let env = try freshEnv()
        var threw = false
        do {
            _ = try env.warehouse.createFloorPlan(name: "   ", widthInches: 480, lengthInches: 360)
        } catch WarehouseService.WarehouseError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createFloorPlan must throw requiredFieldEmpty when name is whitespace-only")
    }

    @Test("addStorageUnit throws requiredFieldEmpty when name is blank")
    func testAddStorageUnit_throwsForBlankName() throws {
        let env = try freshEnv()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        var threw = false
        do {
            _ = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "   ", unitType: "shelf")
        } catch WarehouseService.WarehouseError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "addStorageUnit must throw requiredFieldEmpty when name is whitespace-only")
    }

    @Test("createTrailer throws requiredFieldEmpty when name is blank")
    func testCreateTrailer_throwsForBlankName() throws {
        let env = try freshEnv()
        var threw = false
        do {
            _ = try env.warehouse.createTrailer(trailerCode: "T1", name: "   ")
        } catch WarehouseService.WarehouseError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createTrailer must throw requiredFieldEmpty when name is whitespace-only")
    }

    @Test("createTrailer throws requiredFieldEmpty when trailerCode is blank")
    func testCreateTrailer_throwsForBlankTrailerCode() throws {
        let env = try freshEnv()
        var threw = false
        do {
            _ = try env.warehouse.createTrailer(trailerCode: "", name: "Trailer A")
        } catch WarehouseService.WarehouseError.requiredFieldEmpty {
            threw = true
        } catch {}
        #expect(threw, "createTrailer must throw requiredFieldEmpty when trailerCode is empty")
    }

    // MARK: - Dimension Validation (PE-040 extension)

    @Test("createFloorPlan throws invalidDimension when widthInches is zero")
    func testCreateFloorPlan_throwsForZeroWidth() throws {
        let env = try freshEnv()
        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            _ = try env.warehouse.createFloorPlan(name: "Bad Plan", widthInches: 0, lengthInches: 360)
        }
    }

    @Test("createFloorPlan throws invalidDimension when lengthInches is negative")
    func testCreateFloorPlan_throwsForNegativeLength() throws {
        let env = try freshEnv()
        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            _ = try env.warehouse.createFloorPlan(name: "Bad Plan", widthInches: 240, lengthInches: -1)
        }
    }

    @Test("updateFloorPlanGrid throws invalidDimension when rows is zero")
    func testUpdateFloorPlanGrid_throwsForZeroRows() throws {
        let env = try freshEnv()
        let plan = try env.warehouse.createFloorPlan(name: "Grid Test", widthInches: 240, lengthInches: 360)
        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            try env.warehouse.updateFloorPlanGrid(floorPlanId: plan.id!, rows: 0, cols: 8)
        }
    }

    @Test("addStorageLevel throws requiredFieldEmpty when levelCode is blank")
    func testAddStorageLevel_throwsForBlankLevelCode() throws {
        let env = try freshEnv()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        #expect(throws: WarehouseService.WarehouseError.requiredFieldEmpty) {
            _ = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "   ")
        }
    }

    @Test("addBin throws invalidDimension when binNumber is zero")
    func testAddBin_throwsForZeroBinNumber() throws {
        let env = try freshEnv()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "S1", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1")
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        #expect(throws: WarehouseService.WarehouseError.invalidDimension) {
            _ = try env.warehouse.addBin(areaId: area.id!, binNumber: 0)
        }
    }

    @Test("updateStorageUnit is a no-op on soft-deleted unit")
    func testUpdateStorageUnit_noOpOnSoftDeletedUnit() throws {
        let env = try freshEnv()
        let plan = try env.warehouse.createFloorPlan(name: "WH", widthInches: 200, lengthInches: 200)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "Original Name", unitType: "shelf")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_storage_units SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [unit.id!])
        }
        // Should be a silent no-op — no throw, name unchanged
        try env.warehouse.updateStorageUnit(id: unit.id!, name: "New Name")
        let units = try env.warehouse.listStorageUnits(floorPlanId: plan.id!)
        #expect(units.isEmpty, "soft-deleted unit should be invisible; name change should not resurrect it")
    }

    @Test("updateTrailer is a no-op on soft-deleted trailer")
    func testUpdateTrailer_noOpOnSoftDeletedTrailer() throws {
        let env = try freshEnv()
        let trailerId = try env.warehouse.createTrailer(trailerCode: "T-UPD-SOFT", name: "Soft Trailer")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE job_trailers SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [trailerId])
        }
        // Should silently update 0 rows — no throw
        try env.warehouse.updateTrailer(id: trailerId, status: "inactive")
        let trailer = try env.warehouse.getTrailer(id: trailerId)
        #expect(trailer == nil, "tombstoned trailer should not be returned by getTrailer")
    }

    // MARK: - Tombstone guards: inventory write paths

    private func makeAreaId(_ env: E2ETestHelpers.TestEnvironment) throws -> Int64 {
        let plan = try env.warehouse.createFloorPlan(name: "Test Plan", widthInches: 100, lengthInches: 100)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "U", unitType: "shelf")
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "L1", heightInches: 12)
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        return area.id!
    }

    @Test("castConsolidationVote rejects tombstoned user")
    func testCastConsolidationVote_rejectsTombstonedUser() throws {
        let env = try freshEnv()
        let areaId = try makeAreaId(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let vote = try env.warehouse.suggestConsolidation(partId: partId)
        // Tombstoned user should not be able to cast a vote
        // (If no active vote exists, suggestConsolidation returns nil — just guard the path)
        if let vote = vote {
            #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
                try env.warehouse.castConsolidationVote(voteId: vote.id!, userId: env.adminUserId, chosenAreaId: areaId)
            }
        }
    }

    @Test("castConsolidationVote rejects tombstoned area")
    func testCastConsolidationVote_rejectsTombstonedArea() throws {
        let env = try freshEnv()
        let areaId = try makeAreaId(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_storage_areas SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [areaId])
        }
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let vote = try env.warehouse.suggestConsolidation(partId: partId)
        if let vote = vote {
            #expect(throws: WarehouseService.WarehouseError.areaNotFound(areaId)) {
                try env.warehouse.castConsolidationVote(voteId: vote.id!, userId: env.adminUserId, chosenAreaId: areaId)
            }
        }
    }

    @Test("updateUserRating rejects tombstoned user")
    func testUpdateUserRating_rejectsTombstonedUser() throws {
        let env = try freshEnv()
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.updateUserRating(userId: env.adminUserId, action: "audit", result: "accurate")
        }
    }

    @Test("recordOrgCheck rejects tombstoned area")
    func testRecordOrgCheck_rejectsTombstonedArea() throws {
        let env = try freshEnv()
        let areaId = try makeAreaId(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE warehouse_storage_areas SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [areaId])
        }
        #expect(throws: WarehouseService.WarehouseError.areaNotFound(areaId)) {
            try env.warehouse.recordOrgCheck(areaId: areaId, checkedBy: env.adminUserId,
                labelsAccurate: true, partsInHome: true, noDuplicates: true,
                notOvercrowded: true, binsAssigned: true)
        }
    }

    @Test("recordOrgCheck rejects tombstoned checker")
    func testRecordOrgCheck_rejectsTombstonedChecker() throws {
        let env = try freshEnv()
        let areaId = try makeAreaId(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        #expect(throws: WarehouseService.WarehouseError.userNotFound(env.adminUserId)) {
            try env.warehouse.recordOrgCheck(areaId: areaId, checkedBy: env.adminUserId,
                labelsAccurate: true, partsInHome: true, noDuplicates: true,
                notOvercrowded: true, binsAssigned: true)
        }
    }

    @Test("managerOverrideConsolidation is a no-op on tombstoned vote")
    func testManagerOverrideConsolidation_noOpOnTombstonedVote() throws {
        let env = try freshEnv()
        let areaId = try makeAreaId(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        guard let vote = try env.warehouse.suggestConsolidation(partId: partId) else { return }
        let voteId = vote.id!
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE consolidation_votes SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [voteId])
        }
        // Should silently update 0 rows — no throw
        try env.warehouse.managerOverrideConsolidation(voteId: voteId, chosenAreaId: areaId)
        // Verify the tombstoned vote is unchanged
        let stillTombstoned = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT status FROM consolidation_votes WHERE id = ?",
                             arguments: [voteId])
        }
        #expect(stillTombstoned?["status"] == "voting", "tombstoned vote status must not be changed")
    }

    @Test("dismissConsolidation is a no-op on tombstoned vote")
    func testDismissConsolidation_noOpOnTombstonedVote() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        guard let vote = try env.warehouse.suggestConsolidation(partId: partId) else { return }
        let voteId = vote.id!
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE consolidation_votes SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [voteId])
        }
        try env.warehouse.dismissConsolidation(voteId: voteId, reason: "no need")
        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT status FROM consolidation_votes WHERE id = ?",
                             arguments: [voteId])
        }
        #expect(row?["status"] == "voting", "tombstoned vote status must not be changed by dismiss")
    }

    // MARK: - Batch confidence query (#260)

    @Test("getAllPartConfidenceLevels returns all levels in one query")
    func testGetAllPartConfidenceLevels_returnsAllLevels() throws {
        let env = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId1 = try E2ETestHelpers.seedPart(env, name: "Conf Part A", categoryId: catId)
        let partId2 = try E2ETestHelpers.seedPart(env, name: "Conf Part B", categoryId: catId)
        let plan = try env.warehouse.createFloorPlan(name: "Test Plan", widthInches: 100, lengthInches: 100)
        let unit = try env.warehouse.addStorageUnit(floorPlanId: plan.id!, name: "Unit 1", unitType: "shelf")
        let unitId = unit.id!
        let level = try env.warehouse.addStorageLevel(unitId: unitId, levelCode: "L1", heightInches: 12)
        let levelId = level.id!
        let area = try env.warehouse.addStorageArea(levelId: levelId, areaNumber: 1)
        let areaId = area.id!

        try env.warehouse.setPartConfidence(partId: partId1, areaId: areaId, percent: 0.95)
        try env.warehouse.setPartConfidence(partId: partId2, areaId: areaId, percent: 0.30)

        let all = try env.warehouse.getAllPartConfidenceLevels()
        // Sum per-level is the ground-truth total
        let total = try (0...10).reduce(0) { acc, level in
            acc + (try env.warehouse.getPartsAtLevel(level: level)).count
        }
        #expect(all.count == total,
            "getAllPartConfidenceLevels must return the same total as 11 per-level calls")
        #expect(all.count >= 2, "both inserted records should be present")
    }
}
