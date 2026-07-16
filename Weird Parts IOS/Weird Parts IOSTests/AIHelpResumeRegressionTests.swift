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

        XCTAssertTrue(assistant.contains("FoundationModelsService.latestConversationId(from: db)"))
        XCTAssertTrue(assistant.contains("FoundationModelsService.listConversations(from: db)"))
        XCTAssertTrue(assistant.contains("guard let db = appCore.db else"))
        XCTAssertTrue(assistant.contains("savedConversations = []"))
        XCTAssertTrue(assistant.contains("No Saved Conversations"))
        XCTAssertTrue(assistant.contains("Loading conversations…"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Resume a past conversation\")"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Resume conversation: \\(conversation.preview)\")"))
        XCTAssertTrue(assistant.contains("await resumeLastConversationIfNeeded()"))
        XCTAssertTrue(assistant.contains(".frame(minWidth: 44, minHeight: 44)"))
    }

    func testHelpHandoffWaitsForInitialHistoryAndClearWaitsForPersistence() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let mainView = try Self.readSource("Navigation/IOSMainView.swift")

        XCTAssertTrue(assistant.contains("await loadSavedMessages()\n            isReadyForHelpHandoff = true"))
        XCTAssertTrue(assistant.contains("consumePendingHelpRequestIfReady()"))
        XCTAssertFalse(mainView.contains("Task.sleep(for: .milliseconds(500))"))
        XCTAssertTrue(assistant.contains("let pendingHelpPersistence = helpPersistenceTask"))
        XCTAssertTrue(assistant.contains("await pendingHelpPersistence?.value"))
        XCTAssertFalse(assistant.contains("Task.detached { [db, currentConversationId, userPrompt, assistantResponse]"))
    }

    func testAssistantMessagesAndHistoryPreviewsRenderMarkdown() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")

        XCTAssertTrue(assistant.contains("Text(renderedMarkdown(message.content))"))
        XCTAssertTrue(assistant.contains("Text(renderedMarkdown(conversation.preview))"))
        XCTAssertTrue(assistant.contains("AttributedString(markdown: content)"))
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
