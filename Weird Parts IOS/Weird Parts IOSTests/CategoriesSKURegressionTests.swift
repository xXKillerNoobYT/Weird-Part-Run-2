import XCTest

final class CategoriesSKURegressionTests: XCTestCase {
    func testTreeShowsSKURowsAndEmptyStateForTypeBrandNodes() throws {
        let source = try Self.readPartsSource(named: "CategoriesTreeView.swift")

        XCTAssertTrue(
            source.contains("ForEach(brandSKUs, id: \\.id) { sku in"),
            "Categories tree should render color_brand_skus rows under each type/brand node."
        )
        XCTAssertTrue(
            source.contains("selection = .sku(skuId: sku.id, typeId: typeId, brandId: sku.brandId, colorId: sku.colorId)"),
            "Tapping a SKU row should select that SKU for the right-side editor panel."
        )
        XCTAssertTrue(
            source.contains("EmptyStateView(") && source.contains("No SKU Rows Yet"),
            "Expanded type/brand nodes with zero SKU rows should show the standard EmptyStateView empty state."
        )
    }

    func testEditorRoutesSkuSelectionAndPersistsWithInlineErrors() throws {
        let source = try Self.readPartsSource(named: "CategoriesEditorPanel.swift")

        XCTAssertTrue(
            source.contains("case .sku(let skuId, let typeId, let brandId, let colorId):"),
            "Editor panel should route SKU tree selections to the SKU editor."
        )
        XCTAssertTrue(
            source.contains("try service.updateColorBrandSKU("),
            "SKU editor should persist edits through the SKU update service call."
        )
        XCTAssertTrue(
            source.contains("userFriendlyError(error, context: \"save SKU row\")"),
            "SKU save failures should be shown inline with user-friendly feedback."
        )
    }

    func testColorPriceResolutionFailuresShowUnavailableState() throws {
        let source = try Self.readPartsSource(named: "CategoriesTreeView.swift")

        XCTAssertTrue(
            source.contains("enum ColorPriceCacheEntry") && source.contains("case unavailable"),
            "The color price cache should preserve failed lookups as an explicit unavailable state."
        )
        XCTAssertTrue(
            source.contains("categoryPriceLog.error") && source.contains("colorId=\\(colorId, privacy: .public) typeId=\\(typeId, privacy: .public)"),
            "Failed price lookups should log colorId and typeId for debugging."
        )
        XCTAssertTrue(
            source.contains("struct ColorPriceCacheKey: Hashable") &&
            source.contains("let colorId: Int64") &&
            source.contains("let typeId: Int64"),
            "The color price cache key should include both colorId and typeId because effective price lookup is type-specific."
        )
        XCTAssertTrue(
            source.contains("cache[cacheKey] = .unavailable") &&
            source.contains("priceChipState(for colorId: Int64, typeId: Int64") &&
            source.contains("ColorPriceCacheKey(colorId: colorId, typeId: typeId)"),
            "Failed lookups should be cached and rendered per color/type pair so one type cannot overwrite another."
        )
        XCTAssertTrue(
            source.contains("Price unavailable"),
            "Rows with failed price resolution should render a visible unavailable chip instead of falling back to No price."
        )
        XCTAssertTrue(
            source.contains("Pricing unavailable: parts service is not ready.") && source.contains("unavailablePriceCache(for: hierarchy)"),
            "A missing parts service should create a visible pricing unavailable state for the hierarchy."
        )
    }

    private static func readPartsSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
