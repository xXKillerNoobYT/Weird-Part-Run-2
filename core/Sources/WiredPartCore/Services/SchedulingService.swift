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
    private let auth: AuthService

    public init(db: AppDatabase, auth: AuthService? = nil) {
        self.db = db
        self.auth = auth ?? AuthService(db: db)
    }

    // =========================================================================
    // MARK: - Error Types
    // =========================================================================

    public enum SchedulingError: Error, Sendable, Equatable {
        case timeOffRequestNotFound(Int64)
        case invalidStatus(String)
        case insertFailed(String)
        case doubleBooking(userId: Int64, date: String)
        /// Dispatcher attempted to create a dispatch for a user who has approved time-off on that date.
        /// Fix #355: service-layer enforcement so all callers (sync, AI, future pages) are covered.
        case timeOffConflict(userId: Int64, date: String, reason: String?)
        /// Approver attempted to approve time-off that conflicts with N existing dispatches.
        /// Fix #207: surfaces the conflict so UI can require cancellation/resolution first.
        case timeOffConflictsWithDispatch(conflicts: Int)
        case invalidDateRange(start: String, end: String)
        case invalidDate(String)
        case requiredFieldEmpty
        case jobNotFound(Int64)
        case userNotFound(Int64)
        case insufficientPermissions(required: String)
        case contractorNotFound(Int64)
        case subcontractorScheduleNotFound(Int64)
        case subcontractorScheduleConflict(jobId: Int64, gcId: Int64, date: String)
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
        public let timeSlot: String
        public let userName: String?

        public init(
            id: Int64, jobName: String, date: String,
            startTime: String?, endTime: String?,
            status: String, notes: String?,
            timeSlot: String = "full", userName: String? = nil
        ) {
            self.id = id
            self.jobName = jobName
            self.date = date
            self.startTime = startTime
            self.endTime = endTime
            self.status = status
            self.notes = notes
            self.timeSlot = timeSlot
            self.userName = userName
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

    /// A flex-pool dispatch assignment waiting on manager approval.
    public struct ScheduleChangeApproval: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let userId: Int64
        public let jobName: String
        public let userName: String
        public let dispatchDate: String
        public let timeSlot: String
        public let createdAt: String

        public init(
            id: Int64,
            jobId: Int64,
            userId: Int64,
            jobName: String,
            userName: String,
            dispatchDate: String,
            timeSlot: String,
            createdAt: String
        ) {
            self.id = id
            self.jobId = jobId
            self.userId = userId
            self.jobName = jobName
            self.userName = userName
            self.dispatchDate = dispatchDate
            self.timeSlot = timeSlot
            self.createdAt = createdAt
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

    /// A subcontractor schedule row for the sub-schedule list and add/edit forms.
    public struct SubScheduleRow: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let gcId: Int64
        public let subName: String
        public let companyName: String
        public let jobName: String
        public let scheduleDate: String
        public let status: String
        public let arrivalTime: String?
        public let departureTime: String?
        public let scopeOfWork: String?
        public let notes: String?

        public init(
            id: Int64,
            jobId: Int64 = 0,
            gcId: Int64 = 0,
            subName: String,
            companyName: String,
            jobName: String,
            scheduleDate: String,
            status: String,
            arrivalTime: String? = nil,
            departureTime: String? = nil,
            scopeOfWork: String? = nil,
            notes: String? = nil
        ) {
            self.id = id
            self.jobId = jobId
            self.gcId = gcId
            self.subName = subName
            self.companyName = companyName
            self.jobName = jobName
            self.scheduleDate = scheduleDate
            self.status = status
            self.arrivalTime = arrivalTime
            self.departureTime = departureTime
            self.scopeOfWork = scopeOfWork
            self.notes = notes
        }
    }

    /// A weekly-availability row: one employee and their 7-day availability flags (Mon-Sun).
    public struct WeeklyAvailabilityRow: Sendable, Identifiable {
        public let id: Int64
        public let employeeName: String
        /// Mon-Sun, 7 entries; `true` = available.
        public let days: [Bool]

        public init(id: Int64, employeeName: String, days: [Bool]) {
            self.id = id
            self.employeeName = employeeName
            self.days = days
        }
    }

    /// Summary of schedule data for a single day (month view).
    public struct DayScheduleSummary: Sendable {
        public let date: String
        public let amCount: Int
        public let pmCount: Int
        public let fullDayCount: Int
        public let totalWorkers: Int
        public let timeOffCount: Int

        public init(date: String, amCount: Int, pmCount: Int, fullDayCount: Int, totalWorkers: Int, timeOffCount: Int) {
            self.date = date
            self.amCount = amCount
            self.pmCount = pmCount
            self.fullDayCount = fullDayCount
            self.totalWorkers = totalWorkers
            self.timeOffCount = timeOffCount
        }
    }

    /// A time-off entry for the day detail view.
    public struct TimeOffEntry: Sendable, Identifiable {
        public let id: Int64
        public let employeeName: String
        public let reason: String?

        public init(id: Int64, employeeName: String, reason: String?) {
            self.id = id
            self.employeeName = employeeName
            self.reason = reason
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
                           COALESCE(jd.time_slot, 'full') AS time_slot,
                           COALESCE(j.job_name, 'Unassigned') AS job_name,
                           COALESCE(u.display_name, u.email) AS user_name
                    FROM job_dispatch jd
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jd.user_id AND u.deleted_at IS NULL
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
                        notes: row["notes"] as String?,
                        timeSlot: row["time_slot"] ?? "full",
                        userName: row["user_name"] as String?
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
                    LEFT JOIN users u ON u.id = jd.user_id AND u.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
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

                // Group consecutive days belonging to the same multi-day request.
                // Rows with a shared `request_group` UUID (set at insert time) are
                // collapsed into a single TimeOffRow spanning [MIN date, MAX date].
                // Legacy rows (request_group IS NULL) each map to a single-day request
                // via COALESCE(request_group, CAST(id AS TEXT)) as the grouping key.
                let sql = """
                    SELECT MIN(se.id) AS id,
                           MIN(se.exception_date) AS start_date,
                           MAX(se.exception_date) AS end_date,
                           se.reason,
                           CASE WHEN MAX(se.is_approved) = 1 THEN 'approved' ELSE 'pending' END AS status,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                           COALESCE(ua.display_name, ua.email) AS approved_by_name
                    FROM schedule_exceptions se
                    LEFT JOIN users u ON u.id = se.user_id AND u.deleted_at IS NULL
                    LEFT JOIN users ua ON ua.id = se.approved_by AND ua.deleted_at IS NULL
                    WHERE se.exception_type = 'time_off'
                      AND \(whereClauses.joined(separator: " AND "))
                    GROUP BY COALESCE(se.request_group, CAST(se.id AS TEXT)), se.user_id
                    ORDER BY start_date DESC
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

    /// Create a new time-off request. Returns the inserted row ID, or 0 if the user is tombstoned.
    @discardableResult
    public func createTimeOffRequest(
        userId: Int64,
        startDate: String,
        endDate: String,
        reason: String? = nil
    ) throws -> Int64 {
        guard !startDate.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        guard !endDate.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        // Guard: user must exist and not be tombstoned — otherwise the INSERT INTO
        // schedule_exceptions below would create orphan time-off rows against a
        // soft-deleted user (the FK constraint allows the write; deleted_at doesn't).
        let userExists = try db.writer.read { dbConn -> Bool in
            (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [userId]) ?? 0) > 0
        }
        guard userExists else { return 0 }

        // Validate date ordering: end must be on or after start.
        // datesInRange silently returns [] for reversed ranges, which would fall
        // back to just the start date — a confusing silent degradation.
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        if let s = fmt.date(from: String(startDate.prefix(10))),
           let e = fmt.date(from: String(endDate.prefix(10))),
           e < s {
            throw SchedulingError.invalidDateRange(start: startDate, end: endDate)
        }

        // Generate all dates in the range [startDate, endDate]
        let dates = Self.datesInRange(from: startDate, to: endDate)
        // A shared UUID links all per-day rows back to one logical request so
        // listTimeOffRequests() can group them into a single TimeOffRow.
        let requestGroup = UUID().uuidString
        guard !dates.isEmpty else {
            // Fallback: insert just the start date with the group key.
            return try db.writer.write { dbConn in
                try dbConn.execute(
                    sql: """
                        INSERT INTO schedule_exceptions
                        (user_id, exception_date, exception_type, reason, is_approved, request_group, created_at)
                        VALUES (?, ?, 'time_off', ?, 0, ?, datetime('now'))
                        """,
                    arguments: [userId, startDate, reason, requestGroup]
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
                        (user_id, exception_date, exception_type, reason, is_approved, request_group, created_at)
                        VALUES (?, ?, 'time_off', ?, 0, ?, datetime('now'))
                        """,
                    arguments: [userId, date, reason, requestGroup]
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

        let requiredPermission = "approve_time_off"
        let requiresApprovalActor = status == "approved" || status == "denied"
        if requiresApprovalActor || approvedBy != nil {
            guard let approvedBy,
                  try auth.hasPermission(approvedBy, permissionKey: requiredPermission) else {
                throw SchedulingError.insufficientPermissions(required: requiredPermission)
            }
        }

        try db.writer.write { dbConn in
            // Verify the row exists and retrieve its request_group so we can
            // update every day in the same multi-day request atomically.
            guard let row = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT id, request_group FROM schedule_exceptions
                    WHERE id = ? AND exception_type = 'time_off' AND deleted_at IS NULL
                    """,
                arguments: [id]
            ) else {
                throw SchedulingError.timeOffRequestNotFound(id)
            }

            let requestGroup: String? = row["request_group"]
            let isApproved = status == "approved" ? 1 : 0

            // Fix #207: On approval, scan for overlapping dispatches and reject if any exist.
            // This forces the approver to cancel/resolve the dispatch before PTO is granted,
            // preventing the state where an employee has approved PTO AND an active dispatch
            // on the same day.
            if status == "approved" {
                let dateRows: [Row]
                if let group = requestGroup {
                    dateRows = try Row.fetchAll(dbConn, sql: """
                        SELECT user_id, exception_date FROM schedule_exceptions
                        WHERE request_group = ? AND exception_type = 'time_off' AND deleted_at IS NULL
                        """, arguments: [group])
                } else {
                    dateRows = try Row.fetchAll(dbConn, sql: """
                        SELECT user_id, exception_date FROM schedule_exceptions
                        WHERE id = ? AND deleted_at IS NULL
                        """, arguments: [id])
                }

                var totalConflicts = 0
                for dr in dateRows {
                    let uid: Int64 = dr["user_id"]
                    let date: String = dr["exception_date"] ?? ""
                    guard !date.isEmpty else { continue }
                    let count = try Int.fetchOne(dbConn, sql: """
                        SELECT COUNT(*) FROM job_dispatch
                        WHERE user_id = ? AND dispatch_date = ? AND deleted_at IS NULL
                        """, arguments: [uid, date]) ?? 0
                    totalConflicts += count
                }
                if totalConflicts > 0 {
                    throw SchedulingError.timeOffConflictsWithDispatch(conflicts: totalConflicts)
                }
            }

            // Build a WHERE clause that matches all days of the same request:
            // if request_group is set, target the whole group; otherwise just this row.
            if status == "approved" {
                if let group = requestGroup {
                    try dbConn.execute(
                        sql: """
                            UPDATE schedule_exceptions
                            SET is_approved = ?, approved_by = ?, approved_at = datetime('now')
                            WHERE request_group = ? AND exception_type = 'time_off' AND deleted_at IS NULL
                            """,
                        arguments: [isApproved, approvedBy, group]
                    )
                } else {
                    try dbConn.execute(
                        sql: """
                            UPDATE schedule_exceptions
                            SET is_approved = ?, approved_by = ?, approved_at = datetime('now')
                            WHERE id = ? AND deleted_at IS NULL
                            """,
                        arguments: [isApproved, approvedBy, id]
                    )
                }
            } else {
                if let group = requestGroup {
                    try dbConn.execute(
                        sql: """
                            UPDATE schedule_exceptions
                            SET is_approved = ?, approved_by = NULL, approved_at = NULL
                            WHERE request_group = ? AND exception_type = 'time_off' AND deleted_at IS NULL
                            """,
                        arguments: [isApproved, group]
                    )
                } else {
                    try dbConn.execute(
                        sql: """
                            UPDATE schedule_exceptions
                            SET is_approved = ?, approved_by = NULL, approved_at = NULL
                            WHERE id = ? AND deleted_at IS NULL
                            """,
                        arguments: [isApproved, id]
                    )
                }
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
    // MARK: - 5. Sub Schedule
    // =========================================================================

    /// Get subcontractor schedule rows for a given date.
    public func getSubSchedule(date: String) throws -> [SubScheduleRow] {
        let normalizedDate = try Self.normalizeScheduleDateOnly(date)
        do {
            return try db.writer.read { dbConn -> [SubScheduleRow] in
                let sql = """
                    SELECT ss.id,
                           ss.job_id,
                           ss.gc_id,
                           COALESCE(gc.contact_name, gc.company_name, 'Unknown') AS sub_name,
                           COALESCE(gc.company_name, '') AS company_name,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           ss.scheduled_date AS schedule_date,
                           COALESCE(ss.status, 'scheduled') AS status,
                           ss.arrival_time,
                           ss.departure_time,
                           ss.scope_of_work,
                           ss.notes
                    FROM subcontractor_schedules ss
                    LEFT JOIN general_contractors gc ON gc.id = ss.gc_id AND gc.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = ss.job_id AND j.deleted_at IS NULL
                    WHERE ss.scheduled_date = ?
                      AND ss.deleted_at IS NULL
                    ORDER BY sub_name
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [normalizedDate])
                return rows.map { row in
                    SubScheduleRow(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        gcId: row["gc_id"] ?? 0,
                        subName: row["sub_name"] ?? "Unknown",
                        companyName: row["company_name"] ?? "",
                        jobName: row["job_name"] ?? "Unknown Job",
                        scheduleDate: row["schedule_date"] ?? normalizedDate,
                        status: row["status"] ?? "scheduled",
                        arrivalTime: row["arrival_time"],
                        departureTime: row["departure_time"],
                        scopeOfWork: row["scope_of_work"],
                        notes: row["notes"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Create a subcontractor schedule row with strict date-only validation.
    @discardableResult
    public func createSubcontractorSchedule(
        jobId: Int64,
        gcId: Int64,
        scheduledDate: String,
        arrivalTime: String? = nil,
        departureTime: String? = nil,
        scopeOfWork: String? = nil,
        status: String = "scheduled",
        notes: String? = nil,
        createdBy: Int64? = nil
    ) throws -> Int64 {
        let normalizedDate = try Self.normalizeScheduleDateOnly(scheduledDate)
        let normalizedStatus = try Self.normalizeSubcontractorScheduleStatus(status)
        let normalizedArrivalTime = Self.normalizeOptionalSubcontractorScheduleText(arrivalTime)
        let normalizedDepartureTime = Self.normalizeOptionalSubcontractorScheduleText(departureTime)
        try Self.validateSubcontractorScheduleTimeRange(arrivalTime: normalizedArrivalTime, departureTime: normalizedDepartureTime)
        let normalizedScopeOfWork = Self.normalizeOptionalSubcontractorScheduleText(scopeOfWork)
        let normalizedNotes = Self.normalizeOptionalSubcontractorScheduleText(notes)

        return try db.writer.write { dbConn in
            try validateSubcontractorScheduleParents(dbConn, jobId: jobId, gcId: gcId)
            try guardNoActiveSubcontractorScheduleConflict(dbConn, jobId: jobId, gcId: gcId, date: normalizedDate)

            try dbConn.execute(
                sql: """
                    INSERT INTO subcontractor_schedules
                    (job_id, gc_id, scheduled_date, arrival_time, departure_time, scope_of_work, status, notes, created_by, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, gcId, normalizedDate, normalizedArrivalTime, normalizedDepartureTime, normalizedScopeOfWork, normalizedStatus, normalizedNotes, createdBy]
            )
            return dbConn.lastInsertedRowID
        }
    }

    /// Update all editable subcontractor schedule fields used by the add/edit flow.
    public func updateSubcontractorSchedule(
        id: Int64,
        jobId: Int64,
        gcId: Int64,
        scheduledDate: String,
        arrivalTime: String? = nil,
        departureTime: String? = nil,
        scopeOfWork: String? = nil,
        status: String = "scheduled",
        notes: String? = nil
    ) throws {
        let normalizedDate = try Self.normalizeScheduleDateOnly(scheduledDate)
        let normalizedStatus = try Self.normalizeSubcontractorScheduleStatus(status)
        let normalizedArrivalTime = Self.normalizeOptionalSubcontractorScheduleText(arrivalTime)
        let normalizedDepartureTime = Self.normalizeOptionalSubcontractorScheduleText(departureTime)
        try Self.validateSubcontractorScheduleTimeRange(arrivalTime: normalizedArrivalTime, departureTime: normalizedDepartureTime)
        let normalizedScopeOfWork = Self.normalizeOptionalSubcontractorScheduleText(scopeOfWork)
        let normalizedNotes = Self.normalizeOptionalSubcontractorScheduleText(notes)

        try db.writer.write { dbConn in
            let scheduleExists = (try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM subcontractor_schedules WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            ) ?? 0) > 0
            guard scheduleExists else { throw SchedulingError.subcontractorScheduleNotFound(id) }

            try validateSubcontractorScheduleParents(dbConn, jobId: jobId, gcId: gcId)

            let conflictCount = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*)
                    FROM subcontractor_schedules
                    WHERE job_id = ?
                      AND gc_id = ?
                      AND scheduled_date = ?
                      AND deleted_at IS NULL
                      AND id <> ?
                    """,
                arguments: [jobId, gcId, normalizedDate, id]
            ) ?? 0
            if conflictCount > 0 {
                throw SchedulingError.subcontractorScheduleConflict(jobId: jobId, gcId: gcId, date: normalizedDate)
            }

            try dbConn.execute(
                sql: """
                    UPDATE subcontractor_schedules
                    SET job_id = ?,
                        gc_id = ?,
                        scheduled_date = ?,
                        arrival_time = ?,
                        departure_time = ?,
                        scope_of_work = ?,
                        status = ?,
                        notes = ?,
                        updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [jobId, gcId, normalizedDate, normalizedArrivalTime, normalizedDepartureTime, normalizedScopeOfWork, normalizedStatus, normalizedNotes, id]
            )
        }
    }

    /// Backwards-compatible date-only correction helper for existing callers.
    public func updateSubcontractorScheduleDate(id: Int64, scheduledDate: String) throws {
        let normalizedDate = try Self.normalizeScheduleDateOnly(scheduledDate)

        try db.writer.write { dbConn in
            guard let existing = try Row.fetchOne(
                dbConn,
                sql: """
                    SELECT job_id, gc_id
                    FROM subcontractor_schedules
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [id]
            ) else {
                throw SchedulingError.subcontractorScheduleNotFound(id)
            }

            let jobId: Int64 = existing["job_id"]
            let gcId: Int64 = existing["gc_id"]
            try validateSubcontractorScheduleParents(dbConn, jobId: jobId, gcId: gcId)

            let conflictCount = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*)
                    FROM subcontractor_schedules
                    WHERE job_id = ?
                      AND gc_id = ?
                      AND scheduled_date = ?
                      AND deleted_at IS NULL
                      AND id <> ?
                    """,
                arguments: [jobId, gcId, normalizedDate, id]
            ) ?? 0
            if conflictCount > 0 {
                throw SchedulingError.subcontractorScheduleConflict(jobId: jobId, gcId: gcId, date: normalizedDate)
            }

            try dbConn.execute(
                sql: """
                    UPDATE subcontractor_schedules
                    SET scheduled_date = ?, updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [normalizedDate, id]
            )
        }
    }

    /// Soft-delete a subcontractor schedule so it disappears from scheduling views.
    public func cancelSubcontractorSchedule(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE subcontractor_schedules
                    SET status = 'cancelled', deleted_at = datetime('now'), updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [id]
            )

            guard dbConn.changesCount > 0 else {
                throw SchedulingError.subcontractorScheduleNotFound(id)
            }
        }
    }

    // =========================================================================
    // MARK: - 6. Weekly Availability
    // =========================================================================

    /// Get employee weekly availability for the week starting at `weekStartDate`.
    /// Returns one row per employee with a 7-element `days` array (Mon-Sun).
    /// `true` = available (no schedule exception on that day).
    public func getWeeklyAvailability(weekStartDate: Date) throws -> [WeeklyAvailabilityRow] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let dateStrings = (0..<7).map { offset -> String in
            let d = Calendar.current.date(byAdding: .day, value: offset, to: weekStartDate) ?? weekStartDate
            return f.string(from: d)
        }

        do {
            return try db.writer.read { dbConn -> [WeeklyAvailabilityRow] in
                let empSql = "SELECT id, COALESCE(display_name, email) AS name FROM users WHERE deleted_at IS NULL AND is_active = 1 ORDER BY name"
                let employees = try Row.fetchAll(dbConn, sql: empSql)

                return try employees.map { emp -> WeeklyAvailabilityRow in
                    let empId: Int64 = emp["id"] ?? 0
                    let name: String = emp["name"] ?? "Unknown"

                    let days = try dateStrings.map { dateStr -> Bool in
                        let countSql = "SELECT COUNT(*) FROM schedule_exceptions WHERE user_id = ? AND exception_date = ? AND deleted_at IS NULL"
                        let count = try Int.fetchOne(dbConn, sql: countSql, arguments: [empId, dateStr]) ?? 0
                        return count == 0
                    }

                    return WeeklyAvailabilityRow(id: empId, employeeName: name, days: days)
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. Dispatch Creation

    // =========================================================================

    /// Creates a new dispatch entry (assign user to job on a date).
    /// Checks for double-booking before inserting (fixes #198).
    /// Checks for approved time-off conflict before inserting (fixes #355).
    /// Pass `forceCreateDespiteTimeOff: true` for the explicit "Assign anyway?" UI override.
    @discardableResult
    public func createDispatch(
        jobId: Int64,
        userId: Int64,
        date: String,
        notes: String? = nil,
        forceCreateDespiteTimeOff: Bool = false
    ) throws -> Int64 {
        guard !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        // Service-layer time-off conflict enforcement (fixes #355).
        // Runs outside the write closure since checkTimeOffConflict uses db.writer.read.
        if !forceCreateDespiteTimeOff {
            if let conflict = try checkTimeOffConflict(employeeId: userId, date: date) {
                throw SchedulingError.timeOffConflict(
                    userId: userId,
                    date: date,
                    reason: conflict.reason
                )
            }
        }
        return try db.writer.write { dbConn -> Int64 in
            // Guard: job + user must exist and not be tombstoned — otherwise the
            // INSERT creates an orphan job_dispatch row pointing at a deleted job/user,
            // invisible to listDispatches' deleted_at filter but blocking future
            // createDispatch calls via the double-booking check.
            let jobExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId]) ?? 0) > 0
            guard jobExists else { throw SchedulingError.jobNotFound(jobId) }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [userId]) ?? 0) > 0
            guard userExists else { throw SchedulingError.userNotFound(userId) }

            // Check for existing dispatch on this date for this user
            let existingCount = try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*) FROM job_dispatch
                    WHERE user_id = ? AND dispatch_date = ? AND deleted_at IS NULL
                    """,
                arguments: [userId, date]
            ) ?? 0
            if existingCount > 0 {
                throw SchedulingError.doubleBooking(userId: userId, date: date)
            }

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
    // MARK: - 7b. Weekly Dispatch Board (Gantt)
    // =========================================================================

    /// A dispatch assignment row for the Gantt-style board.
    public struct DispatchAssignment: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let employeeId: Int64
        public let employeeName: String
        public let employeeInitials: String
        public let date: String
        public let timeSlot: String
        public let status: String

        public init(
            id: Int64, jobId: Int64, jobName: String,
            employeeId: Int64, employeeName: String, employeeInitials: String,
            date: String, timeSlot: String, status: String
        ) {
            self.id = id
            self.jobId = jobId
            self.jobName = jobName
            self.employeeId = employeeId
            self.employeeName = employeeName
            self.employeeInitials = employeeInitials
            self.date = date
            self.timeSlot = timeSlot
            self.status = status
        }
    }

    /// A job row summary for the dispatch board.
    public struct DispatchJobRow: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let stageName: String?

        public init(id: Int64, jobName: String, stageName: String?) {
            self.id = id
            self.jobName = jobName
            self.stageName = stageName
        }
    }

    /// Get all dispatch assignments for a week.
    public func getWeeklyDispatchAssignments(weekStart: String, weekEnd: String) throws -> [DispatchAssignment] {
        do {
            return try db.writer.read { dbConn -> [DispatchAssignment] in
                let sql = """
                    SELECT jd.id, jd.job_id, jd.user_id AS employee_id,
                           jd.dispatch_date AS date,
                           COALESCE(jd.time_slot, 'full') AS time_slot,
                           jd.status,
                           COALESCE(j.job_name, 'Unassigned') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name
                    FROM job_dispatch jd
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jd.user_id AND u.deleted_at IS NULL
                    WHERE jd.dispatch_date >= ?
                      AND jd.dispatch_date <= ?
                      AND jd.deleted_at IS NULL
                    ORDER BY j.job_name, jd.dispatch_date
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [weekStart, weekEnd])
                return rows.map { row in
                    let name: String = row["employee_name"] ?? "Unknown"
                    let initials = Self.makeInitials(name)
                    return DispatchAssignment(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "Unassigned",
                        employeeId: row["employee_id"] ?? 0,
                        employeeName: name,
                        employeeInitials: initials,
                        date: row["date"] ?? "",
                        timeSlot: row["time_slot"] ?? "full",
                        status: row["status"] ?? "scheduled"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get active job rows for the dispatch board (jobs with active status).
    public func getDispatchJobRows() throws -> [DispatchJobRow] {
        do {
            return try db.writer.read { dbConn -> [DispatchJobRow] in
                let sql = """
                    SELECT j.id, j.job_name,
                           j.status AS stage_name
                    FROM jobs j
                    WHERE j.status = 'active'
                      AND j.deleted_at IS NULL
                    ORDER BY j.job_name
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    DispatchJobRow(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        stageName: row["stage_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get workers who have no dispatch assignments for the given week.
    public func getUnassignedWorkers(weekStart: String, weekEnd: String) throws -> [UnassignedWorker] {
        do {
            return try db.writer.read { dbConn -> [UnassignedWorker] in
                let sql = """
                    SELECT u.id, COALESCE(u.display_name, u.email, 'Unknown') AS name
                    FROM users u
                    WHERE u.deleted_at IS NULL
                      AND u.is_active = 1
                      AND u.id NOT IN (
                          SELECT DISTINCT jd.user_id FROM job_dispatch jd
                          WHERE jd.dispatch_date >= ?
                            AND jd.dispatch_date <= ?
                            AND jd.deleted_at IS NULL
                      )
                    ORDER BY name
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [weekStart, weekEnd])
                return rows.map { row in
                    UnassignedWorker(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "Unknown"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// An unassigned worker for the dispatch board.
    public struct UnassignedWorker: Sendable, Identifiable {
        public let id: Int64
        public let name: String

        public init(id: Int64, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// Check if a user has time off on a specific date.
    /// Returns the time-off entry if found, nil otherwise.
    public func checkTimeOffConflict(employeeId: Int64, date: String) throws -> TimeOffEntry? {
        do {
            return try db.writer.read { dbConn -> TimeOffEntry? in
                let sql = """
                    SELECT se.id, se.reason,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name
                    FROM schedule_exceptions se
                    LEFT JOIN users u ON u.id = se.user_id AND u.deleted_at IS NULL
                    WHERE se.user_id = ?
                      AND se.exception_date = ?
                      AND se.exception_type = 'time_off'
                      AND se.is_approved = 1
                      AND se.deleted_at IS NULL
                    LIMIT 1
                    """
                guard let row = try Row.fetchOne(dbConn, sql: sql, arguments: [employeeId, date]) else {
                    return nil
                }
                return TimeOffEntry(
                    id: row["id"] ?? 0,
                    employeeName: row["employee_name"] ?? "Unknown",
                    reason: row["reason"] as String?
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    /// Generate initials from a name (e.g., "John Smith" → "JS").
    private static func makeInitials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // =========================================================================
    // MARK: - 8. Schedule Entry Creation
    // =========================================================================

    /// Creates a new schedule entry (schedule a user for a job on a date with optional times).
    /// Checks for approved time-off conflict before inserting (mirrors createDispatch enforcement).
    /// Pass `forceCreateDespiteTimeOff: true` for the "Assign anyway?" explicit override.
    @discardableResult
    public func createScheduleEntry(
        userId: Int64,
        jobId: Int64,
        date: String,
        startTime: String? = nil,
        endTime: String? = nil,
        notes: String? = nil,
        timeSlot: String = "full",
        forceCreateDespiteTimeOff: Bool = false
    ) throws -> Int64 {
        guard !date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        // Service-layer time-off conflict enforcement (consistent with createDispatch).
        if !forceCreateDespiteTimeOff {
            if let conflict = try checkTimeOffConflict(employeeId: userId, date: date) {
                throw SchedulingError.timeOffConflict(
                    userId: userId,
                    date: date,
                    reason: conflict.reason
                )
            }
        }
        return try db.writer.write { dbConn -> Int64 in
            // Guard: job + user must exist and not be tombstoned.
            let jobExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId]) ?? 0) > 0
            guard jobExists else { throw SchedulingError.jobNotFound(jobId) }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [userId]) ?? 0) > 0
            guard userExists else { throw SchedulingError.userNotFound(userId) }

            try dbConn.execute(
                sql: """
                    INSERT INTO job_dispatch
                    (job_id, user_id, dispatch_date, shift_start, shift_end, notes, time_slot, status, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 'scheduled', datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, userId, date, startTime, endTime, notes, timeSlot]
            )
            return dbConn.lastInsertedRowID
        }
    }

    // =========================================================================
    // MARK: - 9. Month Schedule Summary
    // =========================================================================

    /// Get a summary of schedule data for each day in a given month.
    /// Used by the month calendar view to show dots/indicators.
    public func getMonthScheduleSummary(year: Int, month: Int) throws -> [String: DayScheduleSummary] {
        let startDate = String(format: "%04d-%02d-01", year, month)
        // Calculate last day of month
        var comps = DateComponents()
        comps.year = year
        comps.month = month + 1
        comps.day = 0
        let cal = Calendar.current
        let lastDay = cal.date(from: comps).map { cal.component(.day, from: $0) } ?? 28
        let endDate = String(format: "%04d-%02d-%02d", year, month, lastDay)

        do {
            return try db.writer.read { dbConn -> [String: DayScheduleSummary] in
                // Count schedule entries by date and time_slot
                let sql = """
                    SELECT jd.dispatch_date AS date,
                           COALESCE(jd.time_slot, 'full') AS time_slot,
                           COUNT(*) AS cnt
                    FROM job_dispatch jd
                    WHERE jd.dispatch_date >= ?
                      AND jd.dispatch_date <= ?
                      AND jd.deleted_at IS NULL
                    GROUP BY jd.dispatch_date, COALESCE(jd.time_slot, 'full')
                    ORDER BY jd.dispatch_date
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])

                // Count time-off entries by date
                let toSql = """
                    SELECT exception_date AS date, COUNT(*) AS cnt
                    FROM schedule_exceptions
                    WHERE exception_type = 'time_off'
                      AND exception_date >= ?
                      AND exception_date <= ?
                      AND deleted_at IS NULL
                    GROUP BY exception_date
                    """
                let toRows = try Row.fetchAll(dbConn, sql: toSql, arguments: [startDate, endDate])

                // Build time-off lookup
                var timeOffByDate: [String: Int] = [:]
                for row in toRows {
                    let date: String = row["date"] ?? ""
                    let cnt: Int = row["cnt"] ?? 0
                    timeOffByDate[date] = cnt
                }

                // Build schedule summary by date
                var tempData: [String: (am: Int, pm: Int, full: Int)] = [:]
                for row in rows {
                    let date: String = row["date"] ?? ""
                    let slot: String = row["time_slot"] ?? "full"
                    let cnt: Int = row["cnt"] ?? 0
                    var entry = tempData[date] ?? (am: 0, pm: 0, full: 0)
                    switch slot {
                    case "am": entry.am += cnt
                    case "pm": entry.pm += cnt
                    default: entry.full += cnt
                    }
                    tempData[date] = entry
                }

                // Merge into final summaries
                var result: [String: DayScheduleSummary] = [:]
                let allDates = Set(tempData.keys).union(timeOffByDate.keys)
                for date in allDates {
                    let sched = tempData[date] ?? (am: 0, pm: 0, full: 0)
                    let toCount = timeOffByDate[date] ?? 0
                    result[date] = DayScheduleSummary(
                        date: date,
                        amCount: sched.am,
                        pmCount: sched.pm,
                        fullDayCount: sched.full,
                        totalWorkers: sched.am + sched.pm + sched.full,
                        timeOffCount: toCount
                    )
                }
                return result
            }
        } catch {
            if isTableNotFoundError(error) { return [:] }
            throw error
        }
    }

    /// Get all schedule entries for a specific date (all users).
    /// Used by the day detail view.
    public func getScheduleEntriesForDate(date: String) throws -> [ScheduleEntry] {
        do {
            return try db.writer.read { dbConn -> [ScheduleEntry] in
                let sql = """
                    SELECT jd.id, jd.dispatch_date AS date,
                           jd.shift_start AS start_time, jd.shift_end AS end_time,
                           jd.status, jd.notes,
                           COALESCE(jd.time_slot, 'full') AS time_slot,
                           COALESCE(j.job_name, 'Unassigned') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name
                    FROM job_dispatch jd
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jd.user_id AND u.deleted_at IS NULL
                    WHERE jd.dispatch_date = ?
                      AND jd.deleted_at IS NULL
                    ORDER BY COALESCE(jd.time_slot, 'full'), u.display_name ASC
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [date])
                return rows.map { row in
                    ScheduleEntry(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "Unassigned",
                        date: row["date"] ?? "",
                        startTime: row["start_time"] as String?,
                        endTime: row["end_time"] as String?,
                        status: row["status"] ?? "scheduled",
                        notes: row["notes"] as String?,
                        timeSlot: row["time_slot"] ?? "full",
                        userName: row["user_name"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get time-off entries for a specific date.
    public func getTimeOffForDate(date: String) throws -> [TimeOffEntry] {
        do {
            return try db.writer.read { dbConn -> [TimeOffEntry] in
                let sql = """
                    SELECT se.id, se.reason,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name
                    FROM schedule_exceptions se
                    LEFT JOIN users u ON u.id = se.user_id AND u.deleted_at IS NULL
                    WHERE se.exception_date = ?
                      AND se.exception_type = 'time_off'
                      AND se.deleted_at IS NULL
                    ORDER BY employee_name
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [date])
                return rows.map { row in
                    TimeOffEntry(
                        id: row["id"] ?? 0,
                        employeeName: row["employee_name"] ?? "Unknown",
                        reason: row["reason"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 10. Scheduling Stats
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
    // MARK: - 11. Pipeline
    // =========================================================================

    /// A pipeline item representing a job ready or near-ready for scheduling.
    public struct PipelineItem: Sendable, Identifiable {
        public let id: Int64
        public let jobId: Int64
        public let jobName: String
        public let customerName: String
        public let estimatedDays: Int?
        public let pipelineCategory: String  // "start_anytime", "schedule_needed", "favorite_gc", "small_job"
        public let callbackDate: String?
        public let callbackSnoozedUntil: String?
        public let notes: String?

        public init(
            id: Int64, jobId: Int64, jobName: String, customerName: String,
            estimatedDays: Int?, pipelineCategory: String,
            callbackDate: String?, callbackSnoozedUntil: String?, notes: String?
        ) {
            self.id = id
            self.jobId = jobId
            self.jobName = jobName
            self.customerName = customerName
            self.estimatedDays = estimatedDays
            self.pipelineCategory = pipelineCategory
            self.callbackDate = callbackDate
            self.callbackSnoozedUntil = callbackSnoozedUntil
            self.notes = notes
        }
    }

    /// Get the short-term pipeline: active jobs categorized by readiness.
    /// Categories: start_anytime (no blockers), schedule_needed (need dispatch),
    /// favorite_gc (from preferred GCs), small_job (<=2 est. days).
    public func getShortTermPipeline() throws -> [PipelineItem] {
        do {
            return try db.writer.read { dbConn -> [PipelineItem] in
                // Active jobs not yet completed, that don't have future dispatches
                let sql = """
                    SELECT j.id, j.job_name,
                           COALESCE(j.customer_name, 'Unknown') AS customer_name,
                           CAST(COALESCE(j.estimated_hours, 0) / 8 AS INTEGER) AS estimated_days,
                           j.notes,
                           j.due_date AS callback_date,
                           (SELECT COUNT(*) FROM job_dispatch jd
                            WHERE jd.job_id = j.id
                              AND jd.dispatch_date >= date('now')
                              AND jd.deleted_at IS NULL) AS future_dispatches
                    FROM jobs j
                    WHERE j.status = 'active'
                      AND j.deleted_at IS NULL
                    ORDER BY j.job_name
                    """
                let rows = try Row.fetchAll(dbConn, sql: sql)

                return rows.compactMap { row -> PipelineItem? in
                    let id: Int64 = row["id"] ?? 0
                    let jobName: String = row["job_name"] ?? ""
                    let customerName: String = row["customer_name"] ?? "Unknown"
                    let estimatedDays: Int? = row["estimated_days"] as Int?
                    let futureDispatches: Int = row["future_dispatches"] ?? 0
                    let callbackDate: String? = row["callback_date"] as String?
                    let notes: String? = row["notes"] as String?

                    // Categorize
                    let category: String
                    if let days = estimatedDays, days <= 2 {
                        category = "small_job"
                    } else if futureDispatches == 0 {
                        category = "start_anytime"
                    } else {
                        category = "schedule_needed"
                    }

                    return PipelineItem(
                        id: id, jobId: id, jobName: jobName,
                        customerName: customerName,
                        estimatedDays: estimatedDays,
                        pipelineCategory: category,
                        callbackDate: callbackDate,
                        callbackSnoozedUntil: nil,
                        notes: notes
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Snooze a callback to a future date (updates the job's due_date).
    public func snoozeCallback(jobId: Int64, until: String) throws {
        guard !until.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE jobs SET due_date = ?, updated_at = datetime('now') WHERE id = ? AND deleted_at IS NULL",
                arguments: [until, jobId]
            )
        }
    }

    /// Mark a callback as complete (clear the due date).
    public func markCallbackComplete(jobId: Int64, notes: String?) throws {
        try db.writer.write { dbConn in
            if let notes, !notes.isEmpty {
                try dbConn.execute(
                    sql: "UPDATE jobs SET due_date = NULL, notes = COALESCE(notes || '\n', '') || ?, updated_at = datetime('now') WHERE id = ? AND deleted_at IS NULL",
                    arguments: [notes, jobId]
                )
            } else {
                try dbConn.execute(
                    sql: "UPDATE jobs SET due_date = NULL, updated_at = datetime('now') WHERE id = ? AND deleted_at IS NULL",
                    arguments: [jobId]
                )
            }
        }
    }

    // =========================================================================
    // MARK: - 12. Long-Term Pipeline
    // =========================================================================

    /// Monthly capacity summary for the long-term timeline.
    public struct MonthCapacity: Sendable, Identifiable {
        public let id: String           // "2026-04"
        public let monthLabel: String   // "April 2026"
        public let availableDays: Int   // work-days × crew size
        public let scheduledDays: Int   // sum of estimated job days
        public let jobCount: Int
        public let pendingBidCount: Int
        public let jobs: [JobSummary]

        public var utilizationPercent: Double {
            Double(scheduledDays) / max(Double(availableDays), 1)
        }

        public init(id: String, monthLabel: String, availableDays: Int, scheduledDays: Int,
                     jobCount: Int, pendingBidCount: Int, jobs: [JobSummary]) {
            self.id = id
            self.monthLabel = monthLabel
            self.availableDays = availableDays
            self.scheduledDays = scheduledDays
            self.jobCount = jobCount
            self.pendingBidCount = pendingBidCount
            self.jobs = jobs
        }
    }

    /// Job summary for month detail view.
    public struct JobSummary: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let estimatedDays: Int?
        public let status: String

        public init(id: Int64, name: String, estimatedDays: Int?, status: String) {
            self.id = id
            self.name = name
            self.estimatedDays = estimatedDays
            self.status = status
        }
    }

    /// AI-generated capacity warning.
    public struct CapacityWarning: Sendable, Identifiable {
        public let id: String
        public let month: String
        public let message: String
        public let suggestion: String
        public let isOvercommitted: Bool

        public init(id: String, month: String, message: String, suggestion: String, isOvercommitted: Bool) {
            self.id = id
            self.month = month
            self.message = message
            self.suggestion = suggestion
            self.isOvercommitted = isOvercommitted
        }
    }

    /// Intermediate job row used for in-memory month overlap filtering.
    private struct JobTimelineRow {
        let id: Int64
        let name: String
        let estimatedDays: Int?
        let status: String
        let startDate: String
        let dueDate: String?
    }

    /// Get a 36-month timeline of capacity data.
    /// Uses 2 batch queries (one for jobs, one for bid counts) instead of 72 per-month
    /// queries, reducing SQLite round-trips from O(months×2) to O(1).
    public func getLongTermTimeline(months: Int = 36) throws -> [MonthCapacity] {
        let cal = Calendar.current
        let today = Date()
        let crewSize = try getActiveCrewSize()
        let avgWorkDaysPerMonth = 22
        let availableDays = avgWorkDaysPerMonth * max(crewSize, 1)

        // Build month ranges up front
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        struct MonthRange {
            let id: String; let label: String; let start: String; let end: String
        }
        var monthRanges: [MonthRange] = []
        for offset in 0..<months {
            guard let monthDate = cal.date(byAdding: .month, value: offset, to: today) else { continue }
            let year = cal.component(.year, from: monthDate)
            let month = cal.component(.month, from: monthDate)
            let start = String(format: "%04d-%02d-01", year, month)
            var comps = DateComponents(); comps.year = year; comps.month = month + 1; comps.day = 0
            let lastDay = cal.date(from: comps).map { cal.component(.day, from: $0) } ?? 28
            let end = String(format: "%04d-%02d-%02d", year, month, lastDay)
            monthRanges.append(MonthRange(id: String(format: "%04d-%02d", year, month),
                                          label: f.string(from: monthDate),
                                          start: start, end: end))
        }
        guard !monthRanges.isEmpty else { return [] }

        // Batch query 1: all relevant jobs for the entire range (2 queries total)
        let allJobs = try batchFetchJobsInRange(from: monthRanges.first!.start, to: monthRanges.last!.end)

        // Batch query 2: bid counts per month + null-start bids (counted in every month)
        let (bidsByMonth, nullBidCount) = try batchFetchBidCounts(from: monthRanges.first!.start, to: monthRanges.last!.end)

        // Distribute results to months in memory
        return monthRanges.map { range in
            let monthJobs = allJobs.filter { job in
                let jobEnd = job.dueDate ?? "9999-12-31"
                return job.startDate <= range.end && jobEnd >= range.start
            }
            let scheduledDays = monthJobs.reduce(0) { $0 + ($1.estimatedDays ?? 0) }
            let pendingBids = (bidsByMonth[range.id] ?? 0) + nullBidCount
            return MonthCapacity(
                id: range.id, monthLabel: range.label, availableDays: availableDays,
                scheduledDays: scheduledDays, jobCount: monthJobs.count,
                pendingBidCount: pendingBids,
                jobs: monthJobs.map { JobSummary(id: $0.id, name: $0.name, estimatedDays: $0.estimatedDays, status: $0.status) }
            )
        }
    }

    /// Get active crew member count.
    private func getActiveCrewSize() throws -> Int {
        try safeCount(sql: "SELECT COUNT(*) FROM users WHERE is_active = 1 AND deleted_at IS NULL")
    }

    /// Batch-fetch all jobs overlapping [from, to] for the timeline.
    private func batchFetchJobsInRange(from firstStart: String, to lastEnd: String) throws -> [JobTimelineRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT DISTINCT j.id, j.job_name,
                           CAST(COALESCE(j.estimated_hours, 0) / 8 AS INTEGER) AS estimated_days,
                           j.status, j.start_date, j.due_date
                    FROM jobs j
                    WHERE j.deleted_at IS NULL
                      AND j.status IN ('active', 'scheduled', 'pending')
                      AND (
                          j.start_date <= ? AND (j.due_date >= ? OR j.due_date IS NULL)
                          OR j.start_date BETWEEN ? AND ?
                      )
                    ORDER BY j.job_name
                    """, arguments: [lastEnd, firstStart, firstStart, lastEnd])
                return rows.map { row in
                    JobTimelineRow(
                        id: row["id"] ?? 0,
                        name: row["job_name"] ?? "",
                        estimatedDays: row["estimated_days"] as Int?,
                        status: row["status"] ?? "",
                        startDate: row["start_date"] as String? ?? "",
                        dueDate: row["due_date"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Batch-fetch bid counts grouped by month + count of bids with null start_date.
    private func batchFetchBidCounts(from firstStart: String, to lastEnd: String) throws -> ([String: Int], Int) {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT STRFTIME('%Y-%m', start_date) AS month_key, COUNT(*) AS cnt
                    FROM jobs
                    WHERE status = 'bid' AND deleted_at IS NULL
                      AND start_date IS NOT NULL
                      AND start_date BETWEEN ? AND ?
                    GROUP BY STRFTIME('%Y-%m', start_date)
                    """, arguments: [firstStart, lastEnd])
                var byMonth: [String: Int] = [:]
                for row in rows {
                    if let key = row["month_key"] as String?, let cnt = row["cnt"] as Int? {
                        byMonth[key] = cnt
                    }
                }
                let nullCount = (try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM jobs
                    WHERE status = 'bid' AND deleted_at IS NULL AND start_date IS NULL
                    """) ?? 0)
                return (byMonth, nullCount)
            }
        } catch {
            if isTableNotFoundError(error) { return ([:], 0) }
            throw error
        }
    }

    /// Generate capacity warnings from timeline data.
    public func getCapacityWarnings(timeline: [MonthCapacity]) -> [CapacityWarning] {
        var warnings: [CapacityWarning] = []
        for month in timeline.prefix(12) {
            if month.utilizationPercent > 1.0 {
                warnings.append(CapacityWarning(
                    id: "over-\(month.id)",
                    month: month.monthLabel,
                    message: "\(month.monthLabel): Overcommitted at \(Int(month.utilizationPercent * 100))% capacity",
                    suggestion: "Consider pushing some jobs or hiring temporary help",
                    isOvercommitted: true
                ))
            } else if month.utilizationPercent < 0.3 && month.jobCount == 0 {
                warnings.append(CapacityWarning(
                    id: "under-\(month.id)",
                    month: month.monthLabel,
                    message: "\(month.monthLabel): No jobs scheduled",
                    suggestion: "Accelerate sales pipeline or pull jobs forward",
                    isOvercommitted: false
                ))
            }
        }
        return warnings
    }

    // =========================================================================
    // MARK: - Report Queries
    // =========================================================================

    /// Crew utilization row — scheduled hours vs available hours per employee.
    public struct CrewUtilizationRow: Sendable, Identifiable {
        public let id: Int64
        public let employeeName: String
        public let scheduledHours: Double
        public let availableHours: Double
        public let utilization: Double
    }

    /// Dispatch efficiency row — dispatched vs scheduled vs completed.
    public struct DispatchEfficiencyRow: Sendable, Identifiable {
        public let id: String
        public let date: String
        public let scheduledCount: Int
        public let dispatchedCount: Int
        public let completedCount: Int
        public let efficiency: Double
    }

    /// Pipeline summary row — job counts by status.
    public struct PipelineSummaryRow: Sendable, Identifiable {
        public let id: String
        public let status: String
        public let jobCount: Int
        public let totalEstimatedHours: Double
    }

    /// Get crew utilization for a date range: scheduled hours vs available hours per employee.
    public func getCrewUtilizationReport(startDate: Date, endDate: Date) throws -> [CrewUtilizationRow] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)
        let totalDays = max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        let availableHoursPerEmployee = Double(totalDays) * 8.0 // 8-hour workday assumption
        do {
            return try db.writer.read { dbConn -> [CrewUtilizationRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT u.id, COALESCE(u.display_name, u.email, 'Employee') AS employee_name,
                           COUNT(jd.id) AS dispatch_count,
                           COALESCE(SUM(
                               CASE
                                   WHEN jd.shift_start IS NOT NULL AND jd.shift_end IS NOT NULL
                                   THEN (julianday(jd.shift_end) - julianday(jd.shift_start)) * 24
                                   ELSE 8.0
                               END
                           ), 0) AS scheduled_hours
                    FROM users u
                    LEFT JOIN job_dispatch jd ON jd.user_id = u.id
                        AND jd.deleted_at IS NULL
                        AND jd.dispatch_date >= ? AND jd.dispatch_date <= ?
                    WHERE u.deleted_at IS NULL AND u.is_active = 1
                      AND u.id NOT IN (
                          SELECT uh.user_id FROM user_hats uh
                          JOIN hats h ON h.id = uh.hat_id
                          WHERE h.name = 'Admin' AND uh.deleted_at IS NULL
                      )
                    GROUP BY u.id
                    HAVING dispatch_count > 0
                    ORDER BY scheduled_hours DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    let hours: Double = row["scheduled_hours"] ?? 0
                    return CrewUtilizationRow(
                        id: row["id"] ?? 0,
                        employeeName: row["employee_name"] ?? "Unknown",
                        scheduledHours: hours,
                        availableHours: availableHoursPerEmployee,
                        utilization: min(1.0, hours / max(1, availableHoursPerEmployee))
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get dispatch efficiency by date — how many dispatches were completed vs scheduled.
    public func getDispatchEfficiencyReport(startDate: Date, endDate: Date) throws -> [DispatchEfficiencyRow] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)
        do {
            return try db.writer.read { dbConn -> [DispatchEfficiencyRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT dispatch_date,
                           COUNT(*) AS scheduled_count,
                           SUM(CASE WHEN status IN ('dispatched', 'completed') THEN 1 ELSE 0 END) AS dispatched_count,
                           SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed_count
                    FROM job_dispatch
                    WHERE deleted_at IS NULL
                      AND dispatch_date >= ? AND dispatch_date <= ?
                    GROUP BY dispatch_date
                    ORDER BY dispatch_date DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    let scheduled: Int = row["scheduled_count"] ?? 0
                    let completed: Int = row["completed_count"] ?? 0
                    let dateStr: String = row["dispatch_date"] ?? ""
                    return DispatchEfficiencyRow(
                        id: dateStr,
                        date: dateStr,
                        scheduledCount: scheduled,
                        dispatchedCount: row["dispatched_count"] ?? 0,
                        completedCount: completed,
                        efficiency: scheduled > 0 ? Double(completed) / Double(scheduled) : 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get pipeline summary — active jobs grouped by status.
    public func getPipelineSummaryReport() throws -> [PipelineSummaryRow] {
        do {
            return try db.writer.read { dbConn -> [PipelineSummaryRow] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT j.status,
                           COUNT(j.id) AS job_count,
                           COALESCE(SUM(j.estimated_hours), 0) AS total_estimated_hours
                    FROM jobs j
                    WHERE j.deleted_at IS NULL AND j.status != 'archived'
                    GROUP BY j.status
                    ORDER BY
                        CASE j.status
                            WHEN 'active' THEN 1
                            WHEN 'scheduled' THEN 2
                            WHEN 'pending' THEN 3
                            WHEN 'on_hold' THEN 4
                            WHEN 'completed' THEN 5
                            ELSE 6
                        END
                    """)
                return rows.map { row in
                    let status: String = row["status"] ?? "unknown"
                    return PipelineSummaryRow(
                        id: status,
                        status: status,
                        jobCount: row["job_count"] ?? 0,
                        totalEstimatedHours: row["total_estimated_hours"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 13. Shift Templates
    // =========================================================================

    /// A shift template row with hat name for display.
    public struct ShiftTemplateRow: Sendable, Identifiable {
        public let id: Int64
        public var name: String
        public var hatId: Int64?
        public var hatName: String?
        public var workDays: String
        public var startTime: String
        public var endTime: String
        public var breakMinutes: Int
        public var breakPaid: Bool
        public var overtimeRule: String

        public init(
            id: Int64, name: String, hatId: Int64?, hatName: String?,
            workDays: String, startTime: String, endTime: String,
            breakMinutes: Int, breakPaid: Bool, overtimeRule: String
        ) {
            self.id = id; self.name = name; self.hatId = hatId; self.hatName = hatName
            self.workDays = workDays; self.startTime = startTime; self.endTime = endTime
            self.breakMinutes = breakMinutes; self.breakPaid = breakPaid; self.overtimeRule = overtimeRule
        }
    }

    /// List all active shift templates.
    public func getShiftTemplates() throws -> [ShiftTemplateRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT st.*, h.name AS hat_name
                    FROM shift_templates st
                    LEFT JOIN hats h ON h.id = st.hat_id
                    WHERE st.deleted_at IS NULL
                    ORDER BY st.name
                    """)
                return rows.map { row in
                    ShiftTemplateRow(
                        id: row["id"],
                        name: row["name"],
                        hatId: row["hat_id"],
                        hatName: row["hat_name"],
                        workDays: row["work_days"],
                        startTime: row["start_time"],
                        endTime: row["end_time"],
                        breakMinutes: row["break_minutes"] ?? 30,
                        breakPaid: (row["break_paid"] as Int?) == 1,
                        overtimeRule: row["overtime_rule"] ?? "company_default"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Save (insert or update) a shift template.
    @discardableResult
    public func saveShiftTemplate(
        id: Int64? = nil, name: String, hatId: Int64?,
        workDays: String, startTime: String, endTime: String,
        breakMinutes: Int = 30, breakPaid: Bool = false,
        overtimeRule: String = "company_default"
    ) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        guard !workDays.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        guard !startTime.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        guard !endTime.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        return try db.writer.write { dbConn in
            if let existingId = id {
                try dbConn.execute(sql: """
                    UPDATE shift_templates
                    SET name = ?, hat_id = ?, work_days = ?, start_time = ?, end_time = ?,
                        break_minutes = ?, break_paid = ?, overtime_rule = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [name, hatId, workDays, startTime, endTime,
                                     breakMinutes, breakPaid ? 1 : 0, overtimeRule, existingId])
                return existingId
            } else {
                var template = ShiftTemplate(
                    name: name, hatId: hatId, workDays: workDays,
                    startTime: startTime, endTime: endTime,
                    breakMinutes: breakMinutes, breakPaid: breakPaid ? 1 : 0,
                    overtimeRule: overtimeRule
                )
                try template.insert(dbConn)
                guard let newId = template.id else {
                    throw SchedulingError.insertFailed("Failed to retrieve ID after shift template insert")
                }
                return newId
            }
        }
    }

    /// Soft-delete a shift template.
    public func deleteShiftTemplate(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE shift_templates SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - 14. Company Holidays
    // =========================================================================

    /// A holiday row for list views.
    public struct HolidayRow: Sendable, Identifiable {
        public let id: Int64
        public var name: String
        public var date: String
        public var isPaid: Bool
        public var isRecurring: Bool

        public init(id: Int64, name: String, date: String, isPaid: Bool, isRecurring: Bool) {
            self.id = id; self.name = name; self.date = date
            self.isPaid = isPaid; self.isRecurring = isRecurring
        }
    }

    /// List all active holidays.
    public func getHolidays() throws -> [HolidayRow] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM company_holidays WHERE deleted_at IS NULL ORDER BY date
                    """)
                return rows.map { row in
                    HolidayRow(
                        id: row["id"],
                        name: row["name"],
                        date: row["date"],
                        isPaid: (row["is_paid"] as Int?) == 1,
                        isRecurring: (row["is_recurring"] as Int?) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Save (insert or update) a holiday.
    @discardableResult
    public func saveHoliday(
        id: Int64? = nil, name: String, date: String,
        isPaid: Bool = true, isRecurring: Bool = false
    ) throws -> Int64 {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        guard !date.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SchedulingError.requiredFieldEmpty
        }
        return try db.writer.write { dbConn in
            if let existingId = id {
                try dbConn.execute(sql: """
                    UPDATE company_holidays
                    SET name = ?, date = ?, is_paid = ?, is_recurring = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [name, date, isPaid ? 1 : 0, isRecurring ? 1 : 0, existingId])
                return existingId
            } else {
                var holiday = CompanyHoliday(
                    name: name, date: date,
                    isPaid: isPaid ? 1 : 0,
                    isRecurring: isRecurring ? 1 : 0
                )
                try holiday.insert(dbConn)
                guard let newId = holiday.id else {
                    throw SchedulingError.insertFailed("Failed to retrieve ID after holiday insert")
                }
                return newId
            }
        }
    }

    /// Soft-delete a holiday.
    public func deleteHoliday(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: "UPDATE company_holidays SET deleted_at = datetime('now') WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // =========================================================================
    // MARK: - Flex Pool
    // =========================================================================

    /// Returns all flex-pool jobs visible to the given user.
    ///
    /// A job is visible to a user if:
    /// - `is_flex_pool = 1` and status is not completed/cancelled/on_hold
    /// - `flex_pool_user_filter` is NULL **or** contains `userId`
    /// - `flex_pool_team_filter` is NULL **or** the user belongs to one of the listed teams
    ///
    /// Returns an empty array if the `jobs` table is missing (fresh install).
    public func fetchFlexPool(userId: Int64) throws -> [FlexPoolJob] {
        // Read approval setting first (separate from the jobs query to avoid fragile JOINs).
        let isApprovalRequired: Bool
        do {
            let val = try db.writer.read { dbConn in
                try String.fetchOne(dbConn,
                    sql: "SELECT value FROM settings WHERE key = 'flex_pool_requires_approval' LIMIT 1")
            }
            isApprovalRequired = (val == "1")
        } catch {
            if isTableNotFoundError(error) { isApprovalRequired = false }
            else { throw error }
        }

        // Fetch flex-pool jobs visible to this user.
        do {
            return try db.writer.read { dbConn in
                // Fix #167: Load this user's team IDs once so we can enforce
                // flex_pool_team_filter on each row. Missing table = no teams.
                let userTeamIds: Set<Int64>
                do {
                    let ids = try Int64.fetchAll(dbConn, sql: """
                        SELECT team_id FROM employee_team_members
                        WHERE user_id = ? AND deleted_at IS NULL
                        """, arguments: [userId])
                    userTeamIds = Set(ids)
                } catch {
                    if isTableNotFoundError(error) { userTeamIds = [] }
                    else { throw error }
                }

                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT id, job_name, job_number, address_line1,
                           notes, estimated_hours,
                           flex_pool_user_filter, flex_pool_team_filter
                    FROM jobs
                    WHERE is_flex_pool = 1
                      AND deleted_at IS NULL
                      AND status NOT IN ('completed', 'cancelled', 'on_hold')
                    ORDER BY created_at DESC
                    """)

                return rows.compactMap { row -> FlexPoolJob? in
                    let id: Int64 = row["id"]
                    let userFilter: String? = row["flex_pool_user_filter"]
                    let teamFilter: String? = row["flex_pool_team_filter"]

                    // User-level filter: if set, userId must appear in the JSON array.
                    if let uf = userFilter,
                       let data = uf.data(using: .utf8),
                       let ids = try? JSONDecoder().decode([Int64].self, from: data),
                       !ids.contains(userId) {
                        return nil
                    }

                    // Fix #167: Team-level filter. If the job restricts to specific teams,
                    // the user must belong to at least one of them.
                    if let tf = teamFilter, !tf.isEmpty,
                       let data = tf.data(using: .utf8),
                       let allowedTeams = try? JSONDecoder().decode([Int64].self, from: data),
                       !allowedTeams.isEmpty {
                        if userTeamIds.isDisjoint(with: Set(allowedTeams)) {
                            return nil
                        }
                    }

                    return FlexPoolJob(
                        id: id,
                        jobName: row["job_name"] ?? "",
                        jobNumber: row["job_number"] ?? "",
                        address: row["address_line1"],
                        description: row["notes"],
                        estimatedHours: row["estimated_hours"],
                        isApprovalRequired: isApprovalRequired
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Claims a flex-pool job for a user.
    ///
    /// If `flex_pool_requires_approval` is enabled in settings, creates a
    /// `dispatch_entries` row with status `pending_approval`. Otherwise,
    /// sets the user as lead and creates an `active` dispatch entry in a
    /// single transaction.
    public func claimFlexJob(jobId: Int64, userId: Int64) throws {
        let requiresApproval: Bool
        do {
            let val = try db.writer.read { dbConn in
                try String.fetchOne(dbConn,
                    sql: "SELECT value FROM settings WHERE key = 'flex_pool_requires_approval' LIMIT 1")
            }
            requiresApproval = (val == "1")
        } catch {
            if isTableNotFoundError(error) { requiresApproval = false }
            else { throw error }
        }

        try db.writer.write { dbConn in
            // Guard: job + user must exist and not be tombstoned — flex-pool
            // pickup from a stale UI should not create orphan dispatches against
            // deleted jobs or promote a tombstoned user to lead.
            let jobExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL
                """, arguments: [jobId]) ?? 0) > 0
            guard jobExists else { throw SchedulingError.jobNotFound(jobId) }
            let userExists = (try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM users WHERE id = ? AND deleted_at IS NULL AND is_active = 1
                """, arguments: [userId]) ?? 0) > 0
            guard userExists else { throw SchedulingError.userNotFound(userId) }

            let dispatchStatus = requiresApproval ? "pending_approval" : "scheduled"

            if !requiresApproval {
                // Set worker as lead and remove from pool immediately.
                try dbConn.execute(
                    sql: "UPDATE jobs SET is_flex_pool = 0, lead_user_id = ? WHERE id = ? AND deleted_at IS NULL",
                    arguments: [userId, jobId]
                )
            }

            // Create a dispatch entry in job_dispatch so the assignment shows on the dispatch board.
            try dbConn.execute(
                sql: """
                    INSERT INTO job_dispatch
                    (job_id, user_id, dispatch_date, status, created_at, updated_at)
                    VALUES (?, ?, date('now'), ?, datetime('now'), datetime('now'))
                    """,
                arguments: [jobId, userId, dispatchStatus]
            )
        }
    }

    /// List flex-pool dispatch assignments awaiting manager approval.
    public func listPendingScheduleChangeApprovals() throws -> [ScheduleChangeApproval] {
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT jd.id, jd.job_id, jd.user_id, jd.dispatch_date,
                           COALESCE(jd.time_slot, 'full') AS time_slot,
                           COALESCE(jd.created_at, '') AS created_at,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name
                    FROM job_dispatch jd
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jd.user_id AND u.deleted_at IS NULL
                    WHERE jd.status = 'pending_approval'
                      AND jd.deleted_at IS NULL
                    ORDER BY jd.created_at ASC, jd.id ASC
                    """)
                return rows.map { row in
                    ScheduleChangeApproval(
                        id: row["id"] ?? 0,
                        jobId: row["job_id"] ?? 0,
                        userId: row["user_id"] ?? 0,
                        jobName: row["job_name"] ?? "Unknown Job",
                        userName: row["user_name"] ?? "Unknown",
                        dispatchDate: row["dispatch_date"] ?? "",
                        timeSlot: row["time_slot"] ?? "full",
                        createdAt: row["created_at"] ?? ""
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Approve a pending flex-pool dispatch and assign the worker to the job.
    public func approveScheduleChange(dispatchId: Int64, approvedBy: Int64?) throws {
        try db.writer.write { dbConn in
            guard let row = try Row.fetchOne(dbConn, sql: """
                SELECT id, job_id, user_id
                FROM job_dispatch
                WHERE id = ? AND status = 'pending_approval' AND deleted_at IS NULL
                """, arguments: [dispatchId]) else {
                throw SchedulingError.timeOffRequestNotFound(dispatchId)
            }

            let jobId: Int64 = row["job_id"] ?? 0
            let userId: Int64 = row["user_id"] ?? 0

            try dbConn.execute(sql: """
                UPDATE jobs
                SET is_flex_pool = 0,
                    lead_user_id = ?,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [userId, jobId])

            try dbConn.execute(sql: """
                UPDATE job_dispatch
                SET status = 'scheduled',
                    dispatched_by = ?,
                    updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [approvedBy, dispatchId])
        }
    }

    /// Reject a pending flex-pool dispatch approval without assigning the worker.
    public func rejectScheduleChange(dispatchId: Int64, rejectedBy: Int64?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE job_dispatch
                SET status = 'rejected',
                    dispatched_by = ?,
                    updated_at = datetime('now')
                WHERE id = ? AND status = 'pending_approval' AND deleted_at IS NULL
                """, arguments: [rejectedBy, dispatchId])
            if dbConn.changesCount == 0 {
                throw SchedulingError.timeOffRequestNotFound(dispatchId)
            }
        }
    }

    /// Marks a job as flex-pool available (or removes it from the pool).
    ///
    /// - Parameters:
    ///   - jobId: The job to update.
    ///   - isFlexPool: True to add to pool, false to remove.
    ///   - teamFilter: Optional JSON-encoded array of team IDs. NULL = all teams.
    ///   - userFilter: Optional JSON-encoded array of user IDs. NULL = all users.
    public func markJobFlexPool(
        jobId: Int64,
        isFlexPool: Bool,
        teamFilter: [Int64]? = nil,
        userFilter: [Int64]? = nil
    ) throws {
        let teamJSON: String? = teamFilter.flatMap {
            guard let data = try? JSONEncoder().encode($0) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let userJSON: String? = userFilter.flatMap {
            guard let data = try? JSONEncoder().encode($0) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        try db.writer.write { dbConn in
            try dbConn.execute(
                sql: """
                    UPDATE jobs
                    SET is_flex_pool = ?,
                        flex_pool_team_filter = ?,
                        flex_pool_user_filter = ?,
                        updated_at = datetime('now')
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [isFlexPool ? 1 : 0, teamJSON, userJSON, jobId]
            )
        }
    }

    /// Returns whether a job is currently in the flex pool.
    public func isJobInFlexPool(jobId: Int64) throws -> Bool {
        do {
            return try db.writer.read { dbConn in
                let val = try Int.fetchOne(dbConn,
                    sql: "SELECT is_flex_pool FROM jobs WHERE id = ? AND deleted_at IS NULL",
                    arguments: [jobId])
                return val == 1
            }
        } catch {
            if isTableNotFoundError(error) { return false }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Normalize a user-entered schedule date without timezone conversion.
    /// Accepts only a trimmed yyyy-MM-dd calendar date string.
    private static func normalizeScheduleDateOnly(_ rawDate: String) throws -> String {
        let value = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SchedulingError.requiredFieldEmpty }

        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              String(format: "%04d-%02d-%02d", year, month, day) == value,
              (1...12).contains(month) else {
            throw SchedulingError.invalidDate(value)
        }

        let daysInMonth: Int
        switch month {
        case 1, 3, 5, 7, 8, 10, 12:
            daysInMonth = 31
        case 4, 6, 9, 11:
            daysInMonth = 30
        case 2:
            let isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
            daysInMonth = isLeapYear ? 29 : 28
        default:
            throw SchedulingError.invalidDate(value)
        }

        guard (1...daysInMonth).contains(day) else {
            throw SchedulingError.invalidDate(value)
        }

        return value
    }

    private static func normalizeOptionalSubcontractorScheduleText(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func validateSubcontractorScheduleTimeRange(arrivalTime: String?, departureTime: String?) throws {
        guard let arrivalTime, let departureTime else { return }
        let arrivalComparable = minutesSinceMidnight(arrivalTime) ?? -1
        let departureComparable = minutesSinceMidnight(departureTime) ?? -1
        let isOrdered: Bool
        if arrivalComparable >= 0 && departureComparable >= 0 {
            isOrdered = departureComparable > arrivalComparable
        } else {
            // Preserve compatibility for legacy/custom time labels while still enforcing
            // the edit-flow rule when both values are comparable strings.
            isOrdered = departureTime > arrivalTime
        }
        guard isOrdered else {
            throw SchedulingError.invalidDateRange(start: arrivalTime, end: departureTime)
        }
    }

    private static func minutesSinceMidnight(_ time: String) -> Int? {
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    private static func normalizeSubcontractorScheduleStatus(_ rawStatus: String) throws -> String {
        let value = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let validStatuses: Set<String> = ["scheduled", "confirmed", "in_progress", "completed", "cancelled"]
        guard validStatuses.contains(value) else {
            throw SchedulingError.invalidStatus(rawStatus)
        }
        return value
    }

    private func validateSubcontractorScheduleParents(_ dbConn: Database, jobId: Int64, gcId: Int64) throws {
        let jobExists = (try Int.fetchOne(
            dbConn,
            sql: "SELECT COUNT(*) FROM jobs WHERE id = ? AND deleted_at IS NULL",
            arguments: [jobId]
        ) ?? 0) > 0
        guard jobExists else { throw SchedulingError.jobNotFound(jobId) }

        let contractorExists = (try Int.fetchOne(
            dbConn,
            sql: "SELECT COUNT(*) FROM general_contractors WHERE id = ? AND deleted_at IS NULL",
            arguments: [gcId]
        ) ?? 0) > 0
        guard contractorExists else { throw SchedulingError.contractorNotFound(gcId) }
    }

    private func guardNoActiveSubcontractorScheduleConflict(_ dbConn: Database, jobId: Int64, gcId: Int64, date: String) throws {
        let conflictCount = try Int.fetchOne(
            dbConn,
            sql: """
                SELECT COUNT(*)
                FROM subcontractor_schedules
                WHERE job_id = ?
                  AND gc_id = ?
                  AND scheduled_date = ?
                  AND deleted_at IS NULL
                """,
            arguments: [jobId, gcId, date]
        ) ?? 0
        guard conflictCount == 0 else {
            throw SchedulingError.subcontractorScheduleConflict(jobId: jobId, gcId: gcId, date: date)
        }
    }

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
        return message.contains("no such table") || message.contains("no such column")
    }
}
