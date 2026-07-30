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
            "-UITestingClearMovementWizardDraft",
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

    @MainActor
    func testDirectWarehouseQRScanAddsScannedPartToRestoredDraft() throws {
        let app = XCUIApplication()
        app.launchEnvironment["WEIRD_PARTS_UI_TEST_PIN"] = "8396"
        app.launchArguments += [
            "-UITesting",
            "-UITestingWEI936AutoLogin",
            "-UITestingDispatchBoard",
            "-UITestingWarehouseMovements",
            "-UITestingClearMovementWizardDraft",
        ]
        app.launch()

        let openWizard = app.descendants(matching: .any)["whMovement_openWizard"].firstMatch
        XCTAssertTrue(openWizard.waitForExistence(timeout: 10))
        openWizard.tap()

        let fromWarehouse = app.descendants(matching: .any)["movementWizard_from_warehouse"].firstMatch
        XCTAssertTrue(fromWarehouse.waitForExistence(timeout: 10))
        fromWarehouse.tap()
        let toTruck = app.descendants(matching: .any)["movementWizard_to_truck"].firstMatch
        XCTAssertTrue(toTruck.waitForExistence(timeout: 5))
        toTruck.tap()
        let next = app.descendants(matching: .any)["movement_wizard_next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isEnabled)
        next.tap()

        let searchField = app.textFields["Search by name or code…"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("UITEST-QA-WIRE")
        let draftPart = app.descendants(matching: .any)["movement_wizard_part_result_900002"].firstMatch
        XCTAssertTrue(draftPart.waitForExistence(timeout: 10))
        draftPart.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["movement_wizard_selected_part_900002"].waitForExistence(timeout: 5),
            "The selected draft part must be rendered before saving the draft."
        )

        let saveDraft = app.buttons["Save & Exit"].firstMatch
        XCTAssertTrue(saveDraft.waitForExistence(timeout: 5))
        saveDraft.tap()

        let scanButton = app.descendants(matching: .any)["whMovement_scanQR"].firstMatch
        XCTAssertTrue(scanButton.waitForExistence(timeout: 10))
        scanButton.tap()
        let manualCodeField = app.textFields["qrScanManualCodeField"].firstMatch
        XCTAssertTrue(manualCodeField.waitForExistence(timeout: 10))
        manualCodeField.tap()
        manualCodeField.typeText("{\"app\":\"wiredpart\",\"version\":2,\"type\":\"part\",\"id\":900001,\"code\":\"UITEST-QA-CONDUIT\"}")
        app.buttons["qrScanLookUpButton"].firstMatch.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["movement_wizard_selected_part_900002"].waitForExistence(timeout: 10),
            "The existing draft selection must remain available after a direct QR handoff."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["movement_wizard_selected_part_900001"].waitForExistence(timeout: 10),
            "The newly scanned part must be added to a restored movement draft."
        )
    }
}
