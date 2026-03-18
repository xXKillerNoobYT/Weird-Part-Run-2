import SwiftUI

/// Design System button style hierarchy.
///
/// Provides a clear ladder of emphasis levels for buttons.
/// All styles enforce a 44x44pt minimum tap target for accessibility.
///
/// Usage:
///   Button("Save") { ... }.dsButtonStyle(.primary)
///   Button("Delete") { ... }.dsButtonStyle(.destructive)

// MARK: - Button Emphasis Levels

enum DSButtonEmphasis {
    /// Main CTA per screen — filled accent background.
    case primary
    /// Supporting actions — bordered outline.
    case secondary
    /// Low-emphasis — plain text with accent color.
    case tertiary
    /// Destructive action — bordered with red tint.
    case destructive
}

// MARK: - Button Style Modifier

extension View {
    /// Apply a Design System button style.
    ///
    /// - Parameter emphasis: The visual emphasis level for the button.
    /// - Parameter large: When true, uses `.controlSize(.large)` (good for forms).
    @ViewBuilder
    func dsButtonStyle(_ emphasis: DSButtonEmphasis, large: Bool = false) -> some View {
        switch emphasis {
        case .primary:
            self
                .buttonStyle(.borderedProminent)
                .controlSize(large ? .large : .regular)

        case .secondary:
            self
                .buttonStyle(.bordered)
                .controlSize(large ? .large : .regular)

        case .tertiary:
            self
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)

        case .destructive:
            self
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(large ? .large : .regular)
        }
    }
}

// MARK: - Icon Button Style

/// A button style that ensures a 44x44pt minimum tap target for icon-only buttons.
///
/// Usage:
///   Button { } label: {
///       Image(systemName: "plus")
///   }
///   .buttonStyle(DSIconButtonStyle())
struct DSIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

extension ButtonStyle where Self == DSIconButtonStyle {
    /// Icon button style with 44x44pt minimum tap target.
    static var dsIcon: DSIconButtonStyle { DSIconButtonStyle() }
}
