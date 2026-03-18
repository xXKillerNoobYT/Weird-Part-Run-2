import SwiftUI
import WiredPartCore

/// Progress screen shown while a newly-paired device downloads
/// the company database from the shop computer.
///
/// Displays a progress bar and status messages during initial sync.
/// On completion, navigates to LoginView where the user selects
/// themselves from the synced user list.
struct SyncWaitingView: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var progress: Double = 0.0
    @State private var statusMessage = "Connecting to shop computer..."
    @State private var isSyncComplete = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated indicator
            VStack(spacing: 20) {
                if isSyncComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                        .controlSize(.large)
                }

                Text(isSyncComplete ? "Sync Complete!" : "Syncing Data")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Progress bar
            if !isSyncComplete {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // Error
            if let error = errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Button("Retry") {
                        startSync()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            if isSyncComplete {
                Button {
                    // Dismiss onboarding — AppCore will show LoginView
                    // since users now exist but no one is logged in
                    appCore.completeOnboarding()
                } label: {
                    Text("Continue to Login")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 300)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 48)
            } else {
                Text("Keep this device near the shop computer during sync.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #elseif os(macOS)
        .background(Color(.windowBackgroundColor))
        #endif
        .navigationBarBackButtonHidden(true)
        .onAppear { startSync() }
    }

    // MARK: - Sync Logic

    private func startSync() {
        errorMessage = nil
        progress = 0.0
        isSyncComplete = false
        statusMessage = "Connecting to shop computer..."

        // Actual sync will be implemented in Phase 16 (Sync Infrastructure).
        // For now, simulate a progress sequence.
        simulateSync()
    }

    private func simulateSync() {
        let stages: [(Double, String)] = [
            (0.15, "Downloading company settings..."),
            (0.30, "Syncing users and permissions..."),
            (0.50, "Syncing parts catalog..."),
            (0.70, "Syncing jobs and orders..."),
            (0.85, "Syncing warehouse data..."),
            (0.95, "Finalizing..."),
            (1.0, "All data synced successfully"),
        ]

        for (index, stage) in stages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index + 1) * 0.6) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    progress = stage.0
                    statusMessage = stage.1
                }
                if index == stages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSyncComplete = true
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SyncWaitingView()
            .environmentObject(AppCore())
    }
}
