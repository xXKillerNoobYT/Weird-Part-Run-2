import SwiftUI
import WiredPartCore

// MARK: - AI Display Mode

/// Controls how the AI assistant panel is presented.
enum AIDisplayMode: String, Sendable {
    case sheet   // Full modal sheet (default)
    case overlay // Floating panel, app remains navigable
}

// MARK: - AI Assistant Panel

/// Floating AI assistant panel accessible from any page in the app.
///
/// Provides a compact interface for asking natural language questions
/// about the business data. Uses on-device Foundation Models with tool calling
/// when available, gracefully degrades to keyword matching when unavailable.
///
/// Features:
/// - Enter to send, Shift+Enter for newline
/// - Real database queries via Foundation Models tool calling
/// - Permission-gated data access (AI can't see what the user can't see)
/// - App layout awareness for navigation guidance
/// - Sheet or floating overlay display mode
struct IOSAIAssistantPanel: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @Binding var displayMode: AIDisplayMode
    @Binding var isVisible: Bool

    @State private var query = ""
    @State private var messages: [AssistantMessage] = []
    @State private var isProcessing = false
    @State private var aiAvailability: AIAvailability = .notSupported

    private let aiService = FoundationModelsService()

    var body: some View {
        if displayMode == .sheet {
            sheetContent
        } else {
            overlayContent
        }
    }

    // MARK: - Sheet Mode

    @ViewBuilder
    private var sheetContent: some View {
        NavigationStack {
            chatBody
                .navigationTitle("AI Assistant")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        Button {
                            withAnimation { displayMode = .overlay }
                            dismiss()
                            // Re-show as overlay after sheet dismisses
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                isVisible = true
                            }
                        } label: {
                            Image(systemName: "pip")
                        }
                        .help("Switch to floating overlay")

                        Button {
                            messages.removeAll()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(messages.isEmpty)
                    }
                }
        }
    }

    // MARK: - Overlay Mode

    @ViewBuilder
    private var overlayContent: some View {
        VStack(spacing: 0) {
            // Overlay header with controls
            overlayHeader

            Divider()

            // Availability banner
            availabilityHeader

            // Messages + Input
            chatBody
        }
        .frame(
            width: DeviceContext.isLargeScreen ? 360 : nil,
            height: DeviceContext.isLargeScreen ? 440 : nil
        )
        .frame(maxWidth: DeviceContext.isLargeScreen ? 360 : .infinity,
               maxHeight: DeviceContext.isLargeScreen ? 440 : .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(DeviceContext.isLargeScreen ? 12 : 0)
    }

    @ViewBuilder
    private var overlayHeader: some View {
        HStack {
            Text("AI Assistant")
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            Button {
                // Switch to sheet mode
                isVisible = false
                withAnimation { displayMode = .sheet }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isVisible = true
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Switch to full sheet")

            Button {
                messages.removeAll()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty)

            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Shared Chat Body

    @ViewBuilder
    private var chatBody: some View {
        VStack(spacing: 0) {
            if displayMode == .sheet {
                availabilityHeader
            }
            messagesArea
            inputBar
        }
        .task {
            aiAvailability = await aiService.checkAvailability()
            if messages.isEmpty {
                messages.append(AssistantMessage(
                    role: .assistant,
                    content: "How can I help you today? I can search your data, answer questions about jobs, parts, orders, and help you navigate the app."
                ))
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
        HStack(alignment: .bottom, spacing: 8) {
            // Multi-line text editor with Enter/Shift+Enter handling
            chatTextEditor

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

    /// Text editor that supports Enter to send and Shift+Enter for newline.
    @ViewBuilder
    private var chatTextEditor: some View {
        let lineCount = max(1, query.components(separatedBy: "\n").count)
        let dynamicHeight = min(max(CGFloat(lineCount) * 20 + 16, 44), 120)

        TextEditor(text: $query)
            .font(.subheadline)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 44, maxHeight: dynamicHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 0.5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
            )
            .disabled(isProcessing)
            .onKeyPress(.return, phases: .down) { keyPress in
                if keyPress.modifiers.contains(.shift) {
                    // Shift+Enter: allow default (insert newline)
                    return .ignored
                } else {
                    // Enter alone: send the message
                    sendQuery()
                    return .handled
                }
            }
    }

    // MARK: - Send Query

    private func sendQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(AssistantMessage(role: .user, content: trimmed))
        query = ""
        isProcessing = true

        Task {
            let response = await generateResponse(for: trimmed)
            messages.append(AssistantMessage(role: .assistant, content: response))
            isProcessing = false
        }
    }

    /// Generates a response using Foundation Models with tool calling when available,
    /// falls back to basic keyword matching.
    private func generateResponse(for queryText: String) async -> String {
        if aiAvailability == .available, let db = appCore.db {
            // Use Foundation Models with tool calling for real database access
            let navContext = buildNavigationContext(permissions: appCore.permissions)
            let result = await aiService.chatWithTools(
                query: queryText,
                db: db,
                permissions: appCore.permissions,
                navigationContext: navContext
            )
            if result.success, let text = result.text, !text.isEmpty {
                return text
            }
        }

        // Fallback: basic keyword matching
        return generateFallbackResponse(for: queryText)
    }

    // MARK: - Navigation Context Builder

    /// Builds a string describing the app's module/tab layout with permission annotations.
    /// This is embedded in the AI's system instructions so it can guide users to features
    /// and note when they lack access to something.
    private func buildNavigationContext(permissions: [String]) -> String {
        var lines: [String] = ["App Navigation Structure:"]
        for module in appModules {
            let hasAccess = module.permission == nil || permissions.contains(module.permission!)
            let accessNote = hasAccess ? "" : " [NO ACCESS]"
            lines.append("- \(module.label) (\(module.icon))\(accessNote)")
            for tab in module.tabs {
                let tabAccess = tab.permission == nil || permissions.contains(tab.permission!)
                let tabNote = tabAccess ? "" : " [NO ACCESS]"
                lines.append("  - \(tab.label): \(tab.path)\(tabNote)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Fallback Response

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

        return "I can help you navigate the app and search your data. Try asking about jobs, orders, parts, scheduling, reports, or fleet management."
    }
}

// MARK: - Message Model

struct AssistantMessage: Identifiable, Sendable {
    let id = UUID()
    let role: MessageRole
    let content: String
}

enum MessageRole: Sendable {
    case user, assistant
}
