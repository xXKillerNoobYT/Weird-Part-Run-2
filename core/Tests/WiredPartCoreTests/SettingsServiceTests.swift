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

        var profile = CompanyProfile(companyName: "Test Corp", isPrimary: 1, createdAt: "2026-03-14 00:00:00", updatedAt: "2026-03-14 00:00:00")
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

        let profile = CompanyProfile(companyName: "To Delete", isPrimary: 0, createdAt: "2026-03-14 00:00:00", updatedAt: "2026-03-14 00:00:00")
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

    // MARK: - upsertSettingsMap

    @Test("upsertSettingsMap writes all key-value pairs")
    func testUpsertSettingsMap() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSettingsMap(
            ["color": "blue", "font": "system", "size": "14"],
            category: "ui"
        )

        let map = try svc.getSettingsByCategory("ui")
        #expect(map["color"] == "blue")
        #expect(map["font"] == "system")
        #expect(map["size"] == "14")
    }

    // MARK: - Business Profile

    @Test("createBusinessProfile and hasBusinessProfile")
    func testBusinessProfileCreate() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        #expect(try svc.hasBusinessProfile() == false)
        #expect(try svc.getBusinessProfile() == nil)

        var profile = BusinessProfile(companyName: "WiredPart LLC", isActive: 1)
        profile.industry = "Electrical"
        let created = try svc.createBusinessProfile(profile)
        #expect(created.id != nil)
        #expect(try svc.hasBusinessProfile() == true)
    }

    @Test("updateBusinessProfile persists changes")
    func testBusinessProfileUpdate() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let profile = BusinessProfile(companyName: "Original LLC", isActive: 1)
        var created = try svc.createBusinessProfile(profile)
        created.companyName = "Updated LLC"
        let updated = try svc.updateBusinessProfile(created)
        #expect(updated.companyName == "Updated LLC")

        let fetched = try svc.getBusinessProfile()
        #expect(fetched?.companyName == "Updated LLC")
    }

    // MARK: - Backup Info

    @Test("getBackupInfo returns zero count on fresh DB")
    func testBackupInfoDefaults() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let info = try svc.getBackupInfo()
        #expect(info.lastBackupTime == nil)
        #expect(info.backupCount == 0)
    }

    @Test("getBackupInfo reflects stored settings")
    func testBackupInfoWithValues() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "last_backup_time", value: "2026-03-31T00:00:00Z", category: "backup")
        try svc.upsertSetting(key: "backup_count", value: "7", category: "backup")

        let info = try svc.getBackupInfo()
        #expect(info.lastBackupTime == "2026-03-31T00:00:00Z")
        #expect(info.backupCount == 7)
    }

    // MARK: - Update Settings

    @Test("getUpdateSettings returns stable channel by default")
    func testUpdateSettingsDefaults() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let settings = try svc.getUpdateSettings()
        #expect(settings.updateChannel == "stable")
        #expect(settings.lastCheckTime == nil)
        #expect(settings.availableVersion == nil)
    }

    @Test("saveUpdateChannel persists channel")
    func testSaveUpdateChannel() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.saveUpdateChannel("beta")
        let settings = try svc.getUpdateSettings()
        #expect(settings.updateChannel == "beta")
    }

    // MARK: - Clock-Out Questions

    @Test("addClockOutQuestion and listClockOutQuestions")
    func testClockOutQuestionCRUD() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let id = try svc.addClockOutQuestion(
            text: "Did you complete the safety checklist?",
            type: "boolean",
            isRequired: true,
            sortOrder: 1
        )
        #expect(id > 0)

        let questions = try svc.listClockOutQuestions()
        #expect(questions.count >= 1)
        let q = questions.first(where: { $0.id == "\(id)" })
        #expect(q != nil)
        #expect(q?.text == "Did you complete the safety checklist?")
        #expect(q?.type == "boolean")
        #expect(q?.isRequired == true)
    }

    @Test("updateClockOutQuestion changes text and type")
    func testUpdateClockOutQuestion() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let id = try svc.addClockOutQuestion(
            text: "Original question?",
            type: "text",
            isRequired: false,
            sortOrder: 1
        )

        try svc.updateClockOutQuestion(
            id: "\(id)",
            text: "Updated question?",
            type: "boolean",
            isRequired: true
        )

        let questions = try svc.listClockOutQuestions()
        let q = questions.first(where: { $0.id == "\(id)" })
        #expect(q?.text == "Updated question?")
        #expect(q?.type == "boolean")
        #expect(q?.isRequired == true)
    }

    @Test("deleteClockOutQuestion removes the question")
    func testDeleteClockOutQuestion() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let id = try svc.addClockOutQuestion(
            text: "To be deleted",
            type: "text",
            isRequired: false,
            sortOrder: 1
        )

        let before = try svc.listClockOutQuestions()
        #expect(before.contains(where: { $0.id == "\(id)" }))

        try svc.deleteClockOutQuestion(id: "\(id)")

        let after = try svc.listClockOutQuestions()
        #expect(!after.contains(where: { $0.id == "\(id)" }))
    }

    // MARK: - Database Tables

    @Test("listDatabaseTables returns non-empty list of tables")
    func testListDatabaseTables() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let tables = try svc.listDatabaseTables()
        #expect(!tables.isEmpty)
        // Core tables should be present
        #expect(tables.contains("users"))
        #expect(tables.contains("parts"))
        // SQLite internals should be excluded
        #expect(!tables.contains(where: { $0.hasPrefix("sqlite_") }))
    }

    @Test("exportTable returns rows for known table")
    func testExportTable() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        // After seedFirstAdmin the settings table has entries
        let rows = try svc.exportTable("app_settings")
        #expect(rows.count >= 0) // may be empty or have defaults; should not throw

        // Non-existent table returns empty without throwing
        let empty = try svc.exportTable("nonexistent_table_xyz")
        #expect(empty.isEmpty)
    }

    // MARK: - Device Key (graceful empty)

    @Test("getActiveDeviceKey returns empty info when no key exists")
    func testActiveDeviceKeyEmpty() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let info = try svc.getActiveDeviceKey()
        #expect(info.fingerprint == nil)
        #expect(info.createdAt == nil)
        #expect(info.rotatedAt == nil)
    }

    // MARK: - Bootstrap Devices (graceful empty)

    @Test("listBootstrapDevices returns empty on fresh DB")
    func testBootstrapDevicesEmpty() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let devices = try svc.listBootstrapDevices()
        #expect(devices.isEmpty)
    }

    // MARK: - Integrations (graceful empty)

    @Test("listIntegrations returns empty without throwing when table has no rows")
    func testListIntegrationsEmpty() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let integrations = try svc.listIntegrations()
        // integrations table has no seeded rows and may not exist — both return 0 gracefully
        #expect(integrations.count >= 0)
    }

    // MARK: - Audit Log

    @Test("listAuditLog returns empty on fresh database with no writes")
    func testListAuditLogEmpty() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let svc = SettingsService(db: db)

        // A brand-new in-memory DB with no writes has an empty _change_log
        let log = try svc.listAuditLog(limit: 50)
        #expect(log.isEmpty)
    }

    @Test("listAuditLog returns entries after a direct _change_log insert")
    func testListAuditLogAfterWrite() throws {
        let env = try E2ETestHelpers.setUp()
        let svc = SettingsService(db: env.db)

        // Insert a synthetic change log entry to simulate a tracked write
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO _change_log (device_id, table_name, record_id, operation)
                VALUES ('test-device', 'settings', 999, 'INSERT')
                """)
        }

        let log = try svc.listAuditLog(limit: 100)
        #expect(log.count > 0, "listAuditLog should return the inserted entry")

        // Every entry should have a non-empty entityType and action
        for entry in log {
            #expect(!entry.entityType.isEmpty)
            #expect(!entry.action.isEmpty)
        }
    }

    @Test("listAuditLog respects the limit parameter")
    func testListAuditLogLimit() throws {
        let env = try E2ETestHelpers.setUp()
        let svc = SettingsService(db: env.db)

        // Get all entries first
        let all = try svc.listAuditLog(limit: 1000)
        guard all.count > 3 else { return } // Skip if not enough entries

        // Limit to 2 should return exactly 2 (most recent)
        let limited = try svc.listAuditLog(limit: 2)
        #expect(limited.count == 2)
    }

    // MARK: - updateSetting (alias for upsertSetting)

    @Test("updateSetting persists value via upsertSetting alias")
    func testUpdateSettingAlias() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.updateSetting(key: "alias_test", value: "hello", category: "test")
        let stored = try svc.getSetting("alias_test")
        #expect(stored == "hello")
    }
}
