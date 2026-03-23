import Foundation
import GRDB

/// Scheduling Service — schedule entries, dispatch board, time-off requests,
/// dispatch templates, and scheduling stats.
///
/// All queries run against the local SQLite database via GRDB.
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Scheduling & Dispatch feature area (Phases 10, 16)
public final class SchedulingService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum SchedulingError: Error, Sendable {
        case timeOffRequestNotFound(Int64)
        case invalidStatus(String)
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A schedule entry row for a user's schedule view.
    public struct ScheduleEntry: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let date: String
        public let startTime: String?
        public let endTime: String?
        public let status: String
        public let notes: String?

        public init(
            id: Int64, jobName: String, date: String,
            startTime: String?, endTime: String?,
            status: String, notes: String?
        ) {
            self.id = id
            self.jobName = jobName
            self.date = date
            self.startTime = startTime
            self.endTime = endTime
            self.status = status
            self.notes = notes
        }
    }

    /// A dispatch board row showing who is dispatched where on a given date.
    public struct DispatchRow: Sendable, Identifiable {
        public let id: Int64
        public let userName: String
        public let jobName: String
        public let vehicleName: String?
        public let status: String
        public let notes: String?

        public init(
            id: Int64, userName: String, jobName: String,
            vehicleName: String?, status: String, notes: String?
        ) {
            self.id = id
            self.userName = userName
            self.jobName = jobName
            self.vehicleName = vehicleName
            self.status = status
            self.notes = notes
        }
    }

    /// A time-off request row for list views.
    public struct TimeOffRow: Sendable, Identifiable {
        public let id: Int64
        public let userName: String
        public let startDate: String
        public let endDate: String
        public let reason: String?
        public let status: String
        public let approvedByName: String?

        public init(
            id: Int64, userName: String, startDate: String,
            endDate: String, reason: String?, status: String,
            approvedByName: String?
        ) {
            self.id = id
            self.userName = userName
            self.startDate = startDate
            self.endDate = endDate
            self.reason = reason
            self.status = status
            self.approvedByName = approvedByName
        }
    }

    /// A dispatch template list item.
    public struct TemplateListItem: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let description: String?
        public let isActive: Bool

        public init(id: Int64, name: String, description: String?, isActive: Bool) {
            self.id = id
            self.name = name
            self.description = description
            self.isActive = isActive
        }
    }

    /// Dashboard-level scheduling stats.
    public struct SchedulingStats: Sendable {
        public let scheduledToday: Int
        public let dispatchedToday: Int
        public let pendingTimeOff: Int

        public init(scheduledToday: Int, dispatchedToday: Int, pendingTimeOff: Int) {
            self.scheduledToday = scheduledToday
            self.dispatchedToday = dispatchedToday
            self.pendingTimeOff = pendingTimeOff
        }
    }

    // =========================================================================
    // MARK: - 1. My Schedule
    // =========================================================================

    /// Get schedule entries for a specific user within a date range.
    public func getMySchedule(
        userId: Int64,
        startDate: String,
        endDate: String
    ) throws -> [ScheduleEntry] {
        do {
            return try db.writer.read { dbConn -> [ScheduleEntry] in
                let sql = """
                    SELECT jd.id, jd.dispatch_date AS date,
                           jd.shift_start AS start_time, jd.shift_end AS end_time,
                           jd.status, jd.notes,
                           COALESCE(j.job_name, 'Unassigned') AS job_name
                    FROM job_dispatch jd
                    LEFT JOIN jobs j ON j.id = jd.job_id
                    WHERE jd.user_id = ?
                      AND jd.dispatch_date >= ?
                      AND jd.dispatch_date <= ?
                      AND jd.deleted_at IS NULL
                    ORDER BY jd.dispatch_date ASC, jd.shift_start ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [userId, startDate, endDate])
                return rows.map { row in
                    ScheduleEntry(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "Unassigned",
                        date: row["date"] ?? "",
                        startTime: row["start_time"] as String?,
                        endTime: row["end_time"] as String?,
                        status: row["status"] ?? "scheduled",
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Dispatch Board
    // =========================================================================

    /// Get the dispatch board for a given date — all dispatch entries with
    /// user, job, and vehicle names resolved.
    public func getDispatchBoard(date: String) throws -> [DispatchRow] {
        do {
            return try db.writer.read { dbConn -> [DispatchRow] in
                let sql = """
                    SELECT jd.id, jd.status, jd.notes,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                           COALESCE(j.job_name, 'Unassigned') AS job_name,
                           NULL AS vehicle_name
                    FROM job_dispatch jd
                    LEFT JOIN users u ON u.id = jd.user_id
                    LEFT JOIN jobs j ON j.id = jd.job_id
                    WHERE jd.dispatch_date = ?
                      AND jd.deleted_at IS NULL
                    ORDER BY u.display_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [date])
                return rows.map { row in
                    DispatchRow(
                        id: row["id"] ?? 0,
                        userName: row["user_name"] ?? "Unknown",
                        jobName: row["job_name"] ?? "Unassigned",
                        vehicleName: row["vehicle_name"] as String?,
                        status: row["status"] ?? "pending",
                        notes: row["notes"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Time-Off Requests
    // =========================================================================

    /// List time-off requests, optionally filtered by user and/or status.
    public func listTimeOffRequests(
        userId: Int64? = nil,
        status: String? = nil
    ) throws -> [TimeOffRow] {
        do {
            return try db.writer.read { dbConn -> [TimeOffRow] in
                var whereClauses = ["se.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []

                if let userId {
                    whereClauses.append("se.user_id = ?")
                    args.append(userId)
                }
                if let status, !status.isEmpty {
                    let statusCondition = status == "approved"
                        ? "se.is_approved = 1"
                        : "se.is_approved = 0"
                    whereClauses.append(statusCondition)
                }

                let sql = """
                    SELECT se.id, se.exception_date AS start_date,
                           se.exception_date AS end_date, se.reason,
                           CASE WHEN se.is_approved = 1 THEN 'approved' ELSE 'pending' END AS status,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                           COALESCE(ua.display_name, ua.email) AS approved_by_name
                    FROM schedule_exceptions se
                    LEFT JOIN users u ON u.id = se.user_id
                    LEFT JOIN users ua ON ua.id = se.approved_by
                    WHERE se.exception_type = 'time_off'
                      AND \(whereClauses.joined(separator: " AND "))
                    ORDER BY se.exception_date DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    TimeOffRow(
                        id: row["id"] ?? 0,
                        userName: row["user_name"] ?? "Unknown",
                        startDate: row["start_date"] ?? "",
                        endDate: row["end_date"] ?? "",
                        reason: row["reason"] as String?,
                        status: row["status"] ?? "pending",
                        approvedByName: row["approved_by_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a new time-off request. Returns the inserted row ID.
    @discardableResult
    public func createTimeOffRequest(
        userId: Int64,
        startDate: String,
        endDate: String,
        reason: String? = nil
    ) throws -> Int64 {
        // Generate all dates in the range [startDate, endDate]
        let dates = Self.datesInRange(from: startDate, to: endDate)
        guard !dates.isEmpty else {
            // Fallback: at least insert the start date
            return try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: """
                        INSERT INTO schedule_exceptions
                        (user_id, exception_date, exception_type, reason, is_approved, created_at)
                        VALUES (?, ?, 'time_off', ?, 0, datetime('now'))
                        """,
                    arguments: [userId, startDate, reason]
                )
                return dbConn.lastInsertedRowID
            }
        }

        return try db.writer.write { dbConn in
            var firstId: Int64 = 0
            for (i, date) in dates.enumerated() {
                try dbConn.execute(
                    sql: """
                        INSERT OR IGNORE INTO schedule_exceptions
                        (user_id, exception_date, exception_type, reason, is_approved, created_at)
                        VALUES (?, ?, 'time_off', ?, 0, datetime('now'))
                        """,
                    arguments: [userId, date, reason]
                )
                if i == 0 { firstId = dbConn.lastInsertedRowID }
            }
            return firstId
        }
    }

    /// Generate an array of date strings from start to end (inclusive), format "YYYY-MM-DD".
    private static func datesInRange(from start: String, to end: String) -> [String] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")

        guard let startDate = fmt.date(from: String(start.prefix(10))),
              let endDate = fmt.date(from: String(end.prefix(10))) else {
            return []
        }

        var dates: [String] = []
        var current = startDate
        while current <= endDate {
            dates.append(fmt.string(from: current))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    /// Update the status of a time-off request (e.g. approve or deny).
    public func updateTimeOffStatus(
        id: Int64,
        status: String,
        approvedBy: Int64? = nil
    ) throws {
        let validStatuses = ["pending", "approved", "denied", "cancelled"]
        guard validStatuses.contains(status) else {
            throw SchedulingError.invalidStatus(status)
        }

        try db.writer.write { dbConn in
            // Verify the request exists
            let count = try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM schedule_exceptions WHERE id = ? AND exception_type = 'time_off' AND deleted_at IS NULL",
                arguments: [id]
            ) ?? 0

            guard count > 0 else {
                throw SchedulingError.timeOffRequestNotFound(id)
            }

            let isApproved = status == "approved" ? 1 : 0
            if status == "approved", let approvedBy {
                try dbConn.execute(
                    sql: """
                        UPDATE schedule_exceptions
                        SET is_approved = ?, approved_by = ?, approved_at = datetime('now')
                        WHERE id = ?
                        """,
                    arguments: [isApproved, approvedBy, id]
                )
            } else {
                try dbConn.execute(
                    sql: """
                        UPDATE schedule_exceptions
                        SET is_approved = ?
                        WHERE id = ?
                        """,
                    arguments: [isApproved, id]
                )
            }
        }
    }

    // =========================================================================
    // MARK: - 4. Dispatch Templates
    // =========================================================================

    /// List all dispatch templates (excludes soft-deleted).
    public func listDispatchTemplates() throws -> [TemplateListItem] {
        do {
            return try db.writer.read { dbConn -> [TemplateListItem] in
                let sql = """
                    SELECT id, name, description, is_active
                    FROM dispatch_templates
                    WHERE deleted_at IS NULL
                    ORDER BY name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    TemplateListItem(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        description: row["description"] as String?,
                        isActive: (row["is_active"] as Int?) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Dispatch Creation
    // =========================================================================

    /// Creates a new dispatch entry (assign user to job on a date).
    @discardableResult
    public func createDispatch(
        jobId: Int64,
        userId: Int64,
        date: String,
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO job_dispatch
                    (job_id, user_id, dispatch_date, notes, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'scheduled', datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, userId, date, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 6. Schedule Entry Creation
    // =========================================================================

    /// Creates a new schedule entry (schedule a user for a job on a date with optional times).
    @discardableResult
    public func createScheduleEntry(
        userId: Int64,
        jobId: Int64,
        date: String,
        startTime: String? = nil,
        endTime: String? = nil,
        notes: String? = nil
    ) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    INSERT INTO job_dispatch
                    (job_id, user_id, dispatch_date, shift_start, shift_end, notes, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'scheduled', datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, userId, date, startTime, endTime, notes]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 7. Scheduling Stats
    // =========================================================================

    /// Get scheduling dashboard stats: scheduled today, dispatched today, pending time-off.
    public func getSchedulingStats() throws -> SchedulingStats {
        let scheduledToday = try safeCount(
            sql: """
                SELECT COUNT(*) FROM job_dispatch
                WHERE dispatch_date = date('now') AND deleted_at IS NULL
                """
        )

        let dispatchedToday = try safeCount(
            sql: """
                SELECT COUNT(*) FROM job_dispatch
                WHERE dispatch_date = date('now') AND status = 'dispatched' AND deleted_at IS NULL
                """
        )

        let pendingTimeOff = try safeCount(
            sql: """
                SELECT COUNT(*) FROM schedule_exceptions
                WHERE exception_type = 'time_off' AND is_approved = 0 AND deleted_at IS NULL
                """
        )

        return SchedulingStats(
            scheduledToday: scheduledToday,
            dispatchedToday: dispatchedToday,
            pendingTimeOff: pendingTimeOff
        )
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) query returning an Int.
    /// Returns 0 if the table does not exist.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConn in
                try Int.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }
}
