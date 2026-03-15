import SwiftUI
import WiredPartCore

/// Order Staging placeholder page.
///
/// Displays the Order Staging section title with an empty state.
/// Full implementation will show orders being staged for delivery
/// or pickup, with status tracking and assignment management.
struct OrderStagingPage: View {
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
                Text("Order Staging")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Track orders being staged for delivery or pickup")
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
            Image(systemName: "tray.2")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No staged orders")
                .font(.headline)
            Text("Orders being prepared for delivery or pickup will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
