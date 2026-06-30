import XCTest

final class PartsForecastingPageRegressionTests: XCTestCase {
    func testForecastStockTargetsRejectMalformedTextInsteadOfDefaultingToZero() throws {
        let source = try Self.readPartsForecastingPageSource()

        XCTAssertTrue(
            source.contains("guard let min = parseStockTarget(editMinStock, fieldName: \"Min\") else { return }"),
            "Saving forecast settings should parse min stock through the required whole-number validator."
        )
        XCTAssertTrue(
            source.contains("guard let target = parseStockTarget(editTargetStock, fieldName: \"Target\") else { return }"),
            "Saving forecast settings should parse target stock through the required whole-number validator."
        )
        XCTAssertTrue(
            source.contains("guard let max = parseStockTarget(editMaxStock, fieldName: \"Max\") else { return }"),
            "Saving forecast settings should parse max stock through the required whole-number validator."
        )
        XCTAssertTrue(
            source.contains("editError = \"\\(fieldName) stock must be a whole number\""),
            "Malformed stock target input should leave a field-specific visible validation error."
        )
        XCTAssertTrue(
            source.contains("trimmingCharacters(in: .whitespacesAndNewlines)"),
            "Stock target parsing should accept padded whole-number text without treating whitespace as malformed."
        )
        XCTAssertTrue(
            source.contains("value >= 0"),
            "Stock targets should remain non-negative whole numbers."
        )
        XCTAssertFalse(
            source.contains("Int(editMinStock) ?? 0") ||
                source.contains("Int(editTargetStock) ?? 0") ||
                source.contains("Int(editMaxStock) ?? 0"),
            "Malformed stock target input must never be coerced to zero on save."
        )
    }

    private static func readPartsForecastingPageSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Parts")
            .appendingPathComponent("PartsForecastingPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
