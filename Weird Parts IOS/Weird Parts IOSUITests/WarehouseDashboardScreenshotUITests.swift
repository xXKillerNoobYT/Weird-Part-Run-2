import UIKit
import XCTest

final class WarehouseDashboardScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWarehouseDashboardScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        navigateToWarehouse(in: app)

        XCTAssertTrue(
            app.staticTexts["Audit Score"].waitForExistence(timeout: 10),
            "Warehouse dashboard should show the Audit Score KPI"
        )
        XCTAssertTrue(app.staticTexts["Total Stock"].exists, "Warehouse dashboard should show the Total Stock KPI")
        XCTAssertTrue(app.staticTexts["Health"].exists, "Warehouse dashboard should show the Health KPI")
        XCTAssertTrue(app.staticTexts["Shortfalls"].exists, "Warehouse dashboard should show the Shortfalls KPI")

        try writeScreenshot(app.screenshot())
    }

    private func navigateToWarehouse(in app: XCUIApplication) {
        let warehouseTab = app.tabBars.buttons["Warehouse"]
        if warehouseTab.waitForExistence(timeout: 5) {
            warehouseTab.tap()
            return
        }

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 10), "More tab should be available when Warehouse overflows")
        moreTab.tap()

        let warehouseCell = app.cells.staticTexts["Warehouse"]
        if warehouseCell.waitForExistence(timeout: 5) {
            warehouseCell.tap()
            return
        }

        let warehouseButton = app.buttons["Warehouse"]
        XCTAssertTrue(warehouseButton.waitForExistence(timeout: 5), "Warehouse should be reachable from More")
        warehouseButton.tap()
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
