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
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var action: (() -> Void)? = nil

    /// Button size that scales with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var buttonWidth: CGFloat = 88
    @ScaledMetric(relativeTo: .caption2) private var buttonHeight: CGFloat = 76

    var body: some View {
        Button {
            guard !isLoading && !isDisabled else { return }
            action?()
        } label: {
            VStack(spacing: DS.Space.xs) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(height: 28)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(isDisabled ? .secondary : color)
                }

                Text(title)
                    .dsStyle(.label)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .dsCard()
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
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
