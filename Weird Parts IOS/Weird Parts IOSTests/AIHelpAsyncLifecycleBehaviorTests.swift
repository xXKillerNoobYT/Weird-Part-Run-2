import XCTest
@testable import Weird_Parts
import WiredPartCore

/// Behavioral async-lifecycle coverage for WEI-5062 / PR #1460.
///
/// These tests drive the production `AIAssistantLifecycleCoordinator` used by
/// Help persistence and conversation-list completions in `IOSAIAssistantPanel`.
/// Suspensions are controlled with explicit continuations so the test owns the
/// exact stale-completion ordering instead of depending on `Task.yield()`.
@MainActor
final class AIHelpAsyncLifecycleBehaviorTests: XCTestCase {
    func testDelayedHelpSuccessAfterNewDoesNotContaminateConversationB() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(staged: true)

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.transitionToNewConversation("conversation-b")
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation()

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
    }

    func testDelayedHelpFailureAfterNewDoesNotContaminateConversationB() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.transitionToNewConversation("conversation-b")
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation()

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
        XCTAssertFalse(box.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterResumeDoesNotContaminateConversationB() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(staged: true)

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.resumeConversation("conversation-b")
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation()

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
    }

    func testDelayedHelpFailureAfterResumeDoesNotContaminateConversationB() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.resumeConversation("conversation-b")
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation()

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
        XCTAssertFalse(box.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterLogoutDoesNotContaminateNextSession() async {
        let box = CoordinatorBox(conversationId: "help-a", ownerUserId: 101)
        let delayedHelpA = box.beginHelpCompletion(staged: true)

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.logout(newConversationId: "post-logout-b")
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation("Post logout question")

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Post logout question",
            "Generated response for post-logout-b",
        ])
    }

    func testDelayedHelpFailureAfterLogoutDoesNotContaminateNextSession() async {
        let box = CoordinatorBox(conversationId: "help-a", ownerUserId: 101)
        let delayedHelpA = box.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.logout(newConversationId: "post-logout-b")
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation("Post logout question")

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Post logout question",
            "Generated response for post-logout-b",
        ])
        XCTAssertFalse(box.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterClearDoesNotContaminateClearedConversation() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(staged: true)

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.clearCurrentConversation()
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation("Question after clear")

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Question after clear",
            "Generated response for help-a",
        ])
    }

    func testDelayedHelpFailureAfterClearDoesNotContaminateClearedConversation() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        box.clearCurrentConversation()
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertFalse(applied)
        box.sendInCurrentConversation("Question after clear")

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Question after clear",
            "Generated response for help-a",
        ])
        XCTAssertFalse(box.messages.contains { $0.content.contains("stale Help A") })
    }

    func testCurrentHelpFailureRemainsAWarningWithoutBlockingOrReplacingTheNextResponse() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let delayedHelpA = box.beginHelpCompletion(
            staged: false,
            errorDescription: "current Help persistence failure"
        )

        let task = box.finishHelpCompletionAfterGate(delayedHelpA)
        await delayedHelpA.gate.waitUntilEntered()
        await delayedHelpA.gate.release()

        let applied = await task.value
        XCTAssertTrue(applied)
        box.sendInCurrentConversation("Follow-up question")

        XCTAssertEqual(
            box.conversationPersistenceError,
            "This Help conversation is visible now but could not be saved: current Help persistence failure"
        )
        XCTAssertEqual(box.messages.map(\.content), [
            "Follow-up question",
            "Generated response for help-a",
        ])
    }

    func testSecondHelpHandoffUsesLatestLifecycleAndIgnoresEarlierCompletion() async {
        let box = CoordinatorBox(conversationId: "help-a")
        let firstHelp = box.beginHelpCompletion(
            staged: false,
            errorDescription: "first stale Help failure"
        )

        let firstTask = box.finishHelpCompletionAfterGate(firstHelp)
        await firstHelp.gate.waitUntilEntered()
        box.clearCurrentConversation()

        let secondHelp = box.beginHelpCompletion(staged: true)
        let secondTask = box.finishHelpCompletionAfterGate(secondHelp)
        await secondHelp.gate.waitUntilEntered()
        await secondHelp.gate.release()
        await firstHelp.gate.release()

        let secondApplied = await secondTask.value
        let firstApplied = await firstTask.value
        XCTAssertTrue(secondApplied)
        XCTAssertFalse(firstApplied)
        box.sendInCurrentConversation("Second Help follow-up")

        XCTAssertNil(box.conversationPersistenceError)
        XCTAssertEqual(box.messages.map(\.content), [
            "Second Help follow-up",
            "Generated response for help-a",
        ])
        XCTAssertFalse(box.messages.contains { $0.content.contains("first stale Help") })
    }

    func testStaleConversationListReturnAlwaysClearsLoadingAfterNewResumeAndLogout() async {
        for transition in ListTransition.allCases {
            let box = CoordinatorBox(conversationId: "conversation-a", ownerUserId: 1)
            let delayedListA = box.beginConversationListLoad(rows: [
                IOSAIAssistantPanel.SavedConversation(
                    id: "conversation-a",
                    lastMessageAt: "2026-07-16 10:00:00",
                    preview: "stale A preview"
                ),
            ])
            XCTAssertTrue(box.isLoadingConversations)

            let task = box.finishConversationListLoadAfterGate(delayedListA)
            await delayedListA.gate.waitUntilEntered()
            switch transition {
            case .new:
                box.transitionToNewConversation("conversation-b")
            case .resume:
                box.resumeConversation("conversation-b")
            case .logout:
                box.logout(newConversationId: "post-logout-b")
            }
            await delayedListA.gate.release()

            let applied = await task.value
            XCTAssertFalse(applied)
            XCTAssertFalse(box.isLoadingConversations, "\(transition) must clear the spinner even when the delayed list is stale.")
            XCTAssertTrue(box.savedConversations.isEmpty, "\(transition) must not install stale A rows.")
        }
    }

    func testOverlappingConversationListCompletionCannotInstallStaleRowsOverNewestLoad() async {
        let box = CoordinatorBox(conversationId: "conversation-a", ownerUserId: 1)
        let staleList = box.beginConversationListLoad(rows: [
            IOSAIAssistantPanel.SavedConversation(
                id: "conversation-a",
                lastMessageAt: "2026-07-16 10:00:00",
                preview: "stale preview"
            ),
        ])
        let staleTask = box.finishConversationListLoadAfterGate(staleList)
        await staleList.gate.waitUntilEntered()

        box.resumeConversation("conversation-b")
        let currentList = box.beginConversationListLoad(rows: [
            IOSAIAssistantPanel.SavedConversation(
                id: "conversation-b",
                lastMessageAt: "2026-07-16 10:02:00",
                preview: "current preview"
            ),
        ])
        let currentTask = box.finishConversationListLoadAfterGate(currentList)
        await currentList.gate.waitUntilEntered()

        await currentList.gate.release()
        await staleList.gate.release()

        let currentApplied = await currentTask.value
        let staleApplied = await staleTask.value
        XCTAssertTrue(currentApplied)
        XCTAssertFalse(staleApplied)
        XCTAssertFalse(box.isLoadingConversations)
        XCTAssertEqual(box.savedConversations.map(\.preview), ["current preview"])
    }

    func testCurrentConversationListReturnInstallsRowsAndClearsLoading() async {
        let box = CoordinatorBox(conversationId: "conversation-a", ownerUserId: 1)
        let currentList = box.beginConversationListLoad(rows: [
            IOSAIAssistantPanel.SavedConversation(
                id: "conversation-a",
                lastMessageAt: "2026-07-16 10:00:00",
                preview: "current preview"
            ),
        ])

        let task = box.finishConversationListLoadAfterGate(currentList)
        await currentList.gate.waitUntilEntered()
        await currentList.gate.release()

        let applied = await task.value
        XCTAssertTrue(applied)
        XCTAssertFalse(box.isLoadingConversations)
        XCTAssertEqual(box.savedConversations.map(\.preview), ["current preview"])
    }

    func testHelpHandoffWaitsForSuspendedFallbackPersistenceAndLeavesComposerUsable() async {
        let box = FallbackHelpHandoffBox(conversationId: "conversation-a", ownerUserId: 42)
        let delayedFallback = box.beginFallbackPersistence(
            userPrompt: "Fallback question",
            assistantResponse: "Fallback response"
        )

        let persistenceTask = box.finishFallbackPersistenceAfterGate(delayedFallback)
        await delayedFallback.gate.waitUntilEntered()
        box.queueHelpHandoff(
            requestID: "help-during-fallback",
            userPrompt: "Help question",
            assistantResponse: "Help response"
        )

        XCTAssertFalse(box.consumeQueuedHelpHandoff())
        XCTAssertFalse(box.isComposerUsable)
        XCTAssertTrue(box.hasPendingFallbackRetry)

        await delayedFallback.gate.release()
        await persistenceTask.value

        XCTAssertTrue(box.consumeQueuedHelpHandoff())
        XCTAssertTrue(box.isComposerUsable)
        XCTAssertFalse(box.hasPendingFallbackRetry)
        XCTAssertNil(box.persistenceError)
        XCTAssertEqual(box.visibleTranscript.map(\.content), [
            "Fallback question",
            "Fallback response",
            "Help question",
            "Help response",
        ])
        XCTAssertEqual(
            box.persistedTranscript,
            box.visibleTranscript,
            "The fallback pair must settle before Help takes ownership of the same conversation transcript."
        )
        XCTAssertTrue(box.persistedTranscript.allSatisfy {
            $0.conversationId == "conversation-a" && $0.ownerUserId == 42
        })
    }

    func testHelpHandoffWaitsForSuspendedGenerationAndKeepsVisibleReloadedAndStagedHistoryEqual() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        let conversationId = "help-during-generation"
        let ownerUserId: Int64 = 42
        var readiness = AIHelpHandoffReadinessCoordinator()
        let initialization = readiness.beginInitialization()
        XCTAssertTrue(readiness.finishInitialization(initialization))
        let sendLifecycle = readiness.beginSendLifecycle()
        var visibleTranscript: [AIConversationMessage] = []

        let generationTask = Task { @MainActor in
            await gate.enterAndWaitForRelease()
            let outcome = try await service.stageLocalConversation(
                conversationId,
                ownerUserId: ownerUserId,
                userPrompt: "Suspended model question",
                assistantResponse: "Persisted model response",
                in: db
            )
            XCTAssertEqual(outcome, .persistedAndStaged)
            visibleTranscript.append(contentsOf: [
                AIConversationMessage(conversationId: conversationId, role: "user", content: "Suspended model question"),
                AIConversationMessage(conversationId: conversationId, role: "assistant", content: "Persisted model response"),
            ])
            XCTAssertTrue(readiness.finishSendLifecycle(sendLifecycle))
        }

        await gate.waitUntilEntered()
        readiness.queueHelpRequest(id: "help-arrived-during-generation")
        XCTAssertNil(
            readiness.consumeQueuedHelpRequest(),
            "Help must remain queued for the complete generation and model-persistence lifecycle."
        )

        await gate.release()
        try await generationTask.value
        XCTAssertEqual(readiness.consumeQueuedHelpRequest(), "help-arrived-during-generation")

        let helpStaged = try await service.stageHelpConversation(
            conversationId,
            ownerUserId: ownerUserId,
            userPrompt: "Help question",
            assistantResponse: "Help response",
            in: db
        )
        XCTAssertTrue(helpStaged)
        visibleTranscript.append(contentsOf: [
            AIConversationMessage(conversationId: conversationId, role: "user", content: "Help question"),
            AIConversationMessage(conversationId: conversationId, role: "assistant", content: "Help response"),
        ])

        let reloaded = try await FoundationModelsService.loadConversation(
            conversationId,
            ownerUserId: ownerUserId,
            from: db
        )
        let otherOwnerReload = try await FoundationModelsService.loadConversation(
            conversationId,
            ownerUserId: ownerUserId + 1,
            from: db
        )
        let stagedModelHistory = await service.currentMessageHistory()

        XCTAssertEqual(reloaded.map(\.role), visibleTranscript.map(\.role))
        XCTAssertEqual(reloaded.map(\.content), visibleTranscript.map(\.content))
        XCTAssertEqual(stagedModelHistory.map(\.role), visibleTranscript.map(\.role))
        XCTAssertEqual(stagedModelHistory.map(\.content), visibleTranscript.map(\.content))
        XCTAssertTrue(reloaded.allSatisfy { $0.conversationId == conversationId })
        XCTAssertTrue(otherOwnerReload.isEmpty, "The completed lifecycle must remain isolated to the sending owner.")
    }

    func testPersistedButNotStagedFallbackClearsRetryInsteadOfDuplicatingDurablePair() async throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        let conversationId = "fallback-ui-post-write-race"
        let ownerUserId: Int64 = 42

        let persistenceTask = Task {
            try await service.stageLocalConversation(
                conversationId,
                ownerUserId: ownerUserId,
                userPrompt: "Fallback question",
                assistantResponse: "Fallback response",
                in: db,
                afterPersisting: {
                    await gate.enterAndWaitForRelease()
                }
            )
        }

        await gate.waitUntilEntered()
        await service.clearConversation()
        await gate.release()

        let outcome = try await persistenceTask.value
        let retryDecision = AIFallbackPersistenceRetryDecision.resolve(
            outcome: outcome,
            lifecycleIsCurrent: false
        )
        let reloaded = try await FoundationModelsService.loadConversation(
            conversationId,
            ownerUserId: ownerUserId,
            from: db
        )
        let stagedHistory = await service.currentMessageHistory()

        XCTAssertEqual(outcome, .persistedButNotStaged)
        XCTAssertEqual(retryDecision, .saved)
        XCTAssertEqual(reloaded.map(\.role), ["user", "assistant"])
        XCTAssertEqual(reloaded.map(\.content), ["Fallback question", "Fallback response"])
        XCTAssertTrue(stagedHistory.isEmpty)
    }

    func testHelpHandoffClearsFailedFallbackRetryAfterSuspension() async {
        let box = FallbackHelpHandoffBox(conversationId: "conversation-a", ownerUserId: 42)
        let delayedFallback = box.beginFallbackPersistence(
            userPrompt: "Unsaved fallback question",
            assistantResponse: "Unsaved fallback response",
            errorDescription: "simulated storage failure"
        )

        let persistenceTask = box.finishFallbackPersistenceAfterGate(delayedFallback)
        await delayedFallback.gate.waitUntilEntered()
        box.queueHelpHandoff(
            requestID: "help-after-failed-fallback",
            userPrompt: "Help question",
            assistantResponse: "Help response"
        )
        await delayedFallback.gate.release()
        await persistenceTask.value

        XCTAssertTrue(box.hasPendingFallbackRetry)
        XCTAssertNotNil(box.persistenceError)
        XCTAssertFalse(
            box.consumeQueuedHelpHandoff(),
            "Queued Help must wait while the failed fallback pair remains recoverable."
        )
        XCTAssertTrue(box.dismissFallbackWarningAndConsumeQueuedHelp())
        XCTAssertTrue(box.isComposerUsable)
        XCTAssertFalse(box.hasPendingFallbackRetry)
        XCTAssertNil(box.persistenceError)
        XCTAssertEqual(box.persistedTranscript.map(\.content), ["Help question", "Help response"])
        XCTAssertTrue(box.persistedTranscript.allSatisfy {
            $0.conversationId == "conversation-a" && $0.ownerUserId == 42
        })
    }

    func testDismissAttemptDuringSuspendedRetrySuccessPreservesPayloadUntilCompletion() async {
        let box = FallbackRetryWarningBox()
        let delayedRetry = box.beginRetryPersistence()
        let retryTask = box.finishRetryPersistenceAfterGate(delayedRetry)
        await delayedRetry.gate.waitUntilEntered()

        XCTAssertFalse(box.attemptDismissWarning())
        XCTAssertFalse(box.areWarningActionsEnabled)
        XCTAssertTrue(box.hasPendingFallbackRetry)

        await delayedRetry.gate.release()
        await retryTask.value

        XCTAssertTrue(box.areWarningActionsEnabled)
        XCTAssertFalse(box.hasPendingFallbackRetry)
        XCTAssertNil(box.persistenceError)
    }

    func testDismissAttemptDuringSuspendedRetryFailureRetainsRecoverableExactPair() async {
        let box = FallbackRetryWarningBox()
        let delayedRetry = box.beginRetryPersistence(errorDescription: "simulated retry storage failure")
        let retryTask = box.finishRetryPersistenceAfterGate(delayedRetry)
        await delayedRetry.gate.waitUntilEntered()

        XCTAssertFalse(box.attemptDismissWarning())
        XCTAssertFalse(box.areWarningActionsEnabled)
        XCTAssertEqual(box.pendingPair, FallbackRetryWarningBox.Pair(
            userPrompt: "Exact retry question",
            assistantResponse: "Exact retry response"
        ))

        await delayedRetry.gate.release()
        await retryTask.value

        XCTAssertTrue(box.areWarningActionsEnabled)
        XCTAssertTrue(box.hasPendingFallbackRetry)
        XCTAssertEqual(box.persistenceError, "simulated retry storage failure")
        XCTAssertEqual(box.pendingPair, FallbackRetryWarningBox.Pair(
            userPrompt: "Exact retry question",
            assistantResponse: "Exact retry response"
        ))
    }

    func testFailedHydrationThenResumeCurrentRowRequiresRecoveryLoad() {
        let action = AIAssistantResumeSelectionPolicy.action(
            selectedConversationId: "conversation-a",
            currentConversationId: "conversation-a",
            hasTranscriptHydrationFailure: true
        )

        XCTAssertEqual(action, .retryCurrentHydration)
        XCTAssertNotEqual(action, .noChange)
    }

    func testCurrentRowWithoutHydrationFailureRemainsNoOp() {
        XCTAssertEqual(
            AIAssistantResumeSelectionPolicy.action(
                selectedConversationId: "conversation-a",
                currentConversationId: "conversation-a",
                hasTranscriptHydrationFailure: false
            ),
            .noChange
        )
        XCTAssertEqual(
            AIAssistantResumeSelectionPolicy.action(
                selectedConversationId: "conversation-b",
                currentConversationId: "conversation-a",
                hasTranscriptHydrationFailure: true
            ),
            .switchConversation
        )
    }

    func testHelpHandoffWaitsForAuthenticatedInitializationToFinish() {
        var readiness = AIHelpHandoffReadinessCoordinator()

        let unauthenticatedPass = readiness.beginInitialization()
        XCTAssertTrue(readiness.finishInitialization(unauthenticatedPass))
        XCTAssertTrue(readiness.isReadyForHelpHandoff)

        let authenticatedPass = readiness.beginInitialization()
        XCTAssertFalse(
            readiness.isReadyForHelpHandoff,
            "A login-triggered history hydration must make Help wait instead of seeding the pre-resume conversation."
        )
        XCTAssertNil(readiness.consumeQueuedHelpRequest())

        readiness.queueHelpRequest(id: "help-arriving-during-hydration")
        XCTAssertNil(readiness.consumeQueuedHelpRequest())
        XCTAssertTrue(readiness.finishInitialization(authenticatedPass))
        XCTAssertEqual(readiness.consumeQueuedHelpRequest(), "help-arriving-during-hydration")
    }

    private enum ListTransition: CaseIterable, CustomStringConvertible {
        case new
        case resume
        case logout

        var description: String {
            switch self {
            case .new: return "New"
            case .resume: return "Resume"
            case .logout: return "logout"
            }
        }
    }
}

