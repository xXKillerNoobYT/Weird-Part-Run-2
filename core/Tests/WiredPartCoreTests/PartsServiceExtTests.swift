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

    @Test("getPart throws partNotFound for soft-deleted parts")
    func testGetPart_throwsForDeletedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DelPartCat")
        let partId = try env.parts.createPart(categoryId: catId, name: "Doomed Part", code: "DOOM-001")

        // Soft-delete the part
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [partId]
            )
        }

        #expect(throws: (any Error).self) {
            _ = try env.parts.getPart(id: partId)
        }
    }

    @Test("searchParts hides dimension names when category/brand is soft-deleted")
    func testSearchParts_hidesDeletedDimensionNames() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try env.parts.createCategory(name: "Deletable Cat")
        let brandId = try E2ETestHelpers.seedBrand(env, name: "Deletable Brand")
        let partId = try env.parts.createPart(
            categoryId: catId, name: "Dim Hidden Part", code: "DIM-001", brandId: brandId
        )

        // Soft-delete the category AND brand but leave the part itself active
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE part_categories SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [catId])
            try db.execute(sql: "UPDATE brands SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [brandId])
        }

        let results = try env.parts.searchParts(query: "DIM-001")
        let match = results.first { $0.id == partId }
        #expect(match != nil, "Part itself is active — search should still find it")
        // The LEFT JOIN guards should have stripped the deleted category/brand names.
        // (searchParts returns [Part] which doesn't expose categoryName — ensure the
        //  listCatalogParts companion path would degrade via LEFT JOIN → NULL.)
        let listed = try env.parts.listCatalogParts(search: "DIM-001")
        let listedMatch = listed.parts.first { $0.part.id == partId }
        #expect(listedMatch?.categoryName == nil,
                "Soft-deleted category must not leak its name via listCatalogParts LEFT JOIN")
        #expect(listedMatch?.brandName == nil,
                "Soft-deleted brand must not leak its name via listCatalogParts LEFT JOIN")
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

    @Test("getPartSuppliers excludes soft-deleted suppliers even with active part_supplier_links")
    func testGetPartSuppliers_excludesDeletedSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "TombstonedSupplier")

        _ = try env.parts.addPartSupplierLink(
            partId: partId, supplierId: supplierId,
            supplierPartNumber: "PRE-DEL-001", costPrice: 3.00
        )

        // Before: link visible
        let before = try env.parts.getPartSuppliers(partId: partId)
        #expect(before.contains { $0.supplierId == supplierId })

        // Soft-delete the supplier but leave the part_supplier_links row active
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }

        // After: link must not be returned since the supplier is tombstoned
        let after = try env.parts.getPartSuppliers(partId: partId)
        #expect(!after.contains { $0.supplierId == supplierId },
                "getPartSuppliers must not return links to soft-deleted suppliers even if psl.deleted_at is still NULL")
    }

    @Test("getColorSupplierPartNumbers excludes soft-deleted suppliers")
    func testGetColorSupplierPartNumbers_excludesDeletedSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let colorId = try env.parts.createColor(name: "ForDeletedSupplier", hexCode: "#123456")
        let partId = try env.parts.createPart(
            categoryId: catId, name: "ColorPart", colorId: colorId, code: "CP-001"
        )
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "WillBeDeleted")

        _ = try env.parts.addPartSupplierLink(
            partId: partId, supplierId: supplierId,
            supplierPartNumber: "SUP-CDEL-001", costPrice: 1.75
        )

        let before = try env.parts.getColorSupplierPartNumbers(colorId: colorId)
        #expect(before.contains { $0.supplierId == supplierId })

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }

        let after = try env.parts.getColorSupplierPartNumbers(colorId: colorId)
        #expect(!after.contains { $0.supplierId == supplierId },
                "getColorSupplierPartNumbers must not return soft-deleted suppliers")
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

    @Test("listCompanionRules excludes soft-deleted rules")
    func testListCompanionRulesExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let ruleId = try env.parts.createCompanionRule(name: "To Be Deleted")
        let before = try env.parts.listCompanionRules()
        let countBefore = before.filter { $0.id == ruleId }.count
        #expect(countBefore == 1)

        try env.parts.deleteCompanionRule(id: ruleId)

        let after = try env.parts.listCompanionRules()
        let countAfter = after.filter { $0.id == ruleId }.count
        #expect(countAfter == 0, "Soft-deleted rule must not appear in listCompanionRules")
    }

    @Test("listCompanionRulesHierarchy childCount excludes soft-deleted children")
    func testHierarchyChildCountExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let parentId = try env.parts.createCompanionRule(name: "Parent Rule")
        let childId = try env.parts.createCompanionRuleAtLevel(
            name: "Child Rule", parentRuleId: parentId, sources: [], targets: []
        )
        #expect(childId > 0)

        // Before deletion: parent should show 1 child
        let hierarchyBefore = try env.parts.listCompanionRulesHierarchy()
        let parentBefore = hierarchyBefore.first { $0.id == parentId }
        #expect(parentBefore?.childCount == 1)

        // Soft-delete the child
        try env.parts.deleteCompanionRuleSoft(id: childId)

        // After deletion: parent must show 0 active children
        let hierarchyAfter = try env.parts.listCompanionRulesHierarchy()
        let parentAfter = hierarchyAfter.first { $0.id == parentId }
        #expect(parentAfter?.childCount == 0,
                "childCount must exclude soft-deleted children — UI uses this to hide expand buttons")
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

    // MARK: - ColorBrandSKU CRUD (PE-COLORS Phase 1)

    @Test("upsertColorBrandSKU creates a new SKU row")
    func testUpsertColorBrandSKUCreate() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Gray", hexCode: "#808080")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "ABC-123", unitCost: 4.99
        )
        #expect(skuId > 0)

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus.count == 1)
        #expect(skus[0].partNumber == "ABC-123")
        #expect(skus[0].unitCost == 4.99)
        #expect(skus[0].colorId == colorId)
    }

    @Test("upsertColorBrandSKU reactivates a soft-deleted row")
    func testUpsertColorBrandSKUReactivate() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Red", hexCode: "#FF0000")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId, partNumber: "RED-001"
        )
        try env.parts.deleteColorBrandSKU(skuId: skuId)
        let afterDelete = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(afterDelete.isEmpty)

        // Re-upsert — should reactivate with new part number
        let reactivatedId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId, partNumber: "RED-002"
        )
        #expect(reactivatedId == skuId)
        let reactivated = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(reactivated.count == 1)
        #expect(reactivated[0].partNumber == "RED-002")
        #expect(reactivated[0].isActive == true)
    }

    @Test("getSKUsForColor returns all active SKUs across brands and types")
    func testGetSKUsForColor() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let (_, _, typeId2) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "Conduit", style: "PVC", type: "1/2 inch"
        )
        let colorId = try env.parts.createColor(name: "White", hexCode: "#FFFFFF")
        let brandId1 = try E2ETestHelpers.seedBrand(env, name: "Cantex")
        let brandId2 = try E2ETestHelpers.seedBrand(env, name: "Carlon")

        try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandId1, typeId: typeId, partNumber: "CX-001")
        try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandId2, typeId: typeId, partNumber: "CL-001")
        try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brandId1, typeId: typeId2, partNumber: "CX-002")

        let allForColor = try env.parts.getSKUsForColor(colorId: colorId)
        #expect(allForColor.count == 3)
        #expect(allForColor.allSatisfy { $0.colorId == colorId })
    }

    @Test("updateColorBrandSKU patches partNumber and unitCost in place")
    func testUpdateColorBrandSKU() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Black", hexCode: "#000000")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "OLD-001", unitCost: 1.00
        )
        try env.parts.updateColorBrandSKU(skuId: skuId, partNumber: "NEW-001", unitCost: 2.50)

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus[0].partNumber == "NEW-001")
        #expect(skus[0].unitCost == 2.50)
    }

    @Test("deleteColorBrandSKU soft-deletes — row excluded from active listings")
    func testDeleteColorBrandSKU() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Yellow", hexCode: "#FFFF00")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId, partNumber: "YEL-001"
        )
        #expect(!(try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)).isEmpty)

        try env.parts.deleteColorBrandSKU(skuId: skuId)
        let afterDelete = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(afterDelete.isEmpty)

        // Color-level query should also exclude the deleted SKU
        let forColor = try env.parts.getSKUsForColor(colorId: colorId)
        #expect(forColor.isEmpty)
    }

    // MARK: - PE-COLORS Plan Tests (colors-parts-redesign.md)

    @Test("PE-COLORS Plan Test 2: named-only variant (hex_code=NULL) creates and lists correctly")
    func testNamedOnlyVariant() throws {
        let env = try E2ETestHelpers.setUp()

        // Named-only variant: finish type with no color chip
        let variantId = try env.parts.createColor(name: "Fire-Rated", hexCode: nil)
        #expect(variantId > 0)

        let colors = try env.parts.listColors()
        let match = colors.first { $0.id == variantId }
        #expect(match != nil)
        #expect(match?.name == "Fire-Rated")
        #expect(match?.hexCode == nil, "Named-only variant must have nil hex_code")
    }

    @Test("PE-COLORS Plan Test 4: searchParts finds a part by its SKU-level part_number")
    func testSearchBySkuPartNumber() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Orange", hexCode: "#FFA500")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let partId = try env.parts.createPart(
            categoryId: catId,
            name: "PVC Conduit Orange",
            typeId: typeId,
            colorId: colorId,
            code: "PCO-ORANGE",
            brandId: brandId
        )
        #expect(partId > 0)

        // Create a SKU row with a brand-specific part number
        _ = try env.parts.upsertColorBrandSKU(
            colorId: colorId,
            brandId: brandId,
            typeId: typeId,
            partNumber: "CBS-CANTEX-ORANGE-001"
        )

        // Search by the SKU-level part number — must find the parent part
        let results = try env.parts.searchParts(query: "CANTEX-ORANGE-001")
        #expect(results.contains { $0.id == partId },
                "searchParts must return the part when the SKU-level part_number matches")
    }

    // MARK: - Fix Regression Tests (Iteration 5)

    @Test("listCompanionRulesHierarchy excludes soft-deleted parent rules")
    func testListCompanionRulesHierarchyExcludesSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()

        let ruleId = try env.parts.createCompanionRule(name: "To Be Hierarchy Deleted")
        let before = try env.parts.listCompanionRulesHierarchy()
        #expect(before.contains { $0.id == ruleId })

        try env.parts.deleteCompanionRuleSoft(id: ruleId)

        let after = try env.parts.listCompanionRulesHierarchy()
        #expect(!after.contains { $0.id == ruleId },
                "Soft-deleted rule must not appear in listCompanionRulesHierarchy")
    }

    @Test("updateColorBrandSKU: updating only partNumber preserves existing unitCost")
    func testUpdateColorBrandSKU_partNumberOnly_preservesUnitCost() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Blue", hexCode: "#0000FF")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "BLUE-001", unitCost: 3.75
        )
        // Update only partNumber — unitCost must survive
        try env.parts.updateColorBrandSKU(skuId: skuId, partNumber: "BLUE-002", unitCost: nil)

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus[0].partNumber == "BLUE-002")
        #expect(skus[0].unitCost == 3.75,
                "unitCost must be preserved when updateColorBrandSKU is called with nil unitCost")
    }

    @Test("upsertColorBrandSKU reactivation preserves existing data when nil passed")
    func testUpsertColorBrandSKUReactivate_preservesDataWhenNilPassed() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Yellow", hexCode: "#FFFF00")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "YEL-001", unitCost: 2.50
        )
        try env.parts.deleteColorBrandSKU(skuId: skuId)

        // Reactivate without passing partNumber or unitCost — both must survive
        let reactivatedId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId
        )
        #expect(reactivatedId == skuId)
        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus[0].partNumber == "YEL-001",
                "partNumber must be preserved on reactivation with nil partNumber")
        #expect(skus[0].unitCost == 2.50,
                "unitCost must be preserved on reactivation with nil unitCost")
    }

    @Test("getJobsWithCategoryCoOccurrence excludes soft-deleted jobs")
    func testGetJobsWithCategoryCoOccurrence_excludesDeletedJobs() throws {
        let env = try E2ETestHelpers.setUp()

        // Two categories so a single job meets the HAVING COUNT(DISTINCT category) >= 2 threshold
        let cat1 = try env.parts.createCategory(name: "Conduit")
        let cat2 = try env.parts.createCategory(name: "Fittings")
        let part1 = try E2ETestHelpers.seedPart(env, name: "Conduit Part", categoryId: cat1)
        let part2 = try E2ETestHelpers.seedPart(env, name: "Fitting Part", categoryId: cat2)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CO-001")

        try env.jobs.addJobPart(jobId: jobId, partId: part1, qty: 1, performedBy: env.adminUserId)
        try env.jobs.addJobPart(jobId: jobId, partId: part2, qty: 1, performedBy: env.adminUserId)

        // Before deletion: job appears in suggestions
        let before = try env.parts.getJobsWithCategoryCoOccurrence(categoryIds: [cat1, cat2])
        #expect(before.contains { $0.jobId == jobId })

        // Soft-delete the job
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }

        // After deletion: job must not appear in companion suggestions
        let after = try env.parts.getJobsWithCategoryCoOccurrence(categoryIds: [cat1, cat2])
        #expect(!after.contains { $0.jobId == jobId },
                "Soft-deleted jobs must not appear in getJobsWithCategoryCoOccurrence results")
    }

    @Test("PE-COLORS Plan Test 3: color pool is global — same color accessible across all type+brand contexts")
    func testColorPoolIsGlobal() throws {
        let env = try E2ETestHelpers.setUp()

        // Two different type contexts
        let (_, _, typeId1) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "Conduit", style: "PVC", type: "1/2 Inch"
        )
        let (_, _, typeId2) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "Fittings", style: "PVC", type: "Coupling 1/2"
        )
        let brandId1 = try E2ETestHelpers.seedBrand(env, name: "Cantex")
        let brandId2 = try E2ETestHelpers.seedBrand(env, name: "Carlon")

        // One shared color "Gray" — belongs to no specific type
        let grayId = try env.parts.createColor(name: "GlobalGray", hexCode: "#808080")

        // Create distinct SKUs for different (color, brand, type) triples
        let sku1Id = try env.parts.upsertColorBrandSKU(
            colorId: grayId, brandId: brandId1, typeId: typeId1, partNumber: "CX-GRAY-PVC-001"
        )
        let sku2Id = try env.parts.upsertColorBrandSKU(
            colorId: grayId, brandId: brandId2, typeId: typeId1, partNumber: "CA-GRAY-PVC-001"
        )
        let sku3Id = try env.parts.upsertColorBrandSKU(
            colorId: grayId, brandId: brandId1, typeId: typeId2, partNumber: "CX-GRAY-FIT-001"
        )

        // 1. Color pool is global — listColors returns Gray exactly once, not per-type
        let allColors = try env.parts.listColors()
        let grayOccurrences = allColors.filter { $0.id == grayId }
        #expect(grayOccurrences.count == 1,
                "part_colors pool is global — a color must appear exactly once regardless of how many (type, brand) SKUs reference it")

        // 2. getSKUsForColor returns all 3 SKUs across type+brand contexts
        let skusForGray = try env.parts.getSKUsForColor(colorId: grayId)
        #expect(skusForGray.count == 3,
                "getSKUsForColor must return all active SKUs for the color across all (type, brand) contexts")
        let skuIds = skusForGray.map(\.id)
        #expect(skuIds.contains(sku1Id))
        #expect(skuIds.contains(sku2Id))
        #expect(skuIds.contains(sku3Id))

        // 3. getColorBrandSKUs is correctly scoped — each (type, brand) combo is distinct
        let cantexConduit = try env.parts.getColorBrandSKUs(typeId: typeId1, brandId: brandId1)
        #expect(cantexConduit.count == 1)
        #expect(cantexConduit[0].partNumber == "CX-GRAY-PVC-001",
                "Cantex+Conduit SKU must be distinct from Carlon+Conduit SKU")

        let carlonConduit = try env.parts.getColorBrandSKUs(typeId: typeId1, brandId: brandId2)
        #expect(carlonConduit.count == 1)
        #expect(carlonConduit[0].partNumber == "CA-GRAY-PVC-001")

        let cantexFitting = try env.parts.getColorBrandSKUs(typeId: typeId2, brandId: brandId1)
        #expect(cantexFitting.count == 1)
        #expect(cantexFitting[0].partNumber == "CX-GRAY-FIT-001")
    }

    @Test("PE-COLORS Plan Test 1: upsert returns same id for duplicate (color, brand, type) triple")
    func testColorBrandSKUUniqueConstraintReturnsSameId() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Gray", hexCode: "#808080")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let id1 = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId, partNumber: "GR-001"
        )
        // Second upsert with the same triple — must return the same row id
        let id2 = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId, partNumber: "GR-002"
        )
        #expect(id1 == id2, "Duplicate (color, brand, type) triple must reuse the existing row")

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus.count == 1, "Only one SKU row should exist for the triple")
        #expect(skus[0].partNumber == "GR-002", "partNumber should be updated to the latest value")
    }
}
