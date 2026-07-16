import Foundation
import GRDB

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Availability

/// Describes the availability status of the on-device AI model.
public enum AIAvailability: String, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable
    case notSupported // Platform too old
}

// MARK: - Enhance Mode

/// Text enhancement modes matching the TypeScript implementation.
public enum EnhanceMode: String, Sendable, CaseIterable {
    case proofread
    case rewrite
    case summarize
    case expand
    case professional

    public var displayName: String {
        rawValue.capitalized
    }

    public var systemImage: String {
        switch self {
        case .proofread: return "text.magnifyingglass"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .summarize: return "text.badge.minus"
        case .expand: return "text.badge.plus"
        case .professional: return "briefcase"
        }
    }
}

// MARK: - AI Result

/// Result of an AI text generation operation.
public struct AIResult: Sendable {
    public let success: Bool
    public let text: String?
    public let error: String?

    public static func ok(_ text: String) -> AIResult {
        AIResult(success: true, text: text, error: nil)
    }

    public static func fail(_ error: String) -> AIResult {
        AIResult(success: false, text: nil, error: error)
    }
}

// MARK: - Foundation Models Service

/// A single message in an AI conversation, suitable for DB persistence.
public struct AIConversationMessage: Sendable, Codable {
    public let id: String
    public let conversationId: String
    public let role: String   // "user" or "assistant"
    public let content: String
    public let createdAt: String

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        role: String,
        content: String,
        createdAt: String = CoreFormatters.nowISO()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum AIConversationPersistenceError: LocalizedError, Sendable, Equatable {
    case missingAuthenticatedUser
    case deleteVerificationFailed(conversationId: String, remainingMessageCount: Int)

    public var errorDescription: String? {
        switch self {
        case .missingAuthenticatedUser:
            "An authenticated user is required to access AI conversation history."
        case .deleteVerificationFailed(let conversationId, let remainingMessageCount):
            "Conversation \(conversationId) still has \(remainingMessageCount) stored message(s) after deletion."
        }
    }
}

struct AIConversationScope: Hashable, Sendable {
    let conversationId: String
    let ownerUserId: Int64
}

/// Identifies the security- and context-bearing inputs used to build a chat session.
///
/// Foundation Models sessions capture tool instances and instructions at creation time,
/// so a cached session is safe to reuse only when every field here is unchanged.
struct AIChatSessionIdentity: Equatable, Sendable {
    let conversationId: String
    let databaseIdentity: String
    let userId: Int64?
    let permissionKeys: [String]
    let navigationContext: String

