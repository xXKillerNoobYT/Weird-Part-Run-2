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
    @Binding var pendingHelpRequest: [AnyHashable: Any]?

    @State private var query = ""
    @State private var messages: [AssistantMessage] = []
    @State private var isProcessing = false
    @State private var isClearingConversation = false
    /// Invalidates response tasks when Clear, New, Resume, or logout changes visible history.
    @State private var conversationRevision: UInt = 0
    @State private var clearConversationError: String?
    @State private var clearConversationRetryId: String?
    @State private var conversationPersistenceError: String?
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
    @State private var jobDetailContext: String?
    @State private var laborContext: String?
    @State private var dailyReportsContext: String?
    @State private var questionnaireContext: String?
    @State private var estimationQuestionnaireContext: String?
    @State private var estimationReviewContext: String?
    @State private var jobReportsContext: String?
    @State private var jposContext: String?
    @State private var purchaseOrdersContext: String?
    @State private var poDetailContext: String?
    @State private var receiveShipmentContext: String?
    @State private var procurementContext: String?
    @State private var returnsContext: String?
    @State private var jpoCreationContext: String?
    @State private var jpoDetailContext: String?
    @State private var orderStagingContext: String?
    @State private var partsOrderManagementContext: String?
    @State private var ordersWishlistContext: String?
    @State private var unifiedOrderContext: String?
    @State private var warehouseDashboardContext: String?
    @State private var inventoryGridContext: String?
    @State private var warehouseLocationsContext: String?
    @State private var warehouseMovementsContext: String?
    @State private var warehouseReceivingContext: String?
    @State private var warehouseStagingContext: String?
    @State private var warehouseAuditContext: String?
    @State private var warehouseReturnsContext: String?
    @State private var warehouseToolsContext: String?
    @State private var warehouseNetworkContext: String?
    @State private var warehouseSettingsContext: String?
    @State private var warehouseOrganizationAuditContext: String?
    @State private var warehouseLeaderboardContext: String?
    @State private var dispatchContext: String?
    @State private var scheduleCalendarContext: String?
    @State private var employeesContext: String?
    @State private var peopleDashboardContext: String?
    @State private var customersContext: String?
    @State private var contactsContext: String?
    @State private var officeDashboardContext: String?
    @State private var officeApprovalsContext: String?
    @State private var officeSpendingContext: String?
    @State private var reportsLaborContext: String?
    @State private var reportsSpendingContext: String?
    @State private var reportsProfitabilityContext: String?
    @State private var reportsTimesheetsContext: String?
    @State private var reportsPrebillingContext: String?
    @State private var reportsBookkeeperContext: String?
    @State private var reportsDailySummaryContext: String?
    @State private var vehiclesContext: String?
    @State private var fleetDashboardContext: String?
    @State private var fleetTrailersContext: String?
    @State private var fleetMaintenanceContext: String?
    @State private var fleetMileageContext: String?
    @State private var fleetFuelContext: String?
    @State private var fleetInspectionsContext: String?
    @State private var fleetTrackingContext: String?
    @State private var fleetTelematicsContext: String?
    @State private var fleetMyTruckContext: String?
    @State private var toolRegistryContext: String?
    @State private var notebooksListContext: String?
    @State private var settingsContext: String?

    /// Tracks which page the user is currently on, mapped to a HelpContentRegistry page ID.
    /// Updated whenever a page-active notification fires, cleared on page-inactive.
    @State private var activePageId: String?

    /// Unique ID for the current conversation thread. Changing this starts a fresh session.
    @State private var conversationId: String = UUID().uuidString

    /// Guards the one-time cross-launch resume so it only runs on the panel's first appearance.
    @State private var didAttemptResume = false

    /// Past conversations for the resume picker, loaded on demand.
    @State private var savedConversations: [SavedConversation] = []
    @State private var showConversationPicker = false
    @State private var isLoadingConversations = false
    /// Prevents a prompt from racing ahead of persisted transcript hydration.
    @State private var isLoadingConversationHistory = false
    @State private var isReadyForHelpHandoff = false
    @State private var queuedHelpRequest: [AnyHashable: Any]?
    @State private var helpPersistenceTask: Task<Void, Never>?
    @State private var conversationLoadTask: Task<Void, Never>?

    struct SavedConversation: Identifiable, Equatable {
        let id: String
        let lastMessageAt: String
        let preview: String
    }

    /// Whether the beta bug-report sheet is presented from the assistant.
    @State private var isBugReportPresented = false

    /// Human-readable name of the page the user is on, derived from
    /// `activePageId` via the help registry, for attaching to a bug report.
    private var activeModuleName: String? {
        guard let pageId = activePageId else { return nil }
        if let title = HelpContentRegistry.helpFor(pageId)?.title {
            // Titles read like "Jobs Help" — trim the trailing " Help" suffix.
            let trimmed = title.hasSuffix(" Help") ? String(title.dropLast(5)) : title
            return trimmed.isEmpty ? pageId : trimmed
        }
        return pageId
    }

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
                            presentConversationPicker()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .help("Resume a past conversation")
                        .accessibilityLabel("Resume a past conversation")

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
                        .disabled(messages.isEmpty || isProcessing || isClearingConversation)
                        .accessibilityLabel("Clear conversation")

                        Button {
                            isBugReportPresented = true
                        } label: {
                            Image(systemName: "ladybug")
                        }
                        .help("Report a bug")
                        .accessibilityLabel("Report a bug")
                    }
                }
                .sheet(isPresented: $isBugReportPresented) {
                    bugReportSheet
                }
        }
    }

    @ViewBuilder
    private var bugReportSheet: some View {
        NavigationStack {
            ReportABugPage(originModule: activeModuleName)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isBugReportPresented = false }
                    }
                }
        }
        .presentationDetents([.large])
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
        .sheet(isPresented: $isBugReportPresented) {
            bugReportSheet
        }
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
                presentConversationPicker()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .help("Resume a past conversation")
            .accessibilityLabel("Resume a past conversation")

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
            .disabled(messages.isEmpty || isProcessing || isClearingConversation)
            .accessibilityLabel("Clear conversation")

            Button {
                isBugReportPresented = true
            } label: {
                Image(systemName: "ladybug")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Report a bug")
            .accessibilityLabel("Report a bug")

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

    // MARK: - Conversation Picker

    @ViewBuilder
    private var conversationPicker: some View {
        NavigationStack {
            Group {
                if isLoadingConversations {
                    ProgressView("Loading conversations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if savedConversations.isEmpty {
                    ContentUnavailableView(
                        "No Saved Conversations",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Chats you have with the assistant will appear here so you can pick them back up later.")
                    )
                } else {
                    List(savedConversations) { conversation in
                        Button {
                            resumeConversation(conversation.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(renderedMarkdown(conversation.preview))
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                                Text(conversationTimestamp(conversation.lastMessageAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Resume conversation: \(plainText(fromMarkdown: conversation.preview))")
                    }
                }
            }
            .navigationTitle("Resume Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showConversationPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func conversationTimestamp(_ iso: String) -> String {
        guard let date = CoreFormatters.parseISO(iso) else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Shared Chat Body

    @ViewBuilder
    private var chatBody: some View {
        VStack(spacing: 0) {
            if displayMode == .sheet {
                availabilityHeader
            }
            clearConversationStatus
            messagesArea
            inputBar
        }
        .task {
            isLoadingConversationHistory = true
            aiAvailability = aiService.checkAvailability()
            await resumeLastConversationIfNeeded()
            await loadCurrentConversation()
            isReadyForHelpHandoff = true
            consumePendingHelpRequestIfReady()
        }
        .sheet(isPresented: $showConversationPicker) {
            conversationPicker
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
            jobDetailContext: $jobDetailContext,
            laborContext: $laborContext,
            dailyReportsContext: $dailyReportsContext,
            questionnaireContext: $questionnaireContext,
            estimationQuestionnaireContext: $estimationQuestionnaireContext,
            estimationReviewContext: $estimationReviewContext,
            jobReportsContext: $jobReportsContext,
            jposContext: $jposContext,
            purchaseOrdersContext: $purchaseOrdersContext,
            poDetailContext: $poDetailContext,
            receiveShipmentContext: $receiveShipmentContext,
            procurementContext: $procurementContext,
            returnsContext: $returnsContext,
            jpoCreationContext: $jpoCreationContext,
            jpoDetailContext: $jpoDetailContext,
            orderStagingContext: $orderStagingContext,
            partsOrderManagementContext: $partsOrderManagementContext,
            ordersWishlistContext: $ordersWishlistContext,
            unifiedOrderContext: $unifiedOrderContext,
            warehouseDashboardContext: $warehouseDashboardContext,
            inventoryGridContext: $inventoryGridContext,
            warehouseLocationsContext: $warehouseLocationsContext,
            warehouseMovementsContext: $warehouseMovementsContext,
            warehouseReceivingContext: $warehouseReceivingContext,
            warehouseStagingContext: $warehouseStagingContext,
            warehouseAuditContext: $warehouseAuditContext,
            warehouseReturnsContext: $warehouseReturnsContext,
            warehouseToolsContext: $warehouseToolsContext,
            warehouseNetworkContext: $warehouseNetworkContext,
            warehouseSettingsContext: $warehouseSettingsContext,
            warehouseOrganizationAuditContext: $warehouseOrganizationAuditContext,
            warehouseLeaderboardContext: $warehouseLeaderboardContext,
            dispatchContext: $dispatchContext,
            scheduleCalendarContext: $scheduleCalendarContext,
            employeesContext: $employeesContext,
            vehiclesContext: $vehiclesContext,
            toolRegistryContext: $toolRegistryContext,
            notebooksListContext: $notebooksListContext,
            settingsContext: $settingsContext
        ))
        .modifier(PeopleOfficeReportsContextObservers(
            peopleDashboardContext: $peopleDashboardContext,
            customersContext: $customersContext,
            contactsContext: $contactsContext,
            officeDashboardContext: $officeDashboardContext,
            officeApprovalsContext: $officeApprovalsContext,
            officeSpendingContext: $officeSpendingContext,
            reportsLaborContext: $reportsLaborContext,
            reportsSpendingContext: $reportsSpendingContext,
            reportsProfitabilityContext: $reportsProfitabilityContext,
            reportsTimesheetsContext: $reportsTimesheetsContext,
            reportsPrebillingContext: $reportsPrebillingContext,
            reportsBookkeeperContext: $reportsBookkeeperContext,
            reportsDailySummaryContext: $reportsDailySummaryContext
        ))
        .modifier(FleetPageContextObserversPrimary(
            fleetDashboardContext: $fleetDashboardContext,
            fleetTrailersContext: $fleetTrailersContext,
            fleetMaintenanceContext: $fleetMaintenanceContext
        ))
        .modifier(FleetPageContextObserversOps(
            fleetMileageContext: $fleetMileageContext,
            fleetFuelContext: $fleetFuelContext,
            fleetInspectionsContext: $fleetInspectionsContext
        ))
        .modifier(FleetPageContextObserversTracking(
            fleetTrackingContext: $fleetTrackingContext,
            fleetTelematicsContext: $fleetTelematicsContext,
            fleetMyTruckContext: $fleetMyTruckContext

        ))
        .modifier(ActivePageIdTracker(activePageId: $activePageId))
        .onReceive(NotificationCenter.default.publisher(for: .appDidLogout)) { _ in
            resetForLogout()
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
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder
    private var clearConversationStatus: some View {
        if isClearingConversation {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Clearing conversation history…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Clearing conversation history")
        } else if let clearConversationError {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation was not cleared")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(clearConversationError)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Retry") {
                    retryClearConversation()
                }
                .font(.caption)
                .disabled(isClearingConversation)
                .accessibilityLabel("Retry clearing conversation")
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.red.opacity(0.12))
            .accessibilityElement(children: .contain)
        } else if let conversationPersistenceError {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(conversationPersistenceError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Dismiss") {
                    self.conversationPersistenceError = nil
                }
                .font(.caption)
                .accessibilityLabel("Dismiss conversation save warning")
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.12))
            .accessibilityElement(children: .contain)
        }
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
                Text(renderedMarkdown(message.content))
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
            .accessibilityLabel("Send message")
            .disabled(
                query.isBlankRequiredText
                    || isProcessing
                    || isClearingConversation
                    || isLoadingConversationHistory
            )
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
            .disabled(isProcessing || isClearingConversation || isLoadingConversationHistory)
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
        guard !trimmed.isEmpty,
              !isClearingConversation,
              !isLoadingConversationHistory else { return }

        clearConversationError = nil
        clearConversationRetryId = nil
        messages.append(AssistantMessage(role: .user, content: trimmed))
        query = ""
        isProcessing = true

        let pendingHelpPersistence = helpPersistenceTask
        let sendConversationId = conversationId
        let sendOwnerUserId = appCore.currentUser?.id
        let sendConversationRevision = conversationRevision

        Task {
            await pendingHelpPersistence?.value

            guard conversationId == sendConversationId,
                  appCore.currentUser?.id == sendOwnerUserId,
                  conversationRevision == sendConversationRevision else { return }

            if let conversationPersistenceError {
                messages.append(AssistantMessage(role: .assistant, content: conversationPersistenceError))
                isProcessing = false
                return
            }

            let response = await generateResponse(for: trimmed)
            guard conversationId == sendConversationId,
                  appCore.currentUser?.id == sendOwnerUserId,
                  conversationRevision == sendConversationRevision else { return }
            messages.append(AssistantMessage(role: .assistant, content: response))
            isProcessing = false
        }
    }

    // MARK: - Help Handoff

    private func consumePendingHelpRequestIfReady() {
        if let pendingHelpRequest {
            queuedHelpRequest = pendingHelpRequest
            self.pendingHelpRequest = nil
        }
        guard isReadyForHelpHandoff, let request = queuedHelpRequest else { return }
        queuedHelpRequest = nil
        handleHelpHandoff(request)
    }

    /// Seeds a read-only help turn locally. No model or network response is required.
    private func handleHelpHandoff(_ userInfo: [AnyHashable: Any]) {
        guard !isClearingConversation else {
            queuedHelpRequest = userInfo
            return
        }
        let title = userInfo["title"] as? String ?? "This Page"
        let prompt = userInfo["prompt"] as? String ?? "Help me understand \(title)."
        let helpBody = userInfo["helpBody"] as? String
        let pageId = userInfo["pageId"] as? String

        if let pageId, HelpContentRegistry.helpFor(pageId) != nil {
            activePageId = pageId
        }

        query = ""
        isProcessing = false

        let response: String
        if let pageId, let entry = HelpContentRegistry.helpFor(pageId) {
            response = formattedHelpResponse(title: entry.title, sections: entry.sections)
        } else if let helpBody, !helpBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            response = "# \(title)\n\n\(helpBody)\n\nI can answer follow-up questions about these read-only help instructions."
        } else {
            response = "I opened the assistant for **\(title)**. Ask me what you want to do on this page and I'll explain the available actions."
        }

        messages.append(AssistantMessage(role: .user, content: prompt))
        messages.append(AssistantMessage(role: .assistant, content: response))
        persistHelpHandoffTurn(userPrompt: prompt, assistantResponse: response)
    }

    private func formattedHelpResponse(title: String, sections: [(String, String)]) -> String {
        var response = "# \(title)\n\n"
        for (heading, body) in sections {
            response += "## \(heading)\n\n\(body)\n\n"
        }
        response += "I can answer follow-up questions about these read-only help instructions."
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Persistence is best-effort because the locally generated help response is already visible.
    /// Tasks are chained so Clear can await one handle and know every earlier Help write settled.
    private func persistHelpHandoffTurn(userPrompt: String, assistantResponse: String) {
        guard let db = appCore.db,
              let ownerUserId = appCore.currentUser?.id,
              ownerUserId > 0 else {
            conversationPersistenceError = "This Help conversation is visible now but could not be saved because the database or signed-in user is unavailable."
            return
        }
        let currentConversationId = conversationId
        let currentConversationRevision = conversationRevision
        let currentLifecycle = AIConversationLifecycleSnapshot(
            conversationId: currentConversationId,
            ownerUserId: ownerUserId,
            revision: currentConversationRevision
        )
        let previousHelpPersistence = helpPersistenceTask
        helpPersistenceTask = Task { [db, currentConversationId, ownerUserId, currentLifecycle, userPrompt, assistantResponse] in
            await previousHelpPersistence?.value
            do {
                let staged = try await aiService.stageHelpConversation(
                    currentConversationId,
                    ownerUserId: ownerUserId,
                    userPrompt: userPrompt,
                    assistantResponse: assistantResponse,
                    in: db
                )
                guard currentLifecycle.matches(
                    conversationId: conversationId,
                    ownerUserId: appCore.currentUser?.id,
                    revision: conversationRevision,
                    isCancelled: Task.isCancelled
                ) else { return }
                conversationPersistenceError = staged
                    ? nil
                    : "This Help conversation changed while it was being saved. Start a new Help handoff before asking a follow-up."
            } catch {
                guard currentLifecycle.matches(
                    conversationId: conversationId,
                    ownerUserId: appCore.currentUser?.id,
                    revision: conversationRevision,
                    isCancelled: Task.isCancelled
                ) else { return }
                conversationPersistenceError = "This Help conversation is visible now but could not be saved: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    private func cancelHelpPersistenceTask() -> Task<Void, Never>? {
        let pendingHelpPersistence = helpPersistenceTask
        pendingHelpPersistence?.cancel()
        helpPersistenceTask = nil
        return pendingHelpPersistence
    }

    // MARK: - Conversation Lifecycle

    /// Start a brand-new conversation — clears the AI session, resets messages, generates a new ID.
    private func startNewConversation() {
        let pendingHelpPersistence = cancelHelpPersistenceTask()
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        isLoadingConversationHistory = false
        conversationRevision &+= 1
        isProcessing = false
        clearConversationError = nil
        clearConversationRetryId = nil
        conversationPersistenceError = nil
        Task { await pendingHelpPersistence?.value }
        Task { await aiService.clearConversation() }
        conversationId = UUID().uuidString
        messages = [welcomeMessage()]
    }

    /// Clear volatile assistant state when the app logs out, without deleting persisted history.
    private func resetForLogout() {
        let pendingHelpPersistence = cancelHelpPersistenceTask()
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        isLoadingConversationHistory = false
        conversationRevision &+= 1
        isProcessing = false
        clearConversationError = nil
        clearConversationRetryId = nil
        conversationPersistenceError = nil
        isClearingConversation = false
        Task { await pendingHelpPersistence?.value }
        Task { await aiService.clearConversation() }
        conversationId = UUID().uuidString
        messages.removeAll()
        savedConversations.removeAll()
        showConversationPicker = false
        didAttemptResume = false
        clearVolatilePageContext()
    }

    /// Drop all page-scoped context captured from notifications.
    ///
    /// These strings may include user-visible page data. A logout must clear every
    /// cached context before the next user can create a fresh Foundation Models
    /// session, otherwise the new session instructions could still include the
    /// previous user's page state.
    private func clearVolatilePageContext() {
        activePageId = nil
        catalogContext = nil
        pricingContext = nil
        suppliersContext = nil
        companionsContext = nil
        forecastContext = nil
        dashboardContext = nil
        jobsListContext = nil
        clockContext = nil
        jobDetailContext = nil
        laborContext = nil
        dailyReportsContext = nil
        questionnaireContext = nil
        estimationQuestionnaireContext = nil
        estimationReviewContext = nil
        jobReportsContext = nil
        jposContext = nil
        purchaseOrdersContext = nil
        poDetailContext = nil
        receiveShipmentContext = nil
        procurementContext = nil
        returnsContext = nil
        jpoCreationContext = nil
        jpoDetailContext = nil
        orderStagingContext = nil
        partsOrderManagementContext = nil
        ordersWishlistContext = nil
        unifiedOrderContext = nil
        warehouseDashboardContext = nil
        inventoryGridContext = nil
        warehouseLocationsContext = nil
        warehouseMovementsContext = nil
        warehouseReceivingContext = nil
        warehouseStagingContext = nil
        warehouseAuditContext = nil
        warehouseReturnsContext = nil
        warehouseToolsContext = nil
        warehouseNetworkContext = nil
        warehouseSettingsContext = nil
        warehouseOrganizationAuditContext = nil
        warehouseLeaderboardContext = nil
        dispatchContext = nil
        scheduleCalendarContext = nil
        employeesContext = nil
        peopleDashboardContext = nil
        customersContext = nil
        contactsContext = nil
        officeDashboardContext = nil
        officeApprovalsContext = nil
        officeSpendingContext = nil
        reportsLaborContext = nil
        reportsSpendingContext = nil
        reportsProfitabilityContext = nil
        reportsTimesheetsContext = nil
        reportsPrebillingContext = nil
        reportsBookkeeperContext = nil
        reportsDailySummaryContext = nil
        vehiclesContext = nil
        fleetDashboardContext = nil
        fleetTrailersContext = nil
        fleetMaintenanceContext = nil
        fleetMileageContext = nil
        fleetFuelContext = nil
        fleetInspectionsContext = nil
        fleetTrackingContext = nil
        fleetTelematicsContext = nil
        fleetMyTruckContext = nil
        toolRegistryContext = nil
        notebooksListContext = nil
        settingsContext = nil
    }

    /// Delete all messages from the current conversation (UI + DB) but keep the same conversation ID.
    private func clearCurrentConversation() {
        clearPersistedConversation(conversationId)
    }

    private func retryClearConversation() {
        clearPersistedConversation(clearConversationRetryId ?? conversationId)
    }

    /// Fail closed: do not clear the visible conversation until persistent deletion succeeds.
    private func clearPersistedConversation(_ cid: String) {
        guard !isClearingConversation else { return }
        guard let db = appCore.db,
              let ownerUserId = appCore.currentUser?.id,
              ownerUserId > 0 else {
            clearConversationRetryId = cid
            clearConversationError = "The database or signed-in user is unavailable. Your stored messages were not deleted; try again after signing in and the app finishes loading."
            return
        }

        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        isLoadingConversationHistory = false
        conversationRevision &+= 1
        isProcessing = false
        isClearingConversation = true
        clearConversationError = nil
        clearConversationRetryId = cid

        let pendingHelpPersistence = cancelHelpPersistenceTask()
        Task {
            do {
                await pendingHelpPersistence?.value
                try await aiService.clearConversation(cid, ownerUserId: ownerUserId, from: db)
                await MainActor.run {
                    if conversationId == cid {
                        messages = [welcomeMessage()]
                    }
                    clearConversationError = nil
                    clearConversationRetryId = nil
                    conversationPersistenceError = nil
                    isClearingConversation = false
                }
            } catch {
                await MainActor.run {
                    clearConversationRetryId = cid
                    clearConversationError = "Stored messages could not be deleted: \(error.localizedDescription)"
                    isClearingConversation = false
                }
            }
        }
    }

    private func welcomeMessage() -> AssistantMessage {
        AssistantMessage(
            role: .assistant,
            content: "How can I help you today? I can search your data, answer questions about jobs, parts, orders, and help you navigate the app."
        )
    }

    private func renderedMarkdown(_ content: String) -> AttributedString {
        var rendered = AttributedString()
        for (index, block) in markdownBlocks(content).enumerated() {
            if index > 0 {
                rendered.append(AttributedString("\n\n"))
            }
            rendered.append(
                (try? AttributedString(
                    markdown: block,
                    options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
                )) ?? AttributedString(block)
            )
        }
        return rendered
    }

    private func plainText(fromMarkdown content: String) -> String {
        markdownBlocks(content)
            .map { String(renderedMarkdown($0).characters) }
            .joined(separator: "\n\n")
    }

    private func markdownBlocks(_ content: String) -> [String] {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Own the current history load so lifecycle transitions can cancel it and the
    /// composer stays disabled until both UI rows and model context are hydrated.
    private func loadCurrentConversation() async {
        let task = beginCurrentConversationLoad()
        await task.value
    }

    @discardableResult
    private func beginCurrentConversationLoad() -> Task<Void, Never> {
        conversationLoadTask?.cancel()
        isLoadingConversationHistory = true
        let loadConversationId = conversationId
        let loadOwnerUserId = appCore.currentUser?.id
        let loadConversationRevision = conversationRevision
        let task = Task {
            await loadSavedMessages()
            guard !Task.isCancelled,
                  conversationId == loadConversationId,
                  appCore.currentUser?.id == loadOwnerUserId,
                  conversationRevision == loadConversationRevision else { return }
            isLoadingConversationHistory = false
            conversationLoadTask = nil
        }
        conversationLoadTask = task
        return task
    }

    /// Load previously saved messages for the current conversation from the DB.
    private func loadSavedMessages() async {
        guard let db = appCore.db,
              let ownerUserId = appCore.currentUser?.id,
              ownerUserId > 0 else {
            addWelcomeMessageIfNeeded()
            return
        }
        let loadConversationId = conversationId
        let loadConversationRevision = conversationRevision
        do {
            let saved = try await aiService.resumeConversation(
                loadConversationId,
                ownerUserId: ownerUserId,
                from: db
            )
            guard !Task.isCancelled,
                  conversationId == loadConversationId,
                  appCore.currentUser?.id == ownerUserId,
                  conversationRevision == loadConversationRevision else { return }
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
            guard !Task.isCancelled,
                  conversationId == loadConversationId,
                  appCore.currentUser?.id == ownerUserId,
                  conversationRevision == loadConversationRevision else { return }
            addWelcomeMessageIfNeeded()
        }
    }

    /// Adds the default welcome message if the messages list is empty.
    private func addWelcomeMessageIfNeeded() {
        if messages.isEmpty {
            messages.append(welcomeMessage())
        }
    }

    // MARK: - Conversation Resume

    private func resumeLastConversationIfNeeded() async {
        guard !didAttemptResume else { return }
        didAttemptResume = true
        guard let db = appCore.db,
              let ownerUserId = appCore.currentUser?.id,
              ownerUserId > 0 else { return }
        let lookupConversationId = conversationId
        let lookupConversationRevision = conversationRevision
        if let latest = try? await FoundationModelsService.latestConversationId(
            ownerUserId: ownerUserId,
            from: db
        ) {
            guard !Task.isCancelled,
                  conversationId == lookupConversationId,
                  appCore.currentUser?.id == ownerUserId,
                  conversationRevision == lookupConversationRevision else { return }
            conversationRevision &+= 1
            conversationId = latest
        }
    }

    private func presentConversationPicker() {
        showConversationPicker = true
        Task { await loadConversationList() }
    }

    private func loadConversationList() async {
        guard let db = appCore.db,
              let ownerUserId = appCore.currentUser?.id,
              ownerUserId > 0 else {
            savedConversations = []
            return
        }
        let listConversationRevision = conversationRevision
        let listLifecycle = AIConversationLifecycleSnapshot(
            conversationId: conversationId,
            ownerUserId: ownerUserId,
            revision: listConversationRevision
        )
        isLoadingConversations = true
        defer { isLoadingConversations = false }
        if let rows = try? await FoundationModelsService.listConversations(
            ownerUserId: ownerUserId,
            from: db
        ) {
            guard listLifecycle.matches(
                conversationId: conversationId,
                ownerUserId: appCore.currentUser?.id,
                revision: conversationRevision,
                isCancelled: Task.isCancelled
            ) else { return }
            savedConversations = rows.map {
                SavedConversation(id: $0.id, lastMessageAt: $0.lastMessageAt, preview: $0.preview)
            }
        } else {
            guard listLifecycle.matches(
                conversationId: conversationId,
                ownerUserId: appCore.currentUser?.id,
                revision: conversationRevision,
                isCancelled: Task.isCancelled
            ) else { return }
            savedConversations = []
        }
    }

    private func resumeConversation(_ id: String) {
        conversationPersistenceError = nil
        guard id != conversationId else {
            showConversationPicker = false
            return
        }
        let pendingHelpPersistence = cancelHelpPersistenceTask()
        conversationLoadTask?.cancel()
        isLoadingConversationHistory = false
        conversationRevision &+= 1
        isProcessing = false
        clearConversationError = nil
        clearConversationRetryId = nil
        Task { await pendingHelpPersistence?.value }
        conversationId = id
        messages = []
        showConversationPicker = false
        beginCurrentConversationLoad()
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
            if let ctx = jobDetailContext {
                navContext += "\n\nJob Detail Context (READ-ONLY): \(ctx)"
            }
            if let ctx = laborContext {
                navContext += "\n\nLabor Context (READ-ONLY): \(ctx)"
            }
            if let ctx = dailyReportsContext {
                navContext += "\n\nDaily Reports Context (READ-ONLY): \(ctx)"
            }
            if let ctx = questionnaireContext {
                navContext += "\n\nQuestionnaire Context (READ-ONLY): \(ctx)"
            }
            if let ctx = estimationQuestionnaireContext {
                navContext += "\n\nEstimation Questionnaire Context (READ-ONLY): \(ctx)"
            }
            if let ctx = estimationReviewContext {
                navContext += "\n\nEstimation Review Context (READ-ONLY): \(ctx)"
            }
            if let ctx = jobReportsContext {
                navContext += "\n\nJob Reports Context (READ-ONLY): \(ctx)"
            }
            if let ctx = jposContext {
                navContext += "\n\nJob Purchase Orders Context: \(ctx)"
            }
            if let ctx = purchaseOrdersContext {
                navContext += "\n\nPurchase Orders Context: \(ctx)"
            }
            if let ctx = poDetailContext {
                navContext += "\n\nPO Detail Context (READ-ONLY): \(ctx)"
            }
            if let ctx = receiveShipmentContext {
                navContext += "\n\nReceive Shipment Context (READ-ONLY): \(ctx)"
            }
            if let ctx = procurementContext {
                navContext += "\n\nProcurement Context (READ-ONLY): \(ctx)"
            }
            if let ctx = returnsContext {
                navContext += "\n\nReturns Context (READ-ONLY): \(ctx)"
            }
            if let ctx = jpoCreationContext {
                navContext += "\n\nJPO Creation Context (READ-ONLY): \(ctx)"
            }
            if let ctx = jpoDetailContext {
                navContext += "\n\nJPO Detail Context (READ-ONLY): \(ctx)"
            }
            if let ctx = orderStagingContext {
                navContext += "\n\nOrder Staging Context (READ-ONLY): \(ctx)"
            }
            if let ctx = partsOrderManagementContext {
                navContext += "\n\nParts Order Management Context (READ-ONLY): \(ctx)"
            }
            if let ctx = ordersWishlistContext {
                navContext += "\n\nOrders Wishlist Context (READ-ONLY): \(ctx)"
            }
            if let ctx = unifiedOrderContext {
                navContext += "\n\nUnified Order Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseDashboardContext {
                navContext += "\n\nWarehouse Dashboard Context (READ-ONLY): \(ctx)"
            }
            if let ctx = inventoryGridContext {
                navContext += "\n\nInventory Grid Context: \(ctx)"
            }
            if let ctx = warehouseLocationsContext {
                navContext += "\n\nWarehouse Locations Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseMovementsContext {
                navContext += "\n\nWarehouse Movements Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseReceivingContext {
                navContext += "\n\nWarehouse Receiving Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseStagingContext {
                navContext += "\n\nWarehouse Staging Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseAuditContext {
                navContext += "\n\nWarehouse Audit Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseReturnsContext {
                navContext += "\n\nWarehouse Returns Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseToolsContext {
                navContext += "\n\nWarehouse Tools Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseNetworkContext {
                navContext += "\n\nWarehouse Network Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseSettingsContext {
                navContext += "\n\nWarehouse Settings Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseOrganizationAuditContext {
                navContext += "\n\nWarehouse Organization Audit Context (READ-ONLY): \(ctx)"
            }
            if let ctx = warehouseLeaderboardContext {
                navContext += "\n\nWarehouse Leaderboard Context (READ-ONLY): \(ctx)"
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
            if let ctx = peopleDashboardContext {
                navContext += "\n\nPeople Dashboard Context (READ-ONLY): \(ctx)"
            }
            if let ctx = customersContext {
                navContext += "\n\nCustomers Context (READ-ONLY): \(ctx)"
            }
            if let ctx = contactsContext {
                navContext += "\n\nContacts Context (READ-ONLY): \(ctx)"
            }
            if let ctx = officeDashboardContext {
                navContext += "\n\nOffice Dashboard Context (READ-ONLY): \(ctx)"
            }
            if let ctx = officeApprovalsContext {
                navContext += "\n\nOffice Approvals Context (READ-ONLY): \(ctx)"
            }
            if let ctx = officeSpendingContext {
                navContext += "\n\nOffice Spending Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsLaborContext {
                navContext += "\n\nReports Labor Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsSpendingContext {
                navContext += "\n\nReports Spending Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsProfitabilityContext {
                navContext += "\n\nReports Profitability Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsTimesheetsContext {
                navContext += "\n\nReports Timesheets Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsPrebillingContext {
                navContext += "\n\nReports Pre-Billing Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsBookkeeperContext {
                navContext += "\n\nReports Bookkeeper Context (READ-ONLY): \(ctx)"
            }
            if let ctx = reportsDailySummaryContext {
                navContext += "\n\nReports Daily Summary Context (READ-ONLY): \(ctx)"
            }
            if let ctx = vehiclesContext {
                navContext += "\n\nVehicles Context: \(ctx)"
            }
            if let ctx = fleetDashboardContext {
                navContext += "\n\nFleet Dashboard Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetMaintenanceContext {
                navContext += "\n\nFleet Maintenance Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetMileageContext {
                navContext += "\n\nFleet Mileage Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetFuelContext {
                navContext += "\n\nFleet Fuel Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetTrailersContext {
                navContext += "\n\nFleet Trailers Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetInspectionsContext {
                navContext += "\n\nFleet Inspections Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetTrackingContext {
                navContext += "\n\nFleet Tracking Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetTelematicsContext {
                navContext += "\n\nFleet Telematics Context (READ-ONLY): \(ctx)"
            }
            if let ctx = fleetMyTruckContext {
                navContext += "\n\nMy Truck Context (READ-ONLY): \(ctx)"
            }
            if let ctx = officeApprovalsContext {
                navContext += "\n\nOffice Approvals Context (READ-ONLY): \(ctx)"
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
                // Fail closed: pass nil when no user session exists so user-specific
                // tools return a not-signed-in error instead of running as user 0 (#724).
                userId: appCore.currentUser?.id,
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
    @Binding var jobDetailContext: String?
    @Binding var laborContext: String?
    @Binding var dailyReportsContext: String?
    @Binding var questionnaireContext: String?
    @Binding var estimationQuestionnaireContext: String?
    @Binding var estimationReviewContext: String?
    @Binding var jobReportsContext: String?
    @Binding var jposContext: String?
    @Binding var purchaseOrdersContext: String?
    @Binding var poDetailContext: String?
    @Binding var receiveShipmentContext: String?
    @Binding var procurementContext: String?
    @Binding var returnsContext: String?
    @Binding var jpoCreationContext: String?
    @Binding var jpoDetailContext: String?
    @Binding var orderStagingContext: String?
    @Binding var partsOrderManagementContext: String?
    @Binding var ordersWishlistContext: String?
    @Binding var unifiedOrderContext: String?
    @Binding var warehouseDashboardContext: String?
    @Binding var inventoryGridContext: String?
    @Binding var warehouseLocationsContext: String?
    @Binding var warehouseMovementsContext: String?
    @Binding var warehouseReceivingContext: String?
    @Binding var warehouseStagingContext: String?
    @Binding var warehouseAuditContext: String?
    @Binding var warehouseReturnsContext: String?
    @Binding var warehouseToolsContext: String?
    @Binding var warehouseNetworkContext: String?
    @Binding var warehouseSettingsContext: String?
    @Binding var warehouseOrganizationAuditContext: String?
    @Binding var warehouseLeaderboardContext: String?
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
            .modifier(FeaturePageContextObserversJobs(
                jobDetailContext: $jobDetailContext,
                laborContext: $laborContext,
                dailyReportsContext: $dailyReportsContext,
                questionnaireContext: $questionnaireContext,
                estimationQuestionnaireContext: $estimationQuestionnaireContext,
                estimationReviewContext: $estimationReviewContext,
                jobReportsContext: $jobReportsContext
            ))
            .modifier(FeaturePageContextObserversGroupD(
                poDetailContext: $poDetailContext,
                receiveShipmentContext: $receiveShipmentContext,
                procurementContext: $procurementContext,
                returnsContext: $returnsContext,
                warehouseDashboardContext: $warehouseDashboardContext,
                warehouseLocationsContext: $warehouseLocationsContext
            ))
            .modifier(FeaturePageContextObserversGroupE(
                warehouseMovementsContext: $warehouseMovementsContext,
                warehouseReceivingContext: $warehouseReceivingContext,
                warehouseStagingContext: $warehouseStagingContext,
                warehouseAuditContext: $warehouseAuditContext,
                warehouseReturnsContext: $warehouseReturnsContext,
                warehouseToolsContext: $warehouseToolsContext,
                warehouseNetworkContext: $warehouseNetworkContext,
                warehouseSettingsContext: $warehouseSettingsContext,
                warehouseOrganizationAuditContext: $warehouseOrganizationAuditContext,
                warehouseLeaderboardContext: $warehouseLeaderboardContext
            ))
            .modifier(FeaturePageContextObserversGroupC(
                jpoCreationContext: $jpoCreationContext,
                jpoDetailContext: $jpoDetailContext,
                orderStagingContext: $orderStagingContext,
                partsOrderManagementContext: $partsOrderManagementContext,
                ordersWishlistContext: $ordersWishlistContext,
                unifiedOrderContext: $unifiedOrderContext
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

/// Jobs completion page observers.
private struct FeaturePageContextObserversJobs: ViewModifier {
    @Binding var jobDetailContext: String?
    @Binding var laborContext: String?
    @Binding var dailyReportsContext: String?
    @Binding var questionnaireContext: String?
    @Binding var estimationQuestionnaireContext: String?
    @Binding var estimationReviewContext: String?
    @Binding var jobReportsContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jobDetailPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { jobDetailContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jobDetailPageInactive)) { _ in
                jobDetailContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .laborPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { laborContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .laborPageInactive)) { _ in
                laborContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyReportsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { dailyReportsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dailyReportsPageInactive)) { _ in
                dailyReportsContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .questionnairePageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { questionnaireContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .questionnairePageInactive)) { _ in
                questionnaireContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .estimationQuestionnairePageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { estimationQuestionnaireContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .estimationQuestionnairePageInactive)) { _ in
                estimationQuestionnaireContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .estimationReviewPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { estimationReviewContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .estimationReviewPageInactive)) { _ in
                estimationReviewContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .jobReportsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { jobReportsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jobReportsPageInactive)) { _ in
                jobReportsContext = nil
            }
    }
}

/// Fourth group of feature page observers for restored orders/warehouse coverage.
private struct FeaturePageContextObserversGroupD: ViewModifier {
    @Binding var poDetailContext: String?
    @Binding var receiveShipmentContext: String?
    @Binding var procurementContext: String?
    @Binding var returnsContext: String?
    @Binding var warehouseDashboardContext: String?
    @Binding var warehouseLocationsContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .poDetailPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { poDetailContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .poDetailPageInactive)) { _ in
                poDetailContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .receiveShipmentPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { receiveShipmentContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .receiveShipmentPageInactive)) { _ in
                receiveShipmentContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .procurementPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { procurementContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .procurementPageInactive)) { _ in
                procurementContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { returnsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .returnsPageInactive)) { _ in
                returnsContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseDashboardPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseDashboardContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseDashboardPageInactive)) { _ in
                warehouseDashboardContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLocationsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseLocationsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLocationsPageInactive)) { _ in
                warehouseLocationsContext = nil
            }
    }
}

/// Fifth group of feature page observers for warehouse completion coverage.
private struct FeaturePageContextObserversGroupE: ViewModifier {
    @Binding var warehouseMovementsContext: String?
    @Binding var warehouseReceivingContext: String?
    @Binding var warehouseStagingContext: String?
    @Binding var warehouseAuditContext: String?
    @Binding var warehouseReturnsContext: String?
    @Binding var warehouseToolsContext: String?
    @Binding var warehouseNetworkContext: String?
    @Binding var warehouseSettingsContext: String?
    @Binding var warehouseOrganizationAuditContext: String?
    @Binding var warehouseLeaderboardContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .warehouseMovementsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseMovementsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseMovementsPageInactive)) { _ in
                warehouseMovementsContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReceivingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseReceivingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReceivingPageInactive)) { _ in
                warehouseReceivingContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseStagingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseStagingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseStagingPageInactive)) { _ in
                warehouseStagingContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseAuditPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseAuditContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseAuditPageInactive)) { _ in
                warehouseAuditContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReturnsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseReturnsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReturnsPageInactive)) { _ in
                warehouseReturnsContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseToolsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseToolsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseToolsPageInactive)) { _ in
                warehouseToolsContext = nil
            }
            .modifier(FeaturePageContextObserversGroupF(
                warehouseNetworkContext: $warehouseNetworkContext,
                warehouseSettingsContext: $warehouseSettingsContext,
                warehouseOrganizationAuditContext: $warehouseOrganizationAuditContext,
                warehouseLeaderboardContext: $warehouseLeaderboardContext
            ))
    }
}

