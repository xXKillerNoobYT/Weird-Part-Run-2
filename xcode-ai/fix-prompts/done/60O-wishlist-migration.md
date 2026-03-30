# 60O — Wishlist Migration, Service & Functional Page

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The wishlist feature was designed but never built. The `wishlist_items` migration was never created, `IOSWishlistPage` is a placeholder showing "Coming Soon", and there is no `WishlistService`. Build all three: migration, service, and functional page.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSWishlistPage.swift` — current placeholder
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — see the pattern for migrations (last is 055_office_channel)
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — see the service pattern (db, public methods, error handling)
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift` — see how services are wired up

## Task

### Step 1: Create migration 056_wishlist_items

In `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`:

1. Add `registerMigration056WishlistItems(&migrator)` to the migrator registration list (after line calling `registerMigration055OfficeChannel`).

2. Add the migration function:

```swift
// MARK: - 056: Wishlist Items

extension AppDatabase {
    private static func registerMigration056WishlistItems(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("056_wishlist_items") { db in
            try db.create(table: "wishlist_items") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).notNull()
                    .references("parts", onDelete: .cascade)
                t.column("source_type", .text).notNull().defaults(to: "manual")
                    // "manual", "forecast", "min_stock", "companion"
                t.column("qty_suggested", .integer).notNull().defaults(to: 1)
                t.column("reason", .text)
                t.column("added_by", .integer)
                    .references("users", onDelete: .setNull)
                t.column("location_type", .text)
                t.column("location_id", .integer)
                t.column("priority", .text).notNull().defaults(to: "normal")
                    // "urgent", "high", "normal", "low"
                t.column("status", .text).notNull().defaults(to: "pending")
                    // "pending", "approved", "dismissed", "sent_to_procurement"
                t.column("auto_added", .integer).notNull().defaults(to: 0)
                t.column("auto_approve_at", .text)
                t.column("approved_by", .integer)
                    .references("users", onDelete: .setNull)
                t.column("approved_at", .text)
                t.column("dismissed_by", .integer)
                    .references("users", onDelete: .setNull)
                t.column("dismissed_reason", .text)
                t.column("sent_to_procurement_at", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("deleted_at", .text)
            }

            try db.create(index: "idx_wishlist_part", on: "wishlist_items", columns: ["part_id"])
            try db.create(index: "idx_wishlist_status", on: "wishlist_items", columns: ["status"])
            try db.create(index: "idx_wishlist_priority", on: "wishlist_items", columns: ["priority"])
        }
    }
}
```

### Step 2: Create WishlistService

Create `core/Sources/WiredPartCore/Services/WishlistService.swift`:

