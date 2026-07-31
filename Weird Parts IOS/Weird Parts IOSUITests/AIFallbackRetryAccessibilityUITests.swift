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
        XCTAssertTrue(assistantButton.waitForExistence(timeout: 45), "AI Assistant should be available at \(context).")

        let warningTitle = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Conversation turn was not saved")
        ).firstMatch
        let warningBody = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Simulated storage write failure for UI verification.")
        ).firstMatch
        let retry = app.buttons["Retry saving conversation turn"]
        let dismiss = app.buttons["Dismiss conversation save warning"]

        // The assistant button can be momentarily covered by late-arriving
        // onboarding overlays (Got It / Skip hints), which swallow the first
        // tap without any test-visible failure — the panel never opens and the
        // fixture warning never renders (flaked 3x on CI, 2026-07-31, across
        // both Dynamic Type variants). Tap, confirm the panel actually opened
        // by watching for the fixture warning, and re-tap after clearing
        // overlays when it did not.
        var panelOpened = false
        for _ in 0..<3 {
            if assistantButton.exists, assistantButton.isHittable {
                assistantButton.tap()
            }
            if warningTitle.waitForExistence(timeout: 10) {
                panelOpened = true
                break
            }
            for prefix in ["Got It", "Skip"] {
                let overlay = app.buttons.matching(
                    NSPredicate(format: "label BEGINSWITH %@", prefix)
                ).firstMatch
                if overlay.exists, overlay.isHittable { overlay.tap() }
            }
        }
        XCTAssertTrue(panelOpened, "Save warning should render at \(context).")
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
        // 90 s: this is the first post-launch wait, so it also absorbs cold
        // bootstrap (SQLCipher open + migrations) on a contended CI Mac.
        XCTAssertTrue(ownerRow.waitForExistence(timeout: 90), "UI test owner should be available.")
        ownerRow.tap()

        let pinField = app.secureTextFields["loginPINField"]
        // 30 s: AX5 Dynamic Type on iPad relayouts the login list slowly under
        // CI load — a 5 s wait flaked (2026-07-31, line: PIN field should appear).
        XCTAssertTrue(pinField.waitForExistence(timeout: 30), "PIN field should appear.")
        pinField.tap()
        pinField.typeText("1234")

        let done = app.buttons["loginPINDoneButton"]
        if done.waitForExistence(timeout: 5), done.isHittable { done.tap() }

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30), "Sign In should appear.")
        signIn.tap()

        // 75 s, not 25: post-sign-in service bootstrap competes with the
        // sibling device-class gate job on the same CI Mac (both gates run
        // concurrently on one machine) — the shell can take over 25 s to
        // appear under that load even though the app is healthy.
        let deadline = Date().addingTimeInterval(75)
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
