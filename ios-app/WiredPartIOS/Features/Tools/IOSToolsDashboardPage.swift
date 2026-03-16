import SwiftUI
import WiredPartCore

/// Tools dashboard page for iOS.
///
/// Displays KPI cards showing total tools, checked out count, tools
/// needing maintenance, and available count. Also shows recent checkout
/// activity. Uses `ToolsService` for data retrieval with pull-to-refresh.
struct IOSToolsDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var stats: ToolsService.ToolsStats?
    @State private var recentCheckouts: [ToolsService.CheckoutRow] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            dashboardContent
                .navigationTitle("Tools Overview")
                .refreshable { loadData() }
                .task { loadData() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var dashboardContent: some View {
        if isLoading {
            ProgressView("Loading tools data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let stats {
            ScrollView {
                VStack(spacing: 16) {
                    kpiGrid(stats)
                    recentSection
                }
                .padding()
            }
        } else {
            ContentUnavailableView {
                Label("No Tools", systemImage: "wrench.and.screwdriver")
            } description: {
                Text("No tools data available.")
            }
        }
    }

    // MARK: - KPI Grid

    private func kpiGrid(_ stats: ToolsService.ToolsStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            kpiCard(
                title: "Total Tools",
                value: "\(stats.totalTools)",
                icon: "wrench.and.screwdriver.fill",
                color: .blue
            )
            kpiCard(
                title: "Checked Out",
                value: "\(stats.checkedOut)",
                icon: "arrow.up.right.circle.fill",
                color: .orange
            )
            kpiCard(
                title: "Maintenance",
                value: "\(stats.inMaintenance)",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
            kpiCard(
                title: "Kits",
                value: "\(stats.totalKits)",
                icon: "suitcase.fill",
                color: .green
            )
        }
    }

    // MARK: - KPI Card

    private func kpiCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Recent Checkouts

    @ViewBuilder
    private var recentSection: some View {
        if !recentCheckouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Activity")
                    .font(.headline)
                    .padding(.top, 4)

                ForEach(recentCheckouts, id: \.id) { checkout in
                    recentRow(checkout)
                    if checkout.id != recentCheckouts.last?.id {
                        Divider()
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private func recentRow(_ checkout: ToolsService.CheckoutRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: checkout.returnedAt == nil ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill")
                .foregroundStyle(checkout.returnedAt == nil ? .blue : .green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(checkout.toolName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(checkout.checkedOutByName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatDate(checkout.checkedOutAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func formatDate(_ dateString: String) -> String {
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short

        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        isoFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = isoFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }
        if dateString.count >= 10 {
            return String(dateString.prefix(10))
        }
        return dateString
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.toolsService else { return }
        isLoading = stats == nil
        do {
            stats = try service.getToolsStats()
            recentCheckouts = try service.listCheckouts(active: false)
        } catch {
            let msg = String(describing: error)
            if !msg.contains("no such table") {
                print("[IOSToolsDashboardPage] Load error: \(error)")
            }
        }
        isLoading = false
    }
}
