# Prompt 14E — Categories: Smart Delete with Empty Shelf Mode

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Replace the current simple delete with an intelligent deletion system:

1. **Delete confirmation on ALL delete buttons** (categories, styles, types, brands, colors)
2. **Inventory check before delete** — if items in this group have stock > 0, don't hard-delete
3. **Empty Shelf Mode** — set stock targets to 0, stop reordering, let stock drain naturally
4. **Alternative part recommendation** — if an alternative part exists, show "Please switch to [Part X] instead of [Part Y]" message
5. **30-day deletion timer** — once stock hits 0, start a 30-day countdown. Resets if inventory rises above 0
6. **Office approval** — after 30 days, send to the Approvals page for final confirmation

## Files to Modify / Create

1. `core/Sources/WiredPartCore/Services/PartsService.swift` — add smart delete methods
2. `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — add `scheduled_deletions` table
3. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesEditorPanel.swift` — update delete buttons
4. `Weird Parts IOS/Weird Parts IOS/Features/Parts/SmartDeleteSheet.swift` — **NEW FILE** — the smart delete confirmation UI

## Step 1: Migration — Add scheduled_deletions Table

**File:** `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`

Add a new migration at the end of the migration chain (after the last existing migration). Find the pattern used for other migrations and add:

```swift
migrator.registerMigration("017_scheduled_deletions") { db in
    try db.create(table: "scheduled_deletions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("entity_type", .text).notNull()       // "category", "style", "type", "brand", "color", "part"
        t.column("entity_id", .integer).notNull()
        t.column("entity_name", .text).notNull()        // human-readable name for display
        t.column("reason", .text)                        // why it's being deleted
        t.column("status", .text).notNull().defaults(to: "draining")  // "draining", "pending_approval", "approved", "cancelled"
        t.column("stock_at_schedule", .integer).defaults(to: 0)       // stock level when scheduled
        t.column("stock_reached_zero_at", .text)         // ISO8601 timestamp when stock first hit 0
        t.column("delete_after", .text)                  // ISO8601 timestamp = stock_reached_zero_at + 30 days
        t.column("alternative_part_id", .integer)        // recommended replacement part
        t.column("alternative_part_name", .text)         // cached name for display
        t.column("scheduled_by", .integer)               // user who initiated
        t.column("approved_by", .integer)                // user who approved final delete
        t.column("approved_at", .text)
        t.column("deleted_at", .text)                    // soft delete
        t.column("created_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
        t.column("updated_at", .text).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }
}
```

## Step 2: Service Layer — Smart Delete Methods

**File:** `core/Sources/WiredPartCore/Services/PartsService.swift`

Add these methods:

### 2A. Check if entity has inventory

```swift
/// Check total stock for all parts under a hierarchy node.
/// Returns total stock count and list of parts with stock > 0.
struct InventoryCheck {
    let totalStock: Int
    let partsWithStock: [(partId: Int64, partName: String, stock: Int)]
    let alternativeParts: [(partId: Int64, partName: String, alternativeId: Int64, alternativeName: String)]
    var hasInventory: Bool { totalStock > 0 }
}

func checkInventoryForDeletion(entityType: String, entityId: Int64) throws -> InventoryCheck {
    try db.reader.read { db in
        // Build WHERE clause based on entity type
        let whereClause: String
        switch entityType {
        case "category": whereClause = "p.category_id = ?"
        case "style": whereClause = "p.style_id = ?"
        case "type": whereClause = "p.type_id = ?"
        case "brand": whereClause = "p.brand_id = ?"
        case "color": whereClause = "p.color_id = ?"
        case "part": whereClause = "p.id = ?"
        default: whereClause = "1=0"
        }

        // Get parts with stock
        let rows = try Row.fetchAll(db, sql: """
            SELECT p.id, p.name,
                   COALESCE((SELECT SUM(si.quantity) FROM stock_items si WHERE si.part_id = p.id), 0) AS stock
            FROM parts p
            WHERE \(whereClause) AND p.deleted_at IS NULL
            HAVING stock > 0
        """, arguments: [entityId])

        let partsWithStock = rows.map { row -> (partId: Int64, partName: String, stock: Int) in
            (row["id"], row["name"], row["stock"])
        }
        let totalStock = partsWithStock.reduce(0) { $0 + $1.stock }

        // Get alternative parts for parts with stock
        var alternatives: [(partId: Int64, partName: String, alternativeId: Int64, alternativeName: String)] = []
        for part in partsWithStock {
            let altRows = try Row.fetchAll(db, sql: """
                SELECT pa.part_id, pa.alternative_part_id, ap.name AS alt_name
                FROM part_alternatives pa
                JOIN parts ap ON ap.id = pa.alternative_part_id
                WHERE pa.part_id = ? AND ap.deleted_at IS NULL
                ORDER BY pa.preference ASC
                LIMIT 1
            """, arguments: [part.partId])
            for altRow in altRows {
                alternatives.append((
                    partId: part.partId,
                    partName: part.partName,
                    alternativeId: altRow["alternative_part_id"],
                    alternativeName: altRow["alt_name"]
                ))
            }
        }

        return InventoryCheck(totalStock: totalStock, partsWithStock: partsWithStock, alternativeParts: alternatives)
    }
}
```

