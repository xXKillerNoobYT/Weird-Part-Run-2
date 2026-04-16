import SwiftUI
import WiredPartCore

/// Break/lunch compliance settings page.
///
/// 6-section form:
/// 1. State Required Paid (read-only from break_policies)
/// 2. State Required Offered Unpaid (read-only)
/// 3. Company Extra Paid (editable)
/// 4. Company Extra Offered (editable)
/// 5. Bonuses (optional, per area: lunch + breaks)
/// 6. Full Breakdown (combined view)
struct IOSBreakSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var activeSheet: ActiveSheet?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Company settings
    @State private var selectedState: String = "WY"
    @State private var roundingMinutes: Int = 15
    @State private var roundingEnabled = false
    @State private var autoFillBreaks = true
    @State private var defaultMorningBreak: String = "10:00"
    @State private var defaultLunch: String = "12:00"
    @State private var defaultAfternoonBreak: String = "14:30"

    // Policies
    @State private var allPolicies: [BreakPolicy] = []
    @State private var bonuses: [BreakBonus] = []

    // Company editable policies
    @State private var companyPaidLunchMin: Int = 0
    @State private var companyPaidBreakCount: Int = 0
    @State private var companyPaidBreakMin: Int = 10
    @State private var companyOfferedLunchMin: Int = 0
    @State private var companyOfferedBreakCount: Int = 0
    @State private var companyOfferedBreakMin: Int = 10

    // Bonus editing
    @State private var lunchBonusAmount: Double = 0
    @State private var breakBonusAmount: Double = 0
    @State private var lunchBonusEnabled = false
    @State private var breakBonusEnabled = false

    private let stateOptions = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY"
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading break settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                settingsForm
            }
        }
        .navigationTitle("Break & Lunch")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Break & Lunch Help", sections: [
                ("What This Page Does", "Configures break and lunch compliance rules. Shows state-required breaks (read-only), company extra breaks (editable), bonus incentives, and a full breakdown of total break allowances."),
                ("How to Use It", "Select your state to load legal requirements. Adjust company-paid and offered breaks using the steppers. Enable bonuses to reward employees who use break buttons. Tap Save to apply all changes."),
            ])
        }
        .task { loadSettings() }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Form

    private var settingsForm: some View {
        Form {
            // Error/success banners
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            if let successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            // State picker
            Section {
                Picker("State", selection: $selectedState) {
                    ForEach(stateOptions, id: \.self) { state in
                        Text(state).tag(state)
                    }
                }
                .onChange(of: selectedState) { _, _ in
                    loadPoliciesForState()
                }

                Button {
                    loadPoliciesForState()
                } label: {
                    Label("Update Data", systemImage: "arrow.clockwise")
                }
            } header: {
                Text("State Labor Law")
            } footer: {
                Text("State-required break policies are loaded from stored labor law data. Select your state to see applicable requirements.")
            }

            // Section 1: State Required Paid
            stateRequiredPaidSection

            // Section 2: State Required Offered Unpaid
            stateRequiredOfferedSection

            // Section 3: Company Extra Paid
            companyExtraPaidSection

            // Section 4: Company Extra Offered
            companyExtraOfferedSection

            // Section 5: Bonuses
            bonusesSection

            // Section 6: Full Breakdown
            fullBreakdownSection

            // Auto-fill & timing settings
            autoFillSection

            // Save button
            Section {
                Button {
                    saveSettings()
                } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        // Fix #149: dismiss keyboard when scrolling break settings
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Section 1: State Required Paid

    private var stateRequiredPaidSection: some View {
        Section {
            let policy = allPolicies.first { $0.policyType == "state_required_paid" && $0.stateCode == selectedState }
            if let p = policy {
                LabeledContent("Lunch (paid)", value: "\(p.lunchMinutes) min")
                LabeledContent("Breaks (paid)", value: "\(p.breakCount) × \(p.breakMinutes) min")
                LabeledContent("Work Day", value: "\(p.workDayHours)+ hours")
                LabeledContent("Source", value: p.dataSource ?? "state law")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No state-required paid break policy found for \(selectedState).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("State Required — Paid")
            }
        } footer: {
            Text("These are legally required paid breaks. Read-only — determined by state law.")
        }
    }

    // MARK: - Section 2: State Required Offered Unpaid

    private var stateRequiredOfferedSection: some View {
        Section {
            let policy = allPolicies.first { $0.policyType == "state_required_offered" && $0.stateCode == selectedState }
            if let p = policy {
                LabeledContent("Lunch (unpaid, offered)", value: "\(p.lunchMinutes) min")
                LabeledContent("Breaks (offered)", value: "\(p.breakCount) × \(p.breakMinutes) min")
            } else {
                Text("No state-required offered break policy found for \(selectedState).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("State Required — Offered Unpaid")
            }
        } footer: {
            Text("Breaks that must be offered but may be unpaid. Read-only.")
        }
    }

    // MARK: - Section 3: Company Extra Paid

    private var companyExtraPaidSection: some View {
        Section {
            Stepper("Lunch: \(companyPaidLunchMin) min", value: $companyPaidLunchMin, in: 0...60, step: 5)
            Stepper("Breaks: \(companyPaidBreakCount) × \(companyPaidBreakMin) min",
                    value: $companyPaidBreakCount, in: 0...4)
            if companyPaidBreakCount > 0 {
                Stepper("Break duration: \(companyPaidBreakMin) min",
                        value: $companyPaidBreakMin, in: 5...30, step: 5)
            }
        } header: {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Company Extra — Paid")
            }
        } footer: {
            Text("Additional paid breaks beyond state requirements. These are your company's policy.")
        }
    }

    // MARK: - Section 4: Company Extra Offered

    private var companyExtraOfferedSection: some View {
        Section {
            Stepper("Lunch: \(companyOfferedLunchMin) min", value: $companyOfferedLunchMin, in: 0...60, step: 5)
            Stepper("Breaks: \(companyOfferedBreakCount) × \(companyOfferedBreakMin) min",
                    value: $companyOfferedBreakCount, in: 0...4)
            if companyOfferedBreakCount > 0 {
                Stepper("Break duration: \(companyOfferedBreakMin) min",
                        value: $companyOfferedBreakMin, in: 5...30, step: 5)
            }
        } header: {
            HStack {
                Image(systemName: "gift.fill")
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)
                Text("Company Extra — Offered")
            }
        } footer: {
            Text("Additional breaks offered but not paid. Employees may take these voluntarily.")
        }
    }

    // MARK: - Section 5: Bonuses

    private var bonusesSection: some View {
        Section {
            Toggle("Break Bonus Enabled", isOn: $breakBonusEnabled)
            if breakBonusEnabled {
                HStack {
                    Text("Break Bonus Amount")
                    Spacer()
                    TextField("$0.00", value: $breakBonusAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Toggle("Lunch Bonus Enabled", isOn: $lunchBonusEnabled)
            if lunchBonusEnabled {
                HStack {
                    Text("Lunch Bonus Amount")
                    Spacer()
                    TextField("$0.00", value: $lunchBonusAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            }

            Text("Bonuses are earned when employees use break buttons (not auto-filled) and stick to state-minimum breaks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Bonuses")
            }
        }
    }

    // MARK: - Section 6: Full Breakdown

    private var fullBreakdownSection: some View {
        Section {
            let stateP = allPolicies.first { $0.policyType == "state_required_paid" && $0.stateCode == selectedState }

            // Total paid lunch
            let totalPaidLunch = (stateP?.lunchMinutes ?? 0) + companyPaidLunchMin
            LabeledContent("Total Paid Lunch", value: "\(totalPaidLunch) min")
                .fontWeight(.medium)

            // Total paid breaks
            let stateBreaks = (stateP?.breakCount ?? 0) * (stateP?.breakMinutes ?? 0)
            let companyBreaks = companyPaidBreakCount * companyPaidBreakMin
            let totalPaidBreaks = stateBreaks + companyBreaks
            LabeledContent("Total Paid Break Time", value: "\(totalPaidBreaks) min")
                .fontWeight(.medium)

            // Total offered (unpaid)
            let totalOfferedLunch = companyOfferedLunchMin
            let totalOfferedBreaks = companyOfferedBreakCount * companyOfferedBreakMin
            if totalOfferedLunch > 0 || totalOfferedBreaks > 0 {
                LabeledContent("Offered Unpaid Lunch", value: "\(totalOfferedLunch) min")
                LabeledContent("Offered Unpaid Breaks", value: "\(totalOfferedBreaks) min")
            }

            // Grand total
            let grandTotal = totalPaidLunch + totalPaidBreaks + totalOfferedLunch + totalOfferedBreaks
            Divider()
            LabeledContent("Total Break Allowance", value: "\(grandTotal) min")
                .fontWeight(.bold)
        } header: {
            HStack {
                Image(systemName: "list.clipboard.fill")
                    .foregroundStyle(.indigo)
                    .accessibilityHidden(true)
                Text("Full Breakdown")
            }
        }
    }

    // MARK: - Auto-Fill Section

    private var autoFillSection: some View {
        Section {
            Toggle("Auto-Fill Breaks at Clock Out", isOn: $autoFillBreaks)

            Toggle("Time Rounding", isOn: $roundingEnabled)
            if roundingEnabled {
                Stepper("Round to nearest \(roundingMinutes) min", value: $roundingMinutes, in: 5...30, step: 5)
            }

            HStack {
                Text("Morning Break")
                Spacer()
                TextField("10:00", text: $defaultMorningBreak)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Lunch")
                Spacer()
                TextField("12:00", text: $defaultLunch)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Afternoon Break")
                Spacer()
                TextField("14:30", text: $defaultAfternoonBreak)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.system(.body, design: .monospaced))
            }
        } header: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)
                Text("Auto-Fill & Timing")
            }
        } footer: {
            Text("When auto-fill is on, if an employee clocks out without having used break buttons, the system auto-fills break records at these default times for compliance.")
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        guard let breakSvc = appCore.breakService else {
            errorMessage = "Break service unavailable"
            isLoading = false
            return
        }

        do {
            let settings = try breakSvc.getCompanyBreakSettings()
            selectedState = settings.stateCode
            roundingMinutes = settings.roundingMinutes
            roundingEnabled = settings.roundingEnabled
            autoFillBreaks = settings.autoFillBreaks
            defaultMorningBreak = settings.defaultMorningBreak ?? "10:00"
            defaultLunch = settings.defaultLunch ?? "12:00"
            defaultAfternoonBreak = settings.defaultAfternoonBreak ?? "14:30"

            allPolicies = try breakSvc.getAllPolicies()
            loadCompanyPolicies()
            loadBonuses()
        } catch {
            errorMessage = userFriendlyError(error, context: "load settings")
        }
        isLoading = false
    }

    private func loadPoliciesForState() {
        guard let breakSvc = appCore.breakService else {
            errorMessage = "Service not available"
            return
        }
        do {
            allPolicies = try breakSvc.getAllPolicies()
        } catch {
            errorMessage = userFriendlyError(error, context: "load policies")
        }
    }

    private func loadCompanyPolicies() {
        let companyPaid = allPolicies.first { $0.policyType == "company_extra_paid" }
        if let p = companyPaid {
            companyPaidLunchMin = p.lunchMinutes
            companyPaidBreakCount = p.breakCount
            companyPaidBreakMin = p.breakMinutes
        }

        let companyOffered = allPolicies.first { $0.policyType == "company_extra_offered" }
        if let p = companyOffered {
            companyOfferedLunchMin = p.lunchMinutes
            companyOfferedBreakCount = p.breakCount
            companyOfferedBreakMin = p.breakMinutes
        }
    }

    private func loadBonuses() {
        guard let breakSvc = appCore.breakService else {
            errorMessage = "Service not available"
            return
        }

        // Find the state policy to get its ID for bonuses
        let statePolicy = allPolicies.first { $0.policyType == "state_required_paid" && $0.stateCode == selectedState }
        guard let policyId = statePolicy?.id else { return }

        do {
            bonuses = try breakSvc.getBreakBonuses(policyId: policyId)
            let lunchBonus = bonuses.first { $0.bonusType == "lunch" }
            let breakBonus = bonuses.first { $0.bonusType == "break" }

            lunchBonusAmount = lunchBonus?.bonusAmount ?? 0
            lunchBonusEnabled = lunchBonus?.isEnabled ?? false
            breakBonusAmount = breakBonus?.bonusAmount ?? 0
            breakBonusEnabled = breakBonus?.isEnabled ?? false
        } catch {
            // Non-critical — bonus data is supplemental; missing bonuses don't affect break compliance
            // usability-hunter: acceptable
        }
    }

    private func saveSettings() {
        guard let breakSvc = appCore.breakService else {
            errorMessage = "Break service unavailable"
            return
        }

        do {
            // Save company settings
            try breakSvc.updateCompanyBreakSettings(
                stateCode: selectedState,
                roundingMinutes: roundingMinutes,
                roundingEnabled: roundingEnabled,
                autoFillBreaks: autoFillBreaks,
                defaultMorningBreak: defaultMorningBreak,
                defaultLunch: defaultLunch,
                defaultAfternoonBreak: defaultAfternoonBreak
            )

            // Save company extra paid policy
            try breakSvc.savePolicy(
                stateCode: nil,
                policyType: "company_extra_paid",
                lunchMinutes: companyPaidLunchMin,
                breakCount: companyPaidBreakCount,
                breakMinutes: companyPaidBreakMin
            )

            // Save company extra offered policy
            try breakSvc.savePolicy(
                stateCode: nil,
                policyType: "company_extra_offered",
                lunchMinutes: companyOfferedLunchMin,
                breakCount: companyOfferedBreakCount,
                breakMinutes: companyOfferedBreakMin
            )

            // Save bonuses
            let statePolicy = allPolicies.first { $0.policyType == "state_required_paid" && $0.stateCode == selectedState }
            if let policyId = statePolicy?.id {
                // Toggle existing bonuses
                for bonus in bonuses {
                    if bonus.bonusType == "lunch" {
                        try breakSvc.toggleBonus(bonusId: bonus.id ?? 0, isEnabled: lunchBonusEnabled)
                    } else if bonus.bonusType == "break" {
                        try breakSvc.toggleBonus(bonusId: bonus.id ?? 0, isEnabled: breakBonusEnabled)
                    }
                }

                // Create bonuses if they don't exist yet
                if !bonuses.contains(where: { $0.bonusType == "lunch" }) && lunchBonusEnabled {
                    try breakSvc.createBonus(
                        policyId: policyId,
                        bonusType: "lunch",
                        bonusAmount: lunchBonusAmount,
                        description: "Lunch compliance bonus",
                        isEnabled: true
                    )
                }
                if !bonuses.contains(where: { $0.bonusType == "break" }) && breakBonusEnabled {
                    try breakSvc.createBonus(
                        policyId: policyId,
                        bonusType: "break",
                        bonusAmount: breakBonusAmount,
                        description: "Break compliance bonus",
                        isEnabled: true
                    )
                }
            }

            errorMessage = nil
            successMessage = "Break settings saved successfully."

            // Reload to confirm
            loadSettings()
        } catch {
            successMessage = nil
            errorMessage = userFriendlyError(error, context: "save settings")
        }
    }
}
