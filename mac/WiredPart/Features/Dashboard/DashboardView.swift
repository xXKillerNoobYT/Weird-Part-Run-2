import SwiftUI
import GRDB
import WiredPartCore

/// Native macOS Dashboard page.
///
/// Shows a greeting, 4 KPI cards, certification expiry alerts,
/// vehicle expiry alerts, and a quick-actions grid.
/// Data loads on appear and auto-refreshes every 60 seconds.
struct DashboardView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var totalParts: Int = 0
    @State private var activeJobs: Int = 0
    @State private var pendingOrders: Int = 0
    @State private var lowStockCount: Int = 0
    @State private var certAlerts: [CertAlert] = []
    @State private var vehicleAlerts: [VehicleAlert] = []
    @State private var isLoading: Bool = true

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greeting
                kpiCards
                alertSections
                quickActions
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
