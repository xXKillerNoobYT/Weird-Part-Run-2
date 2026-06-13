import UIKit
import XCTest

final class WarehouseDashboardScreenshotUITests: XCTestCase {
    private static let uiTestingPIN = "8396"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWarehouseDashboardScreenshot() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
        app.launchArguments += ["-UITesting", "-UITestingWEI936AutoLogin"]
        app.launch()

        navigateToWarehouse(in: app)

        assertKPIExists(in: app, identifier: "warehouseKPIAuditScore", title: "Audit Score")
        assertKPIExists(in: app, identifier: "warehouseKPITotalStock", title: "Total Stock")
        assertKPIExists(in: app, identifier: "warehouseKPIHealth", title: "Health")
        assertKPIExists(in: app, identifier: "warehouseKPIShortfalls", title: "Shortfalls")

        try writeScreenshot(app.screenshot())
    }

    private func assertKPIExists(
        in app: XCUIApplication,
        identifier: String,
        title: String,
        timeout: TimeInterval = 10
    ) {
        let kpi = app.staticTexts[identifier].firstMatch
        let titleText = app.staticTexts[title].firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        let scrollView = app.scrollViews.firstMatch
        while !kpi.exists, !titleText.exists, Date() < deadline {
            if scrollView.exists {
                scrollView.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            kpi.exists || titleText.exists,
            "Warehouse dashboard should expose the \(title) KPI"
        )
    }

    private func navigateToWarehouse(in app: XCUIApplication) {
        if app.buttons["whAction_newMovement"].waitForExistence(timeout: 2) {
            return
        }

        let warehouseTab = app.buttons["tab_warehouse"].firstMatch
        if warehouseTab.waitForExistence(timeout: 8) {
            warehouseTab.tap()
        } else if app.buttons["Warehouse"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["Warehouse"].firstMatch.tap()
        } else if app.tabBars.buttons["More"].waitForExistence(timeout: 3) {
            app.tabBars.buttons["More"].tap()
            let warehouse = app.buttons["Warehouse"].firstMatch
            XCTAssertTrue(warehouse.waitForExistence(timeout: 8), "Warehouse module should be reachable")
            warehouse.tap()
        } else {
            XCTFail("Warehouse module tab should be reachable")
        }

        if !app.buttons["whAction_newMovement"].waitForExistence(timeout: 8) {
            let dashboard = app.buttons["Dashboard"].firstMatch
            if dashboard.waitForExistence(timeout: 5), dashboard.isHittable {
                dashboard.tap()
            }
        }

        XCTAssertTrue(
            app.buttons["whAction_newMovement"].waitForExistence(timeout: 10),
            "Warehouse Dashboard should open and expose quick actions"
        )
    }

    private func writeScreenshot(_ screenshot: XCUIScreenshot) throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = environment["WEI_2545_SCREENSHOT_DIR"] ?? defaultScreenshotDirectory()
        let name = environment["WEI_2545_SCREENSHOT_NAME"] ?? defaultScreenshotName()

        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
        try screenshot.pngRepresentation.write(to: url)
    }

    private func defaultScreenshotDirectory() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("weird-parts-ui-screenshots")
            .appendingPathComponent("WEI-2545")
            .path
    }

    private func defaultScreenshotName() -> String {
        let deviceName = UIDevice.current.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "warehouse-dashboard-\(deviceName).png"
    }
}
