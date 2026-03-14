import Foundation
import GRDB

/// Local Settings Service — theme, app configuration, company profiles, billing/pay cycles.
///
/// Settings are stored as key-value rows in the `settings` table;
/// compound settings (theme, pdf, billing) use a shared category
/// with one row per field.
///
/// Ported from: `src/local/services/settings-service.ts`
public final class SettingsService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Types

    public struct ThemeSettings: Codable, Sendable {
        public var themeMode: String   // "light", "dark", "system"
        public var primaryColor: String
        public var fontFamily: String

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

        public static let defaults = BillingCycleSettings(cycleType: "monthly", startDay: 1)
    }

    public struct PayPeriodSettings: Codable, Sendable {
        public var periodType: String  // "biweekly", "weekly", "monthly"
        public var startDay: Int

        public static let defaults = PayPeriodSettings(periodType: "biweekly", startDay: 1)
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

    /// Bulk upsert a dictionary of key->value pairs under one category.
    public func upsertSettingsMap(_ data: [String: String], category: String) throws {
        for (key, value) in data {
            try upsertSetting(key: key, value: value, category: category)
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
                grouped[cat]![key] = value
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

    // MARK: - Warranty

    /// Get default warranty length in days. Falls back to 365.
    public func getWarrantyLengthDays() throws -> Int {
        guard let val = try getSettingValue("warranty_length_days"),
              let days = Int(val) else { return 365 }
        return days
    }

    /// Update default warranty length in days.
    public func updateWarrantyLengthDays(_ days: Int) throws {
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
        return record.id!
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

    // MARK: - Errors

    public enum SettingsError: Error, Sendable {
        case companyProfileNotFound(Int64)
    }
}
