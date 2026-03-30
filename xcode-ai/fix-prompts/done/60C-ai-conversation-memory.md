# 60C — AI Conversation Memory
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

The AI assistant creates a brand new `LanguageModelSession` for every single message (see `FoundationModelsService.swift` lines 322 and 344). This means the AI has zero memory — "order those" after "show me low stock parts" results in the AI not knowing what "those" refers to. Fix: persist the session across messages within a conversation, and save messages to a local table so conversations survive app restarts.

## Task

### Step 1: Add conversation persistence to FoundationModelsService

In `core/Sources/WiredPartCore/AI/FoundationModelsService.swift`:

**1a.** Add a stored property to hold the active chat session and conversation history:

```swift
public actor FoundationModelsService {

    // Existing properties...
    private let maxContextChars: Int
    private let domainInstructions = """..."""

    // ADD these new properties:
    /// The active chat session — reused across messages so the model retains context.
    #if canImport(FoundationModels)
    private var activeChatSession: (any Sendable)?
    private var activeChatConversationId: String?
    #endif

    /// In-memory message history for rebuilding sessions if needed.
    private var messageHistory: [(role: String, content: String)] = []
```

**1b.** Add a method to get or create a session for a conversation:

```swift
    /// Get the active session or create a new one for this conversation.
    /// If the conversationId changes, create a fresh session.
    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func getOrCreateChatSession(
        conversationId: String,
        tools: [any FoundationModels.Tool],
        instructions: String
    ) -> LanguageModelSession {
        // If we have an active session for this conversation, reuse it
        if let existing = activeChatSession as? LanguageModelSession,
           activeChatConversationId == conversationId {
            return existing
        }

        // Create new session
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        activeChatSession = session
        activeChatConversationId = conversationId
        messageHistory = []
        return session
    }
    #endif
```

**1c.** Modify the `chatWithTools` method to accept a `conversationId` parameter and reuse the session:

Change the signature from:
```swift
public func chatWithTools(
    query: String,
    db: AppDatabase,
    permissions: [String],
    navigationContext: String
) async -> AIResult {
```

To:
```swift
public func chatWithTools(
    query: String,
    conversationId: String = "default",
    db: AppDatabase,
    permissions: [String],
    navigationContext: String
) async -> AIResult {
```

**1d.** Inside `chatWithTools`, replace the line:
```swift
let session = LanguageModelSession(tools: tools, instructions: chatInstructions)
```

With:
```swift
let session = getOrCreateChatSession(
    conversationId: conversationId,
    tools: tools,
    instructions: chatInstructions
)
```

**1e.** After a successful response, append to message history:
```swift
messageHistory.append((role: "user", content: query))
messageHistory.append((role: "assistant", content: text))
```

**1f.** Add a method to clear a conversation:

```swift
    /// Clear the active chat session (e.g., when user starts a new conversation).
    public func clearConversation() {
        #if canImport(FoundationModels)
        activeChatSession = nil
        activeChatConversationId = nil
        #endif
        messageHistory = []
    }
```

### Step 2: Add conversation persistence table

In `core/Sources/WiredPartCore/Database/AppDatabase.swift` (or wherever migrations are defined), add a new migration:

```swift
migrator.registerMigration("addAIConversations") { db in
    try db.create(table: "ai_conversations", ifNotExists: true) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("conversationId", .text).notNull()
        t.column("role", .text).notNull()         // "user" or "assistant"
        t.column("content", .text).notNull()
        t.column("pageContext", .text)              // which page the message was sent from
        t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }
    try db.create(indexOn: "ai_conversations", columns: ["conversationId"])
}
```

### Step 3: Add save/load methods to FoundationModelsService

Add methods to persist and restore conversation messages:

```swift
    /// Save a message to the conversation history table.
    public func saveMessage(
        conversationId: String,
        role: String,
        content: String,
        pageContext: String?,
        db: AppDatabase
    ) {
        do {
            try db.dbWriter.write { dbConn in
                try dbConn.execute(
                    sql: """
                        INSERT INTO ai_conversations (conversationId, role, content, pageContext, createdAt)
                        VALUES (?, ?, ?, ?, ?)
                        """,
                    arguments: [conversationId, role, content, pageContext, Date()]
                )
            }
        } catch {
            // Non-critical — log but don't crash
            print("[AI] Failed to save message: \(error)")
        }
    }

    /// Load conversation history for display in the UI.
    public func loadConversation(
        conversationId: String,
        db: AppDatabase
    ) -> [(role: String, content: String, createdAt: Date)] {
        do {
            return try db.dbWriter.read { dbConn in
                let rows = try Row.fetchAll(
                    dbConn,
                    sql: "SELECT role, content, createdAt FROM ai_conversations WHERE conversationId = ? ORDER BY createdAt",
                    arguments: [conversationId]
                )
                return rows.map { (
                    role: $0["role"] as String,
                    content: $0["content"] as String,
                    createdAt: $0["createdAt"] as Date
                ) }
            }
        } catch {
            return []
        }
    }
```

### Step 4: Wire the AI panel to use conversation memory

In `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift`:

- Generate a `conversationId` (e.g., `UUID().uuidString`) when the panel opens, store it in `@State`.
- Pass `conversationId` to `chatWithTools(query:conversationId:db:permissions:navigationContext:)`.
- After each response, call `saveMessage()` for both the user message and the AI response.
- On panel open, call `loadConversation()` to restore previous messages from the current session.
- Add a "New Conversation" button that calls `clearConversation()` and generates a new `conversationId`.

### Step 5: Update all callers of chatWithTools

Search for all callers of `chatWithTools(query:` and add the `conversationId` parameter. Most callers can use the default `"default"` value. The AI panel should use its own managed conversation ID.

## Files to Modify

1. `core/Sources/WiredPartCore/AI/FoundationModelsService.swift` — session persistence, message history, save/load methods
2. `core/Sources/WiredPartCore/Database/AppDatabase.swift` — add `ai_conversations` migration
3. `Weird Parts IOS/Weird Parts IOS/AI/IOSAIAssistantPanel.swift` — wire conversation ID, load/save messages, "New Conversation" button
4. Any other files that call `chatWithTools` — add conversationId parameter (search for `chatWithTools(query:`)

## Success Criteria

- [ ] AI remembers context from previous messages within the same conversation
- [ ] "Show me low stock parts" followed by "Order those" references the correct parts
- [ ] Messages persist in the `ai_conversations` table
- [ ] Closing and reopening the AI panel restores the conversation
- [ ] "New Conversation" button clears memory and starts fresh
- [ ] The `chatWithTools` method signature is backward-compatible (conversationId has a default value)
- [ ] No compilation errors across the project
