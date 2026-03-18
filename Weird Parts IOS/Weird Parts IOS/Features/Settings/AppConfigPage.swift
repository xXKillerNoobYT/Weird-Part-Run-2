import SwiftUI
import WiredPartCore

/// General application configuration settings.
///
/// Reads and writes key-value settings like auto-lock timeout,
/// stale data threshold, and archive days via SettingsService.
struct AppConfigPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var autoLockMinutes = "15"
    @State private var staleDataHours = "4"
    @State private var archiveDays = "90"
    @State private var warrantyDays = "365"
    @State private var saved = false
    @State private var loadError: String?
    @State private var actionError: String?

    var body: some View {
        Form {
            Section("Security") {
                HStack {
                    Text("Auto-Lock (minutes)")
                    Spacer()
                    TextField("15", text: $autoLockMinutes)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Sync") {
                HStack {
                    Text("Stale Data Warning (hours)")
                    Spacer()
                    TextField("4", text: $staleDataHours)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Data Management") {
                HStack {
                    Text("Archive Completed Jobs (days)")
                    Spacer()
                    TextField("90", text: $archiveDays)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                HStack {
                    Text("Default Warranty (days)")
                    Spacer()
                    TextField("365", text: $warrantyDays)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section {
                Button {
                    saveConfig()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Configuration")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { loadConfig() }
        .alert("Error", isPresented: Binding(get: { loadError != nil || actionError != nil }, set: { if !$0 { loadError = nil; actionError = nil } })) {
            Button("OK") { loadError = nil; actionError = nil }
        } message: {
            Text(loadError ?? actionError ?? "")
        }
    }

    private func loadConfig() {
        do {
            autoLockMinutes = try appCore.settingsService.getSetting("auto_lock_minutes") ?? "15"
            staleDataHours = try appCore.settingsService.getSetting("stale_data_hours") ?? "4"
            archiveDays = try appCore.settingsService.getSetting("archive_completed_days") ?? "90"
            let warranty = try appCore.settingsService.getWarrantyLengthDays()
            warrantyDays = String(warranty)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func saveConfig() {
        do {
            try appCore.settingsService.updateSetting(key: "auto_lock_minutes", value: autoLockMinutes, category: "security")
            try appCore.settingsService.updateSetting(key: "stale_data_hours", value: staleDataHours, category: "sync")
            try appCore.settingsService.updateSetting(key: "archive_completed_days", value: archiveDays, category: "data")
            if let days = Int(warrantyDays) {
                try appCore.settingsService.updateWarrantyLengthDays(days)
            }
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
