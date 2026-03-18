import SwiftUI

/// Compact colored status badge for jobs, orders, and other entities.
///
/// Usage:
///   StatusBadge(text: "Active", color: .green)
///   StatusBadge(text: "Pending Approval", color: .orange)
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .dsStyle(.label)
            .foregroundStyle(color)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xxxs + 1)
            .background(
                Capsule()
                    .fill(DS.SemanticColor.tint(color))
            )
            .accessibilityLabel(text)
    }
}

#Preview {
    HStack(spacing: 8) {
        StatusBadge(text: "Active", color: .green)
        StatusBadge(text: "Pending", color: .orange)
        StatusBadge(text: "Closed", color: .secondary)
        StatusBadge(text: "Urgent", color: .red)
    }
    .padding()
}
