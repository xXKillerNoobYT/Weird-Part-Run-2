import SwiftUI

/// Standard loading state view.
///
/// Replaces inconsistent inline `ProgressView("Loading...")` patterns
/// throughout the app with a centered, well-framed loading indicator.
///
/// Usage:
///   if isLoading {
///       DSLoadingState()
///   }
///   DSLoadingState(message: "Loading fleet dashboard...")
struct DSLoadingState: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: DS.Space.md) {
            ProgressView()
                .controlSize(.regular)

            if let message {
                Text(message)
                    .dsStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Loading")
    }
}

#Preview {
    DSLoadingState(message: "Loading parts catalog...")
}
