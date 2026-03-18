import SwiftUI

/// Design System elevation / shadow tokens.
///
/// Standardizes the shadow values used across the app. Currently only
/// the AI FAB uses a shadow; this provides a consistent scale.
///
/// Usage:
///   .modifier(DS.Elevation.low)
///   .modifier(DS.Elevation.medium)
extension DS {
    enum Elevation {
        /// No shadow.
        static let none = ShadowModifier(color: .clear, radius: 0, x: 0, y: 0)

        /// Subtle card shadow — barely visible, just enough for separation.
        static let low = ShadowModifier(
            color: .black.opacity(0.08),
            radius: 2,
            x: 0,
            y: 1
        )

        /// Standard elevated element — FAB, floating cards.
        static let medium = ShadowModifier(
            color: .black.opacity(0.15),
            radius: 4,
            x: 0,
            y: 2
        )

        /// High elevation — modals, popovers (rarely needed, system handles most).
        static let high = ShadowModifier(
            color: .black.opacity(0.2),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}

/// ViewModifier that applies a shadow consistently.
struct ShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color, radius: radius, x: x, y: y)
    }
}
