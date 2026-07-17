import XCTest

/// User-like expert re-verification for WEI-5134 / PR #1466.
///
/// The simulator-only launch fixture seeds two real SQLCipher conversation rows and
/// temporarily renames the conversation table. Visible, flag-gated QA controls rename
/// that same table through the app's live GRDB/SQLCipher connection so each failure and
/// Retry action is exercised through the real UI in one launch.
final class WEI5134AIReadFailureQATests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = "8396"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingDispatchBoard",
            "-UITestingWEI5134AIReadFailure",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        restoreConversationTableBestEffort()
        app?.terminate()
        app = nil
    }

    @MainActor
    func testAIConversationReadFailureRecovery() throws {
        let launcher = app.buttons["AI Assistant"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 25), "The signed-in UI must expose the AI launcher.")
        launcher.tap()

        // The fixture starts with the SQLCipher table renamed, so opening the
        // panel exercises the automatic latest-conversation lookup failure.
        assertHistoryFailure(
            expectedCopy: "Conversation history could not be checked. Retry to restore your latest saved conversation.",
            screenshot: "01-latest-history-failure"
        )
        let historyRetry = app.buttons["Retry loading conversation history"]
        assertMinimumTapTarget(historyRetry, named: "Retry loading conversation history")

        restoreConversationTable(in: app)
        historyRetry.tap()
        XCTAssertTrue(
            app.staticTexts["WEI-5134 latest preserved transcript"].waitForExistence(timeout: 10),
            "Retry must recover the latest saved transcript."
        )
        assertComposerEnabled()
        capture("02-latest-history-recovered")

        // Prime the Resume sheet so its two saved rows become the last-known
        // rows that must remain visible through a later list-read failure.
        let resume = app.buttons["Resume a past conversation"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        assertSavedRowsVisible()
        app.navigationBars["Resume Conversation"].buttons["Close"].tap()

        breakConversationTable(in: app)
        resume.tap()
        let listFailureTitle = app.staticTexts["Saved Conversations Could Not Be Loaded"]
        XCTAssertTrue(listFailureTitle.waitForExistence(timeout: 10), "The failed list read must not look empty.")
        XCTAssertFalse(app.staticTexts["No Saved Conversations"].exists)

        let listRetry = app.buttons["Retry loading saved conversations"]
        for _ in 0..<3 where !listRetry.waitForExistence(timeout: 1) {
            scrollResumeSheet(up: false)
        }
        XCTAssertTrue(listRetry.waitForExistence(timeout: 5))
        assertSavedListFailureCopyIsReadable(before: listRetry)
        assertMinimumTapTarget(listRetry, named: "Retry loading saved conversations")
        assertSavedRowsVisible()
        capture("03-saved-list-failure-preserves-rows")

        restoreConversationTable(in: app)
        listRetry.tap()
        XCTAssertTrue(listFailureTitle.waitForNonExistence(timeout: 10), "Retry must clear the saved-list failure state.")
        assertSavedRowsVisible()
        capture("04-saved-list-recovered")

        // With successful rows still visible, remove the table and select the
        // older conversation. This drives the transcript-hydration failure path.
        breakConversationTable(in: app)
        let olderRow = app.buttons["Resume conversation: WEI-5134 older saved transcript"]
        for _ in 0..<3 where !olderRow.waitForExistence(timeout: 1) {
            scrollResumeSheet(up: true)
        }
        XCTAssertTrue(olderRow.waitForExistence(timeout: 5))
        olderRow.tap()

        assertHistoryFailure(
            expectedCopy: "Stored messages could not be loaded. Your saved conversation is still on this device; retry to restore it.",
            screenshot: "05-transcript-hydration-failure"
        )
        assertMinimumTapTarget(historyRetry, named: "Retry loading conversation history after transcript failure")
        XCTAssertFalse(app.staticTexts["How can I help?"].exists, "A read failure must not inject the genuine-empty welcome state.")

        restoreConversationTable(in: app)
        historyRetry.tap()
        XCTAssertTrue(
            app.staticTexts["WEI-5134 older saved transcript"].waitForExistence(timeout: 10),
            "Retry must recover the selected saved transcript."
        )
        assertComposerEnabled()
        capture("06-transcript-hydration-recovered")
    }

    private func assertHistoryFailure(expectedCopy: String, screenshot: String) {
        XCTAssertTrue(app.staticTexts[expectedCopy].waitForExistence(timeout: 10))
        let retry = app.buttons["Retry loading conversation history"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))

        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "The composer should remain visible while fail-closed.")
        XCTAssertFalse(composer.isEnabled, "The composer must be disabled until history recovery succeeds.")

        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled, "Send must be disabled until history recovery succeeds.")
        capture(screenshot)
    }

    private func assertComposerEnabled() {
        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isEnabled, "The composer should re-enable after successful recovery.")
    }

    private func assertSavedRowsVisible() {
        let latestRow = app.buttons["Resume conversation: WEI-5134 latest preserved transcript"]
        var scrollCount = 0
        for _ in 0..<3 where !latestRow.waitForExistence(timeout: 1) {
            scrollResumeSheet(up: true)
            scrollCount += 1
        }
        XCTAssertTrue(
            latestRow.waitForExistence(timeout: 5),
            "The latest saved row must remain visible."
        )
        let olderRow = app.buttons["Resume conversation: WEI-5134 older saved transcript"]
        for _ in 0..<3 where !olderRow.waitForExistence(timeout: 1) {
            scrollResumeSheet(up: true)
            scrollCount += 1
        }
        XCTAssertTrue(
            olderRow.waitForExistence(timeout: 5),
            "The older saved row must remain visible."
        )
        // Return to the sheet top so Retry and the visible break/restore controls
        // remain user-reachable on the shorter iPad sheet detent.
        for _ in 0..<scrollCount {
            scrollResumeSheet(up: false)
        }
    }

    private func assertSavedListFailureCopyIsReadable(before retry: XCUIElement) {
        let expectedCopy = "Saved conversations could not be read. Your last loaded conversations are unchanged; retry to refresh them."
        let message = app.staticTexts.matching(identifier: "savedConversationListReadFailureMessage").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5), "The complete saved-list recovery explanation must be exposed.")
        XCTAssertEqual(message.label, expectedCopy)
        XCTAssertGreaterThanOrEqual(
            message.frame.height,
            34,
            "The recovery explanation must retain its multiline height instead of being vertically clipped."
        )
        XCTAssertLessThanOrEqual(
            message.frame.maxY,
            retry.frame.minY,
            "The Retry control must follow the complete recovery explanation without overlapping it."
        )
    }

    private func scrollResumeSheet(up: Bool) {
        let list = app.collectionViews.firstMatch
        if list.exists {
            up ? list.swipeUp() : list.swipeDown()
        } else {
            up ? app.swipeUp() : app.swipeDown()
        }
    }

    private func assertMinimumTapTarget(_ element: XCUIElement, named name: String) {
        XCTAssertTrue(element.exists, "\(name) must exist before measuring its AX frame.")
        let frame = element.frame
        print("WEI-5134 AX frame — \(name): \(frame.width)×\(frame.height) pt; origin=(\(frame.minX),\(frame.minY))")
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(name) AX width must be at least 44 pt.")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name) AX height must be at least 44 pt.")
    }

    private func breakConversationTable(in application: XCUIApplication) {
        let control = hittableButton(
            named: "WEI5134 break AI conversation table",
            in: application
        )
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Visible QA break control must be available.")
        assertMinimumTapTarget(control, named: "WEI5134 break AI conversation table")
        control.tap()
        assertQAState(application, expected: "WEI5134 QA table state: table broken")
    }

    private func restoreConversationTable(in application: XCUIApplication) {
        let control = hittableButton(
            named: "WEI5134 restore AI conversation table",
            in: application
        )
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Visible QA restore control must be available.")
        assertMinimumTapTarget(control, named: "WEI5134 restore AI conversation table")
        control.tap()
        assertQAState(application, expected: "WEI5134 QA table state: table restored")
    }

    private func restoreConversationTableBestEffort() {
        guard let app, app.state != .notRunning else { return }
        let control = hittableButton(
            named: "WEI5134 restore AI conversation table",
            in: app
        )
        guard control.waitForExistence(timeout: 1) else { return }
        control.tap()
        let state = app.staticTexts.matching(identifier: "wei5134QAState").firstMatch
        guard state.waitForExistence(timeout: 1) else { return }
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "WEI5134 QA table state: table restored"),
            object: state
        )
        _ = XCTWaiter.wait(for: [restored], timeout: 2)
    }

    private func hittableButton(named label: String, in application: XCUIApplication) -> XCUIElement {
        let matches = application.buttons.matching(NSPredicate(format: "label == %@", label))
        return matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
    }

    private func assertQAState(_ application: XCUIApplication, expected: String) {
        let state = application.staticTexts.matching(identifier: "wei5134QAState").firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 5), "The SQLCipher table action must report its completion state.")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: state
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 5),
            .completed,
            "The SQLCipher table action did not reach the expected state; current state: \(state.label)"
        )
        XCTAssertEqual(state.label, expected, "Unexpected SQLCipher QA table state: \(state.label)")
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
