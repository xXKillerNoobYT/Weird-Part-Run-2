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
    @State private var catalogContext: String?
    @State private var pricingContext: String?
    @State private var suppliersContext: String?
    @State private var companionsContext: String?
    @State private var forecastContext: String?

    // Page context from all feature areas (prompt 60M)
    @State private var dashboardContext: String?
    @State private var jobsListContext: String?
    @State private var clockContext: String?
    @State private var jposContext: String?
    @State private var purchaseOrdersContext: String?
    @State private var inventoryGridContext: String?
    @State private var dispatchContext: String?
    @State private var scheduleCalendarContext: String?
    @State private var employeesContext: String?
    @State private var vehiclesContext: String?
    @State private var toolRegistryContext: String?
    @State private var notebooksListContext: String?
    @State private var settingsContext: String?

    /// Tracks which page the user is currently on, mapped to a HelpContentRegistry page ID.
    /// Updated whenever a page-active notification fires, cleared on page-inactive.
    @State private var activePageId: String?

    /// Unique ID for the current conversation thread. Changing this starts a fresh session.
    @State private var conversationId: String = UUID().uuidString

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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        Button {
                            withAnimation { displayMode = .overlay }
                            dismiss()
                            // Re-show as overlay after sheet dismisses
                            Task {
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                isVisible = true
                            }
                        } label: {
                            Image(systemName: "pip")
                        }
                        .help("Switch to floating overlay")
                        .accessibilityLabel("Switch to floating overlay")

                        Button {
                            startNewConversation()
                        } label: {
                            Image(systemName: "plus.bubble")
                        }
                        .help("New conversation")
                        .accessibilityLabel("New conversation")

                        Button {
                            clearCurrentConversation()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(messages.isEmpty)
                        .accessibilityLabel("Clear conversation")
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
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    isVisible = true
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Switch to full sheet")
            .accessibilityLabel("Switch to full sheet")

            Button {
                startNewConversation()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("New conversation")
            .accessibilityLabel("New conversation")

            Button {
                clearCurrentConversation()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty)
            .accessibilityLabel("Clear conversation")

            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close AI Assistant")
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
            aiAvailability = aiService.checkAvailability()
            await loadSavedMessages()
        }
        .modifier(PartsPageContextObservers(
            catalogContext: $catalogContext,
            pricingContext: $pricingContext,
            suppliersContext: $suppliersContext,
            companionsContext: $companionsContext,
            forecastContext: $forecastContext
        ))
        .modifier(FeaturePageContextObservers(
            dashboardContext: $dashboardContext,
            jobsListContext: $jobsListContext,
            clockContext: $clockContext,
            jposContext: $jposContext,
            purchaseOrdersContext: $purchaseOrdersContext,
            inventoryGridContext: $inventoryGridContext,
            dispatchContext: $dispatchContext,
            scheduleCalendarContext: $scheduleCalendarContext,
            employeesContext: $employeesContext,
            vehiclesContext: $vehiclesContext,
            toolRegistryContext: $toolRegistryContext,
            notebooksListContext: $notebooksListContext,
            settingsContext: $settingsContext
        ))
        .modifier(ActivePageIdTracker(activePageId: $activePageId))
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
        .background(Color(.secondarySystemGroupedBackground))
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
        .background(Color(.systemBackground))
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

    // MARK: - Conversation Lifecycle

    /// Start a brand-new conversation — clears the AI session, resets messages, generates a new ID.
    private func startNewConversation() {
        Task { await aiService.clearConversation() }
        conversationId = UUID().uuidString
        messages = [AssistantMessage(
            role: .assistant,
            content: "How can I help you today? I can search your data, answer questions about jobs, parts, orders, and help you navigate the app."
        )]
    }

    /// Delete all messages from the current conversation (UI + DB) but keep the same conversation ID.
    private func clearCurrentConversation() {
        let cid = conversationId
        messages.removeAll()
        Task { await aiService.clearConversation() }
        if let db = appCore.db {
            Task {
                try? await FoundationModelsService.deleteConversation(cid, from: db)
            }
        }
        // Re-add the welcome message
        messages.append(AssistantMessage(
            role: .assistant,
            content: "How can I help you today? I can search your data, answer questions about jobs, parts, orders, and help you navigate the app."
        ))
    }

    /// Load previously saved messages for the current conversation from the DB.
    private func loadSavedMessages() async {
        guard let db = appCore.db else {
            addWelcomeMessageIfNeeded()
            return
        }
        do {
            let saved = try await FoundationModelsService.loadConversation(conversationId, from: db)
            if saved.isEmpty {
                addWelcomeMessageIfNeeded()
            } else {
                messages = saved.map { msg in
                    AssistantMessage(
                        role: msg.role == "user" ? .user : .assistant,
                        content: msg.content
                    )
                }
            }
        } catch {
            addWelcomeMessageIfNeeded()
        }
    }

    /// Adds the default welcome message if the messages list is empty.
    private func addWelcomeMessageIfNeeded() {
        if messages.isEmpty {
            messages.append(AssistantMessage(
                role: .assistant,
                content: "How can I help you today? I can search your data, answer questions about jobs, parts, orders, and help you navigate the app."
            ))
        }
    }

    /// Generates a response using Foundation Models with tool calling when available,
    /// falls back to basic keyword matching.
    private func generateResponse(for queryText: String) async -> String {
        if aiAvailability == .available, let db = appCore.db {
            // Use Foundation Models with tool calling for real database access
            var navContext = buildNavigationContext(permissions: appCore.permissions)
            if let ctx = catalogContext {
                navContext += "\n\nCatalog Page Context: \(ctx)"
                navContext += " You can set catalog filters by responding with a JSON action block."
            }
            if let ctx = pricingContext {
                navContext += "\n\nPricing Page Context: \(ctx)"
            }
            if let ctx = suppliersContext {
                navContext += "\n\nSuppliers Page Context (READ-ONLY): \(ctx)"
            }
            if let ctx = companionsContext {
                navContext += "\n\nCompanions Page Context (READ-ONLY): \(ctx)"
            }
            if let ctx = forecastContext {
                navContext += "\n\nForecasting Page Context: \(ctx)"
                navContext += " You can help the user understand their forecast data, identify parts that need reordering, and explain usage trends."
            }
            // Append all feature page contexts (prompt 60M)
            if let ctx = dashboardContext {
                navContext += "\n\nDashboard Context: \(ctx)"
            }
            if let ctx = jobsListContext {
                navContext += "\n\nJobs List Context: \(ctx)"
            }
            if let ctx = clockContext {
                navContext += "\n\nClock In/Out Context: \(ctx)"
            }
            if let ctx = jposContext {
                navContext += "\n\nJob Purchase Orders Context: \(ctx)"
            }
            if let ctx = purchaseOrdersContext {
                navContext += "\n\nPurchase Orders Context: \(ctx)"
            }
            if let ctx = inventoryGridContext {
                navContext += "\n\nInventory Grid Context: \(ctx)"
            }
            if let ctx = dispatchContext {
                navContext += "\n\nDispatch Board Context: \(ctx)"
            }
            if let ctx = scheduleCalendarContext {
                navContext += "\n\nSchedule Calendar Context: \(ctx)"
            }
            if let ctx = employeesContext {
                navContext += "\n\nEmployees Context: \(ctx)"
            }
            if let ctx = vehiclesContext {
                navContext += "\n\nVehicles Context: \(ctx)"
            }
            if let ctx = toolRegistryContext {
                navContext += "\n\nTool Registry Context: \(ctx)"
            }
            if let ctx = notebooksListContext {
                navContext += "\n\nNotebooks Context: \(ctx)"
            }
            if let ctx = settingsContext {
                navContext += "\n\nSettings Context: \(ctx)"
            }
            let result = await aiService.chatWithTools(
                query: queryText,
                db: db,
                permissions: appCore.permissions,
                userId: appCore.currentUser?.id ?? 0,
                navigationContext: navContext,
                conversationId: conversationId
            )
            if result.success, let text = result.text, !text.isEmpty {
                // Check for AI filter activation commands in the response (prompt 62S)
                parseAndApplyFilterCommands(text)
                return cleanFilterJSON(text)
            }
        }

        // Fallback: if on the catalog page, try to handle filter requests locally
        if catalogContext != nil {
            return handleCatalogFallback(for: queryText)
        }

        // Fallback: if on the pricing page, provide pricing-specific help
        if let ctx = pricingContext {
            return handlePricingFallback(for: queryText, context: ctx)
        }

        // Fallback: if on the suppliers page, provide supplier-specific help
        if let ctx = suppliersContext {
            return handleSuppliersFallback(for: queryText, context: ctx)
        }

        // Fallback: if on the companions page, provide companions-specific help
        if companionsContext != nil {
            return "I can help you with companion rules, voting polls, and co-occurrence data. On-device AI is required for full functionality — please check Settings > AI to enable Apple Foundation Models."
        }

        // Fallback: if user asks about help / how to use the current page, use HelpContentRegistry
        if let helpResponse = generateHelpContentResponse(for: queryText) {
            return helpResponse
        }

        // Fallback: basic keyword matching
        return generateFallbackResponse(for: queryText)
    }

    /// Handles pricing-specific queries when Foundation Models aren't available.
    private func handlePricingFallback(for queryText: String, context: String) -> String {
        let lower = queryText.lowercased()

        if lower.contains("markup") && lower.contains("margin") {
            return "**Markup vs Margin**\n\nMarkup is calculated on cost: (Sell - Cost) / Cost × 100\n\nMargin is calculated on sell price: (Sell - Cost) / Sell × 100\n\nExample: Cost $10, Sell $15 → Markup 50%, Margin 33.3%\n\nYou can switch between modes in Pricing Settings."
        }

        if lower.contains("stale") || lower.contains("outdated") || lower.contains("update") {
            return "Stale prices are parts whose cost hasn't been verified recently (default: 90 days). Look for the orange triangle icon on the pricing list. You can verify prices during PO receiving, or update them manually by tapping any part."
        }

        if lower.contains("fifo") || lower.contains("cost layer") || lower.contains("weighted") {
            return "**FIFO Costing**\n\nWhen you receive parts, each batch creates a cost layer at the purchase price. When parts are consumed (sold/used), the oldest batch is used first (First In, First Out).\n\nThe weighted average cost combines all batches: Σ(qty × cost) / Σ(qty). This is what's used to calculate markup and margin."
        }

        if lower.contains("tier") || lower.contains("hierarchy") || lower.contains("inherit") {
            return "**Hierarchical Pricing**\n\nPrices cascade: Part → Brand → Type → Style → Category → Default. A part uses the most specific tier available. Parts with a direct price tier show a green 'Part' badge. Inherited prices show an orange badge indicating the source level."
        }

        // Generic: return the context summary
        return "Here's the current pricing summary from this page:\n\n\(context)\n\nAsk me about markup vs margin, stale prices, FIFO costing, or tier pricing for more details."
    }

    /// Handles supplier-specific queries when Foundation Models aren't available.
    private func handleSuppliersFallback(for queryText: String, context: String) -> String {
        let lower = queryText.lowercased()

        if lower.contains("best") && (lower.contains("quality") || lower.contains("score")) {
            return "Check the supplier list sorted by Quality score (use the sort button → Quality ↓). The quality score is based on return rate — fewer returns means higher quality. Scores appear after the first PO is received and items are returned/not returned."
        }

        if lower.contains("on-time") || lower.contains("on time") || lower.contains("delivery") {
            return "On-Time Rate measures how often a supplier delivers within their stated delivery window. Sort by On-Time ↓ to find the most reliable deliverers. The rate is calculated from PO creation date to receiving session completion date vs. the supplier's stated delivery days."
        }

        if lower.contains("account") || lower.contains("number") {
            return "Account numbers are shown on each supplier's detail card. You can search by account number using the search bar. To add or edit an account number, tap a supplier → Edit (pencil icon)."
        }

        if lower.contains("edit") || lower.contains("change") || lower.contains("add") || lower.contains("delete") || lower.contains("remove") {
            return "I'm a read-only assistant for supplier data — I can't make changes. To edit a supplier, tap it to open the detail sheet, then use the pencil (edit) button. To add a new supplier, use the + button in the toolbar."
        }

        if lower.contains("brand") {
            return "Each supplier's detail sheet shows which brands they carry. You can also manage brand-supplier links from the Brands tab → tap a brand → Manage Suppliers."
        }

        if lower.contains("contact") {
            return "Supplier contacts are shown on the detail sheet. You can add multiple contacts with different roles (Sales Rep, Accounts Payable, etc.) using the + button in the Contacts section. Phone numbers and emails are tappable."
        }

        return "Here's the current supplier data:\n\n\(context)\n\nAsk me about quality scores, on-time rates, account numbers, brands, or contacts for more details."
    }

    /// Handles catalog-specific queries when Foundation Models aren't available.
    private func handleCatalogFallback(for queryText: String) -> String {
        let lower = queryText.lowercased()
        var filters: [String: Any] = [:]

        if lower.contains("clear") && (lower.contains("filter") || lower.contains("all")) {
            filters["clearAll"] = true
            applyAIFilterCommand(filters)
            return "Done — cleared all filters."
        }

        if lower.contains("low stock") || lower.contains("low-stock") {
            filters["lowStock"] = true
        }

        // Look for filter keywords
        let filterKeywords = [
            ("brand", "brand"), ("category", "category"), ("color", "color"),
            ("style", "style"), ("type", "type")
        ]
        for (keyword, filterKey) in filterKeywords {
            if let range = lower.range(of: "\(keyword) ") {
                let afterKeyword = String(lower[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let value = afterKeyword.components(separatedBy: .whitespaces).first ?? afterKeyword
                if !value.isEmpty {
                    filters[filterKey] = value.capitalized
                }
            }
        }

        if !filters.isEmpty {
            applyAIFilterCommand(filters)
            return "Updated catalog filters. Check the catalog view for results."
        }

        return generateFallbackResponse(for: queryText)
    }

    /// Posts filter changes to the catalog page via NotificationCenter.
    private func applyAIFilterCommand(_ filters: [String: Any]) {
        NotificationCenter.default.post(
            name: .aiSetCatalogFilters,
            object: nil,
            userInfo: filters
        )
    }

    // MARK: - AI Filter Command Parsing (prompt 62S)

    /// Scans AI response text for filter activation JSON blocks and applies them.
    /// Expected format: {"activateFilter": {"pageId": "purchase-orders", "value": "draft"}}
    private func parseAndApplyFilterCommands(_ text: String) {
        // Look for JSON blocks containing activateFilter
        let pattern = #"\{[^{}]*"activateFilter"\s*:\s*\{[^{}]*"pageId"\s*:\s*"([^"]+)"[^{}]*"value"\s*:\s*"([^"]+)"[^{}]*\}[^{}]*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let pageId = nsText.substring(with: match.range(at: 1))
            let value = nsText.substring(with: match.range(at: 2))
            appCore.aiFilterRegistry.activateFilter(pageId: pageId, value: value)
        }
    }

    /// Removes filter activation JSON blocks from the AI response so the user
    /// sees clean natural language text only.
    private func cleanFilterJSON(_ text: String) -> String {
        let pattern = #"\s*\{[^{}]*"activateFilter"\s*:\s*\{[^{}]*\}[^{}]*\}\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let nsText = text as NSString
        let cleaned = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length),
            withTemplate: ""
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Navigation Context Builder

    /// Builds a string describing the app's module/tab layout with permission annotations.
    /// This is embedded in the AI's system instructions so it can guide users to features
    /// and note when they lack access to something.
    ///
    /// Also includes help content awareness from `HelpContentRegistry` so the AI can
    /// provide accurate page-specific guidance when users ask "how do I use this page?"
    private func buildNavigationContext(permissions: [String]) -> String {
        var lines: [String] = ["App Navigation Structure:"]
        for module in appModules {
            let hasAccess = module.permission.map { permissions.contains($0) } ?? true
            let accessNote = hasAccess ? "" : " [NO ACCESS]"
            lines.append("- \(module.label) (\(module.icon))\(accessNote)")
            for tab in module.tabs {
                let tabAccess = tab.permission.map { permissions.contains($0) } ?? true
                let tabNote = tabAccess ? "" : " [NO ACCESS]"
                lines.append("  - \(tab.label): \(tab.path)\(tabNote)")
            }
        }

        // Add available AI-activated filters (prompt 62S)
        let availableFilters = appCore.aiFilterRegistry.getAvailableFilters()
        if !availableFilters.isEmpty {
            lines.append("")
            lines.append("AI-Activated Page Filters (you can set these for the user):")
            for filter in availableFilters {
                lines.append("  - Page '\(filter.pageId)': \(filter.filterName) — options: \(filter.options.joined(separator: ", "))")
            }
            lines.append("To activate a filter, include a JSON block in your response: {\"activateFilter\": {\"pageId\": \"<id>\", \"value\": \"<option>\"}}. The filter will be applied immediately if the page is active, or queued for when the user navigates to it.")
        }

        // Add help content awareness
        lines.append("")
        lines.append("You have detailed help content for these pages: \(HelpContentRegistry.availableTopics.joined(separator: ", ")). When the user asks how to use a page or feature, reference this help content for accurate answers.")

        // If we know which page the user is on, include that page's full help content
        if let pageId = activePageId, let helpText = HelpContentRegistry.formattedHelp(for: pageId) {
            lines.append("")
            lines.append("Current Page Help Content:")
            lines.append(helpText)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Help Content Response

    /// Checks if the user is asking about page help and returns a formatted response
    /// from the HelpContentRegistry. Returns nil if the query doesn't match a help request.
    private func generateHelpContentResponse(for queryText: String) -> String? {
        let lower = queryText.lowercased()

        // Detect help-seeking queries
        let isHelpQuery = lower.contains("how do i") || lower.contains("how to")
            || lower.contains("help") || lower.contains("what does this")
            || lower.contains("explain this") || lower.contains("what is this page")
            || lower.contains("how does this work") || lower.contains("what can i do")

        // If user is on a known page and asking for help, provide that page's help
        if isHelpQuery, let pageId = activePageId, let entry = HelpContentRegistry.helpFor(pageId) {
            var response = "**\(entry.title)**\n\n"
            for (heading, body) in entry.sections {
                response += "**\(heading):** \(body)\n\n"
            }
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If user asks about a specific feature by keyword, search the registry
        if isHelpQuery {
            let matches = HelpContentRegistry.search(keyword: queryText)
            if let best = matches.first {
                var response = "**\(best.title)**\n\n"
                for (heading, body) in best.sections {
                    response += "**\(heading):** \(body)\n\n"
                }
                return response.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
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

// MARK: - Page Context Observer Modifiers

/// Groups the original 5 Parts page notification observers to keep chatBody type-checker happy.
private struct PartsPageContextObservers: ViewModifier {
    @Binding var catalogContext: String?
    @Binding var pricingContext: String?
    @Binding var suppliersContext: String?
    @Binding var companionsContext: String?
    @Binding var forecastContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .catalogPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { catalogContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .catalogPageInactive)) { _ in
                catalogContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .pricingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { pricingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pricingPageInactive)) { _ in
                pricingContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .suppliersPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { suppliersContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .suppliersPageInactive)) { _ in
                suppliersContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .companionsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { companionsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .companionsPageInactive)) { _ in
                companionsContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .forecastingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { forecastContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .forecastingPageInactive)) { _ in
                forecastContext = nil
            }
    }
}

/// Groups the prompt 60M feature page notification observers into a single modifier
/// to avoid Swift type-checker complexity limits from long `.onReceive` chains.
private struct FeaturePageContextObservers: ViewModifier {
    @Binding var dashboardContext: String?
    @Binding var jobsListContext: String?
    @Binding var clockContext: String?
    @Binding var jposContext: String?
    @Binding var purchaseOrdersContext: String?
    @Binding var inventoryGridContext: String?
    @Binding var dispatchContext: String?
    @Binding var scheduleCalendarContext: String?
    @Binding var employeesContext: String?
    @Binding var vehiclesContext: String?
    @Binding var toolRegistryContext: String?
    @Binding var notebooksListContext: String?
    @Binding var settingsContext: String?

    func body(content: Content) -> some View {
        content
            .modifier(FeaturePageContextObserversGroupA(
                dashboardContext: $dashboardContext,
                jobsListContext: $jobsListContext,
                clockContext: $clockContext,
                jposContext: $jposContext,
                purchaseOrdersContext: $purchaseOrdersContext,
                inventoryGridContext: $inventoryGridContext,
                dispatchContext: $dispatchContext
            ))
            .modifier(FeaturePageContextObserversGroupB(
                scheduleCalendarContext: $scheduleCalendarContext,
                employeesContext: $employeesContext,
                vehiclesContext: $vehiclesContext,
                toolRegistryContext: $toolRegistryContext,
                notebooksListContext: $notebooksListContext,
                settingsContext: $settingsContext
            ))
    }
}

/// First group of feature page observers (Dashboard, Jobs, Clock, JPOs, POs, Inventory, Dispatch).
private struct FeaturePageContextObserversGroupA: ViewModifier {
    @Binding var dashboardContext: String?
    @Binding var jobsListContext: String?
    @Binding var clockContext: String?
    @Binding var jposContext: String?
    @Binding var purchaseOrdersContext: String?
    @Binding var inventoryGridContext: String?
    @Binding var dispatchContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .dashboardPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { dashboardContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardPageInactive)) { _ in
                dashboardContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .jobsListPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { jobsListContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jobsListPageInactive)) { _ in
                jobsListContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .clockPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { clockContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clockPageInactive)) { _ in
                clockContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .jposPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { jposContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jposPageInactive)) { _ in
                jposContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .purchaseOrdersPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { purchaseOrdersContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .purchaseOrdersPageInactive)) { _ in
                purchaseOrdersContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .inventoryGridPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { inventoryGridContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inventoryGridPageInactive)) { _ in
                inventoryGridContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .dispatchPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { dispatchContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dispatchPageInactive)) { _ in
                dispatchContext = nil
            }
    }
}

/// Second group of feature page observers (Schedule, Employees, Vehicles, Tools, Notebooks, Settings).
private struct FeaturePageContextObserversGroupB: ViewModifier {
    @Binding var scheduleCalendarContext: String?
    @Binding var employeesContext: String?
    @Binding var vehiclesContext: String?
    @Binding var toolRegistryContext: String?
    @Binding var notebooksListContext: String?
    @Binding var settingsContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .scheduleCalendarPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { scheduleCalendarContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleCalendarPageInactive)) { _ in
                scheduleCalendarContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .employeesPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { employeesContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .employeesPageInactive)) { _ in
                employeesContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .vehiclesPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { vehiclesContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vehiclesPageInactive)) { _ in
                vehiclesContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolRegistryPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { toolRegistryContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolRegistryPageInactive)) { _ in
                toolRegistryContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .notebooksListPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { notebooksListContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notebooksListPageInactive)) { _ in
                notebooksListContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { settingsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageInactive)) { _ in
                settingsContext = nil
            }
    }
}

// MARK: - Active Page ID Tracker (prompt 60N)

/// Tracks which page the user is currently viewing by listening to all page-active/inactive
/// notifications and mapping them to HelpContentRegistry page IDs. This allows the AI
/// to automatically include the correct help content in its system prompt.
///
/// Split into 4 sub-groups to stay within Swift's type-checker complexity limits.
private struct ActivePageIdTracker: ViewModifier {
    @Binding var activePageId: String?

    func body(content: Content) -> some View {
        content
            .modifier(ActivePageIdTrackerParts(activePageId: $activePageId))
            .modifier(ActivePageIdTrackerDashJobs(activePageId: $activePageId))
            .modifier(ActivePageIdTrackerOrdersWarehouse(activePageId: $activePageId))
            .modifier(ActivePageIdTrackerSchedulePeopleMore(activePageId: $activePageId))
    }
}

/// Page ID tracker group 1: Parts pages (catalog, pricing, suppliers, companions, forecasting).
private struct ActivePageIdTrackerParts: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .catalogPageActive)) { _ in activePageId = "parts-catalog" }
            .onReceive(NotificationCenter.default.publisher(for: .catalogPageInactive)) { _ in if activePageId == "parts-catalog" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .pricingPageActive)) { _ in activePageId = "parts-pricing" }
            .onReceive(NotificationCenter.default.publisher(for: .pricingPageInactive)) { _ in if activePageId == "parts-pricing" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .suppliersPageActive)) { _ in activePageId = "parts-suppliers" }
            .onReceive(NotificationCenter.default.publisher(for: .suppliersPageInactive)) { _ in if activePageId == "parts-suppliers" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .companionsPageActive)) { _ in activePageId = "parts-companions" }
            .onReceive(NotificationCenter.default.publisher(for: .companionsPageInactive)) { _ in if activePageId == "parts-companions" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .forecastingPageActive)) { _ in activePageId = "parts-forecasting" }
            .onReceive(NotificationCenter.default.publisher(for: .forecastingPageInactive)) { _ in if activePageId == "parts-forecasting" { activePageId = nil } }
    }
}

