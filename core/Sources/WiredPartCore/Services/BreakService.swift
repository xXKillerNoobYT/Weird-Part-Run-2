import Foundation
import GRDB

/// Service for break/lunch compliance: policies, records, auto-fill, and rounding.
public final class BreakService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Break Policies
    // =========================================================================

    /// Get the combined break policy for a state and work day length.
    public func getBreakPolicy(stateCode: String, dayHours: Int = 8) throws -> [BreakPolicy] {
        try db.writer.read { dbConn in
            try BreakPolicy
                .filter(Column("state_code") == stateCode && Column("deleted_at") == nil)
                .filter(Column("work_day_hours") <= dayHours)
                .order(Column("policy_type").asc)
                .fetchAll(dbConn)
        }
    }

    /// Get all policies (state + company) for display in settings.
    public func getAllPolicies() throws -> [BreakPolicy] {
        try db.writer.read { dbConn in
            try BreakPolicy
                .filter(Column("deleted_at") == nil)
                .order(Column("state_code").asc, Column("policy_type").asc)
                .fetchAll(dbConn)
        }
    }

    /// Create or update a company break policy.
    @discardableResult
    public func savePolicy(
        stateCode: String?,
        policyType: String,
        workDayHours: Int = 8,
        lunchMinutes: Int = 30,
        breakCount: Int = 2,
        breakMinutes: Int = 15,
        dataSource: String? = "manual"
    ) throws -> BreakPolicy {
        try db.writer.write { dbConn in
            var policy = BreakPolicy(
                id: nil, stateCode: stateCode, policyType: policyType,
                workDayHours: workDayHours, lunchMinutes: lunchMinutes,
                breakCount: breakCount, breakMinutes: breakMinutes,
                dataSource: dataSource, dataDate: Self.todayString(),
                createdAt: nil, updatedAt: nil, deletedAt: nil
            )
            try policy.insert(dbConn)
            return policy
        }
    }

    // =========================================================================
    // MARK: - Break Bonuses
    // =========================================================================

    /// Get bonuses for a policy.
    public func getBreakBonuses(policyId: Int64) throws -> [BreakBonus] {
        try db.writer.read { dbConn in
            try BreakBonus
                .filter(Column("policy_id") == policyId && Column("deleted_at") == nil)
                .fetchAll(dbConn)
        }
    }

    /// Create a break bonus.
    @discardableResult
    public func createBonus(
        policyId: Int64,
        bonusType: String,
        bonusAmount: Double,
        description: String? = nil,
        isEnabled: Bool = false
    ) throws -> BreakBonus {
        try db.writer.write { dbConn in
            var bonus = BreakBonus(
                id: nil, policyId: policyId, bonusType: bonusType,
                bonusAmount: bonusAmount, description: description,
                isEnabled: isEnabled, createdAt: nil, deletedAt: nil
            )
            try bonus.insert(dbConn)
            return bonus
        }
    }

    /// Toggle a bonus enabled/disabled.
    public func toggleBonus(bonusId: Int64, isEnabled: Bool) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE break_bonuses SET is_enabled = ? WHERE id = ?
                """, arguments: [isEnabled, bonusId])
        }
    }

    // =========================================================================
    // MARK: - Break Records
    // =========================================================================

    /// Start a break/lunch/supply-run for a user.
    @discardableResult
    public func startBreak(
        userId: Int64,
        breakType: String,
        laborEntryId: Int64? = nil,
        timerMinutes: Int? = nil
    ) throws -> BreakRecord {
        let isPaid = (breakType != "lunch_unpaid")
        return try db.writer.write { dbConn in
            var record = BreakRecord(
                id: nil, userId: userId, laborEntryId: laborEntryId,
                breakType: breakType, startedAt: Self.nowString(),
                endedAt: nil, durationMinutes: nil, isPaid: isPaid,
                autoFilled: false, timerDurationMinutes: timerMinutes,
                createdAt: nil, deletedAt: nil
            )
            try record.insert(dbConn)
            return record
        }
    }

    /// End an active break, calculating duration.
    public func endBreak(recordId: Int64) throws {
        try db.writer.write { dbConn in
            guard var record = try BreakRecord.fetchOne(dbConn, key: recordId) else { return }
            let endTime = Self.nowString()
            record.endedAt = endTime

            // Calculate duration in minutes
            if let start = Self.parseDateTime(record.startedAt),
               let end = Self.parseDateTime(endTime) {
                record.durationMinutes = Int(end.timeIntervalSince(start) / 60.0)
            }
            try record.update(dbConn)
        }
    }

    /// Get break records for a user on a specific date.
    public func getBreakRecordsForDay(userId: Int64, date: Date = Date()) throws -> [BreakRecord] {
        let dateStr = Self.formatDate(date)
        return try db.writer.read { dbConn in
            try BreakRecord
                .filter(Column("user_id") == userId && Column("deleted_at") == nil)
                .filter(sql: "date(started_at) = ?", arguments: [dateStr])
                .order(Column("started_at").asc)
                .fetchAll(dbConn)
        }
    }

    /// Get the currently active break for a user (started but not ended).
    public func getActiveBreak(userId: Int64) throws -> BreakRecord? {
        try db.writer.read { dbConn in
            try BreakRecord
                .filter(Column("user_id") == userId &&
                        Column("ended_at") == nil &&
                        Column("deleted_at") == nil)
                .order(Column("started_at").desc)
                .fetchOne(dbConn)
        }
    }

    // =========================================================================
    // MARK: - Break Compliance
    // =========================================================================

    /// Calculate break compliance for a user on a given day.
    public func calculateBreakCompliance(userId: Int64, date: Date = Date()) throws -> BreakComplianceSummary {
        let records = try getBreakRecordsForDay(userId: userId, date: date)
        let settings = try getCompanyBreakSettings()
        let policies = try getBreakPolicy(stateCode: settings.stateCode)

        let requiredPolicy = policies.first { $0.policyType == "state_required_paid" }
        let requiredBreaks = requiredPolicy?.breakCount ?? 2
        let requiredLunchMinutes = requiredPolicy?.lunchMinutes ?? 30

        let breakRecords = records.filter { $0.breakType == "break" }
        let lunchRecords = records.filter { $0.breakType.hasPrefix("lunch") }
        let takenBreaks = breakRecords.count
        let takenLunchMinutes = lunchRecords.reduce(0) { $0 + ($1.durationMinutes ?? 0) }

        let isCompliant = takenBreaks >= requiredBreaks && takenLunchMinutes >= requiredLunchMinutes
        let autoFilled = records.contains { $0.autoFilled }

        // Bonus eligible: used break buttons (not auto-filled), took exactly state minimums
        let bonusEligible = !autoFilled && isCompliant && takenBreaks == requiredBreaks

        return BreakComplianceSummary(
            requiredBreaks: requiredBreaks,
            takenBreaks: takenBreaks,
            requiredLunchMinutes: requiredLunchMinutes,
            takenLunchMinutes: takenLunchMinutes,
            isCompliant: isCompliant,
            autoFilled: autoFilled,
            bonusEligible: bonusEligible
        )
    }

    /// Auto-fill break records at default times for compliance when user didn't log breaks.
    public func autoFillBreaksForDay(userId: Int64, date: Date = Date(), laborEntryId: Int64? = nil) throws {
        let settings = try getCompanyBreakSettings()
        guard settings.autoFillBreaks else { return }

        let existing = try getBreakRecordsForDay(userId: userId, date: date)
        let dateStr = Self.formatDate(date)

        try db.writer.write { dbConn in
            // Auto-fill morning break if missing
            let hasBreak = existing.contains { $0.breakType == "break" }
            if !hasBreak {
                if let morningTime = settings.defaultMorningBreak {
                    let startStr = "\(dateStr)T\(morningTime):00"
                    var record = BreakRecord(
                        id: nil, userId: userId, laborEntryId: laborEntryId,
                        breakType: "break", startedAt: startStr,
                        endedAt: "\(dateStr)T\(Self.addMinutes(morningTime, 15)):00",
                        durationMinutes: 15, isPaid: true,
                        autoFilled: true, timerDurationMinutes: 15,
                        createdAt: nil, deletedAt: nil
                    )
                    try record.insert(dbConn)
                }

                if let afternoonTime = settings.defaultAfternoonBreak {
                    let startStr = "\(dateStr)T\(afternoonTime):00"
                    var record = BreakRecord(
                        id: nil, userId: userId, laborEntryId: laborEntryId,
                        breakType: "break", startedAt: startStr,
                        endedAt: "\(dateStr)T\(Self.addMinutes(afternoonTime, 15)):00",
                        durationMinutes: 15, isPaid: true,
                        autoFilled: true, timerDurationMinutes: 15,
                        createdAt: nil, deletedAt: nil
                    )
                    try record.insert(dbConn)
                }
            }

            // Auto-fill lunch if missing
            let hasLunch = existing.contains { $0.breakType.hasPrefix("lunch") }
            if !hasLunch {
                if let lunchTime = settings.defaultLunch {
                    let startStr = "\(dateStr)T\(lunchTime):00"
                    var record = BreakRecord(
                        id: nil, userId: userId, laborEntryId: laborEntryId,
                        breakType: "lunch_paid", startedAt: startStr,
                        endedAt: "\(dateStr)T\(Self.addMinutes(lunchTime, 30)):00",
                        durationMinutes: 30, isPaid: true,
                        autoFilled: true, timerDurationMinutes: 30,
                        createdAt: nil, deletedAt: nil
                    )
                    try record.insert(dbConn)
                }
            }
        }
    }

    // =========================================================================
    // MARK: - Company Settings
    // =========================================================================

    /// Get company break settings (singleton).
    public func getCompanyBreakSettings() throws -> CompanyBreakSettings {
        try db.writer.read { dbConn in
            if let settings = try CompanyBreakSettings.fetchOne(dbConn, sql: "SELECT * FROM company_break_settings LIMIT 1") {
                return settings
            }
            return CompanyBreakSettings(
                id: nil, stateCode: "WY", roundingMinutes: 15,
                roundingEnabled: false, autoFillBreaks: true,
                defaultMorningBreak: "10:00", defaultLunch: "12:00",
                defaultAfternoonBreak: "14:30", updatedAt: nil
            )
        }
    }

    /// Update company break settings.
    public func updateCompanyBreakSettings(
        stateCode: String,
        roundingMinutes: Int = 15,
        roundingEnabled: Bool = false,
        autoFillBreaks: Bool = true,
        defaultMorningBreak: String? = "10:00",
        defaultLunch: String? = "12:00",
        defaultAfternoonBreak: String? = "14:30"
    ) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE company_break_settings
                SET state_code = ?, rounding_minutes = ?, rounding_enabled = ?,
                    auto_fill_breaks = ?, default_morning_break = ?,
                    default_lunch = ?, default_afternoon_break = ?,
                    updated_at = datetime('now')
                WHERE id = (SELECT id FROM company_break_settings LIMIT 1)
                """, arguments: [
                    stateCode, roundingMinutes, roundingEnabled,
                    autoFillBreaks, defaultMorningBreak,
                    defaultLunch, defaultAfternoonBreak
                ])
        }
    }

    // =========================================================================
    // MARK: - Rounding
    // =========================================================================

    /// Round a time string to the nearest N minutes (for reports only).
    public func getRoundedTime(time: String, roundingMinutes: Int = 15) -> String {
        guard let date = Self.parseDateTime(time) else { return time }
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let roundedMinute = (minute / roundingMinutes) * roundingMinutes
        let diff = roundedMinute - minute
        let rounded = calendar.date(byAdding: .minute, value: diff, to: date) ?? date
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: rounded)
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private static func nowString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func parseDateTime(_ str: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: str) { return d }
        let f3 = DateFormatter()
        f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = f3.date(from: str) { return d }
        let f4 = DateFormatter()
        f4.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f4.date(from: str)
    }

    /// Add minutes to a time string like "10:00" → "10:15".
    private static func addMinutes(_ timeStr: String, _ minutes: Int) -> String {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let min = Int(parts[1]) else { return timeStr }
        let total = hour * 60 + min + minutes
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
