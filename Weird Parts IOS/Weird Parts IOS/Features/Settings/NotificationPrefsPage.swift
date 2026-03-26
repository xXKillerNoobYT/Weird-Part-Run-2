import SwiftUI
import WiredPartCore

/// Notification preferences settings page.
///
/// Allows users to configure which types of notifications they
/// receive and how they are delivered. Currently an informational
/// placeholder that shows the planned notification categories.
struct NotificationPrefsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?
    @State private var orderAlerts = true
    @State private var certExpiry = true
    @State private var vehicleAlerts = true
    @State private var syncStatus = true
    @State private var soundEnabled = true
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Alert Categories") {
                Toggle("Order Status Changes", isOn: $orderAlerts)
                Toggle("Certification Expiry Warnings", isOn: $certExpiry)
                Toggle("Vehicle Maintenance Alerts", isOn: $vehicleAlerts)
                Toggle("Sync Status Notifications", isOn: $syncStatus)
            }

            Section("Delivery") {
                Toggle("Notification Sounds", isOn: $soundEnabled)
            }

            Section {
                Button {
                    savePrefs()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Preferences")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Text("Notification preferences are stored locally. Push notifications require the sync service to be configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Notifications Help", sections: [
                ("What This Page Does", "Controls which alert categories you receive and whether notification sounds are enabled. Categories include order status, certification expiry, vehicle maintenance, and sync status."),
                ("How to Use It", "Toggle each category on or off, then tap Save Preferences. Notification preferences are stored locally on this device."),
            ])
        }
        .onAppear { loadPrefs() }
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

    private func loadPrefs() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            let map = try service.getSettingsByCategory("notifications")
            orderAlerts = map["order_alerts"] != "false"
            certExpiry = map["cert_expiry"] != "false"
            vehicleAlerts = map["vehicle_alerts"] != "false"
            syncStatus = map["sync_status"] != "false"
            soundEnabled = map["sound_enabled"] != "false"
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func savePrefs() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            try service.upsertSettingsMap([
                "order_alerts": String(orderAlerts),
                "cert_expiry": String(certExpiry),
                "vehicle_alerts": String(vehicleAlerts),
                "sync_status": String(syncStatus),
                "sound_enabled": String(soundEnabled),
            ], category: "notifications")
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
