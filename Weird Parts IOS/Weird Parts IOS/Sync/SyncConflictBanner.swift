import SwiftUI
import WiredPartCore

/// Compact banner shown at the top of the main view when unreviewed sync conflicts exist.
///
/// The entire banner is a single tappable button that opens the conflict
/// review sheet. Layout is height-capped on iPhone and across Dynamic Type
/// sizes so the banner never crowds out the active module's content.
/// See `docs/plans/sync-conflict-banner-github-410-ux-spec.md`.
struct SyncConflictBanner: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var verticalPad: CGFloat = 6
    @ScaledMetric(relativeTo: .subheadline) private var minHeight: CGFloat = 44

    private var syncManager: IOSSyncManager { appCore.syncManager }

    let onReview: () -> Void

    private var count: Int { syncManager.unreviewedConflictCount }

    private var countText: String {
        "\(count) sync conflict\(count == 1 ? "" : "s") auto-resolved"
    }

    var body: some View {
        if count > 0 {
            Button(action: onReview) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.triangle.merge")
                        .imageScale(.small)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(countText)
                        .font(.subheadline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text("Review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityHidden(true)

                    if dynamicTypeSize <= .xxLarge {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, 16)
                .padding(.vertical, min(verticalPad, 10))
                .frame(minHeight: min(minHeight, 80))
                .frame(maxHeight: 80)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.orange.opacity(0.12)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.35))
                                .frame(height: 1)
                        }
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("syncConflictBanner")
            .accessibilityLabel("\(countText). Double-tap to review.")
            .accessibilityHint("Opens the sync conflict review sheet")
        }
    }
}
