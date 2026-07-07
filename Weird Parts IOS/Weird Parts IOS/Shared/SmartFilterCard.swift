import SwiftUI

/// A filter card that shows a label and count, used as a replacement for
/// old capsule chip filters. Displays title + count in a rounded card,
/// highlighted when selected.
///
/// Accessibility: exposes the title as label, the count as value (override
/// with `accessibilityValue` for a unit-qualified phrase like "3 JPOs"),
/// selection via the `.isSelected` trait, and a stable identifier derived
/// from the title unless `accessibilityId` is provided.
struct SmartFilterCard: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var accessibilityValue: String? = nil
    var accessibilityHint: String? = nil
    var accessibilityId: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 100, minHeight: 44)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue ?? "\(count)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .modifier(SmartFilterCardOptionalHint(hint: accessibilityHint))
        .accessibilityIdentifier(
            accessibilityId ?? "smart-filter-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))"
        )
    }
}

/// Applies `.accessibilityHint` only when a hint exists, so cards without one
/// don't register a blank utterance in the VoiceOver rotor.
private struct SmartFilterCardOptionalHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint, !hint.isEmpty {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}
