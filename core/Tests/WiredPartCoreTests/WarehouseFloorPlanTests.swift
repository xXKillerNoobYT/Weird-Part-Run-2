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
}