### 2B. Schedule deletion (Empty Shelf Mode)

```swift
/// Put an entity into "Empty Shelf Mode" — sets stock targets to 0 and starts monitoring.
func scheduleEmptyShelfDeletion(entityType: String, entityId: Int64, entityName: String, reason: String?, scheduledBy: Int64?) throws -> Int64 {
    try db.writer.write { db in
        // Set all parts under this entity to: minStockLevel=0, maxStockLevel=0, targetStockLevel=0, reorderPoint=0
        let updateClause: String
        switch entityType {
        case "category": updateClause = "category_id = ?"
        case "style": updateClause = "style_id = ?"
        case "type": updateClause = "type_id = ?"
        case "brand": updateClause = "brand_id = ?"
        case "color": updateClause = "color_id = ?"
        case "part": updateClause = "id = ?"
        default: updateClause = "1=0"
        }

        try db.execute(sql: """
            UPDATE parts SET
                min_stock_level = 0, max_stock_level = 0,
                target_stock_level = 0, reorder_point = 0,
                is_deprecated = 1, deprecation_reason = 'Empty Shelf Mode — pending deletion',
                updated_at = CURRENT_TIMESTAMP
            WHERE \(updateClause) AND deleted_at IS NULL
        """, arguments: [entityId])

        // Check current stock level
        let currentStock = try Int.fetchOne(db, sql: """
            SELECT COALESCE(SUM(si.quantity), 0) FROM stock_items si
            JOIN parts p ON p.id = si.part_id
            WHERE p.\(updateClause.replacingOccurrences(of: " = ?", with: "")) = ? AND p.deleted_at IS NULL
        """, arguments: [entityId]) ?? 0

        // Find best alternative part
        let altRow = try Row.fetchOne(db, sql: """
            SELECT pa.alternative_part_id, ap.name FROM part_alternatives pa
            JOIN parts ap ON ap.id = pa.alternative_part_id
            JOIN parts p ON p.id = pa.part_id
            WHERE p.\(updateClause.replacingOccurrences(of: " = ?", with: "")) = ?
            AND ap.deleted_at IS NULL
            ORDER BY pa.preference ASC LIMIT 1
        """, arguments: [entityId])

        // Create scheduled deletion record
        let now = ISO8601DateFormatter().string(from: Date())
        let stockZeroAt = currentStock == 0 ? now : nil
        let deleteAfter: String? = if currentStock == 0 {
            ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)
        } else {
            nil
        }

        try db.execute(sql: """
            INSERT INTO scheduled_deletions
            (entity_type, entity_id, entity_name, reason, status, stock_at_schedule,
             stock_reached_zero_at, delete_after, alternative_part_id, alternative_part_name,
             scheduled_by, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
            entityType, entityId, entityName, reason,
            currentStock == 0 ? "pending_approval" : "draining",
            currentStock, stockZeroAt, deleteAfter,
            altRow?["alternative_part_id"] as Int64?, altRow?["name"] as String?,
            scheduledBy, now, now
        ])

        return db.lastInsertedRowID
    }
}
```

### 2C. List scheduled deletions (for approvals page)

