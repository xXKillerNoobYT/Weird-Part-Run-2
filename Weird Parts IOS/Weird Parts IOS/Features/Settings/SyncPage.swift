import SwiftUI
import WiredPartCore

/// Sync configuration and status page.
///
/// Shows current sync status and allows configuring the LAN sync
/// server address. The actual sync engine is managed by the core
/// package's SyncEngine and MultipeerManager.
struct SyncPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?
    @State private var shopServerAddress = ""
    @State private var syncInterval = "30"
    @State private var autoSync = true
    @State private var saved = false
    @State private var errorMessage: String?
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

    private var syncManager: IOSSyncManager { appCore.syncManager }

    var body: some View {
        Form {
            // MARK: - Status
            Section("Status") {
                statusRow
                if syncManager.pendingChanges > 0 {
                    LabeledContent("Pending Changes") {
                        Text("\(syncManager.pendingChanges)")
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // MARK: - Server
            Section("Sync Server") {
                TextField("Shop Server Address (e.g. 192.168.1.100:8080)", text: $shopServerAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            // MARK: - Behavior
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

            // MARK: - Actions
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
                    Task { await syncManager.syncNow() }
                } label: {
                    HStack {
                        Spacer()
                        if syncManager.syncStatus == .syncing {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 6)
                        }
                        Text(syncManager.syncStatus == .syncing ? "Syncing..." : "Sync Now")
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(syncManager.syncStatus == .syncing)
            }

            // MARK: - Recent Sync History
            if !syncManager.syncHistory.isEmpty {
                Section("Recent Syncs") {
                    ForEach(syncManager.syncHistory.prefix(10)) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.success ? (entry.conflicts > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill") : "xmark.circle.fill")
                                .foregroundStyle(entry.success ? (entry.conflicts > 0 ? .orange : .green) : .red)
                                .font(.caption)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                HStack(spacing: 8) {
                                    if entry.changesSent > 0 {
                                        Text("\(entry.changesSent) sent")
                                    }
                                    if entry.changesReceived > 0 {
                                        Text("\(entry.changesReceived) received")
                                    }
                                    if entry.conflicts > 0 {
                                        Text("\(entry.conflicts) conflict\(entry.conflicts == 1 ? "" : "s")")
                                            .foregroundStyle(.orange)
                                    }
                                    if entry.changesSent == 0 && entry.changesReceived == 0 && entry.conflicts == 0 {
                                        Text("No changes")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if let err = entry.error {
                                Text(err.prefix(30))
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            // MARK: - Info
            Section {
                Text("LAN sync connects to the shop server over your local network. Changes are merged using last-writer-wins with field-level conflict resolution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // Fix #149: dismiss keyboard on scroll
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("LAN Sync")
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
                PageHelpSheet(title: "LAN Sync Help", sections: [
                    ("What This Page Does", "Configures local network sync between this device and the shop server. Shows current sync status, pending changes, and recent sync history."),
                    ("How to Use It", "Enter the shop server address, set a sync interval, and enable auto-sync. Tap 'Sync Now' for an immediate sync. Changes are merged using last-writer-wins with field-level conflict resolution."),
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
        .onChange(of: shopServerAddress) { _, _ in markDirty() }
        .onChange(of: syncInterval) { _, _ in markDirty() }
        .onChange(of: autoSync) { _, _ in markDirty() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        switch syncManager.syncStatus {
        case .idle:
            Label("Not synced yet", systemImage: "circle.dashed")
                .foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Syncing...")
            }
        case .synced:
            if let lastSync = syncManager.lastSyncDate {
                let displayDate = lastSync.prefix(19).replacingOccurrences(of: "T", with: " ")
                Label("Last sync: \(displayDate)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Synced", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .error:
            Label(syncManager.errorMessage ?? "Sync error", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .offline:
            Label("Offline", systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Load / Save

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        hasLoadedSettings = false
        do {
            let map = try service.getSettingsByCategory("sync")
            shopServerAddress = map["shop_server_address"] ?? ""
            syncInterval = map["sync_interval"] ?? "30"
            autoSync = map["auto_sync"] != "false"
        } catch {
            errorMessage = userFriendlyError(error, context: "load settings")
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
                "shop_server_address": shopServerAddress,
                "sync_interval": syncInterval,
                "auto_sync": String(autoSync),
            ], category: "sync")
            saved = true
            isDirty = false

            // Reconfigure auto-sync with new settings
            if autoSync && syncManager.isSyncAvailable {
                let interval = TimeInterval(syncInterval) ?? 60
                syncManager.startAutoSync(intervalSeconds: max(interval, 15))
            } else {
                syncManager.stopAutoSync()
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "save")
        }
    }
}