@MainActor
private final class CoordinatorBox {
    private var coordinator: AIAssistantLifecycleCoordinator<IOSAIAssistantPanel.SavedConversation>
    private(set) var messages: [AssistantMessage]

    var conversationPersistenceError: String? { coordinator.conversationPersistenceError }
    var savedConversations: [IOSAIAssistantPanel.SavedConversation] { coordinator.savedConversations }
    var isLoadingConversations: Bool { coordinator.isLoadingConversations }

    init(
        conversationId: String = "conversation-a",
        ownerUserId: Int64? = 1,
        conversationRevision: UInt = 0,
        messages: [AssistantMessage] = []
    ) {
        self.coordinator = AIAssistantLifecycleCoordinator(
            conversationId: conversationId,
            ownerUserId: ownerUserId,
            conversationRevision: conversationRevision
        )
        self.messages = messages
    }

    func beginHelpCompletion(
        staged: Bool,
        errorDescription: String? = nil
    ) -> DelayedHelpCompletion {
        DelayedHelpCompletion(
            lifecycle: coordinator.snapshot(),
            staged: staged,
            errorDescription: errorDescription
        )
    }

    func finishHelpCompletionAfterGate(_ delayedCompletion: DelayedHelpCompletion) -> Task<Bool, Never> {
        Task { @MainActor in
            await delayedCompletion.gate.enterAndWaitForRelease()
            return coordinator.finishHelpPersistence(
                lifecycle: delayedCompletion.lifecycle,
                staged: delayedCompletion.staged,
                errorDescription: delayedCompletion.errorDescription
            )
        }
    }

