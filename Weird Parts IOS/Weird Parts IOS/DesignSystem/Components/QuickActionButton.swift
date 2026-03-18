import SwiftUI

/// Reusable quick action button for dashboard and tool grids.
///
/// Compact icon + label button used in horizontal scroll rows.
/// Uses `dsCard()` styling (not glass — typically 4+ per row).
///
/// Usage:
///   DSQuickActionButton(title: "Clock In", icon: "clock.badge.checkmark.fill", color: .green) {
///       clockIn()
///   }
struct DSQuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil

    /// Button size that scales with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var buttonWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .caption2) private var buttonHeight: CGFloat = 72

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: DS.Space.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .dsStyle(.label)
                    .foregroundStyle(.primary)
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .dsCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: DS.Space.md) {
            DSQuickActionButton(title: "Clock In", icon: "clock.badge.checkmark.fill", color: .green)
            DSQuickActionButton(title: "New Order", icon: "plus.circle.fill", color: .blue)
            DSQuickActionButton(title: "Move Stock", icon: "arrow.left.arrow.right", color: .orange)
            DSQuickActionButton(title: "Scan QR", icon: "qrcode.viewfinder", color: .purple)
        }
        .padding()
    }
}
