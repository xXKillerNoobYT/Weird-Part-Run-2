import XCTest

final class WEI5218AIFallbackQAUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testPhoneOrTabletFallbackResumeGenerationFailureAndRetrySave() throws {
        let suffix = UIDevice.current.userInterfaceIdiom == .pad ? "iPad-768x1024" : "iPhone-390x844"

        launch(preserveDatabase: false)
        openAssistant()

        let unavailableQuestion = "WEI5218 unavailable inventory question"
        let inventoryAnswer = "The Parts module has your full catalog with stock levels. The Warehouse module shows inventory movements and audits."
        send(unavailableQuestion)
        XCTAssertTrue(app.staticTexts[inventoryAnswer].waitForExistence(timeout: 20))
        attachScreenshot("01-\(suffix)-unavailable-fallback-visible")

        relaunch(preserveDatabase: true)
        openAssistant()
        XCTAssertTrue(app.staticTexts[unavailableQuestion].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts[inventoryAnswer].exists)
        openResumeAndSelect(previewPrefix: inventoryAnswer)
        XCTAssertTrue(app.staticTexts[unavailableQuestion].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[inventoryAnswer].exists)
        attachScreenshot("02-\(suffix)-unavailable-resumed-both-turns")

        relaunch(preserveDatabase: true, extraArguments: ["-UITestingAIGenerationFailure"])
        openAssistant()
        app.buttons["New conversation"].tap()
        let generationFailureQuestion = "WEI5218 model generation failure inventory question"
        send(generationFailureQuestion)
        XCTAssertTrue(app.staticTexts[inventoryAnswer].waitForExistence(timeout: 30))
        attachScreenshot("03-\(suffix)-available-reported-generation-fallback")

        relaunch(preserveDatabase: true, extraArguments: ["-UITestingAIGenerationFailure"])
        openAssistant()
        XCTAssertTrue(app.staticTexts[generationFailureQuestion].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts[inventoryAnswer].exists)
        openResumeAndSelect(previewPrefix: inventoryAnswer)
        XCTAssertTrue(app.staticTexts[generationFailureQuestion].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[inventoryAnswer].exists)
        attachScreenshot("04-\(suffix)-generation-failure-resumed")

        relaunch(
            preserveDatabase: false,
            // AIFallbackRetryAccessibilityUITests owns the AX5 layout check; this
            // flow focuses on deterministic persistence and retry behavior.
            extraArguments: ["-UITestingAIFailFirstFallbackWrite"]
        )
        openAssistant()
        app.buttons["New conversation"].tap()
        let writeFailureQuestion = "WEI5218 write failure inventory question"
        send(writeFailureQuestion)

        let warningTitle = app.staticTexts["Conversation turn was not saved"]
        XCTAssertTrue(warningTitle.waitForExistence(timeout: 20))
        let warningDetail = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'simulated storage write failure'")
        ).firstMatch
        XCTAssertTrue(warningDetail.exists)

        let retry = app.buttons["Retry saving conversation turn"]
        let dismiss = app.buttons["Dismiss conversation save warning"]
        let composer = app.textViews.firstMatch
        let sendButton = app.buttons["Send message"]
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(dismiss.exists)
        print("WEI-5218 warning AX: title=\(warningTitle.label), retryLabel=\(retry.label), retryFrame=\(retry.frame), dismissLabel=\(dismiss.label), dismissFrame=\(dismiss.frame), composerEnabled=\(composer.isEnabled), sendEnabled=\(sendButton.isEnabled)")
        attachScreenshot("05-\(suffix)-write-warning-AXXXL")
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        XCTAssertFalse(composer.isEnabled)
        XCTAssertFalse(sendButton.isEnabled)
        XCTAssertLessThanOrEqual(retry.frame.maxY, app.frame.maxY)
        XCTAssertLessThanOrEqual(dismiss.frame.maxY, app.frame.maxY)
        XCTAssertFalse(retry.frame.intersects(dismiss.frame))

        retry.tap()
        XCTAssertTrue(waitForDisappearance(warningTitle, timeout: 20))
        XCTAssertTrue(composer.isEnabled)
        XCTAssertFalse(sendButton.isEnabled, "Send remains disabled only because the composer is empty after save recovery.")
        attachScreenshot("06-\(suffix)-retry-save-cleared-warning")

        relaunch(preserveDatabase: true)
        openAssistant()
        XCTAssertTrue(app.staticTexts[writeFailureQuestion].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts[inventoryAnswer].exists)
        openResumeAndSelect(previewPrefix: inventoryAnswer)
        XCTAssertTrue(app.staticTexts[writeFailureQuestion].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[inventoryAnswer].exists)
        attachScreenshot("07-\(suffix)-retry-saved-pair-resumed")
    }

    private func launch(preserveDatabase: Bool, extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UITestingWEI936AutoLogin", "-UITestingAIUnavailable"] + extraArguments
        if preserveDatabase {
            app.launchArguments.append("-UITestingPreserveDatabase")
        }
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["aiAssistantButton"].waitForExistence(timeout: 30))
    }

    private func relaunch(preserveDatabase: Bool, extraArguments: [String] = []) {
        app?.terminate()
        launch(preserveDatabase: preserveDatabase, extraArguments: extraArguments)
    }

    private func openAssistant() {
        app.buttons["aiAssistantButton"].tap()
        XCTAssertTrue(app.navigationBars["AI Assistant"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Resume a past conversation"].exists)
        XCTAssertTrue(app.buttons["New conversation"].exists)
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
    }

    private func send(_ text: String) {
        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.isEnabled)
        composer.tap()
        composer.typeText(text)
        let sendButton = app.buttons["Send message"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()
        _ = waitForDisappearance(app.staticTexts["Thinking..."], timeout: 30)
    }

    private func openResumeAndSelect(previewPrefix: String) {
        app.buttons["Resume a past conversation"].tap()
        XCTAssertTrue(app.navigationBars["Resume Conversation"].waitForExistence(timeout: 15))
        let row = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Resume conversation: \(previewPrefix)")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        row.tap()
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
