import XCTest
@testable import Weird_Parts

/// Behavioral async-lifecycle coverage for WEI-5060 / PR #1460.
///
/// These tests drive the same production completion seam used by
/// `persistHelpHandoffTurn` and `loadConversationList`: each test starts a
/// delayed async completion against Conversation A, performs a lifecycle
/// transition, releases success/failure, and verifies Conversation B remains
/// clean. They intentionally avoid source-substring assertions and avoid a
/// DEBUG-only duplicate of the completion logic.
@MainActor
final class AIHelpAsyncLifecycleBehaviorTests: XCTestCase {
    func testDelayedHelpSuccessAfterNewDoesNotContaminateConversationB() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(staged: true)

        state.transitionToNewConversation("conversation-b")
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation()

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
    }

    func testDelayedHelpFailureAfterNewDoesNotContaminateConversationB() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        state.transitionToNewConversation("conversation-b")
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation()

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
        XCTAssertFalse(state.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterResumeDoesNotContaminateConversationB() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(staged: true)

        state.resumeConversation("conversation-b")
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation()

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
    }

    func testDelayedHelpFailureAfterResumeDoesNotContaminateConversationB() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        state.resumeConversation("conversation-b")
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation()

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
        XCTAssertFalse(state.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterLogoutDoesNotContaminateNextSession() async {
        var state = LifecycleState(conversationId: "help-a", ownerUserId: 101)
        let delayedHelpA = state.beginHelpCompletion(staged: true)

        state.logout(newConversationId: "post-logout-b")
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation("Post logout question")

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Post logout question",
            "Generated response for post-logout-b",
        ])
    }

    func testDelayedHelpFailureAfterLogoutDoesNotContaminateNextSession() async {
        var state = LifecycleState(conversationId: "help-a", ownerUserId: 101)
        let delayedHelpA = state.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        state.logout(newConversationId: "post-logout-b")
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation("Post logout question")

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Post logout question",
            "Generated response for post-logout-b",
        ])
        XCTAssertFalse(state.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterClearDoesNotContaminateClearedConversation() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(staged: true)

        state.clearCurrentConversation()
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation("Question after clear")

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Question after clear",
            "Generated response for help-a",
        ])
    }

    func testDelayedHelpFailureAfterClearDoesNotContaminateClearedConversation() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(
            staged: false,
            errorDescription: "stale Help A persistence failure"
        )

        state.clearCurrentConversation()
        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation("Question after clear")

        XCTAssertNil(state.conversationPersistenceError)
        XCTAssertEqual(state.messages.map(\.content), [
            "Question after clear",
            "Generated response for help-a",
        ])
        XCTAssertFalse(state.messages.contains { $0.content.contains("stale Help A") })
    }

    func testCurrentHelpFailureStillSurfacesBeforeSending() async {
        var state = LifecycleState(conversationId: "help-a")
        let delayedHelpA = state.beginHelpCompletion(
            staged: false,
            errorDescription: "current Help persistence failure"
        )

        await state.finishHelpCompletion(delayedHelpA)
        state.sendInCurrentConversation("Follow-up question")

        XCTAssertEqual(
            state.conversationPersistenceError,
            "This Help conversation is visible now but could not be saved: current Help persistence failure"
        )
        XCTAssertEqual(state.messages.map(\.content), [
            "Follow-up question",
            "This Help conversation is visible now but could not be saved: current Help persistence failure",
        ])
    }

    func testStaleConversationListReturnAlwaysClearsLoadingAfterNewResumeAndLogout() async {
        for transition in ListTransition.allCases {
            var state = LifecycleState(conversationId: "conversation-a", ownerUserId: 1)
            let delayedListA = state.beginConversationListLoad(rows: [
                IOSAIAssistantPanel.SavedConversation(
                    id: "conversation-a",
                    lastMessageAt: "2026-07-16 10:00:00",
                    preview: "stale A preview"
                ),
            ])
            XCTAssertTrue(state.isLoadingConversations)

            switch transition {
            case .new:
                state.transitionToNewConversation("conversation-b")
            case .resume:
                state.resumeConversation("conversation-b")
            case .logout:
                state.logout(newConversationId: "post-logout-b")
            }

            await state.finishConversationListLoad(delayedListA)

            XCTAssertFalse(state.isLoadingConversations, "\(transition) must clear the spinner even when the delayed list is stale.")
            XCTAssertTrue(state.savedConversations.isEmpty, "\(transition) must not install stale A rows.")
        }
    }

    func testCurrentConversationListReturnInstallsRowsAndClearsLoading() async {
        var state = LifecycleState(conversationId: "conversation-a", ownerUserId: 1)
        let currentList = state.beginConversationListLoad(rows: [
            IOSAIAssistantPanel.SavedConversation(
                id: "conversation-a",
                lastMessageAt: "2026-07-16 10:00:00",
                preview: "current preview"
            ),
        ])

        await state.finishConversationListLoad(currentList)

        XCTAssertFalse(state.isLoadingConversations)
        XCTAssertEqual(state.savedConversations.map(\.preview), ["current preview"])
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
private struct LifecycleState {
    var conversationId: String
    var ownerUserId: Int64?
    var conversationRevision: UInt
    var conversationPersistenceError: String?
    var messages: [AssistantMessage]
    var savedConversations: [IOSAIAssistantPanel.SavedConversation]
    var isLoadingConversations = false

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

    func beginHelpCompletion(
        staged: Bool,
        errorDescription: String? = nil
    ) -> DelayedHelpCompletion {
        DelayedHelpCompletion(
            lifecycle: snapshot(),
            staged: staged,
            errorDescription: errorDescription
        )
    }

    mutating func finishHelpCompletion(_ delayedCompletion: DelayedHelpCompletion) async {
        let completion = await delayedCompletion.resolve(
            currentConversationId: conversationId,
            currentOwnerUserId: ownerUserId,
            currentRevision: conversationRevision
        )
        guard let completion else { return }
        conversationPersistenceError = completion.persistenceError
    }

    mutating func transitionToNewConversation(_ newConversationId: String) {
        conversationRevision &+= 1
        conversationId = newConversationId
        conversationPersistenceError = nil
        messages = []
    }

    mutating func resumeConversation(_ resumedConversationId: String) {
        conversationRevision &+= 1
        conversationId = resumedConversationId
        conversationPersistenceError = nil
        messages = []
    }

    mutating func logout(newConversationId: String = "post-logout") {
        conversationRevision &+= 1
        conversationId = newConversationId
        ownerUserId = nil
        conversationPersistenceError = nil
        messages = []
        savedConversations = []
    }

    mutating func clearCurrentConversation() {
        conversationRevision &+= 1
        conversationPersistenceError = nil
        messages = []
    }

    mutating func sendInCurrentConversation(_ text: String = "Conversation B question") {
        messages.append(AssistantMessage(role: .user, content: text))
        if let conversationPersistenceError {
            messages.append(AssistantMessage(role: .assistant, content: conversationPersistenceError))
        } else {
            messages.append(AssistantMessage(role: .assistant, content: "Generated response for \(conversationId)"))
        }
    }

    mutating func beginConversationListLoad(
        rows: [IOSAIAssistantPanel.SavedConversation]
    ) -> DelayedConversationListCompletion {
        isLoadingConversations = true
        return DelayedConversationListCompletion(lifecycle: snapshot(), rows: rows)
    }

    mutating func finishConversationListLoad(_ delayedCompletion: DelayedConversationListCompletion) async {
        defer { isLoadingConversations = false }
        guard let rows = await delayedCompletion.resolve(
            currentConversationId: conversationId,
            currentOwnerUserId: ownerUserId,
            currentRevision: conversationRevision
        ) else { return }
        savedConversations = rows
    }

    private func snapshot() -> AIConversationLifecycleSnapshot {
        AIConversationLifecycleSnapshot(
            conversationId: conversationId,
            ownerUserId: ownerUserId ?? -1,
            revision: conversationRevision
        )
    }
}

private struct DelayedHelpCompletion {
    let lifecycle: AIConversationLifecycleSnapshot
    let staged: Bool
    let errorDescription: String?

    @MainActor
    func resolve(
        currentConversationId: String,
        currentOwnerUserId: Int64?,
        currentRevision: UInt
    ) async -> AIHelpPersistenceCompletion? {
        await Task.yield()
        return AIAsyncLifecycleCompletion.helpPersistenceResult(
            lifecycle: lifecycle,
            staged: staged,
            errorDescription: errorDescription,
            currentConversationId: currentConversationId,
            currentOwnerUserId: currentOwnerUserId,
            currentRevision: currentRevision
        )
    }
}

private struct DelayedConversationListCompletion {
    let lifecycle: AIConversationLifecycleSnapshot
    let rows: [IOSAIAssistantPanel.SavedConversation]

    @MainActor
    func resolve(
        currentConversationId: String,
        currentOwnerUserId: Int64?,
        currentRevision: UInt
    ) async -> [IOSAIAssistantPanel.SavedConversation]? {
        await Task.yield()
        return AIAsyncLifecycleCompletion.conversationListResult(
            lifecycle: lifecycle,
            rows: rows,
            currentConversationId: currentConversationId,
            currentOwnerUserId: currentOwnerUserId,
            currentRevision: currentRevision
        )
    }
}
