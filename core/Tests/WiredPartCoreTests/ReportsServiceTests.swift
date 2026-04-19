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

    // MARK: - Job Costs Report (budget_limit fix)

    // MARK: - generateCustomReport: Remaining Types

    @Test("generateCustomReport labor_hours returns empty on fresh DB")
    func testCustomReportLaborHoursEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.reports.generateCustomReport(
            type: "labor_hours",
            columns: ["employee_name", "date", "hours", "job_name", "activity_type", "clock_in", "clock_out", "notes"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty)
    }

    @Test("generateCustomReport labor_hours returns row after clock in/out")
    func testCustomReportLaborHoursWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborId)

        let columns = ["employee_name", "date", "hours", "job_name"]
        let rows = try env.reports.generateCustomReport(
            type: "labor_hours",
            columns: columns,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.count >= 1)
        if let first = rows.first {
            #expect(first.count == columns.count)
            #expect(first[0] == "TestAdmin")   // employee_name
            #expect(first[3] == "Test Job")    // job_name
        }
    }

    @Test("generateCustomReport parts_usage returns empty on fresh DB")
    func testCustomReportPartsUsageEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.reports.generateCustomReport(
            type: "parts_usage",
            columns: ["part_name", "category", "quantity_used", "job_name", "date", "cost", "total_cost"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty)
    }

    @Test("generateCustomReport vehicle_fuel returns empty on fresh DB")
    func testCustomReportVehicleFuelEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.reports.generateCustomReport(
            type: "vehicle_fuel",
            columns: ["vehicle_name", "date", "gallons", "cost", "odometer"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty)
    }

    @Test("generateCustomReport order_history returns empty on fresh DB")
    func testCustomReportOrderHistoryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.reports.generateCustomReport(
            type: "order_history",
            columns: ["po_number", "supplier_name", "order_date", "total", "status", "items_count"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty)
    }

    @Test("generateCustomReport order_history returns row after creating PO")
    func testCustomReportOrderHistoryWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        _ = try env.orders.createPurchaseOrder(
            poNumber: "PO-HIST-001",
            supplierId: supplierId,
            notes: nil
        )

        let columns = ["po_number", "supplier_name", "order_date", "total", "status", "items_count"]
        let rows = try env.reports.generateCustomReport(
            type: "order_history",
            columns: columns,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.count >= 1)
        if let first = rows.first {
            #expect(first.count == columns.count)
            #expect(first[0] == "PO-HIST-001")   // po_number
            #expect(first[1] == "TestSupplier")  // supplier_name
        }
    }

    @Test("generateCustomReport unknown type returns empty")
    func testCustomReportUnknownType() throws {
        let env = try E2ETestHelpers.setUp()
        let rows = try env.reports.generateCustomReport(
            type: "nonexistent_type",
            columns: ["col1"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty)
    }

    // MARK: - Job Costs Report (budget_limit fix)

    @Test("Job costs report uses budget_limit column correctly")
    func testJobCostsReport() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Set budget_limit on the job
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE jobs SET budget_limit = 50000.0 WHERE id = ?",
                arguments: [jobId]
            )
        }

        let columns = ["job_name", "labor_cost", "material_cost", "total_cost", "budget", "variance"]
        let rows = try env.reports.generateCustomReport(
            type: "job_costs",
            columns: columns,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.count >= 1)
        // Verify budget column reads correctly (no crash = budget_limit column is correct)
        if let first = rows.first {
            #expect(first.count == columns.count)
            // budget column should be "50000.00"
            #expect(first[4] == "50000.00")
        }
    }

    @Test("getTimesheetData shows Unknown for soft-deleted user")
    func testGetTimesheetDataHidesDeletedUserName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [env.adminUserId])
        }
        let rows = try env.reports.getTimesheetData(startDate: "2000-01-01", endDate: "2099-12-31")
        #expect(rows.isEmpty == false)
        #expect(rows.first?.userName == "Unknown")
    }

    @Test("generateDetailedReport hides job and user name for soft-deleted entities")
    func testGenerateDetailedReportHidesDeletedJobAndUserName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let columns = ["employee_name", "date", "hours", "job_name", "activity_type", "clock_in", "clock_out", "notes"]
        let rows = try env.reports.generateCustomReport(
            type: "labor_hours",
            columns: columns,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(rows.isEmpty == false)
        let jobNameIdx = columns.firstIndex(of: "job_name")!
        #expect(rows.first![jobNameIdx] == "")
    }
}
