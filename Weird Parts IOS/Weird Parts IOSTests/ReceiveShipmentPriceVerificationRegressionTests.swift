import XCTest

final class ReceiveShipmentPriceVerificationRegressionTests: XCTestCase {
    func testCompleteReceivingBlocksDifferentVerificationWithoutPositiveActualPrice() throws {
        let source = try Self.readReceiveShipmentSource()

        XCTAssertTrue(
            source.contains("let invalidDifferentItems = sessionItems.compactMap"),
            "Complete Receiving should run a preflight validation pass for .different price verifications."
        )
        XCTAssertTrue(
            source.contains("guard invalidDifferentItems.isEmpty else"),
            "Receiving should stop before session completion when any .different row has a missing or invalid actual price."
        )
        XCTAssertTrue(
            source.contains("invalidDifferentPriceItemIds = Set(invalidDifferentItems.map(\\.id))"),
            "Invalid rows should be tracked so the operator can quickly find which line items need fixes."
        )
        XCTAssertTrue(
            source.contains("Enter a valid actual price (> 0) for each 'Different' item before completing."),
            "The completion error should explain exactly why receiving was blocked."
        )
    }

    func testDifferentPriceInputPreservesRawTextAndSurfacesInlineErrorState() throws {
        let source = try Self.readReceiveShipmentSource()

        XCTAssertTrue(
            source.contains("differentPriceInputs[itemId] = newVal"),
            "The Different price text field should preserve user input instead of silently coercing invalid text to a hidden zero."
        )
        XCTAssertTrue(
            source.contains("if let parsed = Double(trimmed), parsed > 0"),
            "Only positive numeric input should be accepted as a valid Different price."
        )
        XCTAssertTrue(
            source.contains("Enter a valid price greater than 0."),
            "Invalid Different rows should show an inline message that is easy to spot."
        )
    }

    private static func readReceiveShipmentSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Orders")
            .appendingPathComponent("IOSReceiveShipmentPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
