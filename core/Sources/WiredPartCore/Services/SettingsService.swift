import Foundation
import GRDB

/// Local Settings Service — theme, app configuration, company profiles, billing/pay cycles.
///
/// Settings are stored as key-value rows in the `settings` table;
/// compound settings (theme, pdf, billing) use a shared category
/// with one row per field.
///
/// Ported from: `src/local/services/settings-service.ts`
// TODO: When sync is implemented, filter settings by SyncScope:
// - .company → include in company-wide sync
// - .personal → include in per-user sync
// - .device → exclude from sync
// Classification lives in SyncScope.scope(for:) on the iOS side.

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
            // Validate table name to prevent injection
            let tables = try Row.fetchAll(dbConnection, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?
            """, arguments: [tableName])
            guard !tables.isEmpty else { return [] }

            let rows = try Row.fetchAll(dbConnection, sql: "SELECT * FROM \"\(tableName)\" LIMIT 10000")
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
                let rows = try Row.fetchAll(dbConnection, sql: """
                    SELECT cl.id, cl.table_name, cl.operation, cl.timestamp AS changed_at,
                           cl.device_id
                    FROM _change_log cl
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
        try db.writer.write { dbConnection in
            try dbConnection.execute(sql: """
                INSERT INTO clock_out_questions (question_text, answer_type, is_required, sort_order)
                VALUES (?, ?, ?, ?)
            """, arguments: [text, type, isRequired ? 1 : 0, sortOrder])
            return dbConnection.lastInsertedRowID
        }
    }

    /// Update an existing clock-out question.
    public func updateClockOutQuestion(id: String, text: String, type: String, isRequired: Bool) throws {
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

    // MARK: - Errors

    public enum SettingsError: Error, Sendable {
        case companyProfileNotFound(Int64)
    }

    // MARK: - Helpers

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
