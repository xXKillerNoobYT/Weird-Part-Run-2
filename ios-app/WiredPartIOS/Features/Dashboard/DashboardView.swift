import SwiftUI
import GRDB
import WiredPartCore

/// Main dashboard view showing KPI cards, certification alerts,
/// and vehicle/maintenance alerts.
///
/// Uses AppCore to query the database directly for summary statistics.
/// All data is fetched on appear and can be refreshed with pull-to-refresh.
struct DashboardView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var stats = DashboardStats()
    @State private var certAlerts: [CertAlert] = []
    @State private var vehicleAlerts: [VehicleAlert] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Welcome header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome back, \(appCore.currentUser?.displayName ?? "User")")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(formattedDate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    // KPI Cards
                    kpiSection

                    // Certification Alerts
                    if !certAlerts.isEmpty {
                        alertsSection(
                            title: "Certification Alerts",
                            icon: "exclamationmark.shield.fill",
                            color: .orange,
                            items: certAlerts.map { "\($0.userName): \($0.certName) expires \($0.expiryDate)" }
                        )
                    }

                    // Vehicle Alerts
                    if !vehicleAlerts.isEmpty {
                        alertsSection(
                            title: "Vehicle Alerts",
                            icon: "car.badge.gearshape.fill",
                            color: .red,
                            items: vehicleAlerts.map { "\($0.vehicleNumber): \($0.alertMessage)" }
                        )
                    }

                    // Quick Actions
                    quickActionsSection
                }
            }
            .padding(.vertical)
        }
        .refreshable { await loadData() }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .task { await loadData() }
    }

    // MARK: - KPI Cards

    @ViewBuilder
    private var kpiSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            KPICard(title: "Active Jobs", value: "\(stats.activeJobs)", icon: "hammer.fill", color: .blue)
            KPICard(title: "Open Orders", value: "\(stats.openOrders)", icon: "cart.fill", color: .green)
            KPICard(title: "Clocked In", value: "\(stats.clockedIn)", icon: "clock.fill", color: .orange)
            KPICard(title: "Active Vehicles", value: "\(stats.activeVehicles)", icon: "car.fill", color: .purple)
            KPICard(title: "Total Parts", value: "\(stats.totalParts)", icon: "wrench.and.screwdriver.fill", color: .teal)
            KPICard(title: "Active Users", value: "\(stats.activeUsers)", icon: "person.2.fill", color: .indigo)
        }
        .padding(.horizontal)
    }

    // MARK: - Alerts Section

    @ViewBuilder
    private func alertsSection(title: String, icon: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(items, id: \.self) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: Date())
    }

    @Sendable
    private func loadData() async {
        isLoading = true
        do {
            let db = appCore.db!

            // Fetch KPI counts via raw SQL
            let newStats = try await db.writer.read { dbConnection -> DashboardStats in
                let jobs = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM jobs WHERE status IN ('active','in_progress') AND deleted_at IS NULL") ?? 0
                let orders = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM purchase_orders WHERE status IN ('draft','submitted','approved','ordered') AND deleted_at IS NULL") ?? 0
                let clocked = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM labor_entries WHERE clock_out IS NULL AND deleted_at IS NULL") ?? 0
                let vehicles = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM vehicles WHERE status = 'active' AND deleted_at IS NULL") ?? 0
                let parts = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL") ?? 0
                let users = try Int.fetchOne(dbConnection, sql: "SELECT COUNT(*) FROM users WHERE is_active = 1 AND deleted_at IS NULL") ?? 0
                return DashboardStats(
                    activeJobs: jobs,
                    openOrders: orders,
                    clockedIn: clocked,
                    activeVehicles: vehicles,
                    totalParts: parts,
                    activeUsers: users
                )
            }

            // Fetch certification alerts (expiring within 30 days)
            let certs = try await db.writer.read { dbConnection -> [CertAlert] in
                let rows = try Row.fetchAll(dbConnection, sql: """
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
                return rows.map { row in
                    CertAlert(
                        userName: row["display_name"] as String,
                        certName: row["cert_name"] as String,
                        expiryDate: row["expiry_date"] as String
                    )
                }
            }

            // Fetch vehicle alerts (insurance/registration expiring within 30 days)
            // Pre-compute cutoff date outside the sendable closure
            let cutoffDate = dashboardDateString(daysFromNow: 30)
            let vAlerts = try await db.writer.read { dbConnection -> [VehicleAlert] in
                let rows = try Row.fetchAll(dbConnection, sql: """
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
                return rows.compactMap { row -> VehicleAlert? in
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
            }

            await MainActor.run {
                stats = newStats
                certAlerts = certs
                vehicleAlerts = vAlerts
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

private struct DashboardStats {
    var activeJobs = 0
    var openOrders = 0
    var clockedIn = 0
    var activeVehicles = 0
    var totalParts = 0
    var activeUsers = 0
}

private struct CertAlert {
    let userName: String
    let certName: String
    let expiryDate: String
}

private struct VehicleAlert {
    let vehicleNumber: String
    let alertMessage: String
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
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.controlBackgroundColor))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
