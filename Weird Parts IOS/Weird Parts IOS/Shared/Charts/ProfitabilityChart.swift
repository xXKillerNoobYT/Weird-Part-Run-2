import SwiftUI
import Charts

/// Grouped bar chart comparing revenue vs cost per job.
///
/// Used on the Reports profitability page to visualize job margins.
struct ProfitabilityChart: View {
    let data: [JobProfitData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Profitability")
                .font(.headline)

            if data.isEmpty {
                Text("No profitability data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data) { job in
                    BarMark(
                        x: .value("Job", job.jobName),
                        y: .value("Amount", job.revenue)
                    )
                    .foregroundStyle(.green)
                    .position(by: .value("Type", "Revenue"))

                    BarMark(
                        x: .value("Job", job.jobName),
                        y: .value("Amount", job.cost)
                    )
                    .foregroundStyle(.red.opacity(0.7))
                    .position(by: .value("Type", "Cost"))
                }
                .chartForegroundStyleScale([
                    "Revenue": Color.green,
                    "Cost": Color.red.opacity(0.7),
                ])
                .chartYAxisLabel("$")
                .frame(height: 220)

                // Margin summary
                let totalRevenue = data.reduce(0) { $0 + $1.revenue }
                let totalCost = data.reduce(0) { $0 + $1.cost }
                let margin = totalRevenue > 0 ? ((totalRevenue - totalCost) / totalRevenue) * 100 : 0

                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text(String(format: "$%.0f", totalRevenue))
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Revenue")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text(String(format: "$%.0f", totalCost))
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("Cost")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f%%", margin))
                            .font(.headline)
                            .foregroundStyle(margin >= 0 ? .green : .red)
                        Text("Margin")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .dsCard()
    }
}

struct JobProfitData: Identifiable, Sendable {
    let id = UUID()
    let jobName: String
    let revenue: Double
    let cost: Double
    var profit: Double { revenue - cost }
    var margin: Double { revenue > 0 ? ((revenue - cost) / revenue) * 100 : 0 }
}
