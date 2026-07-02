import XCTest

/// Regression coverage for issue #1213: the custom Report Builder accepted an
/// end date earlier than the start date and ran the report, returning a
/// plausible-looking empty preview instead of a validation error.
final class ReportBuilderDateRangeRegressionTests: XCTestCase {
    func testDatePickersAreRangeConstrained() throws {
        let source = try Self.readReportBuilderSource()

        XCTAssertTrue(
            source.contains("DatePicker(\"Start Date\", selection: $startDate, in: startPickerLimit, displayedComponents: .date)"),
            "Start Date must be constrained to on/before the End Date's calendar day."
        )
        XCTAssertTrue(
            source.contains("DatePicker(\"End Date\", selection: $endDate, in: endPickerLimit, displayedComponents: .date)"),
            "End Date must be constrained to on/after the Start Date's calendar day."
        )
    }

    func testGenerateIsBlockedForInvertedRanges() throws {
        let source = try Self.readReportBuilderSource()

        // Day-granularity comparison matches generateCustomReport's
        // yyyy-MM-dd truncation — a same-calendar-day range with a later
        // start time-of-day must NOT be treated as inverted.
        XCTAssertTrue(
            source.contains("Calendar.current.startOfDay(for: startDate) <= Calendar.current.startOfDay(for: endDate)"),
            "The date-range validity check must compare at day granularity, matching the service's yyyy-MM-dd truncation."
        )
        XCTAssertTrue(
            source.contains(".disabled(isGenerating || !hasValidDateRange)"),
            "Generate Report must be disabled while the date range is inverted."
        )
        XCTAssertTrue(
            source.contains("guard hasValidDateRange else {"),
            "generateReport() must refuse inverted ranges as defense in depth."
        )
    }

    func testInvertedRangeShowsVisibleValidationLabel() throws {
        let source = try Self.readReportBuilderSource()

        // Assert the *visible* label layer specifically — the generateReport()
        // guard message alone must not satisfy this test.
        XCTAssertTrue(
            source.contains("Label(\"Start date must be on or before the end date.\", systemImage: \"exclamationmark.triangle\")"),
            "The filters step needs a visible validation label for inverted ranges."
        )
        XCTAssertTrue(
            source.contains(".accessibilityIdentifier(\"reportBuilderDateRangeError\")"),
            "The validation label must keep its accessibility identifier for UI tests."
        )
        XCTAssertTrue(
            source.contains("if !hasValidDateRange {"),
            "The validation label must be gated on the shared date-range validity check."
        )
    }

    private static func readReportBuilderSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Reports")
            .appendingPathComponent("ReportBuilderView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
