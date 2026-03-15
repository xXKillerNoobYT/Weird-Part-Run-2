import SwiftUI
import WiredPartCore

/// A text editor with AI-powered autocomplete and enhancement capabilities.
///
/// Wraps a standard `TextEditor` and adds:
/// - Ghost text suggestions (autocomplete)
/// - Enhancement popover (proofread, rewrite, summarize, expand, professional)
/// - Pre-fill button for empty fields
///
/// Falls back to a plain `TextEditor` when AI is unavailable.
struct AITextEditor: View {
    @Binding var text: String
    let fieldType: String
    var contextData: [String: String] = [:]
    var minHeight: CGFloat = 100

    @State private var suggestion: String = ""
    @State private var isLoadingSuggestion = false
    @State private var isEnhancing = false
    @State private var showEnhanceMenu = false
    @State private var aiAvailable = false
    @State private var debounceTask: Task<Void, Never>?

    private let aiService = FoundationModelsService()

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
                    .onKeyPress(.tab) {
                        if !suggestion.isEmpty {
                            acceptSuggestion()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if !suggestion.isEmpty {
                            suggestion = ""
                            return .handled
                        }
                        return .ignored
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
                aiControls
                    .padding(6)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.2))
            )

            // Hint text
            if !suggestion.isEmpty {
                Text("Press Tab to accept suggestion")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            aiAvailable = await aiService.isAvailable()
        }
    }

    // MARK: - AI Controls

    @ViewBuilder
    private var aiControls: some View {
        if aiAvailable {
            HStack(spacing: 4) {
                if isLoadingSuggestion || isEnhancing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                // Pre-fill button (when text is empty)
                if text.isEmpty && !contextData.isEmpty {
                    Button {
                        Task { await preFill() }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Generate draft with AI")
                }

                // Enhance button (when text is not empty)
                if !text.isEmpty {
                    Button {
                        showEnhanceMenu = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Enhance text with AI")
                    .popover(isPresented: $showEnhanceMenu) {
                        enhanceMenuContent
                    }
                }
            }
        }
    }

    private var enhanceMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Enhance Text")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            ForEach(EnhanceMode.allCases, id: \.self) { mode in
                Button {
                    showEnhanceMenu = false
                    Task { await enhance(mode: mode) }
                } label: {
                    Label(mode.displayName, systemImage: mode.systemImage)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 180)
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