private struct FeaturePageContextObserversGroupF: ViewModifier {
    @Binding var warehouseNetworkContext: String?
    @Binding var warehouseSettingsContext: String?
    @Binding var warehouseOrganizationAuditContext: String?
    @Binding var warehouseLeaderboardContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .warehouseNetworkPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseNetworkContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseNetworkPageInactive)) { _ in
                warehouseNetworkContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseSettingsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseSettingsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseSettingsPageInactive)) { _ in
                warehouseSettingsContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseOrganizationAuditPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseOrganizationAuditContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseOrganizationAuditPageInactive)) { _ in
                warehouseOrganizationAuditContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLeaderboardPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { warehouseLeaderboardContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLeaderboardPageInactive)) { _ in
                warehouseLeaderboardContext = nil
            }
    }
}

/// Third group of feature page observers for the WEI-1194 orders coverage slice.
private struct FeaturePageContextObserversGroupC: ViewModifier {
    @Binding var jpoCreationContext: String?
    @Binding var jpoDetailContext: String?
    @Binding var orderStagingContext: String?
    @Binding var partsOrderManagementContext: String?
    @Binding var ordersWishlistContext: String?
    @Binding var unifiedOrderContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jpoCreationPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { jpoCreationContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jpoCreationPageInactive)) { _ in
                jpoCreationContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .jpoDetailPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { jpoDetailContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .jpoDetailPageInactive)) { _ in
                jpoDetailContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .orderStagingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { orderStagingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .orderStagingPageInactive)) { _ in
                orderStagingContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .partsOrderManagementPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { partsOrderManagementContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .partsOrderManagementPageInactive)) { _ in
                partsOrderManagementContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .ordersWishlistPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { ordersWishlistContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ordersWishlistPageInactive)) { _ in
                ordersWishlistContext = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .unifiedOrderPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { unifiedOrderContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .unifiedOrderPageInactive)) { _ in
                unifiedOrderContext = nil
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


/// People, Office, and Reports observers kept separate from the legacy feature observer groups.
private struct PeopleOfficeReportsContextObservers: ViewModifier {
    @Binding var peopleDashboardContext: String?
    @Binding var customersContext: String?
    @Binding var contactsContext: String?
    @Binding var officeDashboardContext: String?
    @Binding var officeApprovalsContext: String?
    @Binding var officeSpendingContext: String?
    @Binding var reportsLaborContext: String?
    @Binding var reportsSpendingContext: String?
    @Binding var reportsProfitabilityContext: String?
    @Binding var reportsTimesheetsContext: String?
    @Binding var reportsPrebillingContext: String?
    @Binding var reportsBookkeeperContext: String?
    @Binding var reportsDailySummaryContext: String?

    func body(content: Content) -> some View {
        content
            .modifier(PeopleOfficeContextObservers(
                peopleDashboardContext: $peopleDashboardContext,
                customersContext: $customersContext,
                contactsContext: $contactsContext,
                officeDashboardContext: $officeDashboardContext,
                officeApprovalsContext: $officeApprovalsContext,
                officeSpendingContext: $officeSpendingContext
            ))
            .modifier(ReportsContextObservers(
                reportsLaborContext: $reportsLaborContext,
                reportsSpendingContext: $reportsSpendingContext,
                reportsProfitabilityContext: $reportsProfitabilityContext,
                reportsTimesheetsContext: $reportsTimesheetsContext,
                reportsPrebillingContext: $reportsPrebillingContext,
                reportsBookkeeperContext: $reportsBookkeeperContext,
                reportsDailySummaryContext: $reportsDailySummaryContext
            ))
    }
}

private struct PeopleOfficeContextObservers: ViewModifier {
    @Binding var peopleDashboardContext: String?
    @Binding var customersContext: String?
    @Binding var contactsContext: String?
    @Binding var officeDashboardContext: String?
    @Binding var officeApprovalsContext: String?
    @Binding var officeSpendingContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .peopleDashboardPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { peopleDashboardContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .peopleDashboardPageInactive)) { _ in peopleDashboardContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .customersPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { customersContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .customersPageInactive)) { _ in customersContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .contactsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { contactsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .contactsPageInactive)) { _ in contactsContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .officeDashboardPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { officeDashboardContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .officeDashboardPageInactive)) { _ in officeDashboardContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .officeApprovalsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { officeApprovalsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .officeApprovalsPageInactive)) { _ in officeApprovalsContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .officeSpendingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { officeSpendingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .officeSpendingPageInactive)) { _ in officeSpendingContext = nil }
    }
}

