import XCTest

final class WarehouseMovementsQRScanUITests: XCTestCase {
    @MainActor
    func testDirectWarehouseQRScanOpensMovementWizardWithScannedPart() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = "8396"
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingDispatchBoard",
            "-UITestingWarehouseMovements",
        ]
        app.launch()

        let scanButton = app.descendants(matching: .any)["whMovement_scanQR"].firstMatch
        XCTAssertTrue(
            scanButton.waitForExistence(timeout: 10),
            "Warehouse Movements must expose its direct QR scan action."
        )
        scanButton.tap()

        let manualCodeField = app.textFields["qrScanManualCodeField"].firstMatch
        XCTAssertTrue(
            manualCodeField.waitForExistence(timeout: 10),
            "The QR scanner must provide manual entry on the simulator."
        )
        manualCodeField.tap()
        manualCodeField.typeText("{\"app\":\"wiredpart\",\"version\":2,\"type\":\"part\",\"id\":900001,\"code\":\"UITEST-QA-CONDUIT\"}")
        app.buttons["qrScanLookUpButton"].firstMatch.tap()

        let fromWarehouse = app.descendants(matching: .any)["movementWizard_from_warehouse"].firstMatch
        XCTAssertTrue(
            fromWarehouse.waitForExistence(timeout: 10),
            "A matching direct Warehouse Movements scan must open the movement wizard."
        )
        fromWarehouse.tap()
        app.descendants(matching: .any)["movementWizard_to_truck"].firstMatch.tap()
        let next = app.descendants(matching: .any)["movement_wizard_next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isEnabled)
        next.tap()

        XCTAssertTrue(
            app.staticTexts["UITesting QA Conduit"].waitForExistence(timeout: 10),
            "The scanned part must be preselected after the wizard advances to its Parts step."
        )
    }
}
