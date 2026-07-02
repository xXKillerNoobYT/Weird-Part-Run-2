import XCTest

/// Regression coverage for GH #700: dashboard QR scanner quick actions must
/// preserve the scanned entity context through navigation instead of posting a
/// bare module id. The payload store semantics themselves are covered by
/// `QRScanRouteTests` in the core package; these checks pin the scanner page's
/// wiring so a refactor cannot quietly fall back to context-free navigation.
final class DashboardScannerEntityContextRegressionTests: XCTestCase {

    func testQuickActionsRouteThroughContextPreservingNavigation() throws {
        let source = try Self.readScannerSource()

        // Every entity quick action must carry the scanned result to a concrete
        // destination tab through the context-preserving helper.
        let expectedRoutes = [
            "navigateToScannedEntity(moduleId: \"warehouse\", tabId: \"warehouse-movements\", action: .moveStock, result: result)",
            "navigateToScannedEntity(moduleId: \"parts\", tabId: \"parts-catalog\", action: .view, result: result)",
            "navigateToScannedEntity(moduleId: \"tools\", tabId: \"tools-registry\", action: .view, result: result)",
            "navigateToScannedEntity(moduleId: \"jobs\", tabId: \"jobs-list\", action: .view, result: result)",
            "navigateToScannedEntity(moduleId: \"fleet\", tabId: \"fleet-vehicles\", action: .view, result: result)",
            "navigateToScannedEntity(moduleId: \"warehouse\", tabId: \"warehouse-audit\", action: .audit, result: result)",
            "navigateToScannedEntity(moduleId: \"warehouse\", tabId: \"warehouse-audit\", action: .assignPart, result: result)",
            "navigateToScannedEntity(moduleId: \"warehouse\", tabId: \"warehouse-locations\", action: .floorPlan, result: result)"
        ]
        for route in expectedRoutes {
            XCTAssertTrue(
                source.contains(route),
                "Scanner quick actions must include the context-preserving route: \(route)"
            )
        }

        // The old context-dropping pattern must not come back.
        XCTAssertFalse(
            source.contains("navigateToModule(\"warehouse\")"),
            "Quick actions must not post bare module navigation that drops the scanned entity context."
        )
    }

    func testContextIsStashedBeforeNavigationNotificationPosts() throws {
        let source = try Self.readScannerSource()

        let helper = try XCTUnwrap(
            source.range(of: "private func navigateToScannedEntity("),
            "The scanner must define the context-preserving navigation helper."
        )
        let stashCall = try XCTUnwrap(
            source.range(of: "QRScanRouteStore.shared.stash(", range: helper.upperBound..<source.endIndex),
            "The helper must stash the scanned context in QRScanRouteStore."
        )
        let notificationPost = try XCTUnwrap(
            source.range(
                of: "NotificationCenter.default.post(name: .navigateToModule",
                range: helper.upperBound..<source.endIndex
            ),
            "The helper must post the navigation notification."
        )
        XCTAssertTrue(
            stashCall.lowerBound < notificationPost.lowerBound,
            "The scanned context must be stashed BEFORE the navigation notification posts, so the destination page can consume it on appear."
        )

        // The notification itself must carry the entity keys for route-level listeners.
        for key in ["userInfo[\"entityType\"]", "userInfo[\"entityId\"]", "\"action\": action.rawValue", "\"code\": result.code"] {
            XCTAssertTrue(
                source.contains(key),
                "The navigation notification payload must include \(key)."
            )
        }
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
}
