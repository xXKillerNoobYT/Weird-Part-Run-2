import XCTest

final class WEI936OnboardingQAUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureFirstLaunchOnboardingPhone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting", "-UITestingAutoLogin", "-UITestingFirstLaunchOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to WiredPart"].waitForExistence(timeout: 20))
        capture("wei936-phone-welcome-sheet")

        app.buttons["Start setup"].tap()
        XCTAssertTrue(app.staticTexts["Get set up"].waitForExistence(timeout: 10))
        capture("wei936-phone-in-progress-card")

        app.buttons["Hide setup checklist"].tap()
        XCTAssertTrue(app.staticTexts["Setup hidden. Re-open it in Settings."].waitForExistence(timeout: 5))
        capture("wei936-phone-dismiss-toast")

        app.buttons["person.circle"].tap()
        XCTAssertTrue(app.staticTexts["Restart setup checklist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Page Layout"].exists)
        capture("wei936-phone-settings-root-setup")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
