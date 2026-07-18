import XCTest
@testable import Weird_Parts

/// Regression coverage for GitHub #1467 / WEI-5214: every visible local fallback
/// turn is owner-scoped, persisted for Resume, and exposes a recoverable save error.
final class AIFallbackPersistenceRegressionTests: XCTestCase {
    func testUnavailableModelFallbackIsMarkedForLocalPersistence() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let generate = try TestSourceSlicer.braceBalancedBody(
            after: "private func generateResponse(for queryText: String) async -> GeneratedResponse",
            in: assistant
        )
        let send = try TestSourceSlicer.braceBalancedBody(
            after: "private func sendQuery()",
            in: assistant
        )

        XCTAssertTrue(generate.contains("if aiAvailability == .available, let db = appCore.db"))
        XCTAssertTrue(generate.contains("return .fallback(generateFallbackResponse(for: queryText))"))
        XCTAssertTrue(send.contains("if response.needsLocalPersistence"))
        XCTAssertTrue(send.contains("await persistFallbackTurn(pendingSave)"))
        XCTAssertTrue(send.contains("conversationId: sendConversationId"))
        XCTAssertTrue(send.contains("ownerUserId: sendOwnerUserId"))
    }

    func testAvailableModelFailureFallsThroughToPersistedFallback() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let generate = try TestSourceSlicer.braceBalancedBody(
            after: "private func generateResponse(for queryText: String) async -> GeneratedResponse",
            in: assistant
        )

        guard let modelCall = generate.range(of: "let result = await aiService.chatWithTools(")?.lowerBound,
              let successGate = generate.range(of: "if result.success, let text = result.text, !text.isEmpty")?.lowerBound,
              let persistedReturn = generate.range(of: "return .persisted(cleanFilterJSON(text))")?.lowerBound,
              let fallbackReturn = generate.range(of: "return .fallback(generateFallbackResponse(for: queryText))")?.lowerBound else {
            XCTFail("Generation must distinguish the persisted model-success path from local fallback.")
            return
        }
        XCTAssertLessThan(modelCall, successGate)
        XCTAssertLessThan(successGate, persistedReturn)
        XCTAssertLessThan(persistedReturn, fallbackReturn)
        XCTAssertEqual(
            generate.components(separatedBy: "return .persisted").count - 1,
            1,
            "Only a confirmed model success may claim that the pair was already persisted."
        )
    }

    func testFallbackPersistenceUsesAtomicOwnerScopedServiceAndRecoverableWarning() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let persist = try TestSourceSlicer.braceBalancedBody(
            after: "private func persistFallbackTurn(_ pendingSave: PendingFallbackSave) async",
            in: assistant
        )

        XCTAssertTrue(persist.contains("let ownerUserId = appCore.currentUser?.id"))
        XCTAssertTrue(persist.contains("pendingSave.conversationId == conversationId"))
        XCTAssertTrue(persist.contains("pendingSave.conversationRevision == conversationRevision"))
        XCTAssertTrue(persist.contains("aiService.stageLocalConversation("))
        XCTAssertTrue(persist.contains("ownerUserId: ownerUserId"))
        XCTAssertTrue(persist.contains("AIFallbackPersistenceRetryDecision.resolve("))
        XCTAssertTrue(persist.contains("case .saved:"))
        XCTAssertTrue(persist.contains("Tap Retry Save"))
        XCTAssertTrue(assistant.contains("Button(\"Retry Save\")"))
        XCTAssertTrue(assistant.contains("frame(minHeight: 44)"))
        XCTAssertTrue(assistant.contains("accessibilityLabel(\"Retry saving conversation turn\")"))
        XCTAssertTrue(assistant.contains("|| pendingFallbackSave != nil"))
    }

    func testLifecycleChangesDiscardStaleFallbackRetryPayload() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        for lifecycleFunction in [
            "private func startNewConversation()",
            "private func resetForLogout()",
            "private func clearPersistedConversation(_ cid: String)",
            "private func resumeConversation(_ id: String)",
        ] {
            let body = try TestSourceSlicer.braceBalancedBody(after: lifecycleFunction, in: assistant)
            XCTAssertTrue(
                body.contains("pendingFallbackSave = nil"),
                "\(lifecycleFunction) must not let an old fallback pair save into a new lifecycle."
            )
        }
    }

    func testFallbackWarningActionsCannotDismissAnInFlightRetry() throws {
        let assistant = try Self.readSource("AI/IOSAIAssistantPanel.swift")
        let status = try TestSourceSlicer.braceBalancedBody(
            after: "private var clearConversationStatus: some View",
            in: assistant
        )
        guard assistant.contains("private func dismissFallbackSaveWarning()") else {
            XCTFail("The warning needs one guarded dismissal handler shared by its action surface.")
            return
        }
        let dismiss = try TestSourceSlicer.braceBalancedBody(
            after: "private func dismissFallbackSaveWarning()",
            in: assistant
        )

        XCTAssertGreaterThanOrEqual(
            status.components(separatedBy: ".disabled(isProcessing)").count - 1,
            2,
            "Retry Save and Dismiss must both be disabled while retry persistence is active."
        )
        XCTAssertTrue(
            dismiss.contains("guard !isProcessing else { return }"),
            "The action handler must preserve the exact retry payload even if dismissal is invoked programmatically."
        )
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
