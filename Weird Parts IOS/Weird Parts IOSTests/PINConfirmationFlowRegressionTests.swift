import Foundation
import XCTest

final class PINConfirmationFlowRegressionTests: XCTestCase {
    func testAddEmployeeRequiresConfirmationBeforeCreateUser() throws {
        let source = try Self.readAppSource("Features/People/IOSEmployeesPage.swift")
        let addEmployee = try TestSourceSlicer.braceBalancedBody(
            after: "private struct AddEmployeeSheet",
            in: source
        )

        XCTAssertTrue(addEmployee.contains("SecureField(\"Confirm PIN\""))
        XCTAssertTrue(addEmployee.contains("PINConfirmationValidator.newPINError("))
        XCTAssertTrue(addEmployee.contains("confirmation: pinConfirmation"))
        XCTAssertTrue(addEmployee.contains("pin: normalizedPIN"))
    }

    func testAccountChangeUsesExistingAuthenticatedAppCorePath() throws {
        let source = try Self.readAppSource("Features/People/IOSAccountPage.swift")

        XCTAssertTrue(source.contains("SecureField(\"Current PIN\""))
        XCTAssertTrue(source.contains("SecureField(\"New PIN\""))
        XCTAssertTrue(source.contains("SecureField(\"Confirm New PIN\""))
        XCTAssertTrue(source.contains("PINConfirmationValidator.changePINError("))
        XCTAssertTrue(source.contains("let result = await appCore.changePin("))
        XCTAssertTrue(source.contains("oldPin: PINConfirmationValidator.normalize(currentPIN)"))
        XCTAssertTrue(source.contains("newPin: PINConfirmationValidator.normalize(newPIN)"))
    }

    func testUserProfileRowOpensAccountWithoutMovingOtherSettings() throws {
        let source = try Self.readAppSource("Navigation/UserMenuSheet.swift")
        let profileSection = try TestSourceSlicer.braceBalancedBody(
            after: "private var userProfileSection",
            in: source
        )

        XCTAssertTrue(profileSection.contains("NavigationLink"))
        XCTAssertTrue(profileSection.contains("IOSAccountPage()"))
        XCTAssertTrue(profileSection.contains("user-menu-account-link"))
    }

    private static func readAppSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
