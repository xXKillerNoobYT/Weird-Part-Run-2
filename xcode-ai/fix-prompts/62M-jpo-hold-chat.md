# 62M — Auto-Create Chat Thread When JPO Line Put on Hold
> Chain position: Standalone

## Task

When a JPO (Job Parts Order) line item is put on "Hold," automatically create a chat thread linked to that JPO + part. Show the thread in BOTH `IOSJPODetailPage` and `IOSChannelsPage`.

### Step 1: Add service method for hold-linked chat threads

In `core/Sources/WiredPartCore/Services/ChatService.swift`, add a method to create a hold-discussion thread:

```swift
/// Create a chat thread linked to a JPO line hold decision.
/// The thread appears in both the JPO detail and the general channels list.
@discardableResult
public func createJPOHoldThread(
    jpoId: Int64,
    jpoNumber: String,
    partName: String,
    holdReason: String,
    createdBy: Int64
) throws -> Int64 {
    do {
        return try db.writer.write { dbConn in
            // Create the channel with a clear name and link metadata
            let channelName = "Hold: \(partName) (\(jpoNumber))"
            try dbConn.execute(sql: """
                INSERT INTO channels (name, channel_type, context_type, context_id,
                                      created_by, is_archived, deleted_at, created_at, updated_at)
                VALUES (?, 'hold_discussion', 'jpo', ?, ?, 0, NULL, datetime('now'), datetime('now'))
                """, arguments: [channelName, jpoId, createdBy])

            let channelId = dbConn.lastInsertedRowID

            // Post the initial message explaining the hold
            try dbConn.execute(sql: """
                INSERT INTO messages (channel_id, sender_id, content, message_type,
                                      deleted_at, created_at)
                VALUES (?, ?, ?, 'system', NULL, datetime('now'))
                """, arguments: [channelId, createdBy,
                                "**\(partName)** put on hold.\nReason: \(holdReason)"])

            return channelId
        }
    } catch {
        if isTableNotFoundError(error) { return 0 }
        throw error
    }
}

/// Get the chat thread linked to a JPO hold, if one exists.
public func getJPOHoldThread(jpoId: Int64) throws -> Int64? {
    do {
        return try db.writer.read { dbConn in
            try Int64.fetchOne(dbConn, sql: """
                SELECT id FROM channels
                WHERE context_type = 'jpo' AND context_id = ?
                  AND channel_type = 'hold_discussion' AND deleted_at IS NULL
                LIMIT 1
                """, arguments: [jpoId])
        }
    } catch {
        if isTableNotFoundError(error) { return nil }
        throw error
    }
}
```

### Step 2: Trigger thread creation when hold is applied

In `IOSJPODetailPage.swift`, find where the "Hold" action is triggered (the button or menu that sets a JPO line's status to "hold"). After the status update call, create the chat thread:

```swift
// After updating JPO line status to "hold":
if let chatService = appCore.chatService,
   let currentUser = appCore.currentUser {
    try? chatService.createJPOHoldThread(
        jpoId: jpoId,
        jpoNumber: jpoDetail.jpoNumber,
        partName: lineItem.partName,
        holdReason: holdReason,
        createdBy: currentUser.id ?? 0
    )
}
```

### Step 3: Show the thread link on IOSJPODetailPage

For each held line item, show a "View Discussion" button:

```swift
// In the line item row for held items:
if lineItem.status == "hold" {
    Button {
        // Navigate to the chat thread
        if let chatService = appCore.chatService,
           let channelId = try? chatService.getJPOHoldThread(jpoId: jpoId) {
            selectedChannelId = channelId
            showChatThread = true
        }
    } label: {
        Label("Discussion", systemImage: "bubble.left.and.bubble.right")
            .font(.caption)
    }
}
```

### Step 4: Show hold threads in IOSChannelsPage

Hold discussion threads are already stored in the `channels` table with `channel_type = 'hold_discussion'`. They should appear automatically in the channels list. If `IOSChannelsPage` filters by channel_type, make sure `'hold_discussion'` is included.

In `IOSChannelsPage.swift`, verify the channel list query includes hold_discussion channels. If it filters by specific types, add:

```swift
// Ensure hold discussion channels are included in the query
// They should show with an orange "Hold" badge
```

Add visual distinction for hold channels in the list:

```swift
if channel.channelType == "hold_discussion" {
    Text("HOLD")
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.orange, in: Capsule())
}
```

## Files to Modify

- `core/Sources/WiredPartCore/Services/ChatService.swift` — add createJPOHoldThread, getJPOHoldThread
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift` — trigger thread creation on hold, show discussion link
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSChannelsPage.swift` — show hold threads with badge

## Success Criteria
- [ ] Putting a JPO line on hold auto-creates a chat thread named "Hold: [Part] ([JPO#])"
- [ ] Thread has an initial system message explaining the hold
- [ ] Held line items show a "Discussion" link on JPO detail page
- [ ] Thread appears in the channels list with an orange "HOLD" badge
- [ ] Thread is linked to the JPO via context_type/context_id
- [ ] No compile errors
