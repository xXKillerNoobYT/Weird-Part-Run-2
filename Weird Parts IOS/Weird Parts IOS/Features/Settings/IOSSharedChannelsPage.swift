import SwiftUI
import WiredPartCore

/// Shared channels configuration — manages chat channels shared across devices.
struct IOSSharedChannelsPage: View {
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        List {
            Section {
                Text("Shared channels allow chat messages to sync across all paired devices in the network.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Channels") {
                ContentUnavailableView {
                    Label("No Shared Channels", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Shared channels will be configured when multi-device sync is enabled.")
                }
            }

            Section {
                Button {
                    // Create shared channel
                } label: {
                    Label("Create Shared Channel", systemImage: "plus.circle.fill")
                }
                .disabled(true) // Enabled with sync infrastructure
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Shared Channels")
    }
}
