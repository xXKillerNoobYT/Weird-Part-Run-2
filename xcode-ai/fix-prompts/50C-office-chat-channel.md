# 50C — Office Chat Channel

> **Chain position:** 50A → 50B → **50C** → 50D
> **Prerequisite:** 42A (chat unified inbox)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `ChatService.swift` and `IOSChannelsPage.swift`. Add an auto-created "Office" chat channel for admin staff with hat-gated membership and an "Office" badge in the unified inbox.

## Context

The Office needs its own dedicated chat channel, auto-created on first launch, available only to users with office-related hats (manage_office, admin, view_financials). It appears in the unified inbox with a distinctive "Office" badge. Non-office users never see it.

## Task

### Step 1: Auto-Create Office Channel

```swift
// In ChatService or an initialization flow:
func ensureOfficeChannel() async throws {
    try await db.write { db in
        // Check if Office channel exists
        let exists = try Row.fetchOne(db, sql: """
            SELECT id FROM chat_channels
            WHERE channel_type = 'office' AND name = 'Office'
            """)

        if exists == nil {
            // Create the Office channel
            try db.execute(sql: """
                INSERT INTO chat_channels (name, channel_type, created_by, created_at, is_system)
                VALUES ('Office', 'office', 0, datetime('now'), 1)
                """)

            let channelId = db.lastInsertedRowID

            // Add all users with office permissions
            let officeUsers = try Row.fetchAll(db, sql: """
                SELECT DISTINCT hp.user_id
                FROM hat_permissions hp
                JOIN permissions p ON hp.permission_id = p.id
                WHERE p.key IN ('manage_office', 'admin', 'view_financials')
                AND hp.user_id IS NOT NULL
                """)

            for row in officeUsers {
                let userId: Int64 = row["user_id"]
                try db.execute(sql: """
                    INSERT OR IGNORE INTO channel_members (channel_id, user_id, joined_at, role)
                    VALUES (?, ?, datetime('now'), 'member')
                    """, arguments: [channelId, userId])
            }
        }
    }
}
```

### Step 2: Membership Sync (Hat-Gated)

```swift
/// Call when hats change to sync Office channel membership
func syncOfficeChannelMembers() async throws {
    try await db.write { db in
        guard let channelId = try Int64.fetchOne(db, sql: """
            SELECT id FROM chat_channels WHERE channel_type = 'office' AND is_system = 1
            """) else { return }

        // Get current office-eligible users
        let eligibleUserIds = try Int64.fetchAll(db, sql: """
            SELECT DISTINCT hp.user_id
            FROM hat_permissions hp
            JOIN permissions p ON hp.permission_id = p.id
            WHERE p.key IN ('manage_office', 'admin', 'view_financials')
            AND hp.user_id IS NOT NULL
            """)

        // Add missing members
        for userId in eligibleUserIds {
            try db.execute(sql: """
                INSERT OR IGNORE INTO channel_members (channel_id, user_id, joined_at, role)
                VALUES (?, ?, datetime('now'), 'member')
                """, arguments: [channelId, userId])
        }

        // Remove members who lost office permissions
        let placeholders = eligibleUserIds.map { _ in "?" }.joined(separator: ",")
        if !eligibleUserIds.isEmpty {
            try db.execute(sql: """
                DELETE FROM channel_members
                WHERE channel_id = ? AND user_id NOT IN (\(placeholders))
                """, arguments: [channelId] + eligibleUserIds)
        }
    }
}
```

### Step 3: Office Badge in Unified Inbox

```swift
// In the unified inbox (IOSChannelsPage or equivalent),
// add an "Office" badge to the office channel:

struct InboxItemRow: View {
    let item: InboxItem

    var body: some View {
        HStack {
            // Channel icon with badge
            ZStack(alignment: .topTrailing) {
                Image(systemName: channelIcon(item.channelType))
                    .foregroundStyle(channelColor(item.channelType))
                    .frame(width: 32, height: 32)

                if item.channelType == "office" {
                    Text("Office")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(.purple)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.channelName).font(.subheadline)
                        .fontWeight(item.unreadCount > 0 ? .bold : .regular)
                    Spacer()
                    Text(item.lastMessageDate, format: .relative(presentation: .numeric))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(item.lastMessagePreview)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if item.unreadCount > 0 {
                Text("\(item.unreadCount)")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    func channelIcon(_ type: String) -> String {
        switch type {
        case "office": return "building.2.fill"
        case "dm": return "person.fill"
        case "qa": return "questionmark.circle.fill"
        case "supplier": return "shippingbox.fill"
        case "job": return "wrench.fill"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    func channelColor(_ type: String) -> Color {
        switch type {
        case "office": return .purple
        default: return .blue
        }
    }
}
```

### Step 4: Migration

```swift
// Add is_system column to chat_channels if not present
try db.alter(table: "chat_channels") { t in
    t.add(column: "is_system", .boolean).defaults(to: false)
}
```

### Step 5: Call on App Launch

```swift
// In app initialization, ensure office channel exists:
// (after DB is ready but before UI loads)
Task {
    try? await appCore.chatService?.ensureOfficeChannel()
}
```

## Important Notes
- Office channel is auto-created once (system channel, not user-created)
- Only users with manage_office, admin, or view_financials permissions are members
- When hats change, call syncOfficeChannelMembers() to add/remove members
- "Office" badge is purple, shown on the channel icon in the unified inbox
- Non-office users never see this channel in their inbox
- System channels (is_system=true) cannot be deleted by users

## Success Criteria
- [ ] Auto-created Office channel on first launch
- [ ] Hat-gated membership (manage_office, admin, view_financials)
- [ ] Membership sync when hats change
- [ ] "Office" badge in unified inbox (purple)
- [ ] Non-office users can't see the channel
- [ ] Migration: is_system column
- [ ] Service: ensureOfficeChannel, syncOfficeChannelMembers
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 50C Results (YYYY-MM-DD)
- Office chat channel: auto-created, hat-gated
- Membership sync on hat changes
- Purple "Office" badge in inbox
- Migration: is_system column
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 50D.**
