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
    @State private var loadError: String?
    @State private var activeSheet: ActiveSheet?

    private let recentActivityLimit = 10

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(pageId: "tools-dashboard")
            dashboardContent
        }
            .task { appCore.onboardingManager?.markCompleted("tools-dashboard-view") }
            .navigationTitle("Tools Overview")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { _ in
                PageHelpSheet(
                    title: "Tools Overview Help",
                    sections: [
                        ("What This Page Does", "The Tools Overview is your at-a-glance dashboard for all company tools. It shows four key metrics: total tools in the system, how many are currently checked out, how many are in maintenance, and how many tool kits exist."),
                        ("KPI Cards", "Each card at the top summarizes a key number. Blue is total tools, orange is checked out, red is in maintenance, and green is total kits. Tap pull-to-refresh to update these numbers."),
                        ("Recent Activity", "Below the cards you will see the latest checkout and return activity. Each row shows the tool name, who checked it out, and the date. Blue arrows mean checked out, green arrows mean returned."),
                        ("Tips", "Pull down anywhere on the page to refresh the data. If you see a high number of tools in maintenance, check the Maintenance tab for details.")
                    ]
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .refreshable { await loadData() }
            .task { await loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var dashboardContent: some View {
        if isLoading {
            ProgressView("Loading tools data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { Task { await loadData() } }
        } else if let stats {
            ScrollView {
                VStack(spacing: 16) {
                    kpiGrid(stats)
                    recentSection
                }
                .padding()
            }
        } else {
            EmptyStateView(
                icon: "wrench.and.screwdriver",
                title: "No Tools",
                message: "No tools data available."
            )
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
                    .accessibilityHidden(true)
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
                .accessibilityLabel(checkout.returnedAt == nil ? "Status: Checked out" : "Status: Returned")

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
        Formatters.formatSQLiteDate(dateString)
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let service = appCore.toolsService else {
            isLoading = false
            loadError = "Tools service unavailable"
            return
        }
        isLoading = stats == nil
        do {
            stats = try service.getToolsStats()
            recentCheckouts = try service.listCheckouts(active: false, limit: recentActivityLimit)
        } catch {
            loadError = userFriendlyError(error, context: "load tools dashboard")
        }
        isLoading = false
    }
}
