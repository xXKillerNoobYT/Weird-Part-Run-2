import SwiftUI
import WiredPartCore

/// Dispatch AI, flex pool, pipeline targets, and scheduling preferences.
///
/// All values are stored as key-value settings using the `dispatch_` prefix.
struct IOSDispatchPreferencesPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var activeSheet: ActiveSheet?

    // AI Dispatch
    @State private var enableAISuggestions = true
    @State private var enableAILearning = true
    @State private var showConfidenceScores = false

    // Flex Pool
    @State private var enableFlexSelfAssign = false
    @State private var requireManagerApproval = true

    // Pipeline Targets
    @State private var startAnytimeTarget: Int = 3
    @State private var scheduleNeededTarget: Int = 2
    @State private var favoriteGCTarget: Int = 1

    // Scheduling
    @State private var defaultView: String = "week"
    @State private var crewHistoryMonths: Int = 3
    @State private var crewContinuityWeight: String = "medium"

    @State private var isDirty = false
    @State private var saveSuccessMessage: String?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private let viewOptions = ["day", "week", "month"]
    private let viewLabels: [String: String] = ["day": "Day", "week": "Week", "month": "Month"]
    private let weightOptions = ["low", "medium", "high"]
    private let weightLabels: [String: String] = ["low": "Low", "medium": "Medium", "high": "High"]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading dispatch preferences...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ErrorStateView(message: loadError)
            } else {
                settingsForm
            }
        }
        .navigationTitle("Dispatch Preferences")
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
            PageHelpSheet(title: "Dispatch Help", sections: [
                ("About Dispatch Preferences", "Configure how the dispatch system suggests assignments and manages the job pipeline."),
                ("AI Dispatch", "AI suggestions use worker skills, team history, travel distance, and job requirements to recommend optimal assignments."),
                ("Flex Pool", "The flex pool allows unassigned workers to self-assign to available jobs. Manager approval can gate the process."),
                ("Pipeline Targets", "Targets are the minimum number of jobs you want in each pipeline stage. The system warns when you're below target."),
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

            // AI Dispatch
            Section {
                Toggle("Enable AI suggestions", isOn: $enableAISuggestions)
                Toggle("AI learns from picks", isOn: $enableAILearning)
                Toggle("Show confidence scores", isOn: $showConfidenceScores)
            } header: {
                Label("AI Dispatch", systemImage: "cpu")
            } footer: {
                Text("When learning is on, the system improves suggestions based on which assignments the dispatcher actually makes.")
            }

            // Flex Pool
            Section {
                Toggle("Enable flex pool self-assign", isOn: $enableFlexSelfAssign)
                if enableFlexSelfAssign {
                    Toggle("Require manager approval", isOn: $requireManagerApproval)
                }
            } header: {
                Label("Flex Pool", systemImage: "person.2.badge.gearshape")
            } footer: {
                Text("Flex pool lets unassigned workers claim open jobs on their own.")
            }

            // Pipeline Targets
            Section {
                Stepper("Start Anytime: \(startAnytimeTarget)", value: $startAnytimeTarget, in: 0...20)
                Stepper("Schedule Needed: \(scheduleNeededTarget)", value: $scheduleNeededTarget, in: 0...20)
                Stepper("Favorite GC: \(favoriteGCTarget)", value: $favoriteGCTarget, in: 0...20)
                Text("Target = minimum number of jobs in each pipeline stage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Pipeline Targets", systemImage: "chart.bar.fill")
            }

            // Scheduling
            Section {
                Picker("Default view", selection: $defaultView) {
                    ForEach(viewOptions, id: \.self) { opt in
                        Text(viewLabels[opt] ?? opt.capitalized).tag(opt)
                    }
                }

                Stepper("Crew history: \(crewHistoryMonths) months", value: $crewHistoryMonths, in: 1...12)

                Picker("Crew continuity weight", selection: $crewContinuityWeight) {
                    ForEach(weightOptions, id: \.self) { opt in
                        Text(weightLabels[opt] ?? opt.capitalized).tag(opt)
                    }
                }
            } header: {
                Label("Scheduling", systemImage: "calendar.badge.clock")
            } footer: {
                Text("Crew continuity weight controls how strongly the system prefers keeping the same crew on a job.")
            }

            // Save success confirmation (issue #1214 — same pattern as
            // IOSToolPoliciesPage) — cleared on the next edit or error.
            if let saveSuccessMessage {
                Section {
                    Label(saveSuccessMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                .accessibilityIdentifier("dispatchPreferencesSaveSuccessMessage")
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
        .onChange(of: enableAISuggestions) { _, _ in markDirty() }
        .onChange(of: enableAILearning) { _, _ in markDirty() }
        .onChange(of: showConfidenceScores) { _, _ in markDirty() }
        .onChange(of: enableFlexSelfAssign) { _, _ in markDirty() }
        .onChange(of: requireManagerApproval) { _, _ in markDirty() }
        .onChange(of: startAnytimeTarget) { _, _ in markDirty() }
        .onChange(of: scheduleNeededTarget) { _, _ in markDirty() }
        .onChange(of: favoriteGCTarget) { _, _ in markDirty() }
        .onChange(of: defaultView) { _, _ in markDirty() }
        .onChange(of: crewHistoryMonths) { _, _ in markDirty() }
        .onChange(of: crewContinuityWeight) { _, _ in markDirty() }
    }

    // MARK: - Actions

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        do {
            let map = try service.getSettingsByCategory("dispatch")

            var parser = SettingsValueParser()
            enableAISuggestions = parser.bool(map, key: "dispatch_ai_suggestions_enabled", default: true)
            enableAILearning = parser.bool(map, key: "dispatch_ai_learning_enabled", default: true)
            showConfidenceScores = parser.bool(map, key: "dispatch_show_confidence_scores", default: false)

            enableFlexSelfAssign = parser.bool(map, key: "dispatch_flex_self_assign_enabled", default: false)
            requireManagerApproval = parser.bool(map, key: "dispatch_flex_require_approval", default: true)

            startAnytimeTarget = parser.int(map, key: "dispatch_pipeline_start_anytime_target", default: 3)
            scheduleNeededTarget = parser.int(map, key: "dispatch_pipeline_schedule_needed_target", default: 2)
            favoriteGCTarget = parser.int(map, key: "dispatch_pipeline_favorite_gc_target", default: 1)

            defaultView = map["dispatch_default_view"] ?? "week"
            crewHistoryMonths = parser.int(map, key: "dispatch_crew_history_months", default: 3)
            crewContinuityWeight = map["dispatch_crew_continuity_weight"] ?? "medium"
            try parser.throwIfInvalid()
        } catch {
            loadError = settingsHydrationMessage(error)
        }
        isLoading = false
        isDirty = false
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            saveError = "Settings service unavailable"
            return
        }

        do {
            let data: [String: String] = [
                "dispatch_ai_suggestions_enabled": enableAISuggestions ? "true" : "false",
                "dispatch_ai_learning_enabled": enableAILearning ? "true" : "false",
                "dispatch_show_confidence_scores": showConfidenceScores ? "true" : "false",
                "dispatch_flex_self_assign_enabled": enableFlexSelfAssign ? "true" : "false",
                "dispatch_flex_require_approval": requireManagerApproval ? "true" : "false",
                "dispatch_pipeline_start_anytime_target": "\(startAnytimeTarget)",
                "dispatch_pipeline_schedule_needed_target": "\(scheduleNeededTarget)",
                "dispatch_pipeline_favorite_gc_target": "\(favoriteGCTarget)",
                "dispatch_default_view": defaultView,
                "dispatch_crew_history_months": "\(crewHistoryMonths)",
                "dispatch_crew_continuity_weight": crewContinuityWeight,
            ]
            try service.upsertSettingsMap(data, category: "dispatch")
            saveError = nil
            isDirty = false
            saveSuccessMessage = "Dispatch preferences saved."
        } catch {
            saveError = userFriendlyError(error, context: "save data")
            saveSuccessMessage = nil
        }
    }

    /// New edits invalidate the last save confirmation along with marking
    /// the form dirty (issue #1214).
    private func markDirty() {
        isDirty = true
        saveSuccessMessage = nil
    }
}