private struct ReportsContextObservers: ViewModifier {
    @Binding var reportsLaborContext: String?
    @Binding var reportsSpendingContext: String?
    @Binding var reportsProfitabilityContext: String?
    @Binding var reportsTimesheetsContext: String?
    @Binding var reportsPrebillingContext: String?
    @Binding var reportsBookkeeperContext: String?
    @Binding var reportsDailySummaryContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .reportsLaborPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsLaborContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsLaborPageInactive)) { _ in reportsLaborContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .reportsSpendingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsSpendingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsSpendingPageInactive)) { _ in reportsSpendingContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .reportsProfitabilityPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsProfitabilityContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsProfitabilityPageInactive)) { _ in reportsProfitabilityContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .reportsTimesheetsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsTimesheetsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsTimesheetsPageInactive)) { _ in reportsTimesheetsContext = nil }
            .modifier(ReportsContextObserversTail(
                reportsPrebillingContext: $reportsPrebillingContext,
                reportsBookkeeperContext: $reportsBookkeeperContext,
                reportsDailySummaryContext: $reportsDailySummaryContext
            ))
    }
}

private struct ReportsContextObserversTail: ViewModifier {
    @Binding var reportsPrebillingContext: String?
    @Binding var reportsBookkeeperContext: String?
    @Binding var reportsDailySummaryContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .reportsPrebillingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsPrebillingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsPrebillingPageInactive)) { _ in reportsPrebillingContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .reportsBookkeeperPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsBookkeeperContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsBookkeeperPageInactive)) { _ in reportsBookkeeperContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .reportsDailySummaryPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { reportsDailySummaryContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reportsDailySummaryPageInactive)) { _ in reportsDailySummaryContext = nil }
    }
}

