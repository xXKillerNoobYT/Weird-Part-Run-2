import XCTest

/// User-like prerequisite unavailable → available recovery proof for WEI-5159 / PR #1466.
///
/// The app shell boots with its dedicated UI-test database and authenticated fixture user,
/// while the doubly gated simulator seam withholds only the AI conversation-read prerequisites.
/// Visible controls restore/withhold those prerequisites without recreating the panel.
final class WEI5159AIPrerequisiteRecoveryQATests: XCTestCase {
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
            "-UITestingWEI5159AIPrerequisiteRecovery",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    @MainActor
    func testUnavailablePrerequisitesRecoverInitializationAndResumeList() throws {
        let launcher = app.buttons["AI Assistant"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 25), "The signed-in UI must expose the AI launcher.")
        launcher.tap()

        assertQAState("WEI5159 QA prerequisites: unavailable")
        let restore = hittableButton(named: "WEI5159 restore AI conversation prerequisites")
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        assertMinimumTapTarget(restore, named: "Restore AI prerequisites")
        assertComposerDisabled()
        XCTAssertFalse(
            app.staticTexts["How can I help?"].exists,
            "Missing initialization prerequisites must not substitute a genuine-empty welcome message."
        )
        capture("01-prerequisites-unavailable-fail-closed")

        restore.tap()
        assertQAState("WEI5159 QA prerequisites: available")
        XCTAssertTrue(
            app.staticTexts["WEI-5134 latest preserved transcript"].waitForExistence(timeout: 10),
            "Restoring prerequisites must restart initialization and recover the latest transcript in the mounted panel."
        )
        assertComposerEnabled()
        capture("02-prerequisites-restored-initialization-recovers")

        let resume = app.buttons["Resume a past conversation"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        assertSinglePrerequisiteQAControlSurface()
        assertSavedRowsReachable()
        let closeResume = hittableButton(named: "Close")
        XCTAssertTrue(closeResume.waitForExistence(timeout: 5), "Resume must expose a reachable Close control.")
        closeResume.tap()

        let withhold = hittableButton(named: "WEI5159 withhold AI conversation prerequisites")
        XCTAssertTrue(withhold.waitForExistence(timeout: 5))
        assertMinimumTapTarget(withhold, named: "Withhold AI prerequisites")
        withhold.tap()
        assertQAState("WEI5159 QA prerequisites: unavailable")

        resume.tap()
        let failureTitle = app.staticTexts["Saved Conversations Could Not Be Loaded"]
        XCTAssertTrue(failureTitle.waitForExistence(timeout: 10), "Missing prerequisites must end loading with a readable error.")
        XCTAssertFalse(app.staticTexts["Loading conversations…"].exists, "The Resume spinner must yield to the prerequisite error.")
        XCTAssertFalse(app.staticTexts["No Saved Conversations"].exists)
        XCTAssertTrue(
            app.staticTexts["The database or signed-in user is unavailable. Try again after signing in and the app finishes loading."].waitForExistence(timeout: 5)
        )
        assertSavedRowsReachable()

        let listRetry = reachableButton(named: "Retry loading saved conversations")
        assertMinimumTapTarget(listRetry, named: "Retry loading saved conversations")
        capture("03-resume-prerequisite-failure-preserves-rows")

        let sheetRestore = reachableButton(named: "WEI5159 restore AI conversation prerequisites")
        assertMinimumTapTarget(sheetRestore, named: "Restore AI prerequisites in Resume")
        sheetRestore.tap()
        assertQAState("WEI5159 QA prerequisites: available")
        XCTAssertTrue(failureTitle.exists, "Restoring prerequisites must keep the retryable error visible until the user retries.")

        let retryAfterRestore = reachableButton(named: "Retry loading saved conversations")
        retryAfterRestore.tap()
        XCTAssertTrue(waitForNonExistence(failureTitle, timeout: 10), "Retry must clear the prerequisite error after restoration.")
        assertSavedRowsReachable()
        capture("04-resume-restore-and-retry-recovers")
    }

    private func assertComposerDisabled() {
        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(composer.isEnabled, "The composer must remain disabled while prerequisites are unavailable.")
        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(send.isEnabled, "Send must remain disabled while prerequisites are unavailable.")
    }

    private func assertComposerEnabled() {
        let composer = app.textViews.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isEnabled, "The composer must re-enable after prerequisite recovery.")
    }

    private func assertSinglePrerequisiteQAControlSurface() {
        for label in [
            "WEI5159 withhold AI conversation prerequisites",
            "WEI5159 restore AI conversation prerequisites",
        ] {
            XCTAssertEqual(
                app.buttons.matching(NSPredicate(format: "label == %@", label)).count,
                1,
                "Resume must own exactly one accessible \(label) control."
            )
        }
        XCTAssertEqual(app.staticTexts.matching(identifier: "wei5159QAState").count, 1)
    }

    private func assertSavedRowsReachable() {
        var scrollCount = 0
        for label in [
            "Resume conversation: WEI-5134 latest preserved transcript",
            "Resume conversation: WEI-5134 older saved transcript",
        ] {
            let row = app.buttons[label]
            for _ in 0..<4 where !row.waitForExistence(timeout: 1) {
                scrollResumeSheet(up: true)
                scrollCount += 1
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Last-known row must remain reachable: \(label)")
        }
        for _ in 0..<scrollCount {
            scrollResumeSheet(up: false)
        }
    }

    private func reachableButton(named label: String) -> XCUIElement {
        let button = app.buttons[label]
        for _ in 0..<4 where !button.waitForExistence(timeout: 1) || !button.isHittable {
            scrollResumeSheet(up: false)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Expected reachable button: \(label)")
        return button
    }

    private func scrollResumeSheet(up: Bool) {
        let list = app.collectionViews.firstMatch
        if list.exists {
            up ? list.swipeUp() : list.swipeDown()
        } else {
            up ? app.swipeUp() : app.swipeDown()
        }
    }

    private func hittableButton(named label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        return matches.allElementsBoundByIndex.first(where: \.isHittable) ?? matches.firstMatch
    }

    private func assertQAState(_ expected: String) {
        let state = app.staticTexts.matching(identifier: "wei5159QAState").firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected),
            object: state
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        XCTAssertEqual(state.label, expected)
    }

    private func assertMinimumTapTarget(_ element: XCUIElement, named name: String) {
        XCTAssertTrue(element.exists, "\(name) must exist before measuring its AX frame.")
        let frame = element.frame
        print("WEI-5159 AX frame — \(name): \(frame.width)×\(frame.height) pt; origin=(\(frame.minX),\(frame.minY))")
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(name) AX width must be at least 44 pt.")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name) AX height must be at least 44 pt.")
    }

    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