    func transitionToNewConversation(_ newConversationId: String) {
        coordinator.transitionToNewConversation(newConversationId)
        messages = []
    }

    func resumeConversation(_ resumedConversationId: String) {
        coordinator.resumeConversation(resumedConversationId)
        messages = []
    }

    func logout(newConversationId: String = "post-logout") {
        coordinator.logout(newConversationId: newConversationId)
        messages = []
    }

    func clearCurrentConversation() {
        coordinator.clearCurrentConversation()
        messages = []
    }

    func sendInCurrentConversation(_ text: String = "Conversation B question") {
        messages.append(AssistantMessage(role: .user, content: text))
        messages.append(AssistantMessage(role: .assistant, content: "Generated response for \(coordinator.conversationId)"))
    }

    func beginConversationListLoad(
        rows: [IOSAIAssistantPanel.SavedConversation]
    ) -> DelayedConversationListCompletion {
        let nextRequestID = coordinator.conversationListRequestID &+ 1
        let lifecycle = coordinator.beginConversationListLoad(requestID: nextRequestID)
        return DelayedConversationListCompletion(lifecycle: lifecycle, requestID: nextRequestID, rows: rows)
    }

    func finishConversationListLoadAfterGate(_ delayedCompletion: DelayedConversationListCompletion) -> Task<Bool, Never> {
        Task { @MainActor in
            await delayedCompletion.gate.enterAndWaitForRelease()
            return coordinator.finishConversationListLoad(
                lifecycle: delayedCompletion.lifecycle,
                requestID: delayedCompletion.requestID,
                rows: delayedCompletion.rows
            )
        }
    }
}

