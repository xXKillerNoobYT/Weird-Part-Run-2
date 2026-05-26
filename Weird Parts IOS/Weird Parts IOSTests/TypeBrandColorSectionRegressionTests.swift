import XCTest

final class TypeBrandColorSectionRegressionTests: XCTestCase {
    func testTypeBrandColorSectionUsesSelectedBrandChipStripAndSelectedBrandRows() throws {
        let source = try Self.readTypeBrandColorSectionSource()

        XCTAssertTrue(
            source.contains("ScrollView(.horizontal, showsIndicators: false)"),
            "TypeBrandColorSection should render linked brands as a horizontal chip strip."
        )
        XCTAssertTrue(
            source.contains("ForEach(linkedBrands, id: \\.id)"),
            "Brand chip strip should iterate the type-linked brands."
        )
        XCTAssertTrue(
            source.contains(".filter { $0.sku.brandId == selectedBrandId }"),
            "SKU rows should be filtered to the currently selected brand."
        )
    }

    func testTypeBrandColorSectionAddAndDeleteSkuFlowsUseSkuApis() throws {
        let source = try Self.readTypeBrandColorSectionSource()

        XCTAssertTrue(
            source.contains("Label(\"Add SKU\", systemImage: \"plus.circle.fill\")"),
            "The action should present as Add SKU for selected-brand SKU creation."
        )
        XCTAssertTrue(
            source.contains("private func createSKU(") && source.contains("service.upsertColorBrandSKU("),
            "Add SKU should create a color_brand_skus row through the SKU create path."
        )
        XCTAssertTrue(
            source.contains("private func deleteSKU(service: PartsService, skuId: Int64) throws") && source.contains("service.deleteColorBrandSKU(skuId: skuId)"),
            "Remove SKU should soft-delete through the SKU delete path."
        )
    }

    func testTypeBrandColorSectionAddSkuSheetLocksBrandAndPicksVariantFromGlobalPool() throws {
        let source = try Self.readTypeBrandColorSectionSource()

        XCTAssertTrue(
            source.contains("Section(\"Brand\")") && source.contains("Text(brand.name)"),
            "Add SKU sheet should keep the selected brand fixed when creating rows."
        )
        XCTAssertTrue(
            source.contains("Picker(\"Variant\", selection: $selectedColorId)") && source.contains("private var selectableColors: [PartColor]"),
            "Add SKU sheet should pick variants from the global part_colors pool."
        )
        XCTAssertFalse(
            source.contains("Picker(\"Brand\", selection:"),
            "Add SKU sheet should no longer imply brand-scoped variant picking with a brand picker."
        )
    }

    private static func readTypeBrandColorSectionSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent("TypeBrandColorSection.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
