import XCTest

/// User-like regression coverage for GitHub #1476 / WEI-5328.
///
/// Launches with a deterministic `view_people`-only persona, opens the real Teams
/// route, and verifies mutation controls are absent from the accessibility tree.
final class IOSTeamsViewOnlyUITests: XCTestCase {
    @MainActor
    func testViewPeopleOnlyUserCanBrowseTeamsWithoutMutationAffordances() throws {
        let app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingTeamsViewOnly",
            "-UITestingOpenTeams"
        ]
        app.launch()

        XCTAssertTrue(
            app.navigationBars["Teams"].waitForExistence(timeout: 25),
            "The view_people-only fixture should reach the Teams page"
        )
        XCTAssertFalse(
            app.buttons["Add team"].exists,
            "A view_people-only user must not receive the create-team accessibility element"
        )

        let teamsHelp = app.buttons["Help"].firstMatch
        assertMinimumHitTarget(teamsHelp, named: "Teams Help")
        teamsHelp.tap()
        XCTAssertTrue(
            app.navigationBars["Teams Help"].waitForExistence(timeout: 10),
            "The view_people-only user should be able to open Teams Help"
        )
        app.buttons["Done"].tap()

        let fixtureTeam = app.staticTexts["UITest Read Only Team"].firstMatch
        XCTAssertTrue(fixtureTeam.waitForExistence(timeout: 10))
        fixtureTeam.tap()

        XCTAssertTrue(
            app.navigationBars["UITest Read Only Team"].waitForExistence(timeout: 10),
            "The viewer should still be able to browse team details"
        )
        XCTAssertFalse(
            app.buttons["Team actions"].exists,
            "Edit, add-member, and delete actions must be absent for view_people-only users"
        )

        let teamDetailHelp = app.buttons["Help"].firstMatch
        assertMinimumHitTarget(teamDetailHelp, named: "Team Detail Help")
        teamDetailHelp.tap()
        XCTAssertTrue(
            app.navigationBars["Team Detail Help"].waitForExistence(timeout: 10),
            "The view_people-only user should be able to open Team Detail Help"
        )
        app.buttons["Done"].tap()

        let viewerMember = app.staticTexts["UITest People Viewer"].firstMatch
        XCTAssertTrue(viewerMember.waitForExistence(timeout: 10))
        viewerMember.swipeLeft()
        XCTAssertFalse(
            app.buttons["Remove"].exists,
            "The remove-member swipe action must not enter the accessibility tree"
        )
    }

    @MainActor
    private func assertMinimumHitTarget(_ element: XCUIElement, named name: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(name) should be present")
        XCTAssertTrue(element.isHittable, "\(name) should be hittable")
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) should be at least 44pt wide")
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) should be at least 44pt tall")
    }
}
