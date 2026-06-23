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
            source.contains("customerName: changedOptionalText(customerName, original: job.customerName)")
                && source.contains("addressLine1: changedOptionalText(addressLine1, original: job.addressLine1)")
                && source.contains("addressLine2: changedOptionalText(addressLine2, original: job.addressLine2)")
                && source.contains("notes: changedOptionalText(notes, original: job.notes)"),
            "Editable optional detail fields should only send values that changed; an explicit empty string still persists when clearing a previously populated field."
        )
        XCTAssertTrue(
            source.contains("private func changedOptionalText(_ value: String, original: String?) -> String?")
                && source.contains("value == (original ?? \"\") ? nil : value"),
            "Unchanged originally-nil fields should not be converted to empty strings and written back on save."
        )
        XCTAssertTrue(
            source.contains("clearEstimatedHours: shouldClearDouble(estimatedHours, original: job.estimatedHours)")
                && source.contains("clearBudgetLimit: shouldClearDouble(budgetLimit, original: job.budgetLimit)")
                && source.contains("private func shouldClearDouble(_ value: String, original: Double?) -> Bool"),
            "Editable optional numeric fields should distinguish unchanged nil values from explicitly cleared populated values."
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