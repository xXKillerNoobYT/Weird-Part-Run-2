import SwiftUI
import WiredPartCore

/// AI configuration page — model selection and Foundation Models status.
struct IOSAIConfigPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var activeSheet: ActiveSheet?
    @State private var aiEnabled = true
    @State private var selectedModel = "foundation"
    @State private var isCheckingAvailability = false
    @State private var availabilityStatus: AIAvailability?
    @State private var aiLanguage = "en"
    @State private var onboardAIMVPEnabled = false
    @State private var saveError: String?
    // Fix #192: gate the form behind a loading state so defaults don't flash
    // before loadSettings() populates the actual values.
    @State private var isLoading = true

    private let aiService = FoundationModelsService()

    private let modelOptions = [
        ("foundation", "Apple Foundation Models", "On-device, private, fast"),
        ("none", "Disabled", "No AI features"),
    ]

    private let languageOptions = [("en", "English"), ("es", "Spanish")]

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView("Loading AI settings…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("AI Configuration")
                .task { loadSettings() }
        } else {
            loadedForm
        }
    }

    private var loadedForm: some View {
        Form {
            // Device info
            Section("Device Info") {
                LabeledContent("Device", value: UIDevice.current.model)
                LabeledContent("iOS Version", value: UIDevice.current.systemVersion)
            }

            Section {
                Toggle("Enable AI Features", isOn: $aiEnabled)
                    .onChange(of: aiEnabled) { _, _ in saveSetting("ai_enabled", value: aiEnabled ? "true" : "false") }
            } header: {
                Text("AI Assistant")
            } footer: {
                Text("AI features include text suggestions, smart search, and predictive ordering.")
            }

            if aiEnabled {
                Section("Onboarding Rollout") {
                    Toggle("Enable Onboard AI MVP", isOn: $onboardAIMVPEnabled)
                        .onChange(of: onboardAIMVPEnabled) { _, newValue in
                            let raw = newValue ? "true" : "false"
                            UserDefaults.standard.set(newValue, forKey: OnboardAIFeatureFlag.onboardingMVP)
                            saveSetting(OnboardAIFeatureFlag.onboardingMVP, value: raw)
                        }
                } footer: {
                    Text("Feature flag: \(OnboardAIFeatureFlag.onboardingMVP). Turn on to show the local AI onboarding entry on first-run flow.")
                }

                Section("Model Selection") {
                    ForEach(modelOptions, id: \.0) { option in
                        Button {
                            selectedModel = option.0
                            saveSetting("ai_model", value: option.0)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.1)
                                        .foregroundStyle(.primary)
                                        .fontWeight(selectedModel == option.0 ? .semibold : .regular)
                                    Text(option.2)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedModel == option.0 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .accessibilityAddTraits(selectedModel == option.0 ? .isSelected : [])
                    }
                }

                Section {
                    HStack {
                        Text("Foundation Models")
                        Spacer()
                        if isCheckingAvailability {
                            ProgressView().controlSize(.small)
                        } else if let status = availabilityStatus {
                            Text(statusLabel(status))
                                .foregroundStyle(status == .available ? .green : .red)
                        } else {
                            Text("Not Checked")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let status = availabilityStatus, status != .available {
                        Text(statusReason(status))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Check Availability") {
                        checkAvailability()
                    }
                    .disabled(isCheckingAvailability)
                } header: {
                    Text("Status")
                } footer: {
                    Text("Apple Foundation Models require iOS 26+ or macOS 26+ on compatible devices.")
                }

                // Language
                Section("Language") {
                    Picker("AI response language", selection: $aiLanguage) {
                        ForEach(languageOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .onChange(of: aiLanguage) { _, newValue in
                        saveSetting("ai_language", value: newValue)
                    }
                }
            }

            if let saveError {
                Section {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("AI Config")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "AI Config Help", sections: [
                ("What This Page Does", "Configures on-device AI features including model selection, availability checking, and language preferences. AI powers text suggestions, smart search, and predictive ordering."),
                ("How to Use It", "Toggle AI features on or off. Select Apple Foundation Models for on-device processing. Tap 'Check Availability' to verify your device supports on-device AI. Choose a language for AI responses."),
            ])
        }
    }

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    private func checkAvailability() {
        isCheckingAvailability = true
        let status = aiService.checkAvailability()
        availabilityStatus = status
        isCheckingAvailability = false
    }

    private func statusLabel(_ status: AIAvailability) -> String {
        switch status {
        case .available: return "Available"
        case .deviceNotEligible: return "Device Not Eligible"
        case .appleIntelligenceNotEnabled: return "Not Enabled"
        case .modelNotReady: return "Model Not Ready"
        case .unavailable: return "Not Available"
        case .notSupported: return "Not Supported"
        }
    }

    private func statusReason(_ status: AIAvailability) -> String {
        switch status {
        case .available: return ""
        case .deviceNotEligible: return "This device does not support on-device AI models."
        case .appleIntelligenceNotEnabled: return "Apple Intelligence is not enabled in Settings > Apple Intelligence."
        case .modelNotReady: return "The on-device model is downloading or not yet ready."
        case .unavailable: return "Foundation Models are not available on this device."
        case .notSupported: return "This iOS version does not support Foundation Models. iOS 26+ is required."
        }
    }

    private func loadSettings() {
        defer { isLoading = false }   // Fix #192: drop the loading gate once load completes
        guard let service = appCore.settingsService else {
            saveError = "Service not available"
            return
        }
        let map = (try? service.getSettingsByCategory("ai")) ?? [:]
        aiEnabled = (map["ai_enabled"] ?? "true") == "true"
        selectedModel = map["ai_model"] ?? "foundation"
        aiLanguage = map["ai_language"] ?? "en"
        let aiMVPSetting = map[OnboardAIFeatureFlag.onboardingMVP] ?? (UserDefaults.standard.bool(forKey: OnboardAIFeatureFlag.onboardingMVP) ? "true" : "false")
        onboardAIMVPEnabled = aiMVPSetting == "true"
        UserDefaults.standard.set(onboardAIMVPEnabled, forKey: OnboardAIFeatureFlag.onboardingMVP)
        checkAvailability()
    }

    private func saveSetting(_ key: String, value: String) {
        guard let service = appCore.settingsService else {
            saveError = "Service not available"
            return
        }
        do {
            try service.upsertSetting(key: key, value: value, category: "ai")
            saveError = nil
        } catch {
            saveError = userFriendlyError(error, context: "save data")
        }
    }
}
