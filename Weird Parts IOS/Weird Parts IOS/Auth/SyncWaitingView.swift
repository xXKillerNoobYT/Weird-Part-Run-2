import SwiftUI
import WiredPartCore

/// Progress screen shown while a newly-paired device downloads
/// the company database from the shop computer.
///
/// Displays a progress bar and status messages during initial sync.
/// On completion, navigates to the app where the user selects
/// themselves from the synced user list.
struct SyncWaitingView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var syncComplete = false
    @State private var syncError: SyncFailureReport?
    @State private var showTechnicalDetail = false
    @State private var didCopyDetails = false

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            if syncComplete {
                completedView
            } else if let error = syncError {
                errorView(error)
            } else {
                syncingView
            }

            Spacer()

            if !syncComplete && syncError == nil {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(syncManager.syncStatus == .syncing)
        .task {
            await performInitialSync()
        }
    }

    // MARK: - Syncing View

    @ViewBuilder
    private var syncingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Downloading Company Data")
                .font(.title3)
                .fontWeight(.semibold)

            if let message = syncManager.syncProgressMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if syncManager.syncProgressPercent > 0 {
                ProgressView(value: syncManager.syncProgressPercent)
                    .padding(.horizontal, 64)
            }

            Text("This may take a few moments for large databases. Do not close the app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Completed View

    @ViewBuilder
    private var completedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .decorativeIconFont(64)
                .foregroundStyle(.green)

            Text("Sync Complete!")
                .font(.title2)
                .fontWeight(.bold)

            Text("The company database has been downloaded. You can now select your user account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Continue") {
                appCore.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Error View

    private func errorView(_ report: SyncFailureReport) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .decorativeIconFont(48)
                .foregroundStyle(.orange)

            Text("Sync Error")
                .font(.title3)
                .fontWeight(.semibold)

            // The code is shown even while the details stay collapsed. Device
            // logs replicate over the very sync that is broken, so when sync
            // fails a photograph of this screen is the only diagnostic channel
            // left — which is exactly how #1723 was finally identified, from a
            // picture of the Mac's screen after weeks of reading code (#1725).
            Text(report.code)
                .font(.caption.monospaced())
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .accessibilityLabel("Error code \(report.code)")

            Text(report.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .textSelection(.enabled)

            if let detail = report.detail {
                DisclosureGroup("Technical details", isExpanded: $showTechnicalDetail) {
                    ScrollView {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .padding(.top, 8)
                }
                .font(.subheadline)
                .padding(.horizontal, 32)
            }

            // Owner request, 2026-08-14: "I do like the user friendly one if i
            // can have the full error copied to the clipboard or something like
            // that". Copies code + headline + full detail in one go, so a bug
            // report carries the cause verbatim instead of a paraphrase.
            Button {
                UIPasteboard.general.string = report.copyableText
                didCopyDetails = true
            } label: {
                Label(
                    didCopyDetails ? "Copied" : "Copy details",
                    systemImage: didCopyDetails ? "checkmark" : "doc.on.doc"
                )
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(didCopyDetails ? "Details copied" : "Copy error details")

            HStack(spacing: 16) {
                Button("Try Again") {
                    syncError = nil
                    showTechnicalDetail = false
                    didCopyDetails = false
                    Task { await performInitialSync() }
                }
                .buttonStyle(.borderedProminent)

                Button("Go Back") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Sync

    private func performInitialSync() async {
        do {
            try await syncManager.performInitialSync()
            syncComplete = true
        } catch {
            // Prefer the reason the sync manager already composed.
            //
            // `IOSSyncManager.performInitialSync` builds a transport-specific
            // explanation with `initialSyncFailureMessage` — "generate a NEW
            // code on the shop device", "keep both devices close and retry" —
            // and throws it as `SyncError.syncFailed`. Routing that through
            // `userFriendlyError` threw it away: that helper matches the
            // description against a list of substrings and, when none hit,
            // returns the generic "Couldn't sync data. Pull down to retry."
            //
            // The owner's build-63 screenshot is exactly that dead end — a
            // failure the app had already diagnosed, displayed as a shrug
            // (#1580). The composed message is the whole point of that
            // helper; the fallback is only for errors nobody has explained.
            syncError = IOSSyncManager.displayableSyncFailureReport(
                composed: syncManager.lastFailureReport,
                thrown: error
            )
        }
    }
}
