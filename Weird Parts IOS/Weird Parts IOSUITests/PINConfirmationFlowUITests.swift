import XCTest

/// User-path coverage for the PIN confirmation and self-service PIN change flow (#1881).
///
/// These tests launch the real app against its deterministic UI-test database,
/// navigate through the visible People and account interfaces, and submit the
/// production forms. No PIN is printed in assertion messages or attachments.
final class PINConfirmationFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
        app.launchArguments += ["-UITesting", "-UITestingWEI936AutoLogin"]
        app.launch()
    }

    @MainActor
    func testAddEmployeeRequiresMatchingConfirmationThenCreatesEmployee() throws {
        openEmployees()

        let addEmployee = app.buttons["Add employee"]
        XCTAssertTrue(addEmployee.waitForExistence(timeout: 20))
        addEmployee.tap()
        XCTAssertTrue(app.navigationBars["Add Employee"].waitForExistence(timeout: 10))

        let name = element("add-employee-display-name-field")
        let pin = element("add-employee-pin-field")
        let confirmation = element("add-employee-pin-confirmation-field")
        let save = element("add-employee-save-button")
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(pin.exists)
        XCTAssertTrue(confirmation.exists)
        XCTAssertTrue(save.exists)

        name.tap()
        name.typeText("PIN Confirmation Employee")
        pin.tap()
        pin.typeText("2468")
        save.tap()

        let validationError = element("add-employee-pin-validation-error")
        XCTAssertTrue(validationError.waitForExistence(timeout: 5))
        XCTAssertEqual(validationError.label, "PIN validation error: Confirm the new PIN.")
        XCTAssertTrue(app.navigationBars["Add Employee"].exists)

        confirmation.tap()
        confirmation.typeText("1357")
        save.tap()
        XCTAssertTrue(validationError.waitForExistence(timeout: 5))
        XCTAssertEqual(validationError.label, "PIN validation error: PIN entries do not match.")
        XCTAssertTrue(app.navigationBars["Add Employee"].exists)

        deleteFourDigits(from: confirmation)
        confirmation.typeText("2468")
        save.tap()

        XCTAssertFalse(app.navigationBars["Add Employee"].waitForExistence(timeout: 10))
        let createdEmployee = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "PIN Confirmation Employee"))
            .firstMatch
        XCTAssertTrue(createdEmployee.waitForExistence(timeout: 15))
    }

    @MainActor
    func testAccountChangePINRejectsWrongCurrentPINInline() throws {
        openAccount()
        fillAccountPINForm(currentPIN: "9999", newPIN: "5678")
        element("account-change-pin-button").tap()

        let serviceError = element("account-pin-change-error")
        XCTAssertTrue(serviceError.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Account"].exists)
        XCTAssertFalse(element("account-pin-change-success").exists)
    }

    @MainActor
    func testAccountChangePINAcceptsCorrectCurrentPIN() throws {
        openAccount()
        fillAccountPINForm(currentPIN: "1234", newPIN: "5678")
        element("account-change-pin-button").tap()

        let success = element("account-pin-change-success")
        XCTAssertTrue(success.waitForExistence(timeout: 10))
        XCTAssertEqual(success.label, "Success: PIN changed successfully.")
        XCTAssertFalse(element("account-pin-change-error").exists)
    }

    // MARK: - Navigation

    @MainActor
    private func openEmployees() {
        let directPeopleTab = app.buttons["tab_people"]
        if directPeopleTab.waitForExistence(timeout: 20) {
            directPeopleTab.tap()
        } else if app.buttons["People"].waitForExistence(timeout: 3) {
            app.buttons["People"].tap()
        } else {
            let more = app.tabBars.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            more.tap()
            let people = app.buttons["People"]
            XCTAssertTrue(people.waitForExistence(timeout: 10))
            people.tap()
        }

        let employees = app.buttons["Employees"]
        if employees.waitForExistence(timeout: 15) {
            employees.tap()
        }
        XCTAssertTrue(app.buttons["Add employee"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func openAccount() {
        let userMenu = app.buttons["userMenuButton"].firstMatch
        XCTAssertTrue(userMenu.waitForExistence(timeout: 30))
        userMenu.tap()

        let accountLink = element("user-menu-account-link")
        XCTAssertTrue(accountLink.waitForExistence(timeout: 10))
        accountLink.tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func fillAccountPINForm(currentPIN: String, newPIN: String) {
        let current = element("account-current-pin-field")
        let replacement = element("account-new-pin-field")
        let confirmation = element("account-confirm-new-pin-field")
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        XCTAssertTrue(replacement.exists)
        XCTAssertTrue(confirmation.exists)

        current.tap()
        current.typeText(currentPIN)
        replacement.tap()
        replacement.typeText(newPIN)
        confirmation.tap()
        confirmation.typeText(newPIN)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func deleteFourDigits(from field: XCUIElement) {
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
    }
}
