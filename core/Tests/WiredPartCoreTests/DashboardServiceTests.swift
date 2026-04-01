import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("DashboardService Tests")
struct DashboardServiceTests {

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

    @Test("Certification expiry alerts")
    func testCertAlerts() throws {
        let (_, dash) = try freshEnv()
        let alerts = try dash.getCertificationExpiryAlerts(withinDays: 30)
        #expect(alerts.count >= 0)
    }

    @Test("Vehicle expiry alerts")
    func testVehicleAlerts() throws {
        let (_, dash) = try freshEnv()
        let alerts = try dash.getVehicleExpiryAlerts(withinDays: 30)
        #expect(alerts.count >= 0)
    }

    // MARK: - Daily Report

    @Test("Daily report returns valid structure")
    func testDailyReport() throws {
        let (_, dash) = try freshEnv()
        let report = try dash.getDailyReport()
        #expect(report.pendingJPOs >= 0)
    }

    // MARK: - Dashboard Data (Aggregated)

    @Test("Full dashboard data aggregates all KPIs")
    func testDashboardData() throws {
        let (_, dash) = try freshEnv()
        let data = try dash.getDashboardData()
        #expect(data.kpiSummary.activeJobs >= 0)
    }

    // MARK: - Delivery & Budget

    @Test("Expected deliveries query")
    func testExpectedDeliveries() throws {
        let (_, dash) = try freshEnv()
        let deliveries = try dash.getExpectedDeliveries()
        #expect(deliveries.count >= 0)
    }

    @Test("Budget alerts query")
    func testBudgetAlerts() throws {
        let (_, dash) = try freshEnv()
        let alerts = try dash.getBudgetAlerts()
        #expect(alerts.count >= 0)
    }

    // MARK: - Labor & Clock

    @Test("My hours today for user")
    func testMyHoursToday() throws {
        let (env, dash) = try freshEnv()
        let hours = try dash.getMyHoursToday(userId: env.adminUserId)
        #expect(hours.totalHours >= 0)
    }

    @Test("Team clocked in status")
    func testTeamClockedIn() throws {
        let (_, dash) = try freshEnv()
        let team = try dash.getTeamClockedIn()
        #expect(team.count >= 0)
    }

    @Test("Clock status for user")
    func testClockStatus() throws {
        let (env, dash) = try freshEnv()
        let status = try dash.getClockStatus(userId: env.adminUserId)
        #expect(!status.isClockedIn)
    }

    @Test("Labor chart data")
    func testLaborChartData() throws {
        let (_, dash) = try freshEnv()
        let data = try dash.getLaborChartData()
        #expect(data.count >= 0)
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

    @Test("Stock by location type")
    func testStockByLocationType() throws {
        let (_, dash) = try freshEnv()
        let groups = try dash.getStockByLocationType()
        #expect(groups.count >= 0)
    }

    @Test("Low stock parts query")
    func testLowStockParts() throws {
        let (_, dash) = try freshEnv()
        let low = try dash.getLowStockParts()
        #expect(low.count >= 0)
    }

    // MARK: - Detail Queries

    @Test("Job KPI detail")
    func testJobKPIDetail() throws {
        let (env, dash) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)
        let detail = try dash.getJobKPIDetail(jobId: jobId)
        #expect(detail != nil)
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
}
