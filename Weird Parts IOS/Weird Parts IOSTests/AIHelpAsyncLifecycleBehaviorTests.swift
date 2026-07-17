import XCTest
@testable import Weird_Parts

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

    func testCurrentHelpFailureStillSurfacesBeforeSending() async {
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
            "This Help conversation is visible now but could not be saved: current Help persistence failure",
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
        if let conversationPersistenceError {
            messages.append(AssistantMessage(role: .assistant, content: conversationPersistenceError))
        } else {
            messages.append(AssistantMessage(role: .assistant, content: "Generated response for \(coordinator.conversationId)"))
        }
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
