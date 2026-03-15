import SwiftUI
import WiredPartCore

/// Job profitability page showing revenue, costs, and margins per job.
///
/// Displays a table of jobs with revenue, labor cost, material cost,
/// profit, and margin percentage columns. Uses color coding to
/// highlight positive and negative margins.
struct ProfitabilityPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - Data State

    @State private var jobs: [ReportsService.JobProfitRow] = []
    @State private var isLoading = true

    // MARK: - Sorting

    @State private var sortOrder = [KeyPathComparator(\ReportsService.JobProfitRow.profit, order: .reverse)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tableContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadData() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profitability")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("\(jobs.count) job\(jobs.count == 1 ? "" : "s") · Total profit: \(String(format: "$%.2f", totalProfit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                loadData()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var totalProfit: Double {
        jobs.reduce(0) { $0 + $1.profit }
    }

    // MARK: - Table

    @ViewBuilder
    private var tableContent: some View {
        if isLoading {
            ProgressView("Loading profitability data...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if jobs.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No profitability data")
                    .font(.headline)
                Text("Add jobs with billing rates and labor entries to see profitability.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(sortedJobs, sortOrder: $sortOrder) {
                TableColumn("Job", value: \.jobName) { job in
                    Text(job.jobName)
                        .fontWeight(.medium)
                }
                .width(min: 150, ideal: 220)

                TableColumn("Revenue", value: \.revenue) { job in
                    Text(String(format: "$%.2f", job.revenue))
                        .font(.callout)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Labor Cost", value: \.laborCost) { job in
                    Text(String(format: "$%.2f", job.laborCost))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Material Cost", value: \.materialCost) { job in
                    Text(String(format: "$%.2f", job.materialCost))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Profit", value: \.profit) { job in
                    Text(String(format: "$%.2f", job.profit))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(job.profit >= 0 ? .green : .red)
                }
                .width(min: 80, ideal: 110)

                TableColumn("Margin", value: \.margin) { job in
                    Text(String(format: "%.1f%%", job.margin))
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(marginColor(job.margin))
                }
                .width(min: 70, ideal: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var sortedJobs: [ReportsService.JobProfitRow] {
        jobs.sorted(using: sortOrder)
    }

    // MARK: - Helpers

    private func marginColor(_ margin: Double) -> Color {
        if margin >= 20 { return .green }
        if margin >= 0 { return .orange }
        return .red
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let db = appCore.db else { return }
        isLoading = true

        do {
            let service = ReportsService(db: db)
            jobs = try service.getProfitabilitySummary()
        } catch {
            print("[ProfitabilityPage] Load error: \(error)")
        }

        isLoading = false
    }
}
