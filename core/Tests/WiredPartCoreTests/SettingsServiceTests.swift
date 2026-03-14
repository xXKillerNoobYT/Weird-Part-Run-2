import Testing
import GRDB
@testable import WiredPartCore

@Suite("SettingsService Tests")
struct SettingsServiceTests {

    private func freshDB() throws -> AppDatabase {
        try AppDatabase.openInMemoryDatabase()
    }

    // MARK: - Basic Settings

    @Test("upsertSetting creates new setting")
    func testUpsertNew() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "test_key", value: "test_value", category: "general")

        let val = try svc.getSetting("test_key")
        #expect(val == "test_value")
    }

    @Test("upsertSetting updates existing setting")
    func testUpsertUpdate() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "test_key", value: "old_value")
        try svc.upsertSetting(key: "test_key", value: "new_value")

        let val = try svc.getSetting("test_key")
        #expect(val == "new_value")
    }

    @Test("getSetting returns nil for missing key")
    func testGetSettingMissing() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let val = try svc.getSetting("nonexistent")
        #expect(val == nil)
    }

    @Test("getSettingsByCategory returns correct map")
    func testGetByCategory() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "k1", value: "v1", category: "test_cat")
        try svc.upsertSetting(key: "k2", value: "v2", category: "test_cat")
        try svc.upsertSetting(key: "k3", value: "v3", category: "other_cat")

        let map = try svc.getSettingsByCategory("test_cat")
        #expect(map.count == 2)
        #expect(map["k1"] == "v1")
        #expect(map["k2"] == "v2")
    }

    @Test("getAllSettings groups by category")
    func testGetAllGrouped() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "a", value: "1", category: "cat_a")
        try svc.upsertSetting(key: "b", value: "2", category: "cat_b")

        let all = try svc.getAllSettings()
        #expect(all["cat_a"]?["a"] == "1")
        #expect(all["cat_b"]?["b"] == "2")
    }

    // MARK: - Theme

    @Test("getTheme returns defaults when no settings exist")
    func testThemeDefaults() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let theme = try svc.getTheme()
        #expect(theme.themeMode == "system")
        #expect(theme.primaryColor == "#2563eb")
        #expect(theme.fontFamily == "Inter")
    }

    @Test("updateTheme persists and returns updated theme")
    func testUpdateTheme() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let updated = try svc.updateTheme(SettingsService.ThemeSettings(
            themeMode: "dark",
            primaryColor: "#ff0000",
            fontFamily: "Menlo"
        ))

        #expect(updated.themeMode == "dark")
        #expect(updated.primaryColor == "#ff0000")
        #expect(updated.fontFamily == "Menlo")

        // Verify persistence
        let refetched = try svc.getTheme()
        #expect(refetched.themeMode == "dark")
    }

    // MARK: - PDF Settings

    @Test("getPDFSettings returns defaults when no settings exist")
    func testPDFDefaults() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let pdf = try svc.getPDFSettings()
        #expect(pdf.accentColor == "#2563eb")
        #expect(pdf.showUnitPrices == true)
        #expect(pdf.paymentTerms == "Net 30")
    }

    @Test("updatePDFSettings persists changes")
    func testUpdatePDF() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        var settings = SettingsService.PDFSettings.defaults
        settings.paymentTerms = "Net 60"
        settings.showUnitPrices = false

        let updated = try svc.updatePDFSettings(settings)
        #expect(updated.paymentTerms == "Net 60")
        #expect(updated.showUnitPrices == false)
    }

    // MARK: - Warranty

    @Test("getWarrantyLengthDays returns 365 by default")
    func testWarrantyDefault() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let days = try svc.getWarrantyLengthDays()
        #expect(days == 365)
    }

    @Test("updateWarrantyLengthDays persists value")
    func testUpdateWarranty() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.updateWarrantyLengthDays(730)
        let days = try svc.getWarrantyLengthDays()
        #expect(days == 730)
    }

    // MARK: - Billing Cycle

    @Test("getBillingCycle returns defaults")
    func testBillingCycleDefaults() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let bc = try svc.getBillingCycle()
        #expect(bc.cycleType == "monthly")
        #expect(bc.startDay == 1)
    }

    @Test("updateBillingCycle persists changes")
    func testUpdateBillingCycle() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let updated = try svc.updateBillingCycle(SettingsService.BillingCycleSettings(
            cycleType: "weekly",
            startDay: 5
        ))
        #expect(updated.cycleType == "weekly")
        #expect(updated.startDay == 5)
    }

    // MARK: - Pay Period

    @Test("getPayPeriod returns defaults")
    func testPayPeriodDefaults() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let pp = try svc.getPayPeriod()
        #expect(pp.periodType == "biweekly")
        #expect(pp.startDay == 1)
    }

    @Test("updatePayPeriod persists changes")
    func testUpdatePayPeriod() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let updated = try svc.updatePayPeriod(SettingsService.PayPeriodSettings(
            periodType: "monthly",
            startDay: 15
        ))
        #expect(updated.periodType == "monthly")
        #expect(updated.startDay == 15)
    }

    // MARK: - Company Profiles

    @Test("createCompanyProfile and list")
    func testCompanyProfileCRUD() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        var profile = CompanyProfile(companyName: "Test Corp", isPrimary: 1)
        profile.phone = "555-1234"
        profile.email = "info@test.com"

        let id = try svc.createCompanyProfile(profile)
        #expect(id > 0)

        let profiles = try svc.listCompanyProfiles()
        #expect(profiles.count == 1)
        #expect(profiles[0].companyName == "Test Corp")
        #expect(profiles[0].phone == "555-1234")
    }

    @Test("deleteCompanyProfile soft-deletes")
    func testCompanyProfileDelete() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let profile = CompanyProfile(companyName: "To Delete", isPrimary: 0)
        let id = try svc.createCompanyProfile(profile)

        try svc.deleteCompanyProfile(id)

        // Soft-deleted should not appear in list
        let profiles = try svc.listCompanyProfiles()
        #expect(profiles.isEmpty)

        // But still exists in DB
        let raw = try db.writer.read { dbConn in
            try CompanyProfile.fetchOne(dbConn, sql: "SELECT * FROM company_profiles WHERE id = ?", arguments: [id])
        }
        #expect(raw != nil)
        #expect(raw?.deletedAt != nil)
    }
}
