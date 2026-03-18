import SwiftUI
import Charts

/// Bar chart showing fuel costs by week over the past 8 weeks.
///
/// Used on the Fleet dashboard to track fuel spending trends.
struct FuelChart: View {
    let data: [FuelWeekData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fuel Costs (Past 8 Weeks)")
                .font(.headline)

            if data.isEmpty {
                Text("No fuel data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data) { week in
                    BarMark(
                        x: .value("Week", week.weekLabel),
                        y: .value("Cost", week.totalCost)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(4)
                }
                .chartYAxisLabel("$")
                .frame(height: 180)

                // Summary row
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        let total = data.reduce(0) { $0 + $1.totalCost }
                        Text(String(format: "$%.0f", total))
                            .font(.headline)
                        Text("Total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        let totalGallons = data.reduce(0) { $0 + $1.gallons }
                        Text(String(format: "%.0f gal", totalGallons))
                            .font(.headline)
                        Text("Fuel Used")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        let totalCost = data.reduce(0) { $0 + $1.totalCost }
                        let totalGallons = data.reduce(0) { $0 + $1.gallons }
                        let avgPrice = totalGallons > 0 ? totalCost / totalGallons : 0
                        Text(String(format: "$%.2f", avgPrice))
                            .font(.headline)
                        Text("Avg $/gal")
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

struct FuelWeekData: Identifiable, Sendable {
    let id = UUID()
    let weekLabel: String   // e.g. "W1", "W2"
    let weekStart: String   // ISO date
    let totalCost: Double
    let gallons: Double
}
