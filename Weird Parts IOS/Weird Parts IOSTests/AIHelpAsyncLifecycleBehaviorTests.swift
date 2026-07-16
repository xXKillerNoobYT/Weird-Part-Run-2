import XCTest
@testable import Weird_Parts

/// Behavioral async-lifecycle coverage for WEI-5060 / PR #1460.
///
/// These tests exercise the same lifecycle snapshot used by IOSAIAssistantPanel's
/// delayed Help-persistence and conversation-list completions. They intentionally
/// avoid source-substring assertions: each case starts an operation against
/// Conversation A, performs a lifecycle transition, completes the delayed work,
/// then verifies Conversation B remains clean.
@MainActor
final class AIHelpAsyncLifecycleBehaviorTests: XCTestCase {
    func testDelayedHelpSuccessAfterNewDoesNotContaminateConversationB() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.transitionToNewConversation("conversation-b")
        harness.completeHelp(snapshot: delayedHelpA, staged: true)
        harness.sendInCurrentConversation()

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
    }

    func testDelayedHelpFailureAfterNewDoesNotContaminateConversationB() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.transitionToNewConversation("conversation-b")
        harness.completeHelp(
            snapshot: delayedHelpA,
            staged: false,
            error: "stale Help A persistence failure"
        )
        harness.sendInCurrentConversation()

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
        XCTAssertFalse(harness.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterResumeDoesNotContaminateConversationB() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.resumeConversation("conversation-b")
        harness.completeHelp(snapshot: delayedHelpA, staged: true)
        harness.sendInCurrentConversation()

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
    }

    func testDelayedHelpFailureAfterResumeDoesNotContaminateConversationB() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.resumeConversation("conversation-b")
        harness.completeHelp(
            snapshot: delayedHelpA,
            staged: false,
            error: "stale Help A persistence failure"
        )
        harness.sendInCurrentConversation()

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Conversation B question",
            "Generated response for conversation-b",
        ])
        XCTAssertFalse(harness.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterLogoutDoesNotContaminateNextSession() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a", ownerUserId: 101)
        let delayedHelpA = harness.beginHelpCompletion()

        harness.logout(newConversationId: "post-logout-b")
        harness.completeHelp(snapshot: delayedHelpA, staged: true)
        harness.sendInCurrentConversation("Post logout question")

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Post logout question",
            "Generated response for post-logout-b",
        ])
    }

    func testDelayedHelpFailureAfterLogoutDoesNotContaminateNextSession() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a", ownerUserId: 101)
        let delayedHelpA = harness.beginHelpCompletion()

        harness.logout(newConversationId: "post-logout-b")
        harness.completeHelp(
            snapshot: delayedHelpA,
            staged: false,
            error: "stale Help A persistence failure"
        )
        harness.sendInCurrentConversation("Post logout question")

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Post logout question",
            "Generated response for post-logout-b",
        ])
        XCTAssertFalse(harness.messages.contains { $0.content.contains("stale Help A") })
    }

    func testDelayedHelpSuccessAfterClearDoesNotContaminateClearedConversation() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.clearCurrentConversation()
        harness.completeHelp(snapshot: delayedHelpA, staged: true)
        harness.sendInCurrentConversation("Question after clear")

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Question after clear",
            "Generated response for help-a",
        ])
    }

    func testDelayedHelpFailureAfterClearDoesNotContaminateClearedConversation() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.clearCurrentConversation()
        harness.completeHelp(
            snapshot: delayedHelpA,
            staged: false,
            error: "stale Help A persistence failure"
        )
        harness.sendInCurrentConversation("Question after clear")

        XCTAssertNil(harness.conversationPersistenceError)
        XCTAssertEqual(harness.messages.map(\.content), [
            "Question after clear",
            "Generated response for help-a",
        ])
        XCTAssertFalse(harness.messages.contains { $0.content.contains("stale Help A") })
    }

    func testCurrentHelpFailureStillSurfacesBeforeSending() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "help-a")
        let delayedHelpA = harness.beginHelpCompletion()

        harness.completeHelp(
            snapshot: delayedHelpA,
            staged: false,
            error: "current Help persistence failure"
        )
        harness.sendInCurrentConversation("Follow-up question")

        XCTAssertEqual(harness.conversationPersistenceError, "current Help persistence failure")
        XCTAssertEqual(harness.messages.map(\.content), [
            "Follow-up question",
            "current Help persistence failure",
        ])
    }

    func testStaleConversationListReturnAlwaysClearsLoadingAfterNewResumeAndLogout() {
        for transition in ListTransition.allCases {
            let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "conversation-a", ownerUserId: 1)
            let delayedListA = harness.beginConversationListLoad()
            XCTAssertTrue(harness.isLoadingConversations)

            switch transition {
            case .new:
                harness.transitionToNewConversation("conversation-b")
            case .resume:
                harness.resumeConversation("conversation-b")
            case .logout:
                harness.logout(newConversationId: "post-logout-b")
            }

            harness.finishConversationListLoad(
                snapshot: delayedListA,
                rows: [IOSAIAssistantPanel.SavedConversation(
                    id: "conversation-a",
                    lastMessageAt: "2026-07-16 10:00:00",
                    preview: "stale A preview"
                )]
            )

            XCTAssertFalse(harness.isLoadingConversations, "\(transition) must clear the spinner even when the delayed list is stale.")
            XCTAssertTrue(harness.savedConversations.isEmpty, "\(transition) must not install stale A rows.")
        }
    }

    func testCurrentConversationListReturnInstallsRowsAndClearsLoading() {
        let harness = AIHelpAsyncLifecycleRegressionHarness(conversationId: "conversation-a", ownerUserId: 1)
        let currentList = harness.beginConversationListLoad()

        harness.finishConversationListLoad(
            snapshot: currentList,
            rows: [IOSAIAssistantPanel.SavedConversation(
                id: "conversation-a",
                lastMessageAt: "2026-07-16 10:00:00",
                preview: "current preview"
            )]
        )

        XCTAssertFalse(harness.isLoadingConversations)
        XCTAssertEqual(harness.savedConversations.map(\.preview), ["current preview"])
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
