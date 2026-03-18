import SwiftUI

/// Reusable filter chip for filter bars and status pickers.
///
/// A toggleable capsule that shows active/inactive state.
/// Used in catalog filter bars, job status pickers, etc.
///
/// Usage:
///   FilterChip(label: "In Stock", isActive: lowStockOnly) { lowStockOnly.toggle() }
///   FilterChip(label: "Active", icon: "circle.fill", isActive: true) { ... }
struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xxs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .dsStyle(.label)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .background(
                Capsule()
                    .fill(isActive ? Color.accentColor : DS.Background.nested)
            )
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack(spacing: DS.Space.sm) {
        FilterChip(label: "All", isActive: true) {}
        FilterChip(label: "In Stock", isActive: false) {}
        FilterChip(label: "Low Stock", icon: "exclamationmark.triangle", isActive: false) {}
    }
    .padding()
}
