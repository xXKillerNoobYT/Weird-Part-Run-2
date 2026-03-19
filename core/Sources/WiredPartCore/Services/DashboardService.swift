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
                WHERE status IN ('draft', 'submitted', 'acknowledged')
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
            sql: "SELECT COUNT(*) FROM purchase_orders WHERE status = 'submitted' AND deleted_at IS NULL"
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

    /// Detect whether a GRDB/SQLite error indicates a missing table.
    ///
    /// SQLite returns `SQLITE_ERROR` (code 1) with a message like
    /// "no such table: <name>" when a query references a table that
    /// doesn't exist. We treat this as a non-fatal condition so the
    /// dashboard can still render partial data on freshly created databases.
    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table")
    }
}