/// Page ID tracker group 2: Dashboard, Jobs, Clock pages.
private struct ActivePageIdTrackerDashJobs: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .dashboardPageActive)) { _ in activePageId = "dashboard-home" }
            .onReceive(NotificationCenter.default.publisher(for: .dashboardPageInactive)) { _ in if activePageId == "dashboard-home" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .jobsListPageActive)) { _ in activePageId = "jobs-list" }
            .onReceive(NotificationCenter.default.publisher(for: .jobsListPageInactive)) { _ in if activePageId == "jobs-list" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .clockPageActive)) { _ in activePageId = "dashboard-clock" }
            .onReceive(NotificationCenter.default.publisher(for: .clockPageInactive)) { _ in if activePageId == "dashboard-clock" { activePageId = nil } }
    }
}

/// Page ID tracker group 3: Orders + Warehouse pages (JPOs, POs, Inventory).
private struct ActivePageIdTrackerOrdersWarehouse: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jposPageActive)) { _ in activePageId = "orders-jpos" }
            .onReceive(NotificationCenter.default.publisher(for: .jposPageInactive)) { _ in if activePageId == "orders-jpos" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .purchaseOrdersPageActive)) { _ in activePageId = "orders-pos" }
            .onReceive(NotificationCenter.default.publisher(for: .purchaseOrdersPageInactive)) { _ in if activePageId == "orders-pos" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .inventoryGridPageActive)) { _ in activePageId = "warehouse-inventory" }
            .onReceive(NotificationCenter.default.publisher(for: .inventoryGridPageInactive)) { _ in if activePageId == "warehouse-inventory" { activePageId = nil } }
    }
}

