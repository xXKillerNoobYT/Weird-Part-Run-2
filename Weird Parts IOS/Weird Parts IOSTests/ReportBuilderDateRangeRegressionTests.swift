import XCTest

/// Regression coverage for issue #1213: the custom Report Builder accepted an
/// end date earlier than the start date and ran the report, returning a
/// plausible-looking empty preview instead of a validation error.
final class ReportBuilderDateRangeRegressionTests: XCTestCase {
    func testDatePickersAreRangeConstrained() throws {
        let source = try Self.readReportBuilderSource()

        XCTAssertTrue(
            source.contains("DatePicker(\"Start Date\", selection: $startDate, in: ...endDate, displayedComponents: .date)"),
            "Start Date must be constrained to on/before the End Date."
        )
        XCTAssertTrue(
            source.contains("DatePicker(\"End Date\", selection: $endDate, in: startDate..., displayedComponents: .date)"),
            "End Date must be constrained to on/after the Start Date."
        )
    }

    func testGenerateIsBlockedForInvertedRanges() throws {
        let source = try Self.readReportBuilderSource()

        XCTAssertTrue(
            source.contains("private var hasValidDateRange: Bool { startDate <= endDate }"),
            "The builder needs an explicit date-range validity check."
        )
        XCTAssertTrue(
            source.contains(".disabled(isGenerating || !hasValidDateRange)"),
            "Generate Report must be disabled while the date range is inverted."
        )
        XCTAssertTrue(
            source.contains("guard hasValidDateRange else {"),
            "generateReport() must refuse inverted ranges as defense in depth."
        )
        XCTAssertTrue(
            source.contains("Start date must be on or before the end date."),
            "The user needs an actionable validation message for inverted ranges."
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
