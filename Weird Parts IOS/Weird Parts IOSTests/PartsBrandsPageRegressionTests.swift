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
        XCTAssertTrue(
            source.contains("presentAddSuppliersPicker(for: brandId)"),
            "The parent callback should route post-create supplier linking through the guarded presenter."
        )
        XCTAssertTrue(
            source.contains("if activeSheet == nil") && source.contains("activeSheet = .addBrandSuppliers(brandId)"),
            "The guarded presenter should immediately show the supplier picker if the add-brand sheet has already dismissed."
        )
    }

    func testBrandDetailRefreshesDisplayedBrandAfterEditAndSupplierSave() throws {
        let source = try Self.readPartsBrandsPageSource()

        XCTAssertTrue(
            source.contains("@State private var displayedBrand: BrandListRow"),
            "Brand detail should keep a refreshed local row instead of rendering the immutable row passed when the sheet opened."
        )
        XCTAssertTrue(
            source.contains("refreshDisplayedBrand()"),
            "Brand detail should reload the displayed row after edit/save flows so edited text and supplier count appear without closing the sheet."
        )
        XCTAssertTrue(
            source.contains("displayedBrand = BrandListRow("),
            "Refresh should rebuild the displayed row from PartsService.listBrands so brand fields and supplier counts match the saved database state."
        )
        XCTAssertTrue(
            source.contains("await refreshDisplayedBrand()") && source.contains("await onUpdate()"),
            "Edit and supplier save callbacks should refresh the detail sheet and notify the parent list."
        )
        XCTAssertFalse(
            source.contains("LabeledContent(\"Name\", value: brand.name)"),
            "Brand detail must not render stale immutable brand.name after an edit."
        )
    }

    func testNewSupplierFormCanLinkExistingBrandsDuringCreation() throws {
        let source = try Self.readPartsSuppliersPageSource()

        XCTAssertTrue(
            source.contains("@State private var availableBrandsForNewSupplier"),
            "New supplier flow should load existing brands so the user can choose what the supplier carries while creating it."
        )
        XCTAssertTrue(
            source.contains("Text(\"Brands Carried\")"),
            "Supplier creation should visibly ask which existing brands this supplier carries."
        )
        XCTAssertTrue(
            source.contains("selectedBrandIdsForNewSupplier"),
            "Supplier creation should keep an explicit selected-brand set for existing brand links."
        )
        XCTAssertTrue(
            source.contains("let newSupplierId = try service.createSupplier"),
            "Supplier creation must keep the new supplier id so brand links can be saved immediately."
        )
        XCTAssertTrue(
            source.contains("try service.setSupplierBrands(") && source.contains("supplierId: newSupplierId"),
            "After creating a supplier, the form should persist selected existing brand links."
        )
    }

    private static func readPartsBrandsPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        try readPartsPageSource(named: "PartsBrandsPage.swift", file: file)
    }

    private static func readPartsSuppliersPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        try readPartsPageSource(named: "PartsSuppliersPage.swift", file: file)
    }

    private static func readPartsPageSource(named filename: String, file: StaticString = #filePath) throws -> String {
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