```swift
struct ScheduledDeletion: Identifiable {
    let id: Int64
    let entityType: String
    let entityId: Int64
    let entityName: String
    let reason: String?
    let status: String
    let stockAtSchedule: Int
    let deleteAfter: String?
    let alternativePartId: Int64?
    let alternativePartName: String?
    let createdAt: String
}

func listScheduledDeletions(status: String? = nil) throws -> [ScheduledDeletion] {
    try db.reader.read { db in
        var sql = "SELECT * FROM scheduled_deletions WHERE deleted_at IS NULL"
        var args: [DatabaseValueConvertible] = []
        if let status {
            sql += " AND status = ?"
            args.append(status)
        }
        sql += " ORDER BY created_at DESC"
        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        return rows.map { row in
            ScheduledDeletion(
                id: row["id"], entityType: row["entity_type"], entityId: row["entity_id"],
                entityName: row["entity_name"], reason: row["reason"], status: row["status"],
                stockAtSchedule: row["stock_at_schedule"], deleteAfter: row["delete_after"],
                alternativePartId: row["alternative_part_id"], alternativePartName: row["alternative_part_name"],
                createdAt: row["created_at"]
            )
        }
    }
}

/// Approve a scheduled deletion — performs the actual soft delete.
func approveScheduledDeletion(id: Int64, approvedBy: Int64?) throws {
    try db.writer.write { db in
        let row = try Row.fetchOne(db, sql: "SELECT * FROM scheduled_deletions WHERE id = ?", arguments: [id])
        guard let row else { return }
        let entityType: String = row["entity_type"]
        let entityId: Int64 = row["entity_id"]
        let now = ISO8601DateFormatter().string(from: Date())

        // Perform the actual soft delete based on entity type
        let table: String
        switch entityType {
        case "category": table = "part_categories"
        case "style": table = "part_styles"
        case "type": table = "part_types"
        case "brand": table = "brands"
        case "color": table = "part_colors"
        case "part": table = "parts"
        default: return
        }
        try db.execute(sql: "UPDATE \(table) SET deleted_at = ? WHERE id = ?", arguments: [now, entityId])

        // Mark schedule as approved
        try db.execute(sql: """
            UPDATE scheduled_deletions SET status = 'approved', approved_by = ?, approved_at = ?, updated_at = ?
            WHERE id = ?
        """, arguments: [approvedBy, now, now, id])
    }
}

/// Cancel a scheduled deletion — restores stock targets and removes deprecation.
func cancelScheduledDeletion(id: Int64) throws {
    try db.writer.write { db in
        let row = try Row.fetchOne(db, sql: "SELECT * FROM scheduled_deletions WHERE id = ?", arguments: [id])
        guard let row else { return }
        let entityType: String = row["entity_type"]
        let entityId: Int64 = row["entity_id"]
        let now = ISO8601DateFormatter().string(from: Date())

        // Restore parts — remove deprecation flag (stock levels stay at 0; user can edit manually)
        let whereClause: String
        switch entityType {
        case "category": whereClause = "category_id = ?"
        case "style": whereClause = "style_id = ?"
        case "type": whereClause = "type_id = ?"
        case "brand": whereClause = "brand_id = ?"
        case "color": whereClause = "color_id = ?"
        case "part": whereClause = "id = ?"
        default: whereClause = "1=0"
        }
        try db.execute(sql: """
            UPDATE parts SET is_deprecated = 0, deprecation_reason = NULL, updated_at = ?
            WHERE \(whereClause) AND deleted_at IS NULL
        """, arguments: [now, entityId])

        // Cancel the schedule
        try db.execute(sql: """
            UPDATE scheduled_deletions SET status = 'cancelled', deleted_at = ?, updated_at = ?
            WHERE id = ?
        """, arguments: [now, now, id])
    }
}
```

## Step 3: Smart Delete Confirmation Sheet

**Create new file:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/SmartDeleteSheet.swift`

```swift
import SwiftUI
import WiredPartCore

