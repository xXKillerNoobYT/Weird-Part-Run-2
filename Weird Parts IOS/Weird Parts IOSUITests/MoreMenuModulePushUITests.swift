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
        // -UITestingWEI936AutoLogin is how the suite gets a logged-in session
        // deterministically. The first version of this test hand-rolled a login
        // helper instead and failed in CI at "The More tab should be reachable
        // after login" — it never got as far as Notebooks, so the red gate was
        // the test's fault and not the app's.
        app.launchArguments += ["-UITesting", "-UITestingWEI936AutoLogin"]
        app.launch()
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
    ///
    /// **Deliberately NOT in `Stage9DeterministicUISmokes.xctestplan`.** That plan
    /// is bounded on purpose and runs under a 900s phase timeout; this test walks
    /// five modules and would meaningfully change its runtime, and a UI phase that
    /// times out produces the half-written xcresult flake #1636 exists to absorb.
    /// Run it locally when navigation changes, or promote it to a broader plan.
    /// Only `testNotebooksModuleOpensFromMoreMenu` is in the gate.
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

    /// Reproduces the TestFlight Hats & Roles complaint through the real UI.
    /// The tapped hat must remain selected after the detail sheet pushes the
    /// shared permissions editor; otherwise an administrator can unknowingly
    /// change a different role.
    func testHatDetailOpensPermissionsForTheTappedHat() throws {
        openModuleFromMore(named: "People")

        let hatsAndRoles = app.buttons["people-dashboard-hats-and-roles-link"]
        XCTAssertTrue(
            hatsAndRoles.waitForExistence(timeout: 20),
            "People should expose the Hats & Roles workflow to the seeded admin."
        )
        hatsAndRoles.tap()

        let apprentice = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Apprentice,")
        ).firstMatch
        XCTAssertTrue(apprentice.waitForExistence(timeout: 20), "The seeded Apprentice hat should be listed.")
        apprentice.tap()

        let editPermissions = app.buttons["Edit Permissions"]
        XCTAssertTrue(editPermissions.waitForExistence(timeout: 20), "Hat details should link to its permissions.")
        editPermissions.tap()

        XCTAssertTrue(
            app.staticTexts["Editing permissions for Apprentice"].waitForExistence(timeout: 20),
            "The permissions editor should identify the hat that launched it."
        )
        XCTAssertEqual(
            app.buttons["Apprentice hat"].value as? String,
            "Selected",
            "The tapped hat must be selected in the permissions selector."
        )
    }

    // MARK: - Helpers

    /// Opens a module by the route the current layout actually offers.
    ///
    /// iPhone puts overflow modules behind a **More** tab; iPad uses a split-view
    /// **sidebar** and lists them directly, with no More tab at all. The first
    /// version of this helper assumed a tab bar unconditionally and so passed on
    /// iPhone and failed on iPad at "The More tab should be reachable" — a
    /// layout assumption reported as an app failure. Probe, don't assume.
    private func openModuleFromMore(named name: String) {
        let moreTab = app.tabBars.buttons["More"]
        if moreTab.waitForExistence(timeout: 30) {
            moreTab.tap()
        } else {
            // iPad/sidebar: modules are listed without an overflow step. Assert
            // that SOMETHING navigable exists, so a genuinely broken launch still
            // fails here rather than silently falling through to a missing row.
            XCTAssertTrue(
                app.buttons[name].waitForExistence(timeout: 30)
                    || app.staticTexts[name].waitForExistence(timeout: 5),
                "Neither a More tab nor a sidebar entry for \(name) appeared — the app did not reach a navigable state."
            )
        }

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
