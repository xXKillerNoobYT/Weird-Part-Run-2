import XCTest

/// Runtime accessibility regression coverage for GitHub #1505.
///
/// The same test runs against phone and tablet destinations so the exported
/// XCUIElement frames—not merely SwiftUI's requested layout—prove the minimum
/// 44pt interaction targets.
final class AIAssistantComposerAccessibilityUITests: XCTestCase {
    private static let uiTestingPIN = "8396"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @MainActor
    func testComposerAndSendTargetRemainAccessibleForInformationalQuery() throws {
        // AppCore seeds and authenticates the UI-test owner asynchronously. Give
        // the shell time to settle before XCTest takes its first accessibility
        // snapshot; querying during launch can make the simulator report a busy
        // main run loop instead of the finished dashboard tree.
        RunLoop.current.run(until: Date().addingTimeInterval(8))

        let assistantLauncher = app.descendants(matching: .any)["aiAssistantButton"]
        XCTAssertTrue(
            assistantLauncher.waitForExistence(timeout: 20),
            "The signed-in dashboard must expose the AI Assistant launcher."
        )
        assistantLauncher.tap()

        let composer = app.textViews["Message for AI Assistant"]
        XCTAssertTrue(
            composer.waitForExistence(timeout: 10),
            "The AI assistant must expose a labelled message composer."
        )
        XCTAssertFalse(composer.label.isEmpty, "The composer must have a usable accessibility name.")
        XCTAssertGreaterThanOrEqual(
            composer.frame.height,
            44,
            "The exported composer interaction frame must be at least 44pt high."
        )

        let send = app.buttons["Send message"]
        XCTAssertTrue(send.exists, "The assistant must expose a named Send message button.")
        XCTAssertFalse(send.label.isEmpty, "The Send action must have a usable accessibility name.")
        XCTAssertGreaterThanOrEqual(send.frame.width, 44, "The exported Send target must be at least 44pt wide.")
        XCTAssertGreaterThanOrEqual(send.frame.height, 44, "The exported Send target must be at least 44pt high.")
        print(
            "[WEI-1505] composer=\(composer.frame.width)x\(composer.frame.height) "
                + "send=\(send.frame.width)x\(send.frame.height)"
        )

        let informationalQuery = "What does the draft filter mean?"
        composer.tap()
        composer.typeText(informationalQuery)
        XCTAssertTrue(send.isEnabled, "Send should enable after the user enters an informational question.")
        send.tap()

        XCTAssertTrue(
            app.staticTexts[informationalQuery].waitForExistence(timeout: 5),
            "Sending an informational query should add it to the conversation."
        )
        XCTAssertFalse(
            app.alerts["Clear filter?"].waitForExistence(timeout: 2),
            "An informational query must not present the destructive Clear filter confirmation."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "AI assistant composer accessibility evidence"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
