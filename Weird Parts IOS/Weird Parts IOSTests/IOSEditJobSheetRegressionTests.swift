import XCTest

final class IOSEditJobSheetRegressionTests: XCTestCase {
    func testJobDetailSaveCanClearEditableOptionalFields() throws {
        let source = try Self.readEditJobSheetSource()

        XCTAssertTrue(
            source.contains("@State private var addressLine2: String"),
            "Edit job sheet should expose address line 2 so all editable site address fields can be cleared."
        )
        XCTAssertTrue(
            source.contains("TextField(\"Address Line 2\", text: $addressLine2)"),
            "Edit job sheet should include an address line 2 field in the customer/site section."
        )
        XCTAssertTrue(
            source.contains("customerName: clearableOptionalText(customerName)")
                && source.contains("addressLine1: clearableOptionalText(addressLine1)")
                && source.contains("addressLine2: clearableOptionalText(addressLine2)")
                && source.contains("notes: clearableOptionalText(notes)"),
            "Editable optional detail fields must pass an explicit empty string on save so clearing persists instead of being treated as leave-unchanged."
        )
        XCTAssertFalse(
            source.contains("customerName.isEmpty ? nil : customerName")
                || source.contains("addressLine1.isEmpty ? nil : addressLine1")
                || source.contains("notes.isEmpty ? nil : notes"),
            "Edit job sheet must not convert cleared optional fields to nil before updateJob because nil means leave unchanged."
        )
    }

    private static func readEditJobSheetSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Jobs")
            .appendingPathComponent("IOSEditJobSheet.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}