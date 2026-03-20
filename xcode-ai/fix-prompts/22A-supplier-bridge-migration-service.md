# 22A — Supplier Communication Bridge: Migration + Service Layer

> **Chain position:** **22A** → 22B → 22C
> **Prerequisite:** 17A-17H (supplier system) complete
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

Suppliers need to communicate with contractors via the existing chat system. The approach is a **bridge** — supplier contacts can be linked to chat channels without needing full user accounts. A `supplier_channel_bridge` table maps supplier contacts to chat channels with token-gated access.

The existing chat system uses:
- `chat_channels` (types: "job", "dm", "group") — needs "supplier" type
- `chat_channel_members` (user_id FK) — only supports internal users
- `chat_messages` — message content with media support
- `ChatService` — listChannels, createChannel, sendMessage, getMessages

**Key files:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- `core/Sources/WiredPartCore/Services/ChatService.swift`
- `core/Sources/WiredPartCore/Models/` — new model structs
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`

## Task

### Step 1: Migration — Supplier bridge tables

Add a new migration (use the next available number) in `AppDatabase+Migrations.swift`:

```swift
// Migration: Supplier Communication Bridge
migrator.registerMigration("supplier_bridge") { db in
    // Bridge table: links supplier contacts to chat channels
    try db.create(table: "supplier_channel_bridges") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("channel_id", .integer).notNull()
            .references("chat_channels", onDelete: .cascade)
        t.column("supplier_id", .integer).notNull()
            .references("suppliers", onDelete: .cascade)
        t.column("contact_id", .integer)  // optional — specific entity_contacts row
            .references("entity_contacts", onDelete: .setNull)
        t.column("display_name", .text).notNull()  // how they appear in chat
        t.column("role", .text)  // "sales_rep", "accounts", "shipping", etc.
        t.column("invite_token", .text).notNull()  // unique token for future access
        t.column("is_active", .integer).notNull().defaults(to: 1)
        t.column("last_seen_at", .text)  // last time they viewed the channel
        t.column("created_at", .text).notNull()
            .defaults(sql: "datetime('now')")
        t.column("deleted_at", .text)

        t.uniqueKey(["channel_id", "supplier_id"])
    }
    try db.create(index: "idx_supplier_channel_bridges_supplier",
                  on: "supplier_channel_bridges", columns: ["supplier_id"])
    try db.create(index: "idx_supplier_channel_bridges_token",
                  on: "supplier_channel_bridges", columns: ["invite_token"],
                  unique: true)

    // Supplier messages: messages sent on behalf of a supplier (by any internal user)
    // This tracks which messages are "from" a supplier context
    try db.create(table: "supplier_messages") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("message_id", .integer).notNull()
            .references("chat_messages", onDelete: .cascade)
        t.column("bridge_id", .integer).notNull()
            .references("supplier_channel_bridges", onDelete: .cascade)
        t.column("direction", .text).notNull()  // "inbound" (from supplier) or "outbound" (to supplier)
        t.column("attachment_type", .text)  // "pdf", "photo", "link", "po_reference"
        t.column("attachment_ref", .text)  // PO number, PDF path, URL, etc.
        t.column("created_at", .text).notNull()
            .defaults(sql: "datetime('now')")
        t.column("deleted_at", .text)
    }
    try db.create(index: "idx_supplier_messages_bridge",
                  on: "supplier_messages", columns: ["bridge_id"])
}
```

### Step 2: Model structs

Add to the appropriate models file (or create a new one):

```swift
/// A bridge linking a supplier to a chat channel.
public struct SupplierChannelBridge: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: Int64?
    public var channelId: Int64
    public var supplierId: Int64
    public var contactId: Int64?
    public var displayName: String
    public var role: String?
    public var inviteToken: String
    public var isActive: Int
    public var lastSeenAt: String?
    public var createdAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "supplier_channel_bridges"

    enum CodingKeys: String, CodingKey {
        case id, channelId = "channel_id", supplierId = "supplier_id",
             contactId = "contact_id", displayName = "display_name",
             role, inviteToken = "invite_token", isActive = "is_active",
             lastSeenAt = "last_seen_at", createdAt = "created_at",
             deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A message with supplier context.
public struct SupplierMessage: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public var id: Int64?
    public var messageId: Int64
    public var bridgeId: Int64
    public var direction: String
    public var attachmentType: String?
    public var attachmentRef: String?
    public var createdAt: String?
    public var deletedAt: String?

    public static let databaseTableName = "supplier_messages"

    enum CodingKeys: String, CodingKey {
        case id, messageId = "message_id", bridgeId = "bridge_id",
             direction, attachmentType = "attachment_type",
             attachmentRef = "attachment_ref", createdAt = "created_at",
             deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

### Step 3: Add ConflictResolver + ChangeTracker entries

Add the new tables to the ConflictResolver whitelist and ChangeTracker:

```swift
// In ConflictResolver table whitelist:
"supplier_channel_bridges",
"supplier_messages",
```

### Step 4: ChatService — Supplier channel methods

Add supplier bridge methods to `ChatService.swift`:

```swift
// =========================================================================
// MARK: - Supplier Communication Bridge
// =========================================================================

/// Data for a supplier channel listing.
public struct SupplierChannelRow: Sendable {
    public let channelId: Int64
    public let channelName: String
    public let supplierName: String
    public let supplierId: Int64
    public let bridgeDisplayName: String
    public let role: String?
    public let lastMessageAt: String?
    public let unreadCount: Int
}

/// Create a supplier channel and bridge link.
/// Returns the channel ID.
public func createSupplierChannel(
    name: String,
    supplierId: Int64,
    supplierDisplayName: String,
    contactId: Int64?,
    role: String?,
    createdBy: Int64
) throws -> Int64 {
    try db.writer.write { dbConn in
        // Create the channel with type "supplier"
        try dbConn.execute(sql: """
            INSERT INTO chat_channels (channel_type, name, created_by, is_active, created_at)
            VALUES ('supplier', ?, ?, 1, datetime('now'))
            """, arguments: [name, createdBy])
        let channelId = dbConn.lastInsertedRowID

        // Add the creator as a channel member (admin)
        try dbConn.execute(sql: """
            INSERT INTO chat_channel_members (channel_id, user_id, role, joined_at)
            VALUES (?, ?, 'admin', datetime('now'))
            """, arguments: [channelId, createdBy])

        // Create the bridge link
        let token = UUID().uuidString  // unique invite token
        try dbConn.execute(sql: """
            INSERT INTO supplier_channel_bridges
            (channel_id, supplier_id, contact_id, display_name, role, invite_token, is_active, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, datetime('now'))
            """, arguments: [channelId, supplierId, contactId, supplierDisplayName, role, token])

        return channelId
    }
}

/// List all supplier channels for the current user.
public func listSupplierChannels(userId: Int64) throws -> [SupplierChannelRow] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT cc.id AS channel_id, cc.name AS channel_name,
                   s.name AS supplier_name, scb.supplier_id,
                   scb.display_name, scb.role,
                   (SELECT MAX(created_at) FROM chat_messages WHERE channel_id = cc.id AND deleted_at IS NULL) AS last_message_at,
                   (SELECT COUNT(*) FROM chat_messages cm
                    WHERE cm.channel_id = cc.id AND cm.deleted_at IS NULL
                    AND cm.created_at > COALESCE(
                        (SELECT read_at FROM chat_read_receipts WHERE channel_id = cc.id AND user_id = ?), '1970-01-01'
                    )) AS unread_count
            FROM chat_channels cc
            JOIN chat_channel_members ccm ON ccm.channel_id = cc.id AND ccm.user_id = ?
            JOIN supplier_channel_bridges scb ON scb.channel_id = cc.id AND scb.deleted_at IS NULL
            JOIN suppliers s ON s.id = scb.supplier_id AND s.deleted_at IS NULL
            WHERE cc.channel_type = 'supplier' AND cc.deleted_at IS NULL
            ORDER BY last_message_at DESC NULLS LAST
            """, arguments: [userId, userId])

        return rows.map { row in
            SupplierChannelRow(
                channelId: row["channel_id"],
                channelName: row["channel_name"] ?? "",
                supplierName: row["supplier_name"] ?? "",
                supplierId: row["supplier_id"],
                bridgeDisplayName: row["display_name"] ?? "",
                role: row["role"],
                lastMessageAt: row["last_message_at"],
                unreadCount: row["unread_count"] ?? 0
            )
        }
    }
}

/// Send a message in a supplier channel with direction tracking.
public func sendSupplierMessage(
    channelId: Int64,
    senderId: Int64,
    content: String,
    direction: String,  // "inbound" or "outbound"
    attachmentType: String? = nil,
    attachmentRef: String? = nil
) throws -> Int64 {
    try db.writer.write { dbConn in
        // Send as regular chat message
        try dbConn.execute(sql: """
            INSERT INTO chat_messages (channel_id, sender_id, message_type, content, created_at)
            VALUES (?, ?, 'text', ?, datetime('now'))
            """, arguments: [channelId, senderId, content])
        let messageId = dbConn.lastInsertedRowID

        // Get bridge for this channel
        let bridge = try Row.fetchOne(dbConn, sql: """
            SELECT id FROM supplier_channel_bridges
            WHERE channel_id = ? AND deleted_at IS NULL LIMIT 1
            """, arguments: [channelId])

        if let bridgeId: Int64 = bridge?["id"] {
            // Track as supplier message
            try dbConn.execute(sql: """
                INSERT INTO supplier_messages
                (message_id, bridge_id, direction, attachment_type, attachment_ref, created_at)
                VALUES (?, ?, ?, ?, ?, datetime('now'))
                """, arguments: [messageId, bridgeId, direction, attachmentType, attachmentRef])
        }

        return messageId
    }
}

/// Add an internal user to a supplier channel.
public func addUserToSupplierChannel(channelId: Int64, userId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            INSERT OR IGNORE INTO chat_channel_members (channel_id, user_id, role, joined_at)
            VALUES (?, ?, 'member', datetime('now'))
            """, arguments: [channelId, userId])
    }
}

/// Get supplier bridge info for a channel.
public func getSupplierBridge(channelId: Int64) throws -> SupplierChannelBridge? {
    try db.writer.read { dbConn in
        try SupplierChannelBridge.fetchOne(dbConn, sql: """
            SELECT * FROM supplier_channel_bridges
            WHERE channel_id = ? AND deleted_at IS NULL
            """, arguments: [channelId])
    }
}

/// Deactivate a supplier channel bridge (soft delete).
public func deactivateSupplierBridge(channelId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE supplier_channel_bridges SET is_active = 0, deleted_at = datetime('now')
            WHERE channel_id = ?
            """, arguments: [channelId])
    }
}
```

## Important Notes

- The bridge approach means suppliers don't need user accounts. An internal user sends/receives messages on the supplier's behalf through the channel. The `direction` field tracks whether a message is inbound (from supplier) or outbound (to supplier).
- `invite_token` is generated but not used yet for external access — it's a future hook for when suppliers can access channels directly (Phase S4).
- The `contact_id` is optional — a bridge can link to a general supplier or to a specific `entity_contacts` row.
- Supplier channels appear in the regular channels list with type badge "supplier" (green → change to orange or similar in the UI prompt).
- All messages in supplier channels are stored as regular `chat_messages` with additional supplier context in `supplier_messages`.
- The `attachmentRef` field supports PO number references, PDF paths, URLs — structured context for the conversation.

## Success Criteria

- [ ] Migration creates `supplier_channel_bridges` and `supplier_messages` tables
- [ ] `SupplierChannelBridge` and `SupplierMessage` model structs compile
- [ ] Tables added to ConflictResolver whitelist
- [ ] `createSupplierChannel()` creates channel + bridge + membership
- [ ] `listSupplierChannels()` returns channels with unread counts
- [ ] `sendSupplierMessage()` tracks direction (inbound/outbound)
- [ ] `addUserToSupplierChannel()` adds team members
- [ ] `deactivateSupplierBridge()` soft-deletes the bridge
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 22A Results (YYYY-MM-DD)
- Migration: supplier_channel_bridges + supplier_messages tables
- Models: SupplierChannelBridge, SupplierMessage
- ChatService: 6 supplier bridge methods
- Bridge approach: no supplier user accounts needed
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 22B.**
