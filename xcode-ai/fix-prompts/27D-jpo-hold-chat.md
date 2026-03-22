# 27D — JPO Hold + Chat: Per-Part Q&A Thread

> **Chain position:** 27A → 27B → 27C → **27D** → 27E
> **Prerequisite:** 27C complete (per-part actions, Hold button)
> **Plan:** `docs/plans/ios-jpo-page.md` — Hold + Chat Integration
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding to the next prompt.

## Context

When a manager puts a JPO line item "on hold," it should create a chat thread linked to that specific JPO + part. The manager can ask questions ("Do you need tamper-resistant?"), the field worker responds, and the manager can then approve or reject the part based on the answer. The chat thread is per-part, not per-JPO. The JPO list page should show a 💬 indicator when questions are pending.

**Files to read first:**
- `core/Sources/WiredPartCore/Services/ChatService.swift` — channel/message creation methods
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — JPOLineRow, updateJPOLineStatus
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift` — after 27C
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSMessageThreadView.swift` — existing chat UI

**Files to modify:**
- `core/Sources/WiredPartCore/Services/OrdersService.swift` — add holdWithChat method
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift` — wire Hold → chat
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOsPage.swift` — add chat indicator

## Task

### Step 1: Create chat thread when Hold is tapped

In OrdersService, add a method that creates a hold with an associated chat thread:

```swift
/// Put a JPO line on hold and create a chat thread for Q&A.
/// Returns the chat thread/channel ID.
public func holdJPOLineWithChat(lineId: Int64, holdReason: String, userId: Int64, partName: String, jpoId: Int64) throws -> Int64 {
    return try db.writer.write { dbConn -> Int64 in
        // Create a chat channel for this Q&A
        let channelName = "JPO #\(jpoId) — \(partName)"
        try dbConn.execute(
            sql: """
                INSERT INTO chat_channels (name, channel_type, created_by, created_at, updated_at)
                VALUES (?, 'jpo_qa', ?, datetime('now'), datetime('now'))
                """,
            arguments: [channelName, userId]
        )
        let channelId = dbConn.lastInsertedRowID

        // Add the requester and the manager to the channel
        // Get the JPO requester
        let requesterId = try Int64.fetchOne(dbConn, sql: """
            SELECT requested_by FROM job_purchase_orders WHERE id = ?
            """, arguments: [jpoId])

        if let reqId = requesterId {
            try dbConn.execute(
                sql: "INSERT OR IGNORE INTO chat_channel_members (channel_id, user_id, joined_at) VALUES (?, ?, datetime('now'))",
                arguments: [channelId, reqId]
            )
        }
        try dbConn.execute(
            sql: "INSERT OR IGNORE INTO chat_channel_members (channel_id, user_id, joined_at) VALUES (?, ?, datetime('now'))",
            arguments: [channelId, userId]
        )

        // Send the initial question as a message
        try dbConn.execute(
            sql: """
                INSERT INTO chat_messages (channel_id, user_id, content, created_at)
                VALUES (?, ?, ?, datetime('now'))
                """,
            arguments: [channelId, userId, holdReason]
        )

        // Update the JPO line
        try dbConn.execute(
            sql: """
                UPDATE jpo_lines SET
                    line_status = 'on_hold',
                    hold_reason = ?,
                    chat_thread_id = ?,
                    status_updated_at = datetime('now'),
                    status_updated_by = ?
                WHERE id = ?
                """,
            arguments: [holdReason, channelId, userId, lineId]
        )

        // Update parent JPO status
        try updateDerivedJPOStatus(dbConn: dbConn, lineId: lineId)

        return channelId
    }
}

private func updateDerivedJPOStatus(dbConn: Database, lineId: Int64) throws {
    if let jpoId = try Int64.fetchOne(dbConn, sql: "SELECT jpo_id FROM jpo_lines WHERE id = ?", arguments: [lineId]) {
        let statuses = try String.fetchAll(dbConn, sql: "SELECT line_status FROM jpo_lines WHERE jpo_id = ?", arguments: [jpoId])
        let derived = deriveJPOStatusFromRows(statuses)
        try dbConn.execute(sql: "UPDATE job_purchase_orders SET status = ?, updated_at = datetime('now') WHERE id = ?", arguments: [derived, jpoId])
    }
}
```

