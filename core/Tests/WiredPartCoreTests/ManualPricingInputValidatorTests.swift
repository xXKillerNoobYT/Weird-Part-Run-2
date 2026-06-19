import XCTest
@testable import WiredPartCore

final class ManualPricingInputValidatorTests: XCTestCase {
    func testInvalidManualCostIsRejectedInsteadOfCoercedToZero() {
        XCTAssertThrowsError(
            try ManualPricingInputValidator.parseMoney("abc", fieldName: "Cost")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cost must be a valid number. Keep your entered value and fix it before saving."
            )
        }
    }

    func testBlankManualCostIsRejectedInsteadOfCoercedToZero() {
        XCTAssertThrowsError(
            try ManualPricingInputValidator.parseMoney("   ", fieldName: "Cost")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cost is required. Keep your entered value and fix it before saving."
            )
        }
    }

    func testNegativeManualCostIsRejected() {
        XCTAssertThrowsError(
            try ManualPricingInputValidator.parseMoney("-1.25", fieldName: "Cost")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Cost must be zero or greater. Keep your entered value and fix it before saving."
            )
        }
    }

    func testValidManualMarkupAllowsZeroAndPositiveValues() throws {
        XCTAssertEqual(try ManualPricingInputValidator.parsePercent("0", fieldName: "Markup"), 0)
        XCTAssertEqual(try ManualPricingInputValidator.parsePercent("12.5", fieldName: "Markup"), 12.5)
    }
}
