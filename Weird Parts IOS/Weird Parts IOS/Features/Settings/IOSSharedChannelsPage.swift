import SwiftUI
import WiredPartCore

/// Shared channels configuration — manages chat channels shared across devices.
struct IOSSharedChannelsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        List {
            Section {
                Text("Shared channels allow chat messages to sync across all paired devices in the network.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Channels") {
                EmptyStateView(
                    icon: "bubble.left.and.bubble.right",
                    title: "No Shared Channels",
                    message: "Shared channels will be configured when multi-device sync is enabled."
                )
            }

            // NOTE (#1338): the permanently disabled "Create Shared Channel"
            // placeholder button was removed for beta. Re-add the action here
            // once shared-channel creation is wired to sync infrastructure.
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Shared Channels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Shared Channels Help", sections: [
                ("What This Page Does", "Manages chat channels that sync messages across all paired devices in the network. Shared channels let your team communicate across devices."),
                ("How to Use It", "Shared channels will be available once multi-device sync is enabled. You will be able to create, rename, and archive channels from this page."),
            ])
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }
}
