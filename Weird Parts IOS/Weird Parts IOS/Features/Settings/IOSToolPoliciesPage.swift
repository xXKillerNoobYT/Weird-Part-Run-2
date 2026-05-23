import SwiftUI
import WiredPartCore

/// Tool checkout, condition, maintenance, and trade policy settings.
///
/// All values are stored as key-value settings using the `tool_policy_` prefix.
struct IOSToolPoliciesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
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
                ErrorStateView(message: loadError)
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
            ])
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

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        do {
            let map = try service.getSettingsByCategory("tool_policy")

            maxCheckoutDays = Int(map["tool_policy_max_checkout_days"] ?? "") ?? 30
            overdueNotificationDays = Int(map["tool_policy_overdue_notification_days"] ?? "") ?? 7
            autoExtendOnActiveJob = (map["tool_policy_auto_extend_active_job"] ?? "true") == "true"

            requireCheckoutCondition = (map["tool_policy_require_checkout_condition"] ?? "true") == "true"
            requireReturnCondition = (map["tool_policy_require_return_condition"] ?? "true") == "true"
            requireDamagePhoto = (map["tool_policy_require_damage_photo"] ?? "false") == "true"

            maintenanceAfterCheckouts = Int(map["tool_policy_maintenance_after_checkouts"] ?? "") ?? 50
            maintenanceReminderDays = Int(map["tool_policy_maintenance_reminder_days"] ?? "") ?? 14

            allowTrades = (map["tool_policy_allow_trades"] ?? "true") == "true"
            tradeTimeoutDays = Int(map["tool_policy_trade_timeout_days"] ?? "") ?? 7
            requireTradeCondition = (map["tool_policy_require_trade_condition"] ?? "true") == "true"
        } catch {
            loadError = userFriendlyError(error, context: "load")
        }
        isLoading = false
    }

    private func saveSettings() {
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
            ]
            try service.upsertSettingsMap(data, category: "tool_policy")
            saveError = nil
        } catch {
            saveError = userFriendlyError(error, context: "save order")
        }
    }
}
