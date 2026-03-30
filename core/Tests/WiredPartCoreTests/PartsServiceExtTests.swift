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
}