/// Page ID tracker group 4: Scheduling, People, Fleet, Tools, Notebooks, Settings.
private struct ActivePageIdTrackerSchedulePeopleMore: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .dispatchPageActive)) { _ in activePageId = "scheduling-dispatch" }
            .onReceive(NotificationCenter.default.publisher(for: .dispatchPageInactive)) { _ in if activePageId == "scheduling-dispatch" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleCalendarPageActive)) { _ in activePageId = "scheduling-calendar" }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleCalendarPageInactive)) { _ in if activePageId == "scheduling-calendar" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .employeesPageActive)) { _ in activePageId = "people-employees" }
            .onReceive(NotificationCenter.default.publisher(for: .employeesPageInactive)) { _ in if activePageId == "people-employees" { activePageId = nil } }
            .modifier(ActivePageIdTrackerFleetToolsNotebooks(activePageId: $activePageId))
    }
}

/// Page ID tracker group 4b: Fleet, Tools, Notebooks, Settings (sub-split to avoid type-checker limits).
private struct ActivePageIdTrackerFleetToolsNotebooks: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .vehiclesPageActive)) { _ in activePageId = "fleet-vehicles" }
            .onReceive(NotificationCenter.default.publisher(for: .vehiclesPageInactive)) { _ in if activePageId == "fleet-vehicles" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .toolRegistryPageActive)) { _ in activePageId = "tools-registry" }
            .onReceive(NotificationCenter.default.publisher(for: .toolRegistryPageInactive)) { _ in if activePageId == "tools-registry" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .notebooksListPageActive)) { _ in activePageId = "notebooks-all" }
            .onReceive(NotificationCenter.default.publisher(for: .notebooksListPageInactive)) { _ in if activePageId == "notebooks-all" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageActive)) { _ in activePageId = "settings-app-config" }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageInactive)) { _ in if activePageId == "settings-app-config" { activePageId = nil } }
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