/// Smart deletion sheet that checks inventory before deleting.
/// If inventory exists, offers "Empty Shelf Mode" instead of immediate delete.
struct SmartDeleteSheet: View {
    let entityType: String        // "category", "style", "type", etc.
    let entityId: Int64
    let entityName: String
    var onComplete: () async -> Void

    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    @State private var inventoryCheck: PartsService.InventoryCheck?
    @State private var isLoading = true
    @State private var isProcessing = false
    @State private var error: String?
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Checking inventory...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let check = inventoryCheck {
                    deleteContent(check)
                }
            }
            .navigationTitle("Delete \(entityName)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await checkInventory() }
        }
    }

    @ViewBuilder
    private func deleteContent(_ check: PartsService.InventoryCheck) -> some View {
        Form {
            if check.hasInventory {
                // Has stock — show Empty Shelf Mode option
                Section {
                    Label("This \(entityType) has \(check.totalStock) items in stock across \(check.partsWithStock.count) part(s).", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                } header: {
                    Text("Inventory Found")
                }

                // Show parts with stock
                Section("Parts with Stock") {
                    ForEach(check.partsWithStock, id: \.partId) { part in
                        HStack {
                            Text(part.partName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(part.stock) in stock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Alternative part recommendations
                if !check.alternativeParts.isEmpty {
                    Section("Recommended Replacements") {
                        ForEach(check.alternativeParts, id: \.partId) { alt in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Switch from **\(alt.partName)**")
                                    .font(.subheadline)
                                Label("Use **\(alt.alternativeName)** instead", systemImage: "arrow.right.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    TextField("Reason for removal (optional)", text: $reason)
                        .frame(minHeight: 44)
                }

                Section {
                    Button {
                        Task { await startEmptyShelfMode() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start Empty Shelf Mode")
                                    .fontWeight(.semibold)
                                Text("Stock targets set to 0. Once stock is fully used, a 30-day timer starts. Final approval required.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(isProcessing)
                } header: {
                    Text("Action")
                }

            } else {
                // No stock — safe to delete immediately (still confirm)
                Section {
                    Label("No inventory found. Safe to delete.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }

                if !check.alternativeParts.isEmpty {
                    Section("Note: Alternative Parts Exist") {
                        ForEach(check.alternativeParts, id: \.partId) { alt in
                            Text("**\(alt.partName)** has alternative **\(alt.alternativeName)**")
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await deleteImmediately() }
                    } label: {
                        HStack {
                            if isProcessing {
                                ProgressView()
                            }
                            Text("Delete Now")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isProcessing)
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Actions

    private func checkInventory() async {
        guard let service = appCore.partsService else {
            error = "Parts service not available"
            isLoading = false
            return
        }
        do {
            inventoryCheck = try service.checkInventoryForDeletion(entityType: entityType, entityId: entityId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func startEmptyShelfMode() async {
        guard let service = appCore.partsService else { return }
        isProcessing = true
        do {
            _ = try service.scheduleEmptyShelfDeletion(
                entityType: entityType, entityId: entityId, entityName: entityName,
                reason: reason.isEmpty ? nil : reason, scheduledBy: nil
            )
            await onComplete()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isProcessing = false
    }

    private func deleteImmediately() async {
        guard let service = appCore.partsService else { return }
        isProcessing = true
        do {
            // Direct soft-delete via existing service methods
            switch entityType {
            case "category": try service.deleteCategory(id: entityId)
            case "style": try service.deleteStyle(id: entityId)
            case "type": try service.deleteType(id: entityId)
            case "brand": try service.deleteBrand(id: entityId)
            case "color": try service.deleteColor(id: entityId)
            default: break
            }
            await onComplete()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isProcessing = false
    }
}
```

## Step 4: Wire Up Delete Buttons in Editor Panel

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesEditorPanel.swift`

### 4A. Add SmartDeleteSheet state

Add to `ActiveSheet` enum:

```swift
case smartDelete(entityType: String, entityId: Int64, entityName: String)
```

Add its `id` case:

```swift
case .smartDelete(let type, let id, _): return "smartDelete-\(type)-\(id)"
```

Add the sheet case in `.sheet(item:)`:

```swift
case .smartDelete(let type, let id, let name):
    SmartDeleteSheet(entityType: type, entityId: id, entityName: name) {
        await onRefresh()
    }
```

### 4B. Update all delete buttons to use SmartDeleteSheet

Replace each delete button to use the smart delete sheet instead of inline confirmation.

For `deleteCategoryButton`:
```swift
private func deleteCategoryButton(_ catId: Int64, name: String) -> some View {
    Button(role: .destructive) {
        activeSheet = .smartDelete(entityType: "category", entityId: catId, entityName: name)
    } label: {
        Label("Delete", systemImage: "trash")
    }
    .buttonStyle(.bordered)
    .tint(.red)
}
```

Apply the same pattern to `deleteStyleButton`, `deleteTypeButton`, `deleteColorButton`. Remove the old `.alert` confirmation and the `showDeleteConfirm`, `deleteAction`, `deleteConfirmTitle`, `deleteConfirmMessage` state variables.

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] New migration `017_scheduled_deletions` creates the table
- [ ] Every delete button opens SmartDeleteSheet (categories, styles, types, brands, colors)
- [ ] If entity has inventory: shows stock count, parts list, alternative part recommendations, "Empty Shelf Mode" button
- [ ] If entity has no inventory: shows "safe to delete" with immediate delete button
- [ ] Empty Shelf Mode: sets stock targets to 0, marks parts deprecated, creates `scheduled_deletions` record
- [ ] Alternative parts shown as "Please switch to [Part X] instead of [Part Y]"
- [ ] Error messages displayed inline if anything fails
- [ ] Old simple `.alert` delete confirmation removed

## Next

When all criteria are met, read and implement `xcode-ai/fix-prompts/14F-deletion-approval-page.md`.
