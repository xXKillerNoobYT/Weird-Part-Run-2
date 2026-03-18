import SwiftUI
import WiredPartCore

/// AI configuration page — model selection and Foundation Models status.
struct IOSAIConfigPage: View {
    @EnvironmentObject private var appCore: AppCore

    @State private var aiEnabled = true
    @State private var selectedModel = "foundation"
    @State private var isCheckingAvailability = false
    @State private var modelAvailable = false

    private let modelOptions = [
        ("foundation", "Apple Foundation Models", "On-device, private, fast"),
        ("none", "Disabled", "No AI features"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Features", isOn: $aiEnabled)
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
                        } else {
                            Text(modelAvailable ? "Available" : "Not Available")
                                .foregroundStyle(modelAvailable ? .green : .secondary)
                        }
                    }
                    Button("Check Availability") {
                        checkAvailability()
                    }
                    .disabled(isCheckingAvailability)
                } header: {
                    Text("Status")
                } footer: {
                    Text("Apple Foundation Models require macOS 26+ or compatible devices.")
                }
            }
        }
        .navigationTitle("AI Config")
    }

    private func checkAvailability() {
        isCheckingAvailability = true
        // Check Foundation Models availability
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isCheckingAvailability = false
            // Foundation Models availability check would go here
            modelAvailable = false
        }
    }
}
