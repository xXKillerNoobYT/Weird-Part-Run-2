import SwiftUI
import WiredPartCore

/// AI configuration page — model selection and Foundation Models status.
struct IOSAIConfigPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var aiEnabled = true
    @State private var selectedModel = "foundation"
    @State private var isCheckingAvailability = false
    @State private var availabilityStatus: AIAvailability?
    @State private var aiLanguage = "en"
    @State private var saveError: String?

    private let aiService = FoundationModelsService()

    private let modelOptions = [
        ("foundation", "Apple Foundation Models", "On-device, private, fast"),
        ("none", "Disabled", "No AI features"),
    ]

    private let languageOptions = [("en", "English"), ("es", "Spanish")]

    var body: some View {
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
                                }
                            }
                        }
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
        .task { loadSettings() }
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
        guard let service = appCore.settingsService else { return }
        let map = (try? service.getSettingsByCategory("ai")) ?? [:]
        aiEnabled = (map["ai_enabled"] ?? "true") == "true"
        selectedModel = map["ai_model"] ?? "foundation"
        aiLanguage = map["ai_language"] ?? "en"
        checkAvailability()
    }

    private func saveSetting(_ key: String, value: String) {
        guard let service = appCore.settingsService else { return }
        do {
            try service.upsertSetting(key: key, value: value, category: "ai")
            saveError = nil
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
