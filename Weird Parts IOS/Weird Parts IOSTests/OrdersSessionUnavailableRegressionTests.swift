import XCTest

final class OrdersSessionUnavailableRegressionTests: XCTestCase {
    func testOrdersMutationsSurfaceVisibleErrorWhenCurrentUserIsUnavailable() throws {
        let createReturnSource = try Self.readOrdersSource(named: "CreateReturnSheet.swift")
        XCTAssertFalse(
            createReturnSource.contains("guard let userId = appCore.currentUser?.id else { return }"),
            "Create Return should not silently no-op when current user is unavailable."
        )
        XCTAssertTrue(
            createReturnSource.contains("saveError = \"User session unavailable. Sign in again.\""),
            "Create Return should show a visible saveError for missing user session."
        )

        let purchaseOrdersSource = try Self.readOrdersSource(named: "IOSPurchaseOrdersPage.swift")
        XCTAssertFalse(
            purchaseOrdersSource.contains("guard let userId = appCore.currentUser?.id else { return }"),
            "PO cancel/delete should not silently no-op when current user is unavailable."
        )
        XCTAssertTrue(
            purchaseOrdersSource.contains("actionMessage = \"User session unavailable. Sign in again.\""),
            "PO cancel/delete should set actionMessage when user session is unavailable."
        )

        let poDetailSource = try Self.readOrdersSource(named: "IOSPODetailPage.swift")
        XCTAssertFalse(
            poDetailSource.contains("guard let userId = appCore.currentUser?.id else { return }"),
            "PO detail status transitions should not silently no-op when current user is unavailable."
        )
        XCTAssertTrue(
            poDetailSource.contains("actionMessage = \"User session unavailable. Sign in again.\""),
            "PO detail status transitions should set actionMessage when user session is unavailable."
        )
    }

    private static func readOrdersSource(named filename: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Orders")
            .appendingPathComponent(filename)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
