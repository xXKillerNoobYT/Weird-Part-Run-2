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

    var body: some View {
        Form {
            Section("Sync Server") {
                TextField("Shop Server Address (e.g. 192.168.1.100:8080)", text: $shopServerAddress)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }

            Section("Sync Behavior") {
                Toggle("Auto-Sync", isOn: $autoSync)
                HStack {
                    Text("Sync Interval (seconds)")
                    Spacer()
                    TextField("30", text: $syncInterval)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Status") {
                LabeledContent("Last Sync", value: "Not yet synced")
                LabeledContent("Pending Changes", value: "0")
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
                    // Trigger manual sync (placeholder)
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
    }

    private func loadSettings() {
        do {
            let map = try appCore.settingsService.getSettingsByCategory("sync")
            shopServerAddress = map["shop_server_address"] ?? ""
            syncInterval = map["sync_interval"] ?? "30"
            autoSync = map["auto_sync"] != "false"
        } catch {}
    }

    private func saveSettings() {
        do {
            try appCore.settingsService.upsertSettingsMap([
                "shop_server_address": shopServerAddress,
                "sync_interval": syncInterval,
                "auto_sync": String(autoSync),
            ], category: "sync")
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        } catch {}
    }
}
