import SwiftUI
import WiredPartCore

/// Forecast calculation method, multiplier, free-space, and recalculation settings.
///
/// Per-location-type defaults (Shop, Truck, Trailer) stored with `forecast_` prefix.
struct IOSForecastSettingsPage: View {
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

    @State private var selectedLocationType: String = "shop"

    // Per-location-type settings
    @State private var method: [String: String] = ["shop": "adu", "truck": "apw", "trailer": "apw"]
    @State private var lookbackDays: [String: Int] = ["shop": 90, "truck": 42, "trailer": 42]
    @State private var minDataDays: [String: Int] = ["shop": 14, "truck": 7, "trailer": 7]
    @State private var apwWindow: [String: Int] = ["shop": 2, "truck": 2, "trailer": 2]

    // Multipliers — common
    @State private var commonMinMult: Double = 1.0
    @State private var commonTargetMult: Double = 1.5
    @State private var commonMaxMult: Double = 2.0

    // Multipliers — critical
    @State private var criticalMinMult: Double = 1.5
    @State private var criticalTargetMult: Double = 2.0
    @State private var criticalMaxMult: Double = 3.0

    // Free space
    @State private var freeSpaceThreshold: Double = 20

    // Auto-recalculation
    @State private var autoRecalcDaily = true
    @State private var recalcHour: Int = 2
    @State private var categorySuggestionMonths: Int = 6

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private let locationTypes = ["shop", "truck", "trailer"]
    private let locationLabels: [String: String] = ["shop": "Shop", "truck": "Truck", "trailer": "Trailer"]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading forecast settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                settingsForm
            }
        }
        .navigationTitle("Forecast Config")
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
            PageHelpSheet(title: "Forecast Help", sections: [
                ("Calculation Methods", "ADU (Average Daily Usage) divides total usage over the lookback period. APW (Average Per Window) uses rolling windows for more responsive estimates on trucks/trailers."),
                ("Multipliers", "MIN = usage x multiplier. TARGET = the optimal stock level. MAX = the upper bound before overstock warnings."),
                ("Free Space", "Locations with low free space won't receive 'add new part' recommendations to avoid overcrowding."),
            ])
        }
        .task { loadSettings() }
        .interactiveDismissDisabled(isDirty)
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
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

            // Per-location defaults
            Section {
                Picker("Location Type", selection: $selectedLocationType) {
                    ForEach(locationTypes, id: \.self) { type in
                        Text(locationLabels[type] ?? type.capitalized).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                let currentMethod = method[selectedLocationType] ?? "adu"

                Picker("Calculation method", selection: Binding(
                    get: { method[selectedLocationType] ?? "adu" },
                    set: { method[selectedLocationType] = $0 }
                )) {
                    Text("ADU (Avg Daily Usage)").tag("adu")
                    Text("APW (Avg Per Window)").tag("apw")
                }

                if currentMethod == "apw" {
                    Stepper("APW window: \(apwWindow[selectedLocationType] ?? 2) weeks",
                            value: Binding(
                                get: { apwWindow[selectedLocationType] ?? 2 },
                                set: { apwWindow[selectedLocationType] = $0 }
                            ), in: 1...6)
                }

                Stepper("Lookback: \(lookbackDays[selectedLocationType] ?? 90) days",
                        value: Binding(
                            get: { lookbackDays[selectedLocationType] ?? 90 },
                            set: { lookbackDays[selectedLocationType] = $0 }
                        ), in: 7...365)

                Stepper("Min data days: \(minDataDays[selectedLocationType] ?? 14)",
                        value: Binding(
                            get: { minDataDays[selectedLocationType] ?? 14 },
                            set: { minDataDays[selectedLocationType] = $0 }
                        ), in: 1...90)
            } header: {
                Label("Per-Location Defaults", systemImage: "chart.line.uptrend.xyaxis")
            }

            // Common multipliers
            Section {
                multiplierRow("MIN", value: $commonMinMult)
                multiplierRow("TARGET", value: $commonTargetMult)
                multiplierRow("MAX", value: $commonMaxMult)
            } header: {
                Label("Common Part Multipliers", systemImage: "circle")
            } footer: {
                Text("MIN = usage x multiplier. TARGET = optimal stock. MAX = overstock threshold.")
            }

            // Critical multipliers
            Section {
                multiplierRow("MIN", value: $criticalMinMult)
                multiplierRow("TARGET", value: $criticalTargetMult)
                multiplierRow("MAX", value: $criticalMaxMult)
            } header: {
                Label("Critical Part Multipliers", systemImage: "exclamationmark.circle")
            }

            // Free space
            Section {
                VStack(alignment: .leading) {
                    Text("Suppress below \(Int(freeSpaceThreshold))% free space")
                    Slider(value: $freeSpaceThreshold, in: 0...100, step: 5)
                }
                Text("Locations with low free space won't receive 'add new part' recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Free Space", systemImage: "square.dashed")
            }

            // Auto-recalculation
            Section {
                Toggle("Auto-recalculate daily", isOn: $autoRecalcDaily)
                if autoRecalcDaily {
                    Stepper("Recalc time: \(recalcHour):00", value: $recalcHour, in: 0...23)
                }
                Stepper("Category suggestion: every \(categorySuggestionMonths) months",
                        value: $categorySuggestionMonths, in: 1...24)
            } header: {
                Label("Auto-Recalculation", systemImage: "arrow.clockwise")
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
        // Fix #149: dismiss keyboard when scrolling forecast settings
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: method) { _, _ in markDirty() }
        .onChange(of: lookbackDays) { _, _ in markDirty() }
        .onChange(of: minDataDays) { _, _ in markDirty() }
        .onChange(of: apwWindow) { _, _ in markDirty() }
        .onChange(of: commonMinMult) { _, _ in markDirty() }
        .onChange(of: commonTargetMult) { _, _ in markDirty() }
        .onChange(of: commonMaxMult) { _, _ in markDirty() }
        .onChange(of: criticalMinMult) { _, _ in markDirty() }
        .onChange(of: criticalTargetMult) { _, _ in markDirty() }
        .onChange(of: criticalMaxMult) { _, _ in markDirty() }
        .onChange(of: freeSpaceThreshold) { _, _ in markDirty() }
        .onChange(of: autoRecalcDaily) { _, _ in markDirty() }
        .onChange(of: recalcHour) { _, _ in markDirty() }
        .onChange(of: categorySuggestionMonths) { _, _ in markDirty() }
    }

    private func multiplierRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0.0", value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
        }
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
            let map = try service.getSettingsByCategory("forecast")

            for loc in locationTypes {
                method[loc] = map["forecast_\(loc)_method"] ?? (loc == "shop" ? "adu" : "apw")
                lookbackDays[loc] = Int(map["forecast_\(loc)_lookback_days"] ?? "") ?? (loc == "shop" ? 90 : 42)
                minDataDays[loc] = Int(map["forecast_\(loc)_min_data_days"] ?? "") ?? (loc == "shop" ? 14 : 7)
                apwWindow[loc] = Int(map["forecast_\(loc)_apw_window"] ?? "") ?? 2
            }

            commonMinMult = Double(map["forecast_common_min_mult"] ?? "") ?? 1.0
            commonTargetMult = Double(map["forecast_common_target_mult"] ?? "") ?? 1.5
            commonMaxMult = Double(map["forecast_common_max_mult"] ?? "") ?? 2.0
            criticalMinMult = Double(map["forecast_critical_min_mult"] ?? "") ?? 1.5
            criticalTargetMult = Double(map["forecast_critical_target_mult"] ?? "") ?? 2.0
            criticalMaxMult = Double(map["forecast_critical_max_mult"] ?? "") ?? 3.0

            freeSpaceThreshold = Double(map["forecast_free_space_threshold"] ?? "") ?? 20
            autoRecalcDaily = (map["forecast_auto_recalc_daily"] ?? "true") == "true"
            recalcHour = Int(map["forecast_recalc_hour"] ?? "") ?? 2
            categorySuggestionMonths = Int(map["forecast_category_suggestion_months"] ?? "") ?? 6
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
            var data: [String: String] = [:]

            for loc in locationTypes {
                data["forecast_\(loc)_method"] = method[loc] ?? "adu"
                data["forecast_\(loc)_lookback_days"] = "\(lookbackDays[loc] ?? 90)"
                data["forecast_\(loc)_min_data_days"] = "\(minDataDays[loc] ?? 14)"
                data["forecast_\(loc)_apw_window"] = "\(apwWindow[loc] ?? 2)"
            }

            data["forecast_common_min_mult"] = String(format: "%.1f", commonMinMult)
            data["forecast_common_target_mult"] = String(format: "%.1f", commonTargetMult)
            data["forecast_common_max_mult"] = String(format: "%.1f", commonMaxMult)
            data["forecast_critical_min_mult"] = String(format: "%.1f", criticalMinMult)
            data["forecast_critical_target_mult"] = String(format: "%.1f", criticalTargetMult)
            data["forecast_critical_max_mult"] = String(format: "%.1f", criticalMaxMult)

            data["forecast_free_space_threshold"] = "\(Int(freeSpaceThreshold))"
            data["forecast_auto_recalc_daily"] = autoRecalcDaily ? "true" : "false"
            data["forecast_recalc_hour"] = "\(recalcHour)"
            data["forecast_category_suggestion_months"] = "\(categorySuggestionMonths)"

            try service.upsertSettingsMap(data, category: "forecast")
            saveError = nil
            isDirty = false
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
    }
}
