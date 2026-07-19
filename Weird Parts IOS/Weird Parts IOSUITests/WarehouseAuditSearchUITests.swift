import XCTest

final class WarehouseAuditSearchUITests: XCTestCase {
    private static let uiTestingPIN = "8396"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompactAuditSearchRevealFocusTypeClearAndTabRefresh() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingDispatchBoard",
            "-UITestingWarehouseDashboard",
        ]
        app.launch()

        let auditTab = app.descendants(matching: .any)["subtab_warehouse-audit"].firstMatch
        XCTAssertTrue(auditTab.waitForExistence(timeout: 20), "The Warehouse Audit tab should be reachable from the Dashboard.")
        XCTAssertTrue(auditTab.isHittable, "The adjacent Audit tab should be tappable in compact layout.")
        auditTab.tap()
        XCTAssertTrue(app.navigationBars["Warehouse Audit"].waitForExistence(timeout: 10), "Tapping Audit should open Warehouse Audit.")

        let searchField = app.searchFields["Search parts..."]
        if !searchField.waitForExistence(timeout: 3) {
            app.swipeDown()
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Audit search must be user-reachable in compact iPhone layout.")
        XCTAssertTrue(searchField.isHittable, "Audit search must be focusable without an inaccessible navigation gesture.")
        attachScreenshot(named: "01-audit-search-revealed", app: app)

        searchField.tap()
        searchField.typeText("UITEST-MUV-001")
        XCTAssertEqual(searchField.value as? String, "UITEST-MUV-001", "Audit search should accept part names or codes.")
        attachScreenshot(named: "02-audit-search-typed", app: app)

        let clearButton = app.buttons["Clear text"].firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 3), "Focused Audit search should expose the standard clear action.")
        clearButton.tap()
        XCTAssertEqual(searchField.value as? String, "Search parts...", "Clearing Audit search should restore the prompt and refresh empty-search context.")

        let dashboardTab = app.descendants(matching: .any)["subtab_warehouse-dashboard"].firstMatch
        XCTAssertTrue(dashboardTab.waitForExistence(timeout: 5), "The adjacent Warehouse Dashboard tab should be reachable.")
        XCTAssertTrue(dashboardTab.isHittable, "The Dashboard tab should be tappable from Audit.")
        dashboardTab.tap()
        XCTAssertTrue(searchField.waitForNonExistence(timeout: 5), "Leaving Audit should remove its search control and inactive page context.")

        XCTAssertTrue(auditTab.waitForExistence(timeout: 5), "The Audit tab should remain reachable after the context transition.")
        auditTab.tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Returning to Audit should recreate its search control and active page context.")
        searchField.tap()
        searchField.typeText("context-refresh")
        XCTAssertEqual(searchField.value as? String, "context-refresh", "Search should remain interactive after Audit page-context reactivation.")
        attachScreenshot(named: "03-audit-search-context-refreshed", app: app)
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
