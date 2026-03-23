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
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Sync") {
                HStack {
                    Text("Stale Data Warning (hours)")
                    Spacer()
                    TextField("4", text: $staleDataHours)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Data Management") {
                HStack {
                    Text("Archive Completed Jobs (days)")
                    Spacer()
                    TextField("90", text: $archiveDays)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                HStack {
                    Text("Default Warranty (days)")
                    Spacer()
                    TextField("365", text: $warrantyDays)
                        .keyboardType(.numberPad)
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
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            return
        }
        do {
            autoLockMinutes = try service.getSetting("auto_lock_minutes") ?? "15"
            staleDataHours = try service.getSetting("stale_data_hours") ?? "4"
            archiveDays = try service.getSetting("archive_completed_days") ?? "90"
            let warranty = try service.getWarrantyLengthDays()
            warrantyDays = String(warranty)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func saveConfig() {
        guard let service = appCore.settingsService else {
            actionError = "Settings service unavailable"
            return
        }
        do {
            try service.updateSetting(key: "auto_lock_minutes", value: autoLockMinutes, category: "security")
            try service.updateSetting(key: "stale_data_hours", value: staleDataHours, category: "sync")
            try service.updateSetting(key: "archive_completed_days", value: archiveDays, category: "data")
            if let days = Int(warrantyDays) {
                try service.updateWarrantyLengthDays(days)
            }
            saved = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