/// Fleet page observers added for WEI-1112 coverage slices beyond Vehicles.
/// Split into smaller modifiers to keep SwiftUI type-checking bounded.
private struct FleetPageContextObserversPrimary: ViewModifier {
    @Binding var fleetDashboardContext: String?
    @Binding var fleetTrailersContext: String?
    @Binding var fleetMaintenanceContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .fleetDashboardPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetDashboardContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetDashboardPageInactive)) { _ in fleetDashboardContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTrailersPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetTrailersContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTrailersPageInactive)) { _ in fleetTrailersContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMaintenancePageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetMaintenanceContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMaintenancePageInactive)) { _ in fleetMaintenanceContext = nil }
    }
}

private struct FleetPageContextObserversOps: ViewModifier {
    @Binding var fleetMileageContext: String?
    @Binding var fleetFuelContext: String?
    @Binding var fleetInspectionsContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .fleetMileagePageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetMileageContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMileagePageInactive)) { _ in fleetMileageContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .fleetFuelPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetFuelContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetFuelPageInactive)) { _ in fleetFuelContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .fleetInspectionsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetInspectionsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetInspectionsPageInactive)) { _ in fleetInspectionsContext = nil }
    }
}

private struct FleetPageContextObserversTracking: ViewModifier {
    @Binding var fleetTrackingContext: String?
    @Binding var fleetTelematicsContext: String?
    @Binding var fleetMyTruckContext: String?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .fleetTrackingPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetTrackingContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTrackingPageInactive)) { _ in fleetTrackingContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTelematicsPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetTelematicsContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTelematicsPageInactive)) { _ in fleetTelematicsContext = nil }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMyTruckPageActive)) { notification in
                if let ctx = notification.userInfo?["context"] as? String { fleetMyTruckContext = ctx }
            }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMyTruckPageInactive)) { _ in fleetMyTruckContext = nil }
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
            .modifier(ActivePageIdTrackerPeopleOfficeReports(activePageId: $activePageId))
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
            .modifier(ActivePageIdTrackerJobsExtra(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerJobsExtra: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jobDetailPageActive)) { _ in activePageId = "jobs-detail" }
            .onReceive(NotificationCenter.default.publisher(for: .jobDetailPageInactive)) { _ in if activePageId == "jobs-detail" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .laborPageActive)) { _ in activePageId = "jobs-labor" }
            .onReceive(NotificationCenter.default.publisher(for: .laborPageInactive)) { _ in if activePageId == "jobs-labor" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .dailyReportsPageActive)) { _ in activePageId = "jobs-daily-reports" }
            .onReceive(NotificationCenter.default.publisher(for: .dailyReportsPageInactive)) { _ in if activePageId == "jobs-daily-reports" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .questionnairePageActive)) { _ in activePageId = "jobs-questionnaire" }
            .onReceive(NotificationCenter.default.publisher(for: .questionnairePageInactive)) { _ in if activePageId == "jobs-questionnaire" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .estimationQuestionnairePageActive)) { _ in activePageId = "jobs-estimation-questionnaire" }
            .onReceive(NotificationCenter.default.publisher(for: .estimationQuestionnairePageInactive)) { _ in if activePageId == "jobs-estimation-questionnaire" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .estimationReviewPageActive)) { _ in activePageId = "jobs-estimation-review" }
            .onReceive(NotificationCenter.default.publisher(for: .estimationReviewPageInactive)) { _ in if activePageId == "jobs-estimation-review" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .jobReportsPageActive)) { _ in activePageId = "jobs-reports" }
            .onReceive(NotificationCenter.default.publisher(for: .jobReportsPageInactive)) { _ in if activePageId == "jobs-reports" { activePageId = nil } }
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
            .modifier(ActivePageIdTrackerOrdersWarehouseRestored(activePageId: $activePageId))
            .modifier(ActivePageIdTrackerOrdersExtra(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerOrdersWarehouseRestored: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .poDetailPageActive)) { _ in activePageId = "orders-po-detail" }
            .onReceive(NotificationCenter.default.publisher(for: .poDetailPageInactive)) { _ in if activePageId == "orders-po-detail" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .receiveShipmentPageActive)) { _ in activePageId = "orders-receiving" }
            .onReceive(NotificationCenter.default.publisher(for: .receiveShipmentPageInactive)) { _ in if activePageId == "orders-receiving" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .procurementPageActive)) { _ in activePageId = "orders-procurement" }
            .onReceive(NotificationCenter.default.publisher(for: .procurementPageInactive)) { _ in if activePageId == "orders-procurement" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .returnsPageActive)) { _ in activePageId = "orders-returns" }
            .onReceive(NotificationCenter.default.publisher(for: .returnsPageInactive)) { _ in if activePageId == "orders-returns" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseDashboardPageActive)) { _ in activePageId = "warehouse-dashboard" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseDashboardPageInactive)) { _ in if activePageId == "warehouse-dashboard" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLocationsPageActive)) { _ in activePageId = "warehouse-locations" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLocationsPageInactive)) { _ in if activePageId == "warehouse-locations" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseMovementsPageActive)) { _ in activePageId = "warehouse-movements" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseMovementsPageInactive)) { _ in if activePageId == "warehouse-movements" { activePageId = nil } }
            .modifier(ActivePageIdTrackerWarehouseRestoredTail(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerWarehouseRestoredTail: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReceivingPageActive)) { _ in activePageId = "warehouse-receiving" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReceivingPageInactive)) { _ in if activePageId == "warehouse-receiving" { activePageId = nil } }
            .modifier(ActivePageIdTrackerWarehouseRestoredTailB(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerWarehouseRestoredTailB: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .warehouseStagingPageActive)) { _ in activePageId = "warehouse-staging" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseStagingPageInactive)) { _ in if activePageId == "warehouse-staging" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseAuditPageActive)) { _ in activePageId = "warehouse-audit" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseAuditPageInactive)) { _ in if activePageId == "warehouse-audit" { activePageId = nil } }
    }
}

