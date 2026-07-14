import SwiftUI
import WiredPartCore

/// Audit scheduling, speed mode, multi-user verification, and history settings.
///
/// All values stored with `audit_` prefix via SettingsService.
struct IOSAuditSettingsPage: View {
    @EnvironmentObject private var appCore: AppCore

    // MARK: - State

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var activeSheet: ActiveSheet?

    // General
    @State private var enableAutoScheduling = true
    @State private var defaultAuditType: String = "cycle_count"
    @State private var maxConcurrentAudits: Int = 1

    // Speed Mode
    @State private var allowSpeedMode = true
    @State private var speedModeRequiresQR = true
    @State private var speedModeTimeLimit: Int = 10

    // Multi-User
    @State private var verificationThreshold: Int = 2
    @State private var misplacementPenalty: Double = 1.5

    // History
    @State private var keepHistoryMonths: Int = 12
    @State private var autoArchive = true
    @State private var includeInDailyReport = false

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private let auditTypes = ["full_count", "cycle_count", "spot_check"]
    private let auditTypeLabels: [String: String] = [
        "full_count": "Full Count",
        "cycle_count": "Cycle Count",
        "spot_check": "Spot Check",
    ]

    @State private var isDirty = false
    @State private var saveSuccessMessage: String?

    private var hasValidSettings: Bool {
        misplacementPenalty > 0
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading audit settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ErrorStateView(message: loadError)
            } else {
                settingsForm
            }
        }
        .navigationTitle("Audit Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this page.")
                .accessibilityIdentifier("settings-audit-settings-help-button")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Audit Help", sections: [
                ("Audit Types", "Full Count: count every item in a location. Cycle Count: count a rotating subset. Spot Check: quick verification of specific items."),
                ("Speed Mode", "Speed mode streamlines the audit process by timing each item. QR scanning ensures accuracy even at speed."),
                ("Multi-User Verification", "Multiple independent counts increase accuracy. The threshold sets how many people need to count before the result is accepted."),
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

            // General
            Section {
                Toggle("Auto-audit scheduling", isOn: $enableAutoScheduling)

                Picker("Default audit type", selection: $defaultAuditType) {
                    ForEach(auditTypes, id: \.self) { type in
                        Text(auditTypeLabels[type] ?? type).tag(type)
                    }
                }

                Stepper("Max concurrent: \(maxConcurrentAudits)", value: $maxConcurrentAudits, in: 1...5)
            } header: {
                Label("General", systemImage: "magnifyingglass.circle")
            }

            // Speed Mode
            Section {
                Toggle("Allow speed mode", isOn: $allowSpeedMode)
                if allowSpeedMode {
                    Toggle("Requires QR scan", isOn: $speedModeRequiresQR)
                    Stepper("Time limit: \(speedModeTimeLimit)s per item", value: $speedModeTimeLimit, in: 3...30)
                }
            } header: {
                Label("Speed Mode", systemImage: "bolt.circle")
            } footer: {
                Text("Speed mode times each item count. QR scanning ensures items are physically scanned.")
            }

            // Multi-User
            Section {
                Stepper("Verification threshold: \(verificationThreshold)", value: $verificationThreshold, in: 1...5)
                Text("Number of independent counts required before accepting a result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Misplacement penalty")
                    Spacer()
                    TextField("1.5", value: $misplacementPenalty, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .accessibilityLabel("Misplacement penalty multiplier")
                        .accessibilityIdentifier("settings-audit-misplacement-penalty-field")
                    Text("x")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text("Multiplier applied to confidence decay when items are found misplaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Multi-User Verification", systemImage: "person.2.circle")
            }

            // History
            Section {
                Stepper("Keep history: \(keepHistoryMonths) months", value: $keepHistoryMonths, in: 1...36)
                Toggle("Auto-archive completed", isOn: $autoArchive)
                Toggle("Include in daily report", isOn: $includeInDailyReport)
            } header: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            // Save success confirmation (issue #1214 — same pattern as
            // IOSToolPoliciesPage) — cleared on the next edit or error.
            if let saveSuccessMessage {
                Section {
                    Label(saveSuccessMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                .accessibilityIdentifier("auditSettingsSaveSuccessMessage")
            }

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty || !hasValidSettings)
                .accessibilityHint(!hasValidSettings ? "Misplacement penalty must be greater than zero." : (!isDirty ? "Make changes to enable saving." : ""))
            }
        }
        // Fix #149: dismiss keyboard when scrolling audit settings
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: enableAutoScheduling) { _, _ in markDirty() }
        .onChange(of: defaultAuditType) { _, _ in markDirty() }
        .onChange(of: maxConcurrentAudits) { _, _ in markDirty() }
        .onChange(of: allowSpeedMode) { _, _ in markDirty() }
        .onChange(of: speedModeRequiresQR) { _, _ in markDirty() }
        .onChange(of: speedModeTimeLimit) { _, _ in markDirty() }
        .onChange(of: verificationThreshold) { _, _ in markDirty() }
        .onChange(of: misplacementPenalty) { _, _ in markDirty() }
        .onChange(of: keepHistoryMonths) { _, _ in markDirty() }
        .onChange(of: autoArchive) { _, _ in markDirty() }
        .onChange(of: includeInDailyReport) { _, _ in markDirty() }
    }

    // MARK: - Actions

    private func loadSettings() {
        guard let service = appCore.settingsService else {
            loadError = "Settings service unavailable"
            isLoading = false
            return
        }

        do {
            let map = try service.getSettingsByCategory("audit")

            var parser = SettingsValueParser()
            enableAutoScheduling = parser.bool(map, key: "audit_auto_scheduling", default: true)
            defaultAuditType = map["audit_default_type"] ?? "cycle_count"
            maxConcurrentAudits = parser.int(map, key: "audit_max_concurrent", default: 1)

            allowSpeedMode = parser.bool(map, key: "audit_allow_speed_mode", default: true)
            speedModeRequiresQR = parser.bool(map, key: "audit_speed_requires_qr", default: true)
            speedModeTimeLimit = parser.int(map, key: "audit_speed_time_limit", default: 10)

            verificationThreshold = parser.int(map, key: "audit_verification_threshold", default: 2)
            misplacementPenalty = parser.double(map, key: "audit_misplacement_penalty", default: 1.5)

            keepHistoryMonths = parser.int(map, key: "audit_keep_history_months", default: 12)
            autoArchive = parser.bool(map, key: "audit_auto_archive", default: true)
            includeInDailyReport = parser.bool(map, key: "audit_include_in_daily_report", default: false)
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
                "audit_auto_scheduling": enableAutoScheduling ? "true" : "false",
                "audit_default_type": defaultAuditType,
                "audit_max_concurrent": "\(maxConcurrentAudits)",
                "audit_allow_speed_mode": allowSpeedMode ? "true" : "false",
                "audit_speed_requires_qr": speedModeRequiresQR ? "true" : "false",
                "audit_speed_time_limit": "\(speedModeTimeLimit)",
                "audit_verification_threshold": "\(verificationThreshold)",
                "audit_misplacement_penalty": String(format: "%.1f", misplacementPenalty),
                "audit_keep_history_months": "\(keepHistoryMonths)",
                "audit_auto_archive": autoArchive ? "true" : "false",
                "audit_include_in_daily_report": includeInDailyReport ? "true" : "false",
            ]
            try service.upsertSettingsMap(data, category: "audit")
            saveError = nil
            isDirty = false
            saveSuccessMessage = "Audit settings saved."
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
