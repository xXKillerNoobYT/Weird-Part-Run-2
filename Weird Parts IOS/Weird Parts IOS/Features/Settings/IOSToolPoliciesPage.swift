import SwiftUI
import WiredPartCore

/// Tool checkout, condition, maintenance, trade, lost/stolen, and edit-verification
/// policy settings.
///
/// All values are stored as key-value settings using the `tool_policy_` prefix
/// (persisted via `SettingsService.upsertSettingsMap`/`getSettingsByCategory`,
/// same as every other typed settings page) and enforced by `ToolsService`
/// checkout/return/trade/edit/lost-stolen workflows through
/// `SettingsService.ToolPolicySettings`. See issue #438.
struct IOSToolPoliciesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var saveSuccessMessage: String?
    @State private var activeSheet: ActiveSheet?

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

    // Lost / Stolen
    @State private var allowLostStolenReports = true
    @State private var requireLostStolenLocation = false
    @State private var closeCheckoutOnLostStolen = true

    // Edit Verification
    @State private var editVerificationMode: SettingsService.ToolPolicySettings.EditVerificationMode = .pendingWithoutPermission

    @State private var isDirty = false

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
                ErrorStateView(message: loadError) {
                    isLoading = true
                    loadSettings()
                }
            } else {
                settingsForm
            }
        }
        .navigationTitle("Tool Policies")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Tool Policies Help", sections: [
                ("About Tool Policies", "Configure how tools are checked out, returned, maintained, and traded between workers."),
                ("Checkout Limits", "Set maximum durations and overdue notifications for tool checkouts. Auto-extend keeps tools checked out while the worker is on the job."),
                ("Condition Checks", "Require workers to report tool condition during checkout, return, and damage events."),
                ("Maintenance", "Schedule automatic maintenance after a number of checkouts or set reminder lead times."),
                ("Trades", "Allow workers to trade tools directly. Trades expire after the timeout period."),
                ("Lost/Stolen", "Control whether reports are allowed, whether location is required, and whether active checkouts close automatically."),
                ("Edit Verification", "Choose whether tool edits are applied directly or held for manager verification."),
            ])
            .presentationDetents([.medium, .large])
        }
        .task { loadSettings() }
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

            if let saveSuccessMessage {
                Section {
                    Label(saveSuccessMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                .accessibilityIdentifier("toolPoliciesSaveSuccessMessage")
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
                .accessibilityHint(isDirty ? "" : "Make changes to enable saving.")
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

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        saveError = nil
        saveSuccessMessage = nil

        do {
            let map = try service.getSettingsByCategory("tool_policy")

            var parser = SettingsValueParser()
            maxCheckoutDays = parser.int(map, key: "tool_policy_max_checkout_days", default: 30)
            overdueNotificationDays = parser.int(map, key: "tool_policy_overdue_notification_days", default: 7)
            autoExtendOnActiveJob = parser.bool(map, key: "tool_policy_auto_extend_active_job", default: true)

            requireCheckoutCondition = parser.bool(map, key: "tool_policy_require_checkout_condition", default: true)
            requireReturnCondition = parser.bool(map, key: "tool_policy_require_return_condition", default: true)
            requireDamagePhoto = parser.bool(map, key: "tool_policy_require_damage_photo", default: false)

            maintenanceAfterCheckouts = parser.int(map, key: "tool_policy_maintenance_after_checkouts", default: 50)
            maintenanceReminderDays = parser.int(map, key: "tool_policy_maintenance_reminder_days", default: 14)

            allowTrades = parser.bool(map, key: "tool_policy_allow_trades", default: true)
            tradeTimeoutDays = parser.int(map, key: "tool_policy_trade_timeout_days", default: 7)
            requireTradeCondition = parser.bool(map, key: "tool_policy_require_trade_condition", default: true)

            allowLostStolenReports = parser.bool(map, key: "tool_policy_allow_lost_stolen_reports", default: true)
            requireLostStolenLocation = parser.bool(map, key: "tool_policy_require_lost_stolen_location", default: false)
            closeCheckoutOnLostStolen = parser.bool(map, key: "tool_policy_close_checkout_on_lost_stolen", default: true)

            editVerificationMode = parser.rawEnum(map, key: "tool_policy_edit_verification_mode", default: SettingsService.ToolPolicySettings.EditVerificationMode.pendingWithoutPermission)
            try parser.throwIfInvalid()
            loadError = nil
        } catch {
            loadError = settingsHydrationMessage(error)
        }
        isLoading = false
        isDirty = false
    }

    private func saveSettings() {
        saveError = nil
        saveSuccessMessage = nil

        guard let service = appCore.settingsService else {
            saveError = "Settings service unavailable"
            return
        }

        do {
            let data: [String: String] = [
                "tool_policy_max_checkout_days": "\(maxCheckoutDays)",
                "tool_policy_overdue_notification_days": "\(overdueNotificationDays)",
                "tool_policy_auto_extend_active_job": autoExtendOnActiveJob ? "true" : "false",
                "tool_policy_require_checkout_condition": requireCheckoutCondition ? "true" : "false",
                "tool_policy_require_return_condition": requireReturnCondition ? "true" : "false",
                "tool_policy_require_damage_photo": requireDamagePhoto ? "true" : "false",
                "tool_policy_maintenance_after_checkouts": "\(maintenanceAfterCheckouts)",
                "tool_policy_maintenance_reminder_days": "\(maintenanceReminderDays)",
                "tool_policy_allow_trades": allowTrades ? "true" : "false",
                "tool_policy_trade_timeout_days": "\(tradeTimeoutDays)",
                "tool_policy_require_trade_condition": requireTradeCondition ? "true" : "false",
                "tool_policy_allow_lost_stolen_reports": allowLostStolenReports ? "true" : "false",
                "tool_policy_require_lost_stolen_location": requireLostStolenLocation ? "true" : "false",
                "tool_policy_close_checkout_on_lost_stolen": closeCheckoutOnLostStolen ? "true" : "false",
                "tool_policy_edit_verification_mode": editVerificationMode.rawValue,
            ]
            try service.upsertSettingsMap(data, category: "tool_policy")
            saveError = nil
            saveSuccessMessage = "Tool policies saved."
            isDirty = false
        } catch {
            saveSuccessMessage = nil
            saveError = userFriendlyError(error, context: "save order")
        }
    }

    private func markDirty() {
        isDirty = true
        saveSuccessMessage = nil
    }
}
