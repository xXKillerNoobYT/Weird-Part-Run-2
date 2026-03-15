import SwiftUI
import WiredPartCore

/// Fleet dashboard page showing fleet-wide KPI cards.
///
/// Displays a grid of summary cards: Total Vehicles, Active Vehicles,
/// Maintenance Due, and Total Trailers. Uses FleetService.getFleetStats()
/// to fetch aggregate fleet data.
struct FleetDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var stats: FleetService.FleetStats?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if isLoading {
                    ProgressView("Loading fleet stats...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if let stats {
                    kpiCards(stats)
                } else {
                    emptyState
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fleet Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Overview of all vehicles and trailers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - KPI Cards

    private func kpiCards(_ stats: FleetService.FleetStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            kpiCard(
                title: "Total Vehicles",
                value: "\(stats.totalVehicles)",
                icon: "truck.box.fill",
                color: .blue
            )
            kpiCard(
                title: "Active",
                value: "\(stats.activeVehicles)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            kpiCard(
                title: "Maintenance Due",
                value: "\(stats.maintenanceDue)",
                icon: "wrench.and.screwdriver.fill",
                color: stats.maintenanceDue > 0 ? .orange : .secondary
            )
            kpiCard(
                title: "Total Trailers",
                value: "\(stats.totalTrailers)",
                icon: "shippingbox.fill",
                color: .purple
            )
        }
    }

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "truck.box")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No fleet data")
                .font(.headline)
            Text("Add vehicles to see fleet statistics.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            let service = FleetService(db: db)
            stats = try service.getFleetStats()
        } catch {
            print("[FleetDashboardPage] Load error: \(error)")
        }

        isLoading = false
    }
}