private struct DelayedHelpCompletion {
    let lifecycle: AIConversationLifecycleSnapshot
    let staged: Bool
    let errorDescription: String?
    let gate = AsyncGate()
}

private struct DelayedConversationListCompletion {
    let lifecycle: AIConversationLifecycleSnapshot
    let requestID: UInt
    let rows: [IOSAIAssistantPanel.SavedConversation]
    let gate = AsyncGate()
}

@MainActor
private final class FallbackHelpHandoffBox {
    struct OwnedTurn: Equatable {
        let conversationId: String
        let ownerUserId: Int64
        let content: String
    }

    private let conversationId: String
    private let ownerUserId: Int64
    private var readiness = AIHelpHandoffReadinessCoordinator()
    private var queuedHelp: (userPrompt: String, assistantResponse: String)?
    private(set) var visibleTranscript: [OwnedTurn] = []
    private(set) var persistedTranscript: [OwnedTurn] = []
    private(set) var hasPendingFallbackRetry = false
    private(set) var persistenceError: String?
    private var isProcessing = false

    var isComposerUsable: Bool {
        !isProcessing && !hasPendingFallbackRetry
    }

    init(conversationId: String, ownerUserId: Int64) {
        self.conversationId = conversationId
        self.ownerUserId = ownerUserId
        let initialization = readiness.beginInitialization()
        XCTAssertTrue(readiness.finishInitialization(initialization))
    }