### Step 2: Wire Hold button to ask for a question

In IOSJPODetailPage, replace the simple `holdLine()` call with a question prompt:

```swift
@State private var holdQuestion = ""
@State private var showHoldPrompt = false
@State private var holdingLineId: Int64?
@State private var holdingPartName: String?

// When Hold is tapped:
Button {
    holdingLineId = line.id
    holdingPartName = line.partName
    showHoldPrompt = true
} label: {
    Label("Hold", systemImage: "pause.circle.fill")
        .font(.caption2)
}

// Alert for hold question:
.alert("Ask About This Part", isPresented: $showHoldPrompt) {
    TextField("Your question...", text: $holdQuestion)
    Button("Cancel", role: .cancel) { holdQuestion = "" }
    Button("Hold + Send Question") {
        guard !holdQuestion.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await createHoldWithChat() }
        holdQuestion = ""
    }
} message: {
    if let name = holdingPartName {
        Text("Ask the requester about \"\(name)\". They'll be notified to respond in chat.")
    }
}
```

```swift
private func createHoldWithChat() async {
    guard let service = appCore.ordersService,
          let lineId = holdingLineId,
          let jpo = jpo,
          let userId = appCore.authService?.currentUserId else { return }
    do {
        let channelId = try service.holdJPOLineWithChat(
            lineId: lineId,
            holdReason: holdQuestion,
            userId: userId,
            partName: holdingPartName ?? "Part",
            jpoId: jpo.id
        )
        // Open the chat thread
        activeSheet = .viewChat(channelId)
        loadData()
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Step 3: Handle View Chat in sheet routing

```swift
case .viewChat(let channelId):
    NavigationStack {
        IOSMessageThreadView(channelId: channelId)
            .environmentObject(appCore)
    }
```

### Step 4: Add chat indicator to JPO list page

In IOSJPOsPage, update the JPO row to show a chat indicator when any line is on hold:

Add a `hasOpenQuestions` field to `JPOListItem` or compute it from a query. Simplest: add a new field to the list query.

In `OrdersService.listJPOs`, update the SQL to include a count of on_hold lines:

```sql
SELECT jpo.*,
       (SELECT COUNT(*) FROM jpo_lines jl WHERE jl.jpo_id = jpo.id AND jl.line_status = 'on_hold') AS hold_count
FROM job_purchase_orders jpo
...
```

Add `holdCount: Int` to `JPOListItem`. Then in the row:

```swift
if jpo.holdCount > 0 {
    HStack(spacing: 4) {
        Image(systemName: "message.badge")
            .foregroundStyle(.yellow)
        Text("\(jpo.holdCount) question\(jpo.holdCount == 1 ? "" : "s") pending")
            .font(.caption2)
            .foregroundStyle(.yellow)
    }
}
```

## Important Notes

- Chat thread is created with type `'jpo_qa'` to distinguish from regular channels
- Both the manager (who held) and the requester (who created the JPO) are auto-added to the channel
- The hold reason becomes the first message in the thread
- After the field worker responds and the manager approves, the chat stays as a historical record
- The `chat_thread_id` on the JPO line links directly to the channel
- Check that `IOSMessageThreadView` accepts a `channelId` parameter
- The hold count on the list page uses a subquery — check performance with large datasets

## Success Criteria

- [ ] Hold button prompts for a question
- [ ] Chat thread created with JPO + part name as channel name
- [ ] Both requester and manager auto-added to channel
- [ ] Hold reason sent as first chat message
- [ ] [View Chat] button on on_hold lines opens the thread
- [ ] JPO list shows 💬 indicator with hold count
- [ ] holdCount added to JPOListItem struct + SQL
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 27D Results (YYYY-MM-DD)
- Hold → chat thread creation with auto-membership
- Question prompt → first message
- View Chat button on held lines
- Chat indicator on list page with hold count
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 27E.**
