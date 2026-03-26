import SwiftUI
import WiredPartCore

/// General application configuration settings.
///
/// Reads and writes key-value settings like auto-lock timeout,
/// stale data threshold, and archive days via SettingsService.
struct AppConfigPage: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var activeSheet: ActiveSheet?
    @State private var autoLockMinutes = "15"
    @State private var staleDataHours = "4"
    @State private var archiveDays = "90"
    @State private var warrantyDays = "365"
    @State private var paymentTrackingEnabled = false
    @State private var paymentTermsDays = 30
    @State private var overdueWarningDays = 7
    @State private var autoPaymentHold = false
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
                Toggle("Enable Payment Tracking", isOn: $paymentTrackingEnabled)

                if paymentTrackingEnabled {
                    Stepper("Payment Terms: \(paymentTermsDays) days", value: $paymentTermsDays, in: 7...120)
                    Stepper("Overdue Warning: \(overdueWarningDays) days before", value: $overdueWarningDays, in: 1...30)
                    Toggle("Auto Payment Hold", isOn: $autoPaymentHold)
                }
            } header: {
                Text("Payment Tracking")
            } footer: {
                Text("When enabled, track invoices and payments per customer. Shows payment status on customer detail pages.")
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
        .navigationTitle("App Config")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "App Config Help", sections: [
                ("What This Page Does", "General application configuration including auto-lock timeout, stale data warnings, archive retention, warranty defaults, and payment tracking settings."),
                ("How to Use It", "Adjust values for each setting and tap Save. Auto-lock controls how long before the app locks. Stale data warning triggers when sync data is old. Payment tracking enables invoice and payment monitoring per customer."),
            ])
        }
        .onAppear { loadConfig() }
        .alert("Error", isPresented: Binding(get: { loadError != nil || actionError != nil }, set: { if !$0 { loadError = nil; actionError = nil } })) {
            Button("OK") { loadError = nil; actionError = nil }
        } message: {
            Text(loadError ?? actionError ?? "")
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
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

            // Payment tracking settings
            if let peopleService = appCore.peopleService {
                paymentTrackingEnabled = (try? peopleService.isPaymentTrackingEnabled()) ?? false
                let paySettings = try? peopleService.getPaymentSettings()
                paymentTermsDays = paySettings?.termsDays ?? 30
                overdueWarningDays = paySettings?.warningDays ?? 7
                autoPaymentHold = paySettings?.autoHold ?? false
            }
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

            // Payment tracking settings
            if let peopleService = appCore.peopleService {
                try peopleService.setPaymentTrackingEnabled(paymentTrackingEnabled)
                try peopleService.updatePaymentSettings(
                    termsDays: paymentTermsDays,
                    warningDays: overdueWarningDays,
                    autoHold: autoPaymentHold
                )
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
