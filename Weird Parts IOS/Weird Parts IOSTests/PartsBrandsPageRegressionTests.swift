import XCTest

final class PartsBrandsPageRegressionTests: XCTestCase {
    func testNewBrandAddSuppliersActionPresentsSupplierPickerInsteadOfOnlyDismissing() throws {
        let source = try Self.readPartsBrandsPageSource()

        XCTAssertTrue(
            source.contains("case addBrandSuppliers(Int64)"),
            "PartsBrandsPage should have a dedicated sheet route for the post-create supplier picker."
        )
        XCTAssertTrue(
            source.contains("BrandSupplierPickerSheet(brandId: brandId)"),
            "The post-create route must present BrandSupplierPickerSheet for the newly created brand."
        )
        XCTAssertTrue(
            source.contains("onAddSuppliers?(brandId)"),
            "The Add Suppliers prompt should call through to the parent instead of dismissing as a dead-end."
        )
    }

    private static func readPartsBrandsPageSource(
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
            .appendingPathComponent("PartsBrandsPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
