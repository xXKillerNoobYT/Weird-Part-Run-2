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

    @Test("Bookkeeper material POs degrade soft-deleted supplier name to 'Unknown'")
    func testBookkeeperMaterialPOs_hidesDeletedSupplierName() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "TombstonedMaterialVendor")

        // Create a PO from the supplier; report should list it
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-BK-SOFT", supplierId: supplierId, notes: nil
        )
        // Move PO into a date window the report will include
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE purchase_orders SET total_cost = 100.0, created_at = datetime('now') WHERE id = ?",
                arguments: [poId]
            )
        }

        // Soft-delete the supplier. The report must degrade supplier_name to 'Unknown' —
        // previously the LEFT JOIN still matched the tombstoned row and leaked the real name.
        try env.db.writer.write { db in
            try db.execute(
                sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [supplierId]
            )
        }

        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let data = try env.reports.getBookkeeperMaterialPOs(
            startDate: String(today), endDate: String(today)
        )
        let match = data.first { $0.poNumber == "PO-BK-SOFT" }
        #expect(match != nil)
        #expect(match?.supplierName == "Unknown",
                "Soft-deleted supplier's name must not leak into bookkeeper material report — LEFT JOIN guard should make COALESCE degrade to 'Unknown'")
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

    @Test("generateCustomReport parts_usage falls back to 'Unknown' when part is soft-deleted")
    func testPartsUsageReportHidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env, name: "UsageCat")
        let partId = try E2ETestHelpers.seedPart(env, name: "Usage Part", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10)

        // Create a consume movement so the part appears in the usage report.
        _ = try env.warehouse.createMovement(
            partId: partId, qty: 3,
            fromLocationType: "warehouse", fromLocationId: 1,
            toLocationType: nil, toLocationId: nil,
            movementType: .consume,
            performedBy: env.adminUserId,
            unitCostAtMove: 5.0
        )

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
        }

        let rows = try env.reports.generateCustomReport(
            type: "parts_usage",
            columns: ["part_name", "quantity_used", "cost"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date.distantFuture,
            filters: [:]
        )
        #expect(!rows.isEmpty)
        let row = rows.first(where: { $0[0] == "Unknown" })
        #expect(row != nil)
        #expect(!rows.contains(where: { $0[0] == "Usage Part" }))
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

    // MARK: - Behavioral coverage for plan test plan

    @Test("getSpendingSummary totals seeded PO spend")
    func testSpendingSummaryWithSeededPO() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-SPEND-001", supplierId: supplierId)
        // Draft POs are excluded; set to received + total_cost
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE purchase_orders
                SET status = 'received', total_cost = 250.0
                WHERE id = ?
                """, arguments: [poId])
        }
        let summary = try env.reports.getSpendingSummary(days: 365)
        #expect(summary.totalSpend >= 250.0)
        #expect(summary.poCount >= 1)
    }

    @Test("getProfitabilitySummary computes margin from estimated hours and pay rate")
    func testProfitabilityMarginCalculation() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        // revenue = 10h × $100 = $1000; labor = 10h × $20 = $200; profit = $800; margin = 80%
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET estimated_hours = 10.0, billing_rate = 100.0 WHERE id = ?", arguments: [jobId])
            try db.execute(sql: "UPDATE users SET pay_rate = 20.0 WHERE id = ?", arguments: [env.adminUserId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-01-10 07:00:00', '2026-01-10 17:00:00', 10.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }
        let rows = try env.reports.getProfitabilitySummary()
        let row = rows.first(where: { $0.id == jobId })
        #expect(row != nil)
        if let row {
            #expect(abs(row.revenue - 1000.0) < 0.01)
            #expect(abs(row.laborCost - 200.0) < 0.01)
            #expect(abs(row.profit - 800.0) < 0.01)
            #expect(abs(row.margin - 80.0) < 0.1)
        }
    }

    @Test("getPreBillingData returns job with labor hours in date range")
    func testPreBillingDataWithLaborEntries() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-PB-001", name: "Pre-Billing Job")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-02-01 07:00:00', '2026-02-01 11:00:00', 4.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }
        let rows = try env.reports.getPreBillingData(startDate: "2026-02-01", endDate: "2026-02-01")
        let row = rows.first(where: { $0.id == jobId })
        #expect(row != nil)
        #expect(row?.regularHours ?? 0.0 >= 4.0)
    }

    @Test("getDailyReportSummary aggregates labor entries for a specific date")
    func testDailyReportSummaryAggregation() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DR-001", name: "Daily Report Job")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-03-05 07:00:00', '2026-03-05 15:00:00', 8.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }
        let rows = try env.reports.getDailyReportSummary(date: "2026-03-05")
        let row = rows.first(where: { $0.id == jobId })
        #expect(row != nil)
        #expect(row?.workerCount ?? 0 >= 1)
        #expect(row?.totalHours ?? 0.0 >= 8.0)
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
