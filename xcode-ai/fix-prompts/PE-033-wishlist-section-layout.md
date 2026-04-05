# PE-033 — Wishlist: 3-Section Layout + Approval Flows

**GitHub Issue:** #93
**Plan:** `docs/plans/ios-wishlist-enhancements.md` (created this run)
**Priority:** Medium — baseline wishlist exists, this adds the meaningful approval flows

---

## Context

The wishlist page (`IOSWishlistPage.swift`) has a flat list with filter cards. Issue #93 defines a 3-section layout with different approval rules per section. The `wishlist_items` table (migration 057) exists with basic fields, but needs a few new columns for the approval flow logic.

**Current state:**
- `WishlistService.swift` has: `listItems()`, `createItem()`, `approveItem()`, `dismissItem()`, `sendToProcurement()`, `reopenItem()`
- `WishlistItem` model: `id`, `part_id`, `part_name`, `qty_suggested`, `reason`, `priority`, `source_type`, `status`, `requested_by`, `approved_by`, `approved_at`, `dismissed_by`, `dismissed_at`, `notes`, `created_at`, `updated_at`
- `source_type` values: `"manual"`, `"forecast"`, `"system"`

**What's missing (per #93 spec):**
- `dismiss_reason` — required for all dismissals
- `auto_approve_at` — computed timestamp (created_at + 14 days) for user-added items
- `certainty_score` — for forecast items (0.0–1.0)
- 3-section layout in the UI

---

## Task 1 — Core DB Migration

**File:** `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`

Add a new migration after migration 057:

```sql
-- Migration: wishlist_items_v2 — approval flows + certainty
ALTER TABLE wishlist_items ADD COLUMN dismiss_reason TEXT;
ALTER TABLE wishlist_items ADD COLUMN auto_approve_at DATETIME;
ALTER TABLE wishlist_items ADD COLUMN certainty_score REAL;
```

Register as `"057b_wishlist_items_v2"`.

---

## Task 2 — Update WishlistModels.swift

**File:** `core/Sources/WiredPartCore/Models/Orders/WishlistModels.swift`

Add the 3 new fields to `WishlistItem`:
```swift
public var dismissReason: String?
public var autoApproveAt: Date?
public var certaintyScore: Double?
```

Add `CodingKeys` enum if not already present to map snake_case ↔ camelCase.

---

## Task 3 — Update WishlistService.swift

**File:** `core/Sources/WiredPartCore/Services/WishlistService.swift`

### 3a. `createItem()` — set `auto_approve_at` for manual items
When `source_type == "manual"`, set `autoApproveAt = Date().addingTimeInterval(14 * 24 * 3600)`.
For `"forecast"` or `"system"` source types, leave `autoApproveAt` nil.

### 3b. `dismissItem()` — require reason
Update signature:
```swift
public func dismissItem(id: Int64, by dismisser: String, reason: String) throws -> WishlistItem
```
Store `reason` in the `dismiss_reason` column. If `reason` is empty, throw `WishlistServiceError.dismissReasonRequired`.

### 3c. `getSectionedItems()` — new method
```swift
public struct WishlistSections {
    public let userAdded: [WishlistItem]       // source_type = "manual"
    public let forecastDemand: [WishlistItem]  // source_type = "forecast"
    public let autoAdded: [WishlistItem]       // source_type = "system"
}

public func getSectionedItems(statusFilter: String? = nil) throws -> WishlistSections
```
Returns items split by `source_type`, each section filtered by `statusFilter` if provided, sorted by `created_at DESC`.

### 3d. `processAutoApprovals()` — auto-approve expired items
```swift
public func processAutoApprovals(by approver: String) throws -> Int
```
Finds all `status = "pending"` items where `auto_approve_at <= now()` and calls `approveItem()` on each. Returns count of auto-approved items. Call this in `getSectionedItems()` before fetching, so the UI always shows current state.

