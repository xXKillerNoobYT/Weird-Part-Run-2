# 42A — Chat Unified Inbox

> **Chain position:** **42A** → 42B → 42C → 42D
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `IOSChannelsPage.swift` and `ChatService.swift`. The current page has separate tabs or sections for different message types. Redesign as a unified inbox where ALL message types appear in one sorted stream.

## Context

The current chat page separates messages by type (channels, DMs, Q&A). This forces users to check multiple places. A unified inbox shows everything in one sorted list — most recent activity at top, unread channels floating above read ones. Smart cards let users filter by type without switching tabs.

## Task

### Step 1: Add Service Methods to ChatService

```swift
// MARK: - Unified Inbox

struct InboxItem: Identifiable, Sendable {
    let id: Int64
    let channelId: Int64
    let channelName: String
    let channelType: String  // "message", "qa", "rfi", "supplier", "dm", "job"
    let lastMessagePreview: String
    let lastMessageDate: Date
    let lastMessageBy: String
    let unreadCount: Int
    let jobId: Int64?
    let jobName: String?
}

/// Get unified inbox with all channel types, sorted by last activity
func getUnifiedInbox(userId: Int64) async throws -> [InboxItem] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT c.id as channel_id, c.name as channel_name, c.channel_type,
                   m.content as last_message,
                   m.created_at as last_message_date,
                   u.first_name || ' ' || u.last_name as last_message_by,
                   COALESCE(unread.cnt, 0) as unread_count,
                   c.job_id, j.name as job_name
            FROM channels c
            LEFT JOIN (
                SELECT channel_id, content, created_at, user_id,
                       ROW_NUMBER() OVER (PARTITION BY channel_id ORDER BY created_at DESC) as rn
                FROM messages WHERE deleted_at IS NULL
            ) m ON m.channel_id = c.id AND m.rn = 1
            LEFT JOIN users u ON m.user_id = u.id
            LEFT JOIN jobs j ON c.job_id = j.id
            LEFT JOIN (
                SELECT channel_id, COUNT(*) as cnt FROM messages
                WHERE created_at > COALESCE(
                    (SELECT last_read_at FROM channel_members WHERE channel_id = messages.channel_id AND user_id = :userId),
                    '1970-01-01'
                )
                AND deleted_at IS NULL
                GROUP BY channel_id
            ) unread ON unread.channel_id = c.id
            WHERE c.deleted_at IS NULL
            AND c.id IN (SELECT channel_id FROM channel_members WHERE user_id = :userId)
            ORDER BY unread_count DESC, m.created_at DESC
        """, arguments: ["userId": userId])
        .map { /* map to InboxItem */ }
    }
}

/// Get unread count for badge
func getTotalUnreadCount(userId: Int64) async throws -> Int
```

### Step 2: Redesign IOSChannelsPage.swift

**Smart Cards (filter by type):**

```swift
@State private var typeFilter: ChannelTypeFilter = .all
@State private var inboxItems: [InboxItem] = []

enum ChannelTypeFilter: String, CaseIterable {
    case all = "All"
    case messages = "Messages"
    case dm = "DMs"
    case job = "Job"
    case qa = "Q&A"
    case rfi = "RFI"
    case supplier = "Supplier"
}

// Smart cards row
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 10) {
        ForEach(ChannelTypeFilter.allCases, id: \.self) { filter in
            let count = countForFilter(filter)
            SmartCard(
                title: filter.rawValue,
                count: count,
                isActive: typeFilter == filter
            ) {
                typeFilter = filter
            }
        }
    }
    .padding(.horizontal)
}
```

**Unified List:**

```swift
List {
    if let error = actionError {
        Section { Text(error).foregroundStyle(.red) }
    }

    ForEach(filteredItems) { item in
        NavigationLink(value: item.channelId) {
            InboxRow(item: item)
        }
    }
}
.refreshable { await loadData() }
.searchable(text: $searchText, prompt: "Search conversations")
```

**Inbox Row:**

```swift
struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconForType(item.channelType))
                .foregroundStyle(colorForType(item.channelType))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.channelName)
                        .font(.headline)
                        .fontWeight(item.unreadCount > 0 ? .bold : .regular)
                    if let jobName = item.jobName {
                        Text(jobName)
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                Text(item.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(item.lastMessageDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if item.unreadCount > 0 {
                    Text("\(item.unreadCount)")
                        .font(.caption2).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red)
                        .clipShape(Capsule())
                }
            }
        }
    }

    func iconForType(_ type: String) -> String {
        switch type {
        case "dm": return "person.2"
        case "job": return "wrench.and.screwdriver"
        case "qa": return "questionmark.circle"
        case "rfi": return "doc.text"
        case "supplier": return "building.2"
        default: return "bubble.left"
        }
    }
}
```

### Step 3: Fix Silent Guard Returns

Search `IOSChannelsPage.swift` for any `guard let service = ... else { return }` patterns and replace with error state:

```swift
guard let service = appCore.chatService else {
    loadError = "Chat service unavailable"
    isLoading = false
    return
}
```

### Step 4: Unread Channels Float to Top

The SQL query already orders by `unread_count DESC, last_message_date DESC`, so unread channels naturally float to the top. No additional client-side sorting needed.

## Important Notes
- Unread count badge must be RED with white text (iMessage style)
- Last message preview should be truncated to 1 line
- Type icons help visual scanning — use SF Symbols consistently
- Search should filter by channel name AND last message content
- The Create Channel button stays in the toolbar
- If a channel has no messages yet, show "No messages yet" as preview
- Filter "All" shows all types; other filters show only that type

## Success Criteria
- [ ] Unified inbox shows all channel types in one list
- [ ] Unread channels float to top
- [ ] Smart cards filter by type (All, Messages, DMs, Job, Q&A, RFI, Supplier)
- [ ] Last message preview on each row
- [ ] Unread count badge (red number)
- [ ] Type icons for visual identification
- [ ] Silent guard returns fixed
- [ ] .refreshable and .searchable present
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 42A Results (YYYY-MM-DD)
- ChatService: getUnifiedInbox, getTotalUnreadCount
- IOSChannelsPage: unified inbox with smart cards
- Unread badges, type icons, message previews
- X silent guard returns fixed
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 42B.**
