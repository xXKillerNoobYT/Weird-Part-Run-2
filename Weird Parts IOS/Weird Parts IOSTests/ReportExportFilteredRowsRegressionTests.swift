import XCTest

/// Regression coverage for issue #1243: searchable report pages rendered a
/// filtered visible list but exported the unfiltered backing collection, so
/// a search-narrowed PDF/CSV could include employees/jobs hidden on screen.
///
/// Every page below must export the same filtered set its list displays.
final class ReportExportFilteredRowsRegressionTests: XCTestCase {
    func testLaborOverviewExportsFilteredRows() throws {
        let source = try Self.readReportSource("IOSLaborOverviewPage")
        XCTAssertTrue(
            source.contains("rows: filteredTimesheetRows.map"),
            "Labor Overview must export the search-filtered rows the list displays."
        )
        XCTAssertFalse(
            source.contains("rows: timesheetRows.map"),
            "Labor Overview must not export the unfiltered backing collection."
        )
    }

    func testDailySummaryExportsFilteredRows() throws {
        let source = try Self.readReportSource("IOSDailyReportsSummaryPage")
        XCTAssertTrue(
            source.contains("rows: filteredRows.map"),
            "Daily Summary must export the search-filtered rows the list displays."
        )
        XCTAssertFalse(
            source.contains("rows: rows.map"),
            "Daily Summary must not export the unfiltered backing collection."
        )
    }

    func testTimesheetsExportsFilteredSegments() throws {
        let source = try Self.readReportSource("IOSTimesheetsPage")
        XCTAssertTrue(
            source.contains("rows: filteredSegments.map"),
            "Timesheets must export segments filtered by the same employee search as the visible list."
        )
        XCTAssertFalse(
            source.contains("rows: segments.map"),
            "Timesheets must not export the unfiltered segment collection."
        )
        // The segment filter must key off the same field the row filter uses.
        XCTAssertTrue(
            source.contains("private var filteredSegments: [ReportsService.TimesheetSegmentRow]"),
            "Timesheets needs a filteredSegments helper mirroring filteredRows."
        )
    }

    func testProfitabilityExportsFilteredRows() throws {
        let source = try Self.readReportSource("IOSProfitabilityPage")
        XCTAssertTrue(
            source.contains("rows: filteredRows.map"),
            "Profitability must export the search-filtered rows the list displays."
        )
        XCTAssertFalse(
            source.contains("rows: rows.map"),
            "Profitability must not export the unfiltered backing collection."
        )
    }

    func testExportBehaviorIsDocumentedInHelpCopy() throws {
        for page in ["IOSLaborOverviewPage", "IOSDailyReportsSummaryPage",
                     "IOSTimesheetsPage", "IOSProfitabilityPage"] {
            let source = try Self.readReportSource(page)
            XCTAssertTrue(
                source.contains("(\"Exporting\","),
                "\(page) help copy should document that exports match the visible filtered rows."
            )
        }
    }

    private static func readReportSource(
        _ pageName: String,
        file: StaticString = #filePath
    ) throws -> String {
        let projectRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent("Features")
            .appendingPathComponent("Reports")
            .appendingPathComponent("\(pageName).swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