private struct ActivePageIdTrackerOrdersExtra: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .jpoCreationPageActive)) { _ in activePageId = "orders-jpo-create" }
            .onReceive(NotificationCenter.default.publisher(for: .jpoCreationPageInactive)) { _ in if activePageId == "orders-jpo-create" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .jpoDetailPageActive)) { _ in activePageId = "orders-jpo-detail" }
            .onReceive(NotificationCenter.default.publisher(for: .jpoDetailPageInactive)) { _ in if activePageId == "orders-jpo-detail" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .orderStagingPageActive)) { _ in activePageId = "orders-staging" }
            .onReceive(NotificationCenter.default.publisher(for: .orderStagingPageInactive)) { _ in if activePageId == "orders-staging" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .partsOrderManagementPageActive)) { _ in activePageId = "orders-parts" }
            .onReceive(NotificationCenter.default.publisher(for: .partsOrderManagementPageInactive)) { _ in if activePageId == "orders-parts" { activePageId = nil } }
            .modifier(ActivePageIdTrackerOrdersExtraWarehouse(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerOrdersExtraWarehouse: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .ordersWishlistPageActive)) { _ in activePageId = "orders-wishlist" }
            .onReceive(NotificationCenter.default.publisher(for: .ordersWishlistPageInactive)) { _ in if activePageId == "orders-wishlist" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .unifiedOrderPageActive)) { _ in activePageId = "orders-unified" }
            .onReceive(NotificationCenter.default.publisher(for: .unifiedOrderPageInactive)) { _ in if activePageId == "orders-unified" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .inventoryGridPageActive)) { _ in activePageId = "warehouse-inventory" }
            .onReceive(NotificationCenter.default.publisher(for: .inventoryGridPageInactive)) { _ in if activePageId == "warehouse-inventory" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReturnsPageActive)) { _ in activePageId = "warehouse-returns" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseReturnsPageInactive)) { _ in if activePageId == "warehouse-returns" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseToolsPageActive)) { _ in activePageId = "warehouse-tools" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseToolsPageInactive)) { _ in if activePageId == "warehouse-tools" { activePageId = nil } }
            .modifier(ActivePageIdTrackerOrdersExtraTail(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerOrdersExtraTail: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .warehouseNetworkPageActive)) { _ in activePageId = "warehouse-network" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseNetworkPageInactive)) { _ in if activePageId == "warehouse-network" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseSettingsPageActive)) { _ in activePageId = "warehouse-settings" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseSettingsPageInactive)) { _ in if activePageId == "warehouse-settings" { activePageId = nil } }
            .modifier(ActivePageIdTrackerOrdersExtraTailB(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerOrdersExtraTailB: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .warehouseOrganizationAuditPageActive)) { _ in activePageId = "warehouse-organization" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseOrganizationAuditPageInactive)) { _ in if activePageId == "warehouse-organization" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLeaderboardPageActive)) { _ in activePageId = "warehouse-leaderboard" }
            .onReceive(NotificationCenter.default.publisher(for: .warehouseLeaderboardPageInactive)) { _ in if activePageId == "warehouse-leaderboard" { activePageId = nil } }
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
            .onReceive(NotificationCenter.default.publisher(for: .fleetDashboardPageActive)) { _ in activePageId = "fleet-dashboard" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetDashboardPageInactive)) { _ in if activePageId == "fleet-dashboard" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMaintenancePageActive)) { _ in activePageId = "fleet-maintenance" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMaintenancePageInactive)) { _ in if activePageId == "fleet-maintenance" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMileagePageActive)) { _ in activePageId = "fleet-mileage" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMileagePageInactive)) { _ in if activePageId == "fleet-mileage" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .fleetFuelPageActive)) { _ in activePageId = "fleet-fuel" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetFuelPageInactive)) { _ in if activePageId == "fleet-fuel" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTrailersPageActive)) { _ in activePageId = "fleet-trailers" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTrailersPageInactive)) { _ in if activePageId == "fleet-trailers" { activePageId = nil } }
            .modifier(ActivePageIdTrackerFleetToolsNotebooksFleetTail(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerFleetToolsNotebooksFleetTail: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .fleetInspectionsPageActive)) { _ in activePageId = "fleet-inspections" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetInspectionsPageInactive)) { _ in if activePageId == "fleet-inspections" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTelematicsPageActive)) { _ in activePageId = "fleet-tracking" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetTelematicsPageInactive)) { _ in if activePageId == "fleet-tracking" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMyTruckPageActive)) { _ in activePageId = "fleet-my-truck" }
            .onReceive(NotificationCenter.default.publisher(for: .fleetMyTruckPageInactive)) { _ in if activePageId == "fleet-my-truck" { activePageId = nil } }
            .modifier(ActivePageIdTrackerFleetToolsNotebooksTail(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerFleetToolsNotebooksTail: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toolRegistryPageActive)) { _ in activePageId = "tools-registry" }
            .onReceive(NotificationCenter.default.publisher(for: .toolRegistryPageInactive)) { _ in if activePageId == "tools-registry" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .notebooksListPageActive)) { _ in activePageId = "notebooks-all" }
            .onReceive(NotificationCenter.default.publisher(for: .notebooksListPageInactive)) { _ in if activePageId == "notebooks-all" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageActive)) { _ in activePageId = "settings-app-config" }
            .onReceive(NotificationCenter.default.publisher(for: .settingsPageInactive)) { _ in if activePageId == "settings-app-config" { activePageId = nil } }
    }
}

