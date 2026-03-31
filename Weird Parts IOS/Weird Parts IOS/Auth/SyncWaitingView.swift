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
    @State private var syncError: String?

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

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .decorativeIconFont(48)
                .foregroundStyle(.orange)

            Text("Sync Error")
                .font(.title3)
                .fontWeight(.semibold)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 16) {
                Button("Try Again") {
                    syncError = nil
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
            syncError = userFriendlyError(error, context: "sync data")
        }
    }
}
