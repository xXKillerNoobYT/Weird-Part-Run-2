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
        assertInvalidOdometerReading("12O34")
        assertInvalidOdometerReading("12,345")
        assertInvalidOdometerReading("-1")
    }

    func testOdometerParserRejectsNonPositiveMileage() throws {
        assertInvalidOdometerReading("0")
        assertInvalidOdometerReading("0000")
    }

    func testInvalidOdometerErrorShowsActionableValidationCopy() throws {
        XCTAssertEqual(
            PreTripInspectionInputValidator.ValidationError.invalidOdometerReading.errorDescription,
            "Enter the odometer as positive whole miles using digits only, or leave it blank."
        )
    }

    private func assertInvalidOdometerReading(
        _ rawValue: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try PreTripInspectionInputValidator.parseOdometerReading(rawValue),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? PreTripInspectionInputValidator.ValidationError,
                .invalidOdometerReading,
                file: file,
                line: line
            )
        }
    }

}
