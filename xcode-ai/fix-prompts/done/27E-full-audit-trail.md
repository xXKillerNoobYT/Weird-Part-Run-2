# 27E — Full Audit Trail: Part Change History Logging

> **Chain position:** 27A → 27B → 27C → 27D → **27E**
> **Prerequisite:** 27D complete (Hold + Chat)
> **Plan:** `docs/plans/ios-jpo-page.md` — Full Part History / Audit Trail
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement. When done, wait for user confirmation before proceeding.

## Context

**CROSS-CUTTING FEATURE:** Every part change in the entire app needs to be logged with who did it and when. This applies to ALL part modifications — name, code, category, style, type, brand, color, pricing, stock levels, and any other field. The audit trail must be visible when clicking into a part detail view.

This is NOT just for JPOs — it's a system-wide feature. The motivation: "James made a parts list, Jarrett changed a part to make them look stupid. The log shows Jarrett did it."

**Files to read first:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — existing `_change_log` table for sync
- `core/Sources/WiredPartCore/Services/PartsService.swift` — part CRUD methods (update, pricing, etc.)
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — Part struct

**Files to create:**
- Part history view component (reusable)

**Files to modify:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — new migration
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add logging to CRUD methods
- `Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsCatalogPage.swift` — add history to part detail

## Task

### Step 1: Migration — part_change_log table

Add a new migration for the audit trail table:

```swift
private static func registerMigration033PartChangeLog(_ migrator: inout DatabaseMigrator) {
    migrator.registerMigration("033_part_change_log") { db in
        try db.create(table: "part_change_log") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("part_id", .integer).notNull()
                .references("parts", onDelete: .cascade)
            t.column("user_id", .integer)
                .references("users", onDelete: .setNull)
            t.column("user_name", .text)          // denormalized for display
            t.column("action", .text).notNull()    // "created", "updated", "deleted", "restored"
            t.column("field_name", .text)           // which field changed (null for create/delete)
            t.column("old_value", .text)            // previous value (null for create)
            t.column("new_value", .text)            // new value (null for delete)
            t.column("context", .text)              // optional: "JPO #127", "Catalog Edit", "Import"
            t.column("created_at", .text).notNull()
                .defaults(sql: "(datetime('now'))")
        }
        try db.create(index: "idx_pcl_part", on: "part_change_log", columns: ["part_id"])
        try db.create(index: "idx_pcl_user", on: "part_change_log", columns: ["user_id"])
        try db.create(index: "idx_pcl_date", on: "part_change_log", columns: ["created_at"])
        try db.create(index: "idx_pcl_action", on: "part_change_log", columns: ["part_id", "action"])
    }
}
```

Register it in `registerMigrations()`.

### Step 2: Add logging helper to PartsService

Add a reusable method that logs a part change:

```swift
/// Log a change to a part for the audit trail.
public func logPartChange(
    partId: Int64,
    userId: Int64?,
    userName: String?,
    action: String,
    fieldName: String? = nil,
    oldValue: String? = nil,
    newValue: String? = nil,
    context: String? = nil
) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(
            sql: """
                INSERT INTO part_change_log
                (part_id, user_id, user_name, action, field_name, old_value, new_value, context)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [partId, userId, userName, action, fieldName, oldValue, newValue, context]
        )
    }
}

/// Log multiple field changes for a single part update.
public func logPartFieldChanges(
    partId: Int64,
    userId: Int64?,
    userName: String?,
    changes: [(field: String, oldValue: String?, newValue: String?)],
    context: String? = nil
) throws {
    try db.writer.write { dbConn in
        for change in changes {
            try dbConn.execute(
                sql: """
                    INSERT INTO part_change_log
                    (part_id, user_id, user_name, action, field_name, old_value, new_value, context)
                    VALUES (?, ?, ?, 'updated', ?, ?, ?, ?)
                    """,
                arguments: [partId, userId, userName, change.field, change.oldValue, change.newValue, context]
            )
        }
    }
}

/// Get the change history for a part.
public func getPartChangeLog(partId: Int64, limit: Int = 50) throws -> [PartChangeEntry] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT * FROM part_change_log
            WHERE part_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """, arguments: [partId, limit])
        return rows.map { PartChangeEntry(
            id: $0["id"],
            partId: $0["part_id"],
            userId: $0["user_id"],
            userName: $0["user_name"],
            action: $0["action"],
            fieldName: $0["field_name"],
            oldValue: $0["old_value"],
            newValue: $0["new_value"],
            context: $0["context"],
            createdAt: $0["created_at"]
        )}
    }
}
```

Add the model struct:

```swift
public struct PartChangeEntry: Identifiable, Sendable {
    public let id: Int64
    public let partId: Int64
    public let userId: Int64?
    public let userName: String?
    public let action: String
    public let fieldName: String?
    public let oldValue: String?
    public let newValue: String?
    public let context: String?
    public let createdAt: String?
}
```

