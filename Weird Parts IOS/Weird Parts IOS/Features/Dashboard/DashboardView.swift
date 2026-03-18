import SwiftUI
import Charts
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

    // Charts data
    @State private var laborChartData: [LaborDayData] = []
    @State private var stockChartData: [StockLevelData] = []
    @State private var spendingChartData: [SpendingCategory] = []

    @State private var isLoading = true
    @State private var loadError: String?

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                // Greeting
                greeting
                    .padding(.horizontal, DS.Space.lg)

                // Tab picker
                Picker("View", selection: $activeTab) {
                    Text("Overview").tag(0)
                    Text("Daily Report").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Space.lg)

                if isLoading {
                    DSLoadingState()
                        .padding(.top, DS.Space.jumbo)
                } else if let error = loadError {
                    ErrorStateView(message: error) { Task { await loadData() } }
                        .padding(.top, DS.Space.xl)
                } else if activeTab == 0 {
                    // Overview tab
                    kpiSection
                    chartsSection
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
        .background(DS.Background.page)
        .task { await loadData() }
        .onReceive(refreshTimer) { _ in
            Task { await loadData() }
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(greetingText)
                .dsStyle(.pageTitle)
            Text(formattedDate)
                .dsStyle(.detail)
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

    private struct DashboardChartData: Sendable {
    let labor: [LaborDayData]
    let stock: [StockLevelData]
    let spending: [SpendingCategory]
}

// MARK: - KPI Cards

    @ViewBuilder
    private var kpiSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: DS.Space.md),
            GridItem(.flexible(), spacing: DS.Space.md),
        ], spacing: DS.Space.md) {
            DSKPICard(title: "Total Parts", value: "\(stats.totalParts)", icon: "shippingbox", color: .blue)
            DSKPICard(title: "Active Jobs", value: "\(stats.activeJobs)", icon: "hammer", color: .orange)
            DSKPICard(title: "Pending Orders", value: "\(stats.pendingOrders)", icon: "cart", color: .purple)
            DSKPICard(title: "Low Stock", value: "\(stats.lowStockCount)", icon: "exclamationmark.triangle", color: stats.lowStockCount > 0 ? .red : .green)
        }
        .padding(.horizontal, DS.Space.lg)
    }

    // MARK: - Charts Section

    @ViewBuilder
    private var chartsSection: some View {
        VStack(spacing: DS.Space.md) {
            if !laborChartData.isEmpty {
                LaborHoursChart(data: laborChartData)
                    .padding(.horizontal, DS.Space.lg)
            }
            if !stockChartData.isEmpty {
                StockLevelChart(data: stockChartData)
                    .padding(.horizontal, DS.Space.lg)
            }
            if !spendingChartData.isEmpty {
                SpendingChart(data: spendingChartData)
                    .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    // MARK: - Alerts Content

    @ViewBuilder
    private var alertsContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
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
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.SemanticColor.success)
                    Text("No upcoming expiry alerts")
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
                .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    @ViewBuilder
    private func alertsSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .dsStyle(.sectionTitle)
            }

            ForEach(items, id: \.self) { item in
                HStack(spacing: DS.Space.sm) {
                    Circle()
                        .fill(DS.SemanticColor.tint(color))
                        .frame(width: 8, height: 8)
                    Text(item)
                        .dsStyle(.detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .padding(.horizontal, DS.Space.lg)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSSectionHeader(title: "Quick Actions")
                .padding(.horizontal, DS.Space.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.md) {
                    DSQuickActionButton(title: "Clock In", icon: "clock.badge.checkmark.fill", color: .green) {
                        navigateToModule("jobs")
                    }
                    DSQuickActionButton(title: "New Order", icon: "plus.circle.fill", color: .blue) {
                        navigateToModule("orders")
                    }
                    DSQuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange) {
                        navigateToModule("warehouse")
                    }
                    DSQuickActionButton(title: "Scan QR", icon: "qrcode.viewfinder", color: .purple) {
                        navigateToModule("warehouse")
                    }
                }
                .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    // MARK: - Daily Report

    @ViewBuilder
    private var dailyReportContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            // Overdue alert banner
            if overdueDeliveries > 0 {
                DSAlertBanner(
                    severity: .error,
                    title: "\(overdueDeliveries) overdue deliver\(overdueDeliveries == 1 ? "y" : "ies")",
                    message: "Immediate attention required"
                )
                .padding(.horizontal, DS.Space.lg)
            }

            // Pending Actions
            pendingActionsCard
                .padding(.horizontal, DS.Space.lg)

            // Today's Activity
            todayActivityCard
                .padding(.horizontal, DS.Space.lg)

            // Expected Deliveries
            expectedDeliveriesCard
                .padding(.horizontal, DS.Space.lg)

            // Budget Alerts
            if !budgetAlerts.isEmpty {
                budgetAlertsCard
                    .padding(.horizontal, DS.Space.lg)
            }

            // Live indicator
            HStack(spacing: DS.Space.xs) {
                Circle()
                    .fill(DS.SemanticColor.success)
                    .frame(width: 6, height: 6)
                Text("Live — updates every 60 seconds")
                    .dsStyle(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Space.sm)
        }
    }

    private var pendingActionsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pending Actions")
                    .dsStyle(.sectionTitle)
                Spacer()
                let total = pendingJPOs + pendingPOs + returnsToSort + overdueDeliveries
                Text(total > 0 ? "\(total)" : "All clear")
                    .dsStyle(.label)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xxxs + 1)
                    .background(Capsule().fill(DS.SemanticColor.tint(total > 0 ? DS.SemanticColor.warning : DS.SemanticColor.success)))
                    .foregroundStyle(total > 0 ? DS.SemanticColor.warning : DS.SemanticColor.success)
            }
            .padding(DS.Space.lg)

            VStack(spacing: 0) {
                pendingActionRow("JPOs awaiting approval", count: pendingJPOs, icon: "cart", urgent: false)
                Divider().padding(.leading, DS.Space.jumbo)
                pendingActionRow("POs to submit", count: pendingPOs, icon: "shippingbox", urgent: false)
                Divider().padding(.leading, DS.Space.jumbo)
                pendingActionRow("Returns to sort", count: returnsToSort, icon: "arrow.uturn.backward.circle", urgent: false)
                Divider().padding(.leading, DS.Space.jumbo)
                pendingActionRow("Overdue deliveries", count: overdueDeliveries, icon: "exclamationmark.triangle", urgent: true)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.md)
        }
        .dsCard()
    }

    private func pendingActionRow(_ label: String, count: Int, icon: String, urgent: Bool) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(urgent && count > 0 ? DS.SemanticColor.error : .secondary)
            Text(label)
                .dsStyle(.detail)
            Spacer()
            Text("\(count)")
                .dsStyle(.detail)
                .fontWeight(.bold)
                .foregroundStyle(
                    count > 0
                        ? (urgent ? DS.SemanticColor.error : DS.SemanticColor.warning)
                        : .secondary
                )
        }
        .padding(.vertical, DS.Space.xs)
        .opacity(count > 0 ? 1 : 0.5)
    }

    private var todayActivityCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Today's Activity")
                .dsStyle(.sectionTitle)

            HStack(spacing: DS.Space.md) {
                activityStat("Orders Created", value: todayCreatedOrders, color: .blue)
                activityStat("Items Received", value: todayReceivedItems, color: .green)
                activityStat("Returns", value: todayReturns, color: .purple)
            }
        }
        .padding(DS.Space.lg)
        .dsCard()
    }

    private func activityStat(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text("\(value)")
                .dsStyle(.kpiValue)
                .foregroundStyle(color)
            Text(label)
                .dsStyle(.label)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.SemanticColor.muted(color)))
    }

    private var expectedDeliveriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Expected Deliveries This Week")
                    .dsStyle(.sectionTitle)
                Spacer()
                if !expectedDeliveries.isEmpty {
                    Text("\(expectedDeliveries.count)")
                        .dsStyle(.label)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xxxs + 1)
                        .background(Capsule().fill(Color(.systemGray4)))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DS.Space.lg)

            if expectedDeliveries.isEmpty {
                Text("No deliveries expected this week.")
                    .dsStyle(.detail)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DS.Space.lg)
            } else {
                VStack(spacing: DS.Space.sm) {
                    ForEach(expectedDeliveries) { delivery in
                        HStack(spacing: DS.Space.md) {
                            Image(systemName: "truck.box")
                                .foregroundStyle(delivery.isOverdue ? DS.SemanticColor.error : .secondary)
                            VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                                Text("\(delivery.poNumber) — \(delivery.supplierName)")
                                    .dsStyle(.detail)
                                    .lineLimit(1)
                                Text("\(delivery.lineCount) item\(delivery.lineCount == 1 ? "" : "s")")
                                    .dsStyle(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: DS.Space.xxxs) {
                                Text(delivery.expectedDate)
                                    .dsStyle(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(delivery.isOverdue ? DS.SemanticColor.error : .secondary)
                                if delivery.isOverdue {
                                    Text("Overdue")
                                        .dsStyle(.label)
                                        .padding(.horizontal, DS.Space.xs)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(DS.SemanticColor.tint(DS.SemanticColor.error)))
                                        .foregroundStyle(DS.SemanticColor.error)
                                }
                            }
                        }
                        .padding(DS.Space.md - 2)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm)
                                .stroke(delivery.isOverdue ? DS.SemanticColor.error.opacity(0.3) : Color(.separator), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.md)
            }
        }
        .dsCard()
    }

    private var budgetAlertsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Budget Alerts")
                .dsStyle(.sectionTitle)
                .padding(DS.Space.lg)

            VStack(spacing: DS.Space.sm) {
                ForEach(budgetAlerts) { alert in
                    let alertColor = alert.pctUsed >= 100 ? DS.SemanticColor.error : DS.SemanticColor.warning
                    HStack(spacing: DS.Space.md) {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(alertColor)
                        VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                            Text(alert.jobName)
                                .dsStyle(.detail)
                                .lineLimit(1)
                            Text("$\(Int(alert.currentSpend)) of $\(Int(alert.budgetLimit))")
                                .dsStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(alert.pctUsed))%")
                            .dsStyle(.label)
                            .padding(.horizontal, DS.Space.sm)
                            .padding(.vertical, DS.Space.xxxs + 1)
                            .background(Capsule().fill(DS.SemanticColor.tint(alertColor)))
                            .foregroundStyle(alertColor)
                    }
                    .padding(DS.Space.md - 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm)
                            .stroke(alertColor.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.md)
        }
        .dsCard()
    }

    // MARK: - Navigation

    private func navigateToModule(_ moduleId: String) {
        NotificationCenter.default.post(
            name: .navigateToModule,
            object: nil,
            userInfo: ["moduleId": moduleId]
        )
    }

    // MARK: - Data Loading

    @Sendable
    private func loadData() async {
        isLoading = true
        loadError = nil
        do {
            guard let db = appCore.db else {
                await MainActor.run {
                    loadError = "Database not available"
                    isLoading = false
                }
                return
            }

            let cutoffDate = dashboardDateString(daysFromNow: 30)

            let result = try await db.writer.read { dbConnection -> DashboardLoadResult in
                // KPI counts
                let totalParts = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
                let activeJobs = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM jobs WHERE status IN ('active','in_progress') AND deleted_at IS NULL") ?? 0
                let pendingOrders = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM purchase_orders WHERE status IN ('pending','draft') AND deleted_at IS NULL") ?? 0
                let lowStockCount = try Int.fetchOne(dbConnection, sql: """
                    SELECT COUNT(*) FROM parts p
                    WHERE p.deleted_at IS NULL
                      AND p.min_stock_level > 0
                      AND (
                        SELECT COALESCE(SUM(se.quantity), 0)
                        FROM stock_entries se
                        WHERE se.part_id = p.id
                          AND se.deleted_at IS NULL
                      ) < p.min_stock_level
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

                let pJPOs = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM job_parts_orders WHERE status = 'submitted' AND deleted_at IS NULL") ?? 0
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
                           (SELECT COUNT(*) FROM po_line_items pl WHERE pl.po_id = po.id AND pl.deleted_at IS NULL) AS line_count,
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
                    SELECT * FROM (
                        SELECT j.id, j.job_name, j.budget_limit AS budget,
                               COALESCE(
                                 (SELECT SUM(le.regular_hours * COALESCE(u.pay_rate, 0))
                                  FROM labor_entries le
                                  LEFT JOIN users u ON u.id = le.user_id
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

            // Load chart data in background (non-blocking)
            await loadChartData()
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Loads chart data for the dashboard visualizations.
    @Sendable
    private func loadChartData() async {
        guard let db = appCore.db else { return }
        do {
            let charts = try await db.writer.read { conn -> DashboardChartData in
                // Labor hours for past 7 days
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEE"
                let isoFormatter = DateFormatter()
                isoFormatter.dateFormat = "yyyy-MM-dd"

                var laborDays: [LaborDayData] = []
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
                    laborDays.append(LaborDayData(
                        dayLabel: dayFormatter.string(from: date),
                        date: dateStr,
                        regularHours: regular,
                        overtimeHours: overtime
                    ))
                }

                // Top 8 parts by stock level (show low stock prominently)
                let stockRows = try Row.fetchAll(conn, sql: """
                    SELECT p.name,
                           COALESCE((SELECT SUM(se.quantity) FROM stock_entries se
                                     WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0) AS qty,
                           COALESCE(p.min_stock_level, 0) AS min_level
                    FROM parts p
                    WHERE p.deleted_at IS NULL AND p.min_stock_level > 0
                    ORDER BY (COALESCE((SELECT SUM(se.quantity) FROM stock_entries se
                              WHERE se.part_id = p.id AND se.deleted_at IS NULL), 0) * 1.0
                              / NULLIF(p.min_stock_level, 0)) ASC
                    LIMIT 8
                    """)
                let stockLevels = stockRows.map { row in
                    StockLevelData(
                        partName: String((row["name"] as String? ?? "").prefix(20)),
                        quantity: row["qty"] ?? 0,
                        minLevel: row["min_level"] ?? 0
                    )
                }

                // Spending breakdown (labor vs parts vs fuel)
                let laborSpend = try Double.fetchOne(conn, sql: """
                    SELECT COALESCE(SUM(le.regular_hours * COALESCE(u.pay_rate, 0)), 0)
                    FROM labor_entries le
                    LEFT JOIN users u ON u.id = le.user_id
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

                var spending: [SpendingCategory] = []
                if laborSpend > 0 { spending.append(SpendingCategory(name: "Labor", amount: laborSpend, color: .blue)) }
                if partsSpend > 0 { spending.append(SpendingCategory(name: "Parts", amount: partsSpend, color: .orange)) }
                if fuelSpend > 0 { spending.append(SpendingCategory(name: "Fuel", amount: fuelSpend, color: .green)) }

                return DashboardChartData(labor: laborDays, stock: stockLevels, spending: spending)
            }

            await MainActor.run {
                laborChartData = charts.labor
                stockChartData = charts.stock
                spendingChartData = charts.spending
            }
        } catch { print("[DashboardView] Chart data load failed: \(error)") }
    }
}

/// Format a date N days from now as "yyyy-MM-dd" — free function to avoid actor isolation.
private func dashboardDateString(daysFromNow days: Int) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
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



