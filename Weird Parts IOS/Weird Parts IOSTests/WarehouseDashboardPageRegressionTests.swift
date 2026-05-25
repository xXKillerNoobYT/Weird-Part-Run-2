import XCTest

final class WarehouseDashboardPageRegressionTests: XCTestCase {
    func testQuickActionsStayDiscoverableAndExposeStableAccessibilityContracts() throws {
        let source = try Self.readWarehouseDashboardPageSource()

        XCTAssertTrue(
            source.contains("WarehouseQuickAction(") &&
                source.contains("title: \"New Movement\"") &&
                source.contains("identifier: \"whAction_newMovement\"") &&
                source.contains("title: \"Scan QR\"") &&
                source.contains("identifier: \"whAction_scanQR\"") &&
                source.contains("title: \"Receiving\"") &&
                source.contains("identifier: \"whAction_receiving\"") &&
                source.contains("title: \"Audit Queue\"") &&
                source.contains("identifier: \"whAction_auditQueue\""),
            "Warehouse Dashboard quick actions must keep the four required tiles with stable identifiers."
        )

        XCTAssertTrue(
            source.contains("// Smart Card Filters\n                smartCardFilters\n\n                // Quick Actions\n                quickActionsSection\n\n                // KPI Summary\n                kpiRow"),
            "Quick Actions should render before KPI summary so the tiles remain discoverable on phone-height viewports."
        )

        XCTAssertTrue(
            source.contains(".padding(.bottom, 24)"),
            "Dashboard scroll content should reserve bottom space so quick actions are not obscured by the persistent tab bar on phones."
        )

        XCTAssertFalse(
            source.contains(".accessibilityElement(children: .ignore)"),
            "Quick-action button labels should remain visible in accessibility traversal instead of hiding child labels."
        )
    }

    private static func readWarehouseDashboardPageSource(
        file: StaticString = #filePath
    ) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Warehouse")
            .appendingPathComponent("WarehouseDashboardPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
