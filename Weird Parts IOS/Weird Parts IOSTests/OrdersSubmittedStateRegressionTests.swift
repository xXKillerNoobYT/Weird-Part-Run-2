import XCTest

final class OrdersSubmittedStateRegressionTests: XCTestCase {
    func testSubmittedStateCopyAndActionsAvoidImplicitSupplierTransmission() throws {
        let detailSource = try Self.readOrdersPageSource(
            feature: "Orders",
            filename: "IOSPODetailPage.swift"
        )
        let listSource = try Self.readOrdersPageSource(
            feature: "Orders",
            filename: "IOSPurchaseOrdersPage.swift"
        )
        let helpRegistrySource = try Self.readSharedSource(filename: "HelpContentRegistry.swift")

        XCTAssertTrue(
            detailSource.contains("actionButton(\"Mark Supplier Contacted\""),
            "Submitted POs should require an explicit supplier-contact action label before moving to ordered."
        )
        XCTAssertTrue(
            detailSource.contains("Supplier contact details are required before marking ordered."),
            "Marking a submitted PO as ordered must require explicit supplier contact details."
        )
        XCTAssertTrue(
            detailSource.contains("PO marked as Submitted for internal review. Log supplier contact before moving to Ordered."),
            "Submitted status messaging must not imply supplier transmission happened."
        )
        XCTAssertFalse(
            detailSource.contains("PO marked as Submitted. Remember to send the order to the supplier."),
            "Legacy submitted copy implied supplier transmission without a durable contact record."
        )
        XCTAssertTrue(
            listSource.contains("Submitted means internal review/approval; Ordered means supplier contact has been logged."),
            "PO list help copy should distinguish internal submission from supplier-contacted ordering."
        )
        XCTAssertTrue(
            helpRegistrySource.contains("Submitted means internal review/approval; Ordered means supplier contact has been logged."),
            "Shared help registry copy should match the PO page contract so helper surfaces stay consistent."
        )
        XCTAssertTrue(
            helpRegistrySource.contains("Before Ordered, log supplier contact in the Mark Supplier Contacted action."),
            "Shared PO detail help should describe the explicit supplier-contacted step before ordered."
        )
    }

    private static func readOrdersPageSource(
        feature: String,
        filename: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent(feature)
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readSharedSource(
        filename: String,
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Shared")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
