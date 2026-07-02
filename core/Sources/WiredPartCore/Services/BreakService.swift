import Foundation
import GRDB

/// Service for break/lunch compliance: policies, records, auto-fill, and rounding.
public final class BreakService: Sendable {
    private let db: AppDatabase

    public enum BreakError: Error, LocalizedError, Sendable, Equatable {
        case activeBreakAlreadyInProgress(userId: Int64, activeBreakId: Int64?)
        case invalidDefaultBreakTime(field: String, value: String)

        public var errorDescription: String? {
            switch self {
            case .activeBreakAlreadyInProgress:
                return "An active break is already in progress. End the current break before starting another."
            case .invalidDefaultBreakTime(let field, _):
                return "\(field) must be a valid 24-hour time in HH:mm format."
            }
        }
    }

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Break Policies
    // =========================================================================

    /// Get the combined break policy for a state and work day length.
    public func getBreakPolicy(stateCode: String, dayHours: Int = 8) throws -> [BreakPolicy] {
        do {
            return try db.writer.read { dbConn in
                try BreakPolicy
                    .filter(Column("state_code") == stateCode && Column("deleted_at") == nil)
                    .filter(Column("work_day_hours") <= dayHours)
                    .order(Column("policy_type").asc, Column("work_day_hours").desc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get all policies (state + company) for display in settings.
    public func getAllPolicies() throws -> [BreakPolicy] {
        do {
            return try db.writer.read { dbConn in
                try BreakPolicy
                    .filter(Column("deleted_at") == nil)
                    .order(Column("state_code").asc, Column("policy_type").asc, Column("work_day_hours").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
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
        do {
            return try db.writer.write { dbConn in
                let dataDate = Self.todayString()
                let matchingPolicySQL = """
                    SELECT id
                    FROM break_policies
                    WHERE deleted_at IS NULL
                      AND policy_type = ?
                      AND work_day_hours = ?
                      AND ((? IS NULL AND state_code IS NULL) OR state_code = ?)
                    ORDER BY id ASC
                    """
                let matchingIds = try Int64.fetchAll(
                    dbConn,
                    sql: matchingPolicySQL,
                    arguments: [policyType, workDayHours, stateCode, stateCode]
                )

                if let policyId = matchingIds.first {
                    try dbConn.execute(sql: """
                        UPDATE break_policies
                        SET state_code = ?,
                            policy_type = ?,
                            work_day_hours = ?,
                            lunch_minutes = ?,
                            break_count = ?,
                            break_minutes = ?,
                            data_source = ?,
                            data_date = ?,
                            updated_at = datetime('now'),
                            deleted_at = NULL
                        WHERE id = ?
                        """, arguments: [
                            stateCode, policyType, workDayHours, lunchMinutes,
                            breakCount, breakMinutes, dataSource, dataDate, policyId
                        ])

                    if matchingIds.count > 1 {
                        try dbConn.execute(sql: """
                            UPDATE break_policies
                            SET deleted_at = datetime('now'),
                                updated_at = datetime('now')
                            WHERE id IN (
                                SELECT id
                                FROM break_policies
                                WHERE deleted_at IS NULL
                                  AND policy_type = ?
                                  AND work_day_hours = ?
                                  AND ((? IS NULL AND state_code IS NULL) OR state_code = ?)
                                  AND id <> ?
                            )
                            """, arguments: [policyType, workDayHours, stateCode, stateCode, policyId])
                    }

                    return try BreakPolicy.fetchOne(dbConn, key: policyId) ?? BreakPolicy(
                        id: policyId, stateCode: stateCode, policyType: policyType,
                        workDayHours: workDayHours, lunchMinutes: lunchMinutes,
                        breakCount: breakCount, breakMinutes: breakMinutes,
                        dataSource: dataSource, dataDate: dataDate,
                        createdAt: nil, updatedAt: nil, deletedAt: nil
                    )
                } else {
                    var policy = BreakPolicy(
                        id: nil, stateCode: stateCode, policyType: policyType,
                        workDayHours: workDayHours, lunchMinutes: lunchMinutes,
                        breakCount: breakCount, breakMinutes: breakMinutes,
                        dataSource: dataSource, dataDate: dataDate,
                        createdAt: nil, updatedAt: nil, deletedAt: nil
                    )
                    try policy.insert(dbConn)
                    return policy
                }
            }
        } catch {
            if isTableNotFoundError(error) {
                return BreakPolicy(
                    id: nil, stateCode: stateCode, policyType: policyType,
                    workDayHours: workDayHours, lunchMinutes: lunchMinutes,
                    breakCount: breakCount, breakMinutes: breakMinutes,
                    dataSource: dataSource, dataDate: Self.todayString(),
                    createdAt: nil, updatedAt: nil, deletedAt: nil
                )
            }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Break Bonuses
    // =========================================================================

    /// Get bonuses for a policy.
    public func getBreakBonuses(policyId: Int64) throws -> [BreakBonus] {
        do {
            return try db.writer.read { dbConn in
                try BreakBonus
                    .filter(Column("policy_id") == policyId && Column("deleted_at") == nil)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
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
        do {
            return try db.writer.write { dbConn in
                var bonus = BreakBonus(
                    id: nil, policyId: policyId, bonusType: bonusType,
                    bonusAmount: bonusAmount, description: description,
                    isEnabled: isEnabled, createdAt: nil, deletedAt: nil
                )
                try bonus.insert(dbConn)
                return bonus
            }
        } catch {
            if isTableNotFoundError(error) {
                return BreakBonus(
                    id: nil, policyId: policyId, bonusType: bonusType,
                    bonusAmount: bonusAmount, description: description,
                    isEnabled: isEnabled, createdAt: nil, deletedAt: nil
                )
            }
            throw error
        }
    }

    /// Toggle a bonus enabled/disabled.
    public func toggleBonus(bonusId: Int64, isEnabled: Bool) throws {
        do {
            try db.writer.write { dbConn in
                try dbConn.execute(sql: """
                    UPDATE break_bonuses SET is_enabled = ? WHERE id = ?
                    """, arguments: [isEnabled, bonusId])
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
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
        do {
            return try db.writer.write { dbConn in
                let resolvedLaborEntryId = try laborEntryId ?? Self.activeClockEntryId(dbConn: dbConn, userId: userId)
                if let activeBreak = try Self.activeBreak(dbConn: dbConn, userId: userId) {
                    if activeBreak.breakType == breakType && activeBreak.laborEntryId == resolvedLaborEntryId {
                        return activeBreak
                    }
                    throw BreakError.activeBreakAlreadyInProgress(userId: userId, activeBreakId: activeBreak.id)
                }

                var record = BreakRecord(
                    id: nil, userId: userId, laborEntryId: resolvedLaborEntryId,
                    breakType: breakType, startedAt: Self.nowString(),
                    endedAt: nil, durationMinutes: nil, isPaid: isPaid,
                    autoFilled: false, timerDurationMinutes: timerMinutes,
                    createdAt: nil, deletedAt: nil
                )
                try record.insert(dbConn)
                return record
            }
        } catch {
            if isTableNotFoundError(error) {
                return BreakRecord(
                    id: nil, userId: userId, laborEntryId: laborEntryId,
                    breakType: breakType, startedAt: Self.nowString(),
                    endedAt: nil, durationMinutes: nil, isPaid: isPaid,
                    autoFilled: false, timerDurationMinutes: timerMinutes,
                    createdAt: nil, deletedAt: nil
                )
            }
            throw error
        }
    }

    /// End an active break, calculating duration.
    public func endBreak(recordId: Int64) throws {
        do {
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
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    /// Get break records for a user on a specific date.
    public func getBreakRecordsForDay(userId: Int64, date: Date = Date()) throws -> [BreakRecord] {
        let dateStr = Self.formatDateUTC(date)
        do {
            return try db.writer.read { dbConn in
                try BreakRecord
                    .filter(Column("user_id") == userId && Column("deleted_at") == nil)
                    .filter(sql: "substr(started_at, 1, 10) = ?", arguments: [dateStr])
                    .order(Column("started_at").asc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get the currently active break for a user (started but not ended).
    public func getActiveBreak(userId: Int64) throws -> BreakRecord? {
        do {
            return try db.writer.read { dbConn in
                try Self.activeBreak(dbConn: dbConn, userId: userId)
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
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
        let dateStr = Self.formatDateUTC(date)  // must match the UTC date used in getBreakRecordsForDay

        do { try db.writer.write { dbConn in
            func insertScheduledBreakIfMissing(at time: String) throws {
                let startStr = "\(dateStr)T\(time):00"
                let scheduledMinutePrefix = "\(dateStr)T\(time)"
                let alreadyExists = existing.contains {
                    $0.breakType == "break" && $0.startedAt.hasPrefix(scheduledMinutePrefix)
                }
                guard !alreadyExists else { return }
                guard let endDateTime = Self.endDateTimeString(dateStr: dateStr, startTime: time, durationMinutes: 15) else { return }

                var record = BreakRecord(
                    id: nil, userId: userId, laborEntryId: laborEntryId,
                    breakType: "break", startedAt: startStr,
                    endedAt: endDateTime,
                    durationMinutes: 15, isPaid: true,
                    autoFilled: true, timerDurationMinutes: 15,
                    createdAt: nil, deletedAt: nil
                )
                try record.insert(dbConn)
            }

            // Auto-fill each scheduled break independently so one existing break
            // does not suppress the other configured default break.
            if let morningTime = Self.validatedDefaultTime(settings.defaultMorningBreak) {
                try insertScheduledBreakIfMissing(at: morningTime)
            }

            if let afternoonTime = Self.validatedDefaultTime(settings.defaultAfternoonBreak) {
                try insertScheduledBreakIfMissing(at: afternoonTime)
            }

            // Auto-fill lunch if missing
            let hasLunch = existing.contains { $0.breakType.hasPrefix("lunch") }
            if !hasLunch {
                if let lunchTime = Self.validatedDefaultTime(settings.defaultLunch),
                   let lunchEndDateTime = Self.endDateTimeString(dateStr: dateStr, startTime: lunchTime, durationMinutes: 30) {
                    let startStr = "\(dateStr)T\(lunchTime):00"
                    var record = BreakRecord(
                        id: nil, userId: userId, laborEntryId: laborEntryId,
                        breakType: "lunch_paid", startedAt: startStr,
                        endedAt: lunchEndDateTime,
                        durationMinutes: 30, isPaid: true,
                        autoFilled: true, timerDurationMinutes: 30,
                        createdAt: nil, deletedAt: nil
                    )
                    try record.insert(dbConn)
                }
            }
        }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Company Settings
    // =========================================================================

    /// Get company break settings (singleton).
    public func getCompanyBreakSettings() throws -> CompanyBreakSettings {
        do {
            return try db.writer.read { dbConn in
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
        } catch {
            if isTableNotFoundError(error) {
                return CompanyBreakSettings(
                    id: nil, stateCode: "WY", roundingMinutes: 15,
                    roundingEnabled: false, autoFillBreaks: true,
                    defaultMorningBreak: "10:00", defaultLunch: "12:00",
                    defaultAfternoonBreak: "14:30", updatedAt: nil
                )
            }
            throw error
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
        let normalizedMorningBreak = try Self.normalizedDefaultTime(defaultMorningBreak, field: "Morning Break")
        let normalizedLunch = try Self.normalizedDefaultTime(defaultLunch, field: "Lunch")
        let normalizedAfternoonBreak = try Self.normalizedDefaultTime(defaultAfternoonBreak, field: "Afternoon Break")

        do {
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
                        autoFillBreaks, normalizedMorningBreak,
                        normalizedLunch, normalizedAfternoonBreak
                    ])
            }
        } catch {
            if isTableNotFoundError(error) { return }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Rounding
    // =========================================================================

    /// Round a time string to the nearest N minutes (for reports only).
    /// Accepts ISO8601 datetime strings or short "HH:mm" time strings.
    /// Returns in the same format as the input.
    public func getRoundedTime(time: String, roundingMinutes: Int = 15) -> String {
        guard roundingMinutes > 0 else { return time }
        // Handle short "HH:mm" format
        let isShortTime = time.count <= 5 && time.contains(":")
        if isShortTime {
            let parts = time.split(separator: ":")
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return time }
            let roundedMinute = (minute / roundingMinutes) * roundingMinutes
            return String(format: "%02d:%02d", hour, roundedMinute)
        }

        // Handle full datetime formats
        guard let date = Self.parseDateTime(time) else { return time }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let minute = calendar.component(.minute, from: date)
        let roundedMinute = (minute / roundingMinutes) * roundingMinutes
        let diff = roundedMinute - minute
        let rounded = calendar.date(byAdding: .minute, value: diff, to: date) ?? date
        return CoreFormatters.iso8601.string(from: rounded)
    }

    // =========================================================================
    // MARK: - Helpers (use CoreFormatters singletons — fixes #146)
    // =========================================================================

    private static func nowString() -> String {
        CoreFormatters.nowISO()
    }

    private static func todayString() -> String {
        // NOTE: was using local-zone formatter — preserving that behavior with a one-off
        // local DateFormatter rather than CoreFormatters.yearMonthDay (which is UTC).
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Format a date as "yyyy-MM-dd" in UTC (matching how nowString() stores timestamps).
    private static func formatDateUTC(_ date: Date) -> String {
        CoreFormatters.yearMonthDay.string(from: date)
    }

    private static func parseDateTime(_ str: String) -> Date? {
        CoreFormatters.parseDateTime(str)
    }

    private static func activeClockEntryId(dbConn: Database, userId: Int64) throws -> Int64? {
        try Int64.fetchOne(dbConn, sql: """
            SELECT id
            FROM labor_entries
            WHERE user_id = ?
              AND status = 'clocked_in'
              AND deleted_at IS NULL
            ORDER BY clock_in DESC, id DESC
            LIMIT 1
            """, arguments: [userId])
    }

    private static func activeBreak(dbConn: Database, userId: Int64) throws -> BreakRecord? {
        try BreakRecord
            .filter(Column("user_id") == userId &&
                    Column("ended_at") == nil &&
                    Column("deleted_at") == nil)
            .order(Column("started_at").desc, Column("id").desc)
            .fetchOne(dbConn)
    }

    private static func normalizedDefaultTime(_ timeStr: String?, field: String) throws -> String? {
        guard let timeStr else { return nil }
        let trimmed = timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let validated = validatedDefaultTime(trimmed) else {
            throw BreakError.invalidDefaultBreakTime(field: field, value: timeStr)
        }
        return validated
    }

    private static func validatedDefaultTime(_ timeStr: String?) -> String? {
        guard let timeStr else { return nil }
        let trimmed = timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 2,
              parts[0].allSatisfy({ $0 >= "0" && $0 <= "9" }),
              parts[1].allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let hour = Int(parts[0]),
              let min = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(min)
        else { return nil }
        return String(format: "%02d:%02d", hour, min)
    }

    private static func endDateTimeString(dateStr: String, startTime timeStr: String, durationMinutes: Int) -> String? {
        guard let validTime = validatedDefaultTime(timeStr),
              let startDate = CoreFormatters.yearMonthDay.date(from: dateStr)
        else { return nil }

        let parts = validTime.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let min = Int(parts[1]) else { return nil }
        let total = hour * 60 + min + durationMinutes
        guard total >= 0 else { return nil }

        let dayOffset = total / 1440
        let minuteOfDay = total % 1440
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        guard let endDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else { return nil }

        let endDateStr = CoreFormatters.yearMonthDay.string(from: endDate)
        let endTime = String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
        return "\(endDateStr)T\(endTime):00"
    }

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