### Step 3: Wire logging into existing update methods

Find the `updatePart` method in PartsService and add change detection + logging. Before updating, read the current values, compare, and log differences:

```swift
// At the start of updatePart, before the UPDATE statement:
let currentPart = try Part.fetchOne(dbConn, sql: "SELECT * FROM parts WHERE id = ?", arguments: [partId])
// ... after update, compare fields and call logPartFieldChanges
```

The key fields to track:
- `name`, `code`, `description`
- `category_id`, `style_id`, `type_id`, `brand_id`, `color_id`
- `company_cost_price`, `company_sell_price`, `markup_percent`
- `min_stock_level`, `max_stock_level`, `target_stock_level`
- `upc`, `manufacturer_part_number`

Also log:
- Part creation in `createPart`
- Part deletion/restoration in soft-delete methods
- Pricing changes in `setPricingTier`, `addCostLayer`
- Category/brand/type reassignment

### Step 4: Create reusable PartHistoryView

Create a reusable SwiftUI component for displaying the audit trail:

```swift
/// Reusable view showing the change history for a part.
struct PartHistoryView: View {
    @EnvironmentObject private var appCore: AppCore
    let partId: Int64

    @State private var entries: [PartsService.PartChangeEntry] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if entries.isEmpty {
                Text("No changes recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    historyRow(entry)
                }
            }
        }
        .task { loadHistory() }
    }

    @ViewBuilder
    private func historyRow(_ entry: PartsService.PartChangeEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timeline dot
            Circle()
                .fill(actionColor(entry.action))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                // Who + when
                HStack {
                    Text(entry.userName ?? "System")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if let date = entry.createdAt {
                        Text(formatDate(date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // What changed
                switch entry.action {
                case "created":
                    Text("Created this part")
                        .font(.caption)
                        .foregroundStyle(.green)
                case "deleted":
                    Text("Deleted this part")
                        .font(.caption)
                        .foregroundStyle(.red)
                case "restored":
                    Text("Restored this part")
                        .font(.caption)
                        .foregroundStyle(.blue)
                case "updated":
                    if let field = entry.fieldName {
                        HStack(spacing: 4) {
                            Text(field.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                            if let old = entry.oldValue, let new = entry.newValue {
                                Text("\(old) → \(new)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let new = entry.newValue {
                                Text("set to \(new)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                default:
                    Text(entry.action)
                        .font(.caption)
                }

                // Context
                if let ctx = entry.context {
                    Text(ctx)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "created": .green
        case "deleted": .red
        case "restored": .blue
        case "updated": .orange
        default: .secondary
        }
    }

    private func formatDate(_ iso: String) -> String {
        // Simple date formatting — show relative if recent, absolute if older
        let prefix = String(iso.prefix(10))
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        if prefix == String(today) { return "Today" }
        return prefix
    }

    private func loadHistory() {
        guard let service = appCore.partsService else {
            isLoading = false
            return
        }
        do {
            entries = try service.getPartChangeLog(partId: partId)
        } catch { }
        isLoading = false
    }
}
```

### Step 5: Add history section to part detail

Find the part detail sheet/view (in PartsCatalogPage or wherever parts are displayed in detail) and add a collapsible history section:

```swift
// In the part detail view:
Section("Change History") {
    DisclosureGroup("View History") {
        PartHistoryView(partId: part.id!)
    }
}
```

## Important Notes

- This is a **cross-cutting feature** — it applies to ALL part modifications across the entire app
- The `user_name` field is denormalized for display efficiency (don't JOIN on every history query)
- The `context` field provides location context: "Catalog Edit", "JPO #127", "Import", "Procurement", etc.
- The `_change_log` table used for sync is DIFFERENT — it's for sync operations. This `part_change_log` is for human-readable audit trail.
- Start with logging in `updatePart` and `createPart`. Other methods (pricing, category changes) can be wired in follow-up work.
- The `PartHistoryView` is reusable — it can be placed on any page that shows a part
- For large part histories, the `LIMIT 50` prevents performance issues. Add "Load More" later if needed.
- Field comparison should use String representations for logging — convert IDs to names where practical.

## Success Criteria

- [ ] Migration creates `part_change_log` table with indexes
- [ ] `logPartChange` and `logPartFieldChanges` service methods
- [ ] `getPartChangeLog` returns history ordered by date desc
- [ ] `PartChangeEntry` model struct
- [ ] `PartHistoryView` reusable component with timeline display
- [ ] History section added to part detail (collapsible)
- [ ] Logging wired into `updatePart` (field-level diff detection)
- [ ] Logging wired into `createPart` (action = "created")
- [ ] Migration registered in registerMigrations()
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 27E Results (YYYY-MM-DD)
- part_change_log table with migration
- Logging helpers: single change + multi-field changes
- PartHistoryView reusable timeline component
- Wired into updatePart + createPart
- Build: [PASS/FAIL]
```

**JPO prompt chain complete. Continue to next Orders page review.**