    func beginFallbackPersistence(
        userPrompt: String,
        assistantResponse: String,
        errorDescription: String? = nil
    ) -> DelayedFallbackPersistence {
        visibleTranscript.append(contentsOf: ownedTurns(userPrompt, assistantResponse))
        hasPendingFallbackRetry = true
        isProcessing = true
        return DelayedFallbackPersistence(
            requestID: readiness.beginSendLifecycle(),
            userPrompt: userPrompt,
            assistantResponse: assistantResponse,
            errorDescription: errorDescription
        )
    }

    func finishFallbackPersistenceAfterGate(_ delayedPersistence: DelayedFallbackPersistence) -> Task<Void, Never> {
        Task { @MainActor in
            await delayedPersistence.gate.enterAndWaitForRelease()
            if let errorDescription = delayedPersistence.errorDescription {
                persistenceError = errorDescription
            } else {
                persistedTranscript.append(contentsOf: ownedTurns(
                    delayedPersistence.userPrompt,
                    delayedPersistence.assistantResponse
                ))
                hasPendingFallbackRetry = false
                persistenceError = nil
            }
            XCTAssertTrue(readiness.finishSendLifecycle(delayedPersistence.requestID))
            isProcessing = false
        }
    }

    func queueHelpHandoff(
        requestID: String,
        userPrompt: String,
        assistantResponse: String
    ) {
        queuedHelp = (userPrompt, assistantResponse)
        readiness.queueHelpRequest(id: requestID)
    }

