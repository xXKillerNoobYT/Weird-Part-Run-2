import SwiftUI

/// Design System section header component.
///
/// Standardizes the "Section Title [See All ›]" pattern used throughout
/// the app. Replaces the inline `.font(.headline)` + HStack pattern.
///
/// Usage:
///   DSSectionHeader(title: "Recent Activity")
///   DSSectionHeader(title: "Quick Actions", actionLabel: "See All") { showAll() }
struct DSSectionHeader: View {
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .dsStyle(.sectionTitle)

            Spacer()

            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.subheadline)
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DS.Space.xl) {
        DSSectionHeader(title: "Recent Activity")
        DSSectionHeader(title: "Quick Actions", actionLabel: "See All") {
            print("see all tapped")
        }
    }
    .padding()
}
