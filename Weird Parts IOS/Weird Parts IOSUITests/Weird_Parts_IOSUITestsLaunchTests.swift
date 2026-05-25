//
//  Weird_Parts_IOSUITestsLaunchTests.swift
//  Weird Parts IOSUITests
//
//  Launch tests capture screenshots at various points in the app lifecycle.
//  These are useful for App Store screenshots and visual regression testing.
//

import XCTest

final class Weird_Parts_IOSUITestsLaunchTests: XCTestCase {
    private static let uiTestingPIN = "8396"

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
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
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = Self.uiTestingPIN
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
}
