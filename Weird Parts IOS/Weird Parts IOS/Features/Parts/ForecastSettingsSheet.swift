import SwiftUI
import WiredPartCore

/// Settings sheet for forecast calculation parameters per location type.
///
/// Configures ADU lookback (shop) or APW window (truck/trailer), common and
/// critical multipliers for MIN/TARGET/MAX, minimum data requirements, and
/// the free-space suppress threshold. Backend: `forecast_settings` table.
struct ForecastSettingsSheet: View {
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var selectedLocationType = "warehouse"
    @State private var allSettings: [ForecastSettings] = []
    @State private var isSaving = false
    @State private var saveError: String?

    // Editable fields — strings for TextField binding, parsed on save
    @State private var aduLookbackDays = "365"
    @State private var windowWeeks = "3"
    @State private var minDataDays = "90"
    @State private var commonMin = "3.5"
    @State private var commonTarget = "14.0"
    @State private var commonMax = "21.0"
    @State private var criticalMin = "7.0"
    @State private var criticalTarget = "14.0"
    @State private var criticalMax = "30.0"
    @State private var freeSpaceThreshold = 3

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                locationTypeSection
                calculationMethodSection
                lookbackSection
                multiplierSection(
                    header: "Common Parts",
                    footer: "Easy to get, used often. Shorter safety buffers.",
                    minVal: $commonMin, targetVal: $commonTarget, maxVal: $commonMax
                )
                multiplierSection(
                    header: "Critical Parts",
                    footer: "Rarely used but essential. Longer buffers — never run out.",
                    minVal: $criticalMin, targetVal: $criticalTarget, maxVal: $criticalMax
                )
                freeSpaceSection

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Forecast Settings")
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
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - Sections

    private var locationTypeSection: some View {
        Section {
            Picker("Location Type", selection: $selectedLocationType) {
                Text("Shop").tag("warehouse")
                Text("Truck").tag("truck")
                Text("Trailer").tag("trailer")
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedLocationType) { _ in populateFields() }
        } header: {
            Text("Location Type")
        } footer: {
            Text("Each location type has its own forecast calculation defaults.")
        }
    }

    private var calculationMethodSection: some View {
        Section {
            HStack {
                Image(systemName: selectedLocationType == "warehouse" ? "chart.bar" : "calendar")
                    .foregroundStyle(.secondary)
                Text(selectedLocationType == "warehouse"
                    ? "ADU — Average Daily Usage (parts/day)"
                    : "APW — Average Per Window (parts/weeks)")
                    .font(.subheadline)
            }
            .frame(minHeight: 44)
        } header: {
            Text("Calculation Method")
        }
    }

    private var lookbackSection: some View {
        Section {
            if selectedLocationType == "warehouse" {
                HStack {
                    Text("ADU Lookback")
                    Spacer()
                    TextField("365", text: $aduLookbackDays)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 80)
                        .keyboardType(.numberPad)
                    Text("days")
                }
                .frame(minHeight: 44)
            } else {
                HStack {
                    Text("Window")
                    Spacer()
                    TextField("3", text: $windowWeeks)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 60)
                        .keyboardType(.numberPad)
                    Text("weeks")
                }
                .frame(minHeight: 44)
            }

