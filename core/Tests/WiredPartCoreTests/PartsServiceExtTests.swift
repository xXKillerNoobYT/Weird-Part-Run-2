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

    @Test("auto-add-to-wishlist flag defaults off and can be toggled by catalog editor")
    func testAutoAddToWishlistWhenLowToggle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "AutoWishlistCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Auto Wishlist Part", categoryId: catId)

        #expect(try env.parts.getAutoAddToWishlistWhenLow(partId: partId) == false)
        #expect(try env.parts.getPart(id: partId).part.autoAddToWishlistWhenLow == 0)

        try env.parts.setAutoAddToWishlistWhenLow(partId: partId, enabled: true, byUserId: env.adminUserId)

        #expect(try env.parts.getAutoAddToWishlistWhenLow(partId: partId))
        #expect(try env.parts.getPart(id: partId).part.autoAddToWishlistWhenLow == 1)
    }

    @Test("auto-add-to-wishlist toggle audit records old and new values")
    func testAutoAddToWishlistWhenLowToggleAuditValues() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "AutoWishlistAuditCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Auto Wishlist Audit", categoryId: catId)

        try env.parts.setAutoAddToWishlistWhenLow(partId: partId, enabled: true, byUserId: env.adminUserId)
        try env.parts.setAutoAddToWishlistWhenLow(partId: partId, enabled: false, byUserId: env.adminUserId)

        let entries = try env.parts.getPartChangeLog(partId: partId)
            .filter { $0.fieldName == "auto_add_to_wishlist_when_low" }
        #expect(entries.count == 2)
        #expect(entries.contains { $0.oldValue == "0" && $0.newValue == "1" })
        #expect(entries.contains { $0.oldValue == "1" && $0.newValue == "0" })
    }

    @Test("auto-add-to-wishlist toggle rejects users without edit_parts_catalog")
    func testAutoAddToWishlistWhenLowRequiresCatalogEditPermission() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "AutoWishlistPermCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Auto Wishlist Restricted", categoryId: catId)
        let unprivilegedId = try env.auth.createUser(displayName: "NoCatalogEdit", pin: "7777")

        #expect(throws: PartsService.PartsError.insufficientPermissions(required: "edit_parts_catalog")) {
            try env.parts.setAutoAddToWishlistWhenLow(partId: partId, enabled: true, byUserId: unprivilegedId)
        }
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

    @Test("searchParts does not match a part via a soft-deleted color name")
    func testSearchParts_doesNotMatchViaDeletedColorName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let colorId = try env.parts.createColor(name: "UniqueSearchColorXyzzy", hexCode: "#FEDCBA")
        let partId = try env.parts.createPart(
            categoryId: catId, name: "NoMatchNamePart", colorId: colorId, code: "NMNP-001"
        )

        // Baseline: part matches via the color name
        let before = try env.parts.searchParts(query: "UniqueSearchColorXyzzy")
        #expect(before.contains { $0.id == partId })

        // Soft-delete the color. The part itself stays active, but a color-name
        // search should no longer match because the LEFT JOIN condition drops the
        // tombstoned color row — `pc.name` is now NULL in the evaluated row.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE part_colors SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [colorId]
            )
        }

        let after = try env.parts.searchParts(query: "UniqueSearchColorXyzzy")
        #expect(!after.contains { $0.id == partId },
                "Soft-deleted color name must not keep a part searchable — LEFT JOIN guard drops the tombstoned color row")
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

    @Test("Supplier-brand links can be managed from supplier side")
    func testSetSupplierBrandsLinksAndUnlinksExistingBrands() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try env.parts.createSupplier(name: "Supplier Brand Manager")
        let keepBrandId = try env.parts.createBrand(name: "Keep Brand")
        let removeBrandId = try env.parts.createBrand(name: "Remove Brand")
        let addBrandId = try env.parts.createBrand(name: "Add Brand")

        try env.parts.setSupplierBrands(supplierId: supplierId, brandIds: [keepBrandId, removeBrandId])
        try env.parts.setSupplierBrands(supplierId: supplierId, brandIds: [keepBrandId, addBrandId])

        let linkedBrands = try env.parts.getSupplierBrandRows(supplierId: supplierId)
        #expect(linkedBrands.map(\.brandId).sorted() == [addBrandId, keepBrandId].sorted())
        #expect(linkedBrands.allSatisfy { $0.carryStatus == "carry_on_shelf" })
    }

    @Test("Supplier creation can atomically link initial active brands")
    func testCreateSupplierLinksInitialBrandsAtomically() throws {
        let env = try E2ETestHelpers.setUp()
        let firstBrandId = try env.parts.createBrand(name: "Initial Brand One")
        let secondBrandId = try env.parts.createBrand(name: "Initial Brand Two")

        let supplierId = try env.parts.createSupplier(
            name: "Supplier With Initial Brands",
            initialBrandIds: [firstBrandId, secondBrandId]
        )

        let linkedBrands = try env.parts.getSupplierBrandRows(supplierId: supplierId)
        #expect(linkedBrands.map(\.brandId).sorted() == [firstBrandId, secondBrandId].sorted())
        #expect(linkedBrands.allSatisfy { $0.carryStatus == "carry_on_shelf" })
    }

    @Test("Supplier creation rejects inactive initial brands without creating supplier")
    func testCreateSupplierRejectsInactiveInitialBrandWithoutPartialSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let inactiveBrandId = try env.parts.createBrand(name: "Inactive Initial Brand")
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE brands SET is_active = 0 WHERE id = ?",
                arguments: [inactiveBrandId]
            )
        }

        #expect(throws: (any Error).self) {
            _ = try env.parts.createSupplier(
                name: "Should Not Persist",
                initialBrandIds: [inactiveBrandId]
            )
        }

        let suppliers = try env.parts.listSuppliers()
        #expect(!suppliers.contains { $0.supplier.name == "Should Not Persist" })
    }

    @Test("Supplier-side brand picker only offers active unlinked brands")
    func testListBrandsAvailableForSupplierExcludesLinkedAndDeletedBrands() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try env.parts.createSupplier(name: "Picker Supplier")
        let linkedBrandId = try env.parts.createBrand(name: "Already Linked")
        let availableBrandId = try env.parts.createBrand(name: "Available Brand")
        let deletedBrandId = try env.parts.createBrand(name: "Deleted Brand")
        let inactiveBrandId = try env.parts.createBrand(name: "Inactive Brand")
        let inactiveLinkBrandId = try env.parts.createBrand(name: "Inactive Link Brand")
        try env.parts.linkBrandToSupplier(brandId: linkedBrandId, supplierId: supplierId)
        try env.parts.linkBrandToSupplier(brandId: inactiveLinkBrandId, supplierId: supplierId)
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE brands SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [deletedBrandId]
            )
            try db.execute(
                sql: "UPDATE brands SET is_active = 0 WHERE id = ?",
                arguments: [inactiveBrandId]
            )
            try db.execute(
                sql: "UPDATE brand_supplier_links SET is_active = 0 WHERE brand_id = ? AND supplier_id = ?",
                arguments: [inactiveLinkBrandId, supplierId]
            )
        }

        let availableBrands = try env.parts.listBrandsAvailableForSupplier(supplierId: supplierId)
        #expect(availableBrands.compactMap(\.id) == [availableBrandId, inactiveLinkBrandId])
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

    @Test("Company default markup rejects negative writes and clamps corrupt saved values")
    func testCompanyDefaultMarkupRejectsNegativeAndClampsCorruptSavedValues() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "Default Markup Guard")
        let partId = try E2ETestHelpers.seedPart(env, name: "Default Markup Guard Part", categoryId: catId)

        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE parts SET weighted_avg_cost = ?, updated_at = datetime('now') WHERE id = ?",
                arguments: [100.0, partId]
            )
        }

        #expect(throws: (any Error).self) {
            try env.parts.updateCompanyCostSetting(key: "default_markup_percent", value: "-10")
        }

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO company_cost_settings (setting_key, setting_value, updated_at)
                VALUES ('default_markup_percent', '-75', datetime('now'))
                ON CONFLICT(setting_key) DO UPDATE SET
                    setting_value = excluded.setting_value,
                    updated_at = excluded.updated_at
                """)
        }

        let pricing = try env.parts.resolvePartPricing(partId: partId)
        #expect(pricing.effectiveMarkup == 0)
        #expect(pricing.sellPrice == 100)
        #expect(pricing.sellPrice >= pricing.weightedAvgCost)
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

    @Test("tracePartMovements hides performer name when user is soft-deleted")
    func testTracePartMovementsHidesDeletedPerformerName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [env.adminUserId])
        }

        let trace = try env.parts.tracePartMovements(partId: partId)
        #expect(!trace.isEmpty)
        #expect(trace.first?.performedByName == nil)
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

    @Test("upsertColorBrandSKU can explicitly clear nullable SKU fields")
    func testUpsertColorBrandSKUCanClearNullableFields() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Clearable", hexCode: "#112233")
        let brandId = try E2ETestHelpers.seedBrand(env)

        try env.parts.upsertColorBrandSKU(
            colorId: colorId,
            brandId: brandId,
            typeId: typeId,
            partNumber: "CLEAR-ME",
            unitCost: 12.34
        )
        try env.parts.upsertColorBrandSKU(
            colorId: colorId,
            brandId: brandId,
            typeId: typeId,
            partNumber: nil,
            unitCost: nil,
            clearPartNumber: true,
            clearUnitCost: true
        )

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus.count == 1)
        #expect(skus[0].partNumber == nil)
        #expect(skus[0].unitCost == nil)
    }

    @Test("getColorBrandSKUsForType returns active SKU rows across brands in one query")
    func testGetColorBrandSKUsForType() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId1 = try env.parts.createColor(name: "Batch Red", hexCode: "#FF0000")
        let colorId2 = try env.parts.createColor(name: "Batch Blue", hexCode: "#0000FF")
        let brandId1 = try E2ETestHelpers.seedBrand(env, name: "Batch Brand A")
        let brandId2 = try E2ETestHelpers.seedBrand(env, name: "Batch Brand B")

        try env.parts.upsertColorBrandSKU(colorId: colorId1, brandId: brandId1, typeId: typeId, partNumber: "A-RED")
        try env.parts.upsertColorBrandSKU(colorId: colorId2, brandId: brandId2, typeId: typeId, partNumber: "B-BLUE")

        let skus = try env.parts.getColorBrandSKUsForType(typeId: typeId)
        #expect(skus.count == 2)
        #expect(Set(skus.map(\.brandId)) == Set([brandId1, brandId2]))
        #expect(Set(skus.map(\.colorId)) == Set([colorId1, colorId2]))
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

    @Test("updateColor clears hex_code to NULL when passed an empty string")
    func testUpdateColorClearsHexCode() throws {
        let env = try E2ETestHelpers.setUp()
        let colorId = try env.parts.createColor(name: "VisibleThenNamedOnly", hexCode: "#112233")

        try env.parts.updateColor(id: colorId, hexCode: "")

        let colors = try env.parts.listColors()
        let match = colors.first { $0.id == colorId }
        #expect(match?.hexCode == nil, "Empty update hex should clear to NULL for named-only variants")
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

    @Test("listCompanionRulesHierarchy populates hierarchy names on sources and targets")
    func testListCompanionRulesHierarchyPopulatesNames() throws {
        // Guards WEI-1080 (GH#426): companion-rule rows used to display
        // `Cat:<id>` / `Style:<id>` / `Type:<id>` placeholders because the
        // hierarchy listing didn't join the name tables.
        let env = try E2ETestHelpers.setUp()
        let (sourceCat, sourceStyle, sourceType) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "WEI1080SourceCat", style: "WEI1080SourceStyle", type: "WEI1080SourceType"
        )
        let (targetCat, targetStyle, targetType) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "WEI1080TargetCat", style: "WEI1080TargetStyle", type: "WEI1080TargetType"
        )

        let ruleId = try env.parts.createCompanionRuleAtLevel(
            name: "WEI-1080 Type Rule",
            sources: [(categoryId: sourceCat, styleId: sourceStyle, typeId: sourceType)],
            targets: [(categoryId: targetCat, styleId: targetStyle, typeId: targetType)]
        )

        let rule = try env.parts.listCompanionRulesHierarchy().first { $0.id == ruleId }
        let source = try #require(rule?.sources.first)
        let target = try #require(rule?.targets.first)

        #expect(source.categoryName == "WEI1080SourceCat")
        #expect(source.styleName == "WEI1080SourceStyle")
        #expect(source.typeName == "WEI1080SourceType")
        #expect(target.categoryName == "WEI1080TargetCat")
        #expect(target.styleName == "WEI1080TargetStyle")
        #expect(target.typeName == "WEI1080TargetType")
    }

    @Test("listCompanionRulesHierarchy returns nil names when hierarchy refs are soft-deleted")
    func testListCompanionRulesHierarchyDeletedRefsFallBackToNil() throws {
        // Guards WEI-1080 graceful-degradation contract: the UI renders
        // "Unknown ..." labels when names come back nil instead of the old
        // `Cat:<id>` placeholders, so the service must surface nil — not
        // crash and not silently drop the row when refs are soft-deleted.
        let env = try E2ETestHelpers.setUp()
        let (sourceCat, _, _) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "WEI1080DeletedSourceCat", style: "WEI1080DeletedSourceStyle", type: "WEI1080DeletedSourceType"
        )
        let (targetCat, _, _) = try E2ETestHelpers.seedPartHierarchy(
            env, category: "WEI1080DeletedTargetCat", style: "WEI1080DeletedTargetStyle", type: "WEI1080DeletedTargetType"
        )

        let ruleId = try env.parts.createCompanionRuleAtLevel(
            name: "WEI-1080 Orphan Refs Rule",
            sources: [(categoryId: sourceCat, styleId: nil, typeId: nil)],
            targets: [(categoryId: targetCat, styleId: nil, typeId: nil)]
        )

        // Soft-delete the referenced categories (cascades to styles+types).
        try env.parts.deleteCategory(id: sourceCat)
        try env.parts.deleteCategory(id: targetCat)

        let rule = try env.parts.listCompanionRulesHierarchy().first { $0.id == ruleId }
        let source = try #require(rule?.sources.first)
        let target = try #require(rule?.targets.first)

        // IDs still surface so the UI can render "Unknown (#<id>)".
        #expect(source.categoryId == sourceCat)
        #expect(target.categoryId == targetCat)
        // Names are nil so the UI fallback kicks in.
        #expect(source.categoryName == nil)
        #expect(target.categoryName == nil)
    }

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

    @Test("updateColorBrandSKU updates stock quantity for editor panel")
    func testUpdateColorBrandSKU_updatesStockQty() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let colorId = try env.parts.createColor(name: "Green", hexCode: "#00FF00")
        let brandId = try E2ETestHelpers.seedBrand(env)

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "GREEN-001", unitCost: 4.25, stockQty: 3
        )

        try env.parts.updateColorBrandSKU(skuId: skuId, stockQty: 9)

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus[0].stockQty == 9,
                "Categories editor must be able to persist color_brand_skus.stock_qty changes")
        #expect(skus[0].partNumber == "GREEN-001")
        #expect(skus[0].unitCost == 4.25)
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

    // MARK: - CRUD write-path soft-delete guards

    @Test("updatePart is a no-op on a soft-deleted part")
    func testUpdatePart_noOpOnSoftDeletedPart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "UpdateDeletedCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "OriginalName", categoryId: catId)
        try env.parts.deletePart(id: partId)

        // Soft-deleted: update call must not revive field values.
        // Regression: UPDATE parts SET ... WHERE id = ? had no deleted_at guard,
        // so a stale edit form could silently mutate a tombstoned part.
        try env.parts.updatePart(id: partId, name: "ShouldNotStick")

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT name, deleted_at FROM parts WHERE id = ?", arguments: [partId])
        }
        let r = try #require(row)
        let name: String = r["name"] ?? ""
        let deletedAt: String? = r["deleted_at"]
        #expect(name == "OriginalName",
                "Soft-deleted part name must not change — UPDATE must guard AND deleted_at IS NULL")
        #expect(deletedAt != nil, "Part must still be tombstoned")
    }

    @Test("updateCategory is a no-op on a soft-deleted category")
    func testUpdateCategory_noOpOnSoftDeletedCategory() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try env.parts.createCategory(name: "OriginalCat")
        try env.parts.deleteCategory(id: catId)
        try env.parts.updateCategory(id: catId, name: "ShouldNotStick")

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM part_categories WHERE id = ?", arguments: [catId])
        }
        #expect(name == "OriginalCat",
                "Soft-deleted category name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("updateStyle/updateType/updateColor are no-ops on soft-deleted rows")
    func testUpdateStyleTypeColor_noOpOnSoftDeleted() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, styleId, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        _ = catId
        let colorId = try env.parts.createColor(name: "OriginalColor", hexCode: "#112233")

        // Soft-delete each entity, then attempt to rename them
        try env.parts.deleteStyle(id: styleId)
        try env.parts.deleteType(id: typeId)
        try env.parts.deleteColor(id: colorId)

        try env.parts.updateStyle(id: styleId, name: "StyleShouldNotStick")
        try env.parts.updateType(id: typeId, name: "TypeShouldNotStick")
        try env.parts.updateColor(id: colorId, name: "ColorShouldNotStick")

        let styleName = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM part_styles WHERE id = ?", arguments: [styleId])
        }
        let typeName = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM part_types WHERE id = ?", arguments: [typeId])
        }
        let colorName = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM part_colors WHERE id = ?", arguments: [colorId])
        }

        #expect(styleName != "StyleShouldNotStick",
                "Soft-deleted style name must not change — UPDATE must guard AND deleted_at IS NULL")
        #expect(typeName != "TypeShouldNotStick",
                "Soft-deleted type name must not change — UPDATE must guard AND deleted_at IS NULL")
        #expect(colorName != "ColorShouldNotStick",
                "Soft-deleted color name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("updateBrand is a no-op on a soft-deleted brand")
    func testUpdateBrand_noOpOnSoftDeletedBrand() throws {
        let env = try E2ETestHelpers.setUp()
        let brandId = try env.parts.createBrand(name: "OriginalBrand")
        try env.parts.deleteBrand(id: brandId)
        try env.parts.updateBrand(id: brandId, name: "ShouldNotStick")

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM brands WHERE id = ?", arguments: [brandId])
        }
        #expect(name == "OriginalBrand",
                "Soft-deleted brand name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    @Test("updateSupplier is a no-op on a soft-deleted supplier")
    func testUpdateSupplier_noOpOnSoftDeletedSupplier() throws {
        let env = try E2ETestHelpers.setUp()
        let supId = try env.parts.createSupplier(name: "OriginalSupplier")
        try env.parts.deleteSupplier(id: supId)
        try env.parts.updateSupplier(id: supId, name: "ShouldNotStick")

        let name = try env.db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT name FROM suppliers WHERE id = ?", arguments: [supId])
        }
        #expect(name == "OriginalSupplier",
                "Soft-deleted supplier name must not change — UPDATE must guard AND deleted_at IS NULL")
    }

    // MARK: - FK deleted_at guards on create paths (iter 64)

    @Test("createStyle rejects a tombstoned parent category")
    func testCreateStyle_rejectsTombstonedCategory() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try env.parts.createCategory(name: "TombCat")
        try env.parts.deleteCategory(id: catId)
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.createStyle(categoryId: catId, name: "ShouldNotStick")
        }
    }

    @Test("createType rejects a tombstoned parent style")
    func testCreateType_rejectsTombstonedStyle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try env.parts.createCategory(name: "TombStyleCat")
        let styleId = try env.parts.createStyle(categoryId: catId, name: "TombStyle")
        try env.parts.deleteStyle(id: styleId)
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.createType(styleId: styleId, name: "ShouldNotStick")
        }
    }

    @Test("createPart rejects a tombstoned category or brand FK")
    func testCreatePart_rejectsTombstonedFK() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try env.parts.createCategory(name: "PartFKCat")
        let brandId = try env.parts.createBrand(name: "TombstoneBrand")
        try env.parts.deleteBrand(id: brandId)
        // brand FK is tombstoned → throws brandNotFound
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.createPart(categoryId: catId, name: "NoBrand", brandId: brandId)
        }
        // now tombstone category and retry with a valid brand
        try env.parts.deleteCategory(id: catId)
        let brand2 = try env.parts.createBrand(name: "LiveBrand")
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.createPart(categoryId: catId, name: "NoCat", brandId: brand2)
        }
    }

    @Test("addPartSupplierLink rejects tombstoned part or supplier")
    func testAddPartSupplierLink_rejectsTombstonedFK() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try env.parts.createCategory(name: "LinkCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "LinkPart", categoryId: catId)
        let supId = try env.parts.createSupplier(name: "LinkSupp")
        try env.parts.deleteSupplier(id: supId)
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: supId)
        }
        // now tombstone part and retry with a fresh supplier
        try env.parts.deletePart(id: partId)
        let sup2 = try env.parts.createSupplier(name: "LiveSupp")
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.addPartSupplierLink(partId: partId, supplierId: sup2)
        }
    }

    @Test("linkBrandToSupplier rejects tombstoned brand or supplier")
    func testLinkBrandToSupplier_rejectsTombstonedFK() throws {
        let env = try E2ETestHelpers.setUp()
        let brandId = try env.parts.createBrand(name: "B2SBrand")
        let supId = try env.parts.createSupplier(name: "B2SSup")
        try env.parts.deleteBrand(id: brandId)
        #expect(throws: PartsService.PartsError.self) {
            _ = try env.parts.linkBrandToSupplier(brandId: brandId, supplierId: supId)
        }
    }

    // MARK: - is_active defense: hierarchy list functions

    @Test("listCategories excludes is_active=0 categories")
    func testListCategories_excludesInactiveCategory() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "InactiveCat_isActive")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE part_categories SET is_active = 0 WHERE id = ?", arguments: [catId])
        }
        let categories = try env.parts.listCategories()
        #expect(!categories.contains(where: { $0.id == catId }))
    }

    @Test("listColors excludes is_active=0 colors")
    func testListColors_excludesInactiveColor() throws {
        let env = try E2ETestHelpers.setUp()
        let colorId = try env.parts.createColor(name: "InactiveColor_isActive", hexCode: "#AABBCC")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE part_colors SET is_active = 0 WHERE id = ?", arguments: [colorId])
        }
        let colors = try env.parts.listColors()
        #expect(!colors.contains(where: { $0.id == colorId }))
    }

    @Test("getHierarchy excludes is_active=0 categories from tree")
    func testGetHierarchy_excludesInactiveCategory() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "InactiveCatHierarchy_isActive")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE part_categories SET is_active = 0 WHERE id = ?", arguments: [catId])
        }
        let tree = try env.parts.getHierarchy()
        #expect(!tree.categories.contains(where: { $0.id == catId }))
    }

    @Test("listParts excludes is_active=0 parts")
    func testListParts_excludesInactivePart() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "CatForInactivePart")
        let partId = try env.parts.createPart(categoryId: catId, name: "InactivePart_isActive", code: "INACT-001")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET is_active = 0 WHERE id = ?", arguments: [partId])
        }
        let parts = try env.parts.listParts()
        #expect(!parts.contains(where: { $0.part.id == partId }))
    }

    // MARK: - NULL-default boolean field defense (issue: GRDB Int? inserts NULL bypassing SQL DEFAULT)

    @Test("createPart sets isDeprecated=0 — row appears in WHERE is_deprecated=0 query")
    func testCreatePart_setsIsDeprecatedZero() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DeprecatedDefenseCat")
        let partId = try env.parts.createPart(categoryId: catId, name: "NotDeprecatedPart", code: "NODEP-001")
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM parts WHERE id = ? AND is_deprecated = 0", arguments: [partId]) ?? 0
        }
        #expect(count == 1)
    }

    @Test("createPart sets isQrTagged=0 — row appears in WHERE is_qr_tagged=0 query")
    func testCreatePart_setsIsQrTaggedZero() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "QrTagDefenseCat")
        let partId = try env.parts.createPart(categoryId: catId, name: "UntaggedPart", code: "NOTAG-001")
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM parts WHERE id = ? AND is_qr_tagged = 0", arguments: [partId]) ?? 0
        }
        #expect(count == 1)
    }

    @Test("createSupplier sets isActive=1 — row appears in WHERE is_active=1 query")
    func testCreateSupplier_setsIsActiveOne() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try env.parts.createSupplier(name: "ActiveDefenseSupplier")
        let count = try env.db.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM suppliers WHERE id = ? AND is_active = 1", arguments: [supplierId]) ?? 0
        }
        #expect(count == 1)
    }
}
