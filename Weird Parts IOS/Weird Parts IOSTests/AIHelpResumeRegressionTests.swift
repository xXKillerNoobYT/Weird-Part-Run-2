import XCTest

/// Regression coverage for GitHub #1459 / WEI-4986: Help can seed a local,
/// read-only assistant turn and users can safely resume persisted conversations.
final class AIHelpResumeRegressionTests: XCTestCase {
    func testHelpHandoffUsesStableNotificationAndOwnedPayload() throws {
        let navigation = try Self.readSource("Navigation/NavigationConfig.swift")
        let helpSheet = try Self.readSource("Shared/PageHelpSheet.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(navigation.contains("WiredPart.askAIAboutHelp"))
        XCTAssertFalse(navigation.contains("WiredPart.seedAIHelpRequest"))
        XCTAssertTrue(
            helpSheet.contains("name: .askAIAboutHelp")
                && helpSheet.contains("\"requestID\": UUID().uuidString")
                && helpSheet.contains("\"title\": title")
                && helpSheet.contains("\"prompt\": prompt")
                && helpSheet.contains("\"helpBody\": helpBody"),
            "The Help action must forward the visible read-only help content."
        )
        XCTAssertTrue(helpSheet.contains(".onDisappear"))
        XCTAssertTrue(helpSheet.contains("pendingAIHelpRequest = userInfo"))
        XCTAssertTrue(
            mainView.contains("publisher(for: .askAIAboutHelp)")
                && mainView.contains("pendingHelpRequest: $pendingAIHelpRequest"),
            "The shell must present the assistant with an owned pending Help payload."
        )
    }

    func testHelpAffordanceIsVisibleTouchFriendlyAndAccessible() throws {
        let helpSheet = try Self.readSource("Shared/PageHelpSheet.swift")

        XCTAssertTrue(helpSheet.contains("Label(\"Ask AI about this page\", systemImage: \"sparkles\")"))
        XCTAssertTrue(helpSheet.contains("minHeight: 44"))
        XCTAssertTrue(helpSheet.contains("accessibilityLabel(\"Ask AI about this help page\")"))
        XCTAssertTrue(helpSheet.contains("accessibilityIdentifier(\"askAIAboutHelpButton\")"))
        XCTAssertTrue(helpSheet.contains("HelpContentRegistry.pageId(matchingTitle: title)"))
    }

    func testHelpHandoffSeedsLocalResponseWithoutModelCall() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let handoff = try TestSourceSlicer.braceBalancedBody(
            after: "private func handleHelpHandoff(_ userInfo: [AnyHashable: Any])",
            in: assistant
        )

        XCTAssertTrue(handoff.contains("formattedHelpResponse"))
        XCTAssertTrue(handoff.contains("messages.append(AssistantMessage(role: .user"))
        XCTAssertTrue(handoff.contains("messages.append(AssistantMessage(role: .assistant"))
        XCTAssertTrue(handoff.contains("helpBody"), "Unregistered Help sheets need a visible-content fallback.")
        XCTAssertFalse(handoff.contains("generateResponse"), "Help handoff must not require a model response.")
        XCTAssertFalse(handoff.contains("chatWithTools"), "Help handoff must remain local and read-only.")
    }

