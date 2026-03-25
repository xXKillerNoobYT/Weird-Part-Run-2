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
    @State private var showHelp = false

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

    private let auditTypes = ["full_count", "cycle_count", "spot_check"]
    private let auditTypeLabels: [String: String] = [
        "full_count": "Full Count",
        "cycle_count": "Cycle Count",
        "spot_check": "Spot Check",
    ]

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading audit settings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                ContentUnavailableView("Unable to Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                settingsForm
            }
        }
        .navigationTitle("Audit Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            NavigationStack {
                List {
                    Section("Audit Types") {
                        Text("Full Count: count every item in a location. Cycle Count: count a rotating subset. Spot Check: quick verification of specific items.")
                    }
                    Section("Speed Mode") {
                        Text("Speed mode streamlines the audit process by timing each item. QR scanning ensures accuracy even at speed.")
                    }
                    Section("Multi-User Verification") {
                        Text("Multiple independent counts increase accuracy. The threshold sets how many people need to count before the result is accepted.")
                    }
                }
                .navigationTitle("Audit Help")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showHelp = false } } }
            }
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
                    Text("x")
                        .foregroundStyle(.secondary)
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

            // Save
            Section {
                Button { saveSettings() } label: {
                    Label("Save Settings", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
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

            enableAutoScheduling = (map["audit_auto_scheduling"] ?? "true") == "true"
            defaultAuditType = map["audit_default_type"] ?? "cycle_count"
            maxConcurrentAudits = Int(map["audit_max_concurrent"] ?? "") ?? 1

            allowSpeedMode = (map["audit_allow_speed_mode"] ?? "true") == "true"
            speedModeRequiresQR = (map["audit_speed_requires_qr"] ?? "true") == "true"
            speedModeTimeLimit = Int(map["audit_speed_time_limit"] ?? "") ?? 10

            verificationThreshold = Int(map["audit_verification_threshold"] ?? "") ?? 2
            misplacementPenalty = Double(map["audit_misplacement_penalty"] ?? "") ?? 1.5

            keepHistoryMonths = Int(map["audit_keep_history_months"] ?? "") ?? 12
            autoArchive = (map["audit_auto_archive"] ?? "true") == "true"
            includeInDailyReport = (map["audit_include_in_daily_report"] ?? "false") == "true"
        } catch {
            loadError = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
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
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
