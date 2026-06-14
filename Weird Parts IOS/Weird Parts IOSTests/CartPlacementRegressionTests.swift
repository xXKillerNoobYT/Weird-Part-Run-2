import XCTest

/// Regression tests for GitHub #975 / WEI-3584.
///
/// Cart placement must fail closed when persistence is unavailable or throws;
/// otherwise unsaved warehouse cart items can be counted as placed and cleared.
final class CartPlacementRegressionTests: XCTestCase {

    func testPartPlacementRequiresLoadedPartsServiceBeforeCountingSuccess() throws {
        let source = try Self.readCartManagerSource()

        XCTAssertTrue(
            source.contains("guard let service else"),
            "CartManager.placeAllItems() should fail closed when appCore.partsService is nil instead of treating optional updatePart as a no-op success."
        )
        XCTAssertFalse(
            source.contains("try service?.updatePart"),
            "Optional chaining on updatePart silently succeeds when partsService is nil, causing unsaved items to be counted as placed."
        )
    }

    func testFailedPartUpdateLeavesItemUnplacedAndUserVisible() throws {
        let source = try Self.readCartManagerSource()

        XCTAssertTrue(
            source.contains("failedPartIDs.insert(item.id)"),
            "Thrown updatePart failures should track failed cart item IDs so they remain visible/retryable."
        )
        XCTAssertTrue(
            source.contains("placed.subtract(failedPartIDs)"),
            "Failed part updates must be removed from the placed set before CartManager updates UI state."
        )
        XCTAssertTrue(
            source.contains("placementError = msg"),
            "Failed placement attempts should surface actionable error feedback instead of silently clearing/dismissing."
        )
    }

    private static func readCartManagerSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("CartManager.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
