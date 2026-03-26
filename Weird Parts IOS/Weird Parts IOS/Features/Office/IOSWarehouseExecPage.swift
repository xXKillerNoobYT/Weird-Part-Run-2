import SwiftUI
import WiredPartCore

/// Office-level warehouse execution dashboard.
///
/// Provides a high-level overview of warehouse operations for managers:
/// pending movements, low stock alerts, recent receiving sessions,
/// audit schedule. Gated by `manage_warehouse` permission.
struct IOSWarehouseExecPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - ActiveSheet

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var totalStock = 0
    @State private var shortfallCount = 0
    @State private var todayMovements = 0
    @State private var pendingStagingCount = 0
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // KPI Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    KPICard(title: "Low Stock", value: "\(shortfallCount)", icon: "exclamationmark.triangle.fill", color: .orange)
                    KPICard(title: "Today Moves", value: "\(todayMovements)", icon: "arrow.left.arrow.right", color: .blue)
                    KPICard(title: "Total Stock", value: "\(totalStock)", icon: "shippingbox.fill", color: .green)
                    KPICard(title: "Pending Stage", value: "\(pendingStagingCount)", icon: "tray.2.fill", color: .purple)
                }
                .padding(.horizontal)

                // Quick Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Actions")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        Button {
                            NotificationCenter.default.post(
                                name: .navigateToModule,
                                object: nil,
                                userInfo: ["moduleId": "warehouse", "tabId": "movements"]
                            )
                        } label: {
                            QuickActionRow(icon: "arrow.left.arrow.right", title: "New Movement", subtitle: "Transfer parts between locations")
                        }
                        .buttonStyle(.plain)
                        .hideWithoutPermission("manage_warehouse")

                        Button {
                            NotificationCenter.default.post(
                                name: .navigateToModule,
                                object: nil,
                                userInfo: ["moduleId": "orders", "tabId": "receiving"]
                            )
                        } label: {
                            QuickActionRow(icon: "shippingbox.fill", title: "Start Receiving", subtitle: "Receive incoming shipments")
                        }
                        .buttonStyle(.plain)
                        .hideWithoutPermission("manage_warehouse")

                        Button {
                            NotificationCenter.default.post(
                                name: .navigateToModule,
                                object: nil,
                                userInfo: ["moduleId": "warehouse", "tabId": "audit"]
                            )
                        } label: {
                            QuickActionRow(icon: "checkmark.shield.fill", title: "Start Audit", subtitle: "Begin a stock count audit")
                        }
                        .buttonStyle(.plain)
                        .hideWithoutPermission("perform_audit")
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
        .navigationTitle("Warehouse Exec")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .help:
                PageHelpSheet(
                    title: "Warehouse Executive Help",
                    sections: [
                        ("Overview", "High-level warehouse operations dashboard for managers. See pending movements, low stock alerts, receiving sessions, and audit schedules."),
                        ("KPIs", "Cards show total stock units, shortfalls, today's movements, and pending approvals. Tap for details."),
                        ("Quick Actions", "Use the action buttons to navigate directly to movements, receiving, audits, or settings.")
                    ]
                )
            }
        }
        .refreshable { loadData() }
        .task { loadData() }
        .overlay {
            if isLoading {
                ProgressView()
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            }
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let service = appCore.warehouseService else {
            isLoading = false
            loadError = "Warehouse service is not available."
            return
        }
        isLoading = totalStock == 0 && todayMovements == 0
        loadError = nil
        do {
            let dashboard = try service.getDashboardKPIs()
            shortfallCount = dashboard.kpis.shortfallCount
            todayMovements = dashboard.kpis.todayMovements
            totalStock = dashboard.kpis.totalStock
            pendingStagingCount = dashboard.pendingStagingCount
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - KPI Card

private struct KPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .dsCard()
    }
}

// MARK: - Quick Action Row

private struct QuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .dsCard()
    }
}
