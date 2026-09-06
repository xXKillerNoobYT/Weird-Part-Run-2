//
//  Weird_Parts_IOSUITestsLaunchTests.swift
//  Weird Parts IOSUITests
//
//  Launch tests capture screenshots at various points in the app lifecycle.
//  These are useful for App Store screenshots and visual regression testing.
//

import XCTest

final class Weird_Parts_IOSUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        // Wait for the app to be ready (loading should complete)
        // The app shows either onboarding, login, or main view
        sleep(3)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchToMainView() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        // Wait for app to fully load
        sleep(5)

        // Take screenshot of whatever state we land on
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Main View After Launch"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testStartupFailureReportShowsExactDiagnostics() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-UITestingStartupErrorReport"]
        app.launch()

        let reportButton = app.buttons["startup-report-problem-button"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 20))
        reportButton.tap()

        XCTAssertTrue(app.navigationBars["Report a Bug"].waitForExistence(timeout: 20))

        let startupError = materializedElement("bug-report-startup-error-row", in: app)
        XCTAssertTrue(startupError.label.contains("Startup error"))
        XCTAssertTrue(
            startupError.label.contains("UITest startup failure: OSStatus -25308")
                || (startupError.value as? String)?.contains("UITest startup failure: OSStatus -25308") == true
        )

        let page = materializedElement("bug-report-page-row", in: app)
        XCTAssertTrue(page.label.contains("Page"))
        XCTAssertTrue(page.label.contains("Startup") || (page.value as? String)?.contains("Startup") == true)

        let device = materializedElement("bug-report-device-row", in: app)
        XCTAssertTrue(device.label.contains("Device"))

        let os = materializedElement("bug-report-os-row", in: app)
        XCTAssertTrue(os.label.contains("OS"))

        let mac = materializedElement("bug-report-ios-on-mac-row", in: app)
        XCTAssertTrue(mac.label.contains("iOS app on Mac"))
    }

    private func materializedElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        let form = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.scrollViews.firstMatch
        for _ in 0..<6 where !element.exists {
            form.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected diagnostic row \(identifier).")
        return element
    }
}
