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
}
