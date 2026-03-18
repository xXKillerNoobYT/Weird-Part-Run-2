import SwiftUI

/// Standard activity/event row for dashboard and detail lists.
///
/// Shows a colored icon badge, title + subtitle, and a trailing value/date.
/// Extracted from the repeated pattern in Fleet, Warehouse, and Jobs dashboards.
///
/// Usage:
///   DSActivityRow(
///       icon: "wrench.fill",
///       iconColor: .orange,
///       title: "Oil Change - Truck #4",
///       subtitle: "Completed by John",
///       trailing: "2h ago"
///   )
struct DSActivityRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil
    var trailingColor: Color = .secondary

    /// Icon badge size that scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 32

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Icon badge
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: badgeSize, height: badgeSize)
                .background(DS.SemanticColor.tint(iconColor))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

            // Title + subtitle
            VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                Text(title)
                    .dsStyle(.cardTitle)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .dsStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Space.xxs)

            // Trailing value
            if let trailing {
                Text(trailing)
                    .dsStyle(.caption)
                    .foregroundStyle(trailingColor)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        DSActivityRow(
            icon: "wrench.fill",
            iconColor: .orange,
            title: "Oil Change - Truck #4",
            subtitle: "Completed by John",
            trailing: "2h ago"
        )
        DSActivityRow(
            icon: "arrow.left.arrow.right",
            iconColor: .blue,
            title: "Move: A1 → B3 (Brake Pads)",
            subtitle: "Qty: 24",
            trailing: "Today"
        )
        DSActivityRow(
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            title: "Overdue Delivery - PO #1234",
            trailing: "3 days",
            trailingColor: .red
        )
    }
}
