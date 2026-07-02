import Foundation
import GRDB

/// Reports Service — cross-domain reporting queries for timesheets, daily reports,
/// spending, profitability, and reporting stats.
///
/// All queries run against the local SQLite database via GRDB.
/// Uses existing tables (labor_entries, purchase_orders, jobs, etc.) to generate
/// reporting data — no dedicated report tables are created.
///
/// Tables that may not yet exist are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: Reports & Pre-Billing feature area (Phase 8/11)
public final class ReportsService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Result Types
    // =========================================================================

    /// A timesheet summary row aggregated per user within a date range.
    public struct TimesheetRow: Sendable, Identifiable {
        public let id: Int64
        public let userId: Int64
        public let userName: String
        public let regularHours: Double
        public let overtimeHours: Double
        public let totalHours: Double
        public let daysWorked: Int

        public init(
            id: Int64, userId: Int64, userName: String, regularHours: Double,
            overtimeHours: Double, totalHours: Double, daysWorked: Int
        ) {
            self.id = id
            self.userId = userId
            self.userName = userName
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
            self.totalHours = totalHours
            self.daysWorked = daysWorked
        }
    }

    /// A payroll-review segment row for one labor entry with related break totals.
    public struct TimesheetSegmentRow: Sendable, Identifiable {
        public let id: Int64
        public let userId: Int64
        public let userName: String
        public let jobId: Int64
        public let jobName: String
        public let jobNumber: String
        public let clockIn: String
        public let clockOut: String?
        public let paidBreakMinutes: Int
        public let paidLunchMinutes: Int
        public let unpaidLunchMinutes: Int
        public let regularHours: Double
        public let overtimeHours: Double
        public let sourceDevice: String?
        public let syncStatus: String
        public let status: String

        public init(
            id: Int64, userId: Int64, userName: String, jobId: Int64, jobName: String,
            jobNumber: String, clockIn: String, clockOut: String?, paidBreakMinutes: Int,
            paidLunchMinutes: Int, unpaidLunchMinutes: Int, regularHours: Double,
            overtimeHours: Double, sourceDevice: String?, syncStatus: String, status: String
        ) {
            self.id = id
            self.userId = userId
            self.userName = userName
            self.jobId = jobId
            self.jobName = jobName
            self.jobNumber = jobNumber
            self.clockIn = clockIn
            self.clockOut = clockOut
            self.paidBreakMinutes = paidBreakMinutes
            self.paidLunchMinutes = paidLunchMinutes
            self.unpaidLunchMinutes = unpaidLunchMinutes
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
            self.sourceDevice = sourceDevice
            self.syncStatus = syncStatus
            self.status = status
        }
    }

    public struct TimesheetCorrectionRequest: Sendable {
        public let laborEntryId: Int64
        public let adjustedClockIn: String
        public let adjustedClockOut: String
        public let clientPreviewRegularHours: Double
        public let clientPreviewOvertimeHours: Double
        public let reason: String
        public let actorUserId: Int64

        public init(
            laborEntryId: Int64,
            adjustedClockIn: String,
            adjustedClockOut: String,
            clientPreviewRegularHours: Double,
            clientPreviewOvertimeHours: Double,
            reason: String,
            actorUserId: Int64
        ) {
            self.laborEntryId = laborEntryId
            self.adjustedClockIn = adjustedClockIn
            self.adjustedClockOut = adjustedClockOut
            self.clientPreviewRegularHours = clientPreviewRegularHours
            self.clientPreviewOvertimeHours = clientPreviewOvertimeHours
            self.reason = reason
            self.actorUserId = actorUserId
        }
    }

    public struct TimesheetCorrectionAuditRecord: Sendable, Identifiable {
        public let id: Int64
        public let segmentId: Int64
        public let jobId: Int64
        public let jobName: String
        public let jobNumber: String
        public let employeeUserId: Int64
        public let employeeName: String
        public let originalClockIn: String
        public let originalClockOut: String?
        public let adjustedClockIn: String
        public let adjustedClockOut: String
        public let originalRegularHours: Double
        public let originalOvertimeHours: Double
        public let adjustedRegularHours: Double
        public let adjustedOvertimeHours: Double
        public let reason: String
        public let actorUserId: Int64
        public let actorName: String
        public let changedAt: String
        public let approvalStatus: String
        public let approverName: String?

        public init(
            id: Int64,
            segmentId: Int64,
            jobId: Int64,
            jobName: String,
            jobNumber: String,
            employeeUserId: Int64,
            employeeName: String,
            originalClockIn: String,
            originalClockOut: String?,
            adjustedClockIn: String,
            adjustedClockOut: String,
            originalRegularHours: Double,
            originalOvertimeHours: Double,
            adjustedRegularHours: Double,
            adjustedOvertimeHours: Double,
            reason: String,
            actorUserId: Int64,
            actorName: String,
            changedAt: String,
            approvalStatus: String,
            approverName: String?
        ) {
            self.id = id
            self.segmentId = segmentId
            self.jobId = jobId
            self.jobName = jobName
            self.jobNumber = jobNumber
            self.employeeUserId = employeeUserId
            self.employeeName = employeeName
            self.originalClockIn = originalClockIn
            self.originalClockOut = originalClockOut
            self.adjustedClockIn = adjustedClockIn
            self.adjustedClockOut = adjustedClockOut
            self.originalRegularHours = originalRegularHours
            self.originalOvertimeHours = originalOvertimeHours
            self.adjustedRegularHours = adjustedRegularHours
            self.adjustedOvertimeHours = adjustedOvertimeHours
            self.reason = reason
            self.actorUserId = actorUserId
            self.actorName = actorName
            self.changedAt = changedAt
            self.approvalStatus = approvalStatus
            self.approverName = approverName
        }
    }

    /// A daily report summary row showing per-job activity for a given date.
    public struct DailyReportSummaryRow: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let workerCount: Int
        public let totalHours: Double
        public let status: String

        public init(id: Int64, jobName: String, workerCount: Int, totalHours: Double, status: String) {
            self.id = id
            self.jobName = jobName
            self.workerCount = workerCount
            self.totalHours = totalHours
            self.status = status
        }
    }

    /// Spending summary over a given time period.
    public struct SpendingSummary: Sendable {
        public let totalSpend: Double
        public let poCount: Int
        public let avgPOAmount: Double
        public let topSupplierName: String?
        public let topSupplierAmount: Double

        public init(
            totalSpend: Double, poCount: Int, avgPOAmount: Double,
            topSupplierName: String?, topSupplierAmount: Double
        ) {
            self.totalSpend = totalSpend
            self.poCount = poCount
            self.avgPOAmount = avgPOAmount
            self.topSupplierName = topSupplierName
            self.topSupplierAmount = topSupplierAmount
        }
    }

    /// A job profitability row with revenue, costs, and margin.
    public struct JobProfitRow: Sendable, Identifiable {
        public let id: Int64
        public let jobName: String
        public let revenue: Double
        public let laborCost: Double
        public let materialCost: Double
        public let profit: Double
        public let margin: Double

        public init(
            id: Int64, jobName: String, revenue: Double,
            laborCost: Double, materialCost: Double, profit: Double, margin: Double
        ) {
            self.id = id
            self.jobName = jobName
            self.revenue = revenue
            self.laborCost = laborCost
            self.materialCost = materialCost
            self.profit = profit
            self.margin = margin
        }
    }

    /// High-level reporting stats for the reports dashboard.
    public struct ReportsStats: Sendable {
        public let openPeriods: Int
        public let pendingTimesheets: Int
        public let totalLaborHoursThisMonth: Double

        public init(openPeriods: Int, pendingTimesheets: Int, totalLaborHoursThisMonth: Double) {
            self.openPeriods = openPeriods
            self.pendingTimesheets = pendingTimesheets
            self.totalLaborHoursThisMonth = totalLaborHoursThisMonth
        }
    }

    // =========================================================================
    // MARK: - 1. Timesheet Data
    // =========================================================================

    /// Get timesheet data aggregated per user within a date range.
    ///
    /// Groups labor entries by user, summing regular/overtime hours and counting
    /// distinct work days. The `id` field is a sequential index (row number).
    ///
    /// - Parameters:
    ///   - startDate: Start date in ISO-8601 format (e.g., "2026-03-01").
    ///   - endDate: End date in ISO-8601 format (e.g., "2026-03-15").
    /// - Returns: An array of `TimesheetRow` sorted by user name ascending.
    public func getTimesheetData(startDate: String, endDate: String) throws -> [TimesheetRow] {
        do {
            return try db.writer.read { dbConn -> [TimesheetRow] in
                let sql = """
                    SELECT le.user_id,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours,
                           COALESCE(SUM(le.regular_hours), 0) + COALESCE(SUM(le.overtime_hours), 0) AS total_hours,
                           COUNT(DISTINCT \(Self.localDateSQL("le.clock_in"))) AS days_worked
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    WHERE le.deleted_at IS NULL
                      AND \(Self.localDateSQL("le.clock_in")) >= date(?)
                      AND \(Self.localDateSQL("le.clock_in")) <= date(?)
                    GROUP BY le.user_id
                    ORDER BY user_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.enumerated().map { index, row in
                    let userId: Int64 = row["user_id"] ?? 0
                    return TimesheetRow(
                        id: userId == 0 ? Int64(index + 1) : userId,
                        userId: userId,
                        userName: row["user_name"] ?? "Unknown",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        totalHours: row["total_hours"] ?? 0.0,
                        daysWorked: row["days_worked"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get job-level timesheet segments for manager/tech review within a date range.
    public func getTimesheetSegments(
        startDate: String,
        endDate: String,
        userId: Int64? = nil
    ) throws -> [TimesheetSegmentRow] {
        do {
            return try db.writer.read { dbConn -> [TimesheetSegmentRow] in
                var args: [DatabaseValueConvertible?] = [startDate, endDate]
                var userClause = ""
                if let userId {
                    userClause = " AND le.user_id = ?"
                    args.append(userId)
                }

                let sql = """
                    SELECT le.id, le.user_id,
                           COALESCE(u.display_name, u.email, 'Unknown') AS user_name,
                           le.job_id,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           COALESCE(j.job_number, '') AS job_number,
                           le.clock_in, le.clock_out,
                           COALESCE(le.regular_hours, 0) AS regular_hours,
                           COALESCE(le.overtime_hours, 0) AS overtime_hours,
                           COALESCE(le.status, CASE WHEN le.clock_out IS NULL THEN 'open' ELSE 'completed' END) AS status,
                           COALESCE(SUM(CASE
                               WHEN br.break_type = 'break'
                                    AND COALESCE(br.is_paid, 1) = 1
                               THEN COALESCE(br.duration_minutes, 0)
                               ELSE 0
                           END), 0) AS paid_break_minutes,
                           COALESCE(SUM(CASE
                               WHEN br.break_type IN ('lunch_paid', 'lunch_unpaid')
                                    AND COALESCE(br.is_paid, CASE WHEN br.break_type = 'lunch_unpaid' THEN 0 ELSE 1 END) = 1
                               THEN COALESCE(br.duration_minutes, 0)
                               ELSE 0
                           END), 0) AS paid_lunch_minutes,
                           COALESCE(SUM(CASE
                               WHEN COALESCE(br.is_paid, CASE WHEN br.break_type = 'lunch_unpaid' THEN 0 ELSE 1 END) = 0
                               THEN COALESCE(br.duration_minutes, 0)
                               ELSE 0
                           END), 0) AS unpaid_lunch_minutes
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    LEFT JOIN break_records br
                      ON br.labor_entry_id = le.id
                     AND br.deleted_at IS NULL
                     AND br.break_type IN ('break', 'lunch_paid', 'lunch_unpaid')
                    WHERE le.deleted_at IS NULL
                      AND \(Self.localDateSQL("le.clock_in")) >= date(?)
                      AND \(Self.localDateSQL("le.clock_in")) <= date(?)
                      \(userClause)
                    GROUP BY le.id, le.user_id, user_name, le.job_id, job_name, job_number,
                             le.clock_in, le.clock_out, le.regular_hours, le.overtime_hours,
                             COALESCE(le.status, CASE WHEN le.clock_out IS NULL THEN 'open' ELSE 'completed' END)
                    ORDER BY user_name ASC, \(Self.localDateSQL("le.clock_in")) DESC, le.clock_in DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map { row in
                    let clockOut: String? = row["clock_out"] as String?
                    return TimesheetSegmentRow(
                        id: row["id"] ?? 0,
                        userId: row["user_id"] ?? 0,
                        userName: row["user_name"] ?? "Unknown",
                        jobId: row["job_id"] ?? 0,
                        jobName: row["job_name"] ?? "Unknown Job",
                        jobNumber: row["job_number"] ?? "",
                        clockIn: row["clock_in"] ?? "",
                        clockOut: clockOut,
                        paidBreakMinutes: row["paid_break_minutes"] ?? 0,
                        paidLunchMinutes: row["paid_lunch_minutes"] ?? 0,
                        unpaidLunchMinutes: row["unpaid_lunch_minutes"] ?? 0,
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        sourceDevice: nil,
                        syncStatus: "Local",
                        status: row["status"] ?? (clockOut == nil ? "clocked_in" : "completed")
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    @discardableResult
    public func saveTimesheetCorrection(_ request: TimesheetCorrectionRequest) throws -> TimesheetCorrectionAuditRecord {
        let trimmedReason = request.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw ReportsError.invalidTimesheetCorrectionReason }

        guard let adjustedIn = CoreFormatters.parseDateTime(request.adjustedClockIn),
              let adjustedOut = CoreFormatters.parseDateTime(request.adjustedClockOut),
              adjustedOut >= adjustedIn else {
            throw ReportsError.invalidTimesheetCorrectionRange
        }
        let adjustedClockIn = Self.sqliteUTCTimestamp(adjustedIn)
        let adjustedClockOut = Self.sqliteUTCTimestamp(adjustedOut)

        do {
            return try db.writer.write { dbConn -> TimesheetCorrectionAuditRecord in
                guard let original = try Row.fetchOne(dbConn, sql: """
                    SELECT le.id, le.user_id, le.job_id, le.clock_in, le.clock_out,
                           COALESCE(le.regular_hours, 0) AS regular_hours,
                           COALESCE(le.overtime_hours, 0) AS overtime_hours
                    FROM labor_entries le
                    WHERE le.id = ? AND le.deleted_at IS NULL
                    """, arguments: [request.laborEntryId]) else {
                    throw ReportsError.timesheetSegmentNotFound(request.laborEntryId)
                }

                let employeeUserId: Int64 = original["user_id"] ?? 0
                let jobId: Int64 = original["job_id"] ?? 0
                let originalClockIn: String = original["clock_in"] ?? ""
                let originalClockOut: String? = original["clock_out"] as String?
                let originalRegular: Double = original["regular_hours"] ?? 0
                let originalOvertime: Double = original["overtime_hours"] ?? 0
                let changedAt = CoreFormatters.nowISO()

                guard CoreFormatters.parseDateTime(originalClockIn) != nil else {
                    throw ReportsError.invalidTimesheetOriginalTimestamp("clock-in")
                }
                if let originalClockOut, CoreFormatters.parseDateTime(originalClockOut) == nil {
                    throw ReportsError.invalidTimesheetOriginalTimestamp("clock-out")
                }

                let adjustedTotalHours = try Self.correctedBillableHours(
                    dbConn: dbConn,
                    laborEntryId: request.laborEntryId,
                    adjustedIn: adjustedIn,
                    adjustedOut: adjustedOut
                )
                let allocation = try Self.allocateCorrectedOvertimeHours(
                    dbConn: dbConn,
                    userId: employeeUserId,
                    laborEntryId: request.laborEntryId,
                    clockInTimestamp: adjustedClockIn,
                    totalHours: adjustedTotalHours
                )

                try dbConn.execute(sql: """
                    UPDATE labor_entries
                    SET clock_in = ?,
                        clock_out = ?,
                        regular_hours = ROUND(?, 2),
                        overtime_hours = ROUND(?, 2),
                        edited_by = ?,
                        status = 'completed'
                    WHERE id = ? AND deleted_at IS NULL
                    """, arguments: [
                    adjustedClockIn,
                    adjustedClockOut,
                    allocation.regular,
                    allocation.overtime,
                    request.actorUserId,
                    request.laborEntryId
                ])

                try dbConn.execute(sql: """
                    INSERT INTO timesheet_correction_audits
                        (labor_entry_id, employee_user_id, job_id, original_clock_in, original_clock_out,
                         adjusted_clock_in, adjusted_clock_out, original_regular_hours, original_overtime_hours,
                         adjusted_regular_hours, adjusted_overtime_hours, reason, actor_user_id,
                         approval_status, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending_review', ?)
                    """, arguments: [
                    request.laborEntryId, employeeUserId, jobId, originalClockIn, originalClockOut,
                    adjustedClockIn, adjustedClockOut, originalRegular, originalOvertime,
                    allocation.regular, allocation.overtime, trimmedReason,
                    request.actorUserId, changedAt
                ])

                guard let record = try Self.fetchTimesheetCorrectionAuditRecord(
                    dbConn: dbConn,
                    correctionId: dbConn.lastInsertedRowID
                ) else {
                    throw ReportsError.timesheetCorrectionAuditUnavailable
                }
                return record
            }
        } catch {
            if isTableNotFoundError(error) { throw ReportsError.timesheetCorrectionAuditUnavailable }
            throw error
        }
    }

    public func getTimesheetCorrectionHistory(
        laborEntryId: Int64? = nil,
        startDate: String? = nil,
        endDate: String? = nil
    ) throws -> [TimesheetCorrectionAuditRecord] {
        do {
            return try db.writer.read { dbConn -> [TimesheetCorrectionAuditRecord] in
                var clauses = ["tca.deleted_at IS NULL"]
                var args: [DatabaseValueConvertible?] = []
                if let laborEntryId {
                    clauses.append("tca.labor_entry_id = ?")
                    args.append(laborEntryId)
                }
                // A correction must stay reviewable in any period that contains EITHER
                // its original work date OR its adjusted work date. Filtering by
                // original_clock_in alone hides the audit trail when a manager moves an
                // entry across a date/pay-period boundary: the corrected segment shows
                // up in the destination period (getTimesheetSegments filters by the
                // adjusted labor_entries.clock_in) but its history vanished (#1097).
                if startDate != nil || endDate != nil {
                    var perColumnRanges: [String] = []
                    for column in ["tca.original_clock_in", "tca.adjusted_clock_in"] {
                        var bounds: [String] = []
                        if let startDate {
                            bounds.append("\(Self.localDateSQL(column)) >= date(?)")
                            args.append(startDate)
                        }
                        if let endDate {
                            bounds.append("\(Self.localDateSQL(column)) <= date(?)")
                            args.append(endDate)
                        }
                        perColumnRanges.append("(" + bounds.joined(separator: " AND ") + ")")
                    }
                    clauses.append("(" + perColumnRanges.joined(separator: " OR ") + ")")
                }

                let sql = Self.timesheetCorrectionAuditSQL(whereClause: clauses.joined(separator: " AND "))
                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
                return rows.map(Self.mapTimesheetCorrectionAuditRecord)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 2. Daily Report Summary
    // =========================================================================

    /// Get a per-job activity summary for a specific date.
    ///
    /// For each job that had labor entries on the given date, returns the
    /// number of workers, total hours, and the job's current status.
    ///
    /// - Parameter date: The date in ISO-8601 format (e.g., "2026-03-15").
    /// - Returns: An array of `DailyReportSummaryRow` sorted by job name ascending.
    public func getDailyReportSummary(date: String) throws -> [DailyReportSummaryRow] {
        do {
            return try db.writer.read { dbConn -> [DailyReportSummaryRow] in
                let sql = """
                    SELECT j.id, j.job_name, j.status,
                           COUNT(DISTINCT le.user_id) AS worker_count,
                           COALESCE(SUM(le.regular_hours + le.overtime_hours), 0) AS total_hours
                    FROM labor_entries le
                    JOIN jobs j ON j.id = le.job_id
                    WHERE le.deleted_at IS NULL
                      AND j.deleted_at IS NULL
                      AND \(Self.localDateSQL("le.clock_in")) = date(?)
                    GROUP BY j.id
                    ORDER BY j.job_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [date])
                return rows.map { row in
                    DailyReportSummaryRow(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        workerCount: row["worker_count"] ?? 0,
                        totalHours: row["total_hours"] ?? 0.0,
                        status: row["status"] ?? "active"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 3. Spending Summary
    // =========================================================================

    /// Get a spending summary over the last N days.
    ///
    /// Aggregates purchase order totals, counts POs, calculates average PO amount,
    /// and identifies the top supplier by total spend.
    ///
    /// - Parameter days: The lookback window in days. Defaults to 30.
    /// - Returns: A `SpendingSummary` with aggregate spending data.
    public func getSpendingSummary(days: Int = 30) throws -> SpendingSummary {
        do {
            return try db.writer.read { dbConn -> SpendingSummary in
                // Aggregate PO spend in the date window
                let summarySQL = """
                    SELECT COALESCE(SUM(po.total_cost), 0) AS total_spend,
                           COUNT(*) AS po_count,
                           COALESCE(AVG(po.total_cost), 0) AS avg_po_amount
                    FROM purchase_orders po
                    WHERE po.deleted_at IS NULL
                      AND po.status NOT IN ('cancelled', 'draft')
                      AND date(po.created_at) >= date('now', '-' || ? || ' days')
                    """

                let summaryRow = try Row.fetchOne(dbConn, sql: summarySQL, arguments: [days])
                let totalSpend: Double = summaryRow?["total_spend"] ?? 0.0
                let poCount: Int = summaryRow?["po_count"] ?? 0
                let avgPOAmount: Double = summaryRow?["avg_po_amount"] ?? 0.0

                // Top supplier by total spend in the same window
                let topSupplierSQL = """
                    SELECT s.name AS supplier_name,
                           COALESCE(SUM(po.total_cost), 0) AS supplier_total
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    WHERE po.deleted_at IS NULL
                      AND po.status NOT IN ('cancelled', 'draft')
                      AND date(po.created_at) >= date('now', '-' || ? || ' days')
                    GROUP BY po.supplier_id
                    ORDER BY supplier_total DESC
                    LIMIT 1
                    """

                let topRow = try Row.fetchOne(dbConn, sql: topSupplierSQL, arguments: [days])
                let topSupplierName: String? = topRow?["supplier_name"] as String?
                let topSupplierAmount: Double = topRow?["supplier_total"] ?? 0.0

                return SpendingSummary(
                    totalSpend: totalSpend,
                    poCount: poCount,
                    avgPOAmount: avgPOAmount,
                    topSupplierName: topSupplierName,
                    topSupplierAmount: topSupplierAmount
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return SpendingSummary(
                    totalSpend: 0.0, poCount: 0, avgPOAmount: 0.0,
                    topSupplierName: nil, topSupplierAmount: 0.0
                )
            }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 4. Profitability Summary
    // =========================================================================

    /// Get profitability data per job.
    ///
    /// Calculates revenue (estimated hours * billing rate), labor cost
    /// (sum of regular + overtime hours * billing rate), material cost
    /// (from job_parts), profit, and margin percentage for each active job.
    ///
    /// - Returns: An array of `JobProfitRow` sorted by profit descending.
    public func getProfitabilitySummary() throws -> [JobProfitRow] {
        do {
            return try db.writer.read { dbConn -> [JobProfitRow] in
                // Fix #164: Labor cost must use employee pay_rate (what we pay them),
                // NOT billing_rate (what we charge the customer). Overtime at 1.5x.
                let sql = """
                    SELECT j.id, j.job_name,
                           COALESCE(j.estimated_hours, 0) * COALESCE(j.billing_rate, 0) AS revenue,
                           COALESCE((SELECT SUM(le.regular_hours * COALESCE(u.pay_rate, 0) +
                                                le.overtime_hours * COALESCE(u.pay_rate, 0) * 1.5)
                                     FROM labor_entries le
                                     LEFT JOIN users u ON u.id = le.user_id
                                     WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0) AS labor_cost,
                           COALESCE((SELECT SUM(jp.qty_consumed * COALESCE(jp.unit_cost_at_consume, 0))
                                     FROM job_parts jp
                                     WHERE jp.job_id = j.id AND jp.deleted_at IS NULL), 0) AS material_cost
                    FROM jobs j
                    WHERE j.deleted_at IS NULL
                    ORDER BY revenue DESC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql)
                return rows.map { row in
                    let id: Int64 = row["id"] ?? 0
                    let jobName: String = row["job_name"] ?? ""
                    let revenue: Double = row["revenue"] ?? 0.0
                    let laborCost: Double = row["labor_cost"] ?? 0.0
                    let materialCost: Double = row["material_cost"] ?? 0.0
                    let profit = revenue - laborCost - materialCost
                    let margin = revenue > 0 ? (profit / revenue) * 100.0 : 0.0

                    return JobProfitRow(
                        id: id,
                        jobName: jobName,
                        revenue: revenue,
                        laborCost: laborCost,
                        materialCost: materialCost,
                        profit: profit,
                        margin: margin
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 5. Pre-Billing Data
    // =========================================================================

    /// A pre-billing row showing per-job labor hours in a date range.
    public struct PreBillingRow: Sendable, Identifiable {
        public let id: Int64
        public let jobNumber: String
        public let jobName: String
        public let regularHours: Double
        public let overtimeHours: Double
        public let materialCost: Double
        public let billableAmount: Double
        public let laborEntryCount: Int
        public let materialLineCount: Int
        public let jpoCount: Int
        public let purchaseOrderCount: Int
        /// Compatibility field only. `audit_counts` is not job-scoped, so
        /// pre-billing does not expose per-job audit discrepancy attribution.
        public let auditDiscrepancyCount: Int
        public let sourceSummary: String

        public init(
            id: Int64,
            jobNumber: String = "",
            jobName: String,
            regularHours: Double,
            overtimeHours: Double,
            materialCost: Double = 0,
            billableAmount: Double = 0,
            laborEntryCount: Int = 0,
            materialLineCount: Int = 0,
            jpoCount: Int = 0,
            purchaseOrderCount: Int = 0,
            auditDiscrepancyCount: Int = 0,
            sourceSummary: String = ""
        ) {
            self.id = id
            self.jobNumber = jobNumber
            self.jobName = jobName
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
            self.materialCost = materialCost
            self.billableAmount = billableAmount
            self.laborEntryCount = laborEntryCount
            self.materialLineCount = materialLineCount
            self.jpoCount = jpoCount
            self.purchaseOrderCount = purchaseOrderCount
            self.auditDiscrepancyCount = auditDiscrepancyCount
            self.sourceSummary = sourceSummary
        }
    }

    /// Get pre-billing data: per-job labor hours for a date range.
    ///
    /// Only includes jobs that had labor entries (regular or overtime > 0)
    /// during the specified period.
    ///
    /// - Parameters:
    ///   - startDate: Start date in ISO-8601 format (e.g., "2026-03-01").
    ///   - endDate: End date in ISO-8601 format (e.g., "2026-03-15").
    /// - Returns: An array of `PreBillingRow` sorted by job name ascending.
    public func getPreBillingData(startDate: String, endDate: String) throws -> [PreBillingRow] {
        do {
            return try db.writer.read { dbConn -> [PreBillingRow] in
                let sql = """
                    WITH unlocked_labor AS (
                        SELECT le.*
                        FROM labor_entries le
                        WHERE le.deleted_at IS NULL
                          AND \(Self.localDateSQL("le.clock_in")) >= ?
                          AND \(Self.localDateSQL("le.clock_in")) <= ?
                          AND NOT EXISTS (
                              SELECT 1
                              FROM billing_periods bp
                              WHERE (bp.job_id = le.job_id OR bp.job_id IS NULL)
                                AND bp.locked_at IS NOT NULL
                                AND bp.deleted_at IS NULL
                                AND \(Self.localDateSQL("le.clock_in")) >= date(bp.period_start)
                                AND \(Self.localDateSQL("le.clock_in")) <= date(bp.period_end)
                          )
                    ),
                    labor_rollup AS (
                        SELECT job_id,
                               COALESCE(SUM(regular_hours), 0) AS regular_hours,
                               COALESCE(SUM(overtime_hours), 0) AS overtime_hours,
                               COUNT(*) AS labor_entry_count
                        FROM unlocked_labor
                        GROUP BY job_id
                    ),
                    material_rollup AS (
                        SELECT job_id,
                               COALESCE(SUM((qty_consumed - qty_returned) * COALESCE(unit_sell_at_consume, unit_cost_at_consume, 0)), 0) AS material_cost,
                               COUNT(*) AS material_line_count
                        FROM job_parts
                        WHERE deleted_at IS NULL
                          AND date(consumed_at) >= date(?)
                          AND date(consumed_at) <= date(?)
                        GROUP BY job_id
                    ),
                    po_rollup AS (
                        SELECT jpo.job_id,
                               COUNT(DISTINCT jpo.id) AS jpo_count,
                               COUNT(DISTINCT po.id) AS purchase_order_count
                        FROM job_parts_orders jpo
                        LEFT JOIN po_jpo_links pjl ON pjl.jpo_id = jpo.id
                        LEFT JOIN purchase_orders po ON po.id = pjl.po_id AND po.deleted_at IS NULL
                        WHERE jpo.deleted_at IS NULL
                          AND date(jpo.created_at) >= date(?)
                          AND date(jpo.created_at) <= date(?)
                        GROUP BY jpo.job_id
                    )
                    SELECT j.id,
                           COALESCE(j.job_number, '') AS job_number,
                           j.job_name,
                           COALESCE(lr.regular_hours, 0) AS regular_hours,
                           COALESCE(lr.overtime_hours, 0) AS overtime_hours,
                           COALESCE(mr.material_cost, 0) AS material_cost,
                           ROUND(((COALESCE(lr.regular_hours, 0) + COALESCE(lr.overtime_hours, 0)) * COALESCE(j.billing_rate, 0)) + COALESCE(mr.material_cost, 0), 2) AS billable_amount,
                           COALESCE(lr.labor_entry_count, 0) AS labor_entry_count,
                           COALESCE(mr.material_line_count, 0) AS material_line_count,
                           COALESCE(pr.jpo_count, 0) AS jpo_count,
                           COALESCE(pr.purchase_order_count, 0) AS purchase_order_count
                    FROM jobs j
                    LEFT JOIN labor_rollup lr ON lr.job_id = j.id
                    LEFT JOIN material_rollup mr ON mr.job_id = j.id
                    LEFT JOIN po_rollup pr ON pr.job_id = j.id
                    WHERE j.deleted_at IS NULL
                    GROUP BY j.id
                    HAVING regular_hours > 0 OR overtime_hours > 0 OR material_cost > 0
                    ORDER BY j.job_name, j.id
                    """

                let rows = try Row.fetchAll(
                    dbConn,
                    sql: sql,
                    arguments: [startDate, endDate, startDate, endDate, startDate, endDate]
                )
                return rows.map { row in
                    let laborEntryCount: Int = row["labor_entry_count"] ?? 0
                    let materialLineCount: Int = row["material_line_count"] ?? 0
                    let jpoCount: Int = row["jpo_count"] ?? 0
                    let purchaseOrderCount: Int = row["purchase_order_count"] ?? 0
                    return PreBillingRow(
                        id: row["id"] ?? 0,
                        jobNumber: row["job_number"] ?? "",
                        jobName: row["job_name"] ?? "",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        materialCost: row["material_cost"] ?? 0.0,
                        billableAmount: row["billable_amount"] ?? 0.0,
                        laborEntryCount: laborEntryCount,
                        materialLineCount: materialLineCount,
                        jpoCount: jpoCount,
                        purchaseOrderCount: purchaseOrderCount,
                        auditDiscrepancyCount: 0,
                        sourceSummary: Self.reportSourceSummary(
                            laborEntryCount: laborEntryCount,
                            materialLineCount: materialLineCount,
                            jpoCount: jpoCount,
                            purchaseOrderCount: purchaseOrderCount
                        )
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 6. Bookkeeper Export Data
    // =========================================================================

    /// A bookkeeper labor summary row aggregated per employee.
    public struct BookkeeperLaborRow: Sendable, Identifiable {
        public let id: Int64
        public let employeeName: String
        public let regularHours: Double
        public let overtimeHours: Double
        public let grossPay: Double
        public let laborEntryCount: Int
        public let sourceSummary: String

        public init(
            id: Int64,
            employeeName: String,
            regularHours: Double,
            overtimeHours: Double,
            grossPay: Double = 0,
            laborEntryCount: Int = 0,
            sourceSummary: String = ""
        ) {
            self.id = id
            self.employeeName = employeeName
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
            self.grossPay = grossPay
            self.laborEntryCount = laborEntryCount
            self.sourceSummary = sourceSummary
        }
    }

    /// A bookkeeper material purchase order row.
    public struct BookkeeperMaterialRow: Sendable, Identifiable {
        public let id: Int64
        public let poNumber: String
        public let supplierName: String
        public let totalAmount: Double
        public let lineItemCount: Int
        public let jpoCount: Int
        public let jobNames: String
        public let sourceSummary: String

        public init(
            id: Int64,
            poNumber: String,
            supplierName: String,
            totalAmount: Double,
            lineItemCount: Int = 0,
            jpoCount: Int = 0,
            jobNames: String = "",
            sourceSummary: String = ""
        ) {
            self.id = id
            self.poNumber = poNumber
            self.supplierName = supplierName
            self.totalAmount = totalAmount
            self.lineItemCount = lineItemCount
            self.jpoCount = jpoCount
            self.jobNames = jobNames
            self.sourceSummary = sourceSummary
        }
    }

    /// Get bookkeeper labor summary: per-employee hours for a date range.
    ///
    /// - Parameters:
    ///   - startDate: Start date in ISO-8601 format (e.g., "2026-03-01").
    ///   - endDate: End date in ISO-8601 format (e.g., "2026-03-15").
    /// - Returns: An array of `BookkeeperLaborRow` sorted by employee name ascending.
    public func getBookkeeperLaborSummary(startDate: String, endDate: String) throws -> [BookkeeperLaborRow] {
        do {
            return try db.writer.read { dbConn -> [BookkeeperLaborRow] in
                let sql = """
                    SELECT le.user_id AS id,
                           COALESCE(u.display_name, u.email, 'Unknown') AS name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours,
                           ROUND(COALESCE(SUM(
                               le.regular_hours * COALESCE(u.pay_rate, 0) +
                               le.overtime_hours * COALESCE(u.pay_rate, 0) * 1.5
                           ), 0), 2) AS gross_pay,
                           COUNT(le.id) AS labor_entry_count
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    WHERE \(Self.localDateSQL("le.clock_in")) >= date(?)
                      AND \(Self.localDateSQL("le.clock_in")) <= date(?)
                      AND le.deleted_at IS NULL
                    GROUP BY le.user_id
                    ORDER BY name, le.user_id
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.map { row in
                    let laborEntryCount: Int = row["labor_entry_count"] ?? 0
                    return BookkeeperLaborRow(
                        id: row["id"] ?? 0,
                        employeeName: row["name"] ?? "Unknown",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0,
                        grossPay: row["gross_pay"] ?? 0.0,
                        laborEntryCount: laborEntryCount,
                        sourceSummary: "\(laborEntryCount) labor entr\(laborEntryCount == 1 ? "y" : "ies")"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get bookkeeper material purchase orders for a date range.
    ///
    /// - Parameters:
    ///   - startDate: Start date in ISO-8601 format (e.g., "2026-03-01").
    ///   - endDate: End date in ISO-8601 format (e.g., "2026-03-15").
    /// - Returns: An array of `BookkeeperMaterialRow` sorted by PO number ascending.
    public func getBookkeeperMaterialPOs(startDate: String, endDate: String) throws -> [BookkeeperMaterialRow] {
        do {
            return try db.writer.read { dbConn -> [BookkeeperMaterialRow] in
                let sql = """
                    SELECT po.id,
                           po.po_number,
                           COALESCE(s.name, 'Unknown') AS supplier_name,
                           COALESCE(po.total_cost, 0) AS total_amount,
                           COUNT(DISTINCT pli.id) AS line_item_count,
                           COUNT(DISTINCT jpo.id) AS jpo_count,
                           COALESCE((
                               SELECT GROUP_CONCAT(ordered_jobs.job_name)
                               FROM (
                                   SELECT j2.job_name AS job_name, MIN(j2.id) AS first_job_id
                                   FROM po_line_items pli2
                                   JOIN jpo_line_items jli2 ON jli2.id = pli2.jpo_line_id AND jli2.deleted_at IS NULL
                                   JOIN job_parts_orders jpo2 ON jpo2.id = jli2.jpo_id AND jpo2.deleted_at IS NULL
                                   JOIN jobs j2 ON j2.id = jpo2.job_id AND j2.deleted_at IS NULL
                                   WHERE pli2.po_id = po.id
                                     AND pli2.deleted_at IS NULL
                                   GROUP BY j2.job_name
                                   ORDER BY LOWER(j2.job_name), first_job_id
                               ) ordered_jobs
                           ), '') AS job_names
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    LEFT JOIN po_line_items pli ON pli.po_id = po.id AND pli.deleted_at IS NULL
                    LEFT JOIN jpo_line_items jli ON jli.id = pli.jpo_line_id AND jli.deleted_at IS NULL
                    LEFT JOIN job_parts_orders jpo ON jpo.id = jli.jpo_id AND jpo.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = jpo.job_id AND j.deleted_at IS NULL
                    WHERE po.deleted_at IS NULL
                      AND po.status != 'cancelled'
                      AND date(COALESCE(po.order_date, po.created_at)) >= date(?)
                      AND date(COALESCE(po.order_date, po.created_at)) <= date(?)
                    GROUP BY po.id
                    ORDER BY po.po_number, po.id
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.map { row in
                    let lineItemCount: Int = row["line_item_count"] ?? 0
                    let jpoCount: Int = row["jpo_count"] ?? 0
                    return BookkeeperMaterialRow(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown",
                        totalAmount: row["total_amount"] ?? 0.0,
                        lineItemCount: lineItemCount,
                        jpoCount: jpoCount,
                        jobNames: row["job_names"] ?? "",
                        sourceSummary: "\(lineItemCount) PO line\(lineItemCount == 1 ? "" : "s"), \(jpoCount) JPO\(jpoCount == 1 ? "" : "s")"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. Audit Summary Data
    // =========================================================================

    public struct AuditSummaryRow: Sendable, Identifiable {
        public let id: Int64
        public let partId: Int64
        public let partName: String
        public let areaName: String
        public let countCount: Int
        public let discrepancyCount: Int
        public let totalVariance: Int
        public let totalVarianceDollars: Double
        public let lastCountedAt: String?
        public let sourceSummary: String

        public init(
            id: Int64,
            partId: Int64,
            partName: String,
            areaName: String,
            countCount: Int,
            discrepancyCount: Int,
            totalVariance: Int,
            totalVarianceDollars: Double,
            lastCountedAt: String?,
            sourceSummary: String
        ) {
            self.id = id
            self.partId = partId
            self.partName = partName
            self.areaName = areaName
            self.countCount = countCount
            self.discrepancyCount = discrepancyCount
            self.totalVariance = totalVariance
            self.totalVarianceDollars = totalVarianceDollars
            self.lastCountedAt = lastCountedAt
            self.sourceSummary = sourceSummary
        }
    }

    public func getAuditSummaries(startDate: String, endDate: String) throws -> [AuditSummaryRow] {
        do {
            return try db.writer.read { dbConn -> [AuditSummaryRow] in
                let sql = """
                    SELECT ac.part_id,
                           COALESCE(p.name, 'Unknown Part') AS part_name,
                           COALESCE(wsa.full_location_code, wsa.area_code, 'Unknown Area') AS area_name,
                           COUNT(ac.id) AS count_count,
                           SUM(CASE WHEN ac.variance != 0 THEN 1 ELSE 0 END) AS discrepancy_count,
                           COALESCE(SUM(ac.variance), 0) AS total_variance,
                           COALESCE(SUM(ABS(ac.variance_dollars)), 0) AS total_variance_dollars,
                           MAX(ac.counted_at) AS last_counted_at
                    FROM audit_counts ac
                    JOIN audit_sessions_v2 aus ON aus.id = ac.session_id AND aus.deleted_at IS NULL
                    LEFT JOIN parts p ON p.id = ac.part_id AND p.deleted_at IS NULL
                    LEFT JOIN warehouse_storage_areas wsa ON wsa.id = ac.area_id AND wsa.deleted_at IS NULL
                    WHERE date(ac.counted_at) >= date(?)
                      AND date(ac.counted_at) <= date(?)
                    GROUP BY ac.part_id, area_name
                    ORDER BY discrepancy_count DESC, ABS(total_variance_dollars) DESC, part_name, area_name
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.enumerated().map { index, row in
                    let countCount: Int = row["count_count"] ?? 0
                    let discrepancyCount: Int = row["discrepancy_count"] ?? 0
                    return AuditSummaryRow(
                        id: Int64(index + 1),
                        partId: row["part_id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown Part",
                        areaName: row["area_name"] ?? "Unknown Area",
                        countCount: countCount,
                        discrepancyCount: discrepancyCount,
                        totalVariance: row["total_variance"] ?? 0,
                        totalVarianceDollars: row["total_variance_dollars"] ?? 0.0,
                        lastCountedAt: row["last_counted_at"] as String?,
                        sourceSummary: "\(countCount) audit count\(countCount == 1 ? "" : "s"), \(discrepancyCount) discrepanc\(discrepancyCount == 1 ? "y" : "ies")"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 8. Reports Stats
    // =========================================================================

    /// Get high-level reporting stats: open billing periods, pending timesheets,
    /// and total labor hours this month.
    public func getReportsStats() throws -> ReportsStats {
        let openPeriods = try safeCount(
            sql: "SELECT COUNT(*) FROM billing_periods WHERE locked_at IS NULL AND deleted_at IS NULL"
        )

        // Pending timesheets = labor entries from this month that are still clocked in
        let pendingTimesheets = try safeCount(
            sql: """
                SELECT COUNT(*) FROM labor_entries
                WHERE status = 'clocked_in'
                  AND deleted_at IS NULL
                  AND \(Self.localDateSQL("clock_in")) >= date('now', 'localtime', 'start of month')
                """
        )

        let totalLaborHoursThisMonth = try safeCountDouble(
            sql: """
                SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
                FROM labor_entries
                WHERE deleted_at IS NULL
                  AND \(Self.localDateSQL("clock_in")) >= date('now', 'localtime', 'start of month')
                """
        )

        return ReportsStats(
            openPeriods: openPeriods,
            pendingTimesheets: pendingTimesheets,
            totalLaborHoursThisMonth: totalLaborHoursThisMonth
        )
    }

    // =========================================================================
    // MARK: - Internal Helpers
    // =========================================================================

    /// Execute a SELECT COUNT(*) or SELECT COALESCE(SUM(...), 0) query returning an Int.
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

    /// Execute a SELECT COALESCE(SUM(...), 0) query returning a Double.
    /// Returns 0.0 if the table does not exist.
    private func safeCountDouble(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Double {
        do {
            return try db.writer.read { dbConn in
                try Double.fetchOne(dbConn, sql: sql, arguments: arguments) ?? 0.0
            }
        } catch {
            if isTableNotFoundError(error) { return 0.0 }
            throw error
        }
    }

    private static func reportSourceSummary(
        laborEntryCount: Int,
        materialLineCount: Int,
        jpoCount: Int,
        purchaseOrderCount: Int
    ) -> String {
        [
            "\(laborEntryCount) labor entr\(laborEntryCount == 1 ? "y" : "ies")",
            "\(materialLineCount) material line\(materialLineCount == 1 ? "" : "s")",
            "\(jpoCount) JPO\(jpoCount == 1 ? "" : "s")",
            "\(purchaseOrderCount) PO\(purchaseOrderCount == 1 ? "" : "s")"
        ].joined(separator: ", ")
    }

    // =========================================================================
    // MARK: - Custom Report Builder
    // =========================================================================

    /// A saved report configuration.
    public struct SavedReport: Sendable, Identifiable {
        public let id: Int64
        public let name: String
        public let reportType: String
        public let columnsJson: String
        public let filtersJson: String
        public let createdBy: Int64
        public let isShared: Bool
        public let createdAt: String?
        public let lastRunAt: String?
    }

    /// Generate a custom report based on type and selected columns/filters.
    /// Returns rows as arrays of strings matching the requested columns.
    public func generateCustomReport(
        type: String, columns: [String],
        startDate: Date, endDate: Date,
        filters: [String: String]
    ) throws -> [[String]] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)

        switch type {
        case "labor_hours":
            return try generateLaborHoursReport(columns: columns, startStr: startStr, endStr: endStr)
        case "parts_usage":
            return try generatePartsUsageReport(columns: columns, startStr: startStr, endStr: endStr)
        case "job_costs":
            return try generateJobCostsReport(columns: columns, startStr: startStr, endStr: endStr)
        case "tool_checkouts":
            return try generateToolCheckoutsReport(columns: columns, startStr: startStr, endStr: endStr)
        case "vehicle_fuel":
            return try generateVehicleFuelReport(columns: columns, startStr: startStr, endStr: endStr)
        case "order_history":
            return try generateOrderHistoryReport(columns: columns, startStr: startStr, endStr: endStr)
        default:
            return []
        }
    }

    /// Save a report configuration.
    @discardableResult
    public func saveReportConfig(
        name: String, type: String, columns: [String],
        filters: [String: String], userId: Int64, isShared: Bool
    ) throws -> Int64 {
        guard let normalizedName = name.normalizedRequiredText,
              let normalizedType = type.normalizedRequiredText else {
            throw ReportsError.requiredFieldEmpty
        }

        try db.writer.read { dbConn in
            try ServicePermissionGate.requirePermission(dbConn, userId: userId, permissionKey: "view_reports")
        }

        let columnsData = try JSONSerialization.data(withJSONObject: columns)
        let filtersData = try JSONSerialization.data(withJSONObject: filters)
        let columnsJson = String(data: columnsData, encoding: .utf8) ?? "[]"
        let filtersJson = String(data: filtersData, encoding: .utf8) ?? "{}"
        return try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO saved_reports (name, report_type, columns_json, filters_json, created_by, is_shared)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [normalizedName, normalizedType, columnsJson, filtersJson, userId, isShared])
            return dbConn.lastInsertedRowID
        }
    }

    /// Get saved reports for a user (own + shared).
    // SCANNER-IGNORE: system-only read-only listing; does not write audit fields.
    public func getSavedReports(userId: Int64) throws -> [SavedReport] {
        do {
            return try db.writer.read { dbConn -> [SavedReport] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT * FROM saved_reports
                    WHERE deleted_at IS NULL AND (created_by = ? OR is_shared = 1)
                    ORDER BY last_run_at DESC, created_at DESC
                    """, arguments: [userId])
                return rows.map { row in
                    SavedReport(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        reportType: row["report_type"] ?? "",
                        columnsJson: row["columns_json"] ?? "[]",
                        filtersJson: row["filters_json"] ?? "{}",
                        createdBy: row["created_by"] ?? 0,
                        isShared: row["is_shared"] as Bool? ?? false,
                        createdAt: row["created_at"] as String?,
                        lastRunAt: row["last_run_at"] as String?
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Delete a saved report (soft delete).
    public func deleteSavedReport(reportId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE saved_reports SET deleted_at = datetime('now') WHERE id = ?
                """, arguments: [reportId])
        }
    }

    /// Update last_run_at timestamp.
    public func markReportRun(reportId: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE saved_reports SET last_run_at = datetime('now') WHERE id = ?
                """, arguments: [reportId])
        }
    }

    // MARK: - Custom Report Generators

    private func generateLaborHoursReport(columns: [String], startStr: String, endStr: String) throws -> [[String]] {
        do {
            return try db.writer.read { dbConn -> [[String]] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT COALESCE(u.display_name, u.email, 'Unknown') AS employee_name,
                           \(Self.localDateSQL("le.clock_in")) AS date,
                           ROUND(le.regular_hours + le.overtime_hours, 2) AS hours,
                           COALESCE(j.job_name, '') AS job_name,
                           COALESCE(le.status, '') AS activity_type,
                           COALESCE(le.clock_in, '') AS clock_in,
                           COALESCE(le.clock_out, '') AS clock_out,
                           COALESCE(le.notes, '') AS notes
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE le.deleted_at IS NULL
                      AND \(Self.localDateSQL("le.clock_in")) >= ? AND \(Self.localDateSQL("le.clock_in")) <= ?
                    ORDER BY le.clock_in DESC, employee_name
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    columns.map { col in
                        switch col {
                        case "employee_name": return row["employee_name"] as String? ?? ""
                        case "date": return row["date"] as String? ?? ""
                        case "hours": return String(format: "%.2f", row["hours"] as Double? ?? 0)
                        case "job_name": return row["job_name"] as String? ?? ""
                        case "activity_type": return row["activity_type"] as String? ?? ""
                        case "clock_in": return row["clock_in"] as String? ?? ""
                        case "clock_out": return row["clock_out"] as String? ?? ""
                        case "notes": return row["notes"] as String? ?? ""
                        default: return ""
                        }
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private func generatePartsUsageReport(columns: [String], startStr: String, endStr: String) throws -> [[String]] {
        do {
            return try db.writer.read { dbConn -> [[String]] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT COALESCE(p.name, 'Unknown') AS part_name,
                           COALESCE(pc.name, '') AS category,
                           ABS(sm.qty) AS quantity_used,
                           COALESCE(j.job_name, '') AS job_name,
                           date(sm.created_at) AS date,
                           COALESCE(sm.unit_cost_at_move, p.company_cost_price, 0) AS cost,
                           ABS(sm.qty) * COALESCE(sm.unit_cost_at_move, p.company_cost_price, 0) AS total_cost
                    FROM stock_movements sm
                    LEFT JOIN parts p ON p.id = sm.part_id AND p.deleted_at IS NULL
                    LEFT JOIN part_categories pc ON pc.id = p.category_id AND pc.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = sm.job_id AND j.deleted_at IS NULL
                    WHERE sm.deleted_at IS NULL AND sm.movement_type IN \(StockMovement.MovementType.sqlList(StockMovement.MovementType.materialUsageTypes))
                      AND date(sm.created_at) >= ? AND date(sm.created_at) <= ?
                    ORDER BY sm.created_at DESC
                    LIMIT 500
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    columns.map { col in
                        switch col {
                        case "part_name": return row["part_name"] as String? ?? ""
                        case "category": return row["category"] as String? ?? ""
                        case "quantity_used": return "\(row["quantity_used"] as Int? ?? 0)"
                        case "job_name": return row["job_name"] as String? ?? ""
                        case "date": return row["date"] as String? ?? ""
                        case "cost": return String(format: "%.2f", row["cost"] as Double? ?? 0)
                        case "total_cost": return String(format: "%.2f", row["total_cost"] as Double? ?? 0)
                        default: return ""
                        }
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private func generateJobCostsReport(columns: [String], startStr: String, endStr: String) throws -> [[String]] {
        do {
            return try db.writer.read { dbConn -> [[String]] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT j.job_name AS job_name,
                           COALESCE((SELECT SUM(le.regular_hours * COALESCE(u2.pay_rate, 0) +
                                               le.overtime_hours * COALESCE(u2.pay_rate, 0) * 1.5)
                                     FROM labor_entries le
                                     LEFT JOIN users u2 ON u2.id = le.user_id
                                     WHERE le.job_id = j.id AND le.deleted_at IS NULL
                                       AND \(Self.localDateSQL("le.clock_in")) >= ? AND \(Self.localDateSQL("le.clock_in")) <= ?), 0) AS labor_cost,
                           COALESCE((SELECT SUM(ABS(sm.qty) * COALESCE(sm.unit_cost_at_move, 0))
                                     FROM stock_movements sm
                                     WHERE sm.job_id = j.id AND sm.deleted_at IS NULL
                                       AND date(sm.created_at) >= ? AND date(sm.created_at) <= ?), 0) AS material_cost,
                           COALESCE(j.budget_limit, 0) AS budget
                    FROM jobs j
                    WHERE j.deleted_at IS NULL AND j.status != 'archived'
                    ORDER BY j.job_name
                    """, arguments: [startStr, endStr, startStr, endStr])
                return rows.map { row in
                    let labor: Double = row["labor_cost"] ?? 0
                    let material: Double = row["material_cost"] ?? 0
                    let total = labor + material
                    let budget: Double = row["budget"] ?? 0
                    let variance = budget - total
                    return columns.map { col in
                        switch col {
                        case "job_name": return row["job_name"] as String? ?? ""
                        case "labor_cost": return String(format: "%.2f", labor)
                        case "material_cost": return String(format: "%.2f", material)
                        case "total_cost": return String(format: "%.2f", total)
                        case "budget": return String(format: "%.2f", budget)
                        case "variance": return String(format: "%.2f", variance)
                        default: return ""
                        }
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private func generateToolCheckoutsReport(columns: [String], startStr: String, endStr: String) throws -> [[String]] {
        do {
            return try db.writer.read { dbConn -> [[String]] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT COALESCE(t.name, 'Unknown') AS tool_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name,
                           tc.checked_out_at AS checkout_date,
                           COALESCE(tc.checked_in_at, '') AS return_date,
                           COALESCE(tc.checkout_condition, '') AS condition_out,
                           COALESCE(tc.return_condition, '') AS condition_in
                    FROM tool_checkouts tc
                    LEFT JOIN tools t ON t.id = tc.tool_id AND t.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = tc.checked_out_by AND u.deleted_at IS NULL
                    WHERE tc.deleted_at IS NULL
                      AND date(tc.checked_out_at) >= ? AND date(tc.checked_out_at) <= ?
                    ORDER BY tc.checked_out_at DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    columns.map { col in
                        switch col {
                        case "tool_name": return row["tool_name"] as String? ?? ""
                        case "employee_name": return row["employee_name"] as String? ?? ""
                        case "checkout_date": return String((row["checkout_date"] as String? ?? "").prefix(10))
                        case "return_date": return String((row["return_date"] as String? ?? "").prefix(10))
                        case "condition_out": return row["condition_out"] as String? ?? ""
                        case "condition_in": return row["condition_in"] as String? ?? ""
                        default: return ""
                        }
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private func generateVehicleFuelReport(columns: [String], startStr: String, endStr: String) throws -> [[String]] {
        do {
            return try db.writer.read { dbConn -> [[String]] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT COALESCE(v.vehicle_name, v.vehicle_number, 'Unknown') AS vehicle_name,
                           f.log_date AS date,
                           COALESCE(f.gallons, 0) AS gallons,
                           COALESCE(f.total_cost, 0) AS cost,
                           COALESCE(f.odometer_reading, 0) AS odometer
                    FROM fuel_logs f
                    LEFT JOIN vehicles v ON v.id = f.vehicle_id AND v.deleted_at IS NULL
                    WHERE f.deleted_at IS NULL
                      AND f.log_date >= ? AND f.log_date <= ?
                    ORDER BY f.log_date DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    columns.map { col in
                        switch col {
                        case "vehicle_name": return row["vehicle_name"] as String? ?? ""
                        case "date": return row["date"] as String? ?? ""
                        case "gallons": return String(format: "%.1f", row["gallons"] as Double? ?? 0)
                        case "cost": return String(format: "%.2f", row["cost"] as Double? ?? 0)
                        case "odometer": return "\(row["odometer"] as Int? ?? 0)"
                        default: return ""
                        }
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private func generateOrderHistoryReport(columns: [String], startStr: String, endStr: String) throws -> [[String]] {
        do {
            return try db.writer.read { dbConn -> [[String]] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT po.po_number, COALESCE(s.name, 'Unknown') AS supplier_name,
                           COALESCE(po.order_date, date(po.created_at)) AS order_date,
                           COALESCE(po.total_cost, 0) AS total,
                           COALESCE(po.status, '') AS status,
                           (SELECT COUNT(*) FROM po_line_items pol WHERE pol.po_id = po.id AND pol.deleted_at IS NULL) AS items_count
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    WHERE po.deleted_at IS NULL
                      AND COALESCE(po.order_date, date(po.created_at)) >= ?
                      AND COALESCE(po.order_date, date(po.created_at)) <= ?
                    ORDER BY order_date DESC
                    """, arguments: [startStr, endStr])
                return rows.map { row in
                    columns.map { col in
                        switch col {
                        case "po_number": return row["po_number"] as String? ?? ""
                        case "supplier_name": return row["supplier_name"] as String? ?? ""
                        case "order_date": return row["order_date"] as String? ?? ""
                        case "total": return String(format: "%.2f", row["total"] as Double? ?? 0)
                        case "status": return row["status"] as String? ?? ""
                        case "items_count": return "\(row["items_count"] as Int? ?? 0)"
                        default: return ""
                        }
                    }
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    private static func localDateSQL(_ expression: String) -> String {
        "CASE WHEN length(\(expression)) <= 10 THEN date(\(expression)) ELSE date(\(expression), 'localtime') END"
    }

    private static func correctedBillableHours(
        dbConn: Database,
        laborEntryId: Int64,
        adjustedIn: Date,
        adjustedOut: Date
    ) throws -> Double {
        let rawHours = max(0, adjustedOut.timeIntervalSince(adjustedIn) / 3600.0)
        let unpaidBreakMinutes = try Double.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(duration_minutes), 0)
            FROM break_records
            WHERE labor_entry_id = ? AND COALESCE(is_paid, 1) = 0 AND deleted_at IS NULL
            """, arguments: [laborEntryId]) ?? 0
        return max(0, rawHours - (unpaidBreakMinutes / 60.0))
    }

    private static func fetchOvertimeSettings(_ dbConn: Database) throws -> OvertimeSettings {
        if let settings = try OvertimeSettings.fetchOne(
            dbConn,
            sql: "SELECT * FROM overtime_settings ORDER BY id LIMIT 1"
        ) {
            return settings
        }
        return OvertimeSettings(
            id: nil,
            calculationRule: "daily_only",
            dailyThresholdHours: 8.0,
            weeklyThresholdHours: nil,
            weekStartWeekday: 2,
            updatedBy: nil,
            updatedAt: nil
        )
    }

    private static func allocateCorrectedOvertimeHours(
        dbConn: Database,
        userId: Int64,
        laborEntryId: Int64,
        clockInTimestamp: String,
        totalHours: Double
    ) throws -> (regular: Double, overtime: Double) {
        let settings = try fetchOvertimeSettings(dbConn)
        let dailyPriorHours = try priorCompletedHours(
            dbConn: dbConn,
            userId: userId,
            laborEntryId: laborEntryId,
            whereSQL: "\(localDateSQL("clock_in")) = date(?, 'localtime') AND datetime(clock_in) < datetime(?)",
            arguments: [clockInTimestamp, clockInTimestamp]
        )
        let dailyRemaining = max(0, settings.dailyThresholdHours - dailyPriorHours)

        let weeklyRemaining: Double
        if let weeklyThresholdHours = settings.weeklyThresholdHours,
           let clockInDate = CoreFormatters.parseDateTime(clockInTimestamp) {
            let interval = localWeekInterval(containing: clockInDate, weekStartWeekday: settings.weekStartWeekday)
            let weekStart = sqliteUTCTimestamp(interval.start)
            let weekEnd = sqliteUTCTimestamp(interval.end)
            let weeklyPriorHours = try priorCompletedHours(
                dbConn: dbConn,
                userId: userId,
                laborEntryId: laborEntryId,
                whereSQL: "datetime(clock_in) >= datetime(?) AND datetime(clock_in) < datetime(?) AND datetime(clock_in) < datetime(?)",
                arguments: [weekStart, weekEnd, clockInTimestamp]
            )
            weeklyRemaining = max(0, weeklyThresholdHours - weeklyPriorHours)
        } else {
            weeklyRemaining = Double.greatestFiniteMagnitude
        }

        let regularCapacity: Double
        switch settings.calculationRule {
        case "weekly_only":
            regularCapacity = weeklyRemaining
        case "daily_and_weekly":
            regularCapacity = min(dailyRemaining, weeklyRemaining)
        default:
            regularCapacity = dailyRemaining
        }

        let regularHours = min(totalHours, max(0, regularCapacity))
        let overtimeHours = max(0, totalHours - regularHours)
        return (roundHours(regularHours), roundHours(overtimeHours))
    }

    private static func priorCompletedHours(
        dbConn: Database,
        userId: Int64,
        laborEntryId: Int64,
        whereSQL: String,
        arguments: StatementArguments
    ) throws -> Double {
        var allArguments: StatementArguments = [userId, laborEntryId]
        allArguments += arguments
        return try Double.fetchOne(dbConn, sql: """
            SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
            FROM labor_entries
            WHERE user_id = ?
              AND id != ?
              AND status = 'completed'
              AND deleted_at IS NULL
              AND \(whereSQL)
            """, arguments: allArguments) ?? 0
    }

    private static func localWeekInterval(containing date: Date, weekStartWeekday: Int) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = weekStartWeekday

        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysSinceStart = (weekday - weekStartWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -daysSinceStart, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private static func sqliteUTCTimestamp(_ date: Date) -> String {
        sqliteUTCDateFormatter.string(from: date)
    }

    private static let sqliteUTCDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func roundHours(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func timesheetCorrectionAuditSQL(whereClause: String) -> String {
        """
        SELECT tca.id, tca.labor_entry_id, tca.employee_user_id, tca.job_id,
               COALESCE(j.job_name, 'Unknown Job') AS job_name,
               COALESCE(j.job_number, '') AS job_number,
               COALESCE(employee.display_name, employee.email, 'Unknown') AS employee_name,
               tca.original_clock_in, tca.original_clock_out,
               tca.adjusted_clock_in, tca.adjusted_clock_out,
               COALESCE(tca.original_regular_hours, 0) AS original_regular_hours,
               COALESCE(tca.original_overtime_hours, 0) AS original_overtime_hours,
               COALESCE(tca.adjusted_regular_hours, 0) AS adjusted_regular_hours,
               COALESCE(tca.adjusted_overtime_hours, 0) AS adjusted_overtime_hours,
               tca.reason, tca.actor_user_id,
               COALESCE(actor.display_name, actor.email, 'Unknown') AS actor_name,
               tca.created_at,
               COALESCE(tca.approval_status, 'pending_review') AS approval_status,
               COALESCE(approver.display_name, approver.email) AS approver_name
        FROM timesheet_correction_audits tca
        LEFT JOIN jobs j ON j.id = tca.job_id AND j.deleted_at IS NULL
        LEFT JOIN users employee ON employee.id = tca.employee_user_id AND employee.deleted_at IS NULL
        LEFT JOIN users actor ON actor.id = tca.actor_user_id AND actor.deleted_at IS NULL
        LEFT JOIN users approver ON approver.id = tca.approved_by AND approver.deleted_at IS NULL
        WHERE \(whereClause)
        ORDER BY tca.created_at DESC, tca.id DESC
        """
    }

    private static func mapTimesheetCorrectionAuditRecord(_ row: Row) -> TimesheetCorrectionAuditRecord {
        TimesheetCorrectionAuditRecord(
            id: row["id"] ?? 0,
            segmentId: row["labor_entry_id"] ?? 0,
            jobId: row["job_id"] ?? 0,
            jobName: row["job_name"] ?? "Unknown Job",
            jobNumber: row["job_number"] ?? "",
            employeeUserId: row["employee_user_id"] ?? 0,
            employeeName: row["employee_name"] ?? "Unknown",
            originalClockIn: row["original_clock_in"] ?? "",
            originalClockOut: row["original_clock_out"] as String?,
            adjustedClockIn: row["adjusted_clock_in"] ?? "",
            adjustedClockOut: row["adjusted_clock_out"] ?? "",
            originalRegularHours: row["original_regular_hours"] ?? 0,
            originalOvertimeHours: row["original_overtime_hours"] ?? 0,
            adjustedRegularHours: row["adjusted_regular_hours"] ?? 0,
            adjustedOvertimeHours: row["adjusted_overtime_hours"] ?? 0,
            reason: row["reason"] ?? "",
            actorUserId: row["actor_user_id"] ?? 0,
            actorName: row["actor_name"] ?? "Unknown",
            changedAt: row["created_at"] ?? "",
            approvalStatus: row["approval_status"] ?? "pending_review",
            approverName: row["approver_name"] as String?
        )
    }

    private static func fetchTimesheetCorrectionAuditRecord(
        dbConn: Database,
        correctionId: Int64
    ) throws -> TimesheetCorrectionAuditRecord? {
        let sql = timesheetCorrectionAuditSQL(whereClause: "tca.id = ? AND tca.deleted_at IS NULL")
        return try Row.fetchOne(dbConn, sql: sql, arguments: [correctionId]).map(mapTimesheetCorrectionAuditRecord)
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}

public enum ReportsError: Error, LocalizedError, Equatable {
    case requiredFieldEmpty
    case timesheetSegmentNotFound(Int64)
    case invalidTimesheetCorrectionReason
    case invalidTimesheetCorrectionRange
    case invalidTimesheetOriginalTimestamp(String)
    case timesheetCorrectionAuditUnavailable

    public var errorDescription: String? {
        switch self {
        case .requiredFieldEmpty:
            return "Report name and type are required."
        case .timesheetSegmentNotFound:
            return "Timesheet entry was not found."
        case .invalidTimesheetCorrectionReason:
            return "Correction reason is required."
        case .invalidTimesheetCorrectionRange:
            return "Adjusted clock out cannot be before adjusted clock in."
        case .invalidTimesheetOriginalTimestamp(let field):
            return "Original \(field) timestamp is malformed. Repair the stored time entry before saving a correction."
        case .timesheetCorrectionAuditUnavailable:
            return "Timesheet correction audit storage is not available."
        }
    }
}
