import SwiftUI

/// Shared Liquid Glass card styling for iOS 26+.
///
/// Replaces the manual `.background(Color(.secondarySystemGroupedBackground))`
/// + `.clipShape(RoundedRectangle(...))` pattern with a single modifier.
///
/// Usage:
///     VStack { ... }
///         .glassCard()
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// Apply Liquid Glass card styling.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}
