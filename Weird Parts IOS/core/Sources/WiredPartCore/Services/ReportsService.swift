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
                    LEFT JOIN users u ON u.id = le.user_id
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
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
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
                let sql = """
                    SELECT j.id, j.job_name,
                           COALESCE(j.estimated_hours, 0) * COALESCE(j.billing_rate, 0) AS revenue,
                           COALESCE((SELECT SUM(le.regular_hours + le.overtime_hours)
                                     FROM labor_entries le
                                     WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0)
                               * COALESCE(j.billing_rate, 0) AS labor_cost,
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
    // MARK: - 5. Reports Stats
    // =========================================================================

    /// Get high-level reporting stats: open billing periods, pending timesheets,
    /// and total labor hours this month.
    public func getReportsStats() throws -> ReportsStats {
        let openPeriods = try safeCount(
            sql: "SELECT COUNT(*) FROM billing_periods WHERE status = 'open' AND deleted_at IS NULL"
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

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }
}
