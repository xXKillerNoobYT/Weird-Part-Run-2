import XCTest

final class ConflictScreenshotCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureConflictScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        XCTAssertTrue(userRows.firstMatch.waitForExistence(timeout: 12))
        userRows.firstMatch.tap()

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5))
        pinField.tap()
        pinField.typeText("1234")

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        let reviewButton = app.buttons["Review"]
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 12))
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