    @discardableResult
    func consumeQueuedHelpHandoff() -> Bool {
        guard !hasPendingFallbackRetry,
              readiness.consumeQueuedHelpRequest() != nil,
              let queuedHelp else { return false }
        self.queuedHelp = nil
        hasPendingFallbackRetry = false
        persistenceError = nil
        let helpTurns = ownedTurns(queuedHelp.userPrompt, queuedHelp.assistantResponse)
        visibleTranscript.append(contentsOf: helpTurns)
        persistedTranscript.append(contentsOf: helpTurns)
        return true
    }

    @discardableResult
    func dismissFallbackWarningAndConsumeQueuedHelp() -> Bool {
        guard !isProcessing else { return false }
        hasPendingFallbackRetry = false
        persistenceError = nil
        return consumeQueuedHelpHandoff()
    }

    private func ownedTurns(_ userPrompt: String, _ assistantResponse: String) -> [OwnedTurn] {
        [userPrompt, assistantResponse].map {
            OwnedTurn(conversationId: conversationId, ownerUserId: ownerUserId, content: $0)
        }
    }
}

private struct DelayedFallbackPersistence {
    let requestID: UInt
    let userPrompt: String
    let assistantResponse: String
    let errorDescription: String?
    let gate = AsyncGate()
}

@MainActor
private final class FallbackRetryWarningBox {
    struct Pair: Equatable {
        let userPrompt: String
        let assistantResponse: String
    }

