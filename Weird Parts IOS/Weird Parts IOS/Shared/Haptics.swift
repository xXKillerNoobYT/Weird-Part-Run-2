import UIKit

/// Lightweight wrapper around UIKit feedback generators for consistent haptic feedback.
///
/// Use `Haptics.impact(.medium)` at the moment of a user-initiated tap to give
/// immediate tactile confirmation, and `Haptics.success()` / `Haptics.warning()` /
/// `Haptics.error()` once an operation completes to communicate its outcome.
///
/// All methods are safe to call unconditionally — UIKit silently no-ops on devices
/// that don't support haptics.
enum Haptics {

    /// Fires an impact feedback of the given intensity.
    /// Use `.medium` for standard state-changing taps (swipe actions, buttons).
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    /// Fires a notification feedback of the given type.
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    /// `.success` notification — use when an operation completes successfully.
    static func success() { notification(.success) }

    /// `.warning` notification — use when a destructive confirmation is tapped.
    static func warning() { notification(.warning) }

    /// `.error` notification — use when an operation fails.
    static func error() { notification(.error) }
}