            HStack {
                Text("Min Data Required")
                Spacer()
                TextField("90", text: $minDataDays)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .keyboardType(.numberPad)
                Text("days")
            }
            .frame(minHeight: 44)
        } header: {
            Text("Data Requirements")
        } footer: {
            Text("Forecasts won't generate until a part has this many days of history at a location.")
        }
    }

    private func multiplierSection(
        header: String,
        footer: String,
        minVal: Binding<String>,
        targetVal: Binding<String>,
        maxVal: Binding<String>
    ) -> some View {
        Section {
            multiplierRow("MIN", value: minVal)
            multiplierRow("TARGET", value: targetVal)
            multiplierRow("MAX", value: maxVal)
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    private func multiplierRow(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            TextField("0", text: value)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .keyboardType(.decimalPad)
            Text("x \(unitLabel)")
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }

    private var freeSpaceSection: some View {
        Section {
            Stepper("Suppress below: \(freeSpaceThreshold)", value: $freeSpaceThreshold, in: 1...10)
                .frame(minHeight: 44)
        } header: {
            Text("Free Space Threshold")
        } footer: {
            Text("Locations with a free-space rating below this value won't receive \"add stock\" recommendations. Scale: 1 (nearly full) to 10 (lots of room).")
        }
    }

    // MARK: - Helpers

    private var unitLabel: String {
        selectedLocationType == "warehouse" ? "days" : "weeks"
    }

    /// Finds the default settings for the currently selected location type.
    private var currentSettings: ForecastSettings? {
        allSettings.first { $0.locationType == selectedLocationType && $0.locationId == nil }
    }

    // MARK: - Data

    private func loadSettings() async {
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            return
        }
        do {
            allSettings = try service.listAllForecastSettings()
            populateFields()
        } catch {
            saveError = userFriendlyError(error, context: "load forecast settings")
        }
    }

    private func populateFields() {
        guard let s = currentSettings else {
            // No saved settings for this type — use seeded defaults
            if selectedLocationType == "warehouse" {
                aduLookbackDays = "365"; windowWeeks = "3"; minDataDays = "90"
                commonMin = "3.5"; commonTarget = "14.0"; commonMax = "21.0"
                criticalMin = "7.0"; criticalTarget = "14.0"; criticalMax = "30.0"
            } else {
                aduLookbackDays = "365"; windowWeeks = "3"; minDataDays = "90"
                commonMin = "1.0"; commonTarget = "2.0"; commonMax = "3.0"
                criticalMin = "2.0"; criticalTarget = "3.0"; criticalMax = "4.0"
            }
            freeSpaceThreshold = 3
            return
        }
        aduLookbackDays = "\(s.aduLookbackDays)"
        windowWeeks = "\(s.windowWeeks)"
        minDataDays = "\(s.minDataDays)"
        commonMin = formatMultiplier(s.commonMinMultiplier)
        commonTarget = formatMultiplier(s.commonTargetMultiplier)
        commonMax = formatMultiplier(s.commonMaxMultiplier)
        criticalMin = formatMultiplier(s.criticalMinMultiplier)
        criticalTarget = formatMultiplier(s.criticalTargetMultiplier)
        criticalMax = formatMultiplier(s.criticalMaxMultiplier)
        freeSpaceThreshold = s.freeSpaceSuppressThreshold
    }

    private func formatMultiplier(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        saveError = nil

        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            isSaving = false
            return
        }

        // Parse
        guard let cMin = Double(commonMin), let cTar = Double(commonTarget), let cMax = Double(commonMax),
              let crMin = Double(criticalMin), let crTar = Double(criticalTarget), let crMax = Double(criticalMax),
              let lookback = Int(aduLookbackDays), let window = Int(windowWeeks), let minDays = Int(minDataDays) else {
            saveError = "All fields must be valid numbers."
            isSaving = false
            return
        }

        // Validate multipliers > 0
        guard cMin > 0, cTar > 0, cMax > 0, crMin > 0, crTar > 0, crMax > 0 else {
            saveError = "All multiplier values must be greater than zero."
            isSaving = false
            return
        }

        // Validate MIN < TARGET < MAX
        guard cMin < cTar, cTar < cMax else {
            saveError = "Common multipliers must be: MIN < TARGET < MAX."
            isSaving = false
            return
        }
        guard crMin < crTar, crTar < crMax else {
            saveError = "Critical multipliers must be: MIN < TARGET < MAX."
            isSaving = false
            return
        }

        // Validate lookback/window
        if selectedLocationType != "warehouse" {
            guard (1...6).contains(window) else {
                saveError = "Window must be between 1 and 6 weeks."
                isSaving = false
                return
            }
        }
        guard lookback >= minDays else {
            saveError = "ADU lookback must be at least as large as min data days."
            isSaving = false
            return
        }
        guard minDays > 0, lookback > 0 else {
            saveError = "Lookback and min data days must be greater than zero."
            isSaving = false
            return
        }

        // Build settings struct, preserving id if editing an existing record
        let settings = ForecastSettings(
            id: currentSettings?.id,
            locationType: selectedLocationType,
            locationId: nil,
            usageUnit: selectedLocationType == "warehouse" ? "daily" : "weekly",
            aduLookbackDays: lookback,
            windowWeeks: window,
            minDataDays: minDays,
            commonMinMultiplier: cMin,
            commonTargetMultiplier: cTar,
            commonMaxMultiplier: cMax,
            criticalMinMultiplier: crMin,
            criticalTargetMultiplier: crTar,
            criticalMaxMultiplier: crMax,
            freeSpaceSuppressThreshold: freeSpaceThreshold,
            updatedAt: nil
        )

        do {
            try service.saveForecastSettings(settings)
            dismiss()
            await onSave()
        } catch {
            saveError = userFriendlyError(error, context: "save forecast settings")
        }
        isSaving = false
    }
}
