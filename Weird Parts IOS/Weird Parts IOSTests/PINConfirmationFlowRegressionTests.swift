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

        let errorReset = try XCTUnwrap(addEmployee.range(of: "errorMessage = nil"))
        let pinReset = try XCTUnwrap(addEmployee.range(of: "pinValidationMessage = nil"))
        let authGuard = try XCTUnwrap(addEmployee.range(of: "guard let authService"))
        XCTAssertLessThan(errorReset.lowerBound, authGuard.lowerBound)
        XCTAssertLessThan(pinReset.lowerBound, authGuard.lowerBound)
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

        let submit = try TestSourceSlicer.braceBalancedBody(
            after: "private func submitPINChange",
            in: source
        )
        let validationReset = try XCTUnwrap(submit.range(of: "validationMessage = nil"))
        let serviceReset = try XCTUnwrap(submit.range(of: "serviceMessage = nil"))
        let successReset = try XCTUnwrap(submit.range(of: "successMessage = nil"))
        let userGuard = try XCTUnwrap(submit.range(of: "guard let userId"))
        XCTAssertLessThan(validationReset.lowerBound, userGuard.lowerBound)
        XCTAssertLessThan(serviceReset.lowerBound, userGuard.lowerBound)
        XCTAssertLessThan(successReset.lowerBound, userGuard.lowerBound)
    }

    func testPINPlanDescribesTheAllowedLengthAsARange() throws {
        let testFileURL = URL(fileURLWithPath: "\(#filePath)")
        let repositoryRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
            .deletingLastPathComponent() // repository root
        let planURL = repositoryRoot.appendingPathComponent("docs/plans/people-pin-confirmation.md")
        let plan = try String(contentsOf: planURL, encoding: .utf8)

        XCTAssertTrue(plan.contains("It contains 4–8 digits."))
        XCTAssertFalse(plan.contains("It contains exactly 4–8 digits."))
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
