import Foundation
import GRDB

public enum PurchaseOrderGroupingMode: String, Codable, Sendable, CaseIterable {
    case perSupplierMixed = "per_supplier_mixed"
    case perSupplierPerJob = "per_supplier_per_job"

    public var displayName: String {
        switch self {
        case .perSupplierMixed:
            return "Per supplier mixed"
        case .perSupplierPerJob:
            return "Per supplier per job"
        }
    }
}

/// Local Settings Service — theme, app configuration, company profiles, billing/pay cycles.
///
/// Settings are stored as key-value rows in the `settings` table;
/// compound settings (theme, pdf, billing) use a shared category
/// with one row per field.
///
/// Ported from: `src/local/services/settings-service.ts`
///
/// Sync scope contract for Phase 11 sync:
/// - `.company` settings participate in company-wide sync.
/// - `.personal` settings participate in per-user sync.
/// - `.device` settings are local-only and excluded from sync payloads.
///
/// Tracked: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/258

public final class SettingsService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Types

    public enum SyncScope: String, CaseIterable, Sendable {
        case company
        case personal
        case device
    }

    public struct SettingRow: Sendable, Equatable {
        public let key: String
        public let value: String
        public let category: String
        public let syncScope: SyncScope
    }

    public struct ThemeSettings: Codable, Sendable {
        public var themeMode: String   // "light", "dark", "system"
        public var primaryColor: String
        public var fontFamily: String

        public init(themeMode: String, primaryColor: String, fontFamily: String) {
            self.themeMode = themeMode
            self.primaryColor = primaryColor
            self.fontFamily = fontFamily
        }

        public static let defaults = ThemeSettings(
            themeMode: "system",
            primaryColor: "#2563eb",
            fontFamily: "Inter"
        )
    }

    public struct PDFSettings: Codable, Sendable {
        public var accentColor: String
        public var showUnitPrices: Bool
        public var showExtended: Bool
        public var footerText: String
        public var paymentTerms: String
        public var deliveryNotes: String

        public init(accentColor: String, showUnitPrices: Bool, showExtended: Bool, footerText: String, paymentTerms: String, deliveryNotes: String) {
            self.accentColor = accentColor
            self.showUnitPrices = showUnitPrices
            self.showExtended = showExtended
            self.footerText = footerText
            self.paymentTerms = paymentTerms
            self.deliveryNotes = deliveryNotes
        }

        public static let defaults = PDFSettings(
            accentColor: "#2563eb",
            showUnitPrices: true,
            showExtended: true,
            footerText: "",
            paymentTerms: "Net 30",
            deliveryNotes: ""
        )
    }

    public struct BillingCycleSettings: Codable, Sendable {
        public var cycleType: String   // "monthly", "weekly", etc.
        public var startDay: Int

        public init(cycleType: String, startDay: Int) {
            self.cycleType = cycleType
            self.startDay = startDay
        }

        public static let defaults = BillingCycleSettings(cycleType: "monthly", startDay: 1)
    }

    public struct PayPeriodSettings: Codable, Sendable {
        public var periodType: String  // "biweekly", "weekly", "monthly"
        public var startDay: Int

        public init(periodType: String, startDay: Int) {
            self.periodType = periodType
            self.startDay = startDay
        }

        public static let defaults = PayPeriodSettings(periodType: "biweekly", startDay: 1)
    }

    public struct PurchaseOrderSettings: Codable, Sendable {
        public var groupingMode: PurchaseOrderGroupingMode

        public init(groupingMode: PurchaseOrderGroupingMode) {
            self.groupingMode = groupingMode
        }

        public static let defaults = PurchaseOrderSettings(groupingMode: .perSupplierMixed)
    }

    /// Typed tool checkout/return/maintenance/trade/lost-stolen/edit-verification policy.
    ///
    /// Persisted as `tool_policy_*` key-value rows under the `tool_policy` category
    /// (see `getSettingsByCategory`/`upsertSettingsMap`). `ToolsService` reads these
    /// values to enforce checkout duration, condition requirements, trade rules,
    /// lost/stolen handling, and edit verification behavior. See issue #438.
    public struct ToolPolicySettings: Codable, Equatable, Sendable {
        public enum EditVerificationMode: String, Codable, CaseIterable, Hashable, Sendable {
            case pendingWithoutPermission = "pending_without_permission"
            case alwaysPending = "always_pending"
            case directEdits = "direct_edits"
        }

        public var maxCheckoutDays: Int
        public var overdueNotificationDays: Int
        public var autoExtendOnActiveJob: Bool
        public var requireCheckoutCondition: Bool
        public var requireReturnCondition: Bool
        public var requireDamagePhoto: Bool
        public var maintenanceAfterCheckouts: Int
        public var maintenanceReminderDays: Int
        public var allowTrades: Bool
        public var tradeTimeoutDays: Int
        public var requireTradeCondition: Bool
        public var allowLostStolenReports: Bool
        public var requireLostStolenLocation: Bool
        public var closeCheckoutOnLostStolen: Bool
        public var editVerificationMode: EditVerificationMode

        public init(
            maxCheckoutDays: Int,
            overdueNotificationDays: Int,
            autoExtendOnActiveJob: Bool,
            requireCheckoutCondition: Bool,
            requireReturnCondition: Bool,
            requireDamagePhoto: Bool,
            maintenanceAfterCheckouts: Int,
            maintenanceReminderDays: Int,
            allowTrades: Bool,
            tradeTimeoutDays: Int,
            requireTradeCondition: Bool,
            allowLostStolenReports: Bool,
            requireLostStolenLocation: Bool,
            closeCheckoutOnLostStolen: Bool,
            editVerificationMode: EditVerificationMode
        ) {
            self.maxCheckoutDays = maxCheckoutDays
            self.overdueNotificationDays = overdueNotificationDays
            self.autoExtendOnActiveJob = autoExtendOnActiveJob
            self.requireCheckoutCondition = requireCheckoutCondition
            self.requireReturnCondition = requireReturnCondition
            self.requireDamagePhoto = requireDamagePhoto
            self.maintenanceAfterCheckouts = maintenanceAfterCheckouts
            self.maintenanceReminderDays = maintenanceReminderDays
            self.allowTrades = allowTrades
            self.tradeTimeoutDays = tradeTimeoutDays
            self.requireTradeCondition = requireTradeCondition
            self.allowLostStolenReports = allowLostStolenReports
            self.requireLostStolenLocation = requireLostStolenLocation
            self.closeCheckoutOnLostStolen = closeCheckoutOnLostStolen
            self.editVerificationMode = editVerificationMode
        }

        public static let defaults = ToolPolicySettings(
            maxCheckoutDays: 30,
            overdueNotificationDays: 7,
            autoExtendOnActiveJob: true,
            requireCheckoutCondition: true,
            requireReturnCondition: true,
            requireDamagePhoto: false,
            maintenanceAfterCheckouts: 50,
            maintenanceReminderDays: 14,
            allowTrades: true,
            tradeTimeoutDays: 7,
            requireTradeCondition: true,
            allowLostStolenReports: true,
            requireLostStolenLocation: false,
            closeCheckoutOnLostStolen: true,
            editVerificationMode: .pendingWithoutPermission
        )

        public static func fromMap(_ map: [String: String]) -> ToolPolicySettings {
            let defaults = ToolPolicySettings.defaults
            var parser = SettingsValueParserCore()
            return ToolPolicySettings(
                maxCheckoutDays: parser.positiveInt(map["tool_policy_max_checkout_days"], defaultValue: defaults.maxCheckoutDays),
                overdueNotificationDays: parser.positiveInt(map["tool_policy_overdue_notification_days"], defaultValue: defaults.overdueNotificationDays),
                autoExtendOnActiveJob: parser.bool(map["tool_policy_auto_extend_active_job"], defaultValue: defaults.autoExtendOnActiveJob),
                requireCheckoutCondition: parser.bool(map["tool_policy_require_checkout_condition"], defaultValue: defaults.requireCheckoutCondition),
                requireReturnCondition: parser.bool(map["tool_policy_require_return_condition"], defaultValue: defaults.requireReturnCondition),
                requireDamagePhoto: parser.bool(map["tool_policy_require_damage_photo"], defaultValue: defaults.requireDamagePhoto),
                maintenanceAfterCheckouts: parser.positiveInt(map["tool_policy_maintenance_after_checkouts"], defaultValue: defaults.maintenanceAfterCheckouts),
                maintenanceReminderDays: parser.positiveInt(map["tool_policy_maintenance_reminder_days"], defaultValue: defaults.maintenanceReminderDays),
                allowTrades: parser.bool(map["tool_policy_allow_trades"], defaultValue: defaults.allowTrades),
                tradeTimeoutDays: parser.positiveInt(map["tool_policy_trade_timeout_days"], defaultValue: defaults.tradeTimeoutDays),
                requireTradeCondition: parser.bool(map["tool_policy_require_trade_condition"], defaultValue: defaults.requireTradeCondition),
                allowLostStolenReports: parser.bool(map["tool_policy_allow_lost_stolen_reports"], defaultValue: defaults.allowLostStolenReports),
                requireLostStolenLocation: parser.bool(map["tool_policy_require_lost_stolen_location"], defaultValue: defaults.requireLostStolenLocation),
                closeCheckoutOnLostStolen: parser.bool(map["tool_policy_close_checkout_on_lost_stolen"], defaultValue: defaults.closeCheckoutOnLostStolen),
                editVerificationMode: EditVerificationMode(rawValue: map["tool_policy_edit_verification_mode"] ?? "") ?? defaults.editVerificationMode
            )
        }

        public var storageMap: [String: String] {
            [
                "tool_policy_max_checkout_days": String(maxCheckoutDays),
                "tool_policy_overdue_notification_days": String(overdueNotificationDays),
                "tool_policy_auto_extend_active_job": autoExtendOnActiveJob ? "true" : "false",
                "tool_policy_require_checkout_condition": requireCheckoutCondition ? "true" : "false",
                "tool_policy_require_return_condition": requireReturnCondition ? "true" : "false",
                "tool_policy_require_damage_photo": requireDamagePhoto ? "true" : "false",
                "tool_policy_maintenance_after_checkouts": String(maintenanceAfterCheckouts),
                "tool_policy_maintenance_reminder_days": String(maintenanceReminderDays),
                "tool_policy_allow_trades": allowTrades ? "true" : "false",
                "tool_policy_trade_timeout_days": String(tradeTimeoutDays),
                "tool_policy_require_trade_condition": requireTradeCondition ? "true" : "false",
                "tool_policy_allow_lost_stolen_reports": allowLostStolenReports ? "true" : "false",
                "tool_policy_require_lost_stolen_location": requireLostStolenLocation ? "true" : "false",
                "tool_policy_close_checkout_on_lost_stolen": closeCheckoutOnLostStolen ? "true" : "false",
                "tool_policy_edit_verification_mode": editVerificationMode.rawValue,
            ]
        }

        /// Local (core-side) value parser mirroring the app-side `SettingsValueParser`
        /// used by `IOSToolPoliciesPage`. Kept private/minimal here since core has no
        /// dependency on the app target's settings-hydration error type — malformed
        /// stored values simply fall back to defaults rather than surfacing a load error,
        /// matching the pre-existing `fromMap` contract used by every other typed
        /// settings struct in this file (e.g. `getTheme`, `getBillingCycle`).
        private struct SettingsValueParserCore {
            mutating func positiveInt(_ raw: String?, defaultValue: Int) -> Int {
                guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
                    return defaultValue
                }
                return value
            }

            mutating func bool(_ raw: String?, defaultValue: Bool) -> Bool {
                guard let raw else { return defaultValue }
                switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes": return true
                case "false", "0", "no": return false
                default: return defaultValue
                }
            }
        }
    }

    public struct DispatchPreferenceSettings: Codable, Equatable, Sendable {
        public var aiSuggestionsEnabled: Bool
        public var aiLearningEnabled: Bool
        public var showConfidenceScores: Bool
        public var aiSuggestionCount: Int
        public var flexSelfAssignEnabled: Bool
        public var flexRequireApproval: Bool
        public var pipelineStartAnytimeTarget: Int
        public var pipelineScheduleNeededTarget: Int
        public var pipelineFavoriteGCTarget: Int
        public var defaultView: String
        public var crewHistoryMonths: Int
        public var crewContinuityWeight: String

        public init(
            aiSuggestionsEnabled: Bool,
            aiLearningEnabled: Bool,
            showConfidenceScores: Bool,
            aiSuggestionCount: Int,
            flexSelfAssignEnabled: Bool,
            flexRequireApproval: Bool,
            pipelineStartAnytimeTarget: Int,
            pipelineScheduleNeededTarget: Int,
            pipelineFavoriteGCTarget: Int,
            defaultView: String,
            crewHistoryMonths: Int,
            crewContinuityWeight: String
        ) {
            self.aiSuggestionsEnabled = aiSuggestionsEnabled
            self.aiLearningEnabled = aiLearningEnabled
            self.showConfidenceScores = showConfidenceScores
            self.aiSuggestionCount = aiSuggestionCount
            self.flexSelfAssignEnabled = flexSelfAssignEnabled
            self.flexRequireApproval = flexRequireApproval
            self.pipelineStartAnytimeTarget = pipelineStartAnytimeTarget
            self.pipelineScheduleNeededTarget = pipelineScheduleNeededTarget
            self.pipelineFavoriteGCTarget = pipelineFavoriteGCTarget
            self.defaultView = defaultView
            self.crewHistoryMonths = crewHistoryMonths
            self.crewContinuityWeight = crewContinuityWeight
        }

        public static let defaults = DispatchPreferenceSettings(
            aiSuggestionsEnabled: true,
            aiLearningEnabled: true,
            showConfidenceScores: false,
            aiSuggestionCount: 3,
            flexSelfAssignEnabled: true,
            flexRequireApproval: false,
            pipelineStartAnytimeTarget: 3,
            pipelineScheduleNeededTarget: 2,
            pipelineFavoriteGCTarget: 1,
            defaultView: "week",
            crewHistoryMonths: 3,
            crewContinuityWeight: "medium"
        )

        public static func fromMap(_ map: [String: String]) -> DispatchPreferenceSettings {
            let defaults = DispatchPreferenceSettings.defaults
            return DispatchPreferenceSettings(
                aiSuggestionsEnabled: bool(map["dispatch_ai_suggestions_enabled"], defaultValue: defaults.aiSuggestionsEnabled),
                aiLearningEnabled: bool(map["dispatch_ai_learning_enabled"], defaultValue: defaults.aiLearningEnabled),
                showConfidenceScores: bool(map["dispatch_show_confidence_scores"], defaultValue: defaults.showConfidenceScores),
                aiSuggestionCount: clampedInt(map["dispatch_ai_suggestion_count"], defaultValue: defaults.aiSuggestionCount, min: 1, max: 3),
                flexSelfAssignEnabled: bool(map["dispatch_flex_self_assign_enabled"], defaultValue: defaults.flexSelfAssignEnabled),
                flexRequireApproval: bool(
                    map["dispatch_flex_require_approval"] ?? map["flex_pool_requires_approval"],
                    defaultValue: defaults.flexRequireApproval
                ),
                pipelineStartAnytimeTarget: clampedInt(map["dispatch_pipeline_start_anytime_target"], defaultValue: defaults.pipelineStartAnytimeTarget, min: 0, max: 20),
                pipelineScheduleNeededTarget: clampedInt(map["dispatch_pipeline_schedule_needed_target"], defaultValue: defaults.pipelineScheduleNeededTarget, min: 0, max: 20),
                pipelineFavoriteGCTarget: clampedInt(map["dispatch_pipeline_favorite_gc_target"], defaultValue: defaults.pipelineFavoriteGCTarget, min: 0, max: 20),
                defaultView: allowed(map["dispatch_default_view"], defaultValue: defaults.defaultView, allowedValues: Set(["day", "week", "month"])),
                crewHistoryMonths: clampedInt(map["dispatch_crew_history_months"], defaultValue: defaults.crewHistoryMonths, min: 1, max: 12),
                crewContinuityWeight: allowed(map["dispatch_crew_continuity_weight"], defaultValue: defaults.crewContinuityWeight, allowedValues: Set(["low", "medium", "high"]))
            )
        }

        public var storageMap: [String: String] {
            [
                "dispatch_ai_suggestions_enabled": aiSuggestionsEnabled ? "true" : "false",
                "dispatch_ai_learning_enabled": aiLearningEnabled ? "true" : "false",
                "dispatch_show_confidence_scores": showConfidenceScores ? "true" : "false",
                "dispatch_ai_suggestion_count": String(aiSuggestionCount),
                "dispatch_flex_self_assign_enabled": flexSelfAssignEnabled ? "true" : "false",
                "dispatch_flex_require_approval": flexRequireApproval ? "true" : "false",
                "dispatch_pipeline_start_anytime_target": String(pipelineStartAnytimeTarget),
                "dispatch_pipeline_schedule_needed_target": String(pipelineScheduleNeededTarget),
                "dispatch_pipeline_favorite_gc_target": String(pipelineFavoriteGCTarget),
                "dispatch_default_view": defaultView,
                "dispatch_crew_history_months": String(crewHistoryMonths),
                "dispatch_crew_continuity_weight": crewContinuityWeight,
            ]
        }

        private static func bool(_ raw: String?, defaultValue: Bool) -> Bool {
            guard let raw else { return defaultValue }
            switch raw.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return defaultValue
            }
        }

        private static func clampedInt(_ raw: String?, defaultValue: Int, min: Int, max: Int) -> Int {
            guard let raw, let value = Int(raw) else { return defaultValue }
            return Swift.max(min, Swift.min(max, value))
        }

        private static func allowed(_ raw: String?, defaultValue: String, allowedValues: Set<String>) -> String {
            guard let raw, allowedValues.contains(raw) else { return defaultValue }
            return raw
        }
    }
    // MARK: - Helpers

    /// Read a single setting value by key. Returns nil when not found.
    public func getSettingValue(_ key: String) throws -> String? {
        try db.writer.read { dbConnection in
            try String.fetchOne(
                dbConnection,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }

    /// Insert-or-update a setting row.
    public func upsertSetting(key: String, value: String, category: String = "general") throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: """
                    INSERT INTO settings (key, value, category, updated_at)
                    VALUES (?, ?, ?, datetime('now'))
                    ON CONFLICT(key) DO UPDATE SET value = ?, category = ?, updated_at = datetime('now')
                    """,
                arguments: [key, value, category, value, category]
            )
        }
    }

    /// Read all setting rows for a category and return as a key->value map.
    public func getSettingsByCategory(_ category: String) throws -> [String: String] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: "SELECT key, value FROM settings WHERE category = ?",
                arguments: [category]
            )
            var map: [String: String] = [:]
            for row in rows {
                let key: String = row["key"]
                let value: String = row["value"]
                map[key] = value
            }
            return map
        }
    }

    /// Whether automatic background/launch sync is enabled.
    ///
    /// Missing settings default to enabled so existing configured sync installs
    /// keep their prior behavior; only an explicit "false" opts out.
    public func isAutoSyncEnabled() throws -> Bool {
        let value = try getSettingsByCategory("sync")["auto_sync"]
        return value != "false"
    }

    /// Bulk upsert a dictionary of key->value pairs under one category.
    ///
    /// This must be a single database write transaction so a mid-map failure cannot
    /// leave only some keys persisted. Several settings screens save compound
    /// values through this method and expect the category to move between coherent
    /// snapshots, not partially-updated field sets.
    public func upsertSettingsMap(_ data: [String: String], category: String) throws {
        try db.writer.write { dbConnection in
            for (key, value) in data {
                try dbConnection.execute(
                    sql: """
                        INSERT INTO settings (key, value, category, updated_at)
                        VALUES (?, ?, ?, datetime('now'))
                        ON CONFLICT(key) DO UPDATE SET value = ?, category = ?, updated_at = datetime('now')
                        """,
                    arguments: [key, value, category, value, category]
                )
            }
        }
    }

    /// Canonical settings sync classifier.
    ///
    /// Key-specific rules win over category rules so legacy rows with `general`
    /// category can still be scoped safely. Unknown settings default to `.company`
    /// because company-visible configuration is the safer sync default than silently
    /// dropping operational state.
    public static func syncScope(for key: String, category: String? = nil) -> SyncScope {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCategory = (category ?? "general")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if deviceSettingKeys.contains(normalizedKey) || deviceSettingCategories.contains(normalizedCategory) {
            return .device
        }
        if personalSettingKeys.contains(normalizedKey) || personalSettingCategories.contains(normalizedCategory) {
            return .personal
        }
        return .company
    }

    /// Return flat setting rows classified for sync payload construction.
    public func getSettings(scope: SyncScope) throws -> [SettingRow] {
        try getSettingRows().filter { $0.syncScope == scope }
    }

    /// Return flat setting rows except the requested scope. Use `.device` to build
    /// syncable settings while excluding local-only device state.
    public func getSettings(excludingScope excludedScope: SyncScope) throws -> [SettingRow] {
        try getSettingRows().filter { $0.syncScope != excludedScope }
    }

    private func getSettingRows() throws -> [SettingRow] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: "SELECT key, value, category FROM settings ORDER BY category, key"
            )
            return rows.map { row in
                let key: String = row["key"]
                let value: String = row["value"] ?? ""
                let category: String = row["category"] ?? "general"
                return SettingRow(
                    key: key,
                    value: value,
                    category: category,
                    syncScope: Self.syncScope(for: key, category: category)
                )
            }
        }
    }

    // MARK: - Theme

    /// Get current theme settings, filling in defaults for any missing keys.
    public func getTheme() throws -> ThemeSettings {
        let map = try getSettingsByCategory("theme")
        return ThemeSettings(
            themeMode: map["theme_mode"] ?? ThemeSettings.defaults.themeMode,
            primaryColor: map["primary_color"] ?? ThemeSettings.defaults.primaryColor,
            fontFamily: map["font_family"] ?? ThemeSettings.defaults.fontFamily
        )
    }

    /// Update theme settings.
    public func updateTheme(_ theme: ThemeSettings) throws -> ThemeSettings {
        try upsertSettingsMap([
            "theme_mode": theme.themeMode,
            "primary_color": theme.primaryColor,
            "font_family": theme.fontFamily,
        ], category: "theme")
        return try getTheme()
    }

    // MARK: - Dispatch Preferences

    /// Get dispatch preferences, filling in defaults for any missing keys.
    ///
    /// Falls back to the legacy `flex_pool_requires_approval` key (stored outside
    /// the `dispatch` category by older builds) when the typed key is absent, so
    /// upgrading installs keep their previously saved approval requirement.
    public func getDispatchPreferences() throws -> DispatchPreferenceSettings {
        var map = try getSettingsByCategory("dispatch")
        if map["dispatch_flex_require_approval"] == nil,
           let legacyApproval = try getSettingValue("flex_pool_requires_approval") {
            map["flex_pool_requires_approval"] = legacyApproval
        }
        return DispatchPreferenceSettings.fromMap(map)
    }

    /// Update dispatch preferences.
    public func updateDispatchPreferences(_ preferences: DispatchPreferenceSettings) throws -> DispatchPreferenceSettings {
        try upsertSettingsMap(preferences.storageMap, category: "dispatch")
        return try getDispatchPreferences()
    }

    // MARK: - Generic Settings

    /// Get all settings grouped by category.
    public func getAllSettings() throws -> [String: [String: String]] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(
                dbConnection,
                sql: "SELECT key, value, category FROM settings ORDER BY category, key"
            )
            var grouped: [String: [String: String]] = [:]
            for row in rows {
                let cat: String = row["category"] ?? "general"
                let key: String = row["key"]
                let value: String = row["value"]
                if grouped[cat] == nil { grouped[cat] = [:] }
                grouped[cat]?[key] = value
            }
            return grouped
        }
    }

    /// Get a single setting value by key.
    public func getSetting(_ key: String) throws -> String? {
        try getSettingValue(key)
    }

    /// Upsert a single setting by key.
    public func updateSetting(key: String, value: String, category: String = "general") throws {
        try upsertSetting(key: key, value: value, category: category)
    }

    // MARK: - Purchase Orders

    public func getPurchaseOrderSettings() throws -> PurchaseOrderSettings {
        let rawValue = try getSettingValue("po_grouping_mode")
        return PurchaseOrderSettings(
            groupingMode: PurchaseOrderGroupingMode(rawValue: rawValue ?? "") ?? PurchaseOrderSettings.defaults.groupingMode
        )
    }

    @discardableResult
    public func updatePurchaseOrderSettings(_ settings: PurchaseOrderSettings) throws -> PurchaseOrderSettings {
        try upsertSetting(key: "po_grouping_mode", value: settings.groupingMode.rawValue, category: "orders")
        return try getPurchaseOrderSettings()
    }

    // MARK: - Tool Policies

    /// Get tool checkout/return/maintenance/trade/lost-stolen/edit-verification policy,
    /// filling in defaults for any missing or invalid keys.
    public func getToolPolicies() throws -> ToolPolicySettings {
        ToolPolicySettings.fromMap(try getSettingsByCategory("tool_policy"))
    }

    /// Update tool policy settings.
    @discardableResult
    public func updateToolPolicies(_ policies: ToolPolicySettings) throws -> ToolPolicySettings {
        try upsertSettingsMap(policies.storageMap, category: "tool_policy")
        return try getToolPolicies()
    }

    // MARK: - Warranty

    /// Get default warranty length in days. Falls back to 365.
    public func getWarrantyLengthDays() throws -> Int {
        guard let val = try getSettingValue("warranty_length_days"),
              let days = Int(val) else { return 365 }
        return days
    }

    /// Update default warranty length in days. Must be a positive whole-day count —
    /// zero/negative would set warranty_end at or before warranty_start, making the
    /// warranty immediately expired or producing an impossible backward date range.
    public func updateWarrantyLengthDays(_ days: Int) throws {
        guard days > 0 else {
            throw SettingsError.invalidValue("Warranty length must be positive (got \(days))")
        }
        try upsertSetting(key: "warranty_length_days", value: String(days), category: "general")
    }

    // MARK: - Company Profiles

    /// List all company profiles (excludes soft-deleted).
    public func listCompanyProfiles() throws -> [CompanyProfile] {
        try db.writer.read { dbConnection in
            try CompanyProfile.fetchAll(
                dbConnection,
                sql: "SELECT * FROM company_profiles WHERE deleted_at IS NULL ORDER BY name ASC"
            )
        }
    }

    /// Get a single company profile by ID.
    public func getCompanyProfile(_ id: Int64) throws -> CompanyProfile {
        let profile = try db.writer.read { dbConnection in
            try CompanyProfile.fetchOne(
                dbConnection,
                sql: "SELECT * FROM company_profiles WHERE id = ?",
                arguments: [id]
            )
        }
        guard let profile else {
            throw SettingsError.companyProfileNotFound(id)
        }
        return profile
    }

    /// Create a new company profile. Returns the new ID.
    @discardableResult
    public func createCompanyProfile(_ profile: CompanyProfile) throws -> Int64 {
        var record = profile
        try db.writer.write { dbConnection in
            try record.insert(dbConnection)
        }
        guard let id = record.id else { return 0 }
        return id
    }

    /// Update an existing company profile.
    public func updateCompanyProfile(_ profile: CompanyProfile) throws {
        try db.writer.write { dbConnection in
            try profile.update(dbConnection)
        }
    }

    /// Soft-delete a company profile.
    public func deleteCompanyProfile(_ id: Int64) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "UPDATE company_profiles SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - PDF Settings

    /// Get PDF template/document settings.
    public func getPDFSettings() throws -> PDFSettings {
        let map = try getSettingsByCategory("pdf")
        return PDFSettings(
            accentColor: map["accent_color"] ?? PDFSettings.defaults.accentColor,
            showUnitPrices: map["show_unit_prices"].map { $0 == "true" } ?? PDFSettings.defaults.showUnitPrices,
            showExtended: map["show_extended"].map { $0 == "true" } ?? PDFSettings.defaults.showExtended,
            footerText: map["footer_text"] ?? PDFSettings.defaults.footerText,
            paymentTerms: map["payment_terms"] ?? PDFSettings.defaults.paymentTerms,
            deliveryNotes: map["delivery_notes"] ?? PDFSettings.defaults.deliveryNotes
        )
    }

    /// Update PDF template/document settings.
    public func updatePDFSettings(_ settings: PDFSettings) throws -> PDFSettings {
        try upsertSettingsMap([
            "accent_color": settings.accentColor,
            "show_unit_prices": String(settings.showUnitPrices),
            "show_extended": String(settings.showExtended),
            "footer_text": settings.footerText,
            "payment_terms": settings.paymentTerms,
            "delivery_notes": settings.deliveryNotes,
        ], category: "pdf")
        return try getPDFSettings()
    }

    // MARK: - Billing Cycle & Pay Period

    /// Get billing cycle configuration.
    public func getBillingCycle() throws -> BillingCycleSettings {
        let map = try getSettingsByCategory("billing_cycle")
        return BillingCycleSettings(
            cycleType: map["cycle_type"] ?? BillingCycleSettings.defaults.cycleType,
            startDay: map["start_day"].flatMap(Int.init) ?? BillingCycleSettings.defaults.startDay
        )
    }

    /// Update billing cycle configuration.
    public func updateBillingCycle(_ settings: BillingCycleSettings) throws -> BillingCycleSettings {
        try upsertSettingsMap([
            "cycle_type": settings.cycleType,
            "start_day": String(settings.startDay),
        ], category: "billing_cycle")
        return try getBillingCycle()
    }

    /// Get pay period configuration.
    public func getPayPeriod() throws -> PayPeriodSettings {
        let map = try getSettingsByCategory("pay_period")
        return PayPeriodSettings(
            periodType: map["period_type"] ?? PayPeriodSettings.defaults.periodType,
            startDay: map["start_day"].flatMap(Int.init) ?? PayPeriodSettings.defaults.startDay
        )
    }

    /// Update pay period configuration.
    public func updatePayPeriod(_ settings: PayPeriodSettings) throws -> PayPeriodSettings {
        try upsertSettingsMap([
            "period_type": settings.periodType,
            "start_day": String(settings.startDay),
        ], category: "pay_period")
        return try getPayPeriod()
    }

    // MARK: - Business Profiles

    /// Get the active business profile, or nil if none exists.
    public func getBusinessProfile() throws -> BusinessProfile? {
        try db.writer.read { dbConnection in
            try BusinessProfile
                .filter(Column("is_active") == 1)
                .fetchOne(dbConnection)
        }
    }

    /// Create a new business profile.
    public func createBusinessProfile(_ profile: BusinessProfile) throws -> BusinessProfile {
        var record = profile
        try db.writer.write { dbConnection in
            try record.insert(dbConnection)
        }
        return record
    }

    /// Update an existing business profile.
    public func updateBusinessProfile(_ profile: BusinessProfile) throws -> BusinessProfile {
        try db.writer.write { dbConnection in
            try profile.update(dbConnection)
        }
        return profile
    }

    /// Check if any business profile exists.
    public func hasBusinessProfile() throws -> Bool {
        try db.writer.read { dbConnection in
            let count = try Int.fetchOne(
                dbConnection,
                sql: "SELECT COUNT(*) FROM business_profiles WHERE is_active = 1"
            ) ?? 0
            return count > 0
        }
    }

    // MARK: - Backup Info

    /// Summary of last backup time and backup count.
    public struct BackupInfo: Sendable {
        public let lastBackupTime: String?
        public let backupCount: Int
    }

    /// Get backup metadata from the settings table.
    public func getBackupInfo() throws -> BackupInfo {
        let lastTime = try getSettingValue("last_backup_time")
        let countStr = try getSettingValue("backup_count")
        let count = Int(countStr ?? "0") ?? 0
        return BackupInfo(lastBackupTime: lastTime, backupCount: count)
    }

    // MARK: - Database Tables

    /// List all user-created table names in the database (excludes sqlite internals).
    public func listDatabaseTables() throws -> [String] {
        try db.writer.read { dbConnection in
            let rows = try Row.fetchAll(dbConnection, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name ASC
            """)
            return rows.compactMap { $0["name"] as? String }
        }
    }

    /// Export all rows from a table as an array of dictionaries.
    public func exportTable(_ tableName: String) throws -> [Any] {
        try db.writer.read { dbConnection in
            // Validate table name and use the DB-returned name (not caller-supplied) to prevent injection
            let tables = try Row.fetchAll(dbConnection, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?
            """, arguments: [tableName])
            guard let validatedName = tables.first.flatMap({ String.fromDatabaseValue($0["name"]) }) else { return [] }

            let rows = try Row.fetchAll(dbConnection, sql: "SELECT * FROM \"\(validatedName)\" LIMIT 10000")
            return rows.map { row in
                var dict: [String: Any] = [:]
                for (column, value) in row {
                    if value.isNull {
                        dict[column] = NSNull()
                    } else if let intVal = Int64.fromDatabaseValue(value) {
                        dict[column] = intVal
                    } else if let dblVal = Double.fromDatabaseValue(value) {
                        dict[column] = dblVal
                    } else if let strVal = String.fromDatabaseValue(value) {
                        dict[column] = strVal
                    } else {
                        dict[column] = "\(value)"
                    }
                }
                return dict
            }
        }
    }

    // MARK: - Update Protocol

    /// Settings for the update protocol page.
    public struct UpdateSettings: Sendable {
        public let updateChannel: String
        public let lastCheckTime: String?
        public let availableVersion: String?
    }

    /// Get update protocol settings.
    public func getUpdateSettings() throws -> UpdateSettings {
        let channel = try getSettingValue("update_channel") ?? "stable"
        let lastCheck = try getSettingValue("last_update_check")
        let available = try getSettingValue("available_version")
        return UpdateSettings(updateChannel: channel, lastCheckTime: lastCheck, availableVersion: available)
    }

    /// Save the selected update channel.
    public func saveUpdateChannel(_ channel: String) throws {
        try upsertSetting(key: "update_channel", value: channel, category: "updates")
    }

    // MARK: - Integrations

    /// Row data for an integration entry.
    public struct IntegrationRow: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let description: String
        public let isEnabled: Bool
        public let lastSyncAt: String?
    }

    /// List all integrations.
    public func listIntegrations() throws -> [IntegrationRow] {
        do {
            return try db.writer.read { dbConnection in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT id, name, description, is_enabled, last_sync_at
                    FROM integrations ORDER BY name ASC
                """)
                return rows.map { row in
                    IntegrationRow(
                        id: "\(row["id"] as Int64? ?? 0)",
                        name: row["name"] as? String ?? "Unknown",
                        description: row["description"] as? String ?? "",
                        isEnabled: (row["is_enabled"] as? Int64 ?? 0) == 1,
                        lastSyncAt: row["last_sync_at"] as? String
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Toggle an integration on or off.
    public func toggleIntegration(_ id: String, enabled: Bool) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(
                sql: "UPDATE integrations SET is_enabled = ? WHERE id = ?",
                arguments: [enabled ? 1 : 0, id]
            )
        }
    }

    // MARK: - Device Keys

    /// Active device encryption key info.
    public struct DeviceKeyInfo: Sendable {
        public let fingerprint: String?
        public let createdAt: String?
        public let rotatedAt: String?
    }

    /// Get the active device encryption key info.
    public func getActiveDeviceKey() throws -> DeviceKeyInfo {
        do {
            return try db.writer.read { dbConnection in
                let row = try Row.fetchOne(dbConnection, sql: """
                    SELECT fingerprint, created_at, rotated_at
                    FROM device_keys WHERE is_active = 1 LIMIT 1
                """)
                return DeviceKeyInfo(
                    fingerprint: row?["fingerprint"] as? String,
                    createdAt: row?["created_at"] as? String,
                    rotatedAt: row?["rotated_at"] as? String
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return DeviceKeyInfo(fingerprint: nil, createdAt: nil, rotatedAt: nil)
            }
            throw error
        }
    }

    // MARK: - Audit Log

    /// A single audit log entry.
    public struct AuditLogEntry: Sendable, Identifiable {
        public let id: String
        public let entityType: String
        public let action: String
        public let timestamp: String
        public let deviceId: String?
    }

    /// Fetch recent entries from the change log.
    public func listAuditLog(limit: Int = 50) throws -> [AuditLogEntry] {
        do {
            return try db.writer.read { dbConnection in
                // Exclude the migration-112 backfill bootstrap rows — they exist
                // so pre-trigger data syncs to peers, but they are not user
                // actions and would flood a fresh install's audit view.
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT cl.id, cl.table_name, cl.operation, cl.timestamp AS changed_at,
                           cl.device_id
                    FROM _change_log cl
                    WHERE cl.changed_fields IS NULL OR cl.changed_fields != '{"__backfill__":1}'
                    ORDER BY cl.timestamp DESC
                    LIMIT ?
                """, arguments: [limit])
                return rows.map { row in
                    AuditLogEntry(
                        id: "\(row["id"] as Int64? ?? 0)",
                        entityType: row["table_name"] as? String ?? "unknown",
                        action: row["operation"] as? String ?? "unknown",
                        timestamp: row["changed_at"] as? String ?? "",
                        deviceId: row["device_id"] as? String
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Bootstrap Devices

    /// A device registered through the bootstrap process.
    public struct BootstrapDeviceRow: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let deviceType: String
        public let status: String
        public let appVersion: String?
        public let lastCheckin: String?
    }

    /// List all bootstrap-registered devices.
    public func listBootstrapDevices() throws -> [BootstrapDeviceRow] {
        do {
            return try db.writer.read { dbConnection in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT id, name, device_type, status, app_version,
                           last_checkin_at
                    FROM bootstrap_devices
                    ORDER BY last_checkin_at DESC
                """)
                return rows.map { row in
                    BootstrapDeviceRow(
                        id: "\(row["id"] as Int64? ?? 0)",
                        name: row["name"] as? String ?? "Unknown",
                        deviceType: row["device_type"] as? String ?? "unknown",
                        status: row["status"] as? String ?? "pending",
                        appVersion: row["app_version"] as? String,
                        lastCheckin: row["last_checkin_at"] as? String
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Clock-Out Questions

    /// A clock-out question row.
    public struct ClockOutQuestionRow: Sendable, Identifiable {
        public let id: String
        public let text: String
        public let type: String
        public let isRequired: Bool
        public let sortOrder: Int
    }

    /// List all clock-out questions ordered by sort_order.
    public func listClockOutQuestions() throws -> [ClockOutQuestionRow] {
        do {
            return try db.writer.read { dbConnection in
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT id, question_text, answer_type, is_required, sort_order
                    FROM clock_out_questions
                    ORDER BY sort_order ASC, id ASC
                """)
                return rows.map { row in
                    ClockOutQuestionRow(
                        id: "\(row["id"] as Int64? ?? 0)",
                        text: row["question_text"] as? String ?? "",
                        type: row["answer_type"] as? String ?? "text",
                        isRequired: (row["is_required"] as? Int64 ?? 1) == 1,
                        sortOrder: Int(row["sort_order"] as? Int64 ?? 0)
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Add a new clock-out question. Returns the inserted row ID.
    @discardableResult
    public func addClockOutQuestion(text: String, type: String, isRequired: Bool, sortOrder: Int) throws -> Int64 {
        guard !text.isBlankRequiredText else {
            throw SettingsError.requiredFieldEmpty("text")
        }
        guard !type.isBlankRequiredText else {
            throw SettingsError.requiredFieldEmpty("type")
        }
        return try db.writer.write { dbConnection -> Int64 in
            try dbConnection.execute(sql: """
                INSERT INTO clock_out_questions (question_text, answer_type, is_required, sort_order)
                VALUES (?, ?, ?, ?)
            """, arguments: [text, type, isRequired ? 1 : 0, sortOrder])
            return dbConnection.lastInsertedRowID
        }
    }

    /// Update an existing clock-out question.
    public func updateClockOutQuestion(id: String, text: String, type: String, isRequired: Bool) throws {
        guard !text.isBlankRequiredText else {
            throw SettingsError.requiredFieldEmpty("text")
        }
        guard !type.isBlankRequiredText else {
            throw SettingsError.requiredFieldEmpty("type")
        }
        try db.writer.write { dbConnection in
            try dbConnection.execute(sql: """
                UPDATE clock_out_questions
                SET question_text = ?, answer_type = ?, is_required = ?
                WHERE id = ?
            """, arguments: [text, type, isRequired ? 1 : 0, id])
        }
    }

    /// Delete a clock-out question by ID.
    public func deleteClockOutQuestion(id: String) throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(sql: "DELETE FROM clock_out_questions WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Company Setup Draft

    /// Temporary wizard draft state — replaces UserDefaults storage for PII fields.
    /// At most one row exists in `company_setup_draft`.
    public struct CompanySetupDraft: Sendable {
        public var currentStep: Int
        public var completedSteps: Set<Int>
        public var skippedSteps: Set<Int>
        public var name: String
        public var address: String
        public var phone: String
        public var email: String
        public var selectedState: String

        public init(
            currentStep: Int = 0,
            completedSteps: Set<Int> = [],
            skippedSteps: Set<Int> = [],
            name: String = "",
            address: String = "",
            phone: String = "",
            email: String = "",
            selectedState: String = "California"
        ) {
            self.currentStep = currentStep
            self.completedSteps = completedSteps
            self.skippedSteps = skippedSteps
            self.name = name
            self.address = address
            self.phone = phone
            self.email = email
            self.selectedState = selectedState
        }

        init(row: Row) {
            currentStep = Int(row["current_step"] as? Int64 ?? 0)
            name = row["name"] as? String ?? ""
            address = row["address"] as? String ?? ""
            phone = row["phone"] as? String ?? ""
            email = row["email"] as? String ?? ""
            selectedState = row["selected_state"] as? String ?? "California"

            if let json = row["completed_steps"] as? String,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) {
                completedSteps = decoded
            } else {
                completedSteps = []
            }
            if let json = row["skipped_steps"] as? String,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) {
                skippedSteps = decoded
            } else {
                skippedSteps = []
            }
        }
    }

    /// Load wizard draft (returns nil if no draft has been started).
    public func loadSetupDraft() throws -> CompanySetupDraft? {
        try db.writer.read { dbConnection in
            try Row.fetchOne(dbConnection, sql: "SELECT * FROM company_setup_draft LIMIT 1")
                .map { CompanySetupDraft(row: $0) }
        }
    }

    /// Save/update wizard draft (upsert — only one row ever exists).
    public func saveSetupDraft(_ draft: CompanySetupDraft) throws {
        let completedJSON = (try? JSONEncoder().encode(draft.completedSteps))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let skippedJSON = (try? JSONEncoder().encode(draft.skippedSteps))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        try db.writer.write { dbConnection in
            // Delete any existing row then insert fresh — simple single-row upsert
            try dbConnection.execute(sql: "DELETE FROM company_setup_draft")
            try dbConnection.execute(sql: """
                INSERT INTO company_setup_draft
                    (current_step, completed_steps, skipped_steps, name, address, phone, email, selected_state, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """, arguments: [
                draft.currentStep,
                completedJSON,
                skippedJSON,
                draft.name,
                draft.address,
                draft.phone,
                draft.email,
                draft.selectedState
            ])
        }
    }

    /// Delete draft after wizard completion.
    public func deleteSetupDraft() throws {
        try db.writer.write { dbConnection in
            try dbConnection.execute(sql: "DELETE FROM company_setup_draft")
        }
    }

    // MARK: - Errors

    public enum SettingsError: Error, Sendable, Equatable {
        case companyProfileNotFound(Int64)
        case requiredFieldEmpty(String)
        case invalidValue(String)
    }

    // MARK: - Helpers

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }

    private static let personalSettingCategories: Set<String> = [
        "notifications",
        "personal",
        "theme",
        "ui",
        "user_preferences",
    ]

    private static let personalSettingKeys: Set<String> = [
        "dashboard_layout",
        "default_landing_page",
        "font_family",
        "notification_preferences",
        "notifications_enabled",
        "preferred_language",
        "primary_color",
        "reduced_motion",
        "tab_order",
        "theme_mode",
    ]

    private static let deviceSettingCategories: Set<String> = [
        "backup",
        "device",
        "device_keys",
        "local",
        "updates",
    ]

    private static let deviceSettingKeys: Set<String> = [
        "app_version",
        "available_version",
        "backup_count",
        "bluetooth_enabled",
        "device_fingerprint",
        "device_id",
        "device_name",
        "device_pairing_verified_at",
        "device_private_key",
        "shop_server_address",
        "last_backup_time",
        "last_update_check",
        "local_db_path",
        "local_database_path",
        "paired_company_id",
        "paired_shop_device_id",
        "device_pairing_verified_at",
        "shop_server_address",
        "sync_server_address",
        "update_channel",
    ]
}
