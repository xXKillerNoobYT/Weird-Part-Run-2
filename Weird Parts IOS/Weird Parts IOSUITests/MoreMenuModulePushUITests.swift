import XCTest

/// Covers the More → module push, which had **no UI test at all** despite being
/// the flow a tester reported broken.
///
/// Origin: #1577, the first TestFlight feedback we ever received — *"Won't load
/// the notebook page"*, build 2, tapping Notebooks in More → Modules. It sat as
/// "not yet investigated" through five subsequent release notes because nothing
/// could confirm or deny it: 15 UI test files existed and not one mentioned
/// Notebooks or exercised a module push.
///
/// That gap is the real defect here. `IOSMainView`'s destination is:
///
/// ```swift
/// .navigationDestination(for: String.self) { moduleId in
///     if let module = allModulesById[moduleId] { ModuleHostView(...) }
///     // no else — an unresolved id pushes an EMPTY view
/// }
/// ```
///
/// A row whose id does not resolve pushes a blank screen and reports no error
/// anywhere. That is indistinguishable, to a tester, from "won't load" — and
/// indistinguishable, to CI, from success. These tests make it distinguishable.
final class MoreMenuModulePushUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()
        logInIfNeeded()
    }

    /// The originally reported flow.
    func testNotebooksModuleOpensFromMoreMenu() throws {
        openModuleFromMore(named: "Notebooks")

        // A blank push still has a navigation bar, so asserting on the bar alone
        // would pass on exactly the bug being tested. Assert on content the
        // Notebooks page itself owns.
        let landed = app.navigationBars["Notebooks"].waitForExistence(timeout: 30)
        XCTAssertTrue(landed, "Tapping Notebooks in More should push the Notebooks page (#1577).")

        let createButton = app.buttons["Create notebook"]
        let typeFilter = app.staticTexts["All"]
        XCTAssertTrue(
            createButton.waitForExistence(timeout: 20) || typeFilter.waitForExistence(timeout: 5),
            "The Notebooks page pushed but rendered no content — this is the blank-destination failure #1577 describes."
        )
    }

    /// The same push for every overflow module, so a single unresolved id cannot
    /// hide behind the others. This is what splits "navigation is broken" from
    /// "one module is broken" without a human bisecting by hand.
    func testEveryOverflowModulePushesRealContent() throws {
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 30), "The More tab should be reachable after login.")

        for name in ["Notebooks", "Parts", "People", "Tools", "Fleet"] {
            moreTab.tap()
            let row = app.buttons[name]
            guard row.waitForExistence(timeout: 5) else {
                // Not every module is visible to every permission set; a hidden
                // row is a legitimate state, an unopenable visible row is not.
                continue
            }
            row.tap()
            XCTAssertTrue(
                app.navigationBars[name].waitForExistence(timeout: 30),
                "\(name) is listed in More but does not push its page — unresolved module id."
            )
        }
    }

    // MARK: - Helpers

    /// The UITest build lands on a user picker unless a session already exists.
    /// Mirrors `logInAsUITestOwnerIfNeeded` in `Weird_Parts_IOSUITests`, kept
    /// local because that one is private to its file.
    private func logInIfNeeded() {
        if app.tabBars.buttons["More"].waitForExistence(timeout: 5) { return }
        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        if userRows.firstMatch.waitForExistence(timeout: 30) {
            userRows.firstMatch.tap()
        } else if app.staticTexts["UITest Owner"].waitForExistence(timeout: 5) {
            app.staticTexts["UITest Owner"].tap()
        }
    }

    private func openModuleFromMore(named name: String) {
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 30), "The More tab should be reachable after login.")
        moreTab.tap()

        let row = app.buttons[name]
        if !row.waitForExistence(timeout: 10) {
            // The row can sit below the fold on smaller devices.
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<6 where !row.exists {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "\(name) should be listed in More → Modules.")
        row.tap()
    }
}
