import SwiftUI
import WiredPartCore

/// Profitability report page for iOS.
///
/// Displays a list of jobs with revenue, labor cost, material cost, profit,
/// and margin percentage. Uses `ReportsService.getProfitabilitySummary()`.
/// Supports pull-to-refresh and search filtering.
struct IOSProfitabilityPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var rows: [ReportsService.JobProfitRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var activeSheet: ActiveSheet?
    @State private var dateRange: ReportDateRange = .thisWeek
    @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
    @State private var customEnd: Date = Date()

    private enum ActiveSheet: Identifiable { case help; var id: String { "help" } }

    private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
    private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

    var body: some View {
        VStack(spacing: 0) {
            StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)
            profitabilityContent
        }
            .navigationTitle("Profitability")
            .reportExportToolbar(
                title: "Profitability",
                columns: ["Job", "Revenue", "Labor", "Material", "Profit", "Margin"],
                rows: rows.map { [$0.jobName, String(format: "$%.2f", $0.revenue),
                                  String(format: "$%.2f", $0.laborCost),
                                  String(format: "$%.2f", $0.materialCost),
                                  String(format: "$%.2f", $0.profit),
                                  String(format: "%.1f%%", $0.margin)] }
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .help } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("Help")
                }
            }
            .sheet(item: $activeSheet) { _ in
                PageHelpSheet(title: "Profitability Help", sections: [
                    ("What This Page Does", "Shows how much profit each job is making. For every job, you see revenue, labor cost, material cost, total profit, and margin percentage. Green means healthy, red means losing money."),
                    ("How to Use It", "Scroll through the list to see all jobs. Use the search bar to find a specific job. The margin badge on the right gives you a quick color-coded indicator: green is 20%+, orange is break-even, red is a loss."),
                    ("Tips", "Focus on jobs with orange or red margins first. If a job's labor cost is unusually high, check if overtime is driving it up. Export this report to share with management during job reviews.")
                ])
            }
            .searchable(text: $searchText, prompt: "Search jobs...")
            .refreshable { loadData() }
            .task { loadData() }
            .onChange(of: dateRange) { loadData() }
            .onChange(of: customStart) { loadData() }
            .onChange(of: customEnd) { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var profitabilityContent: some View {
        if isLoading {
            ProgressView("Loading profitability...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ErrorStateView(message: error) { loadData() }
        } else if filteredRows.isEmpty {
            EmptyStateView(
                icon: "chart.line.uptrend.xyaxis",
                title: "No Data",
                message: "No profitability data available."
            )
        } else {
            List(filteredRows, id: \.id) { row in
                profitRow(row)
            }
            .listStyle(.insetGrouped)
        }
    }

    private var filteredRows: [ReportsService.JobProfitRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.lowercased()
        return rows.filter { $0.jobName.lowercased().contains(query) }
    }

    // MARK: - Row

    private func profitRow(_ row: ReportsService.JobProfitRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.jobName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                marginBadge(row.margin)
            }

            HStack(spacing: 16) {
                metricLabel(title: "Revenue", value: formatCurrency(row.revenue), color: .green)
                metricLabel(title: "Labor", value: formatCurrency(row.laborCost), color: .orange)
                metricLabel(title: "Material", value: formatCurrency(row.materialCost), color: .blue)
            }

            HStack {
                Label("Profit", systemImage: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(row.profit))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(row.profit >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Metric Label

    private func metricLabel(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    // MARK: - Badge

    private func marginBadge(_ margin: Double) -> some View {
        let color: Color = margin >= 20 ? .green : margin >= 0 ? .orange : .red
        return Text(String(format: "%.1f%%", margin))
            .font(.system(.caption2, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    // MARK: - Helpers

    private func formatCurrency(_ value: Double) -> String {
        Formatters.formatCurrencyWhole(value)
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let service = appCore.reportsService else {
            isLoading = false
            loadError = "Reports service unavailable"
            return
        }
        isLoading = rows.isEmpty
        do {
            rows = try service.getProfitabilitySummary()
        } catch {
            loadError = userFriendlyError(error, context: "load reports")
        }
        isLoading = false
    }
}
