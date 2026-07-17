import XCTest

final class ConflictScreenshotCaptureUITests: XCTestCase {

    private var app: XCUIApplication!
    private let manualOptInMarkerPath = "/tmp/WeirdPartsConflictScreenshotCapture.opt-in"

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        // QA capture mode: keep going on soft assertion failures so we still
        // emit screenshot attachments for the steps that did succeed.
        continueAfterFailure = true

        app = XCUIApplication()
        // Always signal general UI-testing mode; only manual capture runs get
        // the specific fixture mode that seeds and suppresses conflict overlays.
        if let captureScreenshots = ProcessInfo.processInfo.environment["UI_TEST_CONFLICT_SCREENSHOTS"] {
            app.launchEnvironment["UI_TEST_CONFLICT_SCREENSHOTS"] = captureScreenshots
        }
        app.launchArguments += ["-UITesting"]
        if isManualCaptureOptedIn {
            app.launchArguments += ["-UITestingConflictCapture"]
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Conflict screenshot capture
    //
    // Prerequisites (must ALL be true on the simulator / device):
    //   1. At least one user row exists in the login list.
    //   2. That user's PIN is "1234".
    //   3. The post-login dashboard shows a "Review" button leading to Sync Conflicts.
    //
    // The test is skipped automatically on a clean install so it never blocks CI.
    // To run it explicitly, set the environment variable before launching the test:
    //
    //   UI_TEST_CONFLICT_SCREENSHOTS=1 xcodebuild test -scheme "Weird Parts" …
    //
    // In Xcode: Edit Scheme → Test → Arguments → Environment Variables →
    //   Name: UI_TEST_CONFLICT_SCREENSHOTS   Value: 1
    //
    // If this Xcode runner does not expose shell environment variables to the
    // XCTest process, create /tmp/WeirdPartsConflictScreenshotCapture.opt-in
    // before the focused run and remove it after.
    func testCaptureConflictScreenshots() throws {
        guard isManualCaptureOptedIn else {
            throw XCTSkip(
                "Skipped: set the environment variable UI_TEST_CONFLICT_SCREENSHOTS=1 " +
                "or create /tmp/WeirdPartsConflictScreenshotCapture.opt-in, then ensure " +
                "the simulator has a seeded admin user (PIN 1234) with pending sync " +
                "conflicts before running this test."
            )
        }

        app.launch()

        let userRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
        XCTAssertTrue(userRows.firstMatch.waitForExistence(timeout: 12),
                      "No login user rows found — simulator may not have seeded data.")
        userRows.firstMatch.tap()

        let pinField = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pinField.waitForExistence(timeout: 5))
        pinField.tap()
        pinField.typeText("1234")

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        let reviewButton = app.buttons["syncConflictBanner"]

        // Capture dashboard (post-login, banner visible) before tapping Review,
        // so we always have evidence the seed produced unreviewed conflicts even
        // if sheet presentation fails on this iOS build.
        _ = app.staticTexts["3 sync conflicts auto-resolved"].waitForExistence(timeout: 8)
        capture("00-dashboard-with-banner")

        XCTAssertTrue(reviewButton.waitForExistence(timeout: 12),
                      "No sync conflict banner found — simulator may have no pending sync conflicts.")
        XCTAssertTrue(reviewButton.isHittable, "Sync conflict banner exists but is not hittable before tap")
        reviewButton.tap()

        // Sheet may take a moment; wait for any sync-conflict signal rather than
        // pinning to a specific NavigationBar identifier.
        let onSheet = app.staticTexts["Sync Conflicts"].waitForExistence(timeout: 8)
            || app.navigationBars["Sync Conflicts"].waitForExistence(timeout: 2)
            || app.buttons["Done"].waitForExistence(timeout: 2)
        XCTAssertTrue(onSheet, "Conflict review sheet did not appear after banner tap")
        capture("01-sync-conflicts-overview")

        let notes = app.staticTexts["Notes"]
        if notes.waitForExistence(timeout: 3), notes.isHittable {
            notes.tap()
        }
        capture("02-ai-hard-long-text")

        let sheetScroll = app.scrollViews.firstMatch
        if sheetScroll.exists {
            sheetScroll.swipeUp()
        }
        let priorityLabel = app.staticTexts["Priority Label"]
        if priorityLabel.waitForExistence(timeout: 3), priorityLabel.isHittable {
            priorityLabel.tap()
        }
        capture("03-standard-long-value")

        if sheetScroll.exists {
            sheetScroll.swipeUp()
        }

        let useLocalButtons = app.buttons.matching(
            NSPredicate(format: "identifier == 'syncConflictUseLocalValue'")
        )
        if useLocalButtons.count > 0 {
            useLocalButtons.element(boundBy: useLocalButtons.count - 1).tap()
        } else {
            XCTFail("No local-value choice found on the conflict review sheet")
        }

        if waitForCriticalConfirmation() {
            capture("04-critical-alert-presented")

            criticalConfirmationButton(named: "Cancel").tap()
            capture("05-critical-cancel-returned")

            let useRemoteButtons = app.buttons.matching(
                NSPredicate(format: "identifier == 'syncConflictUseRemoteValue'")
            )
            if useRemoteButtons.count > 0 {
                useRemoteButtons.element(boundBy: useRemoteButtons.count - 1).tap()
                if waitForCriticalConfirmation() {
                    criticalConfirmationButton(named: "Confirm").tap()
                }
            } else {
                XCTFail("No remote-value choice found after cancelling the critical decision")
            }
            capture("06-critical-confirm-completed")
        } else {
            // Soft path: still capture whatever the screen shows so we have evidence.
            capture("04-critical-alert-presented-MISSING")
            capture("05-critical-cancel-returned-SKIPPED")
            capture("06-critical-confirm-completed-SKIPPED")
        }
    }

