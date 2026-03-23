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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Sync Not Available Yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("To join an existing business, a shop computer with WiredPart must be running on your network. This feature is coming in a future update.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Go Back") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(false)
    }
}

#Preview {
    NavigationStack {
        SyncWaitingView()
            .environmentObject(AppCore())
    }
}
