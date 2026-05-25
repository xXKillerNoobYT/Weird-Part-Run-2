import XCTest

final class ConflictScreenshotCaptureUITests: XCTestCase {

    private var app: XCUIApplication!
    private static let uiTestingPIN = "8396"

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        // QA capture mode: keep going on soft assertion failures so we still
        // emit screenshot attachments for the steps that did succeed.
        continueAfterFailure = true

        app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
        // Signal both general UI-testing mode and the specific conflict-capture
        // mode so the app can (now or in the future) seed the required fixtures.
        app.launchArguments += ["-UITesting", "-UITestingConflictCapture"]
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Conflict screenshot capture
    //
    // Prerequisites (must ALL be true on the simulator / device):
    //   1. At least one user row exists in the login list.
    //   2. That user's PIN matches WEIRD_PARTS_UI_TEST_PIN.
    //   3. The post-login dashboard shows a "Review" button leading to Sync Conflicts.
    //
    // The test is skipped automatically on a clean install so it never blocks CI.
    // To run it explicitly, set the environment variable before launching the test:
    //
    //   UI_TEST_CONFLICT_SCREENSHOTS=1 xcodebuild test -scheme "Weird Parts IOS" …
    //
    // In Xcode: Edit Scheme → Test → Arguments → Environment Variables →
    //   Name: UI_TEST_CONFLICT_SCREENSHOTS   Value: 1
    func testCaptureConflictScreenshots() throws {
        guard ProcessInfo.processInfo.environment["UI_TEST_CONFLICT_SCREENSHOTS"] == "1" else {
            throw XCTSkip(
                "Skipped: set the environment variable UI_TEST_CONFLICT_SCREENSHOTS=1 " +
                "and ensure the simulator has a seeded admin user using WEIRD_PARTS_UI_TEST_PIN with " +
                "pending sync conflicts before running this test."
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
        pinField.typeText(Self.uiTestingPIN)

        let signIn = app.buttons["loginSignInButton"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()

        // Auth is async, and the post-login Welcome / Quick Tour modals can
        // appear after a fixed waitForExistence window expires. Poll
        // adaptively for up to 30s and dismiss whichever modal is currently
        // visible, until the sync conflict banner becomes hittable.
        let welcomeCTA = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Got It'")).firstMatch
        let skipTour = app.buttons["Skip"]
        let reviewButton = app.buttons["syncConflictBanner"]
        let pollDeadline = Date().addingTimeInterval(30)
        while Date() < pollDeadline {
            if reviewButton.exists && reviewButton.isHittable { break }
            if welcomeCTA.exists && welcomeCTA.isHittable { welcomeCTA.tap(); continue }
            if skipTour.exists && skipTour.isHittable { skipTour.tap(); continue }
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Capture dashboard (post-login, banner visible) before tapping Review,
        // so we always have evidence the seed produced unreviewed conflicts even
        // if sheet presentation fails on this iOS build.
        _ = app.staticTexts["3 sync conflicts auto-resolved"].waitForExistence(timeout: 8)
        capture("00-dashboard-with-banner")

        XCTAssertTrue(reviewButton.waitForExistence(timeout: 12),
                      "No sync conflict banner found — simulator may have no pending sync conflicts.")
        // Defense-in-depth: a modal could have re-presented between capture and Review tap.
        if welcomeCTA.exists && welcomeCTA.isHittable { welcomeCTA.tap() }
        if skipTour.exists && skipTour.isHittable { skipTour.tap() }
        _ = reviewButton.waitForExistence(timeout: 4)
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

        let useThisButtons = app.buttons.matching(NSPredicate(format: "label == 'Use This'"))
        if useThisButtons.count > 0 {
            useThisButtons.element(boundBy: useThisButtons.count - 1).tap()
        } else {
            XCTFail("No 'Use This' buttons found on the conflict review sheet")
        }

        let alert = app.alerts["Confirm Critical Write Decision"]
        if alert.waitForExistence(timeout: 5) {
            capture("04-critical-alert-presented")

            alert.buttons["Cancel"].tap()
            capture("05-critical-cancel-returned")

            let useThisAgain = app.buttons.matching(NSPredicate(format: "label == 'Use This'"))
            if useThisAgain.count > 0 {
                useThisAgain.element(boundBy: useThisAgain.count - 1).tap()
                if alert.waitForExistence(timeout: 5) {
                    alert.buttons["Confirm"].tap()
                }
            }
            capture("06-critical-confirm-completed")
        } else {
            // Soft path: still capture whatever the screen shows so we have evidence.
            capture("04-critical-alert-presented-MISSING")
            capture("05-critical-cancel-returned-SKIPPED")
            capture("06-critical-confirm-completed-SKIPPED")
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
