import SwiftUI

/// Design System animation tokens.
///
/// Standardizes animation curves and durations across the app.
/// All animations should respect Reduce Motion accessibility setting.
///
/// Usage:
///   withAnimation(DS.Anim.standard) { ... }
///   .animation(DS.Anim.spring, value: someState)
extension DS {
    enum Anim {
        /// 0.15s — micro interactions (toggle, chip select)
        static let fast: Animation = .easeInOut(duration: 0.15)

        /// 0.25s — standard transitions (tab switch, expand/collapse)
        static let standard: Animation = .easeInOut(duration: 0.25)

        /// 0.35s — slow transitions (sheet appear, full-screen changes)
        static let slow: Animation = .easeInOut(duration: 0.35)

        /// Spring — bouncy interactions (card press, scale effects)
        static let spring: Animation = .spring(response: 0.3, dampingFraction: 0.7)
    }
}

/// Perform an animation only if Reduce Motion is off.
///
/// Usage:
///   dsAnimate(DS.Anim.standard) { selectedTab = newTab }
func dsAnimate(_ animation: Animation = DS.Anim.standard, _ body: () -> Void) {
    if UIAccessibility.isReduceMotionEnabled {
        body()
    } else {
        withAnimation(animation, body)
    }
}
