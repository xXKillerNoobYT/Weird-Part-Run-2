import SwiftUI

/// Design System corner radius tokens.
///
/// Normalizes the 8/10/12/16 values scattered across the codebase into
/// a consistent scale. The value 10 is eliminated — use sm(8) or md(12).
///
/// Usage:
///   .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
extension DS {
    enum Radius {
        /// 8pt — small elements, icon badges, activity stat backgrounds
        static let sm: CGFloat = 8

        /// 12pt — cards, containers, list rows (most common)
        static let md: CGFloat = 12

        /// 16pt — modal sheets, large cards, main glass containers
        static let lg: CGFloat = 16

        /// 20pt — full-screen overlays
        static let xl: CGFloat = 20

        /// .infinity — capsule shapes (StatusBadge, SubTabPicker chips)
        static let full: CGFloat = .infinity
    }
}
