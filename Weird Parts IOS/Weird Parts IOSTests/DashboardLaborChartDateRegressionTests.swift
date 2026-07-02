import XCTest

/// Regression coverage for issue #1247: the Dashboard labor-hours chart
/// converted any unparseable `LaborChartRow.dateString` into `Date()`,
/// silently mislabeling malformed historical rows as today.
final class DashboardLaborChartDateRegressionTests: XCTestCase {
    func testLaborChartSkipsMalformedDatesInsteadOfDefaultingToToday() throws {
        let source = try Self.readDashboardViewSource()

        XCTAssertFalse(
            source.contains("date(from: row.dateString) ?? Date()"),
            "Labor chart rows must not fall back to Date() — that displays malformed rows as today (issue #1247)."
        )
        XCTAssertTrue(
            source.contains("let laborDays = laborRows.compactMap { row -> LaborDayData? in"),
            "Labor chart mapping should compactMap so malformed rows are skipped, not remapped."
        )
        XCTAssertTrue(
            source.contains("guard let date = Formatters.localDateFormatter.date(from: row.dateString) else"),
            "Labor chart mapping should guard on date parsing and bail out for malformed rows."
        )
        XCTAssertTrue(
            source.contains("Skipping labor chart row with malformed date"),
            "Skipped malformed rows should be logged so bad data stays diagnosable."
        )
    }

    private static func readDashboardViewSource(
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Dashboard")
            .appendingPathComponent("DashboardView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
