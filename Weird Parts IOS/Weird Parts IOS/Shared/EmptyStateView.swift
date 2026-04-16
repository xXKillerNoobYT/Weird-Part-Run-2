import SwiftUI

/// Reusable empty state placeholder for lists and grids.
///
/// Usage:
///   if items.isEmpty {
///       EmptyStateView(
///           icon: "wrench.and.screwdriver",
///           title: "No Parts Yet",
///           message: "Add your first part to get started.",
///           actionLabel: "Add Part"
///       ) {
///           showAddSheet = true
///       }
///   }
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 48

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)

            Text(title)
                .dsStyle(.cardTitle)
                .font(.title3)

            Text(message)
                .dsStyle(.detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.xxxl)

            if let label = actionLabel, let action = action {
                Button(action: action) {
                    Text(label)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, DS.Space.xxs)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "tray",
        title: "No Items",
        message: "There's nothing here yet. Add something to get started.",
        actionLabel: "Add Item"
    ) {
        // Preview-only stub
    }
}
