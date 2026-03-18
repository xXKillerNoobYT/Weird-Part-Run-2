import SwiftUI

/// Shared KPI card used on Dashboard, Fleet, and Warehouse pages.
///
/// Displays a metric with icon, value, title, and optional trend indicator.
/// Uses `dsElevatedCard()` styling (not glass — there are typically 4+ per screen).
///
/// Usage:
///   DSKPICard(title: "Total Parts", value: "1,234", icon: "shippingbox", color: .blue)
///   DSKPICard(title: "Active Jobs", value: "12", icon: "hammer", color: .orange, trend: .up)
struct DSKPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var trend: DSKPITrend? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
                if let trend {
                    trendIndicator(trend)
                }
            }

            Text(value)
                .dsStyle(.kpiValue)

            Text(title)
                .dsStyle(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsElevatedCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    @ViewBuilder
    private func trendIndicator(_ trend: DSKPITrend) -> some View {
        HStack(spacing: DS.Space.xxxs) {
            Image(systemName: trend.icon)
                .font(.caption2)
            if let label = trend.label {
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(trend.color)
    }
}

/// Trend direction for KPI cards.
struct DSKPITrend {
    let direction: Direction
    var label: String? = nil

    enum Direction {
        case up, down, flat
    }

    var icon: String {
        switch direction {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    var color: Color {
        switch direction {
        case .up: DS.SemanticColor.success
        case .down: DS.SemanticColor.error
        case .flat: .secondary
        }
    }

    static func up(_ label: String? = nil) -> DSKPITrend {
        DSKPITrend(direction: .up, label: label)
    }
    static func down(_ label: String? = nil) -> DSKPITrend {
        DSKPITrend(direction: .down, label: label)
    }
    static let flat = DSKPITrend(direction: .flat)
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.Space.md) {
        DSKPICard(title: "Total Parts", value: "1,234", icon: "shippingbox", color: .blue)
        DSKPICard(title: "Active Jobs", value: "12", icon: "hammer", color: .orange, trend: .up("+3"))
        DSKPICard(title: "Pending Orders", value: "8", icon: "cart", color: .purple)
        DSKPICard(title: "Low Stock", value: "0", icon: "checkmark.circle", color: .green, trend: .flat)
    }
    .padding()
}
