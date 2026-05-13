import SwiftUI
import WiredPartCore

/// Tool checkout, condition, maintenance, and trade policy settings.
///
/// All values are stored as key-value settings using the `tool_policy_` prefix.
struct IOSToolPoliciesPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var activeSheet: ActiveSheet?
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

    // Checkout Limits
    @State private var maxCheckoutDays: Int = 30
    @State private var overdueNotificationDays: Int = 7
    @State private var autoExtendOnActiveJob = true

    // Condition Checks
    @State private var requireCheckoutCondition = true
    @State private var requireReturnCondition = true
    @State private var requireDamagePhoto = false

    // Maintenance
    @State private var maintenanceAfterCheckouts: Int = 50
    @State private var maintenanceReminderDays: Int = 14

    // Trades
    @State private var allowTrades = true
    @State private var tradeTimeoutDays: Int = 7
    @State private var requireTradeCondition = true

    // Lost / stolen
    @State private var allowLostStolenReports = true
    @State private var requireLostStolenLocation = false
    @State private var closeCheckoutOnLostStolen = true

    // Edit verification
    @State private var editVerificationMode: SettingsService.ToolPolicySettings.EditVerificationMode = .pendingWithoutPermission

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading tool policies...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                settingsForm
            }
        }
        .navigationTitle("Tool Policies")
        .navigationBarTitleDisplayMode(.inline)
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
                PageHelpSheet(title: "Tool Policies Help", sections: [
                    ("About Tool Policies", "Configure how tools are checked out, returned, maintained, and traded between workers."),
                    ("Checkout Limits", "Set maximum durations and overdue notifications for tool checkouts. Auto-extend keeps tools checked out while the worker is on the job."),
                    ("Condition Checks", "Require workers to report tool condition during checkout, return, and damage events."),
                    ("Maintenance", "Schedule automatic maintenance after a number of checkouts or set reminder lead times."),
                    ("Trades", "Allow workers to trade tools directly. Trades expire after the timeout period."),
                    ("Lost/Stolen", "Control whether reports are allowed, whether location is required, and whether active checkouts close automatically."),
                    ("Edit Verification", "Choose whether tool edits are applied directly or held for manager verification."),
                ])
            }
            .presentationDetents([.medium, .large])
        }
        .task { loadSettings() }
        .interactiveDismissDisabled(isDirty)
        .alert("Discard changes?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
    }

    // MARK: - Form

    private var settingsForm: some View {
        Form {
            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Checkout Limits
            Section {
                Stepper("Max checkout: \(maxCheckoutDays) days", value: $maxCheckoutDays, in: 1...365)
                Stepper("Overdue alert: \(overdueNotificationDays) days before", value: $overdueNotificationDays, in: 1...30)
                Toggle("Auto-extend on active job", isOn: $autoExtendOnActiveJob)
            } header: {
                Label("Checkout Limits", systemImage: "clock.badge.checkmark")
            } footer: {
                Text("Auto-extend keeps the checkout active as long as the worker is clocked into the associated job.")
            }

            // Condition Checks
            Section {
                Toggle("Require on checkout", isOn: $requireCheckoutCondition)
                Toggle("Require on return", isOn: $requireReturnCondition)
                Toggle("Require photo on damage", isOn: $requireDamagePhoto)
            } header: {
                Label("Condition Checks", systemImage: "checkmark.shield")
            } footer: {
                Text("Condition checks track tool wear over time and help identify misuse.")
            }

            // Maintenance
            Section {
                Stepper("After \(maintenanceAfterCheckouts) checkouts", value: $maintenanceAfterCheckouts, in: 5...500, step: 5)
                Stepper("Reminder: \(maintenanceReminderDays) days before due", value: $maintenanceReminderDays, in: 1...60)
            } header: {
                Label("Maintenance Schedule", systemImage: "wrench.and.screwdriver")
            } footer: {
                Text("Auto-schedule maintenance after a certain number of checkouts.")
            }

            // Trades
            Section {
                Toggle("Allow tool trades", isOn: $allowTrades)
                if allowTrades {
                    Stepper("Timeout: \(tradeTimeoutDays) days", value: $tradeTimeoutDays, in: 1...30)
                    Toggle("Require condition check", isOn: $requireTradeCondition)
                }
            } header: {
                Label("Trades", systemImage: "arrow.triangle.swap")
            } footer: {
                Text("When enabled, workers can trade tools directly. Unaccepted trades expire after the timeout.")
            }

            // Lost / Stolen
            Section {
                Toggle("Allow lost/stolen reports", isOn: $allowLostStolenReports)
                if allowLostStolenReports {
                    Toggle("Require last known location", isOn: $requireLostStolenLocation)
                    Toggle("Close active checkout", isOn: $closeCheckoutOnLostStolen)
                }
            } header: {
                Label("Lost/Stolen", systemImage: "exclamationmark.octagon")
            } footer: {
                Text("Lost or stolen reports update tool status and can close the open checkout automatically.")
            }

            // Edit Verification
            Section {
                Picker("Edit handling", selection: $editVerificationMode) {
                    Text("Verify unapproved users").tag(SettingsService.ToolPolicySettings.EditVerificationMode.pendingWithoutPermission)
                    Text("Verify every edit").tag(SettingsService.ToolPolicySettings.EditVerificationMode.alwaysPending)
                    Text("Apply edits directly").tag(SettingsService.ToolPolicySettings.EditVerificationMode.directEdits)
                }
            } header: {
                Label("Edit Verification", systemImage: "checkmark.seal")
            } footer: {
                Text("Verification creates manager-review records before changes are applied.")
            }

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty)
                .accessibilityHint(isDirty ? "Saves tool policy changes" : "Make a tool policy change before saving")
            }
        }
        .onChange(of: maxCheckoutDays) { _, _ in markDirty() }
        .onChange(of: overdueNotificationDays) { _, _ in markDirty() }
        .onChange(of: autoExtendOnActiveJob) { _, _ in markDirty() }
        .onChange(of: requireCheckoutCondition) { _, _ in markDirty() }
        .onChange(of: requireReturnCondition) { _, _ in markDirty() }
        .onChange(of: requireDamagePhoto) { _, _ in markDirty() }
        .onChange(of: maintenanceAfterCheckouts) { _, _ in markDirty() }
        .onChange(of: maintenanceReminderDays) { _, _ in markDirty() }
        .onChange(of: allowTrades) { _, _ in markDirty() }
        .onChange(of: tradeTimeoutDays) { _, _ in markDirty() }
        .onChange(of: requireTradeCondition) { _, _ in markDirty() }
        .onChange(of: allowLostStolenReports) { _, _ in markDirty() }
        .onChange(of: requireLostStolenLocation) { _, _ in markDirty() }
        .onChange(of: closeCheckoutOnLostStolen) { _, _ in markDirty() }
        .onChange(of: editVerificationMode) { _, _ in markDirty() }
    }

    // MARK: - Actions

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
    }

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        hasLoadedSettings = false
        do {
            let policies = try service.getToolPolicies()

            maxCheckoutDays = policies.maxCheckoutDays
            overdueNotificationDays = policies.overdueNotificationDays
            autoExtendOnActiveJob = policies.autoExtendOnActiveJob

            requireCheckoutCondition = policies.requireCheckoutCondition
            requireReturnCondition = policies.requireReturnCondition
            requireDamagePhoto = policies.requireDamagePhoto

            maintenanceAfterCheckouts = policies.maintenanceAfterCheckouts
            maintenanceReminderDays = policies.maintenanceReminderDays

            allowTrades = policies.allowTrades
            tradeTimeoutDays = policies.tradeTimeoutDays
            requireTradeCondition = policies.requireTradeCondition

            allowLostStolenReports = policies.allowLostStolenReports
            requireLostStolenLocation = policies.requireLostStolenLocation
            closeCheckoutOnLostStolen = policies.closeCheckoutOnLostStolen
            editVerificationMode = policies.editVerificationMode
        } catch {
            loadError = userFriendlyError(error, context: "load")
        }
        isLoading = false
        isDirty = false
        Task { @MainActor in
            hasLoadedSettings = true
        }
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            saveError = "Settings service unavailable"
            return
        }

        do {
            let policies = SettingsService.ToolPolicySettings(
                maxCheckoutDays: maxCheckoutDays,
                overdueNotificationDays: overdueNotificationDays,
                autoExtendOnActiveJob: autoExtendOnActiveJob,
                requireCheckoutCondition: requireCheckoutCondition,
                requireReturnCondition: requireReturnCondition,
                requireDamagePhoto: requireDamagePhoto,
                maintenanceAfterCheckouts: maintenanceAfterCheckouts,
                maintenanceReminderDays: maintenanceReminderDays,
                allowTrades: allowTrades,
                tradeTimeoutDays: tradeTimeoutDays,
                requireTradeCondition: requireTradeCondition,
                allowLostStolenReports: allowLostStolenReports,
                requireLostStolenLocation: requireLostStolenLocation,
                closeCheckoutOnLostStolen: closeCheckoutOnLostStolen,
                editVerificationMode: editVerificationMode
            )
            _ = try service.updateToolPolicies(policies)
            saveError = nil
            isDirty = false
        } catch {
            saveError = userFriendlyError(error, context: "save order")
        }
    }
}
