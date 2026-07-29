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
        // The warning assertions require the authenticated app shell. Use the
        // shared deterministic fixture rather than manually driving login and
        // first-run routing, which leaves the AX5 smoke outside its scope.
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
        let dashboardTab = app.descendants(matching: .any)["tab_dashboard"]
        guard dashboardTab.waitForExistence(timeout: 30) else {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Authenticated shell precondition failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("The deterministic UI-test auto-login fixture should reach the authenticated app shell.")
            return
        }
        XCTAssertTrue(dashboardTab.isHittable, "Dashboard should be actionable from the authenticated app shell.")
    }

    @MainActor
    private func openAssistant(context: String) {
        if !name.contains("AX5") {
            let assistantButton = app.descendants(matching: .any)["aiAssistantButton"]
            XCTAssertTrue(assistantButton.waitForExistence(timeout: 15), "AI Assistant should be available at \(context).")
            XCTAssertTrue(assistantButton.isHittable, "AI Assistant should be actionable at \(context).")
            assistantButton.tap()
            return
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            let assistantButton = app.descendants(matching: .any)["sidebarAIAssistantButton"]
            XCTAssertTrue(assistantButton.waitForExistence(timeout: 15), "AI Assistant should be available from the iPad sidebar at \(context).")
            XCTAssertTrue(assistantButton.isHittable, "AI Assistant should be actionable from the iPad sidebar at \(context).")
            assistantButton.tap()
            return
        }

        // AX5 intentionally suppresses the floating control so it cannot
        // overlap dashboard content. Reach the same assistant through the
        // visible More-tab action instead of treating that accessibility layout
        // choice as an authentication failure.
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 15), "More should be available at \(context).")
        XCTAssertTrue(moreTab.isHittable, "More should be actionable at \(context).")
        moreTab.tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 15), "More should open at \(context).")

        // At AX5, More lists overflow modules before account actions. Scroll the
        // user-visible list once to reveal the existing assistant action.
        app.swipeUp()
        let assistantButton = app.buttons["AI Assistant"]
        XCTAssertTrue(assistantButton.waitForExistence(timeout: 15), "AI Assistant should be available from More at \(context).")
        XCTAssertTrue(assistantButton.isHittable, "AI Assistant should be actionable from More at \(context).")
        assistantButton.tap()
    }
}
