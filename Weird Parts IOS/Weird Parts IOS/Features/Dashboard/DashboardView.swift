import SwiftUI
import Combine
import GRDB
import WiredPartCore

/// Main dashboard view matching the macOS Dashboard layout.
///
/// Shows a time-of-day greeting with two tabs:
///   1. Overview — KPI cards, certification/vehicle expiry alerts, quick actions
///   2. Daily Report — pending actions, today's activity, expected deliveries, budget alerts
///
/// Uses AppCore to query the database directly for summary statistics.
/// All data is fetched on appear, supports pull-to-refresh, and auto-refreshes every 60s.
struct DashboardView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var activeTab = 0

    // Overview state
    @State private var stats = DashboardStats()
    @State private var certAlerts: [CertAlert] = []
    @State private var vehicleAlerts: [VehicleAlert] = []

    // Daily Report state
    @State private var pendingJPOs: Int = 0
    @State private var pendingPOs: Int = 0
    @State private var returnsToSort: Int = 0
    @State private var overdueDeliveries: Int = 0
    @State private var todayCreatedOrders: Int = 0
    @State private var todayReceivedItems: Int = 0
    @State private var todayReturns: Int = 0
    @State private var expectedDeliveries: [ExpectedDelivery] = []
    @State private var budgetAlerts: [JobBudgetAlert] = []

    @State private var isLoading = true

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Greeting
                greeting
                    .padding(.horizontal)

                // Tab picker
                Picker("View", selection: $activeTab) {
                    Text("Overview").tag(0)
                    Text("Daily Report").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if activeTab == 0 {
                    // Overview tab
                    kpiSection
                    alertsContent
                    quickActionsSection
                } else {
                    // Daily Report tab
                    dailyReportContent
                }
            }
            .padding(.vertical)
        }
        .refreshable { await loadData() }
        .background(Color(.systemGroupedBackground))
        .task { await loadData() }
        .onReceive(refreshTimer) { _ in
            Task { await loadData() }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.title2)
                .fontWeight(.bold)
            Text(formattedDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appCore.currentUser?.displayName ?? "there"
        let timeOfDay: String
        switch hour {
        case 0..<12:  timeOfDay = "Good morning"
        case 12..<17: timeOfDay = "Good afternoon"
        default:      timeOfDay = "Good evening"
        }
        return "\(timeOfDay), \(name)"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }

    // MARK: - KPI Cards

    @ViewBuilder
    private var kpiSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            KPICard(title: "Total Parts", value: "\(stats.totalParts)", icon: "shippingbox", color: .blue)
            KPICard(title: "Active Jobs", value: "\(stats.activeJobs)", icon: "hammer", color: .orange)
            KPICard(title: "Pending Orders", value: "\(stats.pendingOrders)", icon: "cart", color: .purple)
            KPICard(title: "Low Stock", value: "\(stats.lowStockCount)", icon: "exclamationmark.triangle", color: stats.lowStockCount > 0 ? .red : .green)
        }
        .padding(.horizontal)
    }

    // MARK: - Alerts Content

    @ViewBuilder
    private var alertsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !certAlerts.isEmpty {
                alertsSection(
                    title: "Certification Alerts",
                    icon: "exclamationmark.shield.fill",
                    color: .orange,
                    items: certAlerts.map { "\($0.userName): \($0.certName) expires \($0.expiryDate)" }
                )
            }

            if !vehicleAlerts.isEmpty {
                alertsSection(
                    title: "Vehicle Alerts",
                    icon: "car.badge.gearshape.fill",
                    color: .red,
                    items: vehicleAlerts.map { "\($0.vehicleNumber): \($0.alertMessage)" }
                )
            }

            if certAlerts.isEmpty && vehicleAlerts.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No upcoming expiry alerts")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 12)
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func alertsSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }

            ForEach(items, id: \.self) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
        .padding(.horizontal)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    QuickActionButton(title: "Clock In", icon: "clock.badge.checkmark.fill", color: .green)
                    QuickActionButton(title: "New Order", icon: "plus.circle.fill", color: .blue)
                    QuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange)
                    QuickActionButton(title: "Scan QR", icon: "qrcode.viewfinder", color: .purple)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Daily Report

    @ViewBuilder
    private var dailyReportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Overdue alert banner
            if overdueDeliveries > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(overdueDeliveries) overdue deliver\(overdueDeliveries == 1 ? "y" : "ies")")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                        Text("Immediate attention required")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2), lineWidth: 1))
                .padding(.horizontal)
            }

            // Pending Actions
            pendingActionsCard
                .padding(.horizontal)

            // Today's Activity
            todayActivityCard
                .padding(.horizontal)

            // Expected Deliveries
            expectedDeliveriesCard
                .padding(.horizontal)

            // Budget Alerts
            if !budgetAlerts.isEmpty {
                budgetAlertsCard
                    .padding(.horizontal)
            }

            // Live indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text("Live — updates every 60 seconds")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    private var pendingActionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pending Actions")
                    .font(.headline)
                Spacer()
                let total = pendingJPOs + pendingPOs + returnsToSort + overdueDeliveries
                Text(total > 0 ? "\(total)" : "All clear")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(total > 0 ? Color.orange.opacity(0.15) : Color.green.opacity(0.15)))
                    .foregroundStyle(total > 0 ? .orange : .green)
            }
            .padding()

            VStack(spacing: 0) {
                pendingActionRow("JPOs awaiting approval", count: pendingJPOs, icon: "cart", urgent: false)
                Divider().padding(.leading, 40)
                pendingActionRow("POs to submit", count: pendingPOs, icon: "shippingbox", urgent: false)
                Divider().padding(.leading, 40)
                pendingActionRow("Returns to sort", count: returnsToSort, icon: "arrow.uturn.backward.circle", urgent: false)
                Divider().padding(.leading, 40)
                pendingActionRow("Overdue deliveries", count: overdueDeliveries, icon: "exclamationmark.triangle", urgent: true)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .glassCard(cornerRadius: 12)
    }

    private func pendingActionRow(_ label: String, count: Int, icon: String, urgent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(urgent && count > 0 ? .red : .secondary)
            Text(label)
                .font(.callout)
            Spacer()
            Text("\(count)")
                .font(.callout)
                .fontWeight(.bold)
                .foregroundStyle(
                    count > 0
                        ? (urgent ? .red : .orange)
                        : .secondary
                )
        }
        .padding(.vertical, 6)
        .opacity(count > 0 ? 1 : 0.5)
    }

    private var todayActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Activity")
                .font(.headline)

            HStack(spacing: 12) {
                activityStat("Orders Created", value: todayCreatedOrders, color: .blue)
                activityStat("Items Received", value: todayReceivedItems, color: .green)
                activityStat("Returns", value: todayReturns, color: .purple)
            }
        }
        .padding()
        .glassCard(cornerRadius: 12)
    }

    private func activityStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.06)))
    }

    private var expectedDeliveriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Expected Deliveries This Week")
                    .font(.headline)
                Spacer()
                if !expectedDeliveries.isEmpty {
                    Text("\(expectedDeliveries.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(.systemGray4)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            if expectedDeliveries.isEmpty {
                Text("No deliveries expected this week.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(expectedDeliveries) { delivery in
                        HStack(spacing: 12) {
                            Image(systemName: "truck.box")
                                .foregroundStyle(delivery.isOverdue ? .red : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(delivery.poNumber) — \(delivery.supplierName)")
                                    .font(.callout)
                                    .lineLimit(1)
                                Text("\(delivery.lineCount) item\(delivery.lineCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(delivery.expectedDate)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(delivery.isOverdue ? .red : .secondary)
                                if delivery.isOverdue {
                                    Text("Overdue")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.red.opacity(0.15)))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(delivery.isOverdue ? Color.red.opacity(0.3) : Color(.separator), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .glassCard(cornerRadius: 12)
    }

    private var budgetAlertsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Budget Alerts")
                .font(.headline)
                .padding()

            VStack(spacing: 8) {
                ForEach(budgetAlerts) { alert in
                    HStack(spacing: 12) {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(alert.pctUsed >= 100 ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.jobName)
                                .font(.callout)
                                .lineLimit(1)
                            Text("$\(Int(alert.currentSpend)) of $\(Int(alert.budgetLimit))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(alert.pctUsed))%")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(alert.pctUsed >= 100 ? Color.red.opacity(0.15) : Color.orange.opacity(0.15)))
                            .foregroundStyle(alert.pctUsed >= 100 ? .red : .orange)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(alert.pctUsed >= 100 ? Color.red.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            let db = appCore.db!

            let cutoffDate = dashboardDateString(daysFromNow: 30)

            let result = try await db.writer.read { dbConnection -> DashboardLoadResult in
                // KPI counts
                let totalParts = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
                let activeJobs = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM jobs WHERE status IN ('active','in_progress') AND deleted_at IS NULL") ?? 0
                let pendingOrders = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM purchase_orders WHERE status IN ('pending','draft') AND deleted_at IS NULL") ?? 0
                let lowStockCount = try Int.fetchOne(dbConnection, sql: """
                    SELECT COUNT(*) FROM parts
                    WHERE deleted_at IS NULL
                      AND min_stock_level IS NOT NULL
                      AND current_stock < min_stock_level
                    """) ?? 0

                let newStats = DashboardStats(
                    totalParts: totalParts,
                    activeJobs: activeJobs,
                    pendingOrders: pendingOrders,
                    lowStockCount: lowStockCount
                )

                // Certification alerts (expiring within 30 days)
                let certRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT c.cert_name, c.expiry_date, u.display_name
                    FROM certifications c
                    JOIN users u ON u.id = c.user_id
                    WHERE c.expiry_date IS NOT NULL
                      AND c.expiry_date <= date('now', '+30 days')
                      AND c.expiry_date >= date('now')
                      AND c.deleted_at IS NULL
                    ORDER BY c.expiry_date ASC
                    LIMIT 10
                    """)
                let certs = certRows.map { row in
                    CertAlert(
                        userName: row["display_name"] as String,
                        certName: row["cert_name"] as String,
                        expiryDate: row["expiry_date"] as String
                    )
                }

                // Vehicle alerts (insurance/registration expiring within 30 days)
                let vehicleRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT vehicle_number, insurance_expiry, registration_expiry
                    FROM vehicles
                    WHERE deleted_at IS NULL AND status = 'active'
                      AND (
                        (insurance_expiry IS NOT NULL AND insurance_expiry <= date('now', '+30 days'))
                        OR (registration_expiry IS NOT NULL AND registration_expiry <= date('now', '+30 days'))
                      )
                    ORDER BY COALESCE(insurance_expiry, registration_expiry) ASC
                    LIMIT 10
                    """)
                let vAlerts = vehicleRows.compactMap { row -> VehicleAlert? in
                    let num: String = row["vehicle_number"]
                    let ins: String? = row["insurance_expiry"]
                    let reg: String? = row["registration_expiry"]
                    if let ins, ins <= cutoffDate {
                        return VehicleAlert(vehicleNumber: num, alertMessage: "Insurance expires \(ins)")
                    }
                    if let reg, reg <= cutoffDate {
                        return VehicleAlert(vehicleNumber: num, alertMessage: "Registration expires \(reg)")
                    }
                    return nil
                }

                // --- Daily Report data ---

                let pJPOs = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM jpos WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
                let pPOs = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM purchase_orders WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
                let rSort = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM returns WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
                let oDeliv = try Int.fetchOne(dbConnection, sql: """
                    SELECT COUNT(*) FROM purchase_orders
                    WHERE expected_delivery IS NOT NULL
                      AND date(expected_delivery) < date('now')
                      AND status NOT IN ('received', 'cancelled')
                      AND deleted_at IS NULL
                    """) ?? 0

                let tOrders = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM purchase_orders WHERE date(created_at) = date('now') AND deleted_at IS NULL") ?? 0
                let tReceived = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM receiving_sessions WHERE date(created_at) = date('now') AND deleted_at IS NULL") ?? 0
                let tReturns = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM returns WHERE date(created_at) = date('now') AND deleted_at IS NULL") ?? 0

                // Expected deliveries this week
                let deliveryRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT po.id, po.po_number, po.expected_delivery,
                           COALESCE(s.name, 'Unknown') AS supplier_name,
                           (SELECT COUNT(*) FROM po_lines pl WHERE pl.po_id = po.id AND pl.deleted_at IS NULL) AS line_count,
                           CASE WHEN date(po.expected_delivery) < date('now') THEN 1 ELSE 0 END AS is_overdue
                    FROM purchase_orders po
                    LEFT JOIN suppliers s ON s.id = po.supplier_id
                    WHERE po.expected_delivery IS NOT NULL
                      AND po.status NOT IN ('received', 'cancelled')
                      AND po.deleted_at IS NULL
                      AND date(po.expected_delivery) BETWEEN date('now', '-7 days') AND date('now', '+7 days')
                    ORDER BY po.expected_delivery ASC
                    LIMIT 20
                    """)
                let expDeliv = deliveryRows.map { row in
                    ExpectedDelivery(
                        id: row["id"] ?? 0,
                        poNumber: row["po_number"] ?? "",
                        supplierName: row["supplier_name"] ?? "Unknown",
                        expectedDate: String((row["expected_delivery"] as String? ?? "").prefix(10)),
                        lineCount: row["line_count"] ?? 0,
                        isOverdue: (row["is_overdue"] as Int? ?? 0) == 1
                    )
                }

                // Budget alerts: jobs where spending exceeds 80% of budget
                let budgetRows = try Row.fetchAll(dbConnection, sql: """
                    SELECT j.id, j.job_name, j.budget,
                           COALESCE(
                             (SELECT SUM(le.regular_hours * COALESCE(u.hourly_rate, 0))
                              FROM labor_entries le
                              LEFT JOIN users u ON u.id = le.user_id
                              WHERE le.job_id = j.id AND le.deleted_at IS NULL), 0
                           ) +
                           COALESCE(
                             (SELECT SUM(po.total_cost)
                              FROM purchase_orders po
                              WHERE po.job_id = j.id
                                AND po.status NOT IN ('cancelled')
                                AND po.deleted_at IS NULL), 0
                           ) AS current_spend
                    FROM jobs j
                    WHERE j.budget IS NOT NULL AND j.budget > 0
                      AND j.status = 'active'
                      AND j.deleted_at IS NULL
                    HAVING current_spend >= j.budget * 0.8
                    ORDER BY (current_spend * 1.0 / j.budget) DESC
                    LIMIT 10
                    """)
                let bAlerts = budgetRows.map { row in
                    let budget: Double = row["budget"] ?? 0
                    let spend: Double = row["current_spend"] ?? 0
                    return JobBudgetAlert(
                        id: row["id"] ?? 0,
                        jobName: row["job_name"] ?? "",
                        currentSpend: spend,
                        budgetLimit: budget,
                        pctUsed: budget > 0 ? (spend / budget) * 100 : 0
                    )
                }

                return DashboardLoadResult(
                    stats: newStats,
                    certAlerts: certs,
                    vehicleAlerts: vAlerts,
                    pendingJPOs: pJPOs,
                    pendingPOs: pPOs,
                    returnsToSort: rSort,
                    overdueDeliveries: oDeliv,
                    todayCreatedOrders: tOrders,
                    todayReceivedItems: tReceived,
                    todayReturns: tReturns,
                    expectedDeliveries: expDeliv,
                    budgetAlerts: bAlerts
                )
            }

            await MainActor.run {
                stats = result.stats
                certAlerts = result.certAlerts
                vehicleAlerts = result.vehicleAlerts
                pendingJPOs = result.pendingJPOs
                pendingPOs = result.pendingPOs
                returnsToSort = result.returnsToSort
                overdueDeliveries = result.overdueDeliveries
                todayCreatedOrders = result.todayCreatedOrders
                todayReceivedItems = result.todayReceivedItems
                todayReturns = result.todayReturns
                expectedDeliveries = result.expectedDeliveries
                budgetAlerts = result.budgetAlerts
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

/// Format a date N days from now as "yyyy-MM-dd" — free function to avoid actor isolation.
private func dashboardDateString(daysFromNow days: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let date = Calendar.current.date(byAdding: .day, value: days, to: Date())!
    return formatter.string(from: date)
}

// MARK: - Data Types

private struct DashboardStats: Sendable {
    var totalParts = 0
    var activeJobs = 0
    var pendingOrders = 0
    var lowStockCount = 0
}

/// Result object to transfer all data out of the database read closure.
private struct DashboardLoadResult: Sendable {
    let stats: DashboardStats
    let certAlerts: [CertAlert]
    let vehicleAlerts: [VehicleAlert]
    let pendingJPOs: Int
    let pendingPOs: Int
    let returnsToSort: Int
    let overdueDeliveries: Int
    let todayCreatedOrders: Int
    let todayReceivedItems: Int
    let todayReturns: Int
    let expectedDeliveries: [ExpectedDelivery]
    let budgetAlerts: [JobBudgetAlert]
}

private struct CertAlert: Sendable {
    let userName: String
    let certName: String
    let expiryDate: String
}

private struct VehicleAlert: Sendable {
    let vehicleNumber: String
    let alertMessage: String
}

private struct ExpectedDelivery: Identifiable, Sendable {
    let id: Int64
    let poNumber: String
    let supplierName: String
    let expectedDate: String
    let lineCount: Int
    let isOverdue: Bool
}

private struct JobBudgetAlert: Identifiable, Sendable {
    let id: Int64
    let jobName: String
    let currentSpend: Double
    let budgetLimit: Double
    let pctUsed: Double
}

// MARK: - KPI Card

private struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .frame(width: 80, height: 72)
        .glassCard(cornerRadius: 12)
    }
}