    func testResumeControlsUseExistingPersistenceHelpersAndSafeEmptyState() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("FoundationModelsService.latestConversationId(\n            ownerUserId: ownerUserId"))
        XCTAssertTrue(assistant.contains("FoundationModelsService.listConversations(\n            ownerUserId: ownerUserId"))
        XCTAssertTrue(assistant.contains("let ownerUserId = appCore.currentUser?.id"))
        XCTAssertTrue(assistant.contains("savedConversations = []"))
        XCTAssertTrue(assistant.contains("No Saved Conversations"))
        XCTAssertTrue(assistant.contains("Loading conversations…"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Resume a past conversation\")"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Resume conversation: \\(plainText(fromMarkdown: conversation.preview))\")"))
        XCTAssertTrue(assistant.contains("await resumeLastConversationIfNeeded()"))
        XCTAssertTrue(assistant.contains(".task(id: resumePrerequisiteToken)"))
        XCTAssertTrue(assistant.contains(".frame(width: 44, height: 44)\n                        .contentShape(Rectangle())"))
        XCTAssertTrue(assistant.contains(".frame(width: 44, height: 44)\n            .contentShape(Rectangle())"))
    }

    func testResumeAttemptWaitsForDatabaseAndAuthenticatedUser() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeLastConversationIfNeeded() async",
            in: assistant
        )

        guard let prerequisiteIndex = resume.range(of: "guard let db = appCore.db")?.lowerBound,
              let attemptedIndex = resume.range(of: "didAttemptResume = true")?.lowerBound else {
            XCTFail("Automatic resume must guard its prerequisites and record the attempt.")
            return
        }
        XCTAssertLessThan(prerequisiteIndex, attemptedIndex)
        XCTAssertTrue(assistant.contains("private var resumePrerequisiteToken: ResumePrerequisiteToken"))
        XCTAssertTrue(assistant.contains("ownerUserId: appCore.currentUser?.id"))
        XCTAssertTrue(assistant.contains("isDatabaseReady: appCore.db != nil"))
    }

    func testHelpObservationUsesDedicatedConstantSizeRequestIdentity() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let token = try TestSourceSlicer.braceBalancedBody(
            after: "private var pendingHelpRequestToken: String?",
            in: assistant
        )

        XCTAssertTrue(token.contains("pendingHelpRequest?[\"requestID\"] as? String"))
        XCTAssertFalse(token.contains("helpBody"))
        XCTAssertFalse(token.contains("joined"))
    }

    func testHelpHandoffWaitsForInitialHistoryAndClearWaitsForPersistence() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(assistant.contains("await loadCurrentConversation()\n            isReadyForHelpHandoff = true"))
        XCTAssertTrue(assistant.contains("consumePendingHelpRequestIfReady()"))
        XCTAssertTrue(assistant.contains("pendingHelpRequestToken"))
        XCTAssertTrue(
            assistant.contains(".onChange(of: pendingHelpRequestToken)"),
            "The mounted assistant must observe a second Help payload after the initial task has already run."
        )
        XCTAssertFalse(mainView.contains("Task.sleep"), "Help presentation must follow dismissal state, not a timer.")
        XCTAssertTrue(assistant.contains("let pendingHelpPersistence = helpPersistenceTask"))
        XCTAssertTrue(assistant.contains("await pendingHelpPersistence?.value"))
        XCTAssertTrue(assistant.contains("try await aiService.clearConversation(cid, ownerUserId: ownerUserId, from: db)"))
        XCTAssertTrue(assistant.contains("aiService.stageHelpConversation("))
        XCTAssertTrue(assistant.contains("ownerUserId: ownerUserId"))
        XCTAssertTrue(assistant.contains("conversationPersistenceError = \"This Help conversation is visible now but could not be saved"))
        XCTAssertFalse(assistant.contains("try? await FoundationModelsService.saveMessages"))
        XCTAssertFalse(assistant.contains("Task.detached { [db, currentConversationId, userPrompt, assistantResponse]"))
    }

    func testImmediateFollowUpWaitsForCompletedHelpStaging() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )

        XCTAssertTrue(sendQuery.contains("let pendingHelpPersistence = helpPersistenceTask"))
        XCTAssertTrue(sendQuery.contains("let sendConversationId = conversationId"))
        XCTAssertTrue(sendQuery.contains("let sendOwnerUserId = appCore.currentUser?.id"))
        XCTAssertTrue(sendQuery.contains("await pendingHelpPersistence?.value"))
        XCTAssertTrue(sendQuery.contains("conversationId == sendConversationId"))
        XCTAssertTrue(sendQuery.contains("appCore.currentUser?.id == sendOwnerUserId"))
        XCTAssertTrue(sendQuery.contains("if let conversationPersistenceError"))
        guard let waitIndex = sendQuery.range(of: "await pendingHelpPersistence?.value")?.lowerBound,
              let generationIndex = sendQuery.range(of: "let response = await generateResponse")?.lowerBound else {
            XCTFail("sendQuery must contain both the Help-staging wait and response generation.")
            return
        }
        XCTAssertLessThan(waitIndex, generationIndex, "Follow-up generation must be ordered after completed Help staging.")
    }

    func testHelpPersistenceErrorCannotBleedAcrossLifecycleChanges() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let persist = try TestSourceSlicer.braceBalancedBody(
            after: "private func persistHelpHandoffTurn(userPrompt: String, assistantResponse: String)",
            in: assistant
        )
        let cancel = try TestSourceSlicer.braceBalancedBody(
            after: "private func cancelHelpPersistenceTask() -> Task<Void, Never>?",
            in: assistant
        )

        XCTAssertTrue(persist.contains("let currentConversationId = conversationId"))
        XCTAssertTrue(persist.contains("let currentConversationRevision = conversationRevision"))
        XCTAssertTrue(persist.contains("let currentLifecycle = AIConversationLifecycleSnapshot"))
        XCTAssertTrue(persist.contains("currentLifecycleCoordinator()"))
        XCTAssertEqual(
            persist.components(separatedBy: "lifecycleCoordinator.finishHelpPersistence(").count - 1,
            2,
            "Help persistence must guard both success and failure writes through the production lifecycle coordinator seam."
        )
        XCTAssertFalse(assistant.contains("AIHelpAsyncLifecycleRegressionHarness"))
        XCTAssertTrue(assistant.contains("AIAssistantLifecycleCoordinator"))
        XCTAssertTrue(cancel.contains("pendingHelpPersistence?.cancel()"))
        XCTAssertTrue(cancel.contains("helpPersistenceTask = nil"))

        for lifecycleFunction in [
            "private func startNewConversation()",
            "private func resetForLogout()",
            "private func clearPersistedConversation(_ cid: String)",
            "private func resumeConversation(_ id: String)",
        ] {
            let body = try TestSourceSlicer.braceBalancedBody(after: lifecycleFunction, in: assistant)
            XCTAssertTrue(body.contains("cancelHelpPersistenceTask()"), "\(lifecycleFunction) must cancel and take ownership of stale Help persistence.")
        }

        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeConversation(_ id: String)",
            in: assistant
        )
        XCTAssertTrue(resume.contains("conversationPersistenceError = nil"))
    }

    func testConversationPickerLoadingFlagClearsOnStaleListReturn() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let list = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadConversationList(requestID: UInt) async",
            in: assistant
        )

        XCTAssertTrue(list.contains("defer {"))
        XCTAssertTrue(list.contains("if conversationListRequestID == requestID"))
        XCTAssertTrue(list.contains("isLoadingConversations = lifecycleCoordinator.isLoadingConversations"))
        XCTAssertTrue(list.contains("conversationListRequestID == requestID"))
        XCTAssertTrue(list.contains("lifecycleCoordinator.finishConversationListLoad"))
        XCTAssertTrue(assistant.contains("@State private var conversationListTask: Task<Void, Never>?"))
    }

    func testClearInvalidatesPendingFollowUpBeforeDeletion() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )
        let clear = try TestSourceSlicer.braceBalancedBody(
            after: "private func clearPersistedConversation(_ cid: String)",
            in: assistant
        )

        XCTAssertTrue(
            assistant.contains(".disabled(messages.isEmpty || isProcessing || isClearingConversation)"),
            "Clear must not remain user-actionable while a response task is pending."
        )
        XCTAssertTrue(sendQuery.contains("let sendConversationRevision = conversationRevision"))
        XCTAssertEqual(
            sendQuery.components(separatedBy: "conversationRevision == sendConversationRevision").count - 1,
            2,
            "Send must reject an invalidated task before generation and before appending its response."
        )
        guard let invalidateIndex = clear.range(of: "conversationRevision &+= 1")?.lowerBound,
              let waitIndex = clear.range(of: "await pendingHelpPersistence?.value")?.lowerBound,
              let deleteIndex = clear.range(of: "try await aiService.clearConversation")?.lowerBound else {
            XCTFail("Clear must synchronously invalidate pending sends before awaiting Help staging or deletion.")
            return
        }
        XCTAssertLessThan(invalidateIndex, waitIndex)
        XCTAssertLessThan(invalidateIndex, deleteIndex)
    }

    func testConversationLoadsAreCancelledAndGenerationCheckedAcrossLifecycleChanges() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let load = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadSavedMessages() async",
            in: assistant
        )
        let latest = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeLastConversationIfNeeded() async",
            in: assistant
        )
        let list = try TestSourceSlicer.braceBalancedBody(
            after: "private func loadConversationList(requestID: UInt) async",
            in: assistant
        )

        XCTAssertTrue(assistant.contains("@State private var conversationLoadTask: Task<Void, Never>?"))
        XCTAssertTrue(load.contains("let loadConversationId = conversationId"))
        XCTAssertTrue(load.contains("let loadConversationRevision = conversationRevision"))
        XCTAssertTrue(load.contains("!Task.isCancelled"))
        XCTAssertTrue(load.contains("conversationId == loadConversationId"))
        XCTAssertTrue(load.contains("appCore.currentUser?.id == ownerUserId"))
        XCTAssertTrue(load.contains("conversationRevision == loadConversationRevision"))
        XCTAssertTrue(latest.contains("let lookupConversationRevision = conversationRevision"))
        XCTAssertTrue(latest.contains("conversationRevision == lookupConversationRevision"))
        XCTAssertTrue(latest.contains("conversationRevision &+= 1"))
        XCTAssertTrue(list.contains("let listLifecycle = lifecycleCoordinator.beginConversationListLoad(requestID: requestID)"))
        XCTAssertTrue(list.contains("lifecycleCoordinator.finishConversationListLoad("))
        XCTAssertTrue(list.contains("requestID: requestID"))
        XCTAssertTrue(assistant.contains("savedConversations.removeAll()"))

        for lifecycleFunction in [
            "private func startNewConversation()",
            "private func resetForLogout()",
            "private func clearPersistedConversation(_ cid: String)",
            "private func resumeConversation(_ id: String)",
        ] {
            let body = try TestSourceSlicer.braceBalancedBody(after: lifecycleFunction, in: assistant)
            XCTAssertTrue(body.contains("conversationLoadTask?.cancel()"), "\(lifecycleFunction) must cancel stale history hydration.")
        }
    }

    func testComposerWaitsForConversationHydrationBeforeSending() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let sendQuery = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )
        let beginLoad = try TestSourceSlicer.braceBalancedBody(
            after: "private func beginCurrentConversationLoad()",
            in: assistant
        )
        let resume = try TestSourceSlicer.braceBalancedBody(
            after: "private func resumeConversation(_ id: String)",
            in: assistant
        )

        XCTAssertTrue(assistant.contains("@State private var isLoadingConversationHistory = false"))
        XCTAssertTrue(assistant.contains(".task {\n            isLoadingConversationHistory = true"))
        XCTAssertTrue(sendQuery.contains("!isLoadingConversationHistory"))
        XCTAssertTrue(
            assistant.contains(".disabled(isProcessing || isClearingConversation || isLoadingConversationHistory)"),
            "The editor must stay disabled while persisted history hydrates."
        )
        XCTAssertTrue(
            assistant.contains("|| isLoadingConversationHistory\n            )"),
            "The Send control must stay disabled while persisted history hydrates."
        )
        XCTAssertTrue(beginLoad.contains("isLoadingConversationHistory = true"))
        XCTAssertTrue(beginLoad.contains("await loadSavedMessages()"))
        XCTAssertTrue(beginLoad.contains("conversationRevision == loadConversationRevision"))
        XCTAssertTrue(beginLoad.contains("isLoadingConversationHistory = false"))
        XCTAssertTrue(resume.contains("beginCurrentConversationLoad()"))
    }

    func testAssistantMessagesAndHistoryPreviewsRenderMarkdown() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("Text(renderedMarkdown(message.content))"))
        XCTAssertTrue(assistant.contains("Text(renderedMarkdown(conversation.preview))"))
        XCTAssertTrue(assistant.contains("markdown: block"))
        XCTAssertTrue(assistant.contains("interpretedSyntax: .full"))
        XCTAssertTrue(assistant.contains("markdownBlocks(content)"))
        XCTAssertTrue(assistant.contains(".joined(separator: \"\\n\\n\")"))
    }

    func testExistingAssistantBugReportContextRemainsAvailable() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("isBugReportPresented"))
        XCTAssertTrue(assistant.contains("ReportABugPage(originModule: activeModuleName)"))
        XCTAssertTrue(assistant.contains("HelpContentRegistry.helpFor(pageId)"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Report a bug\")"))
    }

    private static func readSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let projectRoot = testFileURL
            .deletingLastPathComponent() // Weird Parts IOSTests
            .deletingLastPathComponent() // Weird Parts IOS
        let sourceURL = projectRoot
            .appendingPathComponent("Weird Parts IOS")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