private struct ActivePageIdTrackerPeopleOfficeReports: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .peopleDashboardPageActive)) { _ in activePageId = "people-dashboard" }
            .onReceive(NotificationCenter.default.publisher(for: .peopleDashboardPageInactive)) { _ in if activePageId == "people-dashboard" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .customersPageActive)) { _ in activePageId = "people-customers" }
            .onReceive(NotificationCenter.default.publisher(for: .customersPageInactive)) { _ in if activePageId == "people-customers" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .contactsPageActive)) { _ in activePageId = "people-contacts" }
            .onReceive(NotificationCenter.default.publisher(for: .contactsPageInactive)) { _ in if activePageId == "people-contacts" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .officeDashboardPageActive)) { _ in activePageId = "office-dashboard" }
            .onReceive(NotificationCenter.default.publisher(for: .officeDashboardPageInactive)) { _ in if activePageId == "office-dashboard" { activePageId = nil } }
            .modifier(ActivePageIdTrackerOfficeReports(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerOfficeReports: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .officeApprovalsPageActive)) { _ in activePageId = "office-approvals" }
            .onReceive(NotificationCenter.default.publisher(for: .officeApprovalsPageInactive)) { _ in if activePageId == "office-approvals" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .officeSpendingPageActive)) { _ in activePageId = "office-spending" }
            .onReceive(NotificationCenter.default.publisher(for: .officeSpendingPageInactive)) { _ in if activePageId == "office-spending" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .reportsLaborPageActive)) { _ in activePageId = "reports-labor" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsLaborPageInactive)) { _ in if activePageId == "reports-labor" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .reportsSpendingPageActive)) { _ in activePageId = "reports-spending" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsSpendingPageInactive)) { _ in if activePageId == "reports-spending" { activePageId = nil } }
            .modifier(ActivePageIdTrackerReportsTail(activePageId: $activePageId))
    }
}

