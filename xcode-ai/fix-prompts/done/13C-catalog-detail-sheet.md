# Fix Prompt 13C: Catalog Page — Fix Part Detail Sheet

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.
>
> **DEPENDS ON:** Prompts 13A and 13B must be completed first.

---

## What the User Wants

When a user taps a part in the catalog list, a bottom sheet should open showing the part's full details. Currently this sheet exists (`PartDetailSheet`) but **doesn't work** — the user reported they can't expand/open parts to see details.

The detail sheet should be **read-only** for viewing, with an **Edit button** in the toolbar that opens the existing `PartFormSheet` for editing. The sheet should also show stock by location.

---

## File To Edit

**`Weird Parts IOS/Features/Parts/PartsCatalogPage.swift`**

### Step 1: Verify the Sheet Opens

The sheet is triggered by `activeSheet = .partDetail(part)` when a row is tapped (line 334). Verify this still works after the Prompt 01 changes (single `.sheet(item:)` enum). The `ActiveSheet` enum already has a `.partDetail(CatalogPartRow)` case.

If the sheet doesn't open, the most likely issue is the `CatalogPartRow` struct not conforming to something the `.sheet(item:)` needs. Check that `ActiveSheet` properly implements `Identifiable` and that each case returns a unique `id`.

### Step 2: Fix the PartDetailSheet Stock Loading

Find the `PartDetailSheet` struct (around line 997). It has a `stockEntries` state variable and loads stock data. Verify the stock query actually runs:

Check `loadStockEntries()` — if it's missing or empty, add it:

```swift
.task { await loadStockEntries() }

private func loadStockEntries() async {
    guard let db = appCore.db else { return }
    do {
        let entries = try await db.writer.read { conn -> [StockEntry] in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT s.id, s.location_type, s.location_id, s.qty,
                       COALESCE(wl.label, 'Location #' || s.location_id) AS location_label
                FROM stock s
                LEFT JOIN warehouse_locations wl ON wl.id = s.location_id
                WHERE s.part_id = ? AND s.qty > 0 AND s.deleted_at IS NULL
                ORDER BY s.location_type, s.location_id
                """, arguments: [partRow.id])
            return rows.map { row in
                StockEntry(
                    id: row["id"] ?? 0,
                    locationType: row["location_type"] ?? "warehouse",
                    locationId: row["location_id"] ?? 0,
                    locationLabel: row["location_label"] ?? "",
                    qty: row["qty"] ?? 0
                )
            }
        }
        await MainActor.run { stockEntries = entries }
    } catch {
        print("[PartDetailSheet] Stock load error: \(error)")
    }
}
```

### Step 3: Make Sure Edit Button Works

The detail sheet should have an Edit pencil button in the toolbar that opens `PartFormSheet`. Verify `showEditForm` state and the `.sheet(isPresented: $showEditForm)` work:

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Done") { dismiss() }
    }
    ToolbarItem(placement: .automatic) {
        Button {
            showEditForm = true
        } label: {
            Image(systemName: "pencil")
        }
    }
}
.sheet(isPresented: $showEditForm) {
    PartFormSheet(part: partRow, categories: categories, brands: brands) {
        await onUpdate()
    }
}
```

### Step 4: Verify StockEntry Model Exists

If `StockEntry` isn't defined in this file, add it:

```swift
private struct StockEntry: Identifiable {
    let id: Int64
    let locationType: String
    let locationId: Int64
    let locationLabel: String
    let qty: Int
}
```

### Step 5: Add Delete Confirmation

The swipe-to-delete on catalog rows (line 339-344) has no confirmation dialog. Add one:

```swift
@State private var partToDelete: CatalogPartRow?

// On the swipe action:
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        partToDelete = part
    } label: {
        Label("Delete", systemImage: "trash")
    }
    // ...existing edit swipe
}

// Add confirmation dialog:
.confirmationDialog(
    "Delete Part?",
    isPresented: Binding(
        get: { partToDelete != nil },
        set: { if !$0 { partToDelete = nil } }
    ),
    titleVisibility: .visible
) {
    Button("Delete", role: .destructive) {
        if let part = partToDelete {
            Task { await deletePart(part) }
        }
    }
    Button("Cancel", role: .cancel) { partToDelete = nil }
} message: {
    if let part = partToDelete {
        Text("Are you sure you want to delete \"\(part.name)\"? This cannot be undone.")
    }
}
```

---

## Success Criteria

1. Tapping a part row opens the detail sheet
2. Detail sheet shows: name, code, type, category, style, color, brand, status
3. Detail sheet shows pricing (cost, markup, sell price) if user has `show_dollar_values` permission
4. Detail sheet shows stock by location with quantities
5. Edit button (pencil icon) opens `PartFormSheet` for editing
6. After editing and saving, the detail sheet and catalog list both update
7. Swipe-to-delete shows a confirmation dialog before deleting

---

## When Done

Read and implement **prompt 13D-catalog-nl-search.md** next.
