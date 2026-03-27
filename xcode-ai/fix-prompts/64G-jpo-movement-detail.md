# 64G — JPO Movement Detail: Replace "Coming Soon" Stub

> **Chain position:** After 64F, standalone OK
> **Priority:** MEDIUM — users see "Coming Soon" when tapping a movement from JPO detail
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

In `IOSJPODetailPage.swift`, the `.viewMovement(let movementId)` sheet case (line ~172) shows a placeholder with an icon and "Coming Soon" text. Replace it with a real movement detail view that loads and displays the movement data.

**Read these files first:**
- `Features/Orders/IOSJPODetailPage.swift` — the `.viewMovement` case (~line 172-190)
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` — look for methods to query `stock_movements` by ID
- `Features/Warehouse/WarehouseMovementsPage.swift` — reference for how movements are displayed elsewhere

## Context

The JPO detail page tracks warehouse movements associated with a job purchase order. When the user taps a movement row, it opens a sheet that currently says "View this movement in Warehouse -> Movements for full details." This is unhelpful — show the actual data.

The `stock_movements` table has columns: `id`, `part_id`, `qty`, `from_location_type`, `from_location_id`, `to_location_type`, `to_location_id`, `movement_type`, `reason`, `notes`, `performed_by`, `created_at`.

## Task

### Step 1: Add a method to WarehouseService to fetch a single movement

Check if a `getMovementById` or similar method already exists. If not, add one:

```swift
public func getMovementById(id: Int64) throws -> StockMovementDetail? {
    try db.reader.read { dbConn in
        try Row.fetchOne(dbConn, sql: """
            SELECT sm.*,
                   p.name as part_name,
                   p.sku as part_sku
            FROM stock_movements sm
            LEFT JOIN parts p ON p.id = sm.part_id
            WHERE sm.id = ?
        """, arguments: [id])
    }.map { row in
        StockMovementDetail(
            id: row["id"],
            partId: row["part_id"],
            partName: row["part_name"] ?? "Unknown Part",
            partSku: row["part_sku"],
            qty: row["qty"],
            fromLocationType: row["from_location_type"],
            fromLocationId: row["from_location_id"],
            toLocationType: row["to_location_type"],
            toLocationId: row["to_location_id"],
            movementType: row["movement_type"],
            reason: row["reason"],
            notes: row["notes"],
            performedBy: row["performed_by"],
            createdAt: row["created_at"]
        )
    }
}
```

If `StockMovementDetail` doesn't exist as a struct, create it in the WarehouseService file (or a Models file). Match column names and types to what the table actually has. Adapt the SQL and struct to match the real schema.

### Step 2: Replace the stub view in IOSJPODetailPage

Replace the `.viewMovement` case content (lines ~172-190) with a real detail view:

```swift
case .viewMovement(let movementId):
    NavigationStack {
        MovementDetailContent(movementId: movementId)
            .environmentObject(appCore)
            .navigationTitle("Movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
            }
    }
```

### Step 3: Create `MovementDetailContent` as a private view

Add this as a private struct within `IOSJPODetailPage.swift` (or as a separate small file if the page is already large):

```swift
private struct MovementDetailContent: View {
    @EnvironmentObject var appCore: AppCore
    let movementId: Int64

    @State private var movement: StockMovementDetail?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading movement...")
            } else if let error = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let m = movement {
                List {
                    // Type & Status
                    Section("Movement Info") {
                        LabeledContent("Type", value: m.movementType ?? "Unknown")
                        LabeledContent("Quantity", value: "\(m.qty ?? 0)")
                        if let reason = m.reason, !reason.isEmpty {
                            LabeledContent("Reason", value: reason)
                        }
                    }

                    // Part Info
                    Section("Part") {
                        LabeledContent("Name", value: m.partName)
                        if let sku = m.partSku, !sku.isEmpty {
                            LabeledContent("SKU", value: sku)
                        }
                    }

                    // Locations
                    Section("Locations") {
                        if let fromType = m.fromLocationType {
                            LabeledContent("From", value: "\(fromType) #\(m.fromLocationId ?? 0)")
                        }
                        if let toType = m.toLocationType {
                            LabeledContent("To", value: "\(toType) #\(m.toLocationId ?? 0)")
                        }
                    }

                    // Who & When
                    Section("Details") {
                        if let by = m.performedBy, !by.isEmpty {
                            LabeledContent("Performed By", value: by)
                        }
                        if let date = m.createdAt {
                            LabeledContent("Date", value: date)
                        }
                        if let notes = m.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(notes)
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Link to Movements page
                    Section {
                        NavigationLink {
                            WarehouseMovementsPage()
                                .environmentObject(appCore)
                        } label: {
                            Label("View All Movements", systemImage: "arrow.left.arrow.right")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView("Movement Not Found", systemImage: "questionmark.circle", description: Text("Movement #\(movementId) could not be loaded."))
            }
        }
        .task {
            await loadMovement()
        }
    }

    private func loadMovement() async {
        guard let service = appCore.warehouseService else {
            loadError = "Warehouse service not available"
            isLoading = false
            return
        }
        do {
            movement = try service.getMovementById(id: movementId)
        } catch {
            loadError = userFriendlyError(error, context: "load movement")
        }
        isLoading = false
    }
}
```

**Adapt as needed:** If `WarehouseMovementsPage` is named differently, or if the navigation link doesn't make sense in a sheet context, use a plain text link or remove it. Check actual type names and column types — adjust optionals and type casts to match the real data model.

### Step 4: Verify the `StockMovementDetail` struct fields match the schema

Read the actual `stock_movements` table definition (in the migrations file) and ensure every field name and type is correct. Common issues:
- `qty` might be `Int` not `Int64`
- `created_at` might need date parsing
- `performed_by` might be an employee ID (Int64) not a name string — if so, join to get the name

## Success Criteria

- [ ] Tapping a movement in JPO detail shows real movement data (not "Coming Soon")
- [ ] Movement detail shows: type, part name, quantity, from/to locations, who, when, notes
- [ ] Error states handled (missing movement, service unavailable)
- [ ] "View All Movements" link provided
- [ ] `getMovementById()` method added to WarehouseService (if it didn't exist)
- [ ] Project builds with zero errors
- [ ] Log entry added to `xcode-ai/prompt-results-log.md`

## Log Entry

```
## Prompt 64G — JPO Movement Detail
**Date:** YYYY-MM-DD
**Status:** ✅ / ❌
**Files changed:** (list)
**What changed:** Movement stub replaced with real detail view, service method added
**Build:** PASS / FAIL
```
