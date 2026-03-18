import SwiftUI
import WiredPartCore

/// Remote (internet) sync configuration page.
struct IOSRemoteSyncPage: View {
    @EnvironmentObject private var appCore: AppCore

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
    }
}
