import SwiftUI
import WiredPartCore

/// Remote (internet) sync configuration page.
struct IOSRemoteSyncPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var activeSheet: ActiveSheet?
    @State private var syncEnabled = false
    @State private var syncInterval = 30
    @State private var lastSyncDate = "Never"

    var body: some View {
        Form {
            Section {
                Toggle("Enable Remote Sync", isOn: $syncEnabled)
            } header: {
                Text("Internet Sync")
            } footer: {
                Text("Syncs data between shops over the internet. Requires network connectivity.")
            }

            if syncEnabled {
                Section("Configuration") {
                    Stepper("Sync Every: \(syncInterval) min", value: $syncInterval, in: 5...120, step: 5)
                    HStack {
                        Text("Last Sync")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastSyncDate)
                            .fontWeight(.medium)
                    }
                }

                Section {
                    Button("Sync Now") {
                        // Manual sync trigger
                    }
                    .disabled(true) // Enabled in Phase 16
                }
            }

            Section {
                Text("Remote sync is planned for a future release. Currently, all sync happens over LAN and Bluetooth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Remote Sync")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Remote Sync Help", sections: [
                ("What This Page Does", "Configures internet-based sync between multiple shop locations. Remote sync allows data to travel between shops that are not on the same local network."),
                ("How to Use It", "Enable remote sync and set a sync interval. This feature is planned for a future release. Currently all sync happens over LAN and Bluetooth."),
            ])
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }
}
