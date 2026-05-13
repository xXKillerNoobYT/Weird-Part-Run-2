import Foundation
import GRDB

/// Dashboard Service — aggregate KPI queries for the main dashboard.
///
/// Reads directly from the local SQLite database via GRDB.
/// All queries are read-only and run synchronously against the local store.
/// No network calls are made — this is a pure local-data service.
///
/// Tables that may not yet exist (e.g., on a freshly bootstrapped database
/// before certain migrations have run) are handled gracefully: queries that
/// hit a missing table return zero counts or empty arrays rather than throwing.
///
/// Ported from: `src/pages/DashboardPage.tsx` aggregate queries
public final class DashboardService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Result Types

    /// Top-level KPI counts displayed as summary cards on the dashboard.
    public struct KPISummary: Sendable {
        /// Total number of active (non-deleted) part types in the catalog.
        public let partTypes: Int
        /// Total physical stock units across all locations.
        public let totalStock: Int
        /// Number of jobs with status = 'active'.
        public let activeJobs: Int
        /// Number of POs in draft, submitted, or acknowledged status.
        public let pendingOrders: Int
        /// Number of parts whose aggregate stock falls below their min_stock_level.
        public let lowStockAlerts: Int

        public init(
            partTypes: Int,
            totalStock: Int,
            activeJobs: Int,
            pendingOrders: Int,
            lowStockAlerts: Int
        ) {
            self.partTypes = partTypes
            self.totalStock = totalStock
            self.activeJobs = activeJobs
            self.pendingOrders = pendingOrders
            self.lowStockAlerts = lowStockAlerts
        }
    }

    /// A single certification that is approaching its expiry date.
    public struct CertificationExpiryAlert: Sendable {
        /// The employee's display name.
        public let displayName: String
        /// The type/category of the certification (e.g., "OSHA 30").
        public let certType: String
        /// The name of the certification.
        public let certName: String
        /// The expiry date as stored in the database (ISO-8601 date string).
        public let expiryDate: String
        /// Number of days remaining until expiry. Zero means expiring today;
        /// negative values indicate already expired (though the query filters these out).
        public let daysRemaining: Int

        public init(
            displayName: String,
            certType: String,
            certName: String,
            expiryDate: String,
            daysRemaining: Int
        ) {
            self.displayName = displayName
            self.certType = certType
            self.certName = certName
            self.expiryDate = expiryDate
            self.daysRemaining = daysRemaining
        }
    }

    /// A single vehicle document (insurance, registration) that is approaching its expiry date.
    public struct VehicleExpiryAlert: Sendable {
        /// The vehicle's display name (e.g., "Truck 1").
        public let vehicleName: String
        /// The vehicle number (unique identifier).
        public let vehicleNumber: String
        /// Which document is expiring: "insurance" or "registration".
        public let expiryType: String
        /// The expiry date as stored in the database (ISO-8601 date string).
        public let expiryDate: String
        /// Number of days remaining until expiry.
        public let daysRemaining: Int

        public init(
            vehicleName: String,
            vehicleNumber: String,
            expiryType: String,
            expiryDate: String,
            daysRemaining: Int
        ) {
            self.vehicleName = vehicleName
            self.vehicleNumber = vehicleNumber
            self.expiryType = expiryType
            self.expiryDate = expiryDate
            self.daysRemaining = daysRemaining
        }
    }

    /// Daily operational report counters — items needing attention today.
    public struct DailyReport: Sendable {
        /// JPOs (Job Part Orders) awaiting office review.
        public let pendingJPOs: Int
        /// Purchase orders awaiting supplier acknowledgement.
        public let pendingPOs: Int
        /// Returns that have been submitted but not yet sorted.
        public let returnsToSort: Int
        /// POs past their expected delivery date that haven't been received or cancelled.
        public let overdueDeliveries: Int
        /// Purchase orders created today.
        public let todayCreatedOrders: Int
        /// Receiving sessions started today.
        public let todayReceivedItems: Int
        /// Returns created today.
        public let todayReturns: Int

        public init(
            pendingJPOs: Int,
            pendingPOs: Int,
            returnsToSort: Int,
            overdueDeliveries: Int,
            todayCreatedOrders: Int,
            todayReceivedItems: Int,
            todayReturns: Int
        ) {
            self.pendingJPOs = pendingJPOs
            self.pendingPOs = pendingPOs
            self.returnsToSort = returnsToSort
            self.overdueDeliveries = overdueDeliveries
            self.todayCreatedOrders = todayCreatedOrders
            self.todayReceivedItems = todayReceivedItems
            self.todayReturns = todayReturns
        }
    }

    // MARK: - KPI Summary

    /// Fetch the four headline KPI counts for the dashboard summary cards.
    ///
    /// - Returns: A `KPISummary` with total parts, active jobs, pending orders,
    ///   and low-stock alert counts.
    public func getKPISummary() throws -> KPISummary {
        let partTypes = try safeCount(
            sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL"
        )

        let totalStock = try safeCount(
            sql: "SELECT COALESCE(SUM(qty), 0) FROM stock WHERE deleted_at IS NULL"
        )

        let activeJobs = try safeCount(
            sql: "SELECT COUNT(*) FROM jobs WHERE status = 'active' AND deleted_at IS NULL"
        )

        let pendingOrders = try safeCount(
            sql: """
                SELECT COUNT(*) FROM purchase_orders
                WHERE status IN ('draft', 'submitted', 'drafting', 'ordered', 'partial')
                  AND deleted_at IS NULL
                """
        )

        // Low stock: parts where the sum of stock qty < min_stock_level.
        // We use a correlated subquery to aggregate stock per part, then compare
        // against the part's configured minimum. Parts with min_stock_level = 0
        // are excluded (they have no configured minimum).
        let lowStockAlerts = try safeCount(
            sql: """
                SELECT COUNT(*) FROM parts p
                WHERE p.deleted_at IS NULL
                  AND p.min_stock_level > 0
                  AND (
                    SELECT COALESCE(SUM(s.qty), 0)
                    FROM stock s
                    WHERE s.part_id = p.id
                      AND s.deleted_at IS NULL
                  ) < p.min_stock_level
                """
        )

        return KPISummary(
            partTypes: partTypes,
            totalStock: totalStock,
            activeJobs: activeJobs,
            pendingOrders: pendingOrders,
            lowStockAlerts: lowStockAlerts
        )
    }

    // MARK: - Certification Expiry Alerts

    /// Fetch certifications that are expiring within the given number of days.
    ///
    /// Returns only certifications that have not yet expired (expiry_date >= today)
    /// and are still active (is_active = 1, deleted_at IS NULL).
    ///
    /// - Parameter withinDays: The lookahead window in days. Defaults to 30.
    /// - Returns: An array of `CertificationExpiryAlert` sorted by days remaining
    ///   (most urgent first).
    public func getCertificationExpiryAlerts(withinDays: Int = 30) throws -> [CertificationExpiryAlert] {
        do {
            return try db.writer.read { dbConnection in
                let rows = try Row.fetchAll(
                    dbConnection,
                    sql: """
                        SELECT
                            u.display_name,
                            c.cert_type,
                            c.cert_name,
                            c.expiry_date,
                            CAST(julianday(c.expiry_date) - julianday(date('now')) AS INTEGER) AS days_remaining
                        FROM certifications c
                        JOIN users u ON u.id = c.user_id
                        WHERE c.expiry_date IS NOT NULL
                          AND c.is_active = 1
                          AND c.deleted_at IS NULL
                          AND u.deleted_at IS NULL
                          AND u.is_active = 1
                          AND date(c.expiry_date) >= date('now')
                          AND date(c.expiry_date) <= date('now', '+' || ? || ' days')
                        ORDER BY days_remaining ASC
                        """,
                    arguments: [withinDays]
                )
                return rows.map { row in
                    CertificationExpiryAlert(
                        displayName: row["display_name"] as String,
                        certType: row["cert_type"] as String,
                        certName: row["cert_name"] as String,
                        expiryDate: row["expiry_date"] as String,
                        daysRemaining: row["days_remaining"] as Int
                    )
                }
            }
        } catch {
            // Table may not exist yet — return empty
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Vehicle Expiry Alerts

    /// Fetch vehicles with insurance or registration expiring within the given number of days.
    ///
    /// Each expiry type (insurance, registration) is checked independently,
    /// so a single vehicle may appear twice if both are expiring soon.
    ///
    /// - Parameter withinDays: The lookahead window in days. Defaults to 30.
    /// - Returns: An array of `VehicleExpiryAlert` sorted by days remaining
    ///   (most urgent first).
    public func getVehicleExpiryAlerts(withinDays: Int = 30) throws -> [VehicleExpiryAlert] {
        do {
            return try db.writer.read { dbConnection in
                // Use UNION ALL to check both expiry columns in a single query.
                let rows = try Row.fetchAll(
                    dbConnection,
                    sql: """
                        SELECT vehicle_name, vehicle_number, expiry_type, expiry_date, days_remaining
                        FROM (
                            SELECT
                                v.vehicle_name,
                                v.vehicle_number,
                                'insurance' AS expiry_type,
                                v.insurance_expiry AS expiry_date,
                                CAST(julianday(v.insurance_expiry) - julianday(date('now')) AS INTEGER) AS days_remaining
                            FROM vehicles v
                            WHERE v.insurance_expiry IS NOT NULL
                              AND v.deleted_at IS NULL
                              AND v.is_active = 1
                              AND date(v.insurance_expiry) >= date('now')
                              AND date(v.insurance_expiry) <= date('now', '+' || ? || ' days')

                            UNION ALL

                            SELECT
                                v.vehicle_name,
                                v.vehicle_number,
                                'registration' AS expiry_type,
                                v.registration_expiry AS expiry_date,
                                CAST(julianday(v.registration_expiry) - julianday(date('now')) AS INTEGER) AS days_remaining
                            FROM vehicles v
                            WHERE v.registration_expiry IS NOT NULL
                              AND v.deleted_at IS NULL
                              AND v.is_active = 1
                              AND date(v.registration_expiry) >= date('now')
                              AND date(v.registration_expiry) <= date('now', '+' || ? || ' days')
                        )
                        ORDER BY days_remaining ASC
                        """,
                    arguments: [withinDays, withinDays]
                )
                return rows.map { row in
                    VehicleExpiryAlert(
                        vehicleName: row["vehicle_name"] as String,
                        vehicleNumber: row["vehicle_number"] as String,
                        expiryType: row["expiry_type"] as String,
                        expiryDate: row["expiry_date"] as String,
                        daysRemaining: row["days_remaining"] as Int
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Daily Report

    /// Fetch the daily operations report — counts of items needing attention today.
    ///
    /// Includes pending JPOs, pending POs, returns to sort, overdue deliveries,
    /// and today's activity counts (orders created, items received, returns filed).
    public func getDailyReport() throws -> DailyReport {
        let pendingJPOs = try safeCount(
            sql: "SELECT COUNT(*) FROM job_parts_orders WHERE status = 'submitted' AND deleted_at IS NULL"
        )

        let pendingPOs = try safeCount(
            sql: "SELECT COUNT(*) FROM purchase_orders WHERE status IN ('draft', 'submitted', 'drafting') AND deleted_at IS NULL"
        )

        let returnsToSort = try safeCount(
            sql: "SELECT COUNT(*) FROM returns WHERE status = 'submitted' AND deleted_at IS NULL"
        )

        let overdueDeliveries = try safeCount(
            sql: """
                SELECT COUNT(*) FROM purchase_orders
                WHERE expected_delivery IS NOT NULL
                  AND date(expected_delivery) < date('now')
                  AND status NOT IN ('received', 'cancelled')
                  AND deleted_at IS NULL
                """
        )

        let todayCreatedOrders = try safeCount(
            sql: """
                SELECT COUNT(*) FROM purchase_orders
                WHERE date(created_at) = date('now')
                  AND deleted_at IS NULL
                """
        )

        let todayReceivedItems = try safeCount(
            sql: """
                SELECT COUNT(*) FROM receiving_sessions
                WHERE date(created_at) = date('now')
                  AND deleted_at IS NULL
                """
        )

        let todayReturns = try safeCount(
            sql: """
                SELECT COUNT(*) FROM returns
                WHERE date(created_at) = date('now')
                  AND deleted_at IS NULL
                """
        )

        return DailyReport(
            pendingJPOs: pendingJPOs,
            pendingPOs: pendingPOs,
            returnsToSort: returnsToSort,
            overdueDeliveries: overdueDeliveries,
            todayCreatedOrders: todayCreatedOrders,
            todayReceivedItems: todayReceivedItems,
            todayReturns: todayReturns
        )
    }

    // MARK: - Convenience: Full Dashboard Load

    /// Fetch all dashboard data in a single call.
    ///
    /// Combines KPI summary, certification alerts, vehicle alerts, and the daily
    /// report into one struct. This is the recommended entry point for a
    /// dashboard screen that needs everything at once.
    ///
    /// - Parameter alertDays: Lookahead window for expiry alerts. Defaults to 30.
    /// - Returns: A `DashboardData` struct containing all dashboard sections.
    public func getDashboardData(alertDays: Int = 30) throws -> DashboardData {
        let kpi = try getKPISummary()
        let certAlerts = try getCertificationExpiryAlerts(withinDays: alertDays)
        let vehicleAlerts = try getVehicleExpiryAlerts(withinDays: alertDays)
        let daily = try getDailyReport()

        return DashboardData(
            kpiSummary: kpi,
            certificationAlerts: certAlerts,
            vehicleAlerts: vehicleAlerts,
            dailyReport: daily
        )
    }

    /// Combined result of all dashboard queries, returned by `getDashboardData`.
    public struct DashboardData: Sendable {
        public let kpiSummary: KPISummary
        public let certificationAlerts: [CertificationExpiryAlert]
        public let vehicleAlerts: [VehicleExpiryAlert]
        public let dailyReport: DailyReport

        public init(
            kpiSummary: KPISummary,
            certificationAlerts: [CertificationExpiryAlert],
            vehicleAlerts: [VehicleExpiryAlert],
            dailyReport: DailyReport
        ) {
            self.kpiSummary = kpiSummary
            self.certificationAlerts = certificationAlerts
            self.vehicleAlerts = vehicleAlerts
            self.dailyReport = dailyReport
        }
    }

    // MARK: - Expected Deliveries

    /// A PO expected to be delivered soon (within +/- 7 days of today).
    public struct ExpectedDeliveryRow: Sendable {
        public let id: Int64
        public let poNumber: String
        public let supplierName: String
        public let expectedDate: String
        public let lineCount: Int
        public let isOverdue: Bool

        public init(id: Int64, poNumber: String, supplierName: String,
                    expectedDate: String, lineCount: Int, isOverdue: Bool) {
            self.id = id
            self.poNumber = poNumber
            self.supplierName = supplierName
            self.expectedDate = expectedDate
            self.lineCount = lineCount
            self.isOverdue = isOverdue
        }
    }

    /// Fetch expected deliveries within +/- 7 days of today.
    public func getExpectedDeliveries(limit: Int = 20) throws -> [ExpectedDeliveryRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT po.id, po.po_number, po.expected_delivery,
                           COALESCE(s.name, 'Unknown') AS supplier_name,
                           (SELECT COUNT(*) FROM po_line_items pl WHERE pl.po_id = po.id AND pl.deleted_at IS NULL) AS line_count,
                           CASE WHEN date(po.expected_delivery) < date('now') THEN 1 ELSE 0 END AS is_overdue
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    WHERE po.expected_delivery IS NOT NULL
                      AND po.status NOT IN ('received', 'cancelled')
                      AND po.deleted_at IS NULL
                      AND date(po.expected_delivery) BETWEEN date('now', '-7 days') AND date('now', '+7 days')
                    ORDER BY po.expected_delivery ASC
                    LIMIT ?
                    """, arguments: [limit])
                return rows.map { row in
                    ExpectedDeliveryRow(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown",
                        expectedDate: String((row["expected_delivery"] as String? ?? "").prefix(10)),
                        lineCount: row["line_count"] ?? 0,
                        isOverdue: (row["is_overdue"] as Int? ?? 0) == 1
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Budget Alerts

    /// A job whose spending has reached >= 80% of its budget limit.
    public struct JobBudgetAlertRow: Sendable {
        public let id: Int64
        public let jobName: String
        public let currentSpend: Double
        public let budgetLimit: Double
        public let pctUsed: Double

        public init(id: Int64, jobName: String, currentSpend: Double,
                    budgetLimit: Double, pctUsed: Double) {
            self.id = id
            self.jobName = jobName
            self.currentSpend = currentSpend
            self.budgetLimit = budgetLimit
            self.pctUsed = pctUsed
        }
    }

    /// Fetch active jobs where spending >= 80% of budget.
    public func getBudgetAlerts(limit: Int = 10) throws -> [JobBudgetAlertRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT * FROM (
                        SELECT j.id, j.job_name, j.budget_limit AS budget,
                               COALESCE(
                                 (SELECT SUM(le.regular_hours * COALESCE(u.pay_rate, 0))
                                  FROM labor_entries le
                                  LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                                  WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0
                               ) +
                               COALESCE(
                                 (SELECT SUM(po.total_cost)
                                  FROM purchase_orders po
                                  JOIN po_jpo_links pjl ON pjl.po_id = po.id
                                  JOIN job_parts_orders jpo ON jpo.id = pjl.jpo_id
                                  WHERE jpo.job_id = j.id
                                    AND po.status NOT IN ('cancelled')
                                    AND po.deleted_at IS NULL), 0
                               ) AS current_spend
                        FROM jobs j
                        WHERE j.budget_limit IS NOT NULL AND j.budget_limit > 0
                          AND j.status = 'active'
                          AND j.deleted_at IS NULL
                    ) sub
                    WHERE current_spend >= budget * 0.8
                    ORDER BY (current_spend * 1.0 / budget) DESC
                    LIMIT ?
                    """, arguments: [limit])
                return rows.map { row in
                    let budget: Double = row["budget"] ?? 0
                    let spend: Double = row["current_spend"] ?? 0
                    return JobBudgetAlertRow(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        currentSpend: spend,
                        budgetLimit: budget,
                        pctUsed: budget > 0 ? (spend / budget) * 100 : 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - My Hours Today

    /// Summary of a user's hours worked today.
    public struct MyHoursToday: Sendable {
        public let totalHours: Double
        public let clockInTime: String?
        public let currentJobName: String?
        public let breakMinutes: Int
        public let jobBreakdown: [JobTimeBreakdown]

        public init(totalHours: Double, clockInTime: String?, currentJobName: String?,
                    breakMinutes: Int, jobBreakdown: [JobTimeBreakdown]) {
            self.totalHours = totalHours
            self.clockInTime = clockInTime
            self.currentJobName = currentJobName
            self.breakMinutes = breakMinutes
            self.jobBreakdown = jobBreakdown
        }
    }

    /// Per-job time breakdown for the current day.
    public struct JobTimeBreakdown: Sendable {
        public let jobName: String
        public let hours: Double

        public init(jobName: String, hours: Double) {
            self.jobName = jobName
            self.hours = hours
        }
    }

    /// Fetch hours worked today for a specific user, including active clock session.
    public func getMyHoursToday(userId: Int64) throws -> MyHoursToday {
        do {
            return try db.writer.read { conn in
                // Total completed hours today
                var totalHours = try Double.fetchOne(conn, sql: """
                    SELECT COALESCE(SUM(regular_hours + overtime_hours), 0)
                    FROM labor_entries
                    WHERE user_id = ? AND date(clock_in) = date('now') AND deleted_at IS NULL
                    """, arguments: [userId]) ?? 0

                // Active clock-in session
                var clockInTime: String?
                var currentJobName: String?

                if let activeRow = try Row.fetchOne(conn, sql: """
                    SELECT le.clock_in, COALESCE(j.job_name, 'Shop / Warehouse') AS job_name
                    FROM labor_entries le
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE le.user_id = ? AND le.clock_out IS NULL AND le.deleted_at IS NULL
                    ORDER BY le.clock_in DESC LIMIT 1
                    """, arguments: [userId]) {
                    let rawClockIn: String = activeRow["clock_in"] ?? ""
                    if rawClockIn.count >= 16 {
                        clockInTime = String(rawClockIn.suffix(from: rawClockIn.index(rawClockIn.startIndex, offsetBy: 11)).prefix(5))
                    } else {
                        clockInTime = rawClockIn
                    }
                    currentJobName = activeRow["job_name"]

                    // Add active session elapsed time
                    let activeHours = try Double.fetchOne(conn, sql: """
                        SELECT (julianday('now') - julianday(clock_in)) * 24
                        FROM labor_entries
                        WHERE user_id = ? AND clock_out IS NULL AND deleted_at IS NULL
                        ORDER BY clock_in DESC LIMIT 1
                        """, arguments: [userId]) ?? 0
                    totalHours += max(0, activeHours)
                }

                // Job breakdown
                let breakdownRows = try Row.fetchAll(conn, sql: """
                    SELECT COALESCE(j.job_name, 'Shop / Warehouse') AS job_name,
                           SUM(
                             CASE WHEN le.clock_out IS NOT NULL THEN le.regular_hours + le.overtime_hours
                                  ELSE (julianday('now') - julianday(le.clock_in)) * 24
                             END
                           ) AS total_hours
                    FROM labor_entries le
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE le.user_id = ? AND date(le.clock_in) = date('now') AND le.deleted_at IS NULL
                    GROUP BY le.job_id
                    ORDER BY total_hours DESC
                    """, arguments: [userId])
                let jobBreakdown = breakdownRows.map { row in
                    JobTimeBreakdown(
                        jobName: row["job_name"] ?? "Shop / Warehouse",
                        hours: max(0, row["total_hours"] ?? 0)
                    )
                }

                // Break minutes (gaps between consecutive entries)
                let breakMinutes = try Int.fetchOne(conn, sql: """
                    SELECT COALESCE(SUM(gap_minutes), 0) FROM (
                        SELECT CAST((julianday(le2.clock_in) - julianday(le1.clock_out)) * 1440 AS INTEGER) AS gap_minutes
                        FROM labor_entries le1
                        JOIN labor_entries le2
                            ON le2.user_id = le1.user_id
                            AND le2.clock_in > le1.clock_out
                            AND le2.deleted_at IS NULL
                            AND date(le2.clock_in) = date('now')
                        WHERE le1.user_id = ? AND le1.clock_out IS NOT NULL AND le1.deleted_at IS NULL
                            AND date(le1.clock_in) = date('now')
                            AND NOT EXISTS (
                                SELECT 1 FROM labor_entries le3
                                WHERE le3.user_id = le1.user_id
                                    AND le3.clock_in > le1.clock_out
                                    AND le3.clock_in < le2.clock_in
                                    AND le3.deleted_at IS NULL
                                    AND date(le3.clock_in) = date('now')
                            )
                    )
                    """, arguments: [userId]) ?? 0

                return MyHoursToday(
                    totalHours: totalHours,
                    clockInTime: clockInTime,
                    currentJobName: currentJobName,
                    breakMinutes: max(0, breakMinutes),
                    jobBreakdown: jobBreakdown
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return MyHoursToday(totalHours: 0, clockInTime: nil, currentJobName: nil, breakMinutes: 0, jobBreakdown: [])
            }
            throw error
        }
    }

    // MARK: - Team Clocked In

    /// A team member who is currently clocked in.
    public struct TeamMemberClockStatus: Sendable {
        public let id: Int64
        public let displayName: String
        public let jobName: String
        public let clockInTime: String
        public let clockInRaw: String

        public init(id: Int64, displayName: String, jobName: String,
                    clockInTime: String, clockInRaw: String) {
            self.id = id
            self.displayName = displayName
            self.jobName = jobName
            self.clockInTime = clockInTime
            self.clockInRaw = clockInRaw
        }
    }

    /// Fetch all team members currently clocked in.
    public func getTeamClockedIn() throws -> [TeamMemberClockStatus] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT u.id, u.display_name,
                           COALESCE(j.job_name, 'Shop / Warehouse') AS job_name,
                           le.clock_in
                    FROM labor_entries le
                    JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE le.clock_out IS NULL AND le.deleted_at IS NULL AND u.deleted_at IS NULL
                    ORDER BY le.clock_in ASC
                    """)
                return rows.map { row in
                    let rawClockIn: String = row["clock_in"] ?? ""
                    let timeText: String = rawClockIn.count >= 16
                        ? String(rawClockIn.suffix(from: rawClockIn.index(rawClockIn.startIndex, offsetBy: 11)).prefix(5))
                        : rawClockIn
                    return TeamMemberClockStatus(
                        id: row["id"] ?? 0,
                        displayName: row["display_name"] ?? "",
                        jobName: row["job_name"] ?? "",
                        clockInTime: timeText,
                        clockInRaw: rawClockIn
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Clock Status (Current User)

    /// Current clock-in status for a user.
    public struct ClockStatus: Sendable {
        public let isClockedIn: Bool
        public let jobName: String?
        public let jobNumber: String?
        public let clockInTimestamp: String?

        public init(isClockedIn: Bool, jobName: String?, jobNumber: String?, clockInTimestamp: String?) {
            self.isClockedIn = isClockedIn
            self.jobName = jobName
            self.jobNumber = jobNumber
            self.clockInTimestamp = clockInTimestamp
        }
    }

    /// Fetch clock status for a specific user.
    public func getClockStatus(userId: Int64) throws -> ClockStatus {
        do {
            return try db.writer.read { conn in
                if let clockRow = try Row.fetchOne(conn, sql: """
                    SELECT le.clock_in, j.job_name, j.job_number
                    FROM labor_entries le
                    LEFT JOIN jobs j ON j.id = le.job_id AND j.deleted_at IS NULL
                    WHERE le.user_id = ? AND le.clock_out IS NULL AND le.deleted_at IS NULL
                    ORDER BY le.clock_in DESC LIMIT 1
                    """, arguments: [userId]) {
                    return ClockStatus(
                        isClockedIn: true,
                        jobName: clockRow["job_name"] as String?,
                        jobNumber: clockRow["job_number"] as String?,
                        clockInTimestamp: clockRow["clock_in"] as String?
                    )
                }
                return ClockStatus(isClockedIn: false, jobName: nil, jobNumber: nil, clockInTimestamp: nil)
            }
        } catch {
            if isTableNotFoundError(error) {
                return ClockStatus(isClockedIn: false, jobName: nil, jobNumber: nil, clockInTimestamp: nil)
            }
            throw error
        }
    }

    // MARK: - Chart Data: Labor Hours (7 Days)

    /// Labor hours data for a single day.
    public struct LaborDayRow: Sendable {
        public let dateString: String
        public let regularHours: Double
        public let overtimeHours: Double

        public init(dateString: String, regularHours: Double, overtimeHours: Double) {
            self.dateString = dateString
            self.regularHours = regularHours
            self.overtimeHours = overtimeHours
        }
    }

    /// Fetch labor hours for the past 7 days.
    public func getLaborChartData() throws -> [LaborDayRow] {
        do {
            return try db.writer.read { conn in
                let isoFormatter = DateFormatter()
                isoFormatter.dateFormat = "yyyy-MM-dd"

                var results: [LaborDayRow] = []
                for i in (0..<7).reversed() {
                    let date = Calendar.current.date(byAdding: .day, value: -i, to: Date()) ?? Date()
                    let dateStr = isoFormatter.string(from: date)
                    let regular = try Double.fetchOne(conn, sql: """
                        SELECT COALESCE(SUM(regular_hours), 0) FROM labor_entries
                        WHERE date(clock_in) = ? AND deleted_at IS NULL
                        """, arguments: [dateStr]) ?? 0
                    let overtime = try Double.fetchOne(conn, sql: """
                        SELECT COALESCE(SUM(overtime_hours), 0) FROM labor_entries
                        WHERE date(clock_in) = ? AND deleted_at IS NULL
                        """, arguments: [dateStr]) ?? 0
                    results.append(LaborDayRow(dateString: dateStr, regularHours: regular, overtimeHours: overtime))
                }
                return results
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Chart Data: Stock Levels

    /// Stock level for a part compared to its min level.
    public struct StockLevelRow: Sendable {
        public let partName: String
        public let quantity: Int
        public let minLevel: Int

        public init(partName: String, quantity: Int, minLevel: Int) {
            self.partName = partName
            self.quantity = quantity
            self.minLevel = minLevel
        }
    }

    /// Fetch top parts by stock ratio (lowest stock ratio first) for chart display.
    public func getStockChartData(limit: Int = 8) throws -> [StockLevelRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT p.name,
                           COALESCE((SELECT SUM(s.qty) FROM stock s
                                     WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS qty,
                           COALESCE(p.min_stock_level, 0) AS min_level
                    FROM parts p
                    WHERE p.deleted_at IS NULL AND p.min_stock_level > 0
                    ORDER BY (COALESCE((SELECT SUM(s.qty) FROM stock s
                              WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) * 1.0
                              / NULLIF(p.min_stock_level, 0)) ASC
                    LIMIT ?
                    """, arguments: [limit])
                return rows.map { row in
                    StockLevelRow(
                        partName: String((row["name"] as String? ?? "").prefix(20)),
                        quantity: row["qty"] ?? 0,
                        minLevel: row["min_level"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Chart Data: Spending Breakdown

    /// Spending for a category (labor, parts, fuel).
    public struct SpendingBreakdownRow: Sendable {
        public let name: String
        public let amount: Double

        public init(name: String, amount: Double) {
            self.name = name
            self.amount = amount
        }
    }

    /// Fetch spending breakdown across labor, parts, and fuel.
    public func getSpendingChartData() throws -> [SpendingBreakdownRow] {
        do {
            return try db.writer.read { conn in
                let laborSpend = try Double.fetchOne(conn, sql: """
                    SELECT COALESCE(SUM(le.regular_hours * COALESCE(u.pay_rate, 0)), 0)
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                    WHERE le.deleted_at IS NULL
                    """) ?? 0
                let partsSpend = try Double.fetchOne(conn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM purchase_orders
                    WHERE status NOT IN ('cancelled') AND deleted_at IS NULL
                    """) ?? 0
                let fuelSpend = try Double.fetchOne(conn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM fuel_logs
                    WHERE deleted_at IS NULL
                    """) ?? 0

                var results: [SpendingBreakdownRow] = []
                if laborSpend > 0 { results.append(SpendingBreakdownRow(name: "Labor", amount: laborSpend)) }
                if partsSpend > 0 { results.append(SpendingBreakdownRow(name: "Parts", amount: partsSpend)) }
                if fuelSpend > 0 { results.append(SpendingBreakdownRow(name: "Fuel", amount: fuelSpend)) }
                return results
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Active Jobs (for picker)

    /// Minimal job info for a picker list.
    public struct ActiveJobRow: Sendable {
        public let id: Int64
        public let jobName: String

        public init(id: Int64, jobName: String) {
            self.id = id
            self.jobName = jobName
        }
    }

    /// Fetch active job names for a dropdown/picker.
    public func getActiveJobsForPicker() throws -> [ActiveJobRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT id, job_name FROM jobs
                    WHERE status = 'active' AND deleted_at IS NULL
                    ORDER BY job_name ASC
                    """)
                return rows.map { row in
                    ActiveJobRow(id: row["id"] ?? 0, jobName: row["job_name"] ?? "")
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - KPI Detail: Categories with Counts

    /// A category with its part count.
    public struct CategoryCountRow: Sendable, Hashable {
        public let id: Int64
        public let name: String
        public let count: Int

        public init(id: Int64, name: String, count: Int) {
            self.id = id
            self.name = name
            self.count = count
        }
    }

    /// Fetch categories with part counts.
    public func getCategoriesWithCounts() throws -> [CategoryCountRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT pc.id, pc.name,
                           COUNT(p.id) AS part_count
                    FROM part_categories pc
                    LEFT JOIN parts p ON p.category_id = pc.id AND p.deleted_at IS NULL
                    WHERE pc.deleted_at IS NULL
                    GROUP BY pc.id
                    ORDER BY part_count DESC, pc.name
                    """)
                return rows.map { row in
                    CategoryCountRow(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "Uncategorized",
                        count: row["part_count"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - KPI Detail: Parts in Category

    /// A part with stock info for a category drill-down.
    public struct PartInCategoryRow: Sendable {
        public let id: Int64
        public let name: String
        public let code: String?
        public let totalStock: Int

        public init(id: Int64, name: String, code: String?, totalStock: Int) {
            self.id = id
            self.name = name
            self.code = code
            self.totalStock = totalStock
        }
    }

    /// Fetch parts in a specific category with stock counts.
    public func getPartsInCategory(categoryId: Int64) throws -> [PartInCategoryRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT p.id, p.name, p.code,
                           COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS total_stock
                    FROM parts p
                    WHERE p.category_id = ? AND p.deleted_at IS NULL
                    ORDER BY p.name
                    """, arguments: [categoryId])
                return rows.map { row in
                    PartInCategoryRow(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        code: row["code"] as String?,
                        totalStock: row["total_stock"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - KPI Detail: Stock by Location Type

    /// Stock grouped by location type.
    public struct LocationGroupRow: Sendable, Hashable {
        public let locationType: String
        public let locationCount: Int
        public let totalQty: Int

        public init(locationType: String, locationCount: Int, totalQty: Int) {
            self.locationType = locationType
            self.locationCount = locationCount
            self.totalQty = totalQty
        }
    }

    /// Fetch stock grouped by location type.
    public func getStockByLocationType() throws -> [LocationGroupRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT location_type,
                           COUNT(DISTINCT location_id) AS loc_count,
                           SUM(qty) AS total_qty
                    FROM stock
                    WHERE deleted_at IS NULL AND qty > 0
                    GROUP BY location_type
                    ORDER BY total_qty DESC
                    """)
                return rows.map { row in
                    LocationGroupRow(
                        locationType: row["location_type"] ?? "unknown",
                        locationCount: row["loc_count"] ?? 0,
                        totalQty: row["total_qty"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - KPI Detail: Stock at Location Type

    /// A stock item at a specific location.
    public struct LocationStockRow: Sendable {
        public let partId: Int64
        public let partName: String
        public let partCode: String?
        public let locationId: Int64
        public let qty: Int
        public let locationType: String

        public init(partId: Int64, partName: String, partCode: String?,
                    locationId: Int64, qty: Int, locationType: String) {
            self.partId = partId
            self.partName = partName
            self.partCode = partCode
            self.locationId = locationId
            self.qty = qty
            self.locationType = locationType
        }
    }

    /// Fetch stock items at a specific location type.
    public func getStockAtLocationType(_ locationType: String) throws -> [LocationStockRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT s.location_id, s.part_id, s.qty,
                           p.name AS part_name, p.code AS part_code
                    FROM stock s
                    LEFT JOIN parts p ON p.id = s.part_id AND p.deleted_at IS NULL
                    WHERE s.location_type = ? AND s.qty > 0 AND s.deleted_at IS NULL
                    ORDER BY p.name, s.location_id
                    """, arguments: [locationType])
                return rows.map { row in
                    LocationStockRow(
                        partId: row["part_id"] ?? 0,
                        partName: row["part_name"] ?? "Unknown",
                        partCode: row["part_code"] as String?,
                        locationId: row["location_id"] ?? 0,
                        qty: row["qty"] ?? 0,
                        locationType: locationType
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - KPI Detail: Job Detail

    /// Detailed info about a single job for the KPI drill-down.
    public struct JobKPIDetail: Sendable {
        public let jobName: String
        public let status: String
        public let customerName: String?
        public let startDate: String?
        public let dueDate: String?
        public let budgetLimit: Double?
        public let teamCount: Int
        public let laborHours: Double
        public let currentSpend: Double

        public init(jobName: String, status: String, customerName: String?,
                    startDate: String?, dueDate: String?, budgetLimit: Double?,
                    teamCount: Int, laborHours: Double, currentSpend: Double) {
            self.jobName = jobName
            self.status = status
            self.customerName = customerName
            self.startDate = startDate
            self.dueDate = dueDate
            self.budgetLimit = budgetLimit
            self.teamCount = teamCount
            self.laborHours = laborHours
            self.currentSpend = currentSpend
        }
    }

    /// Fetch detailed KPI information about a single job.
    public func getJobKPIDetail(jobId: Int64) throws -> JobKPIDetail? {
        do {
            return try db.writer.read { conn in
                guard let row = try Row.fetchOne(conn, sql: """
                    SELECT j.job_name, j.status, j.customer_name,
                           j.start_date, j.due_date, j.budget_limit,
                           COALESCE((SELECT COUNT(*) FROM job_team_members jtm
                                     WHERE jtm.job_id = j.id AND jtm.deleted_at IS NULL), 0) AS team_count,
                           COALESCE((SELECT SUM(le.regular_hours + le.overtime_hours) FROM labor_entries le
                                     WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0) AS labor_hours,
                           COALESCE(
                             (SELECT SUM(le.regular_hours * COALESCE(u.pay_rate, 0))
                              FROM labor_entries le LEFT JOIN users u ON u.id = le.user_id AND u.deleted_at IS NULL
                              WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0
                           ) +
                           COALESCE(
                             (SELECT SUM(po.total_cost) FROM purchase_orders po
                              JOIN po_jpo_links pjl ON pjl.po_id = po.id
                              JOIN job_parts_orders jpo ON jpo.id = pjl.jpo_id
                              WHERE jpo.job_id = j.id AND po.status NOT IN ('cancelled') AND po.deleted_at IS NULL), 0
                           ) AS current_spend
                    FROM jobs j
                    WHERE j.id = ? AND j.deleted_at IS NULL
                    """, arguments: [jobId]) else { return nil }
                return JobKPIDetail(
                    jobName: row["job_name"] ?? "",
                    status: row["status"] ?? "",
                    customerName: row["customer_name"] as String?,
                    startDate: row["start_date"] as String?,
                    dueDate: row["due_date"] as String?,
                    budgetLimit: row["budget_limit"] as Double?,
                    teamCount: row["team_count"] ?? 0,
                    laborHours: row["labor_hours"] ?? 0,
                    currentSpend: row["current_spend"] ?? 0
                )
            }
        } catch {
            if isTableNotFoundError(error) { return nil }
            throw error
        }
    }

    // MARK: - KPI Detail: PO Detail

    /// Detailed info about a single purchase order.
    public struct POKPIDetail: Sendable {
        public let poNumber: String
        public let supplierName: String
        public let supplierEmail: String?
        public let supplierPhone: String?
        public let status: String
        public let totalCost: Double?
        public let orderDate: String?
        public let expectedDelivery: String?

        public init(poNumber: String, supplierName: String, supplierEmail: String?,
                    supplierPhone: String?, status: String, totalCost: Double?,
                    orderDate: String?, expectedDelivery: String?) {
            self.poNumber = poNumber
            self.supplierName = supplierName
            self.supplierEmail = supplierEmail
            self.supplierPhone = supplierPhone
            self.status = status
            self.totalCost = totalCost
            self.orderDate = orderDate
            self.expectedDelivery = expectedDelivery
        }
    }

    /// Line item summary for a PO.
    public struct POLineItemRow: Sendable {
        public let partName: String
        public let partCode: String?
        public let qty: Int

        public init(partName: String, partCode: String?, qty: Int) {
            self.partName = partName
            self.partCode = partCode
            self.qty = qty
        }
    }

    /// Fetch PO detail with line items.
    public func getPOKPIDetail(poId: Int64) throws -> (detail: POKPIDetail?, lineItems: [POLineItemRow]) {
        do {
            return try db.writer.read { conn in
                let row = try Row.fetchOne(conn, sql: """
                    SELECT po.po_number, po.status, po.total_cost, po.order_date, po.expected_delivery,
                           COALESCE(s.name, 'Unknown') AS supplier_name,
                           s.email AS supplier_email, s.phone AS supplier_phone
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    WHERE po.id = ? AND po.deleted_at IS NULL
                    """, arguments: [poId])

                let detail = row.map { r in
                    POKPIDetail(
                        poNumber: r["po_number"] ?? "",
                        supplierName: r["supplier_name"] ?? "Unknown",
                        supplierEmail: r["supplier_email"] as String?,
                        supplierPhone: r["supplier_phone"] as String?,
                        status: r["status"] ?? "",
                        totalCost: r["total_cost"] as Double?,
                        orderDate: r["order_date"] as String?,
                        expectedDelivery: r["expected_delivery"] as String?
                    )
                }

                let lineRows = try Row.fetchAll(conn, sql: """
                    SELECT pl.qty_ordered, p.name AS part_name, p.code AS part_code
                    FROM po_line_items pl
                    LEFT JOIN parts p ON p.id = pl.part_id AND p.deleted_at IS NULL
                    WHERE pl.po_id = ? AND pl.deleted_at IS NULL
                    ORDER BY p.name
                    """, arguments: [poId])

                let lines = lineRows.map { r in
                    POLineItemRow(
                        partName: r["part_name"] ?? "Unknown",
                        partCode: r["part_code"] as String?,
                        qty: r["qty_ordered"] ?? 0
                    )
                }

                return (detail, lines)
            }
        } catch {
            if isTableNotFoundError(error) { return (nil, []) }
            throw error
        }
    }

    // MARK: - KPI Detail: Low Stock Parts

    /// A part that is below its minimum stock level.
    public struct LowStockPartRow: Sendable, Hashable {
        public let id: Int64
        public let name: String
        public let code: String?
        public let currentQty: Int
        public let minLevel: Int

        public init(id: Int64, name: String, code: String?, currentQty: Int, minLevel: Int) {
            self.id = id
            self.name = name
            self.code = code
            self.currentQty = currentQty
            self.minLevel = minLevel
        }
    }

    /// Fetch parts below their minimum stock level.
    public func getLowStockParts() throws -> [LowStockPartRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT p.id, p.name, p.code, p.min_stock_level,
                           COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS current_qty
                    FROM parts p
                    WHERE p.deleted_at IS NULL
                      AND p.min_stock_level > 0
                      AND COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) < p.min_stock_level
                    ORDER BY (COALESCE((SELECT SUM(s.qty) FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) * 1.0
                              / NULLIF(p.min_stock_level, 0)) ASC
                    """)
                return rows.map { row in
                    LowStockPartRow(
                        id: row["id"] ?? 0,
                        name: row["name"] ?? "",
                        code: row["code"] as String?,
                        currentQty: row["current_qty"] ?? 0,
                        minLevel: row["min_stock_level"] ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - KPI Detail: Low Stock Part Detail

    /// Fetch stock locations for a specific part.
    public func getStockLocationsForPart(partId: Int64) throws -> [LocationStockRow] {
        do {
            return try db.writer.read { conn in
                let rows = try Row.fetchAll(conn, sql: """
                    SELECT s.location_type, s.location_id, s.qty
                    FROM stock s
                    WHERE s.part_id = ? AND s.qty > 0 AND s.deleted_at IS NULL
                    ORDER BY s.location_type
                    """, arguments: [partId])
                return rows.map { row in
                    LocationStockRow(
                        partId: partId,
                        partName: "",
                        partCode: nil,
                        locationId: row["location_id"] ?? 0,
                        qty: row["qty"] ?? 0,
                        locationType: row["location_type"] ?? "warehouse"
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Fetch the last movement date and reorder point for a part.
    public func getPartMovementInfo(partId: Int64) throws -> (lastMovement: String?, reorderPoint: Int?) {
        do {
            return try db.writer.read { conn in
                let lastMove = try String.fetchOne(conn, sql: """
                    SELECT created_at FROM stock_movements
                    WHERE part_id = ? AND deleted_at IS NULL
                    ORDER BY created_at DESC LIMIT 1
                    """, arguments: [partId])
                let rp = try Int.fetchOne(conn, sql: """
                    SELECT reorder_point FROM parts WHERE id = ?
                    """, arguments: [partId])
                return (lastMove, rp)
            }
        } catch {
            if isTableNotFoundError(error) { return (nil, nil) }
            throw error
        }
    }

    // MARK: - Submit Daily Report

    /// Save a daily report as a notebook entry.
    /// Creates a "daily-report" notebook for the user if none exists,
    /// then adds an entry with the report content.
    @discardableResult
    public func submitDailyReport(
        userId: Int64,
        accomplishments: String,
        issues: String,
        tomorrowNotes: String
    ) throws -> Int64 {
        try db.writer.write { conn in
            // Find or create a "Daily Reports" notebook for this user
            var notebookId = try Int64.fetchOne(conn, sql: """
                SELECT id FROM notebooks
                WHERE notebook_type = 'daily-report' AND created_by = ? AND deleted_at IS NULL
                ORDER BY created_at DESC LIMIT 1
                """, arguments: [userId])

            if notebookId == nil {
                try conn.execute(sql: """
                    INSERT INTO notebooks (title, notebook_type, created_by, status, created_at, updated_at)
                    VALUES ('Daily Reports', 'daily-report', ?, 'active', datetime('now'), datetime('now'))
                    """, arguments: [userId])
                notebookId = conn.lastInsertedRowID
            }

            guard let nbId = notebookId else { return 0 }

            // Get or create section
            var sectionId = try Int64.fetchOne(conn, sql: """
                SELECT id FROM notebook_sections WHERE notebook_id = ? AND deleted_at IS NULL LIMIT 1
                """, arguments: [nbId])
            if sectionId == nil {
                try conn.execute(sql: """
                    INSERT INTO notebook_sections (notebook_id, name, sort_order, created_at)
                    VALUES (?, 'Reports', 0, datetime('now'))
                    """, arguments: [nbId])
                sectionId = conn.lastInsertedRowID
            }

            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = isoFormatter.string(from: Date())

            let content = """
                ## Daily Report — \(dateStr)

                ### Accomplishments
                \(accomplishments)

                ### Issues
                \(issues.isEmpty ? "None reported" : issues)

                ### Notes for Tomorrow
                \(tomorrowNotes.isEmpty ? "None" : tomorrowNotes)
                """

            try conn.execute(sql: """
                INSERT INTO notebook_entries
                (section_id, title, content, entry_type, created_by, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, 'daily-report', ?, 0, datetime('now'), datetime('now'))
                """, arguments: [sectionId, "Report \(dateStr)", content, userId])

            // Update notebook timestamp
            try conn.execute(sql: """
                UPDATE notebooks SET updated_at = datetime('now') WHERE id = ?
                """, arguments: [nbId])

            return conn.lastInsertedRowID
        }
    }

    // MARK: - Report Problem

    /// Save a problem report as a notebook entry tagged with 'problem' entry type.
    @discardableResult
    public func reportProblem(
        userId: Int64,
        jobId: Int64?,
        description: String
    ) throws -> Int64 {
        try db.writer.write { conn in
            // Find or create a "Problem Reports" notebook
            var notebookId = try Int64.fetchOne(conn, sql: """
                SELECT id FROM notebooks
                WHERE notebook_type = 'problem-report' AND deleted_at IS NULL
                ORDER BY created_at DESC LIMIT 1
                """)

            if notebookId == nil {
                try conn.execute(sql: """
                    INSERT INTO notebooks (title, notebook_type, job_id, created_by, status, created_at, updated_at)
                    VALUES ('Problem Reports', 'problem-report', ?, ?, 'active', datetime('now'), datetime('now'))
                    """, arguments: [jobId, userId])
                notebookId = conn.lastInsertedRowID
            }

            guard let nbId = notebookId else { return 0 }

            // Get or create section
            var sectionId = try Int64.fetchOne(conn, sql: """
                SELECT id FROM notebook_sections WHERE notebook_id = ? AND deleted_at IS NULL LIMIT 1
                """, arguments: [nbId])
            if sectionId == nil {
                try conn.execute(sql: """
                    INSERT INTO notebook_sections (notebook_id, name, sort_order, created_at)
                    VALUES (?, 'Problems', 0, datetime('now'))
                    """, arguments: [nbId])
                sectionId = conn.lastInsertedRowID
            }

            let isoFormatter = DateFormatter()
            isoFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            let dateStr = isoFormatter.string(from: Date())

            // Fetch job name if available
            var jobName = "General"
            if let jId = jobId {
                jobName = try String.fetchOne(conn, sql: "SELECT job_name FROM jobs WHERE id = ?", arguments: [jId]) ?? "General"
            }

            try conn.execute(sql: """
                INSERT INTO notebook_entries
                (section_id, title, content, entry_type, created_by, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, 'problem', ?, 0, datetime('now'), datetime('now'))
                """, arguments: [sectionId, "Problem — \(jobName) — \(dateStr)", description, userId])

            // Update notebook timestamp
            try conn.execute(sql: """
                UPDATE notebooks SET updated_at = datetime('now') WHERE id = ?
                """, arguments: [nbId])

            return conn.lastInsertedRowID
        }
    }

    // MARK: - Office Dashboard

    /// Briefing data generated from overnight and current-day activity.
    public struct OfficeBriefing: Sendable {
        public let summary: String
        public let generatedAt: Date
        public let highlights: [String]
        public let alertCount: Int

        public init(summary: String, generatedAt: Date, highlights: [String], alertCount: Int) {
            self.summary = summary
            self.generatedAt = generatedAt
            self.highlights = highlights
            self.alertCount = alertCount
        }
    }

    /// An actionable item requiring manager attention, with urgency-based priority.
    public struct AttentionItem: Identifiable, Sendable {
        public let id: Int64
        public let title: String
        public let subtitle: String
        public let itemType: String
        public let createdAt: Date
        public let priority: AttentionPriority

        public init(id: Int64, title: String, subtitle: String, itemType: String,
                    createdAt: Date, priority: AttentionPriority) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.itemType = itemType
            self.createdAt = createdAt
            self.priority = priority
        }
    }

    /// Priority levels for attention items, based on age since creation.
    public enum AttentionPriority: Int, Sendable, Comparable {
        case low = 1       // green — just created
        case medium = 2    // yellow — same day
        case high = 3      // orange — within 24hr of deadline
        case overdue = 4   // red — past 4 days

        public static func < (lhs: AttentionPriority, rhs: AttentionPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Determine priority from age in seconds since creation.
        public static func from(age: TimeInterval) -> AttentionPriority {
            let days = age / 86400
            if days > 4 { return .overdue }
            if days > 1 { return .high }
            if days > 0 { return .medium }
            return .low
        }
    }

    /// A single scheduled item for today.
    public struct ScheduleItem: Identifiable, Sendable {
        public let id: Int64
        public let title: String
        public let jobName: String?
        public let employeeName: String
        public let shiftStart: String?

        public init(id: Int64, title: String, jobName: String?, employeeName: String, shiftStart: String?) {
            self.id = id
            self.title = title
            self.jobName = jobName
            self.employeeName = employeeName
            self.shiftStart = shiftStart
        }
    }

    /// Financial overview with this-week vs last-week and this-month vs last-month.
    public struct FinancialSnapshot: Sendable {
        public let spendingThisWeek: Double
        public let spendingLastWeek: Double
        public let spendingThisMonth: Double
        public let spendingLastMonth: Double
        public let outstandingPOValue: Double

        public init(spendingThisWeek: Double, spendingLastWeek: Double,
                    spendingThisMonth: Double, spendingLastMonth: Double,
                    outstandingPOValue: Double) {
            self.spendingThisWeek = spendingThisWeek
            self.spendingLastWeek = spendingLastWeek
            self.spendingThisMonth = spendingThisMonth
            self.spendingLastMonth = spendingLastMonth
            self.outstandingPOValue = outstandingPOValue
        }
    }

    /// Generate a briefing from overnight and current-day activity.
    public func getOfficeBriefing() throws -> OfficeBriefing {
        do {
            return try db.writer.read { dbConn -> OfficeBriefing in
                let newJPOs = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM job_parts_orders
                    WHERE created_at >= datetime('now', '-12 hours')
                      AND deleted_at IS NULL
                    """) ?? 0

                let pendingApprovals = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM job_parts_orders
                    WHERE status = 'submitted' AND deleted_at IS NULL
                    """) ?? 0

                let clockedInToday = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(DISTINCT user_id) FROM labor_entries
                    WHERE date(clock_in) = date('now')
                      AND clock_out IS NULL
                      AND deleted_at IS NULL
                    """) ?? 0

                let overdueItems = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM purchase_orders
                    WHERE expected_delivery IS NOT NULL
                      AND date(expected_delivery) < date('now')
                      AND status NOT IN ('received', 'cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                let pendingTimeOff = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM schedule_exceptions
                    WHERE exception_type = 'time_off'
                      AND is_approved = 0
                      AND deleted_at IS NULL
                    """) ?? 0

                var highlights: [String] = []
                if newJPOs > 0 { highlights.append("\(newJPOs) new job part orders overnight") }
                if pendingApprovals > 0 { highlights.append("\(pendingApprovals) JPOs awaiting approval") }
                if clockedInToday > 0 { highlights.append("\(clockedInToday) workers clocked in") }
                if overdueItems > 0 { highlights.append("\(overdueItems) overdue deliveries") }
                if pendingTimeOff > 0 { highlights.append("\(pendingTimeOff) time-off requests pending") }

                let deliveryNote = overdueItems > 0
                    ? "\(overdueItems) deliveries are overdue."
                    : "all deliveries on track."

                let summary = "Good morning. \(pendingApprovals) items need approval, \(clockedInToday) workers are active, and \(deliveryNote)"

                return OfficeBriefing(
                    summary: summary,
                    generatedAt: Date(),
                    highlights: highlights,
                    alertCount: pendingApprovals + overdueItems + pendingTimeOff
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return OfficeBriefing(summary: "Dashboard data not yet available.", generatedAt: Date(), highlights: [], alertCount: 0)
            }
            throw error
        }
    }

    /// Fetch actionable items requiring manager attention, sorted by priority then age.
    public func getAttentionItems() throws -> [AttentionItem] {
        var items: [AttentionItem] = []

        // JPO approvals
        do {
            let jpos = try db.writer.read { dbConn -> [Row] in
                try Row.fetchAll(dbConn, sql: """
                    SELECT jpo.id, jpo.created_at,
                           COALESCE(j.job_name, 'Unknown Job') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS requester
                    FROM job_parts_orders jpo
                    LEFT JOIN jobs j ON jpo.job_id = j.id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON jpo.requested_by = u.id AND u.deleted_at IS NULL
                    WHERE jpo.status = 'submitted'
                      AND jpo.deleted_at IS NULL
                    ORDER BY jpo.created_at ASC
                    """)
            }
            for row in jpos {
                let dateStr: String = row["created_at"] ?? ""
                let created = CoreFormatters.parseISO(dateStr) ?? Date()
                let age = Date().timeIntervalSince(created)
                items.append(AttentionItem(
                    id: row["id"] ?? 0,
                    title: "JPO Approval: \(row["job_name"] as String? ?? "Unknown")",
                    subtitle: "Requested by \(row["requester"] as String? ?? "Unknown")",
                    itemType: "jpo_approval",
                    createdAt: created,
                    priority: .from(age: age)
                ))
            }
        } catch {
            if !isTableNotFoundError(error) { throw error }
        }

        // Pending time-off requests
        do {
            let timeOff = try db.writer.read { dbConn -> [Row] in
                try Row.fetchAll(dbConn, sql: """
                    SELECT se.id, se.exception_date, se.reason,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name
                    FROM schedule_exceptions se
                    LEFT JOIN users u ON u.id = se.user_id AND u.deleted_at IS NULL
                    WHERE se.exception_type = 'time_off'
                      AND se.is_approved = 0
                      AND se.deleted_at IS NULL
                    ORDER BY se.created_at ASC
                    """)
            }
            for row in timeOff {
                let dateStr: String = row["exception_date"] ?? ""
                // exception_date is a date string, use created_at proxy for age
                let now = Date()
                items.append(AttentionItem(
                    id: row["id"] ?? 0,
                    title: "Time Off: \(row["employee_name"] as String? ?? "Unknown")",
                    subtitle: "\(dateStr) — \(row["reason"] as String? ?? "No reason")",
                    itemType: "time_off",
                    createdAt: now.addingTimeInterval(-86400), // approximate 1 day for priority
                    priority: .medium
                ))
            }
        } catch {
            if !isTableNotFoundError(error) { throw error }
        }

        // Overdue PO deliveries
        do {
            let overdue = try db.writer.read { dbConn -> [Row] in
                try Row.fetchAll(dbConn, sql: """
                    SELECT po.id, po.po_number, po.expected_delivery,
                           COALESCE(s.name, 'Unknown') AS supplier_name
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id AND s.deleted_at IS NULL
                    WHERE po.expected_delivery IS NOT NULL
                      AND date(po.expected_delivery) < date('now')
                      AND po.status NOT IN ('received', 'cancelled')
                      AND po.deleted_at IS NULL
                    ORDER BY po.expected_delivery ASC
                    LIMIT 20
                    """)
            }
            for row in overdue {
                items.append(AttentionItem(
                    id: row["id"] ?? 0,
                    title: "Overdue PO: \(row["po_number"] as String? ?? "?")",
                    subtitle: "From \(row["supplier_name"] as String? ?? "Unknown") — expected \(row["expected_delivery"] as String? ?? "?")",
                    itemType: "overdue_po",
                    createdAt: Date().addingTimeInterval(-5 * 86400), // overdue = always red
                    priority: .overdue
                ))
            }
        } catch {
            if !isTableNotFoundError(error) { throw error }
        }

        // Sort by priority (highest first), then by age (oldest first)
        items.sort { a, b in
            if a.priority != b.priority {
                return a.priority > b.priority
            }
            return a.createdAt < b.createdAt
        }

        return items
    }

    /// Fetch today's dispatch schedule (workers assigned to jobs today).
    public func getTodaySchedule() throws -> [ScheduleItem] {
        do {
            return try db.writer.read { dbConn -> [ScheduleItem] in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT jd.id, jd.shift_start,
                           COALESCE(j.job_name, 'Unassigned') AS job_name,
                           COALESCE(u.display_name, u.email, 'Unknown') AS employee_name
                    FROM job_dispatch jd
                    LEFT JOIN jobs j ON j.id = jd.job_id AND j.deleted_at IS NULL
                    LEFT JOIN users u ON u.id = jd.user_id AND u.deleted_at IS NULL
                    WHERE jd.dispatch_date = date('now')
                      AND jd.deleted_at IS NULL
                    ORDER BY jd.shift_start ASC, employee_name ASC
                    """)
                return rows.map { row in
                    ScheduleItem(
                        id: row["id"] ?? 0,
                        title: row["employee_name"] ?? "Unknown",
                        jobName: row["job_name"],
                        employeeName: row["employee_name"] ?? "Unknown",
                        shiftStart: row["shift_start"]
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Fetch financial snapshot comparing this week vs last week and this month vs last month.
    public func getFinancialSnapshot() throws -> FinancialSnapshot {
        do {
            return try db.writer.read { dbConn -> FinancialSnapshot in
                // This week spending (POs created this week)
                let spendingThisWeek = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM purchase_orders
                    WHERE date(created_at) >= date('now', 'weekday 0', '-7 days')
                      AND status NOT IN ('cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                // Last week spending
                let spendingLastWeek = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM purchase_orders
                    WHERE date(created_at) >= date('now', 'weekday 0', '-14 days')
                      AND date(created_at) < date('now', 'weekday 0', '-7 days')
                      AND status NOT IN ('cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                // This month spending
                let spendingThisMonth = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM purchase_orders
                    WHERE date(created_at) >= date('now', 'start of month')
                      AND status NOT IN ('cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                // Last month spending
                let spendingLastMonth = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM purchase_orders
                    WHERE date(created_at) >= date('now', 'start of month', '-1 month')
                      AND date(created_at) < date('now', 'start of month')
                      AND status NOT IN ('cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                // Outstanding PO value (submitted/ordered, not yet received)
                let outstandingPOValue = try Double.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(total_cost), 0) FROM purchase_orders
                    WHERE status IN ('submitted', 'ordered', 'partial')
                      AND deleted_at IS NULL
                    """) ?? 0

                return FinancialSnapshot(
                    spendingThisWeek: spendingThisWeek,
                    spendingLastWeek: spendingLastWeek,
                    spendingThisMonth: spendingThisMonth,
                    spendingLastMonth: spendingLastMonth,
                    outstandingPOValue: outstandingPOValue
                )
            }
        } catch {
            if isTableNotFoundError(error) {
                return FinancialSnapshot(spendingThisWeek: 0, spendingLastWeek: 0, spendingThisMonth: 0, spendingLastMonth: 0, outstandingPOValue: 0)
            }
            throw error
        }
    }

    // MARK: - Employee Count

    /// Fetch the number of active (non-deleted) employees/users in the system.
    ///
    /// Used by the Getting Started checklist to determine whether the user
    /// has added any team members yet.
    public func getEmployeeCount() throws -> Int {
        try safeCount(
            sql: "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND is_active = 1"
        )
    }

    // MARK: - Internal Helpers

    /// Execute a `SELECT COUNT(*)` query and return the integer result.
    /// If the table does not exist (e.g., migration hasn't run), returns 0.
    private func safeCount(sql: String, arguments: StatementArguments = StatementArguments()) throws -> Int {
        do {
            return try db.writer.read { dbConnection in
                try Int.fetchOne(dbConnection, sql: sql, arguments: arguments) ?? 0
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    // MARK: - QR Scanning

    /// Process a raw QR scan string through the auto-fill service.
    public func processQRScan(_ rawString: String) throws -> QRAutoFillResult {
        let autoFill = QRAutoFillService(db: db)
        return try autoFill.processQRScan(rawString)
    }

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    ///
    /// SQLite returns `SQLITE_ERROR` (code 1) with a message like
    /// "no such table: <name>" when a query references a table that
    /// doesn't exist. We treat this as a non-fatal condition so the
    /// dashboard can still render partial data on freshly created databases.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
