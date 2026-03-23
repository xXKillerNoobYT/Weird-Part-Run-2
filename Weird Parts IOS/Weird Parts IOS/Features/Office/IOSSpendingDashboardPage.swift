import SwiftUI
import WiredPartCore

/// Office-level spending dashboard.
///
/// Shows aggregate spending data across all jobs: total costs, parts spend,
/// labor costs, budget status. Gated by `show_dollar_values` permission.
struct IOSSpendingDashboardPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var totalJobs = 0
    @State private var totalPartsCost: Double = 0
    @State private var totalLaborHours: Double = 0
    @State private var activeJobCount = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    SpendCard(title: "Parts Cost", value: formatCurrency(totalPartsCost), icon: "wrench.and.screwdriver", color: .blue)
                    SpendCard(title: "Labor Hours", value: String(format: "%.1f hrs", totalLaborHours), icon: "clock.fill", color: .green)
                    SpendCard(title: "Active Jobs", value: "\(activeJobCount)", icon: "hammer.fill", color: .orange)
                    SpendCard(title: "Total Jobs", value: "\(totalJobs)", icon: "folder.fill", color: .purple)
                }
                .padding(.horizontal)

                // Details Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Spending Breakdown")
                        .font(.headline)
                        .padding(.horizontal)

                    VStack(spacing: 8) {
                        SpendingRow(label: "Total Parts Cost", value: formatCurrency(totalPartsCost), color: .blue)
                        SpendingRow(label: "Total Labor Hours", value: String(format: "%.1f", totalLaborHours), color: .green)
                        SpendingRow(label: "Active Projects", value: "\(activeJobCount)", color: .orange)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)

                // Charts placeholder
                EmptyStateView(
                    icon: "chart.bar",
                    title: "No Spending Data",
                    message: "Spending charts will appear once orders have cost data."
                )
                .padding(.vertical, 16)
            }
            .padding(.vertical)
        }
        .navigationTitle("Spending Dashboard")
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
        guard let jobsService = appCore.jobsService else {
            isLoading = false
            loadError = "Jobs service is not available."
            return
        }
        isLoading = totalJobs == 0
        loadError = nil
        do {
            let stats = try jobsService.getJobStats()
            totalJobs = stats.total
            activeJobCount = stats.active

            // Aggregate from dashboard KPIs
            let kpis = try jobsService.getJobsDashboardKPIs()
            totalLaborHours = kpis.todayLaborHours

            // Parts cost: sum of (qty_consumed * unit_cost_at_consume) across all jobs
            totalPartsCost = try jobsService.getTotalPartsCost()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

// MARK: - Spend Card

private struct SpendCard: View {
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
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .dsCard()
    }
}

// MARK: - Spending Row

private struct SpendingRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(12)
        .dsCard()
    }
}
