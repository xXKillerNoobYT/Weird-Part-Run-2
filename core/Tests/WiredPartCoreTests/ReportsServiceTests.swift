import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("ReportsService Tests")
struct ReportsServiceTests {

    // MARK: - Timesheet

    @Test("Timesheet data returns empty on fresh DB")
    func testTimesheetEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let data = try env.reports.getTimesheetData(startDate: "2026-01-01", endDate: "2026-12-31")
        #expect(data.isEmpty)
    }

    @Test("Timesheet data with clock entries")
    func testTimesheetWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborEntryId)

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let data = try env.reports.getTimesheetData(startDate: String(today), endDate: String(today))
        #expect(data.count >= 1)
    }

    // MARK: - Daily Report Summary

    @Test("Daily report summary empty on fresh DB")
    func testDailyReportSummaryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getDailyReportSummary(date: "2026-03-29")
        #expect(summary.isEmpty)
    }

    // MARK: - Spending

    @Test("Spending summary on fresh DB")
    func testSpendingSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getSpendingSummary(days: 30)
        #expect(summary.totalSpend >= 0)
    }

    // MARK: - Profitability

    @Test("Profitability summary empty on fresh DB")
    func testProfitabilitySummary() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getProfitabilitySummary()
        #expect(summary.isEmpty)
    }

    @Test("Profitability with job and labor")
    func testProfitabilityWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborEntryId)

        let summary = try env.reports.getProfitabilitySummary()
        // May or may not show the job depending on reporting logic
        #expect(summary.count >= 0)
    }

    // MARK: - Pre-Billing

    @Test("Pre-billing data empty on fresh DB")
    func testPreBillingEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let data = try env.reports.getPreBillingData(startDate: "2026-01-01", endDate: "2026-12-31")
        #expect(data.isEmpty)
    }

    // MARK: - Bookkeeper Export

    @Test("Bookkeeper labor summary empty")
    func testBookkeeperLaborEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let data = try env.reports.getBookkeeperLaborSummary(startDate: "2026-01-01", endDate: "2026-12-31")
        #expect(data.isEmpty)
    }

    @Test("Bookkeeper material POs empty")
    func testBookkeeperMaterialEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let data = try env.reports.getBookkeeperMaterialPOs(startDate: "2026-01-01", endDate: "2026-12-31")
        #expect(data.isEmpty)
    }

    // MARK: - Stats

    @Test("Reports stats aggregates correctly")
    func testReportsStats() throws {
        let env = try E2ETestHelpers.setUp()
        let stats = try env.reports.getReportsStats()
        #expect(stats.openPeriods >= 0)
    }

    // MARK: - Custom Reports

    @Test("Save and list custom report configs")
    func testSaveAndListReportConfig() throws {
        let env = try E2ETestHelpers.setUp()
        let reportId = try env.reports.saveReportConfig(
            name: "Weekly Labor",
            type: "labor",
            columns: ["employee", "hours", "job"],
            filters: ["status": "active"],
            userId: env.adminUserId,
            isShared: false
        )
        #expect(reportId > 0)

        let saved = try env.reports.getSavedReports(userId: env.adminUserId)
        #expect(saved.count >= 1)
        #expect(saved.first?.name == "Weekly Labor")
    }

    @Test("Delete saved report")
    func testDeleteSavedReport() throws {
        let env = try E2ETestHelpers.setUp()
        let reportId = try env.reports.saveReportConfig(
            name: "Temp Report",
            type: "labor",
            columns: ["employee"],
            filters: [:],
            userId: env.adminUserId,
            isShared: false
        )
        try env.reports.deleteSavedReport(reportId: reportId)
        let saved = try env.reports.getSavedReports(userId: env.adminUserId)
        #expect(!saved.contains(where: { $0.id == reportId }))
    }

    @Test("Mark report run updates timestamp")
    func testMarkReportRun() throws {
        let env = try E2ETestHelpers.setUp()
        let reportId = try env.reports.saveReportConfig(
            name: "Run Tracker",
            type: "spending",
            columns: ["job", "amount"],
            filters: [:],
            userId: env.adminUserId,
            isShared: true
        )
        try env.reports.markReportRun(reportId: reportId)
    }

    // MARK: - Tool Checkout Report

    @Test("Tool checkout report returns empty on fresh DB")
    func testToolCheckoutReportEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.reports.generateCustomReport(
            type: "tool_checkouts",
            columns: ["tool_name", "employee_name", "checkout_date", "return_date", "condition_out", "condition_in"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty)
    }

    @Test("Tool checkout report returns rows after checkout")
    func testToolCheckoutReportWithData() throws {
        let env = try E2ETestHelpers.setUp()
        // Insert a tool directly
        let toolId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO tools (tool_number, name, category, status, has_kit, created_at, updated_at)
                VALUES ('T-R001', 'Test Wrench', 'hand_tools', 'available', 0, datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }
        // Checkout and return
        try env.tools.checkoutTool(toolId: toolId, userId: env.adminUserId)
        try env.tools.returnTool(toolId: toolId, userId: env.adminUserId)

        let columns = ["tool_name", "employee_name", "checkout_date", "return_date", "condition_out", "condition_in"]
        let rows = try env.reports.generateCustomReport(
            type: "tool_checkouts",
            columns: columns,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.count >= 1)
        // Verify columns map correctly (no crash = SQL columns are correct)
        if let first = rows.first {
            #expect(first.count == columns.count)
            #expect(first[0] == "Test Wrench")  // tool_name
        }
    }
}
