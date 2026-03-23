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

    var body: some View {
        profitabilityContent
            .navigationTitle("Profitability")
            .searchable(text: $searchText, prompt: "Search jobs...")
            .refreshable { loadData() }
            .task { loadData() }
    }

    // MARK: - Content

    @ViewBuilder
    private var profitabilityContent: some View {
        if isLoading {
            ProgressView("Loading profitability...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = loadError {
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if filteredRows.isEmpty {
            ContentUnavailableView {
                Label("No Data", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("No profitability data available.")
            }
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
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
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}