    private(set) var pendingPair: Pair? = Pair(
        userPrompt: "Exact retry question",
        assistantResponse: "Exact retry response"
    )
    private(set) var persistenceError: String? = "initial storage failure"
    private var isProcessing = false

    var areWarningActionsEnabled: Bool { !isProcessing }
    var hasPendingFallbackRetry: Bool { pendingPair != nil }

    func beginRetryPersistence(errorDescription: String? = nil) -> DelayedRetryPersistence {
        precondition(pendingPair != nil)
        isProcessing = true
        return DelayedRetryPersistence(errorDescription: errorDescription)
    }

    func attemptDismissWarning() -> Bool {
        guard !isProcessing else { return false }
        pendingPair = nil
        persistenceError = nil
        return true
    }

    func finishRetryPersistenceAfterGate(_ delayedRetry: DelayedRetryPersistence) -> Task<Void, Never> {
        Task { @MainActor in
            await delayedRetry.gate.enterAndWaitForRelease()
            if let errorDescription = delayedRetry.errorDescription {
                persistenceError = errorDescription
            } else {
                pendingPair = nil
                persistenceError = nil
            }
            isProcessing = false
        }
    }
}

private struct DelayedRetryPersistence {
    let errorDescription: String?
    let gate = AsyncGate()
}

private actor AsyncGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWaitForRelease() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()

        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
