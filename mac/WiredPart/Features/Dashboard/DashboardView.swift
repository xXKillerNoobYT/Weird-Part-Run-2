import SwiftUI
import GRDB
import WiredPartCore

/// Native macOS Dashboard page.
///
/// Shows a greeting with two tabs:
///   1. Overview — KPI cards, certification/vehicle expiry alerts, quick actions
///   2. Daily Report — pending actions, today's activity, expected deliveries, budget alerts
///
/// Data loads on appear and auto-refreshes every 60 seconds.
struct DashboardView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var activeTab = 0

    // Overview state
    @State private var totalParts: Int = 0
    @State private var activeJobs: Int = 0
    @State private var pendingOrders: Int = 0
    @State private var lowStockCount: Int = 0
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

    @State private var isLoading: Bool = true

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greeting

                Picker("View", selection: $activeTab) {
                    Text("Overview").tag(0)
                    Text("Daily Report").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if activeTab == 0 {
                    kpiCards
                    alertSections
                    quickActions
                } else {
                    dailyReportContent
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
        .onReceive(refreshTimer) { _ in
            loadData()
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(dateString)
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

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }

    // MARK: - KPI Cards

    private var kpiCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 16) {
            KPICard(title: "Total Parts", value: "\(totalParts)", icon: "shippingbox", color: .blue)
            KPICard(title: "Active Jobs", value: "\(activeJobs)", icon: "hammer", color: .orange)
            KPICard(title: "Pending Orders", value: "\(pendingOrders)", icon: "cart", color: .purple)
            KPICard(title: "Low Stock", value: "\(lowStockCount)", icon: "exclamationmark.triangle", color: lowStockCount > 0 ? .red : .green)
        }
    }

    // MARK: - Alert Sections

    private var alertSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !certAlerts.isEmpty {
                alertSection(
                    title: "Certification Expiry Alerts",
                    icon: "exclamationmark.shield",
                    items: certAlerts.map { "\($0.name) - expires \($0.expiryDate)" }
                )
            }

            if !vehicleAlerts.isEmpty {
                alertSection(
                    title: "Vehicle Expiry Alerts",
                    icon: "truck.box",
                    items: vehicleAlerts.map { "\($0.name) - \($0.alertType) expires \($0.expiryDate)" }
                )
            }

            if certAlerts.isEmpty && vehicleAlerts.isEmpty && !isLoading {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No upcoming expiry alerts")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
            }
        }
    }

    private func alertSection(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text(item)
                        .font(.callout)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                quickActionButton("New Job", icon: "plus.circle", color: .blue)
                quickActionButton("Move Stock", icon: "arrow.left.arrow.right", color: .green)
                quickActionButton("Clock In", icon: "clock.badge.checkmark", color: .orange)
                quickActionButton("New Order", icon: "cart.badge.plus", color: .purple)
            }
        }
    }

    private func quickActionButton(_ label: String, icon: String, color: Color) -> some View {
        Button {
            // Quick action navigation — placeholder for now
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.controlBackgroundColor)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Daily Report

    private var dailyReportContent: some View {
        VStack(alignment: .leading, spacing: 20) {
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
            }

            // Pending Actions
            pendingActionsCard

            // Today's Activity
            todayActivityCard

            // Expected Deliveries
            expectedDeliveriesCard

            // Budget Alerts
            if !budgetAlerts.isEmpty {
                budgetAlertsCard
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separatorColor), lineWidth: 1))
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

            HStack(spacing: 16) {
                activityStat("Orders Created", value: todayCreatedOrders, color: .blue)
                activityStat("Items Received", value: todayReceivedItems, color: .green)
                activityStat("Returns Processed", value: todayReturns, color: .purple)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separatorColor), lineWidth: 1))
    }

    private func activityStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                        .background(Capsule().fill(Color(.separatorColor).opacity(0.3)))
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
                                .stroke(delivery.isOverdue ? Color.red.opacity(0.3) : Color(.separatorColor), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separatorColor), lineWidth: 1))
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
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.separatorColor), lineWidth: 1))
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            try db.writer.read { dbConnection in
                totalParts = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL"
                ) ?? 0

                activeJobs = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM jobs WHERE status IN ('active', 'in_progress') AND deleted_at IS NULL"
                ) ?? 0

                pendingOrders = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM purchase_orders WHERE status IN ('pending', 'draft') AND deleted_at IS NULL"
                ) ?? 0

                lowStockCount = try Int.fetchOne(
                    dbConnection,
                    sql: """
                        SELECT COUNT(*) FROM parts
                        WHERE deleted_at IS NULL
                          AND min_stock_level IS NOT NULL
                          AND current_stock < min_stock_level
                        """
                ) ?? 0

                // Certification expiry alerts (within 30 days)
                let certRows = try Row.fetchAll(
                    dbConnection,
                    sql: """
                        SELECT u.display_name, e.expiry_date
                        FROM employee_certifications e
                        JOIN users u ON u.id = e.employee_id
                        WHERE e.expiry_date IS NOT NULL
                          AND e.expiry_date <= date('now', '+30 days')
                          AND e.expiry_date >= date('now')
                        ORDER BY e.expiry_date ASC
                        LIMIT 10
                        """
                )
                certAlerts = certRows.map { row in
                    CertAlert(
                        name: row["display_name"] as? String ?? "Unknown",
                        expiryDate: row["expiry_date"] as? String ?? ""
                    )
                }

                // Vehicle expiry alerts (registration/insurance within 30 days)
                let vehicleRows = try Row.fetchAll(
                    dbConnection,
                    sql: """
                        SELECT name,
                               CASE
                                 WHEN registration_expiry IS NOT NULL AND registration_expiry <= date('now', '+30 days')
                                   THEN 'registration'
                                 WHEN insurance_expiry IS NOT NULL AND insurance_expiry <= date('now', '+30 days')
                                   THEN 'insurance'
                                 ELSE 'unknown'
                               END AS alert_type,
                               COALESCE(
                                 CASE WHEN registration_expiry <= date('now', '+30 days') THEN registration_expiry END,
                                 CASE WHEN insurance_expiry <= date('now', '+30 days') THEN insurance_expiry END
                               ) AS expiry_date
                        FROM vehicles
                        WHERE deleted_at IS NULL
                          AND (
                            (registration_expiry IS NOT NULL AND registration_expiry <= date('now', '+30 days') AND registration_expiry >= date('now'))
                            OR
                            (insurance_expiry IS NOT NULL AND insurance_expiry <= date('now', '+30 days') AND insurance_expiry >= date('now'))
                          )
                        ORDER BY expiry_date ASC
                        LIMIT 10
                        """
                )
                vehicleAlerts = vehicleRows.map { row in
                    VehicleAlert(
                        name: row["name"] as? String ?? "Unknown",
                        alertType: row["alert_type"] as? String ?? "",
                        expiryDate: row["expiry_date"] as? String ?? ""
                    )
                }

                // --- Daily Report data ---

                // Pending actions
                pendingJPOs = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM jpos WHERE status = 'submitted' AND deleted_at IS NULL"
                ) ?? 0

                pendingPOs = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM purchase_orders WHERE status = 'submitted' AND deleted_at IS NULL"
                ) ?? 0

                returnsToSort = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM returns WHERE status = 'submitted' AND deleted_at IS NULL"
                ) ?? 0

                overdueDeliveries = try Int.fetchOne(
                    dbConnection,
                    sql: """
                        SELECT COUNT(*) FROM purchase_orders
                        WHERE expected_delivery IS NOT NULL
                          AND date(expected_delivery) < date('now')
                          AND status NOT IN ('received', 'cancelled')
                          AND deleted_at IS NULL
                        """
                ) ?? 0

                // Today's activity
                todayCreatedOrders = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM purchase_orders WHERE date(created_at) = date('now') AND deleted_at IS NULL"
                ) ?? 0

                todayReceivedItems = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM receiving_sessions WHERE date(created_at) = date('now') AND deleted_at IS NULL"
                ) ?? 0

                todayReturns = try Int.fetchOne(
                    dbConnection,
                    sql: "SELECT COUNT(*) FROM returns WHERE date(created_at) = date('now') AND deleted_at IS NULL"
                ) ?? 0

                // Expected deliveries this week
                let deliveryRows = try Row.fetchAll(
                    dbConnection,
                    sql: """
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
                        """
                )
                expectedDeliveries = deliveryRows.map { row in
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
                let budgetRows = try Row.fetchAll(
                    dbConnection,
                    sql: """
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
                        """
                )
                budgetAlerts = budgetRows.map { row in
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
            }
        } catch {
            print("[Dashboard] Data load error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Supporting Types

private struct CertAlert {
    let name: String
    let expiryDate: String
}

private struct VehicleAlert {
    let name: String
    let alertType: String
    let expiryDate: String
}

private struct ExpectedDelivery: Identifiable {
    let id: Int64
    let poNumber: String
    let supplierName: String
    let expectedDate: String
    let lineCount: Int
    let isOverdue: Bool
}

private struct JobBudgetAlert: Identifiable {
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
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}
