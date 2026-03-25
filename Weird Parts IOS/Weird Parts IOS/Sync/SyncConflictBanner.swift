import SwiftUI
import WiredPartCore

/// Compact banner shown at the top of the main view when unreviewed sync conflicts exist.
///
/// Displays the count of auto-resolved conflicts and a "Review" button that
/// navigates to the conflict review page.
struct SyncConflictBanner: View {
    @EnvironmentObject private var appCore: AppCore

    private var syncManager: IOSSyncManager { appCore.syncManager }

    let onReview: () -> Void

    var body: some View {
        if syncManager.unreviewedConflictCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.orange)
                    .font(.subheadline)

                Text("\(syncManager.unreviewedConflictCount) sync conflict\(syncManager.unreviewedConflictCount == 1 ? "" : "s") auto-resolved")
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                Button("Review") { onReview() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.1))
        }
    }
}
