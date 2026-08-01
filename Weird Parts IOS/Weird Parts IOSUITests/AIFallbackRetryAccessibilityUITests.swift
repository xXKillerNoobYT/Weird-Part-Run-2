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
        // This smoke validates the warning after the authenticated app shell has
        // mounted. Seed that prerequisite directly instead of attempting an
        // interactive login whose onboarding state is outside this test's scope.
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
        try openAssistant(context: context)

        let warningTitle = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Conversation turn was not saved")
        ).firstMatch
        let warningBody = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Simulated storage write failure for UI verification.")
        ).firstMatch
        let retry = app.buttons["Retry saving conversation turn"]
        let dismiss = app.buttons["Dismiss conversation save warning"]

        XCTAssertTrue(warningTitle.waitForExistence(timeout: 30), "Save warning should render at \(context).")
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
    private func openAssistant(context: String) throws {
        let shell = app.descendants(matching: .any)["tab_dashboard"]
        XCTAssertTrue(shell.waitForExistence(timeout: 30), "Authenticated app shell should mount at \(context).")

        let floatingAssistant = app.descendants(matching: .any)["aiAssistantButton"]
        if floatingAssistant.exists, floatingAssistant.isHittable {
            floatingAssistant.tap()
            return
        }

        let sidebarAssistant = app.descendants(matching: .any)["sidebarAIAssistantButton"]
        if sidebarAssistant.exists, sidebarAssistant.isHittable {
            sidebarAssistant.tap()
            return
        }

        // The compact floating action is intentionally suppressed at AX sizes;
        // More is the production-accessible route to the same assistant.
        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(moreTab.waitForExistence(timeout: 10), "More tab should expose the AX assistant route at \(context).")
        moreTab.tap()

        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: 10), "More should open at \(context).")
        let moreAssistant = app.buttons["AI Assistant"]
        XCTAssertTrue(moreAssistant.waitForExistence(timeout: 10), "More should expose AI Assistant at \(context).")
        XCTAssertTrue(moreAssistant.isHittable, "More AI Assistant route should be user-actionable at \(context).")
        moreAssistant.tap()
    }
}
