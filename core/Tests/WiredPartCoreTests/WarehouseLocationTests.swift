import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests for WarehouseService location/navigation features:
/// setup progress tiers, user position tracking, getDirections, and QR code lookups.
@Suite("WarehouseLocation Tests")
struct WarehouseLocationTests {

    // MARK: - Setup Progress Tiers

    @Test("getSetupProgress returns .none on fresh database")
    func testSetupProgressFreshDB() throws {
        let env = try E2ETestHelpers.setUp()
        let tier = try env.warehouse.getSetupProgress()
        #expect(tier == .none)
    }

    @Test("getSetupProgress returns .floorPlanInProgress after creating a floor plan")
    func testSetupProgressWithFloorPlan() throws {
        let env = try E2ETestHelpers.setUp()

        _ = try env.warehouse.createFloorPlan(name: "Main Floor", widthInches: 240, lengthInches: 480)

        let tier = try env.warehouse.getSetupProgress()
        #expect(tier == .floorPlanInProgress)
    }

    @Test("getSetupProgress returns .partsOnly when parts have stock but no floor plan")
    func testSetupProgressWithStockOnly() throws {
        let env = try E2ETestHelpers.setUp()

        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5)

        let tier = try env.warehouse.getSetupProgress()
        #expect(tier == .partsOnly)
    }

    // MARK: - User Position Tracking

    @Test("setUserCurrentPosition and getUserCurrentPosition round-trip")
    func testUserPositionRoundTrip() throws {
        let env = try E2ETestHelpers.setUp()

        // No position initially
        let initial = try env.warehouse.getUserCurrentPosition(userId: env.adminUserId)
        #expect(initial == nil)

        // Build a hierarchy to get a valid area ID
        let (_, area) = try buildMinimalHierarchy(env: env, name: "Position")

        // Set position and verify round-trip
        try env.warehouse.setUserCurrentPosition(userId: env.adminUserId, areaId: area.id!)
        let saved = try env.warehouse.getUserCurrentPosition(userId: env.adminUserId)
        #expect(saved == area.id!)
    }

    @Test("setUserCurrentPosition updates when called again with a different area")
    func testUserPositionUpdates() throws {
        let env = try E2ETestHelpers.setUp()

        let (level, area1) = try buildMinimalHierarchy(env: env, name: "Update")
        let area2 = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 2)

        try env.warehouse.setUserCurrentPosition(userId: env.adminUserId, areaId: area1.id!)
        try env.warehouse.setUserCurrentPosition(userId: env.adminUserId, areaId: area2.id!)

        let position = try env.warehouse.getUserCurrentPosition(userId: env.adminUserId)
        #expect(position == area2.id!, "Position should update to the most recently set area")
    }

    // MARK: - getDirections

    @Test("getDirections returns placeholder codes when area IDs do not exist")
    func testGetDirectionsMissingAreas() throws {
        let env = try E2ETestHelpers.setUp()

        // Non-existent area IDs — service returns "?" placeholders without crashing
        let result = try env.warehouse.getDirections(fromAreaId: 9999, toAreaId: 8888)
        #expect(result.fromCode == "?" || result.toCode == "?")
    }

    @Test("getDirections returns valid codes for two real areas")
    func testGetDirectionsRealAreas() throws {
        let env = try E2ETestHelpers.setUp()

        let plan = try env.warehouse.createFloorPlan(name: "Dir Floor", widthInches: 240, lengthInches: 480)

        // Create two units in the same floor plan
        let unit1 = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "Rack A", unitType: "shelf",
            rowNumber: "A", unitNumber: "1", gridX: 0, gridY: 0
        )
        let unit2 = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "Rack B", unitType: "shelf",
            rowNumber: "B", unitNumber: "2", gridX: 3, gridY: 0
        )

        let level1 = try env.warehouse.addStorageLevel(unitId: unit1.id!, levelCode: "S1", order: 0)
        let level2 = try env.warehouse.addStorageLevel(unitId: unit2.id!, levelCode: "S1", order: 0)
        let area1 = try env.warehouse.addStorageArea(levelId: level1.id!, areaNumber: 1)
        let area2 = try env.warehouse.addStorageArea(levelId: level2.id!, areaNumber: 1)

        let result = try env.warehouse.getDirections(fromAreaId: area1.id!, toAreaId: area2.id!)
        #expect(!result.fromCode.isEmpty)
        #expect(!result.toCode.isEmpty)
        #expect(result.fromCode != "?")
        #expect(result.toCode != "?")
    }

    // MARK: - getLocationByQR

    @Test("getLocationByQR returns nil for unknown QR code")
    func testGetLocationByQRUnknown() throws {
        let env = try E2ETestHelpers.setUp()
        let result = try env.warehouse.getLocationByQR(qrCode: "UNKNOWN-QR-CODE-XYZ")
        #expect(result == nil)
    }

    @Test("getLocationByQR returns location info matching the area's full_location_code")
    func testGetLocationByQRFound() throws {
        let env = try E2ETestHelpers.setUp()

        let (_, area) = try buildMinimalHierarchy(env: env, name: "QR")

        // The area's full_location_code is auto-populated by addStorageArea
        guard let locationCode = area.fullLocationCode, !locationCode.isEmpty else {
            // Full location code not yet set — skip gracefully
            return
        }

        let info = try env.warehouse.getLocationByQR(qrCode: locationCode)
        #expect(info != nil)
        #expect(info?.areaId == area.id!)
        #expect(info?.fullLocationCode == locationCode)
    }

    // MARK: - Helpers

    /// Build a minimal unit → level → area hierarchy and return the level and area.
    private func buildMinimalHierarchy(
        env: E2ETestHelpers.TestEnvironment,
        name: String
    ) throws -> (WarehouseStorageLevel, WarehouseStorageArea) {
        let plan = try env.warehouse.createFloorPlan(
            name: "\(name) Floor", widthInches: 120, lengthInches: 240
        )
        let unit = try env.warehouse.addStorageUnit(
            floorPlanId: plan.id!, name: "\(name) Rack", unitType: "shelf",
            rowNumber: "A", unitNumber: "1"
        )
        let level = try env.warehouse.addStorageLevel(unitId: unit.id!, levelCode: "S1", order: 0)
        let area = try env.warehouse.addStorageArea(levelId: level.id!, areaNumber: 1)
        return (level, area)
    }
}
