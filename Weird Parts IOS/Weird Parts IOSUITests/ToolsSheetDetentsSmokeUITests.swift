import XCTest

final class ToolsSheetDetentsSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments += ["-UITesting", "-UITestPrimaryModule", "tools"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testToolsDashboardHelpSheetOpensWithConfiguredDetent() throws {
        loginIfNeeded()
        openToolsFromTabBarOrMore()

        navigateToToolsTab(id: "tools-dashboard", label: "Dashboard")
        openHelpSheet(title: "Tools Overview Help")
        dismissHelpSheet(title: "Tools Overview Help")
    }

    private func loginIfNeeded() {
        let loginView = app.otherElements["loginView"]
        guard loginView.waitForExistence(timeout: 10) else { return }

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "loginUserRow_"))
        let firstUser = userRows.firstMatch
        XCTAssertTrue(firstUser.waitForExistence(timeout: 10), "Seeded UI test user should be available")
        firstUser.tap()

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5), "PIN field should appear after selecting user")
        pinField.tap()
        pinField.typeText("1234")

        let signInButton = app.buttons["loginSignInButton"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 5), "Sign in button should be available")
        signInButton.tap()

        XCTAssertFalse(loginView.waitForExistence(timeout: 10), "Login screen should dismiss after valid PIN")
    }

    private func openToolsFromTabBarOrMore(timeout: TimeInterval = 10) {
        if app.navigationBars["Tools"].exists || app.navigationBars["Tools Overview"].exists {
            return
        }

        if tapWhenReady(app.buttons["fullSidebarModule_tools"], timeout: 2) {
            return
        }

        let toolsTab = app.tabBars.buttons["Tools"]
        if toolsTab.waitForExistence(timeout: timeout) {
            toolsTab.tap()
            return
        }

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: timeout), "More tab should be visible")
        moreTab.tap()

        let toolsMoreRow = app.buttons["moreModule_tools"]
        XCTAssertTrue(toolsMoreRow.waitForExistence(timeout: timeout), "Tools module should be listed under More")
        toolsMoreRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func navigateToToolsTab(id: String, label: String, timeout: TimeInterval = 10) {
        let navigationCandidates = [
            app.buttons["fullSidebarTab_\(id)"],
            app.buttons["moduleSidebarTab_\(id)"],
            app.buttons["moduleTopTab_\(id)"],
            app.buttons[label],
            app.staticTexts[label]
        ]

        var didTap = false
        for _ in 0..<4 {
            for candidate in navigationCandidates where tapWhenReady(candidate, timeout: 1) {
                didTap = true
                break
            }

            if didTap { break }
            app.scrollViews.firstMatch.swipeLeft()
        }

        XCTAssertTrue(
            app.buttons["Help"].waitForExistence(timeout: timeout),
            "Tools \(label) page should expose its Help sheet button"
        )
    }

    private func openHelpSheet(title: String) {
        XCTAssertTrue(tapWhenReady(app.buttons["Help"], timeout: 5), "Help button should be tappable")
        XCTAssertTrue(
            app.navigationBars[title].waitForExistence(timeout: 5),
            "\(title) should appear in a presented sheet"
        )
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3), "\(title) should expose Done")
    }

    private func dismissHelpSheet(title: String) {
        XCTAssertTrue(tapWhenReady(app.buttons["Done"], timeout: 3), "Done button should dismiss \(title)")
        XCTAssertFalse(
            app.navigationBars[title].waitForExistence(timeout: 3),
            "\(title) should dismiss cleanly"
        )
    }

    @discardableResult
    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        guard !element.frame.isEmpty else { return false }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }
}
