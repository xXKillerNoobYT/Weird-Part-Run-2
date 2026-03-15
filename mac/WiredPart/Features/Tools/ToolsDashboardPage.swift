import SwiftUI
import WiredPartCore

/// Tools dashboard page showing aggregate tool statistics.
///
/// Displays 4 KPI cards: Total Tools, Checked Out, In Maintenance,
/// and Total Kits. Uses the ToolsService.getToolsStats() method
/// to fetch aggregate counts from the database.
struct ToolsDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var stats: ToolsService.ToolsStats?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if isLoading {
                    ProgressView("Loading tools stats...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else if let stats {
                    kpiCards(stats)
                    summarySection(stats)
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
                Text("Tools Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Overview of tool inventory and status")
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

    private func kpiCards(_ stats: ToolsService.ToolsStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            kpiCard(
                title: "Total Tools",
                value: "\(stats.totalTools)",
                icon: "wrench.and.screwdriver.fill",
                color: .blue
            )
            kpiCard(
                title: "Checked Out",
                value: "\(stats.checkedOut)",
                icon: "arrow.right.circle.fill",
                color: stats.checkedOut > 0 ? .orange : .green
            )
            kpiCard(
                title: "In Maintenance",
                value: "\(stats.inMaintenance)",
                icon: "gear.badge.xmark",
                color: stats.inMaintenance > 0 ? .red : .green
            )
            kpiCard(
                title: "Total Kits",
                value: "\(stats.totalKits)",
                icon: "briefcase.fill",
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
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Summary Section

    private func summarySection(_ stats: ToolsService.ToolsStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow(
                        label: "Available tools",
                        value: "\(stats.totalTools - stats.checkedOut - stats.inMaintenance)",
                        icon: "checkmark.circle",
                        color: .green
                    )
                    Divider()
                    summaryRow(
                        label: "Tools currently checked out",
                        value: "\(stats.checkedOut)",
                        icon: "arrow.right.circle",
                        color: .orange
                    )
                    Divider()
                    summaryRow(
                        label: "Tools under maintenance",
                        value: "\(stats.inMaintenance)",
                        icon: "gear.badge.xmark",
                        color: .red
                    )
                    Divider()
                    summaryRow(
                        label: "Utilization rate",
                        value: stats.totalTools > 0
                            ? String(format: "%.0f%%", Double(stats.checkedOut) / Double(stats.totalTools) * 100)
                            : "N/A",
                        icon: "chart.pie",
                        color: .blue
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func summaryRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No tools data")
                .font(.headline)
            Text("Register tools to see dashboard statistics.")
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
            let service = ToolsService(db: db)
            stats = try service.getToolsStats()
        } catch {
            print("[ToolsDashboardPage] Load error: \(error)")
        }

        isLoading = false
    }
}
