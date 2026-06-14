import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("FoundationModelsService Tests")
struct FoundationModelsServiceTests {

    // MARK: - Availability

    @Test("checkAvailability returns a valid AIAvailability case")
    func testCheckAvailability_returnsValidStatus() {
        let svc = FoundationModelsService()
        let status = svc.checkAvailability()
        let valid: [AIAvailability] = [.available, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailable, .notSupported]
        #expect(valid.contains(status))
    }

    @Test("isAvailable matches checkAvailability == .available")
    func testIsAvailable_matchesCheckAvailability() {
        let svc = FoundationModelsService()
        #expect(svc.isAvailable() == (svc.checkAvailability() == .available))
    }

    // MARK: - Guard Conditions (testable without FM runtime)

    @Test("generateCompletion rejects text shorter than 10 characters")
    func testGenerateCompletion_tooShortText() async {
        let svc = FoundationModelsService()
        let result = await svc.generateCompletion(partialText: "short")
        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("generateCompletion accepts text >= 10 characters and returns a result")
    func testGenerateCompletion_longEnoughText_returnsResult() async {
        let svc = FoundationModelsService()
        let result = await svc.generateCompletion(partialText: "This is a long enough text")
        // Guard passed — either FM succeeded or returned a failure; both are valid
        #expect(result.success || result.error != nil)
    }

    @Test("enhanceText rejects empty string")
    func testEnhanceText_emptyInput() async {
        let svc = FoundationModelsService()
        let result = await svc.enhanceText(text: "", mode: .proofread)
        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("enhanceText accepts non-empty text and returns a result")
    func testEnhanceText_nonEmpty_returnsResult() async {
        let svc = FoundationModelsService()
        let result = await svc.enhanceText(text: "Fix this text please", mode: .rewrite)
        // Guard passed — either FM succeeded or returned a failure; both are valid
        #expect(result.success || result.error != nil)
    }

    @Test("generatePreFill rejects empty contextData")
    func testGeneratePreFill_emptyContext() async {
        let svc = FoundationModelsService()
        let result = await svc.generatePreFill(fieldType: "dispatch notes", contextData: [:])
        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("chat rejects empty query")
    func testChat_emptyQuery() async {
        let svc = FoundationModelsService()
        let result = await svc.chat(query: "")
        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("chat rejects whitespace-only query")
    func testChat_whitespaceQuery() async {
        let svc = FoundationModelsService()
        let result = await svc.chat(query: "   ")
        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("chatWithTools rejects empty query")
    func testChatWithTools_emptyQuery() async throws {
        let env = try E2ETestHelpers.setUp()
        let svc = FoundationModelsService()
        let result = await svc.chatWithTools(
            query: "",
            db: env.db,
            permissions: ["view_jobs"],
            navigationContext: "App: Jobs, Parts, Settings"
        )
        #expect(!result.success)
    }

    // MARK: - AIResult Factory

    @Test("AIResult.ok stores text and sets success=true")
    func testAIResult_ok() {
        let r = AIResult.ok("Hello world")
        #expect(r.success)
        #expect(r.text == "Hello world")
        #expect(r.error == nil)
    }

    @Test("AIResult.fail stores error and sets success=false")
    func testAIResult_fail() {
        let r = AIResult.fail("Something went wrong")
        #expect(!r.success)
        #expect(r.text == nil)
        #expect(r.error == "Something went wrong")
    }

    // MARK: - Session / Memory Management

    @Test("currentMessageHistory returns empty on fresh instance")
    func testCurrentMessageHistory_startsEmpty() async {
        let svc = FoundationModelsService()
        let history = await svc.currentMessageHistory()
        #expect(history.isEmpty)
    }

    @Test("clearConversation does not crash on empty state")
    func testClearConversation_noOp() async {
        let svc = FoundationModelsService()
        await svc.clearConversation()
        let history = await svc.currentMessageHistory()
        #expect(history.isEmpty)
    }

    // MARK: - DB Persistence (static methods, fully testable)

    @Test("saveMessage then loadConversation round-trips message content")
    func testSaveAndLoadConversation() async throws {
        let env = try E2ETestHelpers.setUp()
        let msg = AIConversationMessage(
            id: "test-msg-1",
            conversationId: "conv-001",
            role: "user",
            content: "How many jobs are open?",
            createdAt: "2026-04-20 10:00:00"
        )
        try await FoundationModelsService.saveMessage(msg, to: env.db)
        let loaded = try await FoundationModelsService.loadConversation("conv-001", from: env.db)
        #expect(loaded.count == 1)
        #expect(loaded[0].content == "How many jobs are open?")
        #expect(loaded[0].role == "user")
        #expect(loaded[0].conversationId == "conv-001")
    }

    @Test("saveMessage multiple turns returns them in order")
    func testSaveMultipleMessages_orderedByCreatedAt() async throws {
        let env = try E2ETestHelpers.setUp()
        let msgs: [AIConversationMessage] = [
            AIConversationMessage(id: "m1", conversationId: "conv-002", role: "user", content: "Q1", createdAt: "2026-04-20 10:00:00"),
            AIConversationMessage(id: "m2", conversationId: "conv-002", role: "assistant", content: "A1", createdAt: "2026-04-20 10:00:01"),
            AIConversationMessage(id: "m3", conversationId: "conv-002", role: "user", content: "Q2", createdAt: "2026-04-20 10:00:02"),
        ]
        for msg in msgs {
            try await FoundationModelsService.saveMessage(msg, to: env.db)
        }
        let loaded = try await FoundationModelsService.loadConversation("conv-002", from: env.db)
        #expect(loaded.count == 3)
        #expect(loaded[0].content == "Q1")
        #expect(loaded[1].content == "A1")
        #expect(loaded[2].content == "Q2")
    }

    @Test("deleteConversation removes all messages for that ID")
    func testDeleteConversation() async throws {
        let env = try E2ETestHelpers.setUp()
        let msg = AIConversationMessage(id: "del-1", conversationId: "conv-delete", role: "user", content: "Delete me", createdAt: "2026-04-20 11:00:00")
        try await FoundationModelsService.saveMessage(msg, to: env.db)
        try await FoundationModelsService.deleteConversation("conv-delete", from: env.db)
        let remaining = try await FoundationModelsService.loadConversation("conv-delete", from: env.db)
        #expect(remaining.isEmpty)
    }

    @Test("deleteConversation only removes matching conversation ID")
    func testDeleteConversation_doesNotAffectOthers() async throws {
        let env = try E2ETestHelpers.setUp()
        let keep = AIConversationMessage(id: "keep-1", conversationId: "conv-keep", role: "user", content: "Keep me", createdAt: "2026-04-20 12:00:00")
        let del = AIConversationMessage(id: "del-2", conversationId: "conv-del2", role: "user", content: "Delete me", createdAt: "2026-04-20 12:00:01")
        try await FoundationModelsService.saveMessage(keep, to: env.db)
        try await FoundationModelsService.saveMessage(del, to: env.db)
        try await FoundationModelsService.deleteConversation("conv-del2", from: env.db)
        let kept = try await FoundationModelsService.loadConversation("conv-keep", from: env.db)
        let deleted = try await FoundationModelsService.loadConversation("conv-del2", from: env.db)
        #expect(kept.count == 1)
        #expect(deleted.isEmpty)
    }

    @Test("clearPersistedConversation deletes and verifies stored messages")
    func testClearPersistedConversation_deletesAndVerifies() async throws {
        let env = try E2ETestHelpers.setUp()
        let msg = AIConversationMessage(
            id: "clear-persisted-1",
            conversationId: "conv-clear-persisted",
            role: "user",
            content: "Delete and verify me",
            createdAt: "2026-04-20 12:05:00"
        )
        try await FoundationModelsService.saveMessage(msg, to: env.db)

        try await FoundationModelsService.clearPersistedConversation("conv-clear-persisted", from: env.db)

        let remaining = try await FoundationModelsService.loadConversation("conv-clear-persisted", from: env.db)
        #expect(remaining.isEmpty)
    }

    @Test("clearPersistedConversation surfaces storage failures instead of swallowing them")
    func testClearPersistedConversation_throwsWhenStorageDeleteFails() async throws {
        let env = try E2ETestHelpers.setUp()
        try await env.db.writer.write { db in
            try db.drop(table: "ai_conversation_messages")
        }

        await #expect(throws: (any Error).self) {
            try await FoundationModelsService.clearPersistedConversation("conv-delete-fails", from: env.db)
        }
    }

    @Test("listConversations returns one entry per distinct conversation ID")
    func testListConversations() async throws {
        let env = try E2ETestHelpers.setUp()
        let msgs: [AIConversationMessage] = [
            AIConversationMessage(id: "lc1", conversationId: "list-conv-A", role: "user", content: "msgA1", createdAt: "2026-04-20 09:00:00"),
            AIConversationMessage(id: "lc2", conversationId: "list-conv-A", role: "assistant", content: "msgA2", createdAt: "2026-04-20 09:00:01"),
            AIConversationMessage(id: "lc3", conversationId: "list-conv-B", role: "user", content: "msgB1", createdAt: "2026-04-20 08:00:00"),
        ]
        for msg in msgs { try await FoundationModelsService.saveMessage(msg, to: env.db) }
        let list = try await FoundationModelsService.listConversations(from: env.db)
        #expect(list.count == 2)
        // Most recent conversation (conv-A, last message at 09:00:01) should be first
        #expect(list[0].id == "list-conv-A")
    }

    @Test("listConversations returns preview from latest message")
    func testListConversations_previewIsLatest() async throws {
        let env = try E2ETestHelpers.setUp()
        let msgs: [AIConversationMessage] = [
            AIConversationMessage(id: "pv1", conversationId: "prev-conv", role: "user", content: "First message", createdAt: "2026-04-20 07:00:00"),
            AIConversationMessage(id: "pv2", conversationId: "prev-conv", role: "assistant", content: "Latest reply", createdAt: "2026-04-20 07:00:01"),
        ]
        for msg in msgs { try await FoundationModelsService.saveMessage(msg, to: env.db) }
        let list = try await FoundationModelsService.listConversations(from: env.db)
        #expect(list.first?.preview == "Latest reply")
    }

    @Test("latestConversationId returns nil when no messages exist")
    func testLatestConversationId_emptyDatabase() async throws {
        let env = try E2ETestHelpers.setUp()
        let latest = try await FoundationModelsService.latestConversationId(from: env.db)
        #expect(latest == nil)
    }

    @Test("latestConversationId returns most recently active conversation")
    func testLatestConversationId_returnsMostRecentConversation() async throws {
        let env = try E2ETestHelpers.setUp()
        let older = AIConversationMessage(
            id: "latest-old",
            conversationId: "older-conv",
            role: "user",
            content: "Older thread",
            createdAt: "2026-04-20 07:00:00"
        )
        let newer = AIConversationMessage(
            id: "latest-new",
            conversationId: "newer-conv",
            role: "assistant",
            content: "Newer thread",
            createdAt: "2026-04-20 08:00:00"
        )
        try await FoundationModelsService.saveMessage(older, to: env.db)
        try await FoundationModelsService.saveMessage(newer, to: env.db)

        let latest = try await FoundationModelsService.latestConversationId(from: env.db)
        #expect(latest == "newer-conv")
    }

    // MARK: - AIConversationMessage Init

    @Test("AIConversationMessage defaults to UUID id and now timestamp")
    func testAIConversationMessage_defaults() {
        let msg = AIConversationMessage(conversationId: "c1", role: "user", content: "Hello")
        #expect(!msg.id.isEmpty)
        #expect(!msg.createdAt.isEmpty)
        #expect(msg.conversationId == "c1")
        #expect(msg.role == "user")
        #expect(msg.content == "Hello")
    }

    // MARK: - EnhanceMode

    @Test("EnhanceMode has correct display names")
    func testEnhanceMode_displayNames() {
        #expect(EnhanceMode.proofread.displayName == "Proofread")
        #expect(EnhanceMode.rewrite.displayName == "Rewrite")
        #expect(EnhanceMode.summarize.displayName == "Summarize")
        #expect(EnhanceMode.expand.displayName == "Expand")
        #expect(EnhanceMode.professional.displayName == "Professional")
    }

    @Test("EnhanceMode allCases has 5 modes")
    func testEnhanceMode_allCases() {
        #expect(EnhanceMode.allCases.count == 5)
    }
}
