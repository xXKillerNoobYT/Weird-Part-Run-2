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
    @State private var hasUnsavedChanges = false
    @State private var showDiscardConfirmation = false
    @State private var baselineFormSignature = ""

    private var syncManager: IOSSyncManager { appCore.syncManager }
    private var formSignature: String {
        [shopServerAddress, syncInterval, String(autoSync)].joined(separator: "|")
    }

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
                        .accessibilityLabel("Sync interval in seconds")
                        .accessibilityIdentifier("settings-sync-interval-field")
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
                                if entry.isOneWayBluetoothTransfer {
                                    Text("One-way Bluetooth send — tap Send Changes on the other device to receive its changes.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
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
                        .rowAccessibility(
                            label: "\(entry.isOneWayBluetoothTransfer ? "One-way Bluetooth send" : "Sync \(entry.success ? "succeeded" : "failed")") on \(entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))",
                            value: historyAccessibilityValue(entry),
                            id: "settings-sync-history-\(entry.id.uuidString)"
                        )
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
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if hasUnsavedChanges {
                    Button("Back") { showDiscardConfirmation = true }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-sync-help-button")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "LAN Sync Help", sections: [
                ("What This Page Does", "Configures local network sync between this device and the shop server. Shows current sync status, pending changes, and recent sync history."),
                ("How to Use It", "Enter the shop server address, set a sync interval, and enable auto-sync. Tap 'Sync Now' for an immediate sync. Changes are merged using last-writer-wins with field-level conflict resolution."),
            ])
        }
        .task { loadSettings() }
        .onChange(of: formSignature) { _, _ in
            hasUnsavedChanges = formSignature != baselineFormSignature
        }
        .confirmationDialog(
            "Discard LAN Sync changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your unsaved sync settings will be lost.")
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
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
            if let summary = syncManager.lastOneWayBluetoothSyncSummary {
                Label(summary, systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
            } else if let lastSync = syncManager.lastSyncDate {
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

    // MARK: - History Accessibility

    /// Mirrors the visible counts for VoiceOver, but with the FULL error text
    /// (the visible row truncates to 30 characters) and "No changes" when the
    /// sync moved nothing.
    private func historyAccessibilityValue(_ entry: IOSSyncManager.SyncHistoryEntry) -> String {
        var parts: [String] = []
        if entry.changesSent == 0 && entry.changesReceived == 0 && entry.conflicts == 0 {
            parts.append("No changes")
        } else {
            parts.append("\(entry.changesSent) sent, \(entry.changesReceived) received, \(entry.conflicts) conflict\(entry.conflicts == 1 ? "" : "s")")
        }
        if let error = entry.error, !error.isEmpty {
            parts.append(error)
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Load / Save

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
            resetDirtyTracking()
        } catch {
            errorMessage = userFriendlyError(error, context: "load settings")
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
            resetDirtyTracking()

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

    private func resetDirtyTracking() {
        baselineFormSignature = formSignature
        hasUnsavedChanges = false
    }
}
