import SwiftUI
import Charts

/// Horizontal bar chart showing stock levels for top parts by quantity.
///
/// Parts below their minimum stock level are highlighted in red.
/// Used on the Warehouse dashboard and Dashboard overview.
struct StockLevelChart: View {
    let data: [StockLevelData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stock Levels")
                .font(.headline)

            if data.isEmpty {
                Text("No stock data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Quantity", item.quantity),
                        y: .value("Part", item.partName)
                    )
                    .foregroundStyle(item.isBelowMin ? .red : Color.accentColor)
                    .annotation(position: .trailing) {
                        Text("\(item.quantity)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxisLabel("Units")
                .frame(height: CGFloat(data.count * 36 + 40))

                // Legend
                HStack(spacing: 16) {
                    Label("In Stock", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Label("Below Minimum", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding()
        .dsCard()
    }
}

struct StockLevelData: Identifiable, Sendable {
    let id = UUID()
    let partName: String
    let quantity: Int
    let minLevel: Int
    var isBelowMin: Bool { quantity < minLevel }
}