private struct ActivePageIdTrackerReportsTail: ViewModifier {
    @Binding var activePageId: String?
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .reportsProfitabilityPageActive)) { _ in activePageId = "reports-profitability" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsProfitabilityPageInactive)) { _ in if activePageId == "reports-profitability" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .reportsTimesheetsPageActive)) { _ in activePageId = "reports-timesheets" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsTimesheetsPageInactive)) { _ in if activePageId == "reports-timesheets" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .reportsPrebillingPageActive)) { _ in activePageId = "reports-prebilling" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsPrebillingPageInactive)) { _ in if activePageId == "reports-prebilling" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .reportsBookkeeperPageActive)) { _ in activePageId = "reports-bookkeeper" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsBookkeeperPageInactive)) { _ in if activePageId == "reports-bookkeeper" { activePageId = nil } }
            .onReceive(NotificationCenter.default.publisher(for: .reportsDailySummaryPageActive)) { _ in activePageId = "reports-daily-summary" }
            .onReceive(NotificationCenter.default.publisher(for: .reportsDailySummaryPageInactive)) { _ in if activePageId == "reports-daily-summary" { activePageId = nil } }
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

struct AIConversationLifecycleSnapshot: Equatable, Sendable {
    let conversationId: String
    let ownerUserId: Int64
    let revision: UInt

