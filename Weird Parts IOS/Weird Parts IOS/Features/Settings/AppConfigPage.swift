import SwiftUI
import WiredPartCore

/// General application configuration settings.
///
/// Reads and writes key-value settings like auto-lock timeout,
/// stale data threshold, and archive days via SettingsService.
struct AppConfigPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
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
    @State private var didLoadConfig = false
    /// True when the last loadConfig() attempt failed (#1335). While set, Save is
    /// disabled and saveConfig() refuses to run: the form is showing built-in
    /// defaults, and persisting them would overwrite the company's real settings
    /// (including silently disabling payment tracking). Cleared by a successful load.
    @State private var configLoadFailed = false
    @State private var hasUnsavedChanges = false
    @State private var showDiscardConfirmation = false
    @State private var baselineFormSignature = ""

    /// Fix #150: input validity gate for the Save button — all numeric text fields must be non-empty positive integers.
    private var isFormValid: Bool {
        Int(autoLockMinutes).map { $0 > 0 } == true &&
        Int(staleDataHours).map { $0 > 0 } == true &&
        Int(archiveDays).map { $0 > 0 } == true &&
        Int(warrantyDays).map { $0 > 0 } == true
    }

    private var formSignature: String {
        [
            autoLockMinutes,
            staleDataHours,
            archiveDays,
            warrantyDays,
            String(paymentTrackingEnabled),
            String(paymentTermsDays),
            String(overdueWarningDays),
            String(autoPaymentHold),
        ].joined(separator: "|")
    }

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

            Section("Onboarding") {
                Button {
                    if let manager = appCore.onboardingManager {
                        manager.resetProgress()
                        manager.isOnboardingActive = true
                    }
                } label: {
                    Label("Restart App Tour", systemImage: "arrow.counterclockwise")
                }
            }

            if configLoadFailed {
                Section {
                    Label("Settings didn't load completely — some values shown may be defaults rather than your saved configuration. Saving is disabled to protect your saved settings.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button {
                        loadConfig()
                    } label: {
                        Label("Retry Load", systemImage: "arrow.clockwise")
                    }
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
                // Fix #150: prevent save with empty/invalid numeric inputs.
                // Fix #1335: prevent save after a failed load — the form holds
                // defaults, not the user's real configuration.
                .disabled(!isFormValid || configLoadFailed)
            }
        }
        // Fix #149: dismiss keyboard on scroll to free space when keyboard covers field
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("App Config")
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
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "App Config Help", sections: [
                ("What This Page Does", "General application configuration including auto-lock timeout, stale data warnings, archive retention, warranty defaults, and payment tracking settings."),
                ("How to Use It", "Adjust values for each setting and tap Save. Auto-lock controls how long before the app locks. Stale data warning triggers when sync data is old. Payment tracking enables invoice and payment monitoring per customer."),
            ])
        }
        .task {
            loadConfig()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .settingsPageInactive, object: nil)
        }
        .onChange(of: autoLockMinutes) { _, _ in postAIContextIfLoaded() }
        .onChange(of: staleDataHours) { _, _ in postAIContextIfLoaded() }
        .onChange(of: archiveDays) { _, _ in postAIContextIfLoaded() }
        .onChange(of: warrantyDays) { _, _ in postAIContextIfLoaded() }
        .onChange(of: paymentTrackingEnabled) { _, _ in postAIContextIfLoaded() }
        .onChange(of: paymentTermsDays) { _, _ in postAIContextIfLoaded() }
        .onChange(of: overdueWarningDays) { _, _ in postAIContextIfLoaded() }
        .onChange(of: autoPaymentHold) { _, _ in postAIContextIfLoaded() }
        .onChange(of: formSignature) { _, _ in
            updateDirtyStateIfLoaded()
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
        }
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
        didLoadConfig = false
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            configLoadFailed = true
            didLoadConfig = true
            postAIContext()
            return
        }
        do {
            autoLockMinutes = try service.getSetting("auto_lock_minutes") ?? "15"
            staleDataHours = try service.getSetting("stale_data_hours") ?? "4"
            archiveDays = try service.getSetting("archive_completed_days") ?? "90"
            let warranty = try service.getWarrantyLengthDays()
            warrantyDays = String(warranty)

            // Payment tracking settings — a read failure must NOT fall back to
            // defaults: Save would then persist those defaults over the company's
            // real payment terms (#1335). A throw routes to the catch below, which
            // marks the load failed and keeps Save disabled.
            if let peopleService = appCore.peopleService {
                paymentTrackingEnabled = try peopleService.isPaymentTrackingEnabled()
                let paySettings = try peopleService.getPaymentSettings()
                paymentTermsDays = paySettings.termsDays
                overdueWarningDays = paySettings.warningDays
                autoPaymentHold = paySettings.autoHold
            }
            configLoadFailed = false
            didLoadConfig = true
            resetDirtyTracking()
            postAIContext()
        } catch {
            loadError = userFriendlyError(error, context: "load settings")
            configLoadFailed = true
            didLoadConfig = true
            resetDirtyTracking()
            postAIContext()
        }
    }

    private func saveConfig() {
        // #1335 data-loss guard: after an incomplete load the form may hold
        // defaults for some fields — saving would overwrite good values in
        // the DB with those defaults.
        guard !configLoadFailed else {
            actionError = "Settings didn't load completely, so saving is disabled to protect your saved configuration. Tap Retry Load first."
            return
        }
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
            resetDirtyTracking()
            postAIContext()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            actionError = userFriendlyError(error, context: "complete action")
        }
    }

    private func postAIContextIfLoaded() {
        guard didLoadConfig else { return }
        postAIContext()
    }

    private func updateDirtyStateIfLoaded() {
        guard didLoadConfig else { return }
        hasUnsavedChanges = formSignature != baselineFormSignature
    }

    private func resetDirtyTracking() {
        baselineFormSignature = formSignature
        hasUnsavedChanges = false
    }

    private func postAIContext() {
        let context = """
        App Config settings page. Read-only context.
        Auto-lock minutes: \(autoLockMinutes), stale data warning hours: \(staleDataHours), archive completed jobs days: \(archiveDays), default warranty days: \(warrantyDays).
        Payment tracking enabled: \(paymentTrackingEnabled), payment terms days: \(paymentTermsDays), overdue warning days: \(overdueWarningDays), auto payment hold: \(autoPaymentHold).
        Form valid: \(isFormValid), saved confirmation visible: \(saved), load error present: \(loadError != nil), action error present: \(actionError != nil).
        Available read-only guidance: explain each setting, current visible values, validation state, payment tracking options, and where Save/Restart App Tour/help controls are located. Do not save or change settings directly.
        """
        NotificationCenter.default.post(
            name: .settingsPageActive,
            object: nil,
            userInfo: ["context": context]
        )
    }
}
