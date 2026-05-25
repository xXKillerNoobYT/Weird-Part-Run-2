import XCTest

/// WEI-936 first-launch onboarding C10 QA harness.
///
/// Provides deterministic fixture states for all six required evidence captures:
///   1. Welcome sheet       — `-UITestingWEI936Welcome`
///   2. Not-started card    — `-UITestingWEI936NotStarted`
///   3. In-progress banner  — `-UITestingWEI936TourActive` + navigate to Jobs
///   4. Required-done strip — `-UITestingWEI936RequiredDone`
///   5. Dismiss toast       — `-UITestingWEI936NotStarted` + tap dismiss
///   6. Celebration screen  — `-UITestingWEI936Celebration`
///
/// Each test is independent and relaunches the app with a fresh fixture state.
/// `continueAfterFailure = true` keeps captures running even if one state fails,
/// matching the QA evidence-collection intent from the issue.
///
/// # How to run
/// ```
/// xcodebuild test \
///   -scheme "Weird Parts IOS" \
///   -destination "platform=iOS Simulator,name=iPad Pro (12.9-inch)" \
///   -only-testing "Weird Parts IOSUITests/WEI936OnboardingQAUITests"
/// ```
/// For landscape evidence set `WEI_1185_LANDSCAPE=1` in the scheme environment.
final class WEI936OnboardingQAUITests: XCTestCase {

    private var app: XCUIApplication!
    private static let uiTestingPIN = "8396"

    // MARK: - Setup & Teardown

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - State 1: Welcome sheet

    /// Verifies the first-launch welcome screen is reachable with
    /// `-UITestingWEI936Welcome`.  No login is needed — the welcome view is
    /// shown before the user-selection screen.
    @MainActor
    func testWEI936State1WelcomeSheet() {
        launchForWEI936(["-UITestingWEI936Welcome"])
        XCTAssertTrue(
            app.staticTexts["WiredPart"].waitForExistence(timeout: 20),
            "WEI-936 state 1: welcome fixture must render the first-launch welcome screen"
        )
        captureWEI936("wei936-01-welcome-sheet")
    }

    // MARK: - State 2: Not-started (Getting Started checklist, 0 data steps done)

    /// Verifies the Getting Started checklist is visible when no business data
    /// has been seeded.  `-UITestingWEI936NotStarted` skips parts/job seeding so
    /// `isFirstLaunchState == true` on the Dashboard.
    @MainActor
    func testWEI936State2NotStarted() {
        launchForWEI936(["-UITestingWEI936NotStarted", "-UITestingWEI936AutoLogin"])
        waitForDashboard()
        XCTAssertTrue(
            app.staticTexts["Getting Started"].waitForExistence(timeout: 20),
            "WEI-936 state 2: not-started fixture must show the Getting Started checklist"
        )
        captureWEI936("wei936-02-card-not-started")
    }

    // MARK: - State 3: In-progress (per-page "Try This" guidance banner)

    /// Verifies the per-page OnboardingBanner shows "Try This" when the guided
    /// tour is active and required tasks are incomplete.  Navigates to the Jobs
    /// list where required tasks (`jobs-view-list`, `jobs-create`,
    /// `jobs-tap-detail`) are never auto-completed, giving a stable capture.
    @MainActor
    func testWEI936State3InProgress() {
        launchForWEI936(["-UITestingWEI936TourActive", "-UITestingWEI936AutoLogin"])
        waitForDashboard()

        // Navigate to the Jobs tab — "Try This" is stable here because Jobs list
        // tasks are never auto-marked complete by the list page itself.
        let jobsTab = app.buttons["tab_jobs"]
        if jobsTab.waitForExistence(timeout: 10) && jobsTab.isHittable {
            jobsTab.tap()
        }

        XCTAssertTrue(
            app.staticTexts["Try This"].waitForExistence(timeout: 20),
            "WEI-936 state 3: tour-active fixture must show the 'Try This' in-progress guidance banner"
        )
        captureWEI936("wei936-03-in-progress-banner")
    }

    // MARK: - State 4: Required-done collapsed strip

    /// Verifies the Dashboard OnboardingBanner collapses to the
    /// "Required tour steps complete" indicator when all required tasks for
    /// the dashboard-home page are marked done by the fixture.
    @MainActor
    func testWEI936State4RequiredDoneCollapsedStrip() {
        launchForWEI936(["-UITestingWEI936RequiredDone", "-UITestingWEI936AutoLogin"])
        waitForDashboard()
        XCTAssertTrue(
            app.staticTexts["Required tour steps complete"].waitForExistence(timeout: 20),
            "WEI-936 state 4: required-done fixture must collapse the per-page banner"
        )
        captureWEI936("wei936-04-required-done-collapsed-strip")
    }

    // MARK: - State 5: Dismiss toast

    /// Verifies the "Checklist dismissed" toast appears after tapping the
    /// dismiss (×) control in the Getting Started checklist card.
    /// Uses `-UITestingWEI936NotStarted` so the checklist is visible.
    @MainActor
    func testWEI936State5DismissToast() {
        launchForWEI936(["-UITestingWEI936NotStarted", "-UITestingWEI936AutoLogin"])
        waitForDashboard()

        let dismissButton = app.buttons["Dismiss checklist"]
        XCTAssertTrue(
            dismissButton.waitForExistence(timeout: 20),
            "WEI-936 state 5: not-started fixture must show the Dismiss checklist button"
        )
        dismissButton.tap()

        XCTAssertTrue(
            app.staticTexts["Checklist dismissed"].waitForExistence(timeout: 5),
            "WEI-936 state 5: tapping dismiss must show the Checklist dismissed undo toast"
        )
        captureWEI936("wei936-05-dismiss-toast")
    }

    // MARK: - State 6: Celebration (all done)

    /// Verifies the completion/celebration screen ("You're All Set!") is
    /// reachable with `-UITestingWEI936Celebration`.  The view is shown before
    /// the user-selection screen, so no login is needed.
    @MainActor
    func testWEI936State6Celebration() {
        launchForWEI936(["-UITestingWEI936Celebration"])
        XCTAssertTrue(
            app.staticTexts["You're All Set!"].waitForExistence(timeout: 20),
            "WEI-936 state 6: celebration fixture must render the You're All Set! completion screen"
        )
        captureWEI936("wei936-06-celebration")
    }

    // MARK: - Private helpers

    /// Launch the app with `-UITesting` plus the supplied WEI-936 fixture flags.
    private func launchForWEI936(_ flags: [String]) {
        app.terminate()
        app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
        app.launchArguments += ["-UITesting"] + flags
        if ProcessInfo.processInfo.environment["WEI_1185_LANDSCAPE"] == "1" {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        app.launch()
    }

    /// Wait until the Dashboard tab or a recognisable main-app element is
    /// visible.  When `-UITestingWEI936AutoLogin` is active the app bypasses
    /// the login screen entirely, so we only need a short stabilisation wait.
    private func waitForDashboard(timeout: TimeInterval = 20) {
        _ = app.buttons["tab_dashboard"].waitForExistence(timeout: timeout)
    }

    /// Attach a PNG screenshot to the test report and optionally write it to
    /// disk if `WEI_936_ARTIFACT_DIR` is set in the environment.
    private func captureWEI936(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let dirPath = ProcessInfo.processInfo.environment["WEI_936_ARTIFACT_DIR"],
           !dirPath.isEmpty {
            let dir = URL(fileURLWithPath: dirPath)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: file, options: .atomic)
        }
    }
}
