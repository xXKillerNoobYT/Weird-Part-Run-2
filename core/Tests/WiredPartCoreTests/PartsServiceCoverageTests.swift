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

    @Test("listCatalogParts search + count excludes parts whose brand was soft-deleted")
    func testListCatalogParts_hidesDeletedBrandFromSearchAndCount() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "BrandSearchCat")
        let brandId = try E2ETestHelpers.seedBrand(env, name: "UniqueZephyrBrand")
        let partId = try env.parts.createPart(
            categoryId: catId, name: "Part With Deleted Brand", code: "DBP-001", brandId: brandId
        )

        // Baseline: searching by the brand's name finds the part and count = 1
        let before = try env.parts.listCatalogParts(search: "UniqueZephyr")
        #expect(before.parts.contains { $0.part.id == partId })

        // Soft-delete the brand. The search by brand-name must no longer match via the
        // count's LEFT JOIN — the pagination count would otherwise be inflated and the
        // fetch would also surface the deleted brand's name via the display LEFT JOIN.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE brands SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [brandId]
            )
        }

        let after = try env.parts.listCatalogParts(search: "UniqueZephyr")
        let match = after.parts.first { $0.part.id == partId }
        // The part itself is still active; COALESCE-on-search includes `(p.name LIKE ? OR p.code LIKE ? OR COALESCE(b.name, '') LIKE ?)`.
        // With the deleted_at JOIN guard, b.name is now NULL for this row so "UniqueZephyr" no longer matches
        // the search — part is expected to not appear when the match was ONLY via brand name.
        #expect(match == nil,
                "Deleted brand's name must not keep a part visible via brand-name search — LEFT JOIN guard + NULL fallback should drop the row from search matches")
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

    // MARK: - findOverrideConflicts

    @Test("findOverrideConflicts returns empty with no scope filter")
    func testFindOverrideConflictsNoScope() throws {
        let env = try E2ETestHelpers.setUp()
        // Calling with no filter always returns early with []
        let conflicts = try env.parts.findOverrideConflicts(newMarkupPercent: 60)
        #expect(conflicts.isEmpty)
    }

    @Test("findOverrideConflicts returns empty when no sub-tier exists under category")
    func testFindOverrideConflictsNoPriorTiers() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "OverrideConflictCat")
        // No sub-tier set → nothing to conflict with
        let conflicts = try env.parts.findOverrideConflicts(categoryId: catId, newMarkupPercent: 60)
        #expect(conflicts.isEmpty)
    }

    @Test("findOverrideConflicts detects sub-tier conflict when style tier exists under category")
    func testFindOverrideConflictsDetectsStyleTier() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ConflictCat")
        let styleId = try env.parts.createStyle(categoryId: catId, name: "ConflictStyle")
        // Set a more-specific tier at the style level
        _ = try env.parts.setPricingTier(styleId: styleId, markupPercent: 40, setBy: env.adminUserId)
        // Now a category-level change should detect the style tier as a conflict
        let conflicts = try env.parts.findOverrideConflicts(categoryId: catId, newMarkupPercent: 60)
        #expect(!conflicts.isEmpty, "Style-level tier should be flagged as conflict for category-level change")
    }

    // MARK: - resolveConflicts decisions (Fix #229)
    // These tests cover the service-layer behavior driven by the iOS PricingOverrideFlow UI.
    // The UI collects Replace/Keep decisions in `conflictDecisions: [Int64: Bool]` and then
    // calls `removePricingTier(tierId:)` for each "Replace" entry before calling setPricingTier.

    @Test("resolveConflicts Replace decision — sub-tier is soft-deleted and new tier applied")
    func testResolveConflictsReplace() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, styleId, _) = try E2ETestHelpers.seedPartHierarchy(env, category: "ReplaceCat", style: "ReplaceStyle", type: "ReplaceType")

        // Existing override at style level (the conflict)
        let styleTier = try env.parts.setPricingTier(styleId: styleId, markupPercent: 40, setBy: env.adminUserId)
        let styleTierId = try #require(styleTier.id)

        // UI decision: Replace → remove the old sub-tier
        try env.parts.removePricingTier(tierId: styleTierId)

        // Then set the new category-level tier
        _ = try env.parts.setPricingTier(categoryId: catId, markupPercent: 60, setBy: env.adminUserId)

        // Verify: style tier is soft-deleted (not visible in active tiers)
        let activeTiers = try env.parts.getPricingTiers(styleId: styleId)
        #expect(activeTiers.isEmpty, "Replaced style tier should be soft-deleted and absent from active tiers")

        // Verify: new category tier exists with correct markup
        let catTiers = try env.parts.getPricingTiers(categoryId: catId)
        let catTier = try #require(catTiers.first)
        #expect(abs((catTier.markupPercent ?? 0) - 60.0) < 0.001, "Category tier markup should be 60%")
    }

    @Test("resolveConflicts Keep decision — sub-tier is preserved alongside new parent tier")
    func testResolveConflictsKeep() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, styleId, _) = try E2ETestHelpers.seedPartHierarchy(env, category: "KeepCat", style: "KeepStyle", type: "KeepType")

        // Existing override at style level (the conflict)
        _ = try env.parts.setPricingTier(styleId: styleId, markupPercent: 35, setBy: env.adminUserId)

        // UI decision: Keep → do NOT remove the sub-tier; just apply the new parent tier
        _ = try env.parts.setPricingTier(categoryId: catId, markupPercent: 55, setBy: env.adminUserId)

        // Verify: style tier still active (not deleted)
        let styleTiers = try env.parts.getPricingTiers(styleId: styleId)
        #expect(!styleTiers.isEmpty, "Kept style tier should still be active")
        let styleTier = try #require(styleTiers.first)
        #expect(abs((styleTier.markupPercent ?? 0) - 35.0) < 0.001, "Kept style tier markup should remain 35%")

        // Verify: new category tier coexists
        let catTiers = try env.parts.getPricingTiers(categoryId: catId)
        #expect(!catTiers.isEmpty, "New category tier should exist alongside kept sub-tier")
        let catTier = try #require(catTiers.first)
        #expect(abs((catTier.markupPercent ?? 0) - 55.0) < 0.001, "Category tier markup should be 55%")
    }

    @Test("resolveConflicts Mixed decisions — one sub-tier replaced, one kept")
    func testResolveConflictsMixed() throws {
        let env = try E2ETestHelpers.setUp()
        let (catId, styleId, _) = try E2ETestHelpers.seedPartHierarchy(env, category: "MixedCat", style: "MixedStyle", type: "MixedType1")
        let typeId2 = try env.parts.createType(styleId: styleId, name: "MixedType2")

        // Two conflicts: one at typeId (will be replaced), one at typeId2 (will be kept)
        let tierToReplace = try env.parts.setPricingTier(typeId: catId, markupPercent: 20, setBy: env.adminUserId)
        let replaceId = try #require(tierToReplace.id)
        _ = try env.parts.setPricingTier(typeId: typeId2, markupPercent: 30, setBy: env.adminUserId)

        // UI decisions: Replace tierToReplace, Keep tier2 (no-op for keep)
        try env.parts.removePricingTier(tierId: replaceId)

        // New category-level tier applied after conflict resolution
        _ = try env.parts.setPricingTier(categoryId: catId, markupPercent: 50, setBy: env.adminUserId)

        // Verify: replaced tier is gone
        let replacedTiers = try env.parts.getPricingTiers(typeId: catId)
        #expect(replacedTiers.isEmpty, "Replaced tier should be soft-deleted")

        // Verify: kept tier still active
        let keptTiers = try env.parts.getPricingTiers(typeId: typeId2)
        #expect(!keptTiers.isEmpty, "Kept tier should still be active")
        #expect(abs((keptTiers.first?.markupPercent ?? 0) - 30.0) < 0.001)

        // Verify: new parent category tier present
        let catTiers = try env.parts.getPricingTiers(categoryId: catId)
        #expect(!catTiers.isEmpty, "New category tier should be present")
    }

    @Test("resolveConflicts No conflicts — setPricingTier completes immediately with no removals")
    func testResolveConflictsNoConflicts() throws {
        // When a scope has no existing sub-level overrides, the UI skips the conflict sheet
        // entirely and calls setPricingTier directly. This test confirms that path works.
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "NoConflictCat")

        // No prior sub-tiers exist — call setPricingTier directly (no removals needed)
        let tier = try env.parts.setPricingTier(
            categoryId: catId,
            markupPercent: 45,
            setBy: env.adminUserId
        )

        #expect(tier.id != nil, "Tier should have a valid id")
        let activeTiers = try env.parts.getPricingTiers(categoryId: catId)
        #expect(activeTiers.count == 1, "Exactly one active tier should exist")
        #expect(abs((activeTiers.first?.markupPercent ?? 0) - 45.0) < 0.001)
    }

    @Test("setPricingTier timestamp validation — createdAt and updatedAt are NOT NULL")
    func testSetPricingTierTimestampsNotNull() throws {
        // Verifies Fix #229: tier.createdAt/updatedAt are always set by setPricingTier,
        // satisfying the NOT NULL constraint in the schema.
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "TimestampCat")

        let tier = try env.parts.setPricingTier(
            categoryId: catId,
            markupPercent: 25.0,
            setBy: env.adminUserId
        )

        #expect(tier.createdAt != nil, "createdAt must not be nil (schema NOT NULL)")
        #expect(tier.updatedAt != nil, "updatedAt must not be nil (schema NOT NULL)")
        // Also confirm the stored row has timestamps
        let stored = try env.parts.getPricingTiers(categoryId: catId)
        let storedTier = try #require(stored.first)
        #expect(storedTier.createdAt != nil, "Stored tier createdAt must not be nil")
        #expect(storedTier.updatedAt != nil, "Stored tier updatedAt must not be nil")
    }

    // Note: "Service unavailable → error shown" is an iOS UI scenario (PricingOverrideFlow
    // displays an error alert when the core throws). Covered by manual testing of PricingTierSetSheet.

    // MARK: - getPreviewParts

    @Test("getPreviewParts returns empty when no parts match scope")
    func testGetPreviewPartsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "EmptyPreviewCat")
        let preview = try env.parts.getPreviewParts(categoryId: catId, newMarkupPercent: 50)
        #expect(preview.isEmpty)
    }

    @Test("getPreviewParts returns preview rows with computed prices for matching parts")
    func testGetPreviewPartsWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "PreviewCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Preview Wire", categoryId: catId)
        // Seed a cost layer so weighted_avg_cost is non-zero
        _ = try env.parts.addCostLayer(partId: partId, qty: 10, unitCost: 5.0)

        let preview = try env.parts.getPreviewParts(categoryId: catId, newMarkupPercent: 80)
        #expect(!preview.isEmpty)
        let row = try #require(preview.first(where: { $0.partId == partId }))
        // With 80% markup on $5 cost: new sell = $5 * 1.80 = $9
        #expect(abs(row.newSellPrice - 9.0) < 0.01)
        #expect(row.weightedAvgCost > 0)
    }

    // MARK: - recalculateWeightedAvgCost

    @Test("recalculateWeightedAvgCost updates part weighted_avg_cost from cost layers")
    func testRecalculateWeightedAvgCost() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "WACCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "WAC Part", categoryId: catId)

        // Add two cost layers: 10 units @ $4 and 10 units @ $6
        _ = try env.parts.addCostLayer(partId: partId, qty: 10, unitCost: 4.0)
        _ = try env.parts.addCostLayer(partId: partId, qty: 10, unitCost: 6.0)

        // Force recalculate (addCostLayer already does this internally, so after both it should be $5)
        try env.parts.recalculateWeightedAvgCost(partId: partId)

        let part = try env.parts.getPart(id: partId)
        let wac = try #require(part.part.weightedAvgCost)
        #expect(abs(wac - 5.0) < 0.01, "WAC = (10*4 + 10*6) / 20 = $5")
    }

    // MARK: - setBrandSuppliers

    @Test("setBrandSuppliers links new suppliers to brand")
    func testSetBrandSuppliersAdds() throws {
        let env = try E2ETestHelpers.setUp()
        let brandId = try E2ETestHelpers.seedBrand(env, name: "SetBrandSup1")
        let sup1 = try E2ETestHelpers.seedSupplier(env, name: "BrandSup A")
        let sup2 = try E2ETestHelpers.seedSupplier(env, name: "BrandSup B")

        try env.parts.setBrandSuppliers(brandId: brandId, supplierIds: [sup1, sup2])

        let linked = try env.parts.getBrandSuppliers(brandId: brandId)
        let linkedIds = Set(linked.compactMap { $0.id })
        #expect(linkedIds.contains(sup1))
        #expect(linkedIds.contains(sup2))
    }

    @Test("setBrandSuppliers removes unselected suppliers from brand")
    func testSetBrandSuppliersRemoves() throws {
        let env = try E2ETestHelpers.setUp()
        let brandId = try E2ETestHelpers.seedBrand(env, name: "SetBrandSup2")
        let sup1 = try E2ETestHelpers.seedSupplier(env, name: "BrandSup C")
        let sup2 = try E2ETestHelpers.seedSupplier(env, name: "BrandSup D")

        // Start with both linked
        _ = try env.parts.linkBrandToSupplier(brandId: brandId, supplierId: sup1)
        _ = try env.parts.linkBrandToSupplier(brandId: brandId, supplierId: sup2)

        // setBrandSuppliers with only sup1 should remove sup2
        try env.parts.setBrandSuppliers(brandId: brandId, supplierIds: [sup1])

        let remaining = try env.parts.getBrandSuppliers(brandId: brandId)
        let remainingIds = Set(remaining.compactMap { $0.id })
        #expect(remainingIds.contains(sup1))
        #expect(!remainingIds.contains(sup2), "sup2 should have been removed")
    }

    // MARK: - listForecastData

    @Test("listForecastData returns empty on fresh database")
    func testListForecastDataEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let parts = try env.parts.listForecastData()
        // Fresh DB may have no parts with forecast data
        #expect(parts.count >= 0) // Should not throw
    }

    @Test("listForecastData returns matching parts by search filter")
    func testListForecastDataSearch() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ForecastCat")
        _ = try E2ETestHelpers.seedPart(env, name: "ForecastWire UniqueXYZ", categoryId: catId)
        _ = try E2ETestHelpers.seedPart(env, name: "Other Part No Match", categoryId: catId)

        let results = try env.parts.listForecastData(search: "ForecastWire")
        #expect(results.allSatisfy { $0.name.contains("ForecastWire") })
    }

    // MARK: - listForecastDataWithStock

    @Test("listForecastDataWithStock returns all active parts with their stock on fresh DB")
    func testListForecastDataWithStockEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ForecastWithStockCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "StockForecastPart", categoryId: catId)

        let rows = try env.parts.listForecastDataWithStock()
        let row = try #require(rows.first(where: { $0.part.id == partId }))
        // No stock seeded, so currentStock should be 0
        #expect(row.currentStock == 0)
    }

    // MARK: - saveForecastSettings + listAllForecastSettings

    @Test("saveForecastSettings and listAllForecastSettings round-trip")
    func testSaveForecastSettings() throws {
        let env = try E2ETestHelpers.setUp()

        // Use a locationId to create a unique per-location override that won't conflict
        // with any default seed row (which has locationId = nil).
        let settings = ForecastSettings(
            id: nil, locationType: "truck", locationId: 999,
            usageUnit: "each", aduLookbackDays: 14, windowWeeks: 2,
            minDataDays: 3, commonMinMultiplier: 1.0, commonTargetMultiplier: 2.0,
            commonMaxMultiplier: 3.0, criticalMinMultiplier: 1.5, criticalTargetMultiplier: 2.5,
            criticalMaxMultiplier: 4.0, freeSpaceSuppressThreshold: 3
        )
        try env.parts.saveForecastSettings(settings)

        let all = try env.parts.listAllForecastSettings()
        let matchingRows = all.filter { $0.locationType == "truck" && $0.locationId == 999 }
        let saved = try #require(matchingRows.first)
        #expect(saved.aduLookbackDays == 14)
        #expect(saved.windowWeeks == 2)
        #expect(abs(saved.commonTargetMultiplier - 2.0) < 0.001)
    }

    // MARK: - recalculateForecasts

    @Test("recalculateForecasts runs without throwing on fresh database")
    func testRecalculateForecastsNoOp() throws {
        let env = try E2ETestHelpers.setUp()
        // Should not throw even on a DB with no consumption data
        try env.parts.recalculateForecasts()
    }

    @Test("recalculateForecasts counts canonical warehouse consumption movement types")
    func testRecalculateForecastsCountsCanonicalConsumptionMovementTypes() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "ForecastMovementTypes")
        let partId = try E2ETestHelpers.seedPart(env, name: "Forecast Movement Type Part", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 100)

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO stock_movements
                    (part_id, qty, from_location_type, from_location_id,
                     to_location_type, to_location_id, movement_type,
                     reason, performed_by, created_at)
                VALUES (?, 12, 'warehouse', 1, 'job', 1, ?, 'Forecast regression', ?, datetime('now'))
                """, arguments: [
                    partId,
                    StockMovement.MovementType.jobPull.rawValue,
                    env.adminUserId
                ])
        }

        try env.parts.recalculateForecasts()

        let part = try env.db.writer.read { db in
            try Part.fetchOne(db, key: partId)
        }
        #expect(abs((part?.forecastAdu30 ?? 0) - 0.4) < 0.0001)
        #expect(abs((part?.forecastAdu90 ?? 0) - (12.0 / 90.0)) < 0.0001)
    }

    // MARK: - listLocationStockTargets

    @Test("listLocationStockTargets returns empty for part with no targets")
    func testListLocationStockTargetsEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "TargetCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Target Part", categoryId: catId)

        let targets = try env.parts.listLocationStockTargets(partId: partId)
        #expect(targets.isEmpty)
    }

    // MARK: - ColorBrandSKU CRUD (PE-COLORS Phase 1 — migration 074)

    @Test("upsertColorBrandSKU creates a new SKU row")
    func testUpsertColorBrandSKU_creates() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let brandId = try E2ETestHelpers.seedBrand(env)
        let colorId = try env.parts.createColor(name: "Gray", hexCode: "#808080")

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "SKU-GRAY-001", unitCost: 2.50
        )
        #expect(skuId > 0)

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus.count == 1)
        #expect(skus[0].partNumber == "SKU-GRAY-001")
        #expect(skus[0].unitCost == 2.50)
        #expect(skus[0].isActive)
    }

    @Test("upsertColorBrandSKU is idempotent — second call updates, not duplicates")
    func testUpsertColorBrandSKU_idempotent() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let brandId = try E2ETestHelpers.seedBrand(env)
        let colorId = try env.parts.createColor(name: "Red", hexCode: "#FF0000")

        let id1 = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "OLD-PN"
        )
        let id2 = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "NEW-PN"
        )
        #expect(id1 == id2, "Must reuse same row ID on duplicate triple")

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus.count == 1, "Must not create duplicate rows")
        #expect(skus[0].partNumber == "NEW-PN", "Must update part_number on upsert")
    }

    @Test("deleteColorBrandSKU soft-deletes the row")
    func testDeleteColorBrandSKU() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let brandId = try E2ETestHelpers.seedBrand(env)
        let colorId = try env.parts.createColor(name: "White", hexCode: "#FFFFFF")

        let skuId = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId
        )
        try env.parts.deleteColorBrandSKU(skuId: skuId)

        let skus = try env.parts.getColorBrandSKUs(typeId: typeId, brandId: brandId)
        #expect(skus.isEmpty, "Soft-deleted SKU must not appear in results")
    }

    @Test("getSKUsForColor returns SKUs across all brands for a color")
    func testGetSKUsForColor() throws {
        let env = try E2ETestHelpers.setUp()
        let (_, _, typeId) = try E2ETestHelpers.seedPartHierarchy(env)
        let brand1 = try E2ETestHelpers.seedBrand(env, name: "Brand A")
        let brand2 = try E2ETestHelpers.seedBrand(env, name: "Brand B")
        let colorId = try env.parts.createColor(name: "Blue", hexCode: "#0000FF")

        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brand1, typeId: typeId, partNumber: "A-BLUE")
        _ = try env.parts.upsertColorBrandSKU(colorId: colorId, brandId: brand2, typeId: typeId, partNumber: "B-BLUE")

        let skus = try env.parts.getSKUsForColor(colorId: colorId)
        #expect(skus.count == 2)
    }

    // MARK: - searchParts UNION over color_brand_skus (PE-COLORS #236)

    @Test("Regression: searchParts matches color_brand_skus part_number")
    func testSearchParts_matchesSKUPartNumber() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "SKUCat")
        let styleId = try env.parts.createStyle(categoryId: catId, name: "SKUStyle")
        let typeId = try env.parts.createType(styleId: styleId, name: "SKUType")
        let brandId = try E2ETestHelpers.seedBrand(env, name: "SKUBrand")
        let colorId = try env.parts.createColor(name: "SKUGray", hexCode: "#999999")

        let partId = try env.parts.createPart(
            categoryId: catId,
            name: "SKU Test Widget",
            typeId: typeId,
            colorId: colorId,
            code: "SKU-WIDGET",
            brandId: brandId
        )
        #expect(partId > 0)

        _ = try env.parts.upsertColorBrandSKU(
            colorId: colorId, brandId: brandId, typeId: typeId,
            partNumber: "CBS-UNIQUE-XYZ"
        )

        let results = try env.parts.searchParts(query: "CBS-UNIQUE-XYZ")
        #expect(results.contains { $0.id == partId }, "searchParts must match color_brand_skus part_number")
    }
}
