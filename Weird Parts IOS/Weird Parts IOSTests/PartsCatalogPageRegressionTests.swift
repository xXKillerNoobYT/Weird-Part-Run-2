import XCTest

final class PartsCatalogPageRegressionTests: XCTestCase {
    func testCatalogFormsValidateNumericPricingInputBeforeSaving() throws {
        let source = try Self.readPartsCatalogPageSource()

        XCTAssertTrue(
            source.contains("Cost price must be a valid number.") && source.contains("Markup must be a valid number."),
            "Catalog quick edit and full form should show inline validation messages when pricing text is not numeric."
        )
        XCTAssertTrue(
            source.contains("@State private var pricingValidationError: String?"),
            "Catalog edit sheets should track inline pricing validation state."
        )
        XCTAssertTrue(
            source.contains("guard let pricing = parsePricingInputs() else { return }"),
            "Save flows should stop before updatePart/createPart when pricing parsing fails."
        )
        XCTAssertFalse(
            source.contains("let cost = Double(costPrice) ?? 0"),
            "Catalog save flow must not coerce invalid cost input to zero."
        )
        XCTAssertFalse(
            source.contains("let markup = Double(markupPercent) ?? 0"),
            "Catalog save flow must not coerce invalid markup input to zero."
        )
    }

    private static func readPartsCatalogPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent("PartsCatalogPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
