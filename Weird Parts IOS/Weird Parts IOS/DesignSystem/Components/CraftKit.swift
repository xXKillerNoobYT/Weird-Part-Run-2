import SwiftUI

// MARK: - Panel-Quality Craft Kit
//
// Shared modifiers that spread the Panel Schedule Builder's craft across the app
// (docs/plans/panel-quality-uplift.md, 2026-07-06 audit). The two highest-leverage
// systemic gaps found by the audit were:
//   1. Four-part accessibility (label + value + hint + stable identifier) missing
//      on custom rows in every feature area (Settings had zero accessibilityValue,
//      Fleet zero accessibilityIdentifier, Orders 5 identifiers in 20 files).
//   2. Custom-drawn controls below the 44pt tap-target floor (Fleet pre-trip
//      status buttons ≈24pt, Office approval buttons ≈36pt, Scheduling chips ≈20pt).
//
// Adopt these instead of hand-rolling per page so the bar is one modifier away.

extension View {
    /// Panel-Builder-style four-part accessibility in one call.
    ///
    /// Collapses the row's children into a single element (like the reference's
    /// circuit cells) and applies a sentence-quality label, an optional dynamic
    /// value, an optional action hint, and a stable identifier for UI tests.
    ///
    ///     .rowAccessibility(
    ///         label: "Truck 12, Ford F-250",
    ///         value: "Assigned to Sam",
    ///         hint: "Opens the vehicle detail page.",
    ///         id: "fleet-vehicle-row-12"
    ///     )
    func rowAccessibility(
        label: String,
        value: String? = nil,
        hint: String? = nil,
        id: String
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .modifier(OptionalAccessibilityValue(value: value))
            .modifier(OptionalAccessibilityHint(hint: hint))
            .accessibilityIdentifier(id)
    }

    // NOTE: the 44pt tap-target modifier already exists in the design system —
    // use `dsMinTapTarget()` from Foundation/SystemIntegration.swift. The audit
    // gap is ADOPTION (Fleet pre-trip ≈24pt, Office approvals ≈36pt, Scheduling
    // chips ≈20pt), not a missing primitive.
}

/// Inline instruction banner for temporary modes or high-risk review flows.
///
/// The Panel Schedule Builder uses a visible move-mode banner so the user always
/// knows what the next tap will do. Reuse this for cross-app draft-import work
/// instead of scattering one-off `Text(...).background(...)` banners that drift
/// on tap target, VoiceOver, and dark-mode behavior.
struct PanelQualityInstructionBanner: View {
    let message: String
    var icon: String = "info.circle"
    var tint: Color = DS.SemanticColor.info
    var accessibilityIdentifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            Image(systemName: icon)
                .fixedSize()
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        // Reuse the shared target floor even though the banner is informational:
        // Catalyst scales SwiftUI geometry before exposing its AX frame, so a raw
        // 44pt frame renders below 44pt there. `dsMinTapTarget()` centralizes the
        // compensated Catalyst dimension while remaining 44pt on iOS/iPadOS.
        .dsMinTapTarget()
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// Stable accessibility-identifier suffix: the record id when present, else a
/// kebab slug of the given name (alphanumerics separated by single dashes,
/// "unnamed" if nothing survives). Never a literal `0` — nil-id records would
/// otherwise collide on the same identifier and make UI tests flaky.
nonisolated func stableAccessibilitySuffix(id: Int64?, name: String) -> String {
    if let id { return String(id) }
    let slug = name.lowercased()
        .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
        .joined()
        .split(separator: "-")
        .joined(separator: "-")
    return slug.isEmpty ? "unnamed" : slug
}

/// Applies `.accessibilityValue` only when a value exists, so empty values don't
/// register a blank utterance in the VoiceOver rotor.
private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?
    func body(content: Content) -> some View {
        if let value, !value.isEmpty {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

/// Applies `.accessibilityHint` only when a hint exists.
private struct OptionalAccessibilityHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint, !hint.isEmpty {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}
