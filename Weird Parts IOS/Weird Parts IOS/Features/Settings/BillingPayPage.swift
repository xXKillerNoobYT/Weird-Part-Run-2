import SwiftUI
import WiredPartCore

/// Fully functional billing cycle and pay period settings page.
///
/// Reads and writes billing cycle (monthly/weekly + start day) and
/// pay period (biweekly/weekly/monthly + start day) via SettingsService.
struct BillingPayPage: View {
    @EnvironmentObject private var appCore: AppCore

    // Billing Cycle
    @State private var billingCycleType = "monthly"
    @State private var billingStartDay = 1

    // Pay Period
    @State private var payPeriodType = "biweekly"
    @State private var payStartDay = 1

    @State private var saved = false
    @State private var errorMessage: String?

    private let cycleTypes = ["monthly", "weekly", "biweekly"]
    private let periodTypes = ["biweekly", "weekly", "monthly", "semimonthly"]

    var body: some View {
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
        .onAppear { loadSettings() }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadSettings() {
        do {
            let billing = try appCore.settingsService.getBillingCycle()
            billingCycleType = billing.cycleType
            billingStartDay = billing.startDay

            let pay = try appCore.settingsService.getPayPeriod()
            payPeriodType = pay.periodType
            payStartDay = pay.startDay
        } catch {
            print("[BillingPayPage] Load error: \(error)")
        }
    }

    private func saveSettings() {
        do {
            _ = try appCore.settingsService.updateBillingCycle(
                SettingsService.BillingCycleSettings(cycleType: billingCycleType, startDay: billingStartDay)
            )
            _ = try appCore.settingsService.updatePayPeriod(
                SettingsService.PayPeriodSettings(periodType: payPeriodType, startDay: payStartDay)
            )
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