```swift
import Foundation
import GRDB

/// Service for managing wishlist items — parts that should be ordered.
public final class WishlistService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Models

    public struct WishlistItem: Codable, Identifiable, Sendable, FetchableRecord {
        public let id: Int64
        public let partId: Int64
        public let sourceType: String
        public let qtySuggested: Int
        public let reason: String?
        public let addedBy: Int64?
        public let locationType: String?
        public let locationId: Int64?
        public let priority: String
        public let status: String
        public let autoAdded: Bool
        public let autoApproveAt: String?
        public let approvedBy: Int64?
        public let approvedAt: String?
        public let dismissedBy: Int64?
        public let dismissedReason: String?
        public let sentToProcurementAt: String?
        public let createdAt: String
        public let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id, reason, priority, status
            case partId = "part_id"
            case sourceType = "source_type"
            case qtySuggested = "qty_suggested"
            case addedBy = "added_by"
            case locationType = "location_type"
            case locationId = "location_id"
            case autoAdded = "auto_added"
            case autoApproveAt = "auto_approve_at"
            case approvedBy = "approved_by"
            case approvedAt = "approved_at"
            case dismissedBy = "dismissed_by"
            case dismissedReason = "dismissed_reason"
            case sentToProcurementAt = "sent_to_procurement_at"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    /// Wishlist item with part name joined.
    public struct WishlistItemWithPart: Identifiable, Sendable {
        public let id: Int64
        public let partName: String
        public let partNumber: String?
        public let partId: Int64
        public let sourceType: String
        public let qtySuggested: Int
        public let reason: String?
        public let priority: String
        public let status: String
        public let createdAt: String
    }

    // MARK: - CRUD

    /// List all active wishlist items with part names.
    public func listItems(status: String? = nil, priority: String? = nil) throws -> [WishlistItemWithPart] {
        try db.writer.read { dbConn in
            var sql = """
                SELECT wi.id, wi.part_id, wi.source_type, wi.qty_suggested, wi.reason,
                       wi.priority, wi.status, wi.created_at,
                       p.name AS part_name, p.part_number
                FROM wishlist_items wi
                JOIN parts p ON p.id = wi.part_id
                WHERE wi.deleted_at IS NULL
                """
            var args: [DatabaseValueConvertible] = []

            if let status {
                sql += " AND wi.status = ?"
                args.append(status)
            }
            if let priority {
                sql += " AND wi.priority = ?"
                args.append(priority)
            }

            sql += " ORDER BY CASE wi.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END, wi.created_at DESC"

            let rows = try Row.fetchAll(dbConn, sql: sql, arguments: StatementArguments(args))
            return rows.map { row in
                WishlistItemWithPart(
                    id: row["id"],
                    partName: row["part_name"] ?? "Unknown",
                    partNumber: row["part_number"],
                    partId: row["part_id"],
                    sourceType: row["source_type"] ?? "manual",
                    qtySuggested: row["qty_suggested"] ?? 1,
                    reason: row["reason"],
                    priority: row["priority"] ?? "normal",
                    status: row["status"] ?? "pending",
                    createdAt: row["created_at"] ?? ""
                )
            }
        }
    }

    /// Add an item to the wishlist.
    public func addItem(partId: Int64, qty: Int, reason: String?, priority: String = "normal", sourceType: String = "manual", addedBy: Int64? = nil) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO wishlist_items (part_id, qty_suggested, reason, priority, source_type, added_by)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [partId, qty, reason, priority, sourceType, addedBy])
            return dbConn.lastInsertedRowID
        }
    }

    /// Approve a wishlist item.
    public func approveItem(id: Int64, approvedBy: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE wishlist_items SET status = 'approved', approved_by = ?, approved_at = datetime('now'), updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [approvedBy, id])
        }
    }

    /// Dismiss a wishlist item.
    public func dismissItem(id: Int64, dismissedBy: Int64, reason: String?) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE wishlist_items SET status = 'dismissed', dismissed_by = ?, dismissed_reason = ?, updated_at = datetime('now')
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [dismissedBy, reason, id])
        }
    }

    /// Send approved items to procurement.
    public func sendToProcurement(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try db.writer.write { dbConn in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            var args: [DatabaseValueConvertible] = []
            args.append(contentsOf: ids)
            try dbConn.execute(sql: """
                UPDATE wishlist_items SET status = 'sent_to_procurement', sent_to_procurement_at = datetime('now'), updated_at = datetime('now')
                WHERE id IN (\(placeholders)) AND deleted_at IS NULL
                """, arguments: StatementArguments(args))
        }
    }

    /// Delete (soft) a wishlist item.
    public func deleteItem(id: Int64) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE wishlist_items SET deleted_at = datetime('now') WHERE id = ?
                """, arguments: [id])
        }
    }

    /// Get counts by status for smart cards.
    public func getStatusCounts() throws -> [String: Int] {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT status, COUNT(*) AS cnt FROM wishlist_items
                WHERE deleted_at IS NULL
                GROUP BY status
                """)
            var result: [String: Int] = [:]
            for row in rows {
                if let status = row["status"] as String?, let count = row["cnt"] as Int? {
                    result[status] = count
                }
            }
            return result
        }
    }
}
```

### Step 3: Wire WishlistService into AppCore

In `AppCore.swift`:

1. Add property: `public private(set) var wishlistService: WishlistService?`
2. In the `initializeServices` (or equivalent setup method), add: `wishlistService = WishlistService(db: database)`
3. In the teardown/reset, add: `wishlistService = nil`

### Step 4: Replace IOSWishlistPage placeholder with functional page

Replace the entire contents of `IOSWishlistPage.swift` with a functional page:

- Smart cards at top showing counts by status (pending, approved, dismissed)
- Filter by status and priority
- List of wishlist items showing: part name, quantity, source type badge, priority badge, reason
- Swipe actions: Approve, Dismiss, Delete
- "Add to Wishlist" button in toolbar that shows a sheet to search parts and add them
- Pull-to-refresh with `.refreshable`
- Empty state using `EmptyStateView` (not ContentUnavailableView)
- Error display using `ErrorBanner` or inline error text
- Uses `@EnvironmentObject var appCore: AppCore` to access `wishlistService`
- Uses ActiveSheet enum pattern for sheets (`.help`, `.addItem`)

## Files to Modify

- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — add migration 056
- `core/Sources/WiredPartCore/Services/WishlistService.swift` — CREATE new service
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift` — wire WishlistService
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSWishlistPage.swift` — replace placeholder with functional page

## Success Criteria

- [ ] Migration 056_wishlist_items creates the `wishlist_items` table with all columns
- [ ] WishlistService has `listItems`, `addItem`, `approveItem`, `dismissItem`, `sendToProcurement`, `deleteItem`, `getStatusCounts`
- [ ] AppCore exposes `wishlistService` property
- [ ] IOSWishlistPage shows smart cards with status counts
- [ ] IOSWishlistPage lists items with part name, qty, priority, source type
- [ ] IOSWishlistPage supports swipe-to-approve and swipe-to-dismiss
- [ ] IOSWishlistPage has "Add to Wishlist" toolbar button
- [ ] IOSWishlistPage uses ActiveSheet pattern, EmptyStateView, .refreshable
- [ ] No force unwraps, no empty catch blocks
- [ ] Builds without errors
