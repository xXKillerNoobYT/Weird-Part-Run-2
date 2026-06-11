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
            source.contains("ContentUnavailableView") && source.contains("No SKU Rows Yet"),
            "Expanded type/brand nodes with zero SKU rows should show a ContentUnavailableView empty state."
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
