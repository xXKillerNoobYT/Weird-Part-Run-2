import SwiftUI
import WiredPartCore

/// Sync configuration and status page.
///
/// Shows current sync status and allows configuring the LAN sync
/// server address. The actual sync engine is managed by the core
/// package's SyncEngine and MultipeerManager.
struct SyncPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var shopServerAddress = ""
    @State private var syncInterval = "30"
    @State private var autoSync = true
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Sync Server") {
                TextField("Shop Server Address (e.g. 192.168.1.100:8080)", text: $shopServerAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Sync Behavior") {
                Toggle("Auto-Sync", isOn: $autoSync)
                HStack {
                    Text("Sync Interval (seconds)")
                    Spacer()
                    TextField("30", text: $syncInterval)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Status") {
                Text("Sync not configured")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    saveSettings()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Sync Settings")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button {
                    errorMessage = "Sync infrastructure not yet configured."
                } label: {
                    HStack {
                        Spacer()
                        Text("Sync Now")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
            }

            Section {
                Text("LAN sync connects to the shop server over your local network. Changes are merged using last-writer-wins with field-level conflict resolution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { loadSettings() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            let map = try service.getSettingsByCategory("sync")
            shopServerAddress = map["shop_server_address"] ?? ""
            syncInterval = map["sync_interval"] ?? "30"
            autoSync = map["auto_sync"] != "false"
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
        }
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            try service.upsertSettingsMap([
                "shop_server_address": shopServerAddress,
                "sync_interval": syncInterval,
                "auto_sync": String(autoSync),
            ], category: "sync")
            saved = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
