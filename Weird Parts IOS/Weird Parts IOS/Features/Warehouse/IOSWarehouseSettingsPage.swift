import SwiftUI
import WiredPartCore

/// Warehouse-specific configuration page.
///
/// Manages warehouse settings including default locations, stock thresholds,
/// movement policies, and audit preferences. Uses `.task` for initial load
/// and `.alert` for error display.
struct IOSWarehouseSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // Location defaults
    @State private var defaultReceivingLocation = "Receiving Dock"
    @State private var defaultStagingLocation = "Staging Area"

    // Stock thresholds
    @State private var lowStockThreshold = 5
    @State private var criticalStockThreshold = 1
    @State private var enableLowStockAlerts = true

    // Movement policies
    @State private var requireMovementNotes = false
    @State private var requireMovementApproval = false
    @State private var autoConfirmSmallMoves = true
    @State private var smallMoveThreshold = 10

    // Audit settings
    @State private var auditFrequencyDays = 30
    @State private var requirePhotoOnDiscrepancy = false

    // State
    @State private var isLoadingSettings = true
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var errorMessage: String?
    @State private var showHelp = false

    var body: some View {
        Group {
            if isLoadingSettings {
                ProgressView("Loading settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                settingsForm
            }
        }
        .navigationTitle("Warehouse Settings")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            PageHelpSheet(
                title: "Warehouse Settings Help",
                sections: [
                    ("Locations", "Configure default receiving and staging locations used when new shipments arrive or parts are pulled."),
                    ("Thresholds", "Set low stock and critical stock thresholds. Enable alerts to be notified when parts drop below these levels."),
                    ("Policies", "Control whether movements require notes or approval, and set thresholds for auto-confirming small moves.")
                ]
            )
        }
        .task { loadSettings() }
        .alert("Settings Saved", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Warehouse settings have been updated.")
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    private var settingsForm: some View {
        Form {
            // Default locations
            Section("Default Locations") {
                TextField("Receiving Location", text: $defaultReceivingLocation)
                TextField("Staging Location", text: $defaultStagingLocation)
            }

            // Stock thresholds
            Section {
                Toggle("Low Stock Alerts", isOn: $enableLowStockAlerts)

                if enableLowStockAlerts {
                    Stepper("Low Stock Threshold: \(lowStockThreshold)", value: $lowStockThreshold, in: 1...100)
                    Stepper("Critical Threshold: \(criticalStockThreshold)", value: $criticalStockThreshold, in: 0...lowStockThreshold)
                }
            } header: {
                Text("Stock Thresholds")
            } footer: {
                Text("Parts below the low stock threshold will be flagged. Critical threshold triggers urgent alerts.")
            }

            // Movement policies
            Section {
                Toggle("Require Notes on Movements", isOn: $requireMovementNotes)
                Toggle("Require Approval for Movements", isOn: $requireMovementApproval)
                Toggle("Auto-confirm Small Moves", isOn: $autoConfirmSmallMoves)

                if autoConfirmSmallMoves {
                    Stepper("Small Move Max: \(smallMoveThreshold) items", value: $smallMoveThreshold, in: 1...50)
                }
            } header: {
                Text("Movement Policies")
            } footer: {
                Text("Controls how warehouse movements are validated and approved.")
            }

            // Audit settings
            Section {
                Stepper("Audit Every: \(auditFrequencyDays) days", value: $auditFrequencyDays, in: 7...365, step: 7)
                Toggle("Require Photo on Discrepancy", isOn: $requirePhotoOnDiscrepancy)
            } header: {
                Text("Audit")
            } footer: {
                Text("Configure how often audits should occur and what evidence is required.")
            }

            // Save
            Section {
                Button {
                    saveSettings()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save Settings")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }
        }
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        isSaving = true
        do {
            try service.upsertSettingsMap([
                "default_receiving_location": defaultReceivingLocation,
                "default_staging_location": defaultStagingLocation,
                "low_stock_threshold": "\(lowStockThreshold)",
                "critical_stock_threshold": "\(criticalStockThreshold)",
                "enable_low_stock_alerts": enableLowStockAlerts ? "1" : "0",
                "require_movement_notes": requireMovementNotes ? "1" : "0",
                "require_movement_approval": requireMovementApproval ? "1" : "0",
                "auto_confirm_small_moves": autoConfirmSmallMoves ? "1" : "0",
                "small_move_threshold": "\(smallMoveThreshold)",
                "audit_frequency_days": "\(auditFrequencyDays)",
                "require_photo_on_discrepancy": requirePhotoOnDiscrepancy ? "1" : "0",
            ], category: "warehouse")
            isSaving = false
            showSaveConfirmation = true
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSaving = false
        }
    }

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            isLoadingSettings = false
            return
        }
        do {
            let s = try service.getSettingsByCategory("warehouse")
            if let v = s["default_receiving_location"] { defaultReceivingLocation = v }
            if let v = s["default_staging_location"] { defaultStagingLocation = v }
            if let v = s["low_stock_threshold"], let n = Int(v) { lowStockThreshold = n }
            if let v = s["critical_stock_threshold"], let n = Int(v) { criticalStockThreshold = n }
            if let v = s["enable_low_stock_alerts"] { enableLowStockAlerts = v == "1" }
            if let v = s["require_movement_notes"] { requireMovementNotes = v == "1" }
            if let v = s["require_movement_approval"] { requireMovementApproval = v == "1" }
            if let v = s["auto_confirm_small_moves"] { autoConfirmSmallMoves = v == "1" }
            if let v = s["small_move_threshold"], let n = Int(v) { smallMoveThreshold = n }
            if let v = s["audit_frequency_days"], let n = Int(v) { auditFrequencyDays = n }
            if let v = s["require_photo_on_discrepancy"] { requirePhotoOnDiscrepancy = v == "1" }
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
        isLoadingSettings = false
    }
}
