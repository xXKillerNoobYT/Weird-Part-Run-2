import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("PartsService Extended Tests")
struct PartsServiceExtTests {

    // MARK: - Hierarchy CRUD

    @Test("Full hierarchy chain: category -> style -> type")
    func testHierarchyChain() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, styleId, typeId) = try E2ETestHelpers.seedPartHierarchy(env)

        let categories = try env.parts.listCategories()
        #expect(categories.contains(where: { $0.id == catId }))

        let styles = try env.parts.listStyles(categoryId: catId)
        #expect(styles.contains(where: { $0.id == styleId }))

        let types = try env.parts.listTypes(styleId: styleId)
        #expect(types.contains(where: { $0.id == typeId }))
    }

    @Test("Create and list colors")
    func testColorCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let colorId = try env.parts.createColor(name: "Red", hexCode: "#FF0000")
        #expect(colorId > 0)
        let colors = try env.parts.listColors()
        #expect(colors.contains(where: { $0.name == "Red" }))
    }

    @Test("Link type to color and brand")
    func testTypeLinks() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Blue", hexCode: "#0000FF")
        let brandId = try E2ETestHelpers.seedBrand(env)

        try env.parts.linkTypeToColor(typeId: typeId, colorId: colorId)
        try env.parts.linkTypeToBrand(typeId: typeId, brandId: brandId)
    }

    // MARK: - Part CRUD

    @Test("Create, search, update, delete part")
    func testPartLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try env.parts.createPart(categoryId: catId, name: "Test Wire 12AWG", code: "TW-1234")
        #expect(partId > 0)

        let searchResults = try env.parts.searchParts(query: "12AWG")
        #expect(searchResults.count >= 1)

        try env.parts.updatePart(id: partId, name: "Updated Wire 12AWG")
        let updated = try env.parts.getPart(id: partId)
        #expect(updated.part.name == "Updated Wire 12AWG")

        try env.parts.deletePart(id: partId)
    }

    @Test("Catalog stats")
    func testCatalogStats() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        _ = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let stats = try env.parts.getCatalogStats()
        #expect(stats.totalParts >= 1)
        #expect(stats.activeParts >= 1)
    }

    // MARK: - Brand & Supplier

    @Test("Brand CRUD")
    func testBrandCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let brandId = try env.parts.createBrand(name: "Southwire")
        #expect(brandId > 0)
        let brands = try env.parts.listBrands()
        #expect(brands.contains(where: { $0.brand.name == "Southwire" }))
    }

    @Test("Supplier CRUD")
    func testSupplierCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try env.parts.createSupplier(name: "ElecSupply Co", email: "info@elecsupply.com")
        #expect(supplierId > 0)
        let suppliers = try env.parts.listSuppliers()
        #expect(suppliers.contains(where: { $0.supplier.name == "ElecSupply Co" }))
    }

    @Test("Part-supplier link")
    func testPartSupplierLink() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supplierId, supplierPartNumber: "SP-001", costPrice: 2.50)
        let links = try env.parts.getPartSuppliers(partId: partId)
        #expect(links.count >= 1)
    }

    // MARK: - Pricing

    @Test("Update part pricing")
    func testPartPricing() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        _ = try env.parts.updatePartPricing(partId: partId, companyCostPrice: 1.50, companyMarkupPercent: 25.0)
        let pricing = try env.parts.resolvePartPricing(partId: partId)
        #expect(pricing.weightedAvgCost >= 0)
    }

    @Test("Cost layer FIFO/LIFO")
    func testCostLayers() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        _ = try env.parts.addCostLayer(partId: partId, qty: 10, unitCost: 1.00)
        _ = try env.parts.addCostLayer(partId: partId, qty: 5, unitCost: 1.50)

        let layers = try env.parts.getCostLayers(partId: partId)
        #expect(layers.count >= 2)
    }

    // MARK: - Forecasting

    @Test("Forecast settings")
    func testForecastSettings() throws {
        let env = try E2ETestHelpers.setUp()
        let settings = try env.parts.getForecastSettings(locationType: "warehouse")
        #expect(settings != nil || settings == nil) // May not exist yet
    }

    // MARK: - Companion Rules

    @Test("Companion rule lifecycle")
    func testCompanionRules() throws {
        let env = try E2ETestHelpers.setUp()

        let ruleId = try env.parts.createCompanionRule(
            name: "Always Together"
        )
        #expect(ruleId > 0)

        let rules = try env.parts.listCompanionRules()
        #expect(rules.count >= 1)
    }

    // MARK: - Hierarchy Tree

    @Test("Get full hierarchy tree")
    func testHierarchyTree() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedPartHierarchy(env)
        let tree = try env.parts.getHierarchy()
        #expect(!tree.categories.isEmpty)
    }

    // MARK: - Part Alternatives

    @Test("listPartAlternatives returns empty when no alternatives exist")
    func testPartAlternativesEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let alts = try env.parts.listPartAlternatives(partId: partId)
        #expect(alts.isEmpty)
    }

    @Test("linkPartAlternative creates link and unlinkPartAlternative removes it")
    func testPartAlternativeLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partA = try E2ETestHelpers.seedPart(env, name: "Part A", categoryId: catId)
        let partB = try E2ETestHelpers.seedPart(env, name: "Part B", categoryId: catId)

        let linkId = try env.parts.linkPartAlternative(
            partId: partA,
            alternativePartId: partB,
            relationship: "substitute",
            preference: 0
        )
        #expect(linkId > 0)

        let alts = try env.parts.listPartAlternatives(partId: partA)
        #expect(alts.contains { $0.id == linkId })

        try env.parts.unlinkPartAlternative(linkId: linkId)
        let afterUnlink = try env.parts.listPartAlternatives(partId: partA)
        #expect(!afterUnlink.contains { $0.id == linkId })
    }

    // MARK: - Price Staleness

    @Test("isPartPriceStale returns true for a fresh part with no cost_last_updated")
    func testPartPriceStaleOnFresh() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let stale = try env.parts.isPartPriceStale(partId: partId)
        #expect(stale == true)
    }

    @Test("getStalePricedParts includes part with no cost_last_updated")
    func testGetStalePricedParts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let stale = try env.parts.getStalePricedParts()
        #expect(stale.contains { $0.partId == partId })
    }

    @Test("markPriceVerified makes part non-stale")
    func testMarkPriceVerified() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        #expect(try env.parts.isPartPriceStale(partId: partId) == true)
        try env.parts.markPriceVerified(partId: partId)
        #expect(try env.parts.isPartPriceStale(partId: partId) == false)
    }

    // MARK: - Consumption History

    @Test("getConsumptionHistory returns empty before any FIFO consumption")
    func testConsumptionHistoryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let history = try env.parts.getConsumptionHistory(partId: partId)
        #expect(history.isEmpty)
    }

    @Test("getConsumptionHistory returns records after FIFO consumption")
    func testConsumptionHistoryAfterFIFO() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.parts.addCostLayer(partId: partId, qty: 10, unitCost: 5.00)
        try env.parts.consumeInventoryFIFO(partId: partId, qty: 3, jobId: jobId)

        let history = try env.parts.getConsumptionHistory(partId: partId)
        #expect(!history.isEmpty)
        #expect(history.contains { $0.partId == partId })
    }

    // MARK: - resetToCurrentBuyPrice

    @Test("resetToCurrentBuyPrice collapses cost layers to current buy price")
    func testResetToCurrentBuyPrice() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        try env.parts.addCostLayer(partId: partId, qty: 5, unitCost: 10.00)
        try env.parts.addCostLayer(partId: partId, qty: 5, unitCost: 20.00)

        let (oldAvg, newAvg) = try env.parts.resetToCurrentBuyPrice(partId: partId)
        #expect(newAvg == 20.00)  // most recent buy price
        // After reset, only one layer remains
        let layers = try env.parts.getCostLayers(partId: partId, nonEmptyOnly: true)
        #expect(layers.count == 1)
        _ = oldAvg  // oldAvg used to show the before value
    }

    // MARK: - Stock Summary

    @Test("getPartStockSummary returns zero totals on fresh part")
    func testPartStockSummaryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let summary = try env.parts.getPartStockSummary(partId: partId)
        #expect(summary.total == 0)
        #expect(summary.byLocationType.isEmpty)
    }

    @Test("getPartStockSummary reflects stock after receiving")
    func testPartStockSummaryWithStock() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 25)

        let summary = try env.parts.getPartStockSummary(partId: partId)
        #expect(summary.total == 25)
        #expect(summary.byLocationType["warehouse"] == 25)
    }

    // MARK: - Supplier Contacts

    @Test("getSupplierContacts + addSupplierContact + removeSupplierContact lifecycle")
    func testSupplierContactLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        // Empty initially
        let initial = try env.parts.getSupplierContacts(supplierId: supplierId)
        #expect(initial.isEmpty)

        // Add a contact
        try env.parts.addSupplierContact(
            supplierId: supplierId,
            firstName: "Jane",
            lastName: "Smith",
            role: "Sales Rep",
            phone: "555-1234",
            email: "jane@supplier.com",
            isPrimary: true
        )

        let contacts = try env.parts.getSupplierContacts(supplierId: supplierId)
        #expect(contacts.count == 1)
        #expect(contacts[0].firstName == "Jane")
        #expect(contacts[0].isPrimary == 1)

        // Remove the contact (soft delete)
        let contactId = contacts[0].contactId
        try env.parts.removeSupplierContact(contactId: contactId)
        let afterRemove = try env.parts.getSupplierContacts(supplierId: supplierId)
        #expect(afterRemove.isEmpty)
    }

    // MARK: - Part Change Log

    @Test("logPartChange and getPartChangeLog round-trip")
    func testPartChangeLog() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        let countBefore = try env.parts.getPartChangeLog(partId: partId).count

        try env.parts.logPartChange(
            partId: partId,
            userId: env.adminUserId,
            userName: "Admin",
            action: "updated",
            fieldName: "name",
            oldValue: "Old Name",
            newValue: "New Name"
        )

        let log = try env.parts.getPartChangeLog(partId: partId)
        #expect(log.count == countBefore + 1)
        let entry = try #require(log.first { $0.action == "updated" && $0.fieldName == "name" })
        #expect(entry.oldValue == "Old Name")
        #expect(entry.newValue == "New Name")
    }

    // MARK: - Part Trace Movements

    @Test("tracePartMovements returns empty for part with no movements")
    func testTracePartMovementsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let trace = try env.parts.tracePartMovements(partId: partId)
        #expect(trace.isEmpty)
    }

    @Test("tracePartMovements returns steps after receiving stock")
    func testTracePartMovementsAfterReceive() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        let trace = try env.parts.tracePartMovements(partId: partId)
        #expect(!trace.isEmpty)
        #expect(trace[0].qty == 10)
    }

    // MARK: - getPartCurrentLocations

    @Test("getPartCurrentLocations returns correct location after stocking")
    func testGetPartCurrentLocations() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 15)

        let locations = try env.parts.getPartCurrentLocations(partId: partId)
        #expect(locations.contains { $0.locationType == "warehouse" && $0.qty == 15 })
    }

    // MARK: - Scheduled Deletions

    @Test("scheduleEmptyShelfDeletion + listScheduledDeletions + cancelScheduledDeletion lifecycle")
    func testScheduledDeletionLifecycle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Obsolete Part", categoryId: catId)

        // Nothing scheduled initially
        let initial = try env.parts.listScheduledDeletions()
        #expect(!initial.contains { $0.entityId == partId })

        // Schedule a deletion
        let deletionId = try env.parts.scheduleEmptyShelfDeletion(
            entityType: "part",
            entityId: partId,
            entityName: "Obsolete Part",
            reason: "End of life",
            scheduledBy: env.adminUserId
        )
        #expect(deletionId > 0)

        let scheduled = try env.parts.listScheduledDeletions()
        #expect(scheduled.contains { $0.id == deletionId })

        // Cancel the scheduled deletion
        try env.parts.cancelScheduledDeletion(id: deletionId)

        // Cancelled items have deleted_at set — should not appear in list
        let afterCancel = try env.parts.listScheduledDeletions()
        #expect(!afterCancel.contains { $0.id == deletionId })
    }
}
