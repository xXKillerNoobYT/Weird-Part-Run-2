import SwiftUI
import Charts

/// Pie chart showing spending breakdown by category (labor, parts, fuel, other).
///
/// Used on the Dashboard and Spending pages to visualize cost distribution.
struct SpendingChart: View {
    let data: [SpendingCategory]

    private var total: Double {
        data.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spending Breakdown")
                .font(.headline)

            if data.isEmpty || total == 0 {
                Text("No spending data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                HStack(spacing: 16) {
                    Chart(data) { category in
                        SectorMark(
                            angle: .value("Amount", category.amount),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Category", category.name))
                        .cornerRadius(4)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 140, height: 140)

                    // Legend with percentages
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(data) { category in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(category.color)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.name)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(String(format: "$%.0f (%.0f%%)", category.amount, (category.amount / total) * 100))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .dsCard()
    }
}

struct SpendingCategory: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let amount: Double
    let color: Color
}
