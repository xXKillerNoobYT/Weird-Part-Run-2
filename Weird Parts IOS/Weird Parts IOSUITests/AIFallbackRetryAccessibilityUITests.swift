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
        // The warning is asserted from the authenticated shell, not through a
        // manual PIN/onboarding flow that belongs to separate coverage.
        application.launchArguments = [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingAIFallbackSaveWarning",
        ]
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
        waitForAuthenticatedAppShell()
        openAssistant(context: context)

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
    private func waitForAuthenticatedAppShell() {
        let dashboard = app.descendants(matching: .any)["tab_dashboard"]
        guard dashboard.waitForExistence(timeout: 30) else {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Authenticated shell precondition failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("The deterministic UI-test fixture should mount the authenticated app shell.")
            return
        }
        XCTAssertTrue(dashboard.isHittable, "The authenticated dashboard shell should be actionable.")
    }

    @MainActor
    private func openAssistant(context: String) {
        if name.contains("AX5") && UIDevice.current.userInterfaceIdiom == .pad {
            // iPad defaults to the full sidebar. This is the AX5 regression
            // path: the visible sidebar action must open the warning directly.
            let assistant = app.descendants(matching: .any)["sidebarAIAssistantButton"]
            XCTAssertTrue(assistant.waitForExistence(timeout: 15), "Full-sidebar AI Assistant should be visible at \(context).")
            XCTAssertTrue(assistant.isHittable, "Full-sidebar AI Assistant should be hittable at \(context).")
            XCTAssertGreaterThanOrEqual(assistant.frame.height, 44, "Full-sidebar AI Assistant must retain a 44pt target at \(context).")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(assistant.frame), "Full-sidebar AI Assistant must remain in the visible viewport at \(context).")
            assistant.tap()
            return
        }

        let assistant = app.descendants(matching: .any)["aiAssistantButton"]
        XCTAssertTrue(assistant.waitForExistence(timeout: 15), "AI Assistant should be available at \(context).")
        XCTAssertTrue(assistant.isHittable, "AI Assistant should be actionable at \(context).")
        assistant.tap()
    }
}
