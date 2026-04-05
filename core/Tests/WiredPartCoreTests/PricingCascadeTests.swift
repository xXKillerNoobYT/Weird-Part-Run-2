import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("Pricing Cascade Tests")
struct PricingCascadeTests {

    // MARK: - Helpers

    private func setUpWithColor() throws -> (E2ETestHelpers.TestEnvironment, Int64, Int64, Int64) {
        let env = try E2ETestHelpers.setUp()
        let (_, styleId, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Red", hexCode: "#FF0000")
        try env.parts.linkTypeToColor(typeId: typeId, colorId: colorId)
        return (env, typeId, colorId, styleId)
    }

    // MARK: - Test 1: Set Type Price

    @Test("Set type default price and verify getEffectivePrice returns it for a linked color")
    func testSetTypePrice() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()

        // Set type default cost
        try env.parts.setPriceForType(typeId: typeId, unitCost: 4.25)

        // Verify effective price resolves to type default
        let resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        #expect(resolved.effectiveCost == 4.25)
        #expect(resolved.source == "type")
        #expect(resolved.typeDefaultCost == 4.25)
        #expect(resolved.colorOverrideCost == nil)
        #expect(resolved.supplierCost == nil)
    }

    // MARK: - Test 2: Color Override

    @Test("Color override wins over type default")
    func testColorOverride() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()

        // Set type default
        try env.parts.setPriceForType(typeId: typeId, unitCost: 4.25)

        // Set color override
        try env.parts.setPriceForColor(colorId: colorId, unitCost: 5.50)

        // Verify color override wins
        let resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        #expect(resolved.effectiveCost == 5.50)
        #expect(resolved.source == "color")
        #expect(resolved.typeDefaultCost == 4.25)
        #expect(resolved.colorOverrideCost == 5.50)
    }

    // MARK: - Test 3: Supplier Cost Override

    @Test("Supplier cost overrides both type default and color override")
    func testSupplierCostOverride() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "ElecSupply")

        // Set all three levels
        try env.parts.setPriceForType(typeId: typeId, unitCost: 4.25)
        try env.parts.setPriceForColor(colorId: colorId, unitCost: 5.50)
        try env.parts.setSupplierCostForColor(colorId: colorId, supplierId: supplierId, cost: 3.75)

        // Verify supplier cost wins when supplierId is provided
        let resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId, supplierId: supplierId)
        #expect(resolved.effectiveCost == 3.75)
        #expect(resolved.source == "supplier")
        #expect(resolved.typeDefaultCost == 4.25)
        #expect(resolved.colorOverrideCost == 5.50)
        #expect(resolved.supplierCost == 3.75)

        // Without supplierId, color override still wins
        let noSupplier = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        #expect(noSupplier.effectiveCost == 5.50)
        #expect(noSupplier.source == "color")
    }

    // MARK: - Test 4: Cascade Fallback

    @Test("Only type price set — color and supplier queries fall back to type default")
    func testCascadeFallback() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "FallbackSupplier")

        // Only set type default — no color override, no supplier cost
        try env.parts.setPriceForType(typeId: typeId, unitCost: 7.99)

        // Query with supplierId — should fall back to type default (no supplier cost set)
        let withSupplier = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId, supplierId: supplierId)
        #expect(withSupplier.effectiveCost == 7.99)
        #expect(withSupplier.source == "type")
        #expect(withSupplier.supplierCost == nil)
        #expect(withSupplier.colorOverrideCost == nil)

        // Query without typeId — should auto-discover via type_color_links
        let autoDiscover = try env.parts.getEffectivePrice(colorId: colorId)
        #expect(autoDiscover.effectiveCost == 7.99)
        #expect(autoDiscover.source == "type")
    }

    // MARK: - Additional: Clear Color Override

    @Test("Clearing color override reverts to type default")
    func testClearColorOverride() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()

        try env.parts.setPriceForType(typeId: typeId, unitCost: 4.25)
        try env.parts.setPriceForColor(colorId: colorId, unitCost: 5.50)

        // Color override wins
        var resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        #expect(resolved.effectiveCost == 5.50)
        #expect(resolved.source == "color")

        // Clear the override
        try env.parts.setPriceForColor(colorId: colorId, unitCost: nil)

        // Now falls back to type default
        resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        #expect(resolved.effectiveCost == 4.25)
        #expect(resolved.source == "type")
        #expect(resolved.colorOverrideCost == nil)
    }

    // MARK: - Additional: Supplier Costs List

    @Test("getColorSupplierCosts returns all suppliers for a color")
    func testColorSupplierCostsList() throws {
        let (env, _, colorId, _) = try setUpWithColor()
        let sup1 = try E2ETestHelpers.seedSupplier(env, name: "Supplier A")
        let sup2 = try env.parts.createSupplier(name: "Supplier B", email: "b@test.com")

        try env.parts.setSupplierCostForColor(colorId: colorId, supplierId: sup1, cost: 3.00, notes: "Bulk rate")
        try env.parts.setSupplierCostForColor(colorId: colorId, supplierId: sup2, cost: 4.00)

        let costs = try env.parts.getColorSupplierCosts(colorId: colorId)
        #expect(costs.count == 2)

        let costA = costs.first(where: { $0.supplierName == "Supplier A" })
        #expect(costA?.cost == 3.00)
        #expect(costA?.notes == "Bulk rate")

        let costB = costs.first(where: { $0.supplierName == "Supplier B" })
        #expect(costB?.cost == 4.00)
    }

    // MARK: - Additional: Remove Supplier Cost

    @Test("Remove supplier cost and verify fallback")
    func testRemoveSupplierCost() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "RemoveMe")

        try env.parts.setPriceForType(typeId: typeId, unitCost: 4.25)
        try env.parts.setSupplierCostForColor(colorId: colorId, supplierId: supplierId, cost: 2.00)

        // Supplier cost wins
        var resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId, supplierId: supplierId)
        #expect(resolved.effectiveCost == 2.00)
        #expect(resolved.source == "supplier")

        // Remove supplier cost
        try env.parts.removeSupplierCostForColor(colorId: colorId, supplierId: supplierId)

        // Falls back to type default
        resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId, supplierId: supplierId)
        #expect(resolved.effectiveCost == 4.25)
        #expect(resolved.source == "type")
        #expect(resolved.supplierCost == nil)
    }

    // MARK: - Edge: No Price Set

    @Test("No price set at any level returns nil effective cost")
    func testNoPriceSet() throws {
        let (env, typeId, colorId, _) = try setUpWithColor()

        let resolved = try env.parts.getEffectivePrice(colorId: colorId, typeId: typeId)
        #expect(resolved.effectiveCost == nil)
        #expect(resolved.source == "none")
    }
}