---

## Task 4 — Rebuild IOSWishlistPage.swift

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSWishlistPage.swift`

Replace the flat list with a 3-section layout.

### State changes
```swift
@State private var sections = WishlistService.WishlistSections(userAdded: [], forecastDemand: [], autoAdded: [])
```
Remove `@State private var allItems` and `statusFilter`.

### Section layout
Replace `wishlistList` with `sectionsView`:
```swift
private var sectionsView: some View {
    List {
        // Section 1: User Added
        Section {
            ForEach(sections.userAdded) { item in
                wishlistRow(item)
            }
        } header: {
            sectionHeader("User Added", count: sections.userAdded.count,
                         subtitle: "Auto-approves after 14 days if no action")
        }

        // Section 2: Forecast Demand
        Section {
            ForEach(sections.forecastDemand) { item in
                wishlistRow(item)
            }
        } header: {
            sectionHeader("Forecast Demand", count: sections.forecastDemand.count,
                         subtitle: "System suggestions based on usage patterns")
        }

        // Section 3: System Auto-Added
        Section {
            ForEach(sections.autoAdded) { item in
                wishlistRow(item)
            }
        } header: {
            sectionHeader("System Auto-Added", count: sections.autoAdded.count,
                         subtitle: "Below MIN with no stock at shop")
        }
    }
}
```

### Row enhancements
In `wishlistRow()`:
- **User Added items:** Show auto-approve countdown if `autoApproveAt` is set and item is pending. Format as "Auto-approves in X days" in secondary text.
- **Forecast items:** Show certainty score as a colored badge if `certaintyScore != nil`:
  - ≥ 0.80 → green badge "High confidence"
  - < 0.80 → orange badge "Review needed — verify stock manually"
- **All items:** Show `ActionDot` (red) on rows that are pending and overdue or high-certainty forecast

### Dismiss sheet — require reason
Replace the direct swipe-to-dismiss action with a sheet:
```swift
case .dismiss(let item):
    DismissWishlistItemSheet(item: item, onDismiss: { reason in
        dismissItem(item, reason: reason)
    })
    .environmentObject(appCore)
```

Add `DismissWishlistItemSheet` as a struct in the same file:
- Title: "Dismiss Item"
- Required `TextEditor` for reason (min 10 chars, shows character count)
- Cancel + Dismiss buttons
- "Dismiss reason is required" inline error if empty

### loadData() update
```swift
private func loadData() async {
    isLoading = true
    loadError = nil
    do {
        sections = try appCore.wishlistService.getSectionedItems()
    } catch {
        loadError = error.localizedDescription
    }
    isLoading = false
}
```

Remove smart card filter state — sections replace the filter pattern for this page.

---

## Task 5 — Tests

**File:** `core/Tests/WiredPartCoreTests/WishlistServiceTests.swift`

Add:
1. `testAutoApproveAtSetOnManualCreate()` — manual item gets `autoApproveAt` = now + 14 days (±5 seconds tolerance)
2. `testForecastItemNoAutoApproveAt()` — forecast item has nil `autoApproveAt`
3. `testDismissRequiresReason()` — empty reason throws `dismissReasonRequired`
4. `testDismissWithReason()` — valid reason saves to `dismiss_reason` column
5. `testProcessAutoApprovals()` — item with expired `auto_approve_at` gets approved, unexpired does not
6. `testGetSectionedItems()` — 3 items with different `source_type` values return in correct sections

---

## Verification

After applying:
- `swift build` in `core/` — 0 errors, 0 warnings
- `swift test` in `core/` — all existing + 6 new tests pass
- iOS: Wishlist page shows 3 named sections
- iOS: Pending user-added item shows "Auto-approves in X days"
- iOS: Forecast item with <0.8 certainty shows orange "Review needed" badge
- iOS: Dismiss swipe opens DismissWishlistItemSheet, empty reason blocks dismiss
