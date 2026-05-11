import XCTest

final class ConflictScreenshotCaptureUITests: XCTestCase {

    private var app: XCUIApplication!

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        // Signal both general UI-testing mode and the specific conflict-capture
        // mode so the app can (now or in the future) seed the required fixtures.
        app.launchArguments += ["-UITesting", "-UITestingConflictCapture"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Conflict screenshot capture
    //
    // Prerequisites (must ALL be true on the simulator / device):
    //   1. At least one user row exists in the login list.
    //   2. That user's PIN is "1234".
    //   3. The post-login dashboard shows a "Review" button leading to Sync Conflicts.
    //
    // The test is skipped automatically on a clean install so it never blocks CI.
    // To run it explicitly, set the environment variable before launching the test:
    //
    //   UI_TEST_CONFLICT_SCREENSHOTS=1 xcodebuild test -scheme "Weird Parts IOS" …
    //
    // In Xcode: Edit Scheme → Test → Arguments → Environment Variables →
    //   Name: UI_TEST_CONFLICT_SCREENSHOTS   Value: 1
    func testCaptureConflictScreenshots() throws {
        guard ProcessInfo.processInfo.environment["UI_TEST_CONFLICT_SCREENSHOTS"] == "1" else {
            throw XCTSkip(
                "Skipped: set the environment variable UI_TEST_CONFLICT_SCREENSHOTS=1 " +
                "and ensure the simulator has a seeded admin user (PIN 1234) with " +
                "pending sync conflicts before running this test."
            )
        }

        app.launch()

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        XCTAssertTrue(userRows.firstMatch.waitForExistence(timeout: 12),
                      "No login user rows found — simulator may not have seeded data.")
        userRows.firstMatch.tap()

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5))
        pinField.tap()
        pinField.typeText("1234")

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        let reviewButton = app.buttons["Review"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 12),
                      "No 'Review' button found — simulator may have no pending sync conflicts.")
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Sync Conflicts"].waitForExistence(timeout: 8))
        capture("01-sync-conflicts-overview")

        if app.staticTexts["Notes"].waitForExistence(timeout: 3) { app.staticTexts["Notes"].tap() }
        capture("02-ai-hard-long-text")

        if app.staticTexts["Priority Label"].waitForExistence(timeout: 3) { app.staticTexts["Priority Label"].tap() }
        capture("03-standard-long-value")

        let useThisButtons = app.buttons.matching(NSPredicate(format: "label == 'Use This'"))
        XCTAssertGreaterThan(useThisButtons.count, 0)
        useThisButtons.element(boundBy: useThisButtons.count - 1).tap()

        let alert = app.alerts["Confirm Critical Write Decision"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        capture("04-critical-alert-presented")

        alert.buttons["Cancel"].tap()
        capture("05-critical-cancel-returned")

        let useThisAgain = app.buttons.matching(NSPredicate(format: "label == 'Use This'"))
        useThisAgain.element(boundBy: useThisAgain.count - 1).tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Confirm"].tap()

        capture("06-critical-confirm-completed")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
