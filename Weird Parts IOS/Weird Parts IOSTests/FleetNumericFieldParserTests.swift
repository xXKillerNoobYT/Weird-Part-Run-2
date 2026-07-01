import XCTest
@testable import Weird_Parts

final class FleetNumericFieldParserTests: XCTestCase {
    func testOptionalWholeNumberAllowsBlankAsNil() throws {
        XCTAssertNil(try FleetNumericFieldParser.optionalWholeNumber("", fieldName: "Odometer"))
        XCTAssertNil(try FleetNumericFieldParser.optionalWholeNumber("   \n", fieldName: "Year"))
    }

    func testOptionalWholeNumberParsesTrimmedDigits() throws {
        XCTAssertEqual(try FleetNumericFieldParser.optionalWholeNumber(" 12345 ", fieldName: "Odometer"), 12345)
        XCTAssertEqual(try FleetNumericFieldParser.optionalWholeNumber("2024", fieldName: "Year"), 2024)
    }

    func testOptionalWholeNumberRejectsMalformedNonEmptyText() throws {
        XCTAssertThrowsError(try FleetNumericFieldParser.optionalWholeNumber("12O34", fieldName: "Odometer")) { error in
            XCTAssertEqual(error.localizedDescription, "Odometer must be a whole number.")
        }

        XCTAssertThrowsError(try FleetNumericFieldParser.optionalWholeNumber("12,345", fieldName: "Odometer"))
        XCTAssertThrowsError(try FleetNumericFieldParser.optionalWholeNumber("2024x", fieldName: "Year"))
    }
}
