import XCTest

/// Exercises the pairing empty state with the same simulator-only injected
/// transport outcome that the app uses for UI verification. The flags have no
/// shipping UI control and are unavailable outside DEBUG simulator builds.
final class DevicePairingTransportErrorUITests: XCTestCase {
    @MainActor
    func testTransportErrorExportsDiagnosticIdentifierAndValue() {
        let app = launchPairingFixture("-UITestingDevicePairingTransportError")
        let genericGuidance = app.staticTexts["No shop computer found nearby."]
        let diagnostic = app.descendants(matching: .any)["device-pairing-transport-error"].firstMatch

        XCTAssertTrue(genericGuidance.waitForExistence(timeout: 15))
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5))
        XCTAssertEqual(diagnostic.value as? String, "BT-SCAN-START — access denied")
        XCTAssertEqual(diagnostic.label, "Bluetooth could not start")
    }

    @MainActor
    func testNoTransportErrorKeepsGenericGuidanceWithoutDiagnostic() {
        let app = launchPairingFixture("-UITestingDevicePairingNoTransportError")
        let genericGuidance = app.staticTexts["No shop computer found nearby."]
        let diagnostic = app.descendants(matching: .any)["device-pairing-transport-error"].firstMatch

        XCTAssertTrue(genericGuidance.waitForExistence(timeout: 15))
        XCTAssertFalse(diagnostic.exists)
    }

    private func launchPairingFixture(_ fixtureArgument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", fixtureArgument]
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launch()
        return app
    }
}