import SwiftUI
import WiredPartCore

/// Fully functional billing cycle and pay period settings page.
///
/// Reads and writes billing cycle (monthly/weekly + start day) and
/// pay period (biweekly/weekly/monthly + start day) via SettingsService.
struct BillingPayPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var activeSheet: ActiveSheet?

    // Billing Cycle
    @State private var billingCycleType = "monthly"
    @State private var billingStartDay = 1

    // Pay Period
    @State private var payPeriodType = "biweekly"
    @State private var payStartDay = 1

    @State private var saved = false
    @State private var errorMessage: String?
    // Fix #192: gate the form behind a loading state so the first render doesn't
    // flash the default values before loadSettings() returns.
    @State private var isLoading = true
    @State private var isDirty = false
    @State private var hasLoadedSettings = false
    @State private var showDiscardConfirmation = false

    private let cycleTypes = ["monthly", "weekly", "biweekly"]
    private let periodTypes = ["biweekly", "weekly", "monthly", "semimonthly"]

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView("Loading settings…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Billing & Pay")
                .task { loadSettings() }
        } else {
            loadedForm
        }
    }

    private var loadedForm: some View {
        Form {
            Section("Billing Cycle") {
                Picker("Cycle Type", selection: $billingCycleType) {
                    ForEach(cycleTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                Stepper("Start Day: \(billingStartDay)", value: $billingStartDay, in: 1...28)
            }

            Section("Pay Period") {
                Picker("Period Type", selection: $payPeriodType) {
                    ForEach(periodTypes, id: \.self) { type in
                        Text(type.capitalized).tag(type)
                    }
                }
                Stepper("Start Day: \(payStartDay)", value: $payStartDay, in: 1...28)
            }

            Section {
                Button {
                    saveSettings()
                } label: {
                    HStack {
                        Spacer()
                        Text(saved ? "Saved!" : "Save Billing & Pay Settings")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Billing & Pay")
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
            PageHelpSheet(title: "Billing & Pay Help", sections: [
                ("What This Page Does", "Sets your company's billing cycle and pay period. These control how reports, invoices, and payroll are grouped by date range."),
                ("How to Use It", "Choose cycle and period types, set the start day of each, then tap Save. The start day determines when each period begins (1-28)."),
            ])
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onChange(of: billingCycleType) { _, _ in markDirty() }
        .onChange(of: billingStartDay) { _, _ in markDirty() }
        .onChange(of: payPeriodType) { _, _ in markDirty() }
        .onChange(of: payStartDay) { _, _ in markDirty() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private func markDirty() {
        guard hasLoadedSettings else { return }
        isDirty = true
    }

    private func loadSettings() {
        defer { isLoading = false }   // Fix #192: drop the loading gate once read completes
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        hasLoadedSettings = false
        do {
            let billing = try service.getBillingCycle()
            billingCycleType = billing.cycleType
            billingStartDay = billing.startDay

            let pay = try service.getPayPeriod()
            payPeriodType = pay.periodType
            payStartDay = pay.startDay
        } catch {
            errorMessage = userFriendlyError(error, context: "load")
        }
        isDirty = false
        Task { @MainActor in
            hasLoadedSettings = true
        }
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            errorMessage = "Settings service unavailable"
            return
        }
        do {
            _ = try service.updateBillingCycle(
                SettingsService.BillingCycleSettings(cycleType: billingCycleType, startDay: billingStartDay)
            )
            _ = try service.updatePayPeriod(
                SettingsService.PayPeriodSettings(periodType: payPeriodType, startDay: payStartDay)
            )
            saved = true
            isDirty = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                saved = false
            }
        } catch {
            errorMessage = userFriendlyError(error, context: "save")
        }
    }
}
