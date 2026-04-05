import SwiftUI

/// A small colored dot that indicates a list row requires user action.
///
/// - Green dot: recently created pending item (action needed)
/// - Red dot: overdue or long-pending item (urgent action needed)
///
/// Usage:
/// ```swift
/// HStack {
///     // ... row content ...
///     Spacer()
///     ActionDot(isOverdue: item.isOverdue)
/// }
/// ```
struct ActionDot: View {
    /// Whether this item is overdue or has been pending for a long time.
    let isOverdue: Bool

    var body: some View {
        Circle()
            .fill(isOverdue ? Color.red : Color.green)
            .frame(width: 10, height: 10)
            .accessibilityLabel(isOverdue ? "Overdue action required" : "Action required")
    }
}

// MARK: - Action Button Ring Modifier

/// Adds a colored border ring around an action button to increase visual prominence.
///
/// Usage:
/// ```swift
/// Button("Approve") { approveAction() }
///     .buttonStyle(.bordered)
///     .tint(.green)
///     .actionRing(.green)
/// ```
struct ActionButtonRingModifier: ViewModifier {
    let color: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color.opacity(0.6), lineWidth: 2)
            )
    }
}

extension View {
    /// Adds a colored border ring to indicate this is an action-required button.
    ///
    /// - Parameters:
    ///   - color: The ring color (typically `.green` for approve, `.red` for reject/destructive).
    ///   - cornerRadius: Corner radius to match the button shape (default 8).
    func actionRing(_ color: Color, cornerRadius: CGFloat = 8) -> some View {
        modifier(ActionButtonRingModifier(color: color, cornerRadius: cornerRadius))
    }
}
