import SwiftUI
import WiredPartCore

/// Billing cycle and pay period configuration page.
///
/// Fully functional — reads/writes via SettingsService.
/// Two sections: billing cycle (type + start day) and pay period (type + start day).
struct BillingPayPage: View {
    @EnvironmentObject private var appCore: AppCore

    // Billing cycle
    @State private var billingType: String = "monthly"
    @State private var billingStartDay: Int = 1

    // Pay period
    @State private var payType: String = "biweekly"
    @State private var payStartDay: Int = 1

    @State private var showSaved: Bool = false

    private let billingTypes = ["weekly", "biweekly", "monthly", "quarterly"]
    private let payTypes = ["weekly", "biweekly", "semimonthly", "monthly"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Billing & Pay Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Billing Cycle
                GroupBox("Billing Cycle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controls the billing period for job cost tracking and invoicing.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Picker("Cycle Type", selection: $billingType) {
                            ForEach(billingTypes, id: \.self) { type in
                                Text(type.capitalized).tag(type)
                            }
                        }
                        .frame(maxWidth: 200)

                        Stepper("Start Day: \(billingStartDay)", value: $billingStartDay, in: 1...28)
                            .frame(maxWidth: 200)
                    }
                    .padding(.vertical, 4)
                }

                // Pay Period
                GroupBox("Pay Period") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Controls the pay period for timesheet and labor calculations.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Picker("Period Type", selection: $payType) {
                            ForEach(payTypes, id: \.self) { type in
                                Text(type.capitalized).tag(type)
                            }
                        }
                        .frame(maxWidth: 200)

                        Stepper("Start Day: \(payStartDay)", value: $payStartDay, in: 1...28)
                            .frame(maxWidth: 200)
                    }
                    .padding(.vertical, 4)
                }

                HStack {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)

                    if showSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .transition(.opacity)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { loadSettings() }
    }

    private func loadSettings() {
        guard let settings = appCore.settingsService else { return }
        if let billing = try? settings.getBillingCycle() {
            billingType = billing.cycleType
            billingStartDay = billing.startDay
        }
        if let pay = try? settings.getPayPeriod() {
            payType = pay.periodType
            payStartDay = pay.startDay
        }
    }

    private func save() {
        guard let settings = appCore.settingsService else { return }
        _ = try? settings.updateBillingCycle(SettingsService.BillingCycleSettings(
            cycleType: billingType,
            startDay: billingStartDay
        ))
        _ = try? settings.updatePayPeriod(SettingsService.PayPeriodSettings(
            periodType: payType,
            startDay: payStartDay
        ))

        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { showSaved = false }
        }
    }
}
