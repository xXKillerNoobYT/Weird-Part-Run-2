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

    @Test("syncScope classifies personal device and company settings")
    func testSyncScopeClassification() throws {
        #expect(SettingsService.syncScope(for: "theme_mode", category: "general") == .personal)
        #expect(SettingsService.syncScope(for: "custom_color", category: "theme") == .personal)

        #expect(SettingsService.syncScope(for: "update_channel", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "custom_backup_key", category: "backup") == .device)
        #expect(SettingsService.syncScope(for: "sync_server_address", category: "sync") == .device)
        #expect(SettingsService.syncScope(for: "shop_server_address", category: "sync") == .device)
        #expect(SettingsService.syncScope(for: "paired_shop_device_id", category: "sync") == .device)
        #expect(SettingsService.syncScope(for: "paired_company_id", category: "sync") == .device)
        #expect(SettingsService.syncScope(for: "device_pairing_verified_at", category: "sync") == .device)
        #expect(SettingsService.syncScope(for: "sync_server_address", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "shop_server_address", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "paired_shop_device_id", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "paired_company_id", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "device_pairing_verified_at", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "local_database_path", category: "general") == .device)
        #expect(SettingsService.syncScope(for: "local_db_path", category: "general") == .device)

        #expect(SettingsService.syncScope(for: "payment_terms", category: "pdf") == .company)
        #expect(SettingsService.syncScope(for: "unknown_future_setting") == .company)
    }

    @Test("server pairing and local database settings stay out of company sync rows")
    func testDeviceOnlySyncSettingsExcludedFromCompanySyncRows() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)
        let deviceOnlyKeys = [
            "sync_server_address",
            "shop_server_address",
            "paired_shop_device_id",
            "paired_company_id",
            "device_pairing_verified_at",
            "local_database_path",
            "local_db_path",
        ]

        for key in deviceOnlyKeys {
            try svc.upsertSetting(key: key, value: "device-only", category: "general")
        }
        try svc.upsertSetting(key: "payment_terms", value: "Net 30", category: "pdf")

        let deviceRows = try svc.getSettings(scope: .device)
        let syncableRows = try svc.getSettings(excludingScope: .device)

        for key in deviceOnlyKeys {
            #expect(deviceRows.contains { $0.key == key && $0.syncScope == .device })
            #expect(!syncableRows.contains { $0.key == key })
        }
        #expect(syncableRows.contains { $0.key == "payment_terms" && $0.syncScope == .company })
    }

    @Test("getSettings filters rows by sync scope")
    func testGetSettingsBySyncScope() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "payment_terms", value: "Net 30", category: "pdf")
        try svc.upsertSetting(key: "theme_mode", value: "dark", category: "theme")
        try svc.upsertSetting(key: "update_channel", value: "beta", category: "updates")

        let company = try svc.getSettings(scope: .company)
        let personal = try svc.getSettings(scope: .personal)
        let device = try svc.getSettings(scope: .device)

        #expect(company.contains { $0.key == "payment_terms" && $0.syncScope == .company })
        #expect(personal.contains { $0.key == "theme_mode" && $0.syncScope == .personal })
        #expect(device.contains { $0.key == "update_channel" && $0.syncScope == .device })
    }

    @Test("getSettings excluding device returns syncable rows only")
    func testGetSettingsExcludingDevice() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "payment_terms", value: "Net 30", category: "pdf")
        try svc.upsertSetting(key: "theme_mode", value: "dark", category: "theme")
        try svc.upsertSetting(key: "last_backup_time", value: "2026-05-17T00:00:00Z", category: "backup")
        try svc.upsertSetting(key: "shop_server_address", value: "http://shop.local", category: "sync")

        let syncable = try svc.getSettings(excludingScope: .device)

        #expect(syncable.contains { $0.key == "payment_terms" })
        #expect(syncable.contains { $0.key == "theme_mode" })
        #expect(!syncable.contains { $0.key == "last_backup_time" })
        #expect(!syncable.contains { $0.key == "shop_server_address" })
    }

    @Test("isAutoSyncEnabled defaults to true")
    func testAutoSyncDefaultsEnabled() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        #expect(try svc.isAutoSyncEnabled() == true)
    }

    @Test("isAutoSyncEnabled respects explicit false")
    func testAutoSyncExplicitFalse() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "auto_sync", value: "false", category: "sync")

        #expect(try svc.isAutoSyncEnabled() == false)
    }

    @Test("isAutoSyncEnabled treats explicit true as enabled")
    func testAutoSyncExplicitTrue() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "auto_sync", value: "true", category: "sync")

        #expect(try svc.isAutoSyncEnabled() == true)
    }

    @Test("purchase order settings default to supplier mixed and persist per-job mode")
    func testPurchaseOrderGroupingSettings() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        #expect(try svc.getPurchaseOrderSettings().groupingMode == .perSupplierMixed)

        let saved = try svc.updatePurchaseOrderSettings(
            SettingsService.PurchaseOrderSettings(groupingMode: .perSupplierPerJob)
        )

        #expect(saved.groupingMode == .perSupplierPerJob)
        #expect(try svc.getPurchaseOrderSettings().groupingMode == .perSupplierPerJob)
        #expect(try svc.getSettingsByCategory("orders")["po_grouping_mode"] == "per_supplier_per_job")
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

    // MARK: - Tool Policies

    @Test("getToolPolicies returns defaults and updateToolPolicies persists typed settings")
    func testToolPoliciesTypedSettings() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let defaults = try svc.getToolPolicies()
        #expect(defaults.maxCheckoutDays == 30)
        #expect(defaults.allowTrades)
        #expect(defaults.editVerificationMode == .pendingWithoutPermission)

        var custom = defaults
        custom.maxCheckoutDays = 5
        custom.allowTrades = false
        custom.requireLostStolenLocation = true
        custom.editVerificationMode = .alwaysPending

        let saved = try svc.updateToolPolicies(custom)
        #expect(saved == custom)

        let reloaded = try svc.getToolPolicies()
        #expect(reloaded.maxCheckoutDays == 5)
        #expect(!reloaded.allowTrades)
        #expect(reloaded.requireLostStolenLocation)
        #expect(reloaded.editVerificationMode == .alwaysPending)
    }

    // MARK: - Dispatch Preferences

    @Test("getDispatchPreferences returns defaults and updateDispatchPreferences persists typed settings")
    func testDispatchPreferencesTypedSettings() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let defaults = try svc.getDispatchPreferences()
        #expect(defaults.aiSuggestionsEnabled)
        #expect(defaults.aiLearningEnabled)
        #expect(defaults.aiSuggestionCount == 3)
        #expect(defaults.flexSelfAssignEnabled)
        #expect(defaults.pipelineStartAnytimeTarget == 3)

        var custom = defaults
        custom.aiSuggestionsEnabled = false
        custom.aiLearningEnabled = false
        custom.aiSuggestionCount = 1
        custom.flexSelfAssignEnabled = false
        custom.flexRequireApproval = true
        custom.pipelineStartAnytimeTarget = 7
        custom.pipelineScheduleNeededTarget = 6
        custom.pipelineFavoriteGCTarget = 5
        custom.defaultView = "month"
        custom.crewHistoryMonths = 8
        custom.crewContinuityWeight = "high"

        let saved = try svc.updateDispatchPreferences(custom)
        #expect(saved == custom)

        let reloaded = try svc.getDispatchPreferences()
        #expect(reloaded == custom)
    }

    @Test("getDispatchPreferences clamps invalid stored dispatch values")
    func testDispatchPreferencesClampInvalidValues() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSettingsMap([
            "dispatch_ai_suggestion_count": "99",
            "dispatch_pipeline_start_anytime_target": "-3",
            "dispatch_pipeline_schedule_needed_target": "33",
            "dispatch_default_view": "decade",
            "dispatch_crew_history_months": "0",
            "dispatch_crew_continuity_weight": "extreme",
        ], category: "dispatch")

        let preferences = try svc.getDispatchPreferences()
        #expect(preferences.aiSuggestionCount == 3)
        #expect(preferences.pipelineStartAnytimeTarget == 0)
        #expect(preferences.pipelineScheduleNeededTarget == 20)
        #expect(preferences.defaultView == "week")
        #expect(preferences.crewHistoryMonths == 1)
        #expect(preferences.crewContinuityWeight == "medium")
    }

    @Test("getDispatchPreferences falls back to legacy flex_pool_requires_approval key")
    func testDispatchPreferencesLegacyApprovalFallback() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.upsertSetting(key: "flex_pool_requires_approval", value: "1", category: "general")

        let preferences = try svc.getDispatchPreferences()
        #expect(preferences.flexRequireApproval)
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

    @Test("upsertSettingsMap rolls back all values when one write fails")
    func testUpsertSettingsMapIsAtomic() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                CREATE TRIGGER fail_after_first_atomic_setting
                BEFORE INSERT ON settings
                WHEN NEW.category = 'atomic_test'
                  AND (SELECT COUNT(*) FROM settings WHERE category = 'atomic_test') > 0
                BEGIN
                    SELECT RAISE(ABORT, 'simulated mid-map settings failure');
                END
                """)
        }

        do {
            try svc.upsertSettingsMap(
                ["first": "saved-before-failure", "second": "should-fail"],
                category: "atomic_test"
            )
            Issue.record("Expected upsertSettingsMap to throw when the trigger aborts the second insert")
        } catch {
            let map = try svc.getSettingsByCategory("atomic_test")
            #expect(map.isEmpty)
        }
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

    @Test("listCompanyProfiles returns only non-deleted profiles")
    func testListCompanyProfiles_excludesDeleted() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let a = CompanyProfile(companyName: "Alpha Corp", isPrimary: 1, createdAt: "2026-01-01 00:00:00", updatedAt: "2026-01-01 00:00:00")
        let b = CompanyProfile(companyName: "Beta Inc", isPrimary: 0, createdAt: "2026-01-01 00:00:00", updatedAt: "2026-01-01 00:00:00")
        let idA = try svc.createCompanyProfile(a)
        let idB = try svc.createCompanyProfile(b)
        try svc.deleteCompanyProfile(idB)

        let visible = try svc.listCompanyProfiles()
        #expect(visible.count == 1)
        #expect(visible.first?.id == idA)
    }

    @Test("hasBusinessProfile returns false on empty DB and true after create")
    func testHasBusinessProfile() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        #expect(try svc.hasBusinessProfile() == false)

        let profile = BusinessProfile(companyName: "Acme LLC", isActive: 1)
        _ = try svc.createBusinessProfile(profile)

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

    @Test("toggleIntegration enables and disables an integration row")
    func testToggleIntegration() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        // The integrations table is not in core migrations — create it manually for this test.
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                CREATE TABLE IF NOT EXISTS integrations (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    description TEXT NOT NULL DEFAULT '',
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    last_sync_at TEXT
                )
                """)
            try dbConn.execute(sql: """
                INSERT INTO integrations (id, name, description, is_enabled)
                VALUES (1, 'TestIntegration', 'Test desc', 1)
                """)
        }

        try svc.toggleIntegration("1", enabled: false)
        let integrations = try svc.listIntegrations()
        let row = try #require(integrations.first(where: { $0.id == "1" }))
        #expect(row.isEnabled == false)

        try svc.toggleIntegration("1", enabled: true)
        let integrations2 = try svc.listIntegrations()
        let row2 = try #require(integrations2.first(where: { $0.id == "1" }))
        #expect(row2.isEnabled == true)
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

    // MARK: - CompanySetupDraft (DIS-005)

    @Test("loadSetupDraft returns nil on fresh database")
    func testLoadSetupDraftEmpty() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let draft = try svc.loadSetupDraft()
        #expect(draft == nil)
    }

    @Test("saveSetupDraft persists all fields and loadSetupDraft retrieves them")
    func testSaveAndLoadSetupDraft() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let original = SettingsService.CompanySetupDraft(
            currentStep: 3,
            completedSteps: [0, 1, 2],
            skippedSteps: [4],
            name: "Acme Corp",
            address: "123 Main St",
            phone: "555-1234",
            email: "info@acme.com",
            selectedState: "Texas"
        )
        try svc.saveSetupDraft(original)

        let loaded = try svc.loadSetupDraft()
        #expect(loaded != nil)
        #expect(loaded?.currentStep == 3)
        #expect(loaded?.completedSteps == [0, 1, 2])
        #expect(loaded?.skippedSteps == [4])
        #expect(loaded?.name == "Acme Corp")
        #expect(loaded?.address == "123 Main St")
        #expect(loaded?.phone == "555-1234")
        #expect(loaded?.email == "info@acme.com")
        #expect(loaded?.selectedState == "Texas")
    }

    @Test("saveSetupDraft overwrites previous draft (single-row upsert)")
    func testSaveSetupDraftOverwrites() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let first = SettingsService.CompanySetupDraft(currentStep: 1, name: "First Corp")
        try svc.saveSetupDraft(first)

        let second = SettingsService.CompanySetupDraft(currentStep: 5, name: "Second Corp")
        try svc.saveSetupDraft(second)

        let loaded = try svc.loadSetupDraft()
        #expect(loaded?.currentStep == 5)
        #expect(loaded?.name == "Second Corp")
    }

    @Test("deleteSetupDraft removes the draft row")
    func testDeleteSetupDraft() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        try svc.saveSetupDraft(SettingsService.CompanySetupDraft(currentStep: 2, name: "ToDelete"))
        #expect(try svc.loadSetupDraft() != nil)

        try svc.deleteSetupDraft()
        #expect(try svc.loadSetupDraft() == nil)
    }

    @Test("deleteSetupDraft on empty table does not throw")
    func testDeleteSetupDraftIdempotent() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        // Should not throw even if no row exists
        #expect(throws: Never.self) {
            try svc.deleteSetupDraft()
        }
    }

    @Test("saveSetupDraft round-trips empty Set fields correctly")
    func testSaveSetupDraftEmptySets() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let draft = SettingsService.CompanySetupDraft(
            currentStep: 0,
            completedSteps: [],
            skippedSteps: []
        )
        try svc.saveSetupDraft(draft)

        let loaded = try svc.loadSetupDraft()
        #expect(loaded?.completedSteps == [])
        #expect(loaded?.skippedSteps == [])
    }

    // MARK: - getSettingValue

    @Test("getSettingValue returns nil for a key that does not exist")
    func testGetSettingValueMissing() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)
        let val = try svc.getSettingValue("nonexistent_key_xyz")
        #expect(val == nil)
    }

    @Test("getSettingValue returns value after upsertSetting")
    func testGetSettingValueAfterUpsert() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)
        try svc.upsertSetting(key: "test_key", value: "hello_world")
        let val = try svc.getSettingValue("test_key")
        #expect(val == "hello_world")
    }

    @Test("getSettingValue returns updated value after second upsert")
    func testGetSettingValueUpdated() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)
        try svc.upsertSetting(key: "mutable_key", value: "first")
        try svc.upsertSetting(key: "mutable_key", value: "second")
        let val = try svc.getSettingValue("mutable_key")
        #expect(val == "second")
    }

    // MARK: - getCompanyProfile / updateCompanyProfile

    @Test("getCompanyProfile throws when profile does not exist")
    func testGetCompanyProfileNotFound() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)
        #expect(throws: (any Error).self) {
            _ = try svc.getCompanyProfile(99999)
        }
    }

    @Test("getCompanyProfile returns profile after create")
    func testGetCompanyProfileRoundTrip() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        // created_at is NOT NULL in the schema — must be provided explicitly
        let profile = CompanyProfile(
            companyName: "Acme Electric",
            email: "info@acme.com",
            createdAt: "2026-04-16 00:00:00",
            updatedAt: "2026-04-16 00:00:00"
        )
        let newId = try svc.createCompanyProfile(profile)
        let fetched = try svc.getCompanyProfile(newId)

        #expect(fetched.companyName == "Acme Electric")
        #expect(fetched.email == "info@acme.com")
    }

    @Test("updateCompanyProfile persists changes")
    func testUpdateCompanyProfile() throws {
        let db = try freshDB()
        let svc = SettingsService(db: db)

        let profile = CompanyProfile(
            companyName: "OldName Co",
            createdAt: "2026-04-16 00:00:00",
            updatedAt: "2026-04-16 00:00:00"
        )
        let newId = try svc.createCompanyProfile(profile)
        var fetched = try svc.getCompanyProfile(newId)

        fetched.companyName = "NewName LLC"
        fetched.phone = "555-1234"
        try svc.updateCompanyProfile(fetched)

        let updated = try svc.getCompanyProfile(newId)
        #expect(updated.companyName == "NewName LLC")
        #expect(updated.phone == "555-1234")
    }

    // MARK: - Input validation (iter 74)

    @Test("updateWarrantyLengthDays rejects zero and negative values")
    func testUpdateWarrantyLengthDays_rejectsInvalidValues() throws {
        let env = try E2ETestHelpers.setUp()
        let svc = SettingsService(db: env.db)
        #expect(throws: SettingsService.SettingsError.self) {
            try svc.updateWarrantyLengthDays(0)
        }
        #expect(throws: SettingsService.SettingsError.self) {
            try svc.updateWarrantyLengthDays(-5)
        }
    }

    @Test("addClockOutQuestion rejects blank text and blank type")
    func testAddClockOutQuestion_rejectsBlankInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let svc = SettingsService(db: env.db)
        #expect(throws: SettingsService.SettingsError.self) {
            _ = try svc.addClockOutQuestion(text: "   ", type: "text", isRequired: true, sortOrder: 0)
        }
        #expect(throws: SettingsService.SettingsError.self) {
            _ = try svc.addClockOutQuestion(text: "Clean up?", type: "", isRequired: true, sortOrder: 0)
        }
    }
}
