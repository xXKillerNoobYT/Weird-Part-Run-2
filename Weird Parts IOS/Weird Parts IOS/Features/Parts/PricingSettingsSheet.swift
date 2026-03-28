import SwiftUI
import WiredPartCore

/// Company-wide pricing settings: mode toggle, default markup, stale threshold.
struct PricingSettingsSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var pricingMode = "markup"
    @State private var defaultMarkup = ""
    @State private var staleThresholdDays = ""
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Display Mode", selection: $pricingMode) {
                        Text("Markup (% on cost)").tag("markup")
                        Text("Margin (% of sell price)").tag("margin")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Pricing Mode")
                } footer: {
                    if pricingMode == "markup" {
                        Text("Markup: (Sell - Cost) ÷ Cost × 100\nExample: Cost $10, Sell $15 = 50% markup")
                    } else {
                        Text("Margin: (Sell - Cost) ÷ Sell × 100\nExample: Cost $10, Sell $15 = 33.3% margin")
                    }
                }

                Section {
                    HStack {
                        Text("Default")
                        Spacer()
                        TextField("50", text: $defaultMarkup)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                            .keyboardType(.decimalPad)
                        Text("%")
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Default Markup")
                } footer: {
                    Text("Applied to parts with no tier pricing set at any level.")
                }

                Section {
                    HStack {
                        Text("Alert after")
                        Spacer()
                        TextField("90", text: $staleThresholdDays)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                            .keyboardType(.numberPad)
                        Text("days")
                    }
                    .frame(minHeight: 44)
                } header: {
                    Text("Stale Price Alert")
                } footer: {
                    Text("Parts not updated in this many days show a warning when ordering. Recommended: check the receipt to verify pricing.")
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Pricing Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving)
                }
            }
            .task { await loadSettings() }
        }
    }

    private func loadSettings() async {
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            return
        }
        pricingMode = (try? service.getCompanyCostSetting(key: "pricing_mode")) ?? "markup"
        defaultMarkup = (try? service.getCompanyCostSetting(key: "default_markup_percent")) ?? "50"
        staleThresholdDays = (try? service.getCompanyCostSetting(key: "stale_price_threshold_days")) ?? "90"
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            guard let service = appCore.partsService else {
                saveError = "Parts service not available"
                isSaving = false
                return
            }
            try service.updateCompanyCostSetting(key: "pricing_mode", value: pricingMode)
            try service.updateCompanyCostSetting(key: "default_markup_percent", value: defaultMarkup)
            try service.updateCompanyCostSetting(key: "stale_price_threshold_days", value: staleThresholdDays)
            await onSave()
            dismiss()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
        isSaving = false
    }
}
