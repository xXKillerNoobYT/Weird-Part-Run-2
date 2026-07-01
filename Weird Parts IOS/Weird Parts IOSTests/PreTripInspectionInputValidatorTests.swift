import XCTest
@testable import Weird_Parts

@MainActor
final class PreTripInspectionInputValidatorTests: XCTestCase {
    func testOdometerParserAllowsBlankAsMissing() throws {
        XCTAssertNil(try PreTripInspectionInputValidator.parseOdometerReading(""))
        XCTAssertNil(try PreTripInspectionInputValidator.parseOdometerReading("  \n"))
    }

    func testOdometerParserAcceptsWholeDigitMiles() throws {
        XCTAssertEqual(try PreTripInspectionInputValidator.parseOdometerReading("12345"), 12345)
        XCTAssertEqual(try PreTripInspectionInputValidator.parseOdometerReading(" 0012 "), 12)
    }

    func testOdometerParserRejectsMalformedNonEmptyInput() throws {
        XCTAssertThrowsError(try PreTripInspectionInputValidator.parseOdometerReading("12O34"))
        XCTAssertThrowsError(try PreTripInspectionInputValidator.parseOdometerReading("12,345"))
        XCTAssertThrowsError(try PreTripInspectionInputValidator.parseOdometerReading("-1"))
        XCTAssertThrowsError(try PreTripInspectionInputValidator.parseOdometerReading("0"))
        XCTAssertThrowsError(try PreTripInspectionInputValidator.parseOdometerReading("0000"))
    }

    func testInvalidOdometerErrorShowsActionableValidationCopy() throws {
        XCTAssertEqual(
            PreTripInspectionInputValidator.ValidationError.invalidOdometerReading.localizedDescription,
            "Enter the odometer as positive whole miles using digits only, or leave it blank."
        )
    }
}
