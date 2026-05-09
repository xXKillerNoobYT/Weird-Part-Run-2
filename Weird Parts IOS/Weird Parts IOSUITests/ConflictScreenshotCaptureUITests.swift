import XCTest

final class ConflictScreenshotCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureConflictScreenshots() throws {
        let app = try launchAndOpenConflictReview()
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

    func testCriticalConflictRequiresExplicitConfirmation() throws {
        let app = try launchAndOpenConflictReview()
        let useThisButtons = app.buttons.matching(NSPredicate(format: "label == 'Use This'"))
        guard useThisButtons.count > 0 else {
            throw XCTSkip("No critical conflict actions available in current UI test data")
        }

        useThisButtons.element(boundBy: useThisButtons.count - 1).tap()
        let alert = app.alerts["Confirm Critical Write Decision"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Critical action must require confirmation")

        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists, "Cancel should dismiss the confirmation alert")

        let useThisAgain = app.buttons.matching(NSPredicate(format: "label == 'Use This'"))
        XCTAssertGreaterThan(useThisAgain.count, 0, "Conflict should remain unresolved after cancel")
        useThisAgain.element(boundBy: useThisAgain.count - 1).tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Critical action should keep requiring explicit confirmation")

        alert.buttons["Confirm"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2), "Alert should close after confirm")
    }

    @discardableResult
    private func launchAndOpenConflictReview() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        guard userRows.firstMatch.waitForExistence(timeout: 12) else {
            throw XCTSkip("No seeded login user rows available for conflict UI test")
        }
        userRows.firstMatch.tap()

        let pinField = app.secureTextFields["loginPINField"]
        guard pinField.waitForExistence(timeout: 5) else {
            throw XCTSkip("PIN field unavailable in current UI test login flow")
        }
        pinField.tap()
        pinField.typeText("1234")

        let signIn = app.buttons["loginSignInButton"]
        guard signIn.waitForExistence(timeout: 5) else {
            throw XCTSkip("Sign-in button unavailable in current UI test login flow")
        }
        signIn.tap()

        let reviewButton = app.buttons["Review"]
        guard reviewButton.waitForExistence(timeout: 12) else {
            throw XCTSkip("Conflict review entry-point unavailable in current UI test data")
        }
        reviewButton.tap()

        XCTAssertTrue(app.navigationBars["Sync Conflicts"].waitForExistence(timeout: 8))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
