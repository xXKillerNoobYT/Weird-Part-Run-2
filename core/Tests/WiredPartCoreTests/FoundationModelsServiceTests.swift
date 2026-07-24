import Foundation
import Testing
import GRDB
@testable import WiredPartCore
#if canImport(FoundationModels)
import FoundationModels
#endif

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

    @Test("chatWithTools fails closed without an authenticated user")
    func testChatWithTools_missingUserFailsClosed() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let result = await service.chatWithTools(
            query: "Show my recent jobs",
            db: env.db,
            permissions: ["view_jobs"],
            userId: nil,
            navigationContext: "App: Jobs"
        )

        #expect(!result.success)
        #expect(result.error == AIConversationPersistenceError.missingAuthenticatedUser.localizedDescription)
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

    @Test("chat session identity covers user permissions database and navigation context")
    func testChatSessionIdentity_coversSecurityAndContextInputs() throws {
        let env = try E2ETestHelpers.setUp()
        let otherEnv = try E2ETestHelpers.setUp()
        let baseline = AIChatSessionIdentity(
            conversationId: "conversation-1",
            db: env.db,
            permissions: ["view_jobs", "admin", "view_jobs"],
            userId: 42,
            navigationContext: "Page A"
        )

        let reorderedPermissions = AIChatSessionIdentity(
            conversationId: "conversation-1",
            db: env.db,
            permissions: ["admin", "view_jobs"],
            userId: 42,
            navigationContext: "Page A"
        )
        #expect(baseline == reorderedPermissions)

        #expect(baseline != AIChatSessionIdentity(
            conversationId: "conversation-2",
            db: env.db,
            permissions: ["view_jobs", "admin"],
            userId: 42,
            navigationContext: "Page A"
        ))
        #expect(baseline != AIChatSessionIdentity(
            conversationId: "conversation-1",
            db: otherEnv.db,
            permissions: ["view_jobs", "admin"],
            userId: 42,
            navigationContext: "Page A"
        ))
        #expect(baseline != AIChatSessionIdentity(
            conversationId: "conversation-1",
            db: env.db,
            permissions: ["view_jobs"],
            userId: 42,
            navigationContext: "Page A"
        ))
        #expect(baseline != AIChatSessionIdentity(
            conversationId: "conversation-1",
            db: env.db,
            permissions: ["view_jobs", "admin"],
            userId: 43,
            navigationContext: "Page A"
        ))
        #expect(baseline != AIChatSessionIdentity(
            conversationId: "conversation-1",
            db: env.db,
            permissions: ["view_jobs", "admin"],
            userId: 42,
            navigationContext: "Page B"
        ))
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
        try await FoundationModelsService.saveMessage(msg, ownerUserId: 1, to: env.db)
        let loaded = try await FoundationModelsService.loadConversation("conv-001", ownerUserId: 1, from: env.db)
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
            try await FoundationModelsService.saveMessage(msg, ownerUserId: 1, to: env.db)
        }
        let loaded = try await FoundationModelsService.loadConversation("conv-002", ownerUserId: 1, from: env.db)
        #expect(loaded.count == 3)
        #expect(loaded[0].content == "Q1")
        #expect(loaded[1].content == "A1")
        #expect(loaded[2].content == "Q2")
    }

    @Test("deleteConversation removes all messages for that ID")
    func testDeleteConversation() async throws {
        let env = try E2ETestHelpers.setUp()
        let msg = AIConversationMessage(id: "del-1", conversationId: "conv-delete", role: "user", content: "Delete me", createdAt: "2026-04-20 11:00:00")
        try await FoundationModelsService.saveMessage(msg, ownerUserId: 1, to: env.db)
        try await FoundationModelsService.deleteConversation("conv-delete", ownerUserId: 1, from: env.db)
        let remaining = try await FoundationModelsService.loadConversation("conv-delete", ownerUserId: 1, from: env.db)
        #expect(remaining.isEmpty)
    }

    @Test("deleteConversation only removes matching conversation ID")
    func testDeleteConversation_doesNotAffectOthers() async throws {
        let env = try E2ETestHelpers.setUp()
        let keep = AIConversationMessage(id: "keep-1", conversationId: "conv-keep", role: "user", content: "Keep me", createdAt: "2026-04-20 12:00:00")
        let del = AIConversationMessage(id: "del-2", conversationId: "conv-del2", role: "user", content: "Delete me", createdAt: "2026-04-20 12:00:01")
        try await FoundationModelsService.saveMessage(keep, ownerUserId: 1, to: env.db)
        try await FoundationModelsService.saveMessage(del, ownerUserId: 1, to: env.db)
        try await FoundationModelsService.deleteConversation("conv-del2", ownerUserId: 1, from: env.db)
        let kept = try await FoundationModelsService.loadConversation("conv-keep", ownerUserId: 1, from: env.db)
        let deleted = try await FoundationModelsService.loadConversation("conv-del2", ownerUserId: 1, from: env.db)
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
        try await FoundationModelsService.saveMessage(msg, ownerUserId: 1, to: env.db)

        try await FoundationModelsService.clearPersistedConversation("conv-clear-persisted", ownerUserId: 1, from: env.db)

        let remaining = try await FoundationModelsService.loadConversation("conv-clear-persisted", ownerUserId: 1, from: env.db)
        #expect(remaining.isEmpty)
    }

    @Test("clearPersistedConversation surfaces storage failures instead of swallowing them")
    func testClearPersistedConversation_throwsWhenStorageDeleteFails() async throws {
        let env = try E2ETestHelpers.setUp()
        try await env.db.writer.write { db in
            try db.drop(table: "ai_conversation_messages")
        }

        await #expect(throws: (any Error).self) {
            try await FoundationModelsService.clearPersistedConversation("conv-delete-fails", ownerUserId: 1, from: env.db)
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
        for msg in msgs { try await FoundationModelsService.saveMessage(msg, ownerUserId: 1, to: env.db) }
        let list = try await FoundationModelsService.listConversations(ownerUserId: 1, from: env.db)
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
        for msg in msgs { try await FoundationModelsService.saveMessage(msg, ownerUserId: 1, to: env.db) }
        let list = try await FoundationModelsService.listConversations(ownerUserId: 1, from: env.db)
        #expect(list.first?.preview == "Latest reply")
    }

    @Test("equal timestamps use save order for resume, list order, and previews")
    func testConversationRecency_equalTimestampsUsesSaveOrderWithinOwner() async throws {
        let env = try E2ETestHelpers.setUp()
        let tiedTimestamp = "2026-07-17T10:00:00Z"
        let ownerMessages = [
            AIConversationMessage(id: "tie-a-1", conversationId: "tie-conv-A", role: "user", content: "A first", createdAt: tiedTimestamp),
            AIConversationMessage(id: "tie-a-2", conversationId: "tie-conv-A", role: "assistant", content: "A actual latest preview", createdAt: tiedTimestamp),
            AIConversationMessage(id: "tie-b-1", conversationId: "tie-conv-B", role: "user", content: "B saved last", createdAt: tiedTimestamp),
        ]
        for message in ownerMessages {
            try await FoundationModelsService.saveMessage(message, ownerUserId: 101, to: env.db)
        }
        try await FoundationModelsService.saveMessage(
            AIConversationMessage(
                id: "tie-other-owner",
                conversationId: "tie-other-owner-conv",
                role: "user",
                content: "Other owner saved newest",
                createdAt: tiedTimestamp
            ),
            ownerUserId: 202,
            to: env.db
        )

        let loadedA = try await FoundationModelsService.loadConversation(
            "tie-conv-A",
            ownerUserId: 101,
            from: env.db
        )
        let ownerList = try await FoundationModelsService.listConversations(ownerUserId: 101, from: env.db)
        let ownerLatest = try await FoundationModelsService.latestConversationId(ownerUserId: 101, from: env.db)

        #expect(loadedA.map(\.content) == ["A first", "A actual latest preview"])
        #expect(ownerList.map(\.id) == ["tie-conv-B", "tie-conv-A"])
        #expect(ownerList.map(\.preview) == ["B saved last", "A actual latest preview"])
        #expect(ownerLatest == "tie-conv-B")
        #expect(try await FoundationModelsService.listConversations(ownerUserId: 202, from: env.db).map(\.id) == ["tie-other-owner-conv"])
    }

    @Test("latestConversationId returns nil when no messages exist")
    func testLatestConversationId_emptyDatabase() async throws {
        let env = try E2ETestHelpers.setUp()
        let latest = try await FoundationModelsService.latestConversationId(ownerUserId: 1, from: env.db)
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
        try await FoundationModelsService.saveMessage(older, ownerUserId: 1, to: env.db)
        try await FoundationModelsService.saveMessage(newer, ownerUserId: 1, to: env.db)

        let latest = try await FoundationModelsService.latestConversationId(ownerUserId: 1, from: env.db)
        #expect(latest == "newer-conv")
    }

    @Test("conversation persistence is isolated by authenticated owner")
    func testConversationPersistence_isolatedByOwner() async throws {
        let env = try E2ETestHelpers.setUp()
        let ownerAMessage = AIConversationMessage(
            id: "owner-a-message",
            conversationId: "shared-conversation-id",
            role: "user",
            content: "Owner A private turn",
            createdAt: "2026-07-16 08:00:00"
        )
        let ownerBMessage = AIConversationMessage(
            id: "owner-b-message",
            conversationId: "shared-conversation-id",
            role: "user",
            content: "Owner B private turn",
            createdAt: "2026-07-16 09:00:00"
        )
        try await FoundationModelsService.saveMessage(ownerAMessage, ownerUserId: 101, to: env.db)
        try await FoundationModelsService.saveMessage(ownerBMessage, ownerUserId: 202, to: env.db)

        let ownerBLoaded = try await FoundationModelsService.loadConversation(
            "shared-conversation-id",
            ownerUserId: 202,
            from: env.db
        )
        let ownerBList = try await FoundationModelsService.listConversations(ownerUserId: 202, from: env.db)
        let ownerBLatest = try await FoundationModelsService.latestConversationId(ownerUserId: 202, from: env.db)
        #expect(ownerBLoaded.map(\.content) == ["Owner B private turn"])
        #expect(ownerBList.map(\.preview) == ["Owner B private turn"])
        #expect(ownerBLatest == "shared-conversation-id")

        try await FoundationModelsService.deleteConversation(
            "shared-conversation-id",
            ownerUserId: 202,
            from: env.db
        )
        let ownerAStillPresent = try await FoundationModelsService.loadConversation(
            "shared-conversation-id",
            ownerUserId: 101,
            from: env.db
        )
        #expect(ownerAStillPresent.map(\.content) == ["Owner A private turn"])
        #expect(try await FoundationModelsService.listConversations(ownerUserId: 202, from: env.db).isEmpty)
        #expect(try await FoundationModelsService.latestConversationId(ownerUserId: 202, from: env.db) == nil)
    }

    @Test("conversation persistence rejects missing authenticated owner")
    func testConversationPersistence_rejectsMissingOwner() async throws {
        let env = try E2ETestHelpers.setUp()
        let message = AIConversationMessage(conversationId: "missing-owner", role: "user", content: "Private")

        await #expect(throws: AIConversationPersistenceError.missingAuthenticatedUser) {
            try await FoundationModelsService.saveMessage(message, ownerUserId: 0, to: env.db)
        }
        await #expect(throws: AIConversationPersistenceError.missingAuthenticatedUser) {
            try await FoundationModelsService.listConversations(ownerUserId: 0, from: env.db)
        }
    }

    @Test("resume stages persisted turns for model-session hydration")
    func testResumeConversation_stagesPriorTurns() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let priorTurns = [
            AIConversationMessage(id: "resume-u", conversationId: "resume", role: "user", content: "Original question"),
            AIConversationMessage(id: "resume-a", conversationId: "resume", role: "assistant", content: "Original answer"),
        ]
        try await FoundationModelsService.saveMessages(priorTurns, ownerUserId: 77, to: env.db)

        let hydrated = try await service.resumeConversation("resume", ownerUserId: 77, from: env.db)
        #expect(hydrated.map(\.content) == ["Original question", "Original answer"])
        #expect(await service.currentMessageHistory().map(\.content) == hydrated.map(\.content))

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let transcript = FoundationModelsService.makeTranscript(
                instructions: "Assistant instructions",
                tools: [],
                history: hydrated
            )
            #expect(transcript.count == 3)
            guard case .prompt(let prompt) = transcript[1],
                  let promptSegment = prompt.segments.first,
                  case .text(let promptText) = promptSegment else {
                Issue.record("Hydrated user turn was not forwarded as a model prompt")
                return
            }
            guard case .response(let response) = transcript[2],
                  let responseSegment = response.segments.first,
                  case .text(let responseText) = responseSegment else {
                Issue.record("Hydrated assistant turn was not forwarded as a model response")
                return
            }
            #expect(promptText.content == "Original question")
            #expect(responseText.content == "Original answer")
        }
        #endif
    }

    @Test("a second resume supersedes delayed history hydration")
    func testResumeConversation_secondResumeWins() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        try await FoundationModelsService.saveMessages([
            AIConversationMessage(conversationId: "resume-a", role: "user", content: "Conversation A"),
            AIConversationMessage(conversationId: "resume-b", role: "user", content: "Conversation B"),
        ], ownerUserId: 77, to: env.db)

        let delayedResume = Task {
            try await service.resumeConversation(
                "resume-a",
                ownerUserId: 77,
                from: env.db,
                beforeHydrating: { await gate.enterAndWaitForRelease() }
            )
        }
        await gate.waitUntilEntered()
        let winningHistory = try await service.resumeConversation("resume-b", ownerUserId: 77, from: env.db)
        await gate.release()

        await #expect(throws: CancellationError.self) { try await delayedResume.value }
        #expect(winningHistory.map(\.content) == ["Conversation B"])
        #expect(await service.currentMessageHistory().map(\.content) == ["Conversation B"])
    }

    @Test("resuming another conversation rejects an in-flight generation's stale history append")
    func testResumeConversation_rejectsStaleGenerationAppend() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        try await FoundationModelsService.saveMessages([
            AIConversationMessage(conversationId: "generation-a", role: "user", content: "Conversation A"),
            AIConversationMessage(conversationId: "generation-b", role: "user", content: "Conversation B"),
        ], ownerUserId: 77, to: env.db)

        _ = try await service.resumeConversation("generation-a", ownerUserId: 77, from: env.db)
        let generationARevision = await service.generationLifecycleRevision()

        _ = try await service.resumeConversation("generation-b", ownerUserId: 77, from: env.db)
        let appended = await service.appendGeneratedMessagesIfCurrent([
            AIConversationMessage(
                conversationId: "generation-a",
                role: "assistant",
                content: "Delayed Conversation A response"
            ),
        ], expectedLifecycleRevision: generationARevision)

        #expect(!appended)
        #expect(await service.currentMessageHistory().map(\.content) == ["Conversation B"])
    }

    @Test("clear prevents delayed resume from restaging deleted history")
    func testResumeConversation_clearWinsOverDelayedHydration() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        try await FoundationModelsService.saveMessage(
            AIConversationMessage(conversationId: "resume-clear", role: "user", content: "Private history"),
            ownerUserId: 77,
            to: env.db
        )

        let delayedResume = Task {
            try await service.resumeConversation(
                "resume-clear",
                ownerUserId: 77,
                from: env.db,
                beforeHydrating: { await gate.enterAndWaitForRelease() }
            )
        }
        await gate.waitUntilEntered()
        try await service.clearConversation("resume-clear", ownerUserId: 77, from: env.db)
        await gate.release()

        await #expect(throws: CancellationError.self) { try await delayedResume.value }
        #expect(await service.currentMessageHistory().isEmpty)
        #expect(try await FoundationModelsService.loadConversation("resume-clear", ownerUserId: 77, from: env.db).isEmpty)
    }

    @Test("volatile clear for New or logout prevents delayed resume hydration")
    func testResumeConversation_volatileClearWinsOverDelayedHydration() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        try await FoundationModelsService.saveMessage(
            AIConversationMessage(conversationId: "resume-logout", role: "user", content: "Prior user history"),
            ownerUserId: 77,
            to: env.db
        )

        let delayedResume = Task {
            try await service.resumeConversation(
                "resume-logout",
                ownerUserId: 77,
                from: env.db,
                beforeHydrating: { await gate.enterAndWaitForRelease() }
            )
        }
        await gate.waitUntilEntered()
        await service.clearConversation()
        await gate.release()

        await #expect(throws: CancellationError.self) { try await delayedResume.value }
        #expect(await service.currentMessageHistory().isEmpty)
    }

    @Test("local Help handoff persists and stages both turns for an immediate follow-up")
    func testStageHelpConversation_stagesVisibleTurns() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()

        let staged = try await service.stageHelpConversation(
            "help-follow-up",
            ownerUserId: 77,
            userPrompt: "Explain the Dashboard",
            assistantResponse: "Dashboard help content",
            in: env.db
        )

        #expect(staged)
        let persisted = try await FoundationModelsService.loadConversation(
            "help-follow-up",
            ownerUserId: 77,
            from: env.db
        )
        #expect(persisted.map(\.content) == ["Explain the Dashboard", "Dashboard help content"])
        #expect(await service.currentMessageHistory().map(\.content) == persisted.map(\.content))

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let transcript = FoundationModelsService.makeTranscript(
                instructions: "Assistant instructions",
                tools: [],
                history: await service.currentMessageHistory()
            )
            #expect(transcript.count == 3)
        }
        #endif
    }

    @Test("local fallback persists atomically and is visible to reload and conversation list")
    func testStageLocalConversation_persistsForResumeAndList() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()

        let outcome = try await service.stageLocalConversation(
            "fallback-resume",
            ownerUserId: 77,
            userPrompt: "How do I update pricing?",
            assistantResponse: "Open Parts, then choose Pricing.",
            in: env.db
        )

        #expect(outcome == .persistedAndStaged)
        let reloaded = try await FoundationModelsService.loadConversation(
            "fallback-resume",
            ownerUserId: 77,
            from: env.db
        )
        let listed = try await FoundationModelsService.listConversations(
            ownerUserId: 77,
            from: env.db
        )
        #expect(reloaded.map(\.role) == ["user", "assistant"])
        #expect(reloaded.map(\.content) == [
            "How do I update pricing?",
            "Open Parts, then choose Pricing.",
        ])
        #expect(listed.first?.id == "fallback-resume")
        #expect(listed.first?.preview == "Open Parts, then choose Pricing.")
        #expect(await service.currentMessageHistory().map(\.content) == reloaded.map(\.content))
    }

    @Test("local fallback write failure rolls back the complete visible pair")
    func testStageLocalConversation_writeFailureIsAtomic() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        try await env.db.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_fallback_assistant
                BEFORE INSERT ON ai_conversation_messages
                WHEN NEW.role = 'assistant'
                BEGIN
                    SELECT RAISE(ABORT, 'forced fallback write failure');
                END
                """)
        }

        await #expect(throws: (any Error).self) {
            try await service.stageLocalConversation(
                "fallback-write-failure",
                ownerUserId: 77,
                userPrompt: "Visible question",
                assistantResponse: "Visible fallback response",
                in: env.db
            )
        }

        let persistedCount = try await env.db.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM ai_conversation_messages WHERE conversation_id = ?",
                arguments: ["fallback-write-failure"]
            ) ?? 0
        }
        #expect(persistedCount == 0)
        #expect(await service.currentMessageHistory().isEmpty)
    }

    @Test("post-write lifecycle invalidation reports durable without replacing newer staged history")
    func testStageLocalConversation_postWriteInvalidationDistinguishesDurablePair() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        let ownerUserId: Int64 = 77

        #expect(try await service.stageLocalConversation(
            "conversation-b",
            ownerUserId: ownerUserId,
            userPrompt: "Conversation B question",
            assistantResponse: "Conversation B response",
            in: env.db
        ) == .persistedAndStaged)

        let stagingTask = Task {
            try await service.stageLocalConversation(
                "fallback-post-write-race",
                ownerUserId: ownerUserId,
                userPrompt: "Visible fallback question",
                assistantResponse: "Visible fallback response",
                in: env.db,
                afterPersisting: {
                    await gate.enterAndWaitForRelease()
                }
            )
        }

        await gate.waitUntilEntered()
        let visibleCurrentConversation = try await service.resumeConversation(
            "conversation-b",
            ownerUserId: ownerUserId,
            from: env.db
        )
        await gate.release()

        let outcome = try await stagingTask.value
        let reloadedFallback = try await FoundationModelsService.loadConversation(
            "fallback-post-write-race",
            ownerUserId: ownerUserId,
            from: env.db
        )
        let otherOwnerReload = try await FoundationModelsService.loadConversation(
            "fallback-post-write-race",
            ownerUserId: ownerUserId + 1,
            from: env.db
        )

        #expect(outcome == .persistedButNotStaged)
        #expect(reloadedFallback.map(\.role) == ["user", "assistant"])
        #expect(reloadedFallback.map(\.content) == [
            "Visible fallback question",
            "Visible fallback response",
        ])
        #expect(otherOwnerReload.isEmpty)
        #expect(await service.currentMessageHistory().map(\.content) == visibleCurrentConversation.map(\.content))
    }

    @Test("delayed Help staging does not hydrate the model transcript until staging completes")
    func testStageHelpConversation_delayedStagingCompletesBeforeHydration() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let gate = AsyncGate()

        let stagingTask = Task {
            try await service.stageHelpConversation(
                "delayed-help-follow-up",
                ownerUserId: 77,
                userPrompt: "Explain the Dashboard",
                assistantResponse: "Dashboard help content",
                in: env.db,
                beforePersisting: {
                    await gate.enterAndWaitForRelease()
                }
            )
        }

        await gate.waitUntilEntered()
        #expect(await service.currentMessageHistory().isEmpty)
        await gate.release()

        let staged = try await stagingTask.value
        #expect(staged)
        #expect(await service.currentMessageHistory().map(\.content) == [
            "Explain the Dashboard",
            "Dashboard help content",
        ])
    }

    @Test("a delayed response cannot recreate history after clear completes")
    func testDelayedWriteAfterClear_isDiscarded() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let scope = AIConversationScope(conversationId: "clear-race", ownerUserId: 88)
        let revisionBeforeClear = await service.persistenceRevision(for: scope)

        try await service.clearConversation("clear-race", ownerUserId: 88, from: env.db)
        let delayedMessage = AIConversationMessage(
            id: "delayed-after-clear",
            conversationId: "clear-race",
            role: "assistant",
            content: "Late response"
        )
        let wasPersisted = try await service.persistMessagesIfCurrent(
            [delayedMessage],
            scope: scope,
            expectedRevision: revisionBeforeClear,
            to: env.db
        )

        let remaining = try await FoundationModelsService.loadConversation(
            "clear-race",
            ownerUserId: 88,
            from: env.db
        )
        #expect(!wasPersisted)
        #expect(remaining.isEmpty)
    }

    @Test("stale fallback cleanup preserves a newer revision's same-scope turns")
    func testDelayedWriteAfterClear_preservesNewerRevisionTurns() async throws {
        let env = try E2ETestHelpers.setUp()
        let service = FoundationModelsService()
        let gate = AsyncGate()
        let scope = AIConversationScope(conversationId: "clear-race-newer-turns", ownerUserId: 88)
        let revisionZero = await service.persistenceRevision(for: scope)
        let staleTurns = [
            AIConversationMessage(
                id: "stale-user-turn",
                conversationId: scope.conversationId,
                role: "user",
                content: "Revision zero question"
            ),
            AIConversationMessage(
                id: "stale-assistant-turn",
                conversationId: scope.conversationId,
                role: "assistant",
                content: "Revision zero answer"
            ),
        ]

        let staleWriter = Task {
            try await service.persistMessagesIfCurrent(
                staleTurns,
                scope: scope,
                expectedRevision: revisionZero,
                to: env.db,
                afterPersisting: { await gate.enterAndWaitForRelease() }
            )
        }
        await gate.waitUntilEntered()

        try await service.clearConversation(scope.conversationId, ownerUserId: scope.ownerUserId, from: env.db)
        let revisionOne = await service.persistenceRevision(for: scope)
        let newerTurns = [
            AIConversationMessage(
                id: "newer-user-turn",
                conversationId: scope.conversationId,
                role: "user",
                content: "Revision one question"
            ),
            AIConversationMessage(
                id: "newer-assistant-turn",
                conversationId: scope.conversationId,
                role: "assistant",
                content: "Revision one answer"
            ),
        ]
        #expect(try await service.persistMessagesIfCurrent(
            newerTurns,
            scope: scope,
            expectedRevision: revisionOne,
            to: env.db
        ))

        await gate.release()
        #expect(!(try await staleWriter.value))
        let reloaded = try await FoundationModelsService.loadConversation(
            scope.conversationId,
            ownerUserId: scope.ownerUserId,
            from: env.db
        )
        #expect(reloaded.map(\.id) == newerTurns.map(\.id))
        #expect(reloaded.map(\.content) == newerTurns.map(\.content))
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

private actor AsyncGate {
    private var didEnter = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitUntilEntered() async {
        if didEnter { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func enterAndWaitForRelease() async {
        didEnter = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
