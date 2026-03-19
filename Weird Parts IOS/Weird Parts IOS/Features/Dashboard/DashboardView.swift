import SwiftUI
import Charts
import Combine
import GRDB
import WiredPartCore

/// Main dashboard view with KPI cards, charts, alerts, and quick actions.
///
/// Sub-pages (QR Scanner, Clock In/Out, Daily Report) are pushed via NavigationStack.
/// Uses AppCore to query the database directly for summary statistics.
/// All data is fetched on appear, supports pull-to-refresh, and auto-refreshes every 60s.
struct DashboardView: View {
    @EnvironmentObject private var appCore: AppCore

    // KPI + alerts state
    @State private var stats = DashboardStats()
    @State private var certAlerts: [CertAlert] = []
    @State private var vehicleAlerts: [VehicleAlert] = []

    // Charts data
    @State private var laborChartData: [LaborDayData] = []
    @State private var stockChartData: [StockLevelData] = []
    @State private var spendingChartData: [SpendingCategory] = []

    // KPI detail sheet
    @State private var activeKPIDetail: KPIDetailType?

    // Dashboard sub-page navigation
    enum DashboardDestination: Hashable {
        case scanner
        case clock
        case dailyReport
    }

    @State private var isLoading = true
    @State private var loadError: String?

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    // Greeting
                    greeting
                        .padding(.horizontal, DS.Space.lg)

                    if isLoading {
                        DSLoadingState()
                            .padding(.top, DS.Space.jumbo)
                    } else if let error = loadError {
                        ErrorStateView(message: error) { Task { await loadData() } }
                            .padding(.top, DS.Space.xl)
                    } else {
                        kpiSection
                        chartsSection
                        alertsContent
                        quickActionsSection
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
            .sheet(item: $activeKPIDetail) { detail in
                KPIDetailSheet(type: detail)
                    .environmentObject(appCore)
            }
            .navigationDestination(for: DashboardDestination.self) { dest in
                switch dest {
                case .scanner:
                    IOSDashboardQRScannerPage()
                case .clock:
                    IOSClockPage()
                case .dailyReport:
                    DashboardDailyReportPage()
                }
            }
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
        let twoColumns = [
            GridItem(.flexible(), spacing: DS.Space.md),
            GridItem(.flexible(), spacing: DS.Space.md),
        ]
        VStack(spacing: DS.Space.md) {
            // Row 1: Part Types + Total Stock
            LazyVGrid(columns: twoColumns, spacing: DS.Space.md) {
                DSKPICard(title: "Part Types", value: "\(stats.partTypes)", icon: "list.clipboard", color: .blue) {
                    activeKPIDetail = .partTypes
                }
                DSKPICard(title: "Total Stock", value: "\(stats.totalStock)", icon: "shippingbox.fill", color: .teal) {
                    activeKPIDetail = .totalStock
                }
            }
            // Row 2: Active Jobs + Pending Orders
            LazyVGrid(columns: twoColumns, spacing: DS.Space.md) {
                DSKPICard(title: "Active Jobs", value: "\(stats.activeJobs)", icon: "hammer", color: .orange) {
                    activeKPIDetail = .activeJobs
                }
                DSKPICard(title: "Pending Orders", value: "\(stats.pendingOrders)", icon: "cart", color: .purple) {
                    activeKPIDetail = .pendingOrders
                }
            }
            // Row 3: Low Stock (full width)
            DSKPICard(title: "Low Stock", value: "\(stats.lowStockCount)", icon: "exclamationmark.triangle", color: stats.lowStockCount > 0 ? .red : .green) {
                activeKPIDetail = .lowStock
            }
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
                    NavigationLink(value: DashboardDestination.scanner) {
                        DSQuickActionButton(title: "Scan QR", icon: "qrcode.viewfinder", color: .purple)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: DashboardDestination.clock) {
                        DSQuickActionButton(title: "Clock In", icon: "clock.badge.checkmark.fill", color: .green)
                    }
                    .buttonStyle(.plain)

                    NavigationLink(value: DashboardDestination.dailyReport) {
                        DSQuickActionButton(title: "Daily Report", icon: "doc.text.magnifyingglass", color: .indigo)
                    }
                    .buttonStyle(.plain)

                    DSQuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange) {
                        navigateToModule("warehouse")
                    }
                    DSQuickActionButton(title: "New Order", icon: "plus.circle.fill", color: .blue) {
                        navigateToModule("orders")
                    }
                }
                .padding(.horizontal, DS.Space.lg)
            }
        }
    }

    // Daily Report is now a separate sub-page: DashboardDailyReportPage

    // Daily report cards (pendingActions, todayActivity, expectedDeliveries, budgetAlerts)
    // are now in DashboardDailyReportPage.swift

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
                        SELECT COALESCE(SUM(s.qty), 0)
                        FROM stock s
                        WHERE s.part_id = p.id
                          AND s.deleted_at IS NULL
                      ) < p.min_stock_level
                    """) ?? 0

                // Total physical stock units across all locations
                let totalStock = try Int.fetchOne(dbConnection, sql: "SELECT COALESCE(SUM(qty), 0) FROM stock WHERE deleted_at IS NULL") ?? 0

                let newStats = DashboardStats(
                    partTypes: totalParts,
                    totalStock: totalStock,
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

                return DashboardLoadResult(
                    stats: newStats,
                    certAlerts: certs,
                    vehicleAlerts: vAlerts
                )
            }

            await MainActor.run {
                stats = result.stats
                certAlerts = result.certAlerts
                vehicleAlerts = result.vehicleAlerts
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
                           COALESCE((SELECT SUM(s.qty) FROM stock s
                                     WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) AS qty,
                           COALESCE(p.min_stock_level, 0) AS min_level
                    FROM parts p
                    WHERE p.deleted_at IS NULL AND p.min_stock_level > 0
                    ORDER BY (COALESCE((SELECT SUM(s.qty) FROM stock s
                              WHERE s.part_id = p.id AND s.deleted_at IS NULL), 0) * 1.0
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
    var partTypes = 0
    var totalStock = 0
    var activeJobs = 0
    var pendingOrders = 0
    var lowStockCount = 0
}

/// Result object to transfer all data out of the database read closure.
private struct DashboardLoadResult: Sendable {
    let stats: DashboardStats
    let certAlerts: [CertAlert]
    let vehicleAlerts: [VehicleAlert]
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




