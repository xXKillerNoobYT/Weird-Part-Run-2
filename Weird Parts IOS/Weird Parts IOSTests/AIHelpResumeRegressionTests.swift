import XCTest

/// Regression coverage for GitHub #1459 / WEI-4986: Help can seed a local,
/// read-only assistant turn and users can safely resume persisted conversations.
final class AIHelpResumeRegressionTests: XCTestCase {
    func testHelpHandoffUsesStableNotificationNamesAndPayload() throws {
        let navigation = try Self.readSource("Navigation/NavigationConfig.swift")
        let helpSheet = try Self.readSource("Shared/PageHelpSheet.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(navigation.contains("WiredPart.askAIAboutHelp"))
        XCTAssertTrue(navigation.contains("WiredPart.seedAIHelpRequest"))
        XCTAssertTrue(
            helpSheet.contains("name: .askAIAboutHelp")
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
        XCTAssertTrue(assistant.contains(".frame(width: 44, height: 44)\n                        .contentShape(Rectangle())"))
        XCTAssertTrue(assistant.contains(".frame(width: 44, height: 44)\n            .contentShape(Rectangle())"))
    }

    func testHelpHandoffWaitsForInitialHistoryAndClearWaitsForPersistence() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(assistant.contains("await loadSavedMessages()\n            isReadyForHelpHandoff = true"))
        XCTAssertTrue(assistant.contains("consumePendingHelpRequestIfReady()"))
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
