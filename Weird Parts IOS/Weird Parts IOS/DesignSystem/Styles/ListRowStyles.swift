import SwiftUI

/// Design System standard list row component.
///
/// Provides a consistent row layout used across all list-based pages:
/// [Leading] [Title / Subtitle] ... [Trailing] [Chevron]
///
/// Usage:
///   DSRow(title: "Brake Pads", subtitle: "Part #BP-1234") {
///       Image(systemName: "wrench.fill")
///           .foregroundStyle(.orange)
///   } trailing: {
///       StatusBadge(text: "In Stock", color: .green)
///   }
struct DSRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    /// Icon frame size that scales with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36

    var body: some View {
        HStack(spacing: DS.Space.md) {
            leading
                .frame(width: iconSize, height: iconSize)
                .background(DS.Background.nested)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))

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

            trailing
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Convenience: Text-Only Leading

extension DSRow where Leading == DSRowIconView {
    /// Convenience initializer with an SF Symbol icon and color.
    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color = .accentColor,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = DSRowIconView(icon: icon, color: iconColor)
        self.trailing = trailing()
    }
}

/// A standard icon view for DSRow's leading slot.
struct DSRowIconView: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.callout)
            .foregroundStyle(color)
    }
}

// MARK: - Convenience: No Trailing

extension DSRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading()
        self.trailing = EmptyView()
    }
}