    func matches(
        conversationId currentConversationId: String,
        ownerUserId currentOwnerUserId: Int64?,
        revision currentRevision: UInt,
        isCancelled: Bool = false
    ) -> Bool {
        !isCancelled
            && conversationId == currentConversationId
            && ownerUserId == currentOwnerUserId
            && revision == currentRevision
    }
}

#if DEBUG
@MainActor
final class AIHelpAsyncLifecycleRegressionHarness {
    private(set) var conversationId: String
    private(set) var ownerUserId: Int64?
    private(set) var conversationRevision: UInt
    private(set) var conversationPersistenceError: String?
    private(set) var messages: [AssistantMessage]
    private(set) var savedConversations: [IOSAIAssistantPanel.SavedConversation]
    private(set) var isLoadingConversations = false

    init(
        conversationId: String = "conversation-a",
        ownerUserId: Int64? = 1,
        conversationRevision: UInt = 0,
        messages: [AssistantMessage] = []
    ) {
        self.conversationId = conversationId
        self.ownerUserId = ownerUserId
        self.conversationRevision = conversationRevision
        self.messages = messages
        self.savedConversations = []
    }

    func beginHelpCompletion() -> AIConversationLifecycleSnapshot {
        AIConversationLifecycleSnapshot(
            conversationId: conversationId,
            ownerUserId: ownerUserId ?? -1,
            revision: conversationRevision
        )
    }

    func completeHelp(
        snapshot: AIConversationLifecycleSnapshot,
        staged: Bool,
        error: String? = nil,
        isCancelled: Bool = false
    ) {
        guard snapshot.matches(
            conversationId: conversationId,
            ownerUserId: ownerUserId,
            revision: conversationRevision,
            isCancelled: isCancelled
        ) else { return }
        if let error {
            conversationPersistenceError = error
        } else {
            conversationPersistenceError = staged
                ? nil
                : "This Help conversation changed while it was being saved. Start a new Help handoff before asking a follow-up."
        }
    }

    func transitionToNewConversation(_ newConversationId: String) {
        conversationRevision &+= 1
        conversationId = newConversationId
        conversationPersistenceError = nil
        messages = []
    }

    func resumeConversation(_ resumedConversationId: String) {
        conversationRevision &+= 1
        conversationId = resumedConversationId
        conversationPersistenceError = nil
        messages = []
    }

    func logout(newConversationId: String = "post-logout") {
        conversationRevision &+= 1
        conversationId = newConversationId
        ownerUserId = nil
        conversationPersistenceError = nil
        messages = []
        savedConversations = []
    }

    func clearCurrentConversation() {
        conversationRevision &+= 1
        conversationPersistenceError = nil
        messages = []
    }

    func sendInCurrentConversation(_ text: String = "Conversation B question") {
        messages.append(AssistantMessage(role: .user, content: text))
        if let conversationPersistenceError {
            messages.append(AssistantMessage(role: .assistant, content: conversationPersistenceError))
        } else {
            messages.append(AssistantMessage(role: .assistant, content: "Generated response for \(conversationId)"))
        }
    }

    func beginConversationListLoad() -> AIConversationLifecycleSnapshot {
        isLoadingConversations = true
        return AIConversationLifecycleSnapshot(
            conversationId: conversationId,
            ownerUserId: ownerUserId ?? -1,
            revision: conversationRevision
        )
    }

    func finishConversationListLoad(
        snapshot: AIConversationLifecycleSnapshot,
        rows: [IOSAIAssistantPanel.SavedConversation],
        isCancelled: Bool = false
    ) {
        defer { isLoadingConversations = false }
        guard snapshot.matches(
            conversationId: conversationId,
            ownerUserId: ownerUserId,
            revision: conversationRevision,
            isCancelled: isCancelled
        ) else { return }
        savedConversations = rows
    }
}
#endif