    func testCriticalLocalResolutionHasAccessibleTargetAndRemovesConflict() throws {
        try assertCriticalResolution(
            choiceIdentifier: "syncConflictUseLocalValue",
            appearance: "Light",
            screenshotName: "critical-local-resolved"
        )
    }

    func testCriticalRemoteResolutionHasAccessibleTargetAndRemovesConflict() throws {
        try assertCriticalResolution(
            choiceIdentifier: "syncConflictUseRemoteValue",
            appearance: "Dark",
            screenshotName: "critical-remote-resolved"
        )
    }

    private func assertCriticalResolution(
        choiceIdentifier: String,
        appearance: String,
        screenshotName: String
    ) throws {
        guard isManualCaptureOptedIn else {
            throw XCTSkip("Conflict fixture capture is not opted in.")
        }

        app.launchArguments.append(
            appearance == "Light" ? "-UITestingAppearanceLight" : "-UITestingAppearanceDark"
        )
        print("WEI-4928 appearance: \(appearance)")
        app.launch()
        let user = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'loginUserRow_'"))
            .firstMatch
        XCTAssertTrue(user.waitForExistence(timeout: 12))
        user.tap()
        let pin = app.secureTextFields["loginPINField"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        pin.typeText("1234")
        app.buttons["loginSignInButton"].tap()

        let review = app.buttons["syncConflictBanner"]
        XCTAssertTrue(review.waitForExistence(timeout: 12))
        review.tap()
        let collection = app.collectionViews.firstMatch
        let scrollView = app.scrollViews.firstMatch
        let scrollTarget: XCUIElement
        if collection.exists {
            scrollTarget = collection
        } else if scrollView.exists {
            scrollTarget = scrollView
        } else {
            scrollTarget = app
        }
        let unitCost = app.staticTexts["Unit Cost"]
        for _ in 0..<5 where !unitCost.exists {
            scrollTarget.swipeUp()
            _ = unitCost.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(unitCost.exists)

        let choice = app.buttons[choiceIdentifier]
        for _ in 0..<5 where !choice.isHittable {
            scrollTarget.swipeUp()
            _ = choice.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(choice.exists)
        XCTAssertGreaterThanOrEqual(choice.frame.width, 44)
        XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
        print("WEI-4928 \(choiceIdentifier) AX frame: \(choice.frame)")
        choice.tap()

        XCTAssertTrue(waitForCriticalConfirmation())
        capture("\(screenshotName)-confirmation")
        criticalConfirmationButton(named: "Cancel").tap()
        XCTAssertTrue(unitCost.waitForExistence(timeout: 5), "Cancelling must preserve the unresolved Unit Cost row")
        capture("\(screenshotName)-cancelled")

        choice.tap()
        XCTAssertTrue(waitForCriticalConfirmation())
        criticalConfirmationButton(named: "Confirm").tap()
        XCTAssertTrue(unitCost.waitForNonExistence(timeout: 8))
        XCTAssertFalse(app.alerts["Sync conflict action failed"].exists)
        capture(screenshotName)
    }

    private func waitForCriticalConfirmation(timeout: TimeInterval = 5) -> Bool {
        let title = "Confirm Critical Write Decision"
        return app.alerts[title].waitForExistence(timeout: timeout)
            || app.staticTexts[title].waitForExistence(timeout: timeout)
    }

    private func criticalConfirmationButton(named name: String) -> XCUIElement {
        let alertButton = app.alerts["Confirm Critical Write Decision"].buttons[name]
        if alertButton.exists {
            return alertButton
        }

        let matches = app.buttons.matching(identifier: name)
        for index in 0..<matches.count {
            let candidate = matches.element(boundBy: index)
            if candidate.isHittable {
                return candidate
            }
        }
        return matches.firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var isManualCaptureOptedIn: Bool {
        ProcessInfo.processInfo.environment["UI_TEST_CONFLICT_SCREENSHOTS"] == "1"
            || app.launchEnvironment["UI_TEST_CONFLICT_SCREENSHOTS"] == "1"
            || FileManager.default.fileExists(atPath: manualOptInMarkerPath)
    }
}
