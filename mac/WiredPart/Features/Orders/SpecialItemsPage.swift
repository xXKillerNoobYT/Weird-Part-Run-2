import SwiftUI
import WiredPartCore

/// Special Items placeholder page.
///
/// Displays the Special Items section title with an empty state.
/// Full implementation will include a list of non-catalog items
/// requested through the ordering process.
struct SpecialItemsPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            emptyState
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Special Items")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Non-catalog items requested through orders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                // Refresh placeholder
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.square")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No special items")
                .font(.headline)
            Text("Special items will appear here when non-catalog parts are requested.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
