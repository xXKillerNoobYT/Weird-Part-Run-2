import SwiftUI
import WiredPartCore

/// A text editor with AI-powered autocomplete and enhancement for iOS.
///
/// Wraps a standard `TextEditor` and adds:
/// - Ghost text suggestions (autocomplete)
/// - Enhancement sheet (proofread, rewrite, summarize, expand, professional)
/// - Pre-fill button for empty fields
///
/// Controls are always visible. When AI is unavailable, tapping them
/// shows a helpful status message instead of silently hiding functionality.
struct IOSAITextEditor: View {
    @Binding var text: String
    let fieldType: String
    var contextData: [String: String] = [:]
    var minHeight: CGFloat = 120

    @State private var suggestion: String = ""
    @State private var isLoadingSuggestion = false
    @State private var isEnhancing = false
    @State private var showEnhanceSheet = false
    @State private var showUnavailableAlert = false
    @State private var aiAvailability: AIAvailability = .notSupported
    @State private var debounceTask: Task<Void, Never>?

    private let aiService = FoundationModelsService()

    private var aiAvailable: Bool {
        aiAvailability == .available
    }

    private var unavailableMessage: String {
        switch aiAvailability {
        case .available:
            return ""
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in your device Settings to enable AI text features."
        case .modelNotReady:
            return "The AI model is still downloading. Please try again later."
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. AI features require iPhone 15 Pro or later."
        case .unavailable:
            return "AI features are temporarily unavailable. Please try again later."
        case .notSupported:
            return "AI features require iOS 26 or later with Apple Intelligence enabled."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .onChange(of: text) { _, newValue in
                        onTextChange(newValue)
                    }

                // Ghost text overlay
                if !suggestion.isEmpty {
                    Text(text + suggestion)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                iosAIControls
                    .padding(8)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Suggestion accept bar
            if !suggestion.isEmpty {
                Button {
                    acceptSuggestion()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Accept suggestion")
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            aiAvailability = aiService.checkAvailability()
        }
        .sheet(isPresented: $showEnhanceSheet) {
            enhanceSheet
        }
        .alert("AI Unavailable", isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(unavailableMessage)
        }
    }

    // MARK: - AI Controls

    @ViewBuilder
    private var iosAIControls: some View {
        HStack(spacing: 8) {
            if isLoadingSuggestion || isEnhancing {
                ProgressView()
                    .scaleEffect(0.7)
            }

            // Pre-fill button — always visible when field is empty with context
            if text.isEmpty && !contextData.isEmpty {
                Button {
                    if aiAvailable {
                        Task { await preFill() }
                    } else {
                        showUnavailableAlert = true
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.body)
                        .foregroundStyle(aiAvailable ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI pre-fill")
            }

            // Enhance button — always visible when text exists
            if !text.isEmpty {
                Button {
                    if aiAvailable {
                        showEnhanceSheet = true
                    } else {
                        showUnavailableAlert = true
                    }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.body)
                        .foregroundStyle(aiAvailable ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enhance text with AI")
            }
        }
    }

    private var enhanceSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(EnhanceMode.allCases, id: \.self) { mode in
                        Button {
                            showEnhanceSheet = false
                            Task { await enhance(mode: mode) }
                        } label: {
                            Label(mode.displayName, systemImage: mode.systemImage)
                        }
                    }
                } header: {
                    Text("Choose enhancement")
                } footer: {
                    Text("AI will transform your text using the selected mode.")
                }
            }
            .navigationTitle("Enhance Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEnhanceSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func onTextChange(_ newText: String) {
        suggestion = ""
        debounceTask?.cancel()

        guard aiAvailable, newText.count >= 10 else { return }

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }

            isLoadingSuggestion = true
            let result = await aiService.generateCompletion(
                partialText: newText,
                fieldType: fieldType,
                contextData: contextData.isEmpty ? nil : contextData
            )
            isLoadingSuggestion = false

            if result.success, let completionText = result.text {
                suggestion = completionText
            }
        }
    }

    private func acceptSuggestion() {
        text += suggestion
        suggestion = ""
    }

    private func enhance(mode: EnhanceMode) async {
        isEnhancing = true
        let result = await aiService.enhanceText(
            text: text,
            mode: mode,
            fieldType: fieldType
        )
        isEnhancing = false

        if result.success, let enhanced = result.text {
            text = enhanced
        }
    }

    private func preFill() async {
        isEnhancing = true
        let result = await aiService.generatePreFill(
            fieldType: fieldType,
            contextData: contextData
        )
        isEnhancing = false

        if result.success, let draft = result.text {
            text = draft
        }
    }
}
