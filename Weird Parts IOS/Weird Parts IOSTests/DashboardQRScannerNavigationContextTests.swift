import XCTest

final class DashboardQRScannerNavigationContextTests: XCTestCase {
    func testQuickActionsSendModuleTabAndScannedContext() throws {
        let source = try Self.readScannerSource()

        XCTAssertTrue(
            source.contains("tabId: \"warehouse-movements\"") && source.contains("action: \"moveStock\""),
            "Move Stock should route to warehouse movements with an explicit moveStock action."
        )
        XCTAssertTrue(
            source.contains("tabId: \"parts-catalog\"") && source.contains("action: \"view\""),
            "View Part should route to the parts catalog tab with a view action."
        )
        XCTAssertTrue(
            source.contains("tabId: \"jobs-list\"") && source.contains("tabId: \"tools-registry\"") && source.contains("tabId: \"fleet-vehicles\""),
            "Job/tool/vehicle quick actions should route to specific destination tabs, not generic modules."
        )
        XCTAssertTrue(
            source.contains("tabId: \"warehouse-audit\"") && source.contains("action: \"assignPart\"") && source.contains("action: \"floorPlan\""),
            "Location quick actions should keep their specific intent and target tabs."
        )
        XCTAssertTrue(
            source.contains("userInfo[\"entityType\"] = entityType") &&
            source.contains("userInfo[\"entityId\"] = entityId") &&
            source.contains("userInfo[\"code\"] = result.code") &&
            source.contains("userInfo[\"action\"] = action"),
            "Scanner navigation payload should include scanned entity context and requested action."
        )
    }

    func testMainNavigationParsesExtendedNavigatePayload() throws {
        let source = try Self.readMainViewSource()

        XCTAssertTrue(
            source.contains("let requestedEntityType = notification.userInfo?[\"entityType\"] as? String"),
            "IOSMainView should parse entityType from navigateToModule payload."
        )
        XCTAssertTrue(
            source.contains("let requestedEntityId = (notification.userInfo?[\"entityId\"] as? NSNumber)?.int64Value"),
            "IOSMainView should parse entityId from navigateToModule payload."
        )
        XCTAssertTrue(
            source.contains("let requestedCode = notification.userInfo?[\"code\"] as? String") &&
            source.contains("let requestedAction = notification.userInfo?[\"action\"] as? String"),
            "IOSMainView should parse code/action context from navigateToModule payload."
        )
        XCTAssertTrue(
            source.contains("let tabId: String?") &&
            source.contains("let entityType: String?") &&
            source.contains("let entityId: Int64?") &&
            source.contains("let code: String?") &&
            source.contains("let action: String?"),
            "ModuleNavigationRequest should preserve optional tab and scan context fields."
        )
    }

    private static func readScannerSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Dashboard")
            .appendingPathComponent("IOSDashboardQRScannerPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func readMainViewSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Navigation")
            .appendingPathComponent("IOSMainView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
