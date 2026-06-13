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
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingDispatchBoard",
            "-UITestingWarehouseDashboard",
        ]
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
        let kpi = app.descendants(matching: .any)[identifier].firstMatch
        let labelPredicate = NSPredicate(format: "label BEGINSWITH %@", "\(title):")
        let titledKPI = app.descendants(matching: .any).matching(labelPredicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while !kpi.exists, !titledKPI.exists, Date() < deadline {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(
            kpi.exists || titledKPI.exists,
            "Warehouse dashboard should expose the \(title) KPI"
        )
    }

    private func navigateToWarehouse(in app: XCUIApplication) {
        if openWarehouseDashboardSubtab(in: app, timeout: 2) {
            return
        }

        let warehouseTab = app.buttons["tab_warehouse"].firstMatch
        if warehouseTab.waitForExistence(timeout: 8) {
            warehouseTab.tap()
        } else if openMoreTab(in: app) {
            let warehouse = app.buttons["Warehouse"].firstMatch
            if warehouse.waitForExistence(timeout: 8) {
                warehouse.tap()
            } else {
                let warehouseText = app.staticTexts["Warehouse"].firstMatch
                XCTAssertTrue(warehouseText.waitForExistence(timeout: 8), "Warehouse module should be reachable")
                warehouseText.tap()
            }
        } else if app.buttons["Warehouse"].firstMatch.waitForExistence(timeout: 3) {
            let warehouse = app.buttons["Warehouse"].firstMatch
            warehouse.tap()
        } else {
            XCTFail("Warehouse module tab should be reachable")
        }

        XCTAssertTrue(
            openWarehouseDashboardSubtab(in: app, timeout: 10),
            "Warehouse Dashboard tab should be reachable"
        )
    }

    private func openMoreTab(in app: XCUIApplication) -> Bool {
        if app.tabBars.buttons["More"].waitForExistence(timeout: 2) {
            app.tabBars.buttons["More"].tap()
            return true
        }

        let moreButton = app.buttons["ellipsis.circle.fill"].firstMatch
        if moreButton.waitForExistence(timeout: 2) {
            moreButton.tap()
            return true
        }

        let moreLabel = app.buttons["More"].firstMatch
        if moreLabel.waitForExistence(timeout: 2) {
            moreLabel.tap()
            return true
        }

        return false
    }

    private func openWarehouseDashboardSubtab(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let dashboardSubtab = app.buttons["subtab_warehouse-dashboard"].firstMatch
        if dashboardSubtab.waitForExistence(timeout: timeout) {
            dashboardSubtab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }

        return false
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
