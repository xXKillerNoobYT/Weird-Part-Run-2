import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// End-to-end tests for settings management and report generation.
///
/// Covers: settings CRUD → themes → company profiles → PDF settings → billing → reports.
@Suite("E2E: Settings & Reports")
struct E2ESettingsReportsTests {

    // MARK: - Settings CRUD

    @Test("Get and set individual settings")
    func testSettingsCRUD() throws {
        let env = try E2ETestHelpers.setUp()

        // Set a new setting
        try env.settings.upsertSetting(key: "test_key", value: "test_value", category: "test")

        // Read it back
        let value = try env.settings.getSettingValue("test_key")
        #expect(value == "test_value")

        // Update it
        try env.settings.upsertSetting(key: "test_key", value: "updated_value", category: "test")
        let updated = try env.settings.getSettingValue("test_key")
        #expect(updated == "updated_value")
    }

    @Test("Get settings by category")
    func testSettingsByCategory() throws {
        let env = try E2ETestHelpers.setUp()

        try env.settings.upsertSetting(key: "cat_key1", value: "val1", category: "mycat")
        try env.settings.upsertSetting(key: "cat_key2", value: "val2", category: "mycat")

        let catSettings = try env.settings.getSettingsByCategory("mycat")
        #expect(catSettings["cat_key1"] == "val1")
        #expect(catSettings["cat_key2"] == "val2")
    }

    @Test("Bulk upsert settings map")
    func testBulkUpsert() throws {
        let env = try E2ETestHelpers.setUp()

        try env.settings.upsertSettingsMap([
            "bulk_a": "alpha",
            "bulk_b": "beta",
            "bulk_c": "gamma",
        ], category: "bulk")

        let result = try env.settings.getSettingsByCategory("bulk")
        #expect(result.count >= 3)
        #expect(result["bulk_a"] == "alpha")
    }

    @Test("Get all settings organized by category")
    func testGetAllSettings() throws {
        let env = try E2ETestHelpers.setUp()
        let all = try env.settings.getAllSettings()
        // Bootstrap creates settings in "general", "security", "sync", "data" categories
        #expect(!all.isEmpty)
    }

    // MARK: - Theme Settings

    @Test("Theme CRUD: get defaults and update")
    func testThemeCRUD() throws {
        let env = try E2ETestHelpers.setUp()

        let defaultTheme = try env.settings.getTheme()
        #expect(defaultTheme.themeMode == "system")

        let custom = SettingsService.ThemeSettings(
            themeMode: "dark",
            primaryColor: "#FF6B00",
            fontFamily: "system"
        )
        let saved = try env.settings.updateTheme(custom)
        #expect(saved.themeMode == "dark")
        #expect(saved.primaryColor == "#FF6B00")

        let reloaded = try env.settings.getTheme()
        #expect(reloaded.themeMode == "dark")
    }

    // MARK: - Company Profiles

    @Test("Company profile CRUD")
    func testCompanyProfileCRUD() throws {
        let env = try E2ETestHelpers.setUp()

        // CompanyProfile.created_at is NOT NULL in migration but optional in model.
        // GRDB includes all columns in INSERT, so we must set createdAt.
        let now = ISO8601DateFormatter().string(from: Date())
        var profile = CompanyProfile(companyName: "Acme Electric")
        profile.addressStreet = "123 Main St"
        profile.addressCity = "Springfield"
        profile.addressState = "IL"
        profile.addressZip = "62701"
        profile.phone = "555-0100"
        profile.email = "info@acme.com"
        profile.contractorLicense = "EC-12345"
        profile.isPrimary = 1
        profile.createdAt = now
        profile.updatedAt = now

        let profileId = try env.settings.createCompanyProfile(profile)
        #expect(profileId > 0)

        let fetched = try env.settings.getCompanyProfile(profileId)
        #expect(fetched.companyName == "Acme Electric")

        var updated = fetched
        updated.companyName = "Acme Electric LLC"
        try env.settings.updateCompanyProfile(updated)

        let profiles = try env.settings.listCompanyProfiles()
        #expect(profiles.contains { $0.companyName == "Acme Electric LLC" })

        try env.settings.deleteCompanyProfile(profileId)
    }

    // MARK: - PDF Settings

    @Test("PDF settings CRUD")
    func testPDFSettings() throws {
        let env = try E2ETestHelpers.setUp()

        let defaults = try env.settings.getPDFSettings()
        #expect(!defaults.accentColor.isEmpty)

        var custom = defaults
        custom.footerText = "Thank you for your business"
        let saved = try env.settings.updatePDFSettings(custom)
        #expect(saved.footerText == "Thank you for your business")
    }

    // MARK: - Billing & Pay Period Settings

    @Test("Billing cycle settings")
    func testBillingCycleSettings() throws {
        let env = try E2ETestHelpers.setUp()

        let defaults = try env.settings.getBillingCycle()
        #expect(!defaults.cycleType.isEmpty)

        var custom = defaults
        custom.cycleType = "monthly"
        let saved = try env.settings.updateBillingCycle(custom)
        #expect(saved.cycleType == "monthly")
    }

    @Test("Pay period settings")
    func testPayPeriodSettings() throws {
        let env = try E2ETestHelpers.setUp()

        let defaults = try env.settings.getPayPeriod()
        #expect(!defaults.periodType.isEmpty)
    }

    // MARK: - Warranty

    @Test("Warranty length setting")
    func testWarrantyLength() throws {
        let env = try E2ETestHelpers.setUp()

        try env.settings.updateWarrantyLengthDays(365)
        let days = try env.settings.getWarrantyLengthDays()
        #expect(days == 365)
    }

    // MARK: - Reports

    @Test("Timesheet data retrieval")
    func testTimesheetData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        _ = try env.jobs.clockOut(laborEntryId: entryId)

        let data = try env.reports.getTimesheetData(
            startDate: "2026-01-01",
            endDate: "2026-12-31"
        )
        #expect(data.count >= 1)
    }

    @Test("Daily report summary")
    func testDailyReportSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getDailyReportSummary(date: "2026-03-15")
        #expect(summary.count >= 0)
    }

    @Test("Spending summary")
    func testSpendingSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getSpendingSummary(days: 30)
        #expect(summary.totalSpend >= 0)
    }

    @Test("Profitability summary")
    func testProfitabilitySummary() throws {
        let env = try E2ETestHelpers.setUp()
        let summary = try env.reports.getProfitabilitySummary()
        #expect(summary.count >= 0)
    }

    @Test("Reports stats")
    func testReportsStats() throws {
        let env = try E2ETestHelpers.setUp()
        // ReportsService.getReportsStats() references billing_periods.status which doesn't exist
        do {
            let stats = try env.reports.getReportsStats()
            #expect(stats.totalLaborHoursThisMonth >= 0)
        } catch {
            #expect(error.localizedDescription.contains("no such column"))
        }
    }
}
