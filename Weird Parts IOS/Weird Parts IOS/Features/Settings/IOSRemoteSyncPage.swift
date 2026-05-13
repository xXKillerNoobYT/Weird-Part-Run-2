import SwiftUI
import WiredPartCore

/// Remote (internet) sync configuration page.
struct IOSRemoteSyncPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: ActiveSheet?
    @State private var syncEnabled = false
    @State private var syncInterval = 30
    @State private var lastSyncDate = "Never"
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

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
                Button {
                    saveSettings()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Remote Sync Settings")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Text("Remote sync is planned for a future release. Currently, all sync happens over LAN and Bluetooth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Remote Sync")
        .navigationBarBackButtonHidden(isDirty)
        .toolbar {
            if isDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiscardConfirmation = true
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            Group {
                PageHelpSheet(title: "Remote Sync Help", sections: [
                    ("What This Page Does", "Configures internet-based sync between multiple shop locations. Remote sync allows data to travel between shops that are not on the same local network."),
                    ("How to Use It", "Enable remote sync and set a sync interval. This feature is planned for a future release. Currently all sync happens over LAN and Bluetooth."),
                ])
            }
            .presentationDetents([.medium, .large])
        }
        .task { loadSettings() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onChange(of: syncEnabled) { _, _ in markDirty() }
        .onChange(of: syncInterval) { _, _ in markDirty() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
    }

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        hasLoadedSettings = false
        do {
            let map = try service.getSettingsByCategory("remote_sync")
            syncEnabled = map["remote_sync_enabled"] == "true"
            syncInterval = Int(map["remote_sync_interval_minutes"] ?? "") ?? 30
            lastSyncDate = map["remote_sync_last_sync_date"] ?? "Never"
        } catch {
            errorMessage = userFriendlyError(error, context: "load")
        }
        isDirty = false
        Task { @MainActor in
            hasLoadedSettings = true
        }
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            try service.upsertSettingsMap([
                "remote_sync_enabled": String(syncEnabled),
                "remote_sync_interval_minutes": "\(syncInterval)",
                "remote_sync_last_sync_date": lastSyncDate,
            ], category: "remote_sync")
            saved = true
            isDirty = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "save")
        }
    }
}
