import SwiftUI
import WiredPartCore

/// Fleet dashboard page for iOS.
///
/// Displays 4 KPI cards (total vehicles, active, maintenance due, total trailers)
/// and a recent maintenance activity feed. Uses FleetService.getFleetStats()
/// for KPIs and FleetService.listMaintenanceRecords(limit: 5) for activity.
struct IOSFleetDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stats: FleetService.FleetStats?
    @State private var recentMaintenance: [FleetService.MaintenanceRow] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading fleet dashboard...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadData() }
            } else {
                dashboardContent
            }
        }
        .navigationTitle("Fleet Dashboard")
        .refreshable { loadData() }
        #if os(iOS)
        .background(DS.Background.page)
        #endif
        .task { loadData() }
    }

    // MARK: - Dashboard Content

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                kpiSection
                recentActivitySection
            }
            .padding()
        }
    }

    // MARK: - KPI Cards

    @ViewBuilder
    private var kpiSection: some View {
        let current = stats ?? FleetService.FleetStats(
            totalVehicles: 0, activeVehicles: 0, maintenanceDue: 0, totalTrailers: 0
        )

        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ], spacing: 12) {
            kpiCard(
                title: "Total Vehicles",
                value: "\(current.totalVehicles)",
                icon: "car.fill",
                color: .blue
            )
            kpiCard(
                title: "Active",
                value: "\(current.activeVehicles)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            kpiCard(
                title: "Maintenance Due",
                value: "\(current.maintenanceDue)",
                icon: "wrench.and.screwdriver.fill",
                color: current.maintenanceDue > 0 ? .orange : .green
            )
            kpiCard(
                title: "Total Trailers",
                value: "\(current.totalTrailers)",
                icon: "shippingbox.fill",
                color: .purple
            )
        }
    }

    @ViewBuilder
    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    // MARK: - Recent Maintenance Activity

    @ViewBuilder
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Maintenance")
                .font(.headline)
                .padding(.horizontal, 4)

            if recentMaintenance.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No recent maintenance")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                #if os(iOS)
                .background(Color(.secondarySystemGroupedBackground))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMaintenance.enumerated()), id: \.element.id) { index, record in
                        maintenanceActivityRow(record)

                        if index < recentMaintenance.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                #if os(iOS)
                .background(Color(.secondarySystemGroupedBackground))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func maintenanceActivityRow(_ record: FleetService.MaintenanceRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.vehicleName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let typeName = record.maintenanceTypeName {
                        Text(typeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let performer = record.performedByName {
                        Text("by \(performer)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let cost = record.cost {
                    Text(String(format: "$%.2f", cost))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(String(record.performedAt.prefix(10)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.fleetService else { return }
        isLoading = stats == nil && recentMaintenance.isEmpty
        loadError = nil

        do {
            stats = try service.getFleetStats()
            recentMaintenance = try service.listMaintenanceRecords(limit: 5)
        } catch {
            loadError = error.localizedDescription
        }

        isLoading = false
    }
}
