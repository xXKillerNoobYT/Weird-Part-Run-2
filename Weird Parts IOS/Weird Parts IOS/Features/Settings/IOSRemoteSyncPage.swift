import SwiftUI
import WiredPartCore

/// Remote (internet) sync status page.
///
/// Remote sync has not shipped yet, so this page is informational only.
/// The previous toggle/interval/"Sync Now" controls were removed for beta
/// because none of them were wired to anything (#1338 — dead-end controls).
struct IOSRemoteSyncPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var activeSheet: ActiveSheet?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "cloud")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Sync")
                            .fontWeight(.medium)
                        Text("Planned for a future release")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Remote sync will move data between shops over the internet. Currently, all sync happens over LAN and Bluetooth — see Settings → Sync.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("LAN sync is active between devices on the same network", systemImage: "wifi")
                    Label("Bluetooth sync covers nearby devices without Wi-Fi", systemImage: "antenna.radiowaves.left.and.right")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Available Today")
            }
        }
        .navigationTitle("Remote Sync")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Remote Sync Help", sections: [
                ("What This Page Does", "Describes internet-based sync between multiple shop locations. Remote sync allows data to travel between shops that are not on the same local network."),
                ("Current Status", "This feature is planned for a future release. Currently all sync happens over LAN and Bluetooth — configure those from Settings → Sync."),
            ])
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }
}
