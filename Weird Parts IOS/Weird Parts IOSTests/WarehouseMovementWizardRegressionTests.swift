import XCTest

final class WarehouseMovementWizardRegressionTests: XCTestCase {
    func testMovementWizardFailsClosedWhenStockCannotBeLoaded() throws {
        let source = try Self.readMovementWizardSource()

        XCTAssertFalse(
            source.contains("availableQty: part.availableQty ?? 999"),
            "Movement wizard must not convert missing stock into a permissive 999 fallback."
        )
        XCTAssertFalse(
            source.contains("var availableQty = 999"),
            "Scanned part flow must not initialize available quantity to permissive sentinel stock."
        )
        XCTAssertTrue(
            source.contains("guard let availableQty = part.availableQty else"),
            "Selecting a part from search results should fail closed when stock data is missing."
        )
        XCTAssertTrue(
            source.contains("guard let service = appCore.partsService else"),
            "Scanned part flow should show an actionable error when the stock service is unavailable."
        )
        XCTAssertTrue(
            source.contains("partSelectionError = \"Unable to add") && source.contains("stock could not be loaded"),
            "Wizard should surface an actionable stock-loading error instead of silently permitting unknown stock."
        )
    }

    private static func readMovementWizardSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("IOSMovementWizard.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