    init(
        conversationId: String,
        db: AppDatabase,
        permissions: [String],
        userId: Int64?,
        navigationContext: String
    ) {
        self.conversationId = conversationId
        self.databaseIdentity = String(describing: ObjectIdentifier(db))
        self.userId = userId
        self.permissionKeys = Array(Set(permissions)).sorted()
        self.navigationContext = navigationContext
    }
}

/// Provides on-device AI text generation via Apple Foundation Models.
///
/// This service wraps `LanguageModelSession` to provide:
/// - Availability checking
/// - Text completion (autocomplete suggestions)
/// - Text enhancement (proofread, rewrite, summarize, expand, professional)
/// - Pre-fill generation for empty fields
/// - Persistent chat sessions with conversation memory
///
/// All methods are safe to call on any platform. On platforms where
/// Foundation Models is not available, methods return graceful fallbacks.
public actor FoundationModelsService {
    /// Maximum characters of context to send to the model.
    private let maxContextChars: Int

    /// System instructions for the electrical contracting domain.
    private let domainInstructions = """
        You are an AI assistant for an electrical contracting business management app \
        called WiredPart. Write in a professional, trade-appropriate tone. Keep responses \
        concise and practical. Use terminology common in electrical contracting, \
        construction, and trade work.
        """

    // MARK: - Conversation Memory

    /// The active Foundation Models chat session, kept alive so follow-up messages
    /// share context. Stored as `Any` to avoid referencing FM types outside the
    /// `#if canImport(FoundationModels)` guard. The actual type is `LanguageModelSession`.
    #if canImport(FoundationModels)
    private var activeChatSession: (any Sendable)?
    #endif

    /// Conversation ID that the current active session belongs to.
    private var activeChatConversationId: String?

    /// Security/context identity that the current active session was built with.
    private var activeChatSessionIdentity: AIChatSessionIdentity?

    /// In-memory message history for the current conversation.
    private var messageHistory: [AIConversationMessage] = []

    /// Identifies history explicitly loaded for the next Foundation Models session.
    private var hydratedConversationScope: AIConversationScope?

    /// Invalidates a model response when its conversation is cleared while generation is in flight.
    private var conversationRevisions: [AIConversationScope: Int] = [:]

    public init(maxContextChars: Int = 1000) {
        self.maxContextChars = maxContextChars
    }

    // MARK: - Availability

    /// Check whether the on-device AI model is available.
    /// This is nonisolated because it only reads immutable system state.
    public nonisolated func checkAvailability() -> AIAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable:
                return .unavailable
            }
        } else {
            return .notSupported
        }
        #else
        return .notSupported
        #endif
    }

    /// Convenience: returns true only when the model is fully available.
    public nonisolated func isAvailable() -> Bool {
        checkAvailability() == .available
    }

    // MARK: - Text Completion

    /// Generate an inline autocomplete suggestion for partial text.
    ///
    /// - Parameters:
    ///   - partialText: The text the user has typed so far.
    ///   - fieldType: Description of the field (e.g. "job notes", "dispatch notes").
    ///   - contextData: Additional context key-value pairs.
    /// - Returns: An `AIResult` containing the suggested continuation text.
    public func generateCompletion(
        partialText: String,
        fieldType: String? = nil,
        contextData: [String: String]? = nil
    ) async -> AIResult {
        guard partialText.count >= 10 else {
            return .fail("Text too short for completion")
        }

        let trimmed = String(partialText.suffix(maxContextChars))

        var instructions = domainInstructions + "\n\n"
        instructions += "Complete the following text naturally. "
        instructions += "Only output the continuation — do not repeat any of the existing text. "
        instructions += "Keep the continuation brief (1-2 sentences max)."

        if let fieldType {
            instructions += "\nThis text is for a \(fieldType) field."
        }

        var prompt = trimmed
        if let contextData, !contextData.isEmpty {
            let contextStr = contextData.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            prompt = "Context: \(contextStr)\n\nText to complete: \(trimmed)"
        }

        return await generate(instructions: instructions, prompt: prompt)
    }

    // MARK: - Text Enhancement

    /// Enhance existing text using the specified mode.
    ///
    /// - Parameters:
    ///   - text: The original text to enhance.
    ///   - mode: The enhancement mode (proofread, rewrite, etc.).
    ///   - fieldType: Description of the field context.
    /// - Returns: An `AIResult` containing the enhanced text.
    public func enhanceText(
        text: String,
        mode: EnhanceMode,
        fieldType: String? = nil
    ) async -> AIResult {
        guard !text.isEmpty else {
            return .fail("No text to enhance")
        }

        var instructions = domainInstructions + "\n\n"

        switch mode {
        case .proofread:
            instructions += """
                Fix spelling, grammar, and punctuation errors. \
                Keep the original meaning and style. \
                Only output the corrected text.
                """
        case .rewrite:
            instructions += """
                Rewrite the following text to be clearer and more professional. \
                Keep the same meaning. Only output the rewritten text.
                """
        case .summarize:
            instructions += """
                Summarize the following text in 1-3 concise sentences. \
                Focus on the key information. Only output the summary.
                """
        case .expand:
            instructions += """
                Expand the following text with more detail and context. \
                Keep the professional tone. Only output the expanded text.
                """
        case .professional:
            instructions += """
                Rewrite the following text in a formal, professional business tone. \
                Keep the same meaning. Only output the professional version.
                """
        }

        if let fieldType {
            instructions += "\nThis text is for a \(fieldType) field."
        }

        return await generate(instructions: instructions, prompt: text)
    }

    // MARK: - Conflict Merge

    /// Attempt to merge two text-compatible conflict versions.
    public func mergeTextConflict(
        localText: String,
        remoteText: String,
        context: String? = nil
    ) async -> AIResult {
        guard !localText.isBlankRequiredText ||
              !remoteText.isBlankRequiredText else {
            return .fail("No text to merge")
        }

        var instructions = domainInstructions + "\n\n"
        instructions += """
            Merge two conflicting notebook block versions into one clear version. \
            Preserve all distinct factual details from both versions. \
            Do not invent details. If details disagree, include both in a concise \
            way that signals the discrepancy for manual review. \
            Only output the merged notebook text.
            """
        if let context, !context.isEmpty {
            instructions += "\nContext: \(context)"
        }

        let prompt = """
            Local version:
            \(localText)

            Remote version:
            \(remoteText)
            """
        return await generate(instructions: instructions, prompt: prompt)
    }

    // MARK: - Pre-Fill Generation

    /// Generate draft content for an empty field based on context.
    ///
    /// - Parameters:
    ///   - fieldType: The type of field to pre-fill (e.g. "dispatch notes", "job description").
    ///   - contextData: Key-value pairs providing context (e.g. jobName, crewLead, date).
    /// - Returns: An `AIResult` containing the generated draft text.
    public func generatePreFill(
        fieldType: String,
        contextData: [String: String]
    ) async -> AIResult {
        guard !contextData.isEmpty else {
            return .fail("No context data provided")
        }

        var instructions = domainInstructions + "\n\n"
        instructions += """
            Generate a draft for a \(fieldType) field. \
            Use the provided context to create appropriate content. \
            Keep it concise and professional. \
            Only output the draft text — no labels or formatting.
            """

        let contextStr = contextData.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
        let prompt = "Generate a \(fieldType) using this context:\n\(contextStr)"

        return await generate(instructions: instructions, prompt: prompt)
    }

    // MARK: - Chat / Q&A

    /// Respond to a general natural-language question about the business.
    ///
    /// - Parameter query: The user's question.
    /// - Returns: An `AIResult` containing the assistant's response.
    public func chat(query: String) async -> AIResult {
        guard !query.isBlankRequiredText else {
            return .fail("Empty query")
        }

        let instructions = domainInstructions + "\n\n" + """
            Answer the user's question helpfully and concisely. \
            If the question is about app navigation, explain where to find the feature. \
            If you don't have enough information, say so honestly. \
            Keep responses under 3 sentences when possible.
            """

        return await generate(instructions: instructions, prompt: query)
    }

    // MARK: - Chat with Tools (Database Access)

    /// Respond to a question using Foundation Models tool calling for real database access.
    ///
    /// The session is persisted across calls for the same `conversationId`, so the model
    /// remembers prior turns. Passing a different `conversationId` (or calling
    /// `clearConversation()`) creates a fresh session.
    ///
    /// Tools are automatically called by the framework when the model decides they're needed.
    /// Each tool respects user permissions — queries for data the user can't see return
    /// a permission-denied message instead of results.
    ///
    /// - Parameters:
    ///   - query: The user's question.
    ///   - db: The app database for tool queries.
    ///   - permissions: The current user's permission keys.
    ///   - userId: The signed-in user's id, or `nil` when no user session exists.
    ///     When `nil` (or the legacy `0` sentinel), user-specific tools fail closed
    ///     with a not-signed-in message instead of querying as user 0 (#724).
    ///   - navigationContext: A string describing the app's module/tab layout with access annotations.
    ///   - conversationId: Identifier for this conversation thread. Defaults to `"default"`.
    /// - Returns: An `AIResult` containing the assistant's response.
    public func chatWithTools(
        query: String,
        db: AppDatabase,
        permissions: [String],
        userId: Int64? = nil,
        navigationContext: String,
        conversationId: String = "default"
    ) async -> AIResult {
        guard !query.isBlankRequiredText else {
            return .fail("Empty query")
        }
        guard let ownerUserId = userId, ownerUserId > 0 else {
            return .fail(AIConversationPersistenceError.missingAuthenticatedUser.localizedDescription)
        }

        let conversationScope = AIConversationScope(
            conversationId: conversationId,
            ownerUserId: ownerUserId
        )
        let startingRevision = conversationRevisions[conversationScope, default: 0]

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            do {
                let tools: [any FoundationModels.Tool] = [
                    SearchPartsTool(db: db, permissions: permissions),
                    SearchContactsTool(db: db, permissions: permissions),
                    SearchJobsTool(db: db, permissions: permissions),
                    GetSupplierInfoTool(db: db, permissions: permissions),
                    ListCompanionRulesTool(db: db, permissions: permissions),
                    GetActiveCompanionPollsTool(db: db, permissions: permissions, userId: userId),
                    ExplainCoOccurrenceTool(db: db, permissions: permissions),
                    GetVotingSummaryTool(db: db, permissions: permissions, userId: userId),
                    GetForecastDataTool(db: db, permissions: permissions),
                ]

                let chatInstructions = domainInstructions + "\n\n" + """
                    You are a helpful assistant for the WiredPart app. You have access to tools \
                    that can search the local database for parts, contacts, jobs, and suppliers. \
                    Use these tools when the user asks about specific data. \
                    \
                    When answering navigation questions, use the app layout below to direct users \
                    to the correct module and tab. If a section is marked [NO ACCESS], tell the user \
                    they don't have permission and suggest they talk to their admin. \
                    \
                    Keep responses concise and practical. If you used a tool, summarize the results \
                    naturally — don't just dump raw data. \
                    \
                    \(navigationContext)
                    """

                let sessionIdentity = AIChatSessionIdentity(
                    conversationId: conversationId,
                    db: db,
                    permissions: permissions,
                    userId: userId,
                    navigationContext: navigationContext
                )

                let session = getOrCreateChatSession(
                    identity: sessionIdentity,
                    tools: tools,
                    instructions: chatInstructions
                )
                let response = try await session.respond(to: query)
                let text = response.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                // Append user + assistant messages to in-memory history
                let userMsg = AIConversationMessage(conversationId: conversationId, role: "user", content: query)
                let assistantMsg = AIConversationMessage(conversationId: conversationId, role: "assistant", content: text)

                // Persist before reporting success. Clear/delete can therefore be awaited after
                // this call without an older detached write recreating the transcript.
                let persisted = try await persistMessagesIfCurrent(
                    [userMsg, assistantMsg],
                    scope: conversationScope,
                    expectedRevision: startingRevision,
                    to: db
                )
                guard persisted else {
                    return .fail("Conversation was cleared while the response was being generated")
                }
                messageHistory.append(userMsg)
                messageHistory.append(assistantMsg)

                return .ok(text)
            } catch {
                return .fail("AI generation failed: \(error.localizedDescription)")
            }
        } else {
            return .fail("Foundation Models requires macOS 26+ or iOS 26+")
        }
        #else
        return .fail("Foundation Models not available on this platform")
        #endif
    }

    // MARK: - Session Management

    /// Returns the existing `LanguageModelSession` if the full session identity matches,
    /// otherwise creates a new session and caches it.
    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func getOrCreateChatSession(
        identity: AIChatSessionIdentity,
        tools: [any FoundationModels.Tool],
        instructions: String
    ) -> LanguageModelSession {
        if identity == activeChatSessionIdentity,
           let existing = activeChatSession as? LanguageModelSession {
            return existing
        }
        let scope = AIConversationScope(
            conversationId: identity.conversationId,
            ownerUserId: identity.userId ?? 0
        )
        let session: LanguageModelSession
        if hydratedConversationScope == scope, !messageHistory.isEmpty {
            let transcript = Self.makeTranscript(
                instructions: instructions,
                tools: tools,
                history: messageHistory
            )
            session = LanguageModelSession(tools: tools, transcript: transcript)
            hydratedConversationScope = nil
        } else {
            session = LanguageModelSession(tools: tools, instructions: instructions)
            messageHistory.removeAll()
        }
        activeChatSession = session
        activeChatConversationId = identity.conversationId
        activeChatSessionIdentity = identity
        return session
    }

    /// Converts persisted user/assistant turns into the transcript used to initialize
    /// the next Foundation Models session. Kept internal so regression tests can verify
    /// that resume hydration reaches the model contract, not only the SwiftUI rows.
    @available(macOS 26.0, iOS 26.0, *)
    nonisolated static func makeTranscript(
        instructions: String,
        tools: [any FoundationModels.Tool],
        history: [AIConversationMessage]
    ) -> Transcript {
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: tools.map { Transcript.ToolDefinition(tool: $0) }
            )),
        ]
        for message in history {
            let segment = Transcript.Segment.text(Transcript.TextSegment(content: message.content))
            switch message.role {
            case "user":
                entries.append(.prompt(Transcript.Prompt(segments: [segment])))
            case "assistant":
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [segment])))
            default:
                continue
            }
        }
        return Transcript(entries: entries)
    }
    #endif

    /// Clear the active conversation session and in-memory history.
    /// The UI should call this when the user taps "New Conversation".
    public func clearConversation() {
        #if canImport(FoundationModels)
        activeChatSession = nil
        #endif
        activeChatConversationId = nil
        activeChatSessionIdentity = nil
        hydratedConversationScope = nil
        messageHistory.removeAll()
    }

    /// Load an owner-scoped persisted transcript and stage it for the next model request.
    /// The returned rows are also suitable for UI display.
    public func resumeConversation(
        _ conversationId: String,
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws -> [AIConversationMessage] {
        let history = try await Self.loadConversation(
            conversationId,
            ownerUserId: ownerUserId,
            from: db
        )
        let scope = try Self.validatedScope(
            conversationId: conversationId,
            ownerUserId: ownerUserId
        )
        #if canImport(FoundationModels)
        activeChatSession = nil
        #endif
        activeChatConversationId = nil
        activeChatSessionIdentity = nil
        hydratedConversationScope = scope
        messageHistory = history
        return history
    }

    /// Persist a locally generated Help turn and stage the complete conversation for
    /// the next Foundation Models request. This keeps Help local/read-only while making
    /// an immediate follow-up receive the same context that is already visible in UI.
    ///
    /// Returns `false` when a concurrent clear invalidated the write before staging.
    public func stageHelpConversation(
        _ conversationId: String,
        ownerUserId: Int64,
        userPrompt: String,
        assistantResponse: String,
        in db: AppDatabase
    ) async throws -> Bool {
        let scope = try Self.validatedScope(
            conversationId: conversationId,
            ownerUserId: ownerUserId
        )
        let expectedRevision = conversationRevisions[scope, default: 0]
        let helpTurns = [
            AIConversationMessage(conversationId: conversationId, role: "user", content: userPrompt),
            AIConversationMessage(conversationId: conversationId, role: "assistant", content: assistantResponse),
        ]

        guard try await persistMessagesIfCurrent(
            helpTurns,
            scope: scope,
            expectedRevision: expectedRevision,
            to: db
        ) else {
            return false
        }

        let history = try await Self.loadConversation(
            conversationId,
            ownerUserId: ownerUserId,
            from: db
        )
        guard conversationRevisions[scope, default: 0] == expectedRevision else {
            return false
        }

        #if canImport(FoundationModels)
        activeChatSession = nil
        #endif
        activeChatConversationId = nil
        activeChatSessionIdentity = nil
        hydratedConversationScope = scope
        messageHistory = history
        return true
    }

    /// Clear persisted and in-memory state as one awaitable actor operation. Incrementing
    /// the revision before the database delete invalidates any response currently in flight.
    public func clearConversation(
        _ conversationId: String,
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws {
        let scope = try Self.validatedScope(
            conversationId: conversationId,
            ownerUserId: ownerUserId
        )
        conversationRevisions[scope, default: 0] += 1
        try await Self.clearPersistedConversation(
            conversationId,
            ownerUserId: ownerUserId,
            from: db
        )
        if activeChatSessionIdentity?.conversationId == conversationId,
           activeChatSessionIdentity?.userId == ownerUserId {
            clearConversation()
        } else if hydratedConversationScope == scope {
            hydratedConversationScope = nil
            messageHistory.removeAll()
        }
    }

    /// Returns the in-memory message history for debugging / display.
    public func currentMessageHistory() -> [AIConversationMessage] {
        messageHistory
    }

    func persistenceRevision(for scope: AIConversationScope) -> Int {
        conversationRevisions[scope, default: 0]
    }

    /// Writes only while the originating conversation revision is still current.
    /// This internal seam makes the delayed-response/clear ordering contract testable
    /// without requiring the Foundation Models runtime to generate a response.
    func persistMessagesIfCurrent(
        _ messages: [AIConversationMessage],
        scope: AIConversationScope,
        expectedRevision: Int,
        to db: AppDatabase
    ) async throws -> Bool {
        guard conversationRevisions[scope, default: 0] == expectedRevision else {
            return false
        }
        try await Self.saveMessages(messages, ownerUserId: scope.ownerUserId, to: db)
        guard conversationRevisions[scope, default: 0] == expectedRevision else {
            // The actor can be re-entered while awaiting GRDB. If clear advanced the
            // revision during that suspension, delete once more so write-vs-clear order
            // cannot leave the just-finished stale write behind.
            try await Self.clearPersistedConversation(
                scope.conversationId,
                ownerUserId: scope.ownerUserId,
                from: db
            )
            return false
        }
        return true
    }

    // MARK: - DB Persistence

    private nonisolated static func validatedScope(
        conversationId: String,
        ownerUserId: Int64
    ) throws -> AIConversationScope {
        guard ownerUserId > 0 else {
            throw AIConversationPersistenceError.missingAuthenticatedUser
        }
        return AIConversationScope(conversationId: conversationId, ownerUserId: ownerUserId)
    }

    /// Save a single owner-scoped message row.
    public static func saveMessage(
        _ msg: AIConversationMessage,
        ownerUserId: Int64,
        to db: AppDatabase
    ) async throws {
        try await saveMessages([msg], ownerUserId: ownerUserId, to: db)
    }

    /// Save one or more turns atomically so a response never leaves a partial pair.
    public static func saveMessages(
        _ messages: [AIConversationMessage],
        ownerUserId: Int64,
        to db: AppDatabase
    ) async throws {
        guard ownerUserId > 0 else {
            throw AIConversationPersistenceError.missingAuthenticatedUser
        }
        try await db.writer.write { dbConn in
            for msg in messages {
                try dbConn.execute(
                    sql: """
                        INSERT INTO ai_conversation_messages
                            (id, conversation_id, owner_user_id, role, content, created_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [msg.id, msg.conversationId, ownerUserId, msg.role, msg.content, msg.createdAt]
                )
            }
        }
    }

    /// Load all owner-scoped messages for a conversation, ordered chronologically.
    public static func loadConversation(
        _ conversationId: String,
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws -> [AIConversationMessage] {
        _ = try validatedScope(conversationId: conversationId, ownerUserId: ownerUserId)
        return try await db.writer.read { dbConn in
            let rows = try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT id, conversation_id, role, content, created_at
                    FROM ai_conversation_messages
                    WHERE conversation_id = ? AND owner_user_id = ?
                    ORDER BY created_at ASC
                    """,
                arguments: [conversationId, ownerUserId]
            )
            return rows.map { row in
                AIConversationMessage(
                    id: row["id"],
                    conversationId: row["conversation_id"],
                    role: row["role"],
                    content: row["content"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    /// Delete only the authenticated owner's messages for a conversation.
    public static func deleteConversation(
        _ conversationId: String,
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws {
        _ = try validatedScope(conversationId: conversationId, ownerUserId: ownerUserId)
        try await db.writer.write { dbConn in
            try dbConn.execute(
                sql: "DELETE FROM ai_conversation_messages WHERE conversation_id = ? AND owner_user_id = ?",
                arguments: [conversationId, ownerUserId]
            )
        }
    }

    /// Delete all messages for a conversation and verify persistence is clear before
    /// callers update UI state. This intentionally rethrows storage failures so the UI
    /// can show a recoverable error instead of pretending private chat history was removed.
    public static func clearPersistedConversation(
        _ conversationId: String,
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws {
        try await deleteConversation(conversationId, ownerUserId: ownerUserId, from: db)

        let remainingCount = try await db.writer.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: """
                    SELECT COUNT(*)
                    FROM ai_conversation_messages
                    WHERE conversation_id = ? AND owner_user_id = ?
                    """,
                arguments: [conversationId, ownerUserId]
            ) ?? 0
        }

        guard remainingCount == 0 else {
            throw AIConversationPersistenceError.deleteVerificationFailed(
                conversationId: conversationId,
                remainingMessageCount: remainingCount
            )
        }
    }

    /// List the authenticated owner's conversations with their latest message timestamp.
    public static func listConversations(
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws -> [(id: String, lastMessageAt: String, preview: String)] {
        guard ownerUserId > 0 else {
            throw AIConversationPersistenceError.missingAuthenticatedUser
        }
        return try await db.writer.read { dbConn in
            let rows = try Row.fetchAll(
                dbConn,
                sql: """
                    SELECT conversation_id,
                           MAX(created_at) AS last_message_at,
                           (SELECT content FROM ai_conversation_messages m2
                            WHERE m2.conversation_id = m1.conversation_id
                              AND m2.owner_user_id = m1.owner_user_id
                            ORDER BY created_at DESC LIMIT 1) AS preview
                    FROM ai_conversation_messages m1
                    WHERE owner_user_id = ?
                    GROUP BY owner_user_id, conversation_id
                    ORDER BY last_message_at DESC
                    """,
                arguments: [ownerUserId]
            )
            return rows.map { row in
                (
                    id: row["conversation_id"] as String,
                    lastMessageAt: row["last_message_at"] as String,
                    preview: row["preview"] as String
                )
            }
        }
    }

    /// Return the most recently active conversation ID, if any persisted chat exists.
    ///
    /// The AI assistant panel uses this to resume the last conversation across app launches
    /// instead of generating a new UUID every time the panel is rebuilt.
    public static func latestConversationId(
        ownerUserId: Int64,
        from db: AppDatabase
    ) async throws -> String? {
        guard ownerUserId > 0 else {
            throw AIConversationPersistenceError.missingAuthenticatedUser
        }
        return try await db.writer.read { dbConn in
            try String.fetchOne(
                dbConn,
                sql: """
                    SELECT conversation_id
                    FROM ai_conversation_messages
                    WHERE owner_user_id = ?
                    ORDER BY created_at DESC
                    LIMIT 1
                    """,
                arguments: [ownerUserId]
            )
        }
    }

    // MARK: - Private Generation

    /// Core generation method that handles the FoundationModels API call.
    private func generate(instructions: String, prompt: String) async -> AIResult {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content
                return .ok(text.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                return .fail("AI generation failed: \(error.localizedDescription)")
            }
        } else {
            return .fail("Foundation Models requires macOS 26+ or iOS 26+")
        }
        #else
        return .fail("Foundation Models not available on this platform")
        #endif
    }
}
