import SwiftUI
import WiredPartCore

/// Global schedule configuration page.
///
/// Manages scheduling settings like work week, default hours,
/// overtime thresholds, and lunch break policies.
struct IOSScheduleConfigPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var workDayStart = "07:00"
    @State private var workDayEnd = "17:00"
    @State private var lunchDuration = 30
    @State private var overtimeThreshold = 40
    @State private var enableWeekendScheduling = false
    @State private var defaultBreakMinutes = 15
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var saveError: String?
    @State private var loadErrorMsg: String?
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    var body: some View {
        Form {
            Section {
                TextField("Day Start", text: $workDayStart)
                TextField("Day End", text: $workDayEnd)
            } header: {
                Text("Work Hours")
            } footer: {
                Text("Default start and end times for the work day (24hr format).")
            }

            Section {
                Stepper("Lunch: \(lunchDuration) min", value: $lunchDuration, in: 0...120, step: 15)
                Stepper("Breaks: \(defaultBreakMinutes) min", value: $defaultBreakMinutes, in: 0...60, step: 5)
            } header: {
                Text("Breaks")
            }

            Section {
                Stepper("OT After: \(overtimeThreshold) hrs/week", value: $overtimeThreshold, in: 20...60)
                Toggle("Weekend Scheduling", isOn: $enableWeekendScheduling)
            } header: {
                Text("Overtime & Weekends")
            } footer: {
                Text("Hours worked beyond the threshold are counted as overtime.")
            }

            Section {
                Button {
                    saveConfig()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save Configuration").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            }

            if let error = saveError ?? loadErrorMsg {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Schedule Config")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Schedule Config Help", sections: [
                ("What This Page Does", "Schedule Config sets the global defaults for your scheduling system. These settings control work hours, break policies, overtime thresholds, and weekend scheduling rules that apply company-wide."),
                ("How to Use It", "Adjust the work day start and end times using 24-hour format (e.g. 07:00 for 7 AM). Set lunch and break durations with the steppers. Configure the overtime threshold for weekly hours. Toggle weekend scheduling on or off."),
                ("Saving Changes", "Tap 'Save Configuration' at the bottom to apply your changes. A confirmation alert appears when saved successfully. If there is an error, it will be displayed in red at the bottom of the form."),
                ("Tips", "These are global defaults. Individual schedule entries can still override these times. The overtime threshold is used for reporting and alerts, not for blocking assignments.")
            ])
        }
        .task { loadConfig() }
        .alert("Configuration Saved", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) { }
        }
    }

    private func saveConfig() {
        guard let service = appCore.settingsService else {
            saveError = "Service not available"
            return
        }
        isSaving = true
        saveError = nil
        do {
            try service.upsertSettingsMap([
                "work_day_start": workDayStart,
                "work_day_end": workDayEnd,
                "lunch_duration": "\(lunchDuration)",
                "overtime_threshold": "\(overtimeThreshold)",
                "weekend_scheduling": enableWeekendScheduling ? "1" : "0",
                "default_break_minutes": "\(defaultBreakMinutes)",
            ], category: "scheduling")
            showSaveConfirmation = true
        } catch {
            saveError = userFriendlyError(error, context: "save")
        }
        isSaving = false
    }

    private func loadConfig() {
        guard let service = appCore.settingsService else {
            loadErrorMsg = "Service not available"
            return
        }
        do {
            let settings = try service.getSettingsByCategory("scheduling")
            if let v = settings["work_day_start"] { workDayStart = v }
            if let v = settings["work_day_end"] { workDayEnd = v }
            if let v = settings["lunch_duration"], let n = Int(v) { lunchDuration = n }
            if let v = settings["overtime_threshold"], let n = Int(v) { overtimeThreshold = n }
            if let v = settings["weekend_scheduling"] { enableWeekendScheduling = v == "1" }
            if let v = settings["default_break_minutes"], let n = Int(v) { defaultBreakMinutes = n }
        } catch {
            loadErrorMsg = userFriendlyError(error, context: "load settings")
        }
    }
}
