import SwiftUI
import WiredPartCore

/// Warehouse organization confidence, audit triggers, consolidation, and rating settings.
///
/// All values stored with `org_` prefix via SettingsService.
struct IOSOrganizationThresholdsPage: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var activeSheet: ActiveSheet?

    // Confidence Decay
    @State private var baseDecayRate: Double = 0.1
    @State private var movementDecayFactor: Double = 0.5

    // Audit Triggers
    @State private var auditThreshold: Double = 80
    @State private var maxRecsPerDay: Int = 1
    @State private var recCooldownDays: Int = 60

    // Consolidation
    @State private var votingTimeoutDays: Int = 7
    @State private var minVotesRequired: Int = 2
    @State private var autoApproveUnanimous = true

    // Organization Rating
    @State private var targetScore: Double = 85
    @State private var showOnDashboard = true
    @State private var includeInDailyReport = false
    @State private var hasUnsavedChanges = false
    @State private var showDiscardConfirmation = false
    @State private var baselineFormSignature = ""

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private var hasValidSettings: Bool {
        baseDecayRate > 0 && movementDecayFactor > 0
    }

    private var formSignature: String {
        [
            String(baseDecayRate),
            String(movementDecayFactor),
            String(auditThreshold),
            String(maxRecsPerDay),
            String(recCooldownDays),
            String(votingTimeoutDays),
            String(minVotesRequired),
            String(autoApproveUnanimous),
            String(targetScore),
            String(showOnDashboard),
            String(includeInDailyReport),
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading thresholds...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ErrorStateView(message: loadError)
            } else {
                settingsForm
            }
        }
        .navigationTitle("Organization Thresholds")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasUnsavedChanges)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if hasUnsavedChanges {
                    Button("Back") { showDiscardConfirmation = true }
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
            PageHelpSheet(title: "Thresholds Help", sections: [
                ("Confidence Decay", "Each location's confidence score decreases daily. Moving parts accelerates decay since items may have been misplaced during the move."),
                ("Audit Triggers", "When a location's confidence drops below the threshold, the system recommends an audit. Cooldown prevents excessive recommendations."),
                ("Consolidation", "Consolidation votes let the team decide when to merge low-stock locations. Unanimous votes can auto-approve."),
                ("Organization Rating", "The overall warehouse organization score reflects how well-organized and accurately tracked your inventory is."),
            ])
        }
        .task { loadSettings() }
        .onChange(of: formSignature) { _, _ in
            guard !isLoading else { return }
            hasUnsavedChanges = formSignature != baselineFormSignature
        }
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
            Button("Keep editing", role: .cancel) {}
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

            // Confidence Decay
            Section {
                HStack {
                    Text("Base decay rate")
                    Spacer()
                    TextField("0.1", value: $baseDecayRate, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("% / day")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Movement decay factor")
                    Spacer()
                    TextField("0.5", value: $movementDecayFactor, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }

                Text("Confidence decreases daily. Moving parts increases decay (things may have been misplaced).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Confidence Decay", systemImage: "chart.line.downtrend.xyaxis")
            }

            // Audit Triggers
            Section {
                VStack(alignment: .leading) {
                    Text("Trigger threshold: \(Int(auditThreshold))%")
                    Slider(value: $auditThreshold, in: 0...100, step: 5)
                }

                Stepper("Max recs/day: \(maxRecsPerDay)", value: $maxRecsPerDay, in: 1...10)

                Stepper("Cooldown: \(recCooldownDays) days", value: $recCooldownDays, in: 7...180)

                Text("When a location's confidence drops below threshold, an audit is recommended.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Audit Triggers", systemImage: "exclamationmark.triangle")
            }

            // Consolidation
            Section {
                Stepper("Voting timeout: \(votingTimeoutDays) days", value: $votingTimeoutDays, in: 1...30)
                Stepper("Min votes: \(minVotesRequired)", value: $minVotesRequired, in: 1...5)
                Toggle("Auto-approve unanimous", isOn: $autoApproveUnanimous)
            } header: {
                Label("Consolidation", systemImage: "arrow.triangle.merge")
            }

            // Organization Rating
            Section {
                VStack(alignment: .leading) {
                    Text("Target score: \(Int(targetScore))%")
                    Slider(value: $targetScore, in: 0...100, step: 5)
                }
                Toggle("Show on dashboard", isOn: $showOnDashboard)
                Toggle("Include in daily report", isOn: $includeInDailyReport)
            } header: {
                Label("Organization Rating", systemImage: "star.circle")
            }

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasValidSettings)
                .accessibilityHint(hasValidSettings ? "" : "Base decay rate and movement decay factor must be greater than zero.")
            }
        }
        // Fix #149: dismiss keyboard when scrolling threshold settings
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Actions

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        do {
            let map = try service.getSettingsByCategory("org")

            var parser = SettingsValueParser()
            baseDecayRate = parser.double(map, key: "org_base_decay_rate", default: 0.1)
            movementDecayFactor = parser.double(map, key: "org_movement_decay_factor", default: 0.5)

            auditThreshold = parser.double(map, key: "org_audit_threshold", default: 80)
            maxRecsPerDay = parser.int(map, key: "org_max_recs_per_day", default: 1)
            recCooldownDays = parser.int(map, key: "org_rec_cooldown_days", default: 60)

            votingTimeoutDays = parser.int(map, key: "org_voting_timeout_days", default: 7)
            minVotesRequired = parser.int(map, key: "org_min_votes_required", default: 2)
            autoApproveUnanimous = parser.bool(map, key: "org_auto_approve_unanimous", default: true)

            targetScore = parser.double(map, key: "org_target_score", default: 85)
            showOnDashboard = parser.bool(map, key: "org_show_on_dashboard", default: true)
            includeInDailyReport = parser.bool(map, key: "org_include_in_daily_report", default: false)
            try parser.throwIfInvalid()
        } catch {
            loadError = settingsHydrationMessage(error)
        }
        isLoading = false
        resetDirtyTracking()
    }

    private func saveSettings() {
        guard let service = appCore.settingsService else {
            saveError = "Settings service unavailable"
            return
        }

        do {
            let data: [String: String] = [
                "org_base_decay_rate": String(format: "%.2f", baseDecayRate),
                "org_movement_decay_factor": String(format: "%.2f", movementDecayFactor),
                "org_audit_threshold": "\(Int(auditThreshold))",
                "org_max_recs_per_day": "\(maxRecsPerDay)",
                "org_rec_cooldown_days": "\(recCooldownDays)",
                "org_voting_timeout_days": "\(votingTimeoutDays)",
                "org_min_votes_required": "\(minVotesRequired)",
                "org_auto_approve_unanimous": autoApproveUnanimous ? "true" : "false",
                "org_target_score": "\(Int(targetScore))",
                "org_show_on_dashboard": showOnDashboard ? "true" : "false",
                "org_include_in_daily_report": includeInDailyReport ? "true" : "false",
            ]
            try service.upsertSettingsMap(data, category: "org")
            saveError = nil
            resetDirtyTracking()
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
    }

    private func resetDirtyTracking() {
        baselineFormSignature = formSignature
        hasUnsavedChanges = false
    }
}
