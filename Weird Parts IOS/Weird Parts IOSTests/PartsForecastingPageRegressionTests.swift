import XCTest

final class PartsForecastingPageRegressionTests: XCTestCase {
    func testThresholdEditorUsesExplicitIntegerValidationInsteadOfZeroFallback() throws {
        let source = try Self.readPartsForecastingPageSource()

        XCTAssertTrue(
            source.contains("parseStockField"),
            "Forecast threshold saves should parse each field through an explicit validator."
        )
        XCTAssertTrue(
            source.contains("trimmingCharacters(in: .whitespacesAndNewlines)"),
            "Threshold parsing should trim pasted whitespace before validating whole-number input."
        )
        XCTAssertTrue(
            source.contains("must be a whole number"),
            "Invalid Min/Target/Max input should produce a field-specific whole-number validation error."
        )
        XCTAssertFalse(
            source.contains("Int(editMinStock) ?? 0") ||
            source.contains("Int(editTargetStock) ?? 0") ||
            source.contains("Int(editMaxStock) ?? 0"),
            "Threshold parsing must not silently coerce invalid Min/Target/Max input to zero."
        )
    }

    private static func readPartsForecastingPageSource(
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
            .appendingPathComponent("PartsForecastingPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
