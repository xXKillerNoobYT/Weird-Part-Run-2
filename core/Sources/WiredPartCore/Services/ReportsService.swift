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
        public let userName: String
        public let regularHours: Double
        public let overtimeHours: Double
        public let totalHours: Double
        public let daysWorked: Int

        public init(
            id: Int64, userName: String, regularHours: Double,
            overtimeHours: Double, totalHours: Double, daysWorked: Int
        ) {
            self.id = id
            self.userName = userName
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
            self.totalHours = totalHours
            self.daysWorked = daysWorked
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
                           COUNT(DISTINCT date(le.clock_in)) AS days_worked
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    WHERE le.deleted_at IS NULL
                      AND date(le.clock_in) >= date(?)
                      AND date(le.clock_in) <= date(?)
                    GROUP BY le.user_id
                    ORDER BY user_name ASC
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.enumerated().map { index, row in
                    TimesheetRow(
                        id: Int64(index + 1),
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
                      AND date(le.clock_in) = date(?)
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
        public let jobName: String
        public let regularHours: Double
        public let overtimeHours: Double

        public init(id: Int64, jobName: String, regularHours: Double, overtimeHours: Double) {
            self.id = id
            self.jobName = jobName
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
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
                    SELECT j.id, j.job_name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours
                    FROM jobs j
                    LEFT JOIN labor_entries le ON le.job_id = j.id
                        AND date(le.clock_in) >= ? AND date(le.clock_in) <= ?
                        AND le.deleted_at IS NULL
                        AND NOT EXISTS (
                            SELECT 1
                            FROM billing_periods bp
                            WHERE (bp.job_id = le.job_id OR bp.job_id IS NULL)
                              AND bp.locked_at IS NOT NULL
                              AND bp.deleted_at IS NULL
                              AND date(le.clock_in) >= date(bp.period_start)
                              AND date(le.clock_in) <= date(bp.period_end)
                        )
                    WHERE j.deleted_at IS NULL
                    GROUP BY j.id
                    HAVING regular_hours > 0 OR overtime_hours > 0
                    ORDER BY j.job_name
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.map { row in
                    PreBillingRow(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0
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

        public init(id: Int64, employeeName: String, regularHours: Double, overtimeHours: Double) {
            self.id = id
            self.employeeName = employeeName
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
        }
    }

    /// A bookkeeper material purchase order row.
    public struct BookkeeperMaterialRow: Sendable, Identifiable {
        public let id: Int64
        public let poNumber: String
        public let supplierName: String
        public let totalAmount: Double

        public init(id: Int64, poNumber: String, supplierName: String, totalAmount: Double) {
            self.id = id
            self.poNumber = poNumber
            self.supplierName = supplierName
            self.totalAmount = totalAmount
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
                    SELECT u.id, COALESCE(u.display_name, u.email) AS name,
                           COALESCE(SUM(le.regular_hours), 0) AS regular_hours,
                           COALESCE(SUM(le.overtime_hours), 0) AS overtime_hours
                    FROM users u
                    JOIN labor_entries le ON le.user_id = u.id
                    WHERE date(le.clock_in) >= ? AND date(le.clock_in) <= ?
                      AND le.deleted_at IS NULL
                    GROUP BY u.id
                    ORDER BY name
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.map { row in
                    BookkeeperLaborRow(
                        id: row["id"] ?? 0,
                        employeeName: row["name"] ?? "Unknown",
                        regularHours: row["regular_hours"] ?? 0.0,
                        overtimeHours: row["overtime_hours"] ?? 0.0
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
                    SELECT po.id, po.po_number, COALESCE(s.name, 'Unknown') AS supplier_name,
                           COALESCE(po.total_cost, 0) AS total_amount
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    WHERE date(po.created_at) >= ? AND date(po.created_at) <= ?
                    ORDER BY po.po_number
                    """

                let rows = try Row.fetchAll(dbConn, sql: sql, arguments: [startDate, endDate])
                return rows.map { row in
                    BookkeeperMaterialRow(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown",
                        totalAmount: row["total_amount"] ?? 0.0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - 7. Reports Stats
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
                  AND date(clock_in) >= date('now', 'start of month')
                """
        )

        let totalLaborHoursThisMonth = try safeCountDouble(
            sql: """
                SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
                FROM labor_entries
                WHERE deleted_at IS NULL
                  AND date(clock_in) >= date('now', 'start of month')
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
        let columnsData = try JSONSerialization.data(withJSONObject: columns)
        let filtersData = try JSONSerialization.data(withJSONObject: filters)
        let columnsJson = String(data: columnsData, encoding: .utf8) ?? "[]"
        let filtersJson = String(data: filtersData, encoding: .utf8) ?? "{}"
        return try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO saved_reports (name, report_type, columns_json, filters_json, created_by, is_shared)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [name, type, columnsJson, filtersJson, userId, isShared])
            return dbConn.lastInsertedRowID
        }
    }

    /// Get saved reports for a user (own + shared).
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
                           date(le.clock_in) AS date,
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
                      AND date(le.clock_in) >= ? AND date(le.clock_in) <= ?
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
                    WHERE sm.deleted_at IS NULL AND sm.movement_type IN ('pull', 'usage', 'job_pull')
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
                                       AND date(le.clock_in) >= ? AND date(le.clock_in) <= ?), 0) AS labor_cost,
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
                    LEFT JOIN tools t ON t.id = tc.tool_id
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

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
