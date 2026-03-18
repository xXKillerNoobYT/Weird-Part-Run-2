import SwiftUI
import WiredPartCore

/// Floating AI assistant panel accessible from any page in the app.
///
/// Provides a compact interface for asking natural language questions
/// about the business data. Uses on-device Foundation Models when available,
/// gracefully degrades when unavailable.
///
/// Can be summoned via a floating button in the main view.
struct IOSAIAssistantPanel: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var messages: [AssistantMessage] = []
    @State private var isProcessing = false
    @State private var aiAvailability: AIAvailability = .notSupported

    private let aiService = FoundationModelsService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Availability banner
                availabilityHeader

                // Messages
                messagesArea

                // Input
                inputBar
            }
            .navigationTitle("AI Assistant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        messages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(messages.isEmpty)
                }
            }
            .task {
                aiAvailability = await aiService.checkAvailability()
                if messages.isEmpty {
                    messages.append(AssistantMessage(
                        role: .assistant,
                        content: "How can I help you today? I can answer questions about your jobs, parts, orders, and more."
                    ))
                }
            }
        }
    }

    // MARK: - Availability Header

    @ViewBuilder
    private var availabilityHeader: some View {
        switch aiAvailability {
        case .available:
            EmptyView()
        case .modelNotReady:
            statusBanner(
                icon: "arrow.down.circle",
                message: "AI model is downloading. Some features may be limited.",
                color: .orange
            )
        default:
            statusBanner(
                icon: "brain",
                message: "On-device AI unavailable. Using basic query matching.",
                color: .secondary
            )
        }
    }

    @ViewBuilder
    private func statusBanner(icon: String, message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        #if os(iOS)
        .background(Color(.secondarySystemGroupedBackground))
        #elseif os(macOS)
        .background(Color(.secondarySystemGroupedBackground))
        #endif
    }

    // MARK: - Messages Area

    @ViewBuilder
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Thinking...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user
                                  ? Color.accentColor
                                  : Color(.secondarySystemGroupedBackground))
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal)
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask a question...", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .disabled(isProcessing)

            Button {
                sendQuery()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isProcessing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(.systemBackground))
        #elseif os(macOS)
        .background(DS.Background.page)
        #endif
    }

    // MARK: - Send Query

    private func sendQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        messages.append(AssistantMessage(role: .user, content: trimmed))
        query = ""
        isProcessing = true

        Task {
            // Generate response
            let response = await generateResponse(for: trimmed)
            messages.append(AssistantMessage(role: .assistant, content: response))
            isProcessing = false
        }
    }

    /// Generates a response using Foundation Models when available,
    /// falls back to basic keyword matching.
    private func generateResponse(for queryText: String) async -> String {
        if aiAvailability == .available {
            // Use Foundation Models
            let result = await aiService.chat(query: queryText)
            if result.success, let text = result.text, !text.isEmpty {
                return text
            }
        }

        // Fallback: basic keyword matching against local data
        return generateFallbackResponse(for: queryText)
    }

    private func generateFallbackResponse(for queryText: String) -> String {
        let lower = queryText.lowercased()

        if lower.contains("job") || lower.contains("active") {
            return "You can view all active jobs in the Jobs module. Use the Jobs tab to see status, team assignments, and labor tracking."
        }
        if lower.contains("order") || lower.contains("purchase") {
            return "Check the Orders module for pending job part orders, purchase orders, and procurement planning."
        }
        if lower.contains("part") || lower.contains("stock") || lower.contains("inventory") {
            return "The Parts module has your full catalog with stock levels. The Warehouse module shows inventory movements and audits."
        }
        if lower.contains("schedule") || lower.contains("dispatch") {
            return "Use the Scheduling module to manage calendars, dispatch templates, and time-off requests."
        }
        if lower.contains("report") || lower.contains("timesheet") {
            return "The Reports module has timesheets, spending analysis, profitability charts, and pre-billing exports."
        }
        if lower.contains("fleet") || lower.contains("truck") || lower.contains("vehicle") {
            return "The Fleet module tracks vehicles, trailers, mileage, fuel, and maintenance. Check My Truck for your assigned vehicle."
        }

        return "I can help you navigate the app. Try asking about jobs, orders, parts, scheduling, reports, or fleet management."
    }
}

// MARK: - Message Model

private struct AssistantMessage: Identifiable, Sendable {
    let id = UUID()
    let role: MessageRole
    let content: String
}

private enum MessageRole: Sendable {
    case user, assistant
}
