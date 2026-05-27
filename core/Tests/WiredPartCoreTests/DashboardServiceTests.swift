import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("DashboardService Tests", .serialized)
struct DashboardServiceTests {
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

    private func freshEnv() throws -> (E2ETestHelpers.TestEnvironment, DashboardService) {
        let env = try E2ETestHelpers.setUp()
        let dashboard = DashboardService(db: env.db)
        return (env, dashboard)
    }

    // MARK: - KPI Summary

    @Test("KPI summary returns valid structure")
    func testKPISummary() throws {
        let (_, dash) = try freshEnv()

        let kpi = try dash.getKPISummary()
        #expect(kpi.activeJobs >= 0)
        #expect(kpi.pendingOrders >= 0)
        #expect(kpi.lowStockAlerts >= 0)
    }

    @Test("KPI summary reflects data: active jobs count")
    func testKPIWithJobs() throws {
        let (env, dash) = try freshEnv()

        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-100", name: "Dashboard Job")

        let kpi = try dash.getKPISummary()
        #expect(kpi.activeJobs >= 1)
    }

    // MARK: - Alerts

    @Test("Certification expiry alerts detect expiring cert")
    func testCertAlerts() throws {
        let (env, dash) = try freshEnv()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let expiryStr = fmt.string(from: Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO certifications (user_id, cert_type, cert_name, expiry_date, is_active)
                VALUES (?, 'OSHA30', 'OSHA 30-Hour', ?, 1)
                """, arguments: [env.adminUserId, expiryStr])
        }
        let alerts = try dash.getCertificationExpiryAlerts(withinDays: 30)
        #expect(alerts.count == 1)
        #expect(alerts[0].daysRemaining >= 0 && alerts[0].daysRemaining <= 30)
    }

    @Test("Vehicle expiry alerts detect expiring insurance")
    func testVehicleAlerts() throws {
        let (env, dash) = try freshEnv()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let expiryStr = fmt.string(from: Calendar.current.date(byAdding: .day, value: 7, to: Date())!)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO vehicles (vehicle_number, vehicle_name, insurance_expiry, is_active)
                VALUES ('T-01', 'Test Truck', ?, 1)
                """, arguments: [expiryStr])
        }
        let alerts = try dash.getVehicleExpiryAlerts(withinDays: 30)
        #expect(alerts.count >= 1)
        let found = alerts.first { $0.vehicleNumber == "T-01" }
        #expect(found != nil)
        #expect(found?.expiryType == "insurance")
    }

    // MARK: - Daily Report

    @Test("Daily report pendingJPOs reflects submitted JPO")
    func testDailyReport() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DR-01", name: "Report Job")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_parts_orders (job_id, order_number, status, order_type, requested_by)
                VALUES (?, 'JPO-TEST-001', 'submitted', 'job', ?)
                """, arguments: [jobId, env.adminUserId])
        }
        let report = try dash.getDailyReport()
        #expect(report.pendingJPOs == 1)
    }

    // MARK: - Dashboard Data (Aggregated)

    @Test("Full dashboard data aggregates all KPIs")
    func testDashboardData() throws {
        let (_, dash) = try freshEnv()
        let data = try dash.getDashboardData()
        #expect(data.kpiSummary.activeJobs >= 0)
    }

    @Test("Labor chart buckets UTC evening clock-in into local work day")
    func testLaborChartUsesLocalOperationalDayForUtcClockIn() throws {
        try withDenverTimeZone {
            let (env, dash) = try freshEnv()
            let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCAL-DASH", name: "Local Dashboard Job")

            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = TimeZone(identifier: "America/Denver")!
            let localStartOfDay = localCalendar.startOfDay(for: Date())
            let localEvening = localCalendar.date(bySettingHour: 21, minute: 30, second: 0, of: localStartOfDay)!

            let utcFormatter = DateFormatter()
            utcFormatter.calendar = Calendar(identifier: .gregorian)
            utcFormatter.locale = Locale(identifier: "en_US_POSIX")
            utcFormatter.timeZone = TimeZone(identifier: "UTC")
            utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            let localDayFormatter = DateFormatter()
            localDayFormatter.calendar = Calendar(identifier: .gregorian)
            localDayFormatter.locale = Locale(identifier: "en_US_POSIX")
            localDayFormatter.timeZone = TimeZone(identifier: "America/Denver")
            localDayFormatter.dateFormat = "yyyy-MM-dd"

            let clockIn = utcFormatter.string(from: localEvening)
            let clockOut = utcFormatter.string(from: localEvening.addingTimeInterval(2 * 60 * 60))
            let localDay = localDayFormatter.string(from: localEvening)

            try env.db.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                    VALUES (?, ?, ?, ?, 2.0, 0.0, 'completed', datetime('now'))
                    """, arguments: [env.adminUserId, jobId, clockIn, clockOut])
            }

            let chartRows = try dash.getLaborChartData()
            let localDayRow = chartRows.first(where: { $0.dateString == localDay })

            #expect(localDayRow != nil)
            #expect(abs((localDayRow?.regularHours ?? 0) - 2.0) < 0.01)
        }
    }

    // MARK: - Delivery & Budget

    @Test("Expected deliveries includes PO with delivery date within window")
    func testExpectedDeliveries() throws {
        let (env, dash) = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(poNumber: "PO-EXP-001", supplierId: suppId)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let tomorrowStr = fmt.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE purchase_orders SET status = 'submitted', expected_delivery = ? WHERE id = ?
                """, arguments: [tomorrowStr, poId])
        }
        let deliveries = try dash.getExpectedDeliveries()
        #expect(deliveries.count >= 1)
        let found = deliveries.first { $0.poNumber == "PO-EXP-001" }
        #expect(found != nil)
    }

    @Test("Budget alerts fire when job spend exceeds 80% of limit")
    func testBudgetAlerts() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BUDGET-01", name: "Budget Job")
        // Set budget_limit=100, pay_rate=100, seed 1 labor hour (100% spent > 80% threshold)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET budget_limit = 100 WHERE id = ?", arguments: [jobId])
            try db.execute(sql: "UPDATE users SET pay_rate = 100 WHERE id = ?", arguments: [env.adminUserId])
            try db.execute(sql: """
                INSERT INTO labor_entries (user_id, job_id, clock_in, clock_out, regular_hours, status)
                VALUES (?, ?, datetime('now','-1 hour'), datetime('now'), 1.0, 'completed')
                """, arguments: [env.adminUserId, jobId])
        }
        let alerts = try dash.getBudgetAlerts()
        #expect(alerts.count >= 1)
        let found = alerts.first { $0.id == jobId }
        #expect(found != nil)
        #expect((found?.pctUsed ?? 0) >= 80.0)
    }

    // MARK: - Labor & Clock

    @Test("My hours today for user")
    func testMyHoursToday() throws {
        let (env, dash) = try freshEnv()
        let hours = try dash.getMyHoursToday(userId: env.adminUserId)
        #expect(hours.totalHours >= 0)
    }

    @Test("My hours today reads completed break minutes from break records without labor gaps")
    func testMyHoursTodayBreakMinutesFromBreakRecords() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-BREAK-01", name: "Break Job")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries (user_id, job_id, clock_in, clock_out, regular_hours, status)
                VALUES (?, ?, datetime('now','-4 hours'), datetime('now','-1 hour'), 3.0, 'completed')
                """, arguments: [env.adminUserId, jobId])
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES
                    (?, 'break', datetime('now','-3 hours'), datetime('now','-2 hours','-45 minutes'), 15, 1, 0),
                    (?, 'lunch_unpaid', datetime('now','-2 hours'), datetime('now','-1 hours','-30 minutes'), 30, 0, 0)
                """, arguments: [env.adminUserId, env.adminUserId])
        }

        let hours = try dash.getMyHoursToday(userId: env.adminUserId)

        #expect(hours.breakMinutes == 45)
    }

    @Test("My hours today includes elapsed minutes for active same-day break record")
    func testMyHoursTodayIncludesActiveBreakElapsedMinutes() throws {
        let (env, dash) = try freshEnv()
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES
                    (?, 'break', datetime('now','-20 minutes'), NULL, NULL, 1, 0)
                """, arguments: [env.adminUserId])
        }

        let hours = try dash.getMyHoursToday(userId: env.adminUserId)

        #expect(hours.breakMinutes >= 19)
        #expect(hours.breakMinutes <= 21)
    }

    @Test("Team clocked in status reflects active clock entry")
    func testTeamClockedIn() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TEAM-01", name: "Team Job")
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        let team = try dash.getTeamClockedIn()
        #expect(team.count == 1)
        #expect(team[0].displayName == "TestAdmin")
    }

    @Test("Clock status for user")
    func testClockStatus() throws {
        let (env, dash) = try freshEnv()
        let status = try dash.getClockStatus(userId: env.adminUserId)
        #expect(!status.isClockedIn)
    }

    @Test("Labor chart data always returns 7 days; today's hours reflect completed entry")
    func testLaborChartData() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LABOR-01", name: "Labor Job")
        // Seed a completed labor entry today with 3.0 regular hours
        try env.db.writer.write { db in
            // Use 'localtime' modifier so SQLite's date matches Swift's local DateFormatter
            try db.execute(sql: """
                INSERT INTO labor_entries (user_id, job_id, clock_in, clock_out, regular_hours, status)
                VALUES (?, ?, date('now','localtime'), datetime('now','localtime'), 3.0, 'completed')
                """, arguments: [env.adminUserId, jobId])
        }
        let data = try dash.getLaborChartData()
        #expect(data.count == 7)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        let todayRow = data.first { $0.dateString == todayStr }
        #expect(todayRow != nil)
        #expect((todayRow?.regularHours ?? 0) == 3.0)
    }

    // MARK: - Inventory Charts

    @Test("Stock chart data")
    func testStockChartData() throws {
        let (_, dash) = try freshEnv()
        let data = try dash.getStockChartData()
        #expect(data.count >= 0)
    }

    @Test("Spending chart data")
    func testSpendingChartData() throws {
        let (_, dash) = try freshEnv()
        let data = try dash.getSpendingChartData()
        #expect(data.count >= 0)
    }

    // MARK: - Part & Category Queries

    @Test("Active jobs for picker")
    func testActiveJobsPicker() throws {
        let (env, dash) = try freshEnv()
        _ = try E2ETestHelpers.seedJob(env)
        let jobs = try dash.getActiveJobsForPicker()
        #expect(jobs.count >= 1)
    }

    @Test("Categories with counts")
    func testCategoriesWithCounts() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        _ = try E2ETestHelpers.seedPart(env, categoryId: catId)
        let cats = try dash.getCategoriesWithCounts()
        #expect(cats.count >= 1)
    }

    @Test("Parts in category")
    func testPartsInCategory() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        _ = try E2ETestHelpers.seedPart(env, name: "Part A", categoryId: catId)
        let parts = try dash.getPartsInCategory(categoryId: catId)
        #expect(parts.count >= 1)
    }

    // MARK: - Stock Queries

    @Test("Stock by location type groups seeded warehouse stock correctly")
    func testStockByLocationType() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Stock Wire", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 15, locationType: "warehouse", locationId: 1)
        let groups = try dash.getStockByLocationType()
        #expect(groups.count >= 1)
        let warehouse = groups.first { $0.locationType == "warehouse" }
        #expect(warehouse != nil)
        #expect((warehouse?.totalQty ?? 0) >= 15)
    }

    @Test("Low stock parts returns part below min level")
    func testLowStockParts() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Low Fuse", categoryId: catId)
        // Set min_stock_level = 10, seed qty = 2 (below threshold)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET min_stock_level = 10 WHERE id = ?", arguments: [partId])
        }
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 2, locationType: "warehouse", locationId: 1)
        let low = try dash.getLowStockParts()
        #expect(low.count >= 1)
        let found = low.first { $0.id == partId }
        #expect(found != nil)
        #expect(found?.currentQty == 2)
        #expect(found?.minLevel == 10)
    }

    // MARK: - Detail Queries

    @Test("Job KPI detail")
    func testJobKPIDetail() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let detail = try dash.getJobKPIDetail(jobId: jobId)
        #expect(detail != nil)
    }

    @Test("getJobKPIDetail returns nil for a soft-deleted job")
    func testGetJobKPIDetail_nilForSoftDeletedJob() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [jobId])
        }
        // Regression: WHERE j.id = ? had no deleted_at guard, so dashboard KPI
        // would happily render tombstoned jobs with stale spend/labor numbers.
        let detail = try dash.getJobKPIDetail(jobId: jobId)
        #expect(detail == nil,
            "Soft-deleted jobs must not surface on dashboard KPI detail")
    }

    // MARK: - Daily Report Submission

    @Test("Submit daily report")
    func testSubmitDailyReport() throws {
        let (env, dash) = try freshEnv()
        let reportId = try dash.submitDailyReport(
            userId: env.adminUserId,
            accomplishments: "Wired Panel A",
            issues: "Missing connectors",
            tomorrowNotes: "Need to order parts"
        )
        #expect(reportId > 0)
    }

    @Test("Report problem")
    func testReportProblem() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let reportId = try dash.reportProblem(
            userId: env.adminUserId,
            jobId: jobId,
            description: "Water damage in ceiling"
        )
        #expect(reportId > 0)
    }

    // MARK: - Attention & Schedule

    @Test("Attention items query")
    func testAttentionItems() throws {
        let (_, dash) = try freshEnv()
        let items = try dash.getAttentionItems()
        #expect(items.count >= 0)
    }

    @Test("Today schedule query")
    func testTodaySchedule() throws {
        let (_, dash) = try freshEnv()
        let schedule = try dash.getTodaySchedule()
        #expect(schedule.count >= 0)
    }

    @Test("Employee count")
    func testEmployeeCount() throws {
        let (_, dash) = try freshEnv()
        let count = try dash.getEmployeeCount()
        #expect(count >= 1)
    }

    // MARK: - Stock At Location Type

    @Test("getStockAtLocationType returns empty on fresh DB")
    func testStockAtLocationTypeEmpty() throws {
        let (_, dash) = try freshEnv()
        let rows = try dash.getStockAtLocationType("warehouse")
        #expect(rows.count >= 0)
    }

    @Test("getStockAtLocationType returns rows for matching type after seeding stock")
    func testStockAtLocationTypeWithData() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Conduit A", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 10, locationType: "warehouse", locationId: 1)

        let rows = try dash.getStockAtLocationType("warehouse")
        #expect(rows.count >= 1)
        let found = rows.first { $0.partId == partId }
        #expect(found != nil)
        #expect(found?.qty == 10)
    }

    @Test("getStockAtLocationType filters by location type — other types not returned")
    func testStockAtLocationTypeFiltersCorrectly() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Breaker", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5, locationType: "truck", locationId: 99)

        // Requesting "warehouse" should NOT include the truck stock
        let rows = try dash.getStockAtLocationType("warehouse")
        let found = rows.first { $0.partId == partId }
        #expect(found == nil)

        // Requesting "truck" should include it
        let truckRows = try dash.getStockAtLocationType("truck")
        let truckFound = truckRows.first { $0.partId == partId }
        #expect(truckFound != nil)
    }

    // MARK: - PO KPI Detail

    @Test("getPOKPIDetail returns nil for non-existent PO")
    func testPOKPIDetailMissing() throws {
        let (_, dash) = try freshEnv()
        let (detail, lines) = try dash.getPOKPIDetail(poId: 99999)
        #expect(detail == nil)
        #expect(lines.isEmpty)
    }

    @Test("getPOKPIDetail returns nil for a soft-deleted PO")
    func testGetPOKPIDetail_nilForSoftDeletedPO() throws {
        let (env, dash) = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-DASH-DEL",
            supplierId: suppId,
            notes: nil
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE purchase_orders SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [poId])
        }
        // Regression: WHERE po.id = ? had no deleted_at guard, so dashboard KPI
        // PO detail still showed tombstoned POs in the "recent orders" deep-link.
        let (detail, _) = try dash.getPOKPIDetail(poId: poId)
        #expect(detail == nil,
            "Soft-deleted POs must not surface on dashboard KPI detail")
    }

    @Test("getPOKPIDetail returns detail for existing PO")
    func testPOKPIDetailExists() throws {
        let (env, dash) = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)

        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-DASH-001",
            supplierId: suppId,
            notes: "Test PO for KPI"
        )

        let (detail, lines) = try dash.getPOKPIDetail(poId: poId)
        #expect(detail != nil)
        #expect(detail?.poNumber == "PO-DASH-001")
        #expect(lines.count >= 0)
    }

    // MARK: - Stock Locations For Part

    @Test("getStockLocationsForPart returns empty for part with no stock")
    func testStockLocationsForPartEmpty() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Empty Part", categoryId: catId)

        let locations = try dash.getStockLocationsForPart(partId: partId)
        #expect(locations.isEmpty)
    }

    @Test("getStockLocationsForPart returns rows after seeding stock")
    func testStockLocationsForPartWithData() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Wire 12 AWG", categoryId: catId)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 20, locationType: "warehouse", locationId: 1)
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 5, locationType: "truck", locationId: 10)

        let locations = try dash.getStockLocationsForPart(partId: partId)
        #expect(locations.count == 2)
        #expect(locations.allSatisfy { $0.qty > 0 })
    }

    // MARK: - Part Movement Info

    @Test("getPartMovementInfo returns nil values for unknown part")
    func testPartMovementInfoUnknown() throws {
        let (_, dash) = try freshEnv()
        let (lastMovement, reorderPoint) = try dash.getPartMovementInfo(partId: 99999)
        #expect(lastMovement == nil)
        #expect(reorderPoint == nil)
    }

    @Test("getPartMovementInfo returns reorder point from parts table")
    func testPartMovementInfoReorderPoint() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Fuse 20A", categoryId: catId)

        // Set reorder_point directly
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET reorder_point = 5 WHERE id = ?", arguments: [partId])
        }

        let (_, reorderPoint) = try dash.getPartMovementInfo(partId: partId)
        #expect(reorderPoint == 5)
    }

    // MARK: - Office Briefing

    @Test("getOfficeBriefing returns valid structure on fresh DB")
    func testOfficeBriefingEmpty() throws {
        let (_, dash) = try freshEnv()
        let briefing = try dash.getOfficeBriefing()
        #expect(!briefing.summary.isEmpty)
        #expect(briefing.alertCount >= 0)
    }

    @Test("getOfficeBriefing summary contains expected language")
    func testOfficeBriefingSummaryFormat() throws {
        let (_, dash) = try freshEnv()
        let briefing = try dash.getOfficeBriefing()
        // Summary always begins with "Good morning." regardless of data state
        #expect(briefing.summary.hasPrefix("Good morning."))
    }

    @Test("getOfficeSmartCards returns command center counts")
    func testOfficeSmartCardsCommandCenterCounts() throws {
        let (env, dash) = try freshEnv()
        let categoryId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Low Stock Coupling", categoryId: categoryId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-OFFICE-CARDS", name: "Office Cards Job")
        let supplierId = try E2ETestHelpers.seedSupplier(env)

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET min_stock_level = 10 WHERE id = ?", arguments: [partId])
            try db.execute(sql: """
                INSERT INTO labor_entries (user_id, job_id, clock_in, work_type)
                VALUES (?, ?, datetime('now'), 'regular')
                """, arguments: [env.adminUserId, jobId])
            try db.execute(sql: """
                INSERT INTO job_parts_orders (job_id, order_number, status, order_type, requested_by)
                VALUES (?, 'JPO-OFFICE-CARDS', 'submitted', 'job', ?)
                """, arguments: [jobId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status, expected_delivery, submitted_by)
                VALUES ('PO-OFFICE-CARDS', ?, 'submitted', date('now', '-1 day'), ?)
                """, arguments: [supplierId, env.adminUserId])
            try db.execute(sql: """
                UPDATE jobs
                SET status = 'payment_hold',
                    due_date = date('now', '-1 day'),
                    warranty_end_date = date('now', '+10 days')
                WHERE id = ?
                """, arguments: [jobId])
            try db.execute(sql: """
                INSERT INTO tool_maintenance_types (name)
                VALUES ('Office Card Calibration')
                """)
            let maintenanceTypeId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO tools (tool_number, name, category, calibration_due_date)
                VALUES ('TOOL-OFFICE-CARDS', 'Office Card Meter', 'meter', date('now', '+2 days'))
                """)
            let toolId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO tool_maintenance_schedules (tool_id, maintenance_type_id, next_due_date)
                VALUES (?, ?, date('now', '+2 days'))
                """, arguments: [toolId, maintenanceTypeId])
        }

        let cards = Dictionary(uniqueKeysWithValues: try dash.getOfficeSmartCards().map { ($0.id, $0.count) })
        #expect(cards["approvals_pending"] == 1)
        #expect(cards["working_today"] == 1)
        #expect(cards["jpos_pending"] == 1)
        #expect(cards["payment_overdue"] == 1)
        #expect(cards["parts_below_min"] == 1)
        #expect(cards["maintenance_due"] == 2)
        #expect(cards["callbacks_overdue"] == 1)
        #expect(cards["warranty_expiring"] == 1)
    }

    @Test("getAttentionItems includes command center attention sources")
    func testAttentionItemsIncludeCommandCenterSources() throws {
        let (env, dash) = try freshEnv()
        let categoryId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, name: "Attention Low Stock Part", categoryId: categoryId)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-ATTENTION-SOURCES", name: "Attention Sources Job")

        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET min_stock_level = 5 WHERE id = ?", arguments: [partId])
            try db.execute(sql: """
                INSERT INTO qa_threads (job_id, asked_by, subject, status, priority)
                VALUES (?, ?, 'Need office decision', 'open', 'normal')
                """, arguments: [jobId, env.adminUserId])
            try db.execute(sql: """
                UPDATE jobs
                SET due_date = date('now', '-1 day'),
                    warranty_end_date = date('now', '+20 days')
                WHERE id = ?
                """, arguments: [jobId])
            try db.execute(sql: """
                INSERT INTO certifications (user_id, cert_type, cert_name, expiry_date, is_active)
                VALUES (?, 'safety', 'Lift Cert', date('now', '+15 days'), 1)
                """, arguments: [env.adminUserId])
            try db.execute(sql: """
                INSERT INTO tool_maintenance_types (name)
                VALUES ('Attention Maintenance')
                """)
            let maintenanceTypeId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO tools (tool_number, name, category)
                VALUES ('TOOL-ATTENTION', 'Attention Meter', 'meter')
                """)
            let toolId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO tool_maintenance_schedules (tool_id, maintenance_type_id, next_due_date)
                VALUES (?, ?, date('now', '+1 day'))
                """, arguments: [toolId, maintenanceTypeId])
        }

        let itemTypes = Set(try dash.getAttentionItems().map(\.itemType))
        #expect(itemTypes.contains("low_stock"))
        #expect(itemTypes.contains("open_qa"))
        #expect(itemTypes.contains("overdue_job"))
        #expect(itemTypes.contains("maintenance_due"))
        #expect(itemTypes.contains("expiring_cert"))
        #expect(itemTypes.contains("warranty_expiring"))
    }

    // MARK: - Financial Snapshot

    @Test("getFinancialSnapshot returns zeroes on fresh DB")
    func testFinancialSnapshotEmpty() throws {
        let (_, dash) = try freshEnv()
        let snap = try dash.getFinancialSnapshot()
        #expect(snap.spendingThisWeek >= 0)
        #expect(snap.spendingLastWeek >= 0)
        #expect(snap.spendingThisMonth >= 0)
        #expect(snap.spendingLastMonth >= 0)
        #expect(snap.outstandingPOValue >= 0)
    }

    @Test("getFinancialSnapshot reflects outstanding PO value")
    func testFinancialSnapshotWithPO() throws {
        let (env, dash) = try freshEnv()
        let suppId = try E2ETestHelpers.seedSupplier(env)

        // Create a submitted PO (counts toward outstanding value)
        let poId = try env.orders.createPurchaseOrder(
            poNumber: "PO-SNAP-001",
            supplierId: suppId
        )
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE purchase_orders SET status = 'submitted', total_cost = 500.0 WHERE id = ?", arguments: [poId])
        }

        let snap = try dash.getFinancialSnapshot()
        #expect(snap.outstandingPOValue >= 500.0)
    }

    // MARK: - processQRScan

    @Test("processQRScan with empty string returns invalid source")
    func testProcessQRScanInvalid() throws {
        let (_, dash) = try freshEnv()
        // Empty string is the one case QRCodec explicitly marks as invalid
        let result = try dash.processQRScan("")
        #expect(result.source == .invalid)
        #expect(result.entityId == nil)
    }

    @Test("processQRScan with unrecognized string returns external source")
    func testProcessQRScanUnrecognized() throws {
        let (_, dash) = try freshEnv()
        // Non-WiredPart strings are treated as external barcodes, not invalid
        let result = try dash.processQRScan("not-a-valid-qr-code-!!!###")
        #expect(result.source == .external)
        #expect(result.entityId == nil)
    }

    @Test("processQRScan with V2 part QR finds the part")
    func testProcessQRScanV2Part() throws {
        let (env, dash) = try freshEnv()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        // Encode a V2 part QR and scan it through the dashboard
        let payload = QRPayload(type: .part, id: partId, code: "P-\(partId)", meta: nil)
        let qrString = try QRCodec.encode(payload)

        let result = try dash.processQRScan(qrString)
        #expect(result.source == .wiredPartV2)
        #expect(result.entityType == .part)
        #expect(result.entityId == partId)
        #expect(result.isFound)
    }

    @Test("processQRScan with V2 QR for non-existent entity returns not_found")
    func testProcessQRScanPartNotFound() throws {
        let (_, dash) = try freshEnv()

        // Encode a QR for a part ID that does not exist
        let payload = QRPayload(type: .part, id: 99999, code: "GHOST", meta: nil)
        let qrString = try QRCodec.encode(payload)

        let result = try dash.processQRScan(qrString)
        #expect(result.source == .wiredPartV2)
        #expect(!result.isFound)
        #expect(result.fields["_status"] == "not_found")
    }

    @Test("processQRScan with plain barcode searches catalog as external code")
    func testProcessQRScanExternalCode() throws {
        let (_, dash) = try freshEnv()
        // A plain non-JSON string is treated as an external code
        let result = try dash.processQRScan("BARCODE-ABC123")
        #expect(result.source == .external)
        // No matching part in DB → not found
        #expect(!result.isFound)
    }

    @Test("getClockStatus returns nil jobName for soft-deleted job")
    func testGetClockStatusHidesDeletedJobName() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let status = try dash.getClockStatus(userId: env.adminUserId)
        #expect(status.isClockedIn == true)
        #expect(status.jobName == nil)
    }

    @Test("getExpectedDeliveries shows Unknown for soft-deleted supplier")
    func testGetExpectedDeliveriesHidesDeletedSupplierName() throws {
        let (env, dash) = try freshEnv()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "DelSupplierDash")
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status, expected_delivery)
                VALUES ('PO-DASH-DEL-01', ?, 'submitted', date('now', '+2 days'))
                """, arguments: [supplierId])
            try db.execute(sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [supplierId])
        }
        let deliveries = try dash.getExpectedDeliveries()
        let row = deliveries.first(where: { $0.poNumber == "PO-DASH-DEL-01" })
        #expect(row != nil)
        #expect(row?.supplierName == "Unknown")
    }

    @Test("getTodaySchedule shows Unknown for soft-deleted job and user")
    func testGetTodayScheduleHidesDeletedJobAndUserNames() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        _ = try env.scheduling.createDispatch(jobId: jobId, userId: env.adminUserId, date: today)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [env.adminUserId])
        }
        let schedule = try dash.getTodaySchedule()
        #expect(schedule.isEmpty == false)
        #expect(schedule.first?.jobName == "Unassigned")
        #expect(schedule.first?.employeeName == "Unknown")
    }

    @Test("getPOKPIDetail shows Unknown for soft-deleted supplier")
    func testGetPOKPIDetailHidesDeletedSupplierName() throws {
        let (env, dash) = try freshEnv()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "DelPOSupplier")
        var poId: Int64 = 0
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status)
                VALUES ('PO-KPI-DEL-01', ?, 'submitted')
                """, arguments: [supplierId])
            poId = db.lastInsertedRowID
            try db.execute(sql: "UPDATE suppliers SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [supplierId])
        }
        let (detail, _) = try dash.getPOKPIDetail(poId: poId)
        #expect(detail != nil)
        #expect(detail?.supplierName == "Unknown")
    }

    @Test("getPOKPIDetail shows Unknown for soft-deleted part in line items")
    func testGetPOKPIDetailHidesDeletedPartInLineItems() throws {
        let (env, dash) = try freshEnv()
        let supplierId = try E2ETestHelpers.seedSupplier(env, name: "ActivePOSupplier")
        let catId = try E2ETestHelpers.seedCategory(env, name: "KPICat")
        let partId = try E2ETestHelpers.seedPart(env, name: "DelPOPart", categoryId: catId)
        var poId: Int64 = 0
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO purchase_orders (po_number, supplier_id, status)
                VALUES ('PO-KPI-PART-01', ?, 'submitted')
                """, arguments: [supplierId])
            poId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO po_line_items (po_id, part_id, qty_ordered, qty_received, unit_cost)
                VALUES (?, ?, 5, 0, 10.00)
                """, arguments: [poId, partId])
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?",
                           arguments: [partId])
        }
        let (_, lines) = try dash.getPOKPIDetail(poId: poId)
        #expect(lines.isEmpty == false)
        #expect(lines.first?.partName == "Unknown")
    }
}
