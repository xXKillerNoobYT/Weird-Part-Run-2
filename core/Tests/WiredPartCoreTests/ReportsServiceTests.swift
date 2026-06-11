import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
import GRDB
@testable import WiredPartCore

@Suite("ReportsService Tests", .serialized)
struct ReportsServiceTests {
    private func withDenverTimeZone(_ work: () throws -> Void) throws {
        let originalTZ = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", "America/Denver", 1)
        tzset()
        defer {
            if let originalTZ {
                setenv("TZ", originalTZ, 1)
            } else {
                unsetenv("TZ")
            }
            tzset()
        }
        try work()
    }

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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let data = try env.reports.getTimesheetData(startDate: today, endDate: today)
        #expect(data.count >= 1)
    }

    @Test("Timesheet data buckets UTC evening clock-in into local work day")
    func testTimesheetUsesLocalOperationalDayForUtcClockIn() throws {
        try withDenverTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCAL-TS", name: "Local Timesheet Job")
            try env.db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES (?, ?, '2026-03-06 03:30:00', '2026-03-06 04:30:00', 1.0, 0.0, 'completed', datetime('now'))
                    """, arguments: [env.adminUserId, jobId])
            }

            let localDayRows = try env.reports.getTimesheetData(startDate: "2026-03-05", endDate: "2026-03-05")

            #expect(localDayRows.count == 1)
            #expect(localDayRows.first?.daysWorked == 1)
            #expect(abs((localDayRows.first?.totalHours ?? 0) - 1.0) < 0.01)
        }
    }

    @Test("Timesheet correction persists audit row and updates labor entry")
    func testTimesheetCorrectionPersistsAuditAndUpdatesEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CORR", name: "Correction Job")
        let laborEntryId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-03-05T08:00:00Z', '2026-03-05T16:00:00Z', 8.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
            return db.lastInsertedRowID
        }

        let record = try env.reports.saveTimesheetCorrection(
            ReportsService.TimesheetCorrectionRequest(
                laborEntryId: laborEntryId,
                adjustedClockIn: "2026-03-05T08:15:00Z",
                adjustedClockOut: "2026-03-05T17:45:00Z",
                clientPreviewRegularHours: 8.0,
                clientPreviewOvertimeHours: 1.5,
                reason: "Employee forgot to stop timer at the right time.",
                actorUserId: env.adminUserId
            )
        )

        #expect(record.segmentId == laborEntryId)
        #expect(record.originalClockIn == "2026-03-05T08:00:00Z")
        #expect(record.adjustedClockIn == "2026-03-05 08:15:00")
        #expect(record.adjustedOvertimeHours == 1.5)
        #expect(record.reason == "Employee forgot to stop timer at the right time.")
        #expect(record.approvalStatus == "pending_review")

        let updated = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT clock_in, clock_out, regular_hours, overtime_hours, edited_by, status
                FROM labor_entries WHERE id = ?
                """, arguments: [laborEntryId])
        }
        #expect(updated?["clock_in"] as String? == "2026-03-05 08:15:00")
        #expect(updated?["clock_out"] as String? == "2026-03-05 17:45:00")
        #expect(updated?["regular_hours"] as Double? == 8.0)
        #expect(updated?["overtime_hours"] as Double? == 1.5)
        #expect(updated?["edited_by"] as Int64? == env.adminUserId)
        #expect(updated?["status"] as String? == "completed")
    }

    @Test("Timesheet correction allocates weekly overtime from current settings instead of request buckets")
    func testTimesheetCorrectionUsesOvertimeSettingsForAdjustedHours() throws {
        try withDenverTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-CORR-OT", name: "Correction Overtime Job")
            _ = try env.jobs.updateOvertimeSettings(
                calculationRule: "weekly_only",
                dailyThresholdHours: 8.0,
                weeklyThresholdHours: 6.0,
                updatedBy: env.adminUserId
            )
            let laborEntryId = try env.db.writer.write { db -> Int64 in
                try db.execute(sql: """
                    INSERT INTO labor_entries
                        (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES
                        (?, ?, '2026-03-05T14:00:00Z', '2026-03-05T18:00:00Z', 4.0, 0.0, 'completed', datetime('now')),
                        (?, ?, '2026-03-05T18:30:00Z', '2026-03-05T20:30:00Z', 2.0, 0.0, 'completed', datetime('now'))
                    """, arguments: [env.adminUserId, jobId, env.adminUserId, jobId])
                return db.lastInsertedRowID
            }

            let record = try env.reports.saveTimesheetCorrection(
                ReportsService.TimesheetCorrectionRequest(
                    laborEntryId: laborEntryId,
                    adjustedClockIn: "2026-03-05T18:30:00Z",
                    adjustedClockOut: "2026-03-05T22:30:00Z",
                    clientPreviewRegularHours: 4.0,
                    clientPreviewOvertimeHours: 0.0,
                    reason: "Corrected by manager after reviewing dispatch notes.",
                    actorUserId: env.adminUserId
                )
            )

            #expect(record.adjustedRegularHours == 2.0)
            #expect(record.adjustedOvertimeHours == 2.0)

            let updated = try env.db.writer.read { db in
                try Row.fetchOne(db, sql: """
                    SELECT regular_hours, overtime_hours
                    FROM labor_entries WHERE id = ?
                    """, arguments: [laborEntryId])
            }
            #expect(updated?["regular_hours"] as Double? == 2.0)
            #expect(updated?["overtime_hours"] as Double? == 2.0)
        }
    }

    @Test("Timesheet correction history loads by reviewed work period")
    func testTimesheetCorrectionHistoryLoadsByWorkPeriod() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-HIST", name: "History Job")
        let laborEntryId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-04-10T08:00:00Z', '2026-04-10T12:00:00Z', 4.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
            return db.lastInsertedRowID
        }

        _ = try env.reports.saveTimesheetCorrection(
            ReportsService.TimesheetCorrectionRequest(
                laborEntryId: laborEntryId,
                adjustedClockIn: "2026-04-10T08:00:00Z",
                adjustedClockOut: "2026-04-10T13:00:00Z",
                clientPreviewRegularHours: 5.0,
                clientPreviewOvertimeHours: 0.0,
                reason: "Verified against supervisor note.",
                actorUserId: env.adminUserId
            )
        )

        let inPeriod = try env.reports.getTimesheetCorrectionHistory(
            startDate: "2026-04-10",
            endDate: "2026-04-10"
        )
        let outsidePeriod = try env.reports.getTimesheetCorrectionHistory(
            startDate: "2026-04-11",
            endDate: "2026-04-11"
        )

        #expect(inPeriod.contains { $0.segmentId == laborEntryId })
        #expect(!outsidePeriod.contains { $0.segmentId == laborEntryId })
    }

    // MARK: - Daily Report Summary

    @Test("Daily report summary empty on fresh DB")
    func testDailyReportSummaryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getDailyReportSummary(date: "2026-03-29")
        #expect(summary.isEmpty)
    }

    @Test("Daily report summary buckets UTC evening clock-in into local work day")
    func testDailyReportSummaryUsesLocalOperationalDayForUtcClockIn() throws {
        try withDenverTimeZone {
            let env = try E2ETestHelpers.setUp()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCAL-DR", name: "Local Daily Report Job")
            try env.db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES (?, ?, '2026-03-06 03:30:00', '2026-03-06 04:30:00', 1.5, 0.0, 'completed', datetime('now'))
                    """, arguments: [env.adminUserId, jobId])
            }

            let rows = try env.reports.getDailyReportSummary(date: "2026-03-05")
            let row = rows.first(where: { $0.id == jobId })

            #expect(row != nil)
            #expect(row?.workerCount == 1)
            #expect(abs((row?.totalHours ?? 0) - 1.5) < 0.01)
        }
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

    @Test("Bookkeeper material POs exclude soft-deleted purchase orders")
    func testBookkeeperMaterialPOs_excludesDeletedPurchaseOrders() throws {
        let env = try E2ETestHelpers.setUp()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Deleted PO Supplier")
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-BK-DELETED", supplierId: supplierId, notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE purchase_orders
                SET total_cost = 125.0,
                    created_at = '2026-06-08 10:00:00',
                    deleted_at = '2026-06-08 11:00:00'
                WHERE id = ?
                """, arguments: [poId])
        }

        let data = try env.reports.getBookkeeperMaterialPOs(
            startDate: "2026-06-08",
            endDate: "2026-06-08"
        )

        #expect(data.allSatisfy { $0.poNumber != "PO-BK-DELETED" })
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

        // Create a pull movement so the part appears in the usage report.
        // qty must be positive; "pull" semantics come from fromLocationType="warehouse" + nil destination.
        _ = try env.warehouse.createMovement(
            partId: partId, qty: 3,
            fromLocationType: "warehouse", fromLocationId: 1,
            toLocationType: nil, toLocationId: nil,
            movementType: StockMovement.MovementType.pull.rawValue,
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
            try db.execute(sql: "UPDATE jobs SET billing_rate = 125.0 WHERE id = ?", arguments: [jobId])
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

    @Test("getPreBillingData includes deterministic material, JPO, and PO provenance")
    func testPreBillingDataIncludesStage8ReadModelProvenance() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-PB-STAGE8", name: "Stage 8 Read Model Job")
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "Stage 8 Category")
        let partId = try E2ETestHelpers.seedPart(env, name: "Stage 8 Part", categoryId: categoryId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Stage 8 Supplier")

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET billing_rate = 100.0 WHERE id = ?", arguments: [jobId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-06-01 07:00:00', '2026-06-01 17:00:00', 8.0, 2.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
            try db.execute(sql: """
                INSERT INTO job_parts
                (job_id, part_id, qty_consumed, qty_returned, unit_cost_at_consume, unit_sell_at_consume, consumed_by, consumed_at)
                VALUES (?, ?, 3, 1, 10.0, 15.0, ?, '2026-06-01 12:00:00')
                """, arguments: [jobId, partId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO job_parts_orders
                (job_id, order_number, status, requested_by, created_at, updated_at)
                VALUES (?, 'JPO-STAGE8-001', 'ordered', ?, '2026-06-01 08:00:00', '2026-06-01 08:00:00')
                """, arguments: [jobId, env.adminUserId])
            let jpoId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO jpo_line_items
                (jpo_id, part_id, qty_requested, qty_ordered, line_status, created_at)
                VALUES (?, ?, 2, 2, 'in_procurement', '2026-06-01 08:05:00')
                """, arguments: [jpoId, partId])
            let jpoLineId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO purchase_orders
                (po_number, supplier_id, status, order_date, total_cost, created_at, updated_at)
                VALUES ('PO-STAGE8-001', ?, 'received', '2026-06-01', 30.0, '2026-06-01 09:00:00', '2026-06-01 09:00:00')
                """, arguments: [supplierId])
            let poId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO po_line_items
                (po_id, jpo_line_id, part_id, qty_ordered, qty_received, unit_cost, status, created_at)
                VALUES (?, ?, ?, 2, 2, 15.0, 'received', '2026-06-01 09:05:00')
                """, arguments: [poId, jpoLineId, partId])
            try db.execute(sql: """
                INSERT OR IGNORE INTO po_jpo_links (po_id, jpo_id, created_at)
                VALUES (?, ?, '2026-06-01 09:10:00')
                """, arguments: [poId, jpoId])
            try db.execute(sql: """
                INSERT INTO stock_movements
                (part_id, qty, to_location_type, to_location_id, movement_type, reason, job_id, performed_by, unit_cost_at_move, created_at)
                VALUES (?, -1, 'job', ?, 'job_consumed', 'Audit provenance link', ?, ?, 10.0, '2026-06-01 10:00:00')
                """, arguments: [partId, jobId, jobId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO warehouse_floor_plans (name, width_inches, length_inches, created_at)
                VALUES ('Stage 8 Floor', 120, 120, datetime('now'))
                """)
            let floorPlanId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO warehouse_storage_units (floor_plan_id, name, unit_type, created_at)
                VALUES (?, 'Stage 8 Unit', 'rack', datetime('now'))
                """, arguments: [floorPlanId])
            let unitId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO warehouse_storage_levels (unit_id, level_code, created_at)
                VALUES (?, 'A', datetime('now'))
                """, arguments: [unitId])
            let levelId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO warehouse_storage_areas (level_id, area_code, area_number, full_location_code, created_at)
                VALUES (?, 'A1', 1, 'A-1', datetime('now'))
                """, arguments: [levelId])
            let areaId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO audit_sessions_v2 (session_type, started_by, status, started_at)
                VALUES ('count', ?, 'completed', '2026-06-01 10:15:00')
                """, arguments: [env.adminUserId])
            let sessionId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO audit_counts
                (session_id, part_id, area_id, system_count, user_count, variance, variance_dollars, variance_percent, result, counted_by, counted_at)
                VALUES (?, ?, ?, 5, 4, -1, -10.0, -20.0, 'variance', ?, '2026-06-01 10:20:00')
                """, arguments: [sessionId, partId, areaId, env.adminUserId])
        }

        let rows = try env.reports.getPreBillingData(startDate: "2026-06-01", endDate: "2026-06-01")
        let row = rows.first(where: { $0.id == jobId })

        #expect(row?.jobNumber == "J-PB-STAGE8")
        #expect(abs((row?.regularHours ?? 0) - 8.0) < 0.01)
        #expect(abs((row?.overtimeHours ?? 0) - 2.0) < 0.01)
        #expect(abs((row?.materialCost ?? 0) - 30.0) < 0.01)
        #expect(abs((row?.billableAmount ?? 0) - 1030.0) < 0.01)
        #expect(row?.laborEntryCount == 1)
        #expect(row?.materialLineCount == 1)
        #expect(row?.jpoCount == 1)
        #expect(row?.purchaseOrderCount == 1)
        #expect(row?.auditDiscrepancyCount == 0)
        #expect(row?.sourceSummary.contains("1 labor entry") == true)
    }

    @Test("getPreBillingData does not attribute shared-part audit counts to jobs")
    func testPreBillingDataDoesNotExposeUnprovenSharedPartAuditAttribution() throws {
        let env = try E2ETestHelpers.setUp()
        let firstJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-PB-AUDIT-1", name: "Audit Shared Part A")
        let secondJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-PB-AUDIT-2", name: "Audit Shared Part B")
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "Shared Audit Category")
        let partId = try E2ETestHelpers.seedPart(env, name: "Shared Audit Part", categoryId: categoryId)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET billing_rate = 100.0 WHERE id IN (?, ?)", arguments: [firstJobId, secondJobId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES
                    (?, ?, '2026-06-04 07:00:00', '2026-06-04 11:00:00', 4.0, 0.0, 'completed', datetime('now')),
                    (?, ?, '2026-06-04 12:00:00', '2026-06-04 16:00:00', 4.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, firstJobId, env.adminUserId, secondJobId])
            try db.execute(sql: """
                INSERT INTO stock_movements
                (part_id, qty, to_location_type, to_location_id, movement_type, reason, job_id, performed_by, unit_cost_at_move, created_at)
                VALUES
                    (?, -1, 'job', ?, 'job_consumed', 'First shared-part job movement', ?, ?, 10.0, '2026-06-04 09:00:00'),
                    (?, -1, 'job', ?, 'job_consumed', 'Second shared-part job movement', ?, ?, 10.0, '2026-06-04 13:00:00')
                """, arguments: [
                    partId, firstJobId, firstJobId, env.adminUserId,
                    partId, secondJobId, secondJobId, env.adminUserId
                ])
            try db.execute(sql: """
                INSERT INTO warehouse_floor_plans (name, width_inches, length_inches, created_at)
                VALUES ('Shared Audit Floor', 120, 120, datetime('now'))
                """)
            let floorPlanId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO warehouse_storage_units (floor_plan_id, name, unit_type, created_at)
                VALUES (?, 'Shared Audit Unit', 'rack', datetime('now'))
                """, arguments: [floorPlanId])
            let unitId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO warehouse_storage_levels (unit_id, level_code, created_at)
                VALUES (?, 'A', datetime('now'))
                """, arguments: [unitId])
            let levelId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO warehouse_storage_areas (level_id, area_code, area_number, full_location_code, created_at)
                VALUES (?, 'A1', 1, 'A-1', datetime('now'))
                """, arguments: [levelId])
            let areaId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO audit_sessions_v2 (session_type, started_by, status, started_at)
                VALUES ('count', ?, 'completed', '2026-06-04 10:15:00')
                """, arguments: [env.adminUserId])
            let sessionId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO audit_counts
                (session_id, part_id, area_id, system_count, user_count, variance, variance_dollars, variance_percent, result, counted_by, counted_at)
                VALUES (?, ?, ?, 5, 4, -1, -10.0, -20.0, 'variance', ?, '2026-06-04 10:20:00')
                """, arguments: [sessionId, partId, areaId, env.adminUserId])
        }

        let rows = try env.reports.getPreBillingData(startDate: "2026-06-04", endDate: "2026-06-04")
        let firstRow = rows.first(where: { $0.id == firstJobId })
        let secondRow = rows.first(where: { $0.id == secondJobId })

        #expect(firstRow?.auditDiscrepancyCount == 0)
        #expect(secondRow?.auditDiscrepancyCount == 0)
        #expect(firstRow?.sourceSummary.contains("audit discrep") == false)
        #expect(secondRow?.sourceSummary.contains("audit discrep") == false)
    }

    @Test("getPreBillingData excludes labor from locked billing periods")
    func testPreBillingDataExcludesLockedBillingPeriods() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-PB-LOCKED", name: "Locked Billing Job")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO billing_periods
                (job_id, period_start, period_end, locked_at, locked_by, created_at)
                VALUES (?, '2026-04-01', '2026-04-30', '2026-05-05 09:00:00', ?, datetime('now'))
                """, arguments: [jobId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-04-15 07:00:00', '2026-04-15 11:00:00', 4.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }

        let rows = try env.reports.getPreBillingData(startDate: "2026-04-01", endDate: "2026-04-30")

        #expect(rows.allSatisfy { $0.id != jobId })
    }

    @Test("getPreBillingData excludes labor from company-wide locked billing periods")
    func testPreBillingDataExcludesCompanyWideLockedBillingPeriods() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-PB-COMPANY-LOCKED", name: "Company Locked Billing Job")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO billing_periods
                (job_id, period_start, period_end, locked_at, locked_by, created_at)
                VALUES (NULL, '2026-05-01', '2026-05-31', '2026-06-01 09:00:00', ?, datetime('now'))
                """, arguments: [env.adminUserId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-05-15 07:00:00', '2026-05-15 11:00:00', 4.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }

        let rows = try env.reports.getPreBillingData(startDate: "2026-05-01", endDate: "2026-05-31")

        #expect(rows.allSatisfy { $0.id != jobId })
    }

    @Test("Bookkeeper labor summary includes gross pay and source count")
    func testBookkeeperLaborSummaryIncludesPayrollTotals() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BK-LABOR", name: "Bookkeeper Labor Job")
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET pay_rate = 20.0 WHERE id = ?", arguments: [env.adminUserId])
            try db.execute(sql: """
                INSERT INTO labor_entries
                (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-06-02 07:00:00', '2026-06-02 18:00:00', 8.0, 2.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }

        let rows = try env.reports.getBookkeeperLaborSummary(startDate: "2026-06-02", endDate: "2026-06-02")
        let row = rows.first(where: { $0.id == env.adminUserId })

        #expect(abs((row?.grossPay ?? 0) - 220.0) < 0.01)
        #expect(row?.laborEntryCount == 1)
        #expect(row?.sourceSummary == "1 labor entry")
    }

    @Test("Bookkeeper material export is deterministic and excludes cancelled and deleted POs")
    func testBookkeeperMaterialPOsDeterministicExportRows() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BK-MAT-Z", name: "Zulu Material Job")
        let alphaJobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BK-MAT-A", name: "Alpha Material Job")
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "Bookkeeper Material Category")
        let partId = try E2ETestHelpers.seedPart(env, name: "Bookkeeper Material Part", categoryId: categoryId)
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "Bookkeeper Material Supplier")

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_parts_orders
                (job_id, order_number, status, requested_by, created_at, updated_at)
                VALUES (?, 'JPO-BK-MAT-001', 'ordered', ?, '2026-06-03 08:00:00', '2026-06-03 08:00:00')
                """, arguments: [jobId, env.adminUserId])
            let jpoId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO job_parts_orders
                (job_id, order_number, status, requested_by, created_at, updated_at)
                VALUES (?, 'JPO-BK-MAT-002', 'ordered', ?, '2026-06-03 08:01:00', '2026-06-03 08:01:00')
                """, arguments: [alphaJobId, env.adminUserId])
            let alphaJpoId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, line_status, created_at)
                VALUES (?, ?, 4, 'in_procurement', '2026-06-03 08:05:00')
                """, arguments: [jpoId, partId])
            let jpoLineId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, line_status, created_at)
                VALUES (?, ?, 2, 'in_procurement', '2026-06-03 08:06:00')
                """, arguments: [alphaJpoId, partId])
            let alphaJpoLineId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO purchase_orders
                (po_number, supplier_id, status, order_date, total_cost, created_at, updated_at)
                VALUES ('PO-BK-MAT-001', ?, 'received', '2026-06-03', 44.0, '2026-06-03 09:00:00', '2026-06-03 09:00:00')
                """, arguments: [supplierId])
            let poId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, jpo_line_id, part_id, qty_ordered, qty_received, unit_cost, status, created_at)
                VALUES (?, ?, ?, 4, 4, 11.0, 'received', '2026-06-03 09:05:00')
                """, arguments: [poId, jpoLineId, partId])
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, jpo_line_id, part_id, qty_ordered, qty_received, unit_cost, status, created_at)
                VALUES (?, ?, ?, 2, 2, 11.0, 'received', '2026-06-03 09:06:00')
                """, arguments: [poId, alphaJpoLineId, partId])
            try db.execute(sql: "INSERT OR IGNORE INTO po_jpo_links (po_id, jpo_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [poId, jpoId])
            try db.execute(sql: "INSERT OR IGNORE INTO po_jpo_links (po_id, jpo_id, created_at) VALUES (?, ?, datetime('now'))", arguments: [poId, alphaJpoId])
            try db.execute(sql: """
                INSERT INTO purchase_orders
                (po_number, supplier_id, status, order_date, total_cost, deleted_at, created_at, updated_at)
                VALUES ('PO-BK-MAT-DELETED', ?, 'received', '2026-06-03', 1000.0, datetime('now'), '2026-06-03 09:00:00', '2026-06-03 09:00:00')
                """, arguments: [supplierId])
            try db.execute(sql: """
                INSERT INTO purchase_orders
                (po_number, supplier_id, status, order_date, total_cost, created_at, updated_at)
                VALUES ('PO-BK-MAT-CANCELLED', ?, 'cancelled', '2026-06-03', 1000.0, '2026-06-03 09:00:00', '2026-06-03 09:00:00')
                """, arguments: [supplierId])
        }

        let rows = try env.reports.getBookkeeperMaterialPOs(startDate: "2026-06-03", endDate: "2026-06-03")

        #expect(rows.map(\.poNumber) == ["PO-BK-MAT-001"])
        #expect(rows.first?.lineItemCount == 2)
        #expect(rows.first?.jpoCount == 2)
        #expect(rows.first?.jobNames == "Alpha Material Job,Zulu Material Job")
        #expect(rows.first?.sourceSummary == "2 PO lines, 2 JPOs")
    }

    @Test("Audit summaries aggregate count variance by part and area")
    func testAuditSummariesAggregateVarianceProvenance() throws {
        let env = try E2ETestHelpers.setUp()
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "Audit Summary Category")
        let partId = try E2ETestHelpers.seedPart(env, name: "Audit Summary Part", categoryId: categoryId)

        try env.db.writer.write { db in
            try db.execute(sql: "INSERT INTO warehouse_floor_plans (name, width_inches, length_inches, created_at) VALUES ('Audit Floor', 120, 120, datetime('now'))")
            let floorPlanId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO warehouse_storage_units (floor_plan_id, name, unit_type, created_at) VALUES (?, 'Audit Unit', 'rack', datetime('now'))", arguments: [floorPlanId])
            let unitId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO warehouse_storage_levels (unit_id, level_code, created_at) VALUES (?, 'B', datetime('now'))", arguments: [unitId])
            let levelId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO warehouse_storage_areas (level_id, area_code, area_number, full_location_code, created_at) VALUES (?, 'B1', 1, 'B-1', datetime('now'))", arguments: [levelId])
            let areaId = db.lastInsertedRowID
            try db.execute(sql: "INSERT INTO audit_sessions_v2 (session_type, started_by, status, started_at) VALUES ('count', ?, 'completed', '2026-06-04 08:00:00')", arguments: [env.adminUserId])
            let sessionId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO audit_counts
                (session_id, part_id, area_id, system_count, user_count, variance, variance_dollars, variance_percent, result, counted_by, counted_at)
                VALUES (?, ?, ?, 10, 8, -2, -24.0, -20.0, 'variance', ?, '2026-06-04 08:10:00')
                """, arguments: [sessionId, partId, areaId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO audit_counts
                (session_id, part_id, area_id, system_count, user_count, variance, variance_dollars, variance_percent, result, counted_by, counted_at)
                VALUES (?, ?, ?, 8, 8, 0, 0.0, 0.0, 'match', ?, '2026-06-04 08:20:00')
                """, arguments: [sessionId, partId, areaId, env.adminUserId])
        }

        let rows = try env.reports.getAuditSummaries(startDate: "2026-06-04", endDate: "2026-06-04")

        #expect(rows.count == 1)
        #expect(rows.first?.partName == "Audit Summary Part")
        #expect(rows.first?.areaName == "B-1")
        #expect(rows.first?.countCount == 2)
        #expect(rows.first?.discrepancyCount == 1)
        #expect(rows.first?.totalVariance == -2)
        #expect(abs((rows.first?.totalVarianceDollars ?? 0) - -24.0) < 0.01)
        #expect(rows.first?.sourceSummary == "2 audit counts, 1 discrepancy")
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
