import SwiftUI

/// Design System card container styles.
///
/// Replaces the `.glassCard()` modifier with a tiered system that respects
/// Apple's guidance on Liquid Glass usage. Glass is reserved for the
/// top 1-2 interactive elements per screen.
///
/// Usage:
///   VStack { ... }.dsCard()           // standard content card
///   VStack { ... }.dsElevatedCard()   // KPI cards, summary cards
///   VStack { ... }.dsGlassCard()      // SPARINGLY — interactive focal elements
///   VStack { ... }.dsAlertCard(.warning)  // alerts, overdue banners

// MARK: - Standard Card

/// System background + rounded corners. The default card for data display.
struct DSCardModifier: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.md

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(DS.Background.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Elevated Card

/// Standard card with a subtle shadow for visual weight.
struct DSElevatedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.md

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(DS.Background.card)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .modifier(DS.Elevation.low)
    }
}

// MARK: - Glass Card

/// Liquid Glass effect — use SPARINGLY (max 1-2 per screen).
/// Falls back to standard card when Reduce Transparency is enabled.
struct DSGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = DS.Radius.lg
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .modifier(DSCardModifier(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.regularMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - Alert Card

/// Severity levels for alert cards.
enum DSAlertSeverity {
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .info: DS.SemanticColor.info
        case .warning: DS.SemanticColor.warning
        case .error: DS.SemanticColor.error
        }
    }
}

/// Colored border + tinted background for warnings and alerts.
struct DSAlertCardModifier: ViewModifier {
    let severity: DSAlertSeverity

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.SemanticColor.muted(severity.color))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(severity.color.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

// MARK: - View Extension

extension View {
    /// Standard content card with system background.
    func dsCard(cornerRadius: CGFloat = DS.Radius.md) -> some View {
        modifier(DSCardModifier(cornerRadius: cornerRadius))
    }

    /// Elevated card with subtle shadow — for KPI cards, summaries.
    func dsElevatedCard(cornerRadius: CGFloat = DS.Radius.md) -> some View {
        modifier(DSElevatedCardModifier(cornerRadius: cornerRadius))
    }

    /// Liquid Glass card — use SPARINGLY (max 1-2 per screen).
    func dsGlassCard(cornerRadius: CGFloat = DS.Radius.lg) -> some View {
        modifier(DSGlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Alert card with colored border — for warnings, overdue, budget alerts.
    func dsAlertCard(_ severity: DSAlertSeverity) -> some View {
        modifier(DSAlertCardModifier(severity: severity))
    }
}
