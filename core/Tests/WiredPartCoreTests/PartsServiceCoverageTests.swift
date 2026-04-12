import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// Tests covering previously-untested PartsService public methods:
/// hierarchy CRUD (getType, updateStyle/Type, deleteStyle/Type),
/// supplier linkage (getTypeBrandLinkId, getPartSupplierCosts),
/// pricing system (setPricingTier, getPricingTiers, removePricingTier,
///                  logPriceChange, getPriceHistory),
/// and settings utilities (getCompanyCostSetting, updateCompanyCostSetting,
///                          findOrCreateCategory, findOrCreateBrand,
///                          listCatalogParts).

@Suite("PartsService Coverage Tests")
struct PartsServiceCoverageTests {

    // MARK: - Hierarchy CRUD: Style

    @Test("updateStyle changes name and description")
    func testUpdateStyle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "UpdateStyleCat")
        let styleId = try env.parts.createStyle(categoryId: catId, name: "OriginalStyle")

        try env.parts.updateStyle(id: styleId, name: "RenamedStyle", description: "New desc")

        let styles = try env.parts.listStyles(categoryId: catId)
        let updated = try #require(styles.first(where: { $0.id == styleId }))
        #expect(updated.name == "RenamedStyle")
        #expect(updated.description == "New desc")
    }

    @Test("updateStyle with no fields is a no-op")
    func testUpdateStyleNoFields() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "NoOpStyleCat")
        let styleId = try env.parts.createStyle(categoryId: catId, name: "Unchanged")

        // Should not throw when called with no updates
        try env.parts.updateStyle(id: styleId)

        let styles = try env.parts.listStyles(categoryId: catId)
        let s = try #require(styles.first(where: { $0.id == styleId }))
        #expect(s.name == "Unchanged")
    }

    @Test("deleteStyle soft-deletes the style")
    func testDeleteStyle() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "DeleteStyleCat")
        let styleId = try env.parts.createStyle(categoryId: catId, name: "ToDelete")

        try env.parts.deleteStyle(id: styleId)

        let styles = try env.parts.listStyles(categoryId: catId)
        #expect(!styles.contains(where: { $0.id == styleId }), "Deleted style should not appear in listing")
    }

    // MARK: - Hierarchy CRUD: Type

    @Test("getType returns correct type by ID")
    func testGetType() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, styleId, typeId) = try E2ETestHelpers.seedPartHierarchy(env)

        let type_ = try env.parts.getType(id: typeId)
        #expect(type_.id == typeId)
        #expect(type_.styleId == styleId)
    }

    @Test("getType throws for non-existent ID")
    func testGetTypeNotFound() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: (any Error).self) {
            try env.parts.getType(id: 999999)
        }
    }

    @Test("updateType changes name")
    func testUpdateType() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, styleId, typeId) = try E2ETestHelpers.seedPartHierarchy(env)

        try env.parts.updateType(id: typeId, name: "RenamedType", description: "Updated desc")

        let types = try env.parts.listTypes(styleId: styleId)
        let updated = try #require(types.first(where: { $0.id == typeId }))
        #expect(updated.name == "RenamedType")
        #expect(updated.description == "Updated desc")
    }

    @Test("deleteType soft-deletes the type")
    func testDeleteType() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, styleId, typeId) = try E2ETestHelpers.seedPartHierarchy(env)

        try env.parts.deleteType(id: typeId)

        let types = try env.parts.listTypes(styleId: styleId)
        #expect(!types.contains(where: { $0.id == typeId }), "Deleted type should not appear in listing")
    }

    // MARK: - Supplier Linkage

    @Test("getTypeBrandLinkId returns link ID after linkTypeBrand")
    func testGetTypeBrandLinkId() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let brandId = try E2ETestHelpers.seedBrand(env, name: "LinkBrand")

        try env.parts.linkTypeToBrand(typeId: typeId, brandId: brandId)

        let linkId = try env.parts.getTypeBrandLinkId(typeId: typeId, brandId: brandId)
        #expect(linkId != nil, "Should find a link ID after linking")
    }

    @Test("getTypeBrandLinkId returns nil when no link exists")
    func testGetTypeBrandLinkIdNotFound() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let brandId = try E2ETestHelpers.seedBrand(env, name: "UnlinkedBrand")

        let linkId = try env.parts.getTypeBrandLinkId(typeId: typeId, brandId: brandId)
        #expect(linkId == nil)
    }

    @Test("getPartSupplierCosts returns costs after linking")
    func testGetPartSupplierCosts() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "CostCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "CostPart", categoryId: catId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "CostSupplier")

        try env.parts.addPartSupplierLink(
            partId: partId,
            supplierId: supplierId,
            supplierPartNumber: "SP-001",
            costPrice: 12.50,
            isPreferred: true
        )

        let costs = try env.parts.getPartSupplierCosts(partId: partId)
        #expect(costs.count == 1)
        #expect(costs[0].supplierCostPrice == 12.50)
        #expect(costs[0].supplierPartNumber == "SP-001")
        #expect(costs[0].isPreferred == true)
    }

    @Test("getPartSupplierCosts returns empty for part with no links")
    func testGetPartSupplierCostsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "EmptyCostCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "NoLinkPart", categoryId: catId)

        let costs = try env.parts.getPartSupplierCosts(partId: partId)
        #expect(costs.isEmpty)
    }

    // MARK: - Price History

    @Test("logPriceChange and getPriceHistory round-trip")
    func testPriceHistoryRoundTrip() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PriceHistCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "PriceHistPart", categoryId: catId)

        try env.parts.logPriceChange(
            partId: partId,
            changeType: "manual",
            oldValue: 10.0,
            newValue: 15.0,
            changedBy: env.adminUserId
        )
        try env.parts.logPriceChange(
            partId: partId,
            changeType: "import",
            oldValue: 15.0,
            newValue: 20.0,
            changedBy: env.adminUserId
        )

        let history = try env.parts.getPriceHistory(partId: partId)
        #expect(history.count == 2)
        // Most recent first
        #expect(history[0].newValue == 20.0)
        #expect(history[1].newValue == 15.0)
    }

    @Test("getPriceHistory returns empty for part with no history")
    func testPriceHistoryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "NoPriceHistCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "NoPriceHistPart", categoryId: catId)

        let history = try env.parts.getPriceHistory(partId: partId)
        #expect(history.isEmpty)
    }

    @Test("getPriceHistory respects limit parameter")
    func testPriceHistoryLimit() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "LimitHistCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "LimitHistPart", categoryId: catId)

        for i in 1...5 {
            try env.parts.logPriceChange(
                partId: partId,
                changeType: "manual",
                oldValue: Double(i),
                newValue: Double(i + 1)
            )
        }

        let limited = try env.parts.getPriceHistory(partId: partId, limit: 3)
        #expect(limited.count == 3)
    }

    // MARK: - Pricing Tiers

    @Test("setPricingTier creates a tier and getPricingTiers retrieves it")
    func testSetAndGetPricingTier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "TierCat")

        let tier = try env.parts.setPricingTier(
            categoryId: catId,
            markupPercent: 40.0,
            setBy: env.adminUserId,
            notes: "40% markup for this category"
        )
        #expect(tier.id != nil)
        #expect(tier.markupPercent == 40.0)
        #expect(tier.categoryId == catId)

        let tiers = try env.parts.getPricingTiers(categoryId: catId)
        #expect(tiers.contains(where: { $0.id == tier.id }))
    }

    @Test("setPricingTier replaces existing tier at same level")
    func testSetPricingTierReplaces() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ReplaceTierCat")

        _ = try env.parts.setPricingTier(categoryId: catId, markupPercent: 30.0)
        _ = try env.parts.setPricingTier(categoryId: catId, markupPercent: 50.0)

        let tiers = try env.parts.getPricingTiers(categoryId: catId)
        // Only one active tier should exist at the category level
        #expect(tiers.count == 1)
        #expect(tiers[0].markupPercent == 50.0)
    }

    @Test("removePricingTier soft-deletes the tier")
    func testRemovePricingTier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "RemoveTierCat")

        let tier = try env.parts.setPricingTier(categoryId: catId, markupPercent: 25.0)
        let tierId = try #require(tier.id)

        try env.parts.removePricingTier(tierId: tierId)

        let tiers = try env.parts.getPricingTiers(categoryId: catId)
        #expect(!tiers.contains(where: { $0.id == tierId }), "Removed tier should not appear")
    }

    @Test("getPricingTiers returns empty when no tiers set")
    func testGetPricingTiersEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "NoTierCat")

        let tiers = try env.parts.getPricingTiers(categoryId: catId)
        #expect(tiers.isEmpty)
    }

    // MARK: - Company Cost Settings

    @Test("getCompanyCostSetting returns nil for unknown key")
    func testGetCompanyCostSettingUnknown() throws {
        let env = try E2ETestHelpers.setUp()
        let value = try env.parts.getCompanyCostSetting(key: "nonexistent_key_xyz")
        #expect(value == nil)
    }

    @Test("updateCompanyCostSetting stores and retrieves value")
    func testUpdateCompanyCostSetting() throws {
        let env = try E2ETestHelpers.setUp()

        try env.parts.updateCompanyCostSetting(key: "default_markup_percent", value: "55", updatedBy: env.adminUserId)

        let value = try env.parts.getCompanyCostSetting(key: "default_markup_percent")
        #expect(value == "55")
    }

    @Test("updateCompanyCostSetting is idempotent — upserts on repeated calls")
    func testUpdateCompanyCostSettingUpsert() throws {
        let env = try E2ETestHelpers.setUp()

        try env.parts.updateCompanyCostSetting(key: "pricing_mode", value: "markup")
        try env.parts.updateCompanyCostSetting(key: "pricing_mode", value: "margin")

        let value = try env.parts.getCompanyCostSetting(key: "pricing_mode")
        #expect(value == "margin", "Second write should win via UPSERT")
    }

    // MARK: - findOrCreate Helpers

    @Test("findOrCreateCategory returns same ID for same name")
    func testFindOrCreateCategoryIdempotent() throws {
        let env = try E2ETestHelpers.setUp()

        let id1 = try env.parts.findOrCreateCategory(name: "Conduit")
        let id2 = try env.parts.findOrCreateCategory(name: "Conduit")
        #expect(id1 == id2, "Same name should return same category ID")
    }

    @Test("findOrCreateCategory creates new category when not found")
    func testFindOrCreateCategoryNew() throws {
        let env = try E2ETestHelpers.setUp()

        let id = try env.parts.findOrCreateCategory(name: "BoxConnectors")
        #expect(id > 0)
    }

    @Test("findOrCreateBrand returns same ID for same name")
    func testFindOrCreateBrandIdempotent() throws {
        let env = try E2ETestHelpers.setUp()

        let id1 = try env.parts.findOrCreateBrand(name: "Southwire")
        let id2 = try env.parts.findOrCreateBrand(name: "Southwire")
        #expect(id1 == id2, "Same name should return same brand ID")
    }

    @Test("findOrCreateBrand creates new brand when not found")
    func testFindOrCreateBrandNew() throws {
        let env = try E2ETestHelpers.setUp()

        let id = try env.parts.findOrCreateBrand(name: "Hubbell")
        #expect(id > 0)
    }

    // MARK: - listCatalogParts

    @Test("listCatalogParts returns all active parts with no filters")
    func testListCatalogPartsUnfiltered() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "CatalogCat")
        _ = try E2ETestHelpers.seedPart(env, name: "Catalog Part A", categoryId: catId)
        _ = try E2ETestHelpers.seedPart(env, name: "Catalog Part B", categoryId: catId)

        let result = try env.parts.listCatalogParts()
        #expect(result.totalCount >= 2)
        #expect(result.parts.count >= 1)
    }

    @Test("listCatalogParts filters by categoryId")
    func testListCatalogPartsByCategoryId() throws {
        let env = try E2ETestHelpers.setUp()
        let catA = try E2ETestHelpers.seedCategory(env, name: "CatalogCatA")
        let catB = try E2ETestHelpers.seedCategory(env, name: "CatalogCatB")
        _ = try E2ETestHelpers.seedPart(env, name: "Part in CatA", categoryId: catA)
        _ = try E2ETestHelpers.seedPart(env, name: "Part in CatB", categoryId: catB)

        let result = try env.parts.listCatalogParts(categoryId: catA)
        #expect(result.parts.allSatisfy { $0.part.categoryId == catA })
    }

    @Test("listCatalogParts search filters by name")
    func testListCatalogPartsSearch() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "SearchCat")
        _ = try E2ETestHelpers.seedPart(env, name: "UniqueSearchName XYZ123", categoryId: catId)
        _ = try E2ETestHelpers.seedPart(env, name: "Other Catalog Part", categoryId: catId)

        let result = try env.parts.listCatalogParts(search: "UniqueSearchName")
        #expect(result.parts.count >= 1)
        #expect(result.parts.allSatisfy { $0.part.name.contains("UniqueSearchName") })
    }

    @Test("listCatalogParts respects pagination")
    func testListCatalogPartsPagination() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PaginateCat")
        for i in 1...5 {
            _ = try E2ETestHelpers.seedPart(env, name: "Page Part \(i)", categoryId: catId)
        }

        let page1 = try env.parts.listCatalogParts(categoryId: catId, limit: 2, offset: 0)
        let page2 = try env.parts.listCatalogParts(categoryId: catId, limit: 2, offset: 2)

        #expect(page1.parts.count == 2)
        #expect(page2.parts.count == 2)
        // No overlap between pages
        let page1Ids = Set(page1.parts.map { $0.part.id! })
        let page2Ids = Set(page2.parts.map { $0.part.id! })
        #expect(page1Ids.isDisjoint(with: page2Ids))
    }
}
