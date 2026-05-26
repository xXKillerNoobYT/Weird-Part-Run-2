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

    func testNewSupplierCreationCanPromptForBrandPickerAfterSave() throws {
        let source = try Self.readPartsSuppliersPageSource()

        XCTAssertTrue(
            source.contains("case addSupplierBrands(Int64)"),
            "PartsSuppliersPage should have a dedicated sheet route for the post-create brand picker."
        )
        XCTAssertTrue(
            source.contains("SupplierBrandPickerSheet(supplierId: supplierId)"),
            "The post-create route must present SupplierBrandPickerSheet for the newly created supplier."
        )
        XCTAssertTrue(
            source.contains("onAddBrands?(supplierId)"),
            "The Add Brands prompt should call through to the parent so the picker opens after dismissal."
        )
        XCTAssertTrue(
            source.contains("presentAddBrandsPicker(for: supplierId)"),
            "The parent callback should route post-create brand linking through the guarded presenter."
        )
        XCTAssertTrue(
            source.contains(".alert(\"Add Brands?\", isPresented: $showAddBrandsPrompt)"),
            "New supplier save flow should show an Add Brands prompt before dismissing."
        )
        XCTAssertTrue(
            source.contains("supplier.brandCount == 0") && source.contains("Label(\"No brands\", systemImage: \"exclamationmark.triangle.fill\")"),
            "Supplier rows should show an orange no-brands indicator when prompt is skipped."
        )
        XCTAssertTrue(
            source.contains("try service.addBrandSupplier("),
            "Supplier brand picker should link each selected brand via addBrandSupplier."
        )
        XCTAssertFalse(
            source.contains("initialBrandIds: selectedBrandIdsForNewSupplier"),
            "Post-save picker flow should no longer rely on initialBrandIds at supplier create time."
        )
    }

    func testWeeklyReviewSheetUsesDirtyDismissSafetyAndBaselineCapture() throws {
        let source = try Self.readJobsPageSource(named: "IOSWeeklyReviewSheet.swift")

        XCTAssertTrue(
            source.contains("@State private var showDiscardConfirmation = false"),
            "Weekly review should track discard confirmation state for cancel flow."
        )
        XCTAssertTrue(
            source.contains("private var isDirty: Bool"),
            "Weekly review should compute dirty state from editable fields."
        )
        XCTAssertTrue(
            source.contains(".dismissSafety(") &&
                source.contains("isDirty: isDirty") &&
                source.contains("isSaving: isSubmitting"),
            "Weekly review should block swipe dismiss while dirty or submitting."
        )
        XCTAssertTrue(
            source.contains("DismissSafety.cancelOrConfirm("),
            "Weekly review cancel should confirm before discarding dirty edits."
        )
        XCTAssertTrue(
            source.contains("captureInitialState()") &&
                source.contains("private func captureInitialState()"),
            "Weekly review should capture baseline state after load/save so dirty detection resets correctly."
        )
    }

    func testTradeResponseSheetUsesDirtyDismissSafety() throws {
        let source = try Self.readToolsPageSource()

        XCTAssertTrue(
            source.contains("struct TradeResponseSheet: View {"),
            "Tools detail page should include TradeResponseSheet."
        )
        XCTAssertTrue(
            source.contains("@State private var showDiscardConfirmation = false"),
            "Trade response should track discard confirmation state."
        )
        XCTAssertTrue(
            source.contains("private var isDirty: Bool"),
            "Trade response should compute dirty state from changed condition/notes."
        )
        XCTAssertTrue(
            source.contains(".dismissSafety(") &&
                source.contains("showDiscardConfirmation: $showDiscardConfirmation"),
            "Trade response should use shared dismiss safety guard."
        )
        XCTAssertTrue(
            source.contains("DismissSafety.cancelOrConfirm("),
            "Trade response cancel should confirm before discarding dirty edits."
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

    private static func readJobsPageSource(
        named filename: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readToolsPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Tools")
            .appendingPathComponent("IOSToolDetailPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
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
