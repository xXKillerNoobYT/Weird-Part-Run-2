import XCTest
import UIKit

/// Focused user-like regression coverage for GitHub #1469 / WEI-5225.
final class AIFallbackRetryAccessibilityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(
            contentSizeCategory: name.contains("AX5") ? .accessibilityExtraExtraExtraLarge : nil
        )
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testRetrySaveExportsMinimumTargetAtDefaultDynamicType() throws {
        try verifyWarningAndRetryTarget(context: "default Dynamic Type")
    }

    @MainActor
    func testRetrySaveExportsMinimumTargetAndWarningFitsAX5DynamicType() throws {
        try verifyWarningAndRetryTarget(context: "AX5 Dynamic Type")
    }

    private func launchApp(contentSizeCategory: UIContentSizeCategory? = nil) -> XCUIApplication {
        let application = XCUIApplication()
        application.launchArguments = ["-UITesting", "-UITestingAIFallbackSaveWarning"]
        if let contentSizeCategory {
            application.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                contentSizeCategory.rawValue,
            ]
        }
        application.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        application.launch()
        return application
    }

    @MainActor
    private func verifyWarningAndRetryTarget(context: String) throws {
        try logInIfNeeded()

        let assistantButton = app.buttons["aiAssistantButton"]
        XCTAssertTrue(assistantButton.waitForExistence(timeout: 15), "AI Assistant should be available at \(context).")
        assistantButton.tap()

        let warningTitle = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Conversation turn was not saved")
        ).firstMatch
        let warningBody = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Simulated storage write failure for UI verification.")
        ).firstMatch
        let retry = app.buttons["Retry saving conversation turn"]
        let dismiss = app.buttons["Dismiss conversation save warning"]

        XCTAssertTrue(warningTitle.waitForExistence(timeout: 10), "Save warning should render at \(context).")
        XCTAssertTrue(warningBody.waitForExistence(timeout: 5), "Save warning detail should remain untruncated at \(context).")
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "Retry Save should render at \(context).")
        XCTAssertTrue(retry.isHittable, "Retry Save should be user-actionable at \(context).")
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44, "Retry Save width must be at least 44pt at \(context).")
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44, "Retry Save height must be at least 44pt at \(context).")

        let viewport = app.windows.firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5), "The visible app window should exist at \(context).")
        for element in [warningTitle, warningBody, retry] {
            XCTAssertTrue(
                viewport.frame.contains(element.frame),
                "\(element.label) must remain inside the visible app frame at \(context)."
            )
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Retry Save warning - \(context)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let clearingAction = name.contains("AX5") ? dismiss : retry
        XCTAssertTrue(clearingAction.waitForExistence(timeout: 5), "The warning clear action should exist at \(context).")
        XCTAssertTrue(clearingAction.isHittable, "The warning clear action should be hittable at \(context).")
        clearingAction.tap()
        XCTAssertTrue(
            warningTitle.waitForNonExistence(timeout: 5),
            "Retry Save and Dismiss should both clear the simulated warning deterministically."
        )
    }

    @MainActor
    private func logInIfNeeded() throws {
        let assistantButton = app.buttons["aiAssistantButton"]
        if assistantButton.waitForExistence(timeout: 5), assistantButton.isHittable { return }

        let ownerRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'")
        ).firstMatch
        XCTAssertTrue(ownerRow.waitForExistence(timeout: 30), "UI test owner should be available.")
        ownerRow.tap()

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5), "PIN field should appear.")
        pinField.tap()
        pinField.typeText("1234")

        let done = app.buttons["loginPINDoneButton"]
        if done.waitForExistence(timeout: 2), done.isHittable { done.tap() }

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5), "Sign In should appear.")
        signIn.tap()

        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Skip'")).firstMatch
            let gotIt = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Got It'")).firstMatch
            if gotIt.exists {
                if gotIt.isHittable {
                    gotIt.tap()
                } else {
                    app.scrollViews.firstMatch.swipeUp()
                }
                continue
            }
            if skip.exists {
                if skip.isHittable {
                    skip.tap()
                } else {
                    app.scrollViews.firstMatch.swipeUp()
                }
                continue
            }
            if app.buttons["aiAssistantButton"].exists,
               app.buttons["aiAssistantButton"].isHittable { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        XCTFail("Login should reach the app shell before opening AI Assistant.")
    }
}
