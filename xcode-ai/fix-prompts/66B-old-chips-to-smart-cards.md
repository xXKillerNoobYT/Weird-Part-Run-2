# 66B — Convert Old Capsule Chips to SmartFilterCard (3 Pages)

> **Chain position:** **66B** (standalone)
> **Issue:** Inconsistent filter UI — 3 pages still use old capsule chip style
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT change any filter logic or data — only change the UI presentation
2. DO NOT remove any filter options — every existing chip must become a SmartFilterCard
3. Each SmartFilterCard must show a COUNT of matching items (not just a label)
4. Selected state must use accent color highlight with border
5. Project must build with zero errors when done

## Context

The app standard for filter bars is `SmartFilterCard` — a tappable card showing the filter label AND a count, with a selected highlight state. Three pages still use the old capsule chip style (small `Capsule()` pills in a horizontal scroll). Convert them to match the app standard.

**Reference implementation** (from IOSPurchaseOrdersPage.swift):

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        let total = statusCounts.values.reduce(0, +)
        SmartFilterCard(
            title: "All",
            count: total,
            isSelected: statusFilter == "all",
            action: { statusFilter = "all"; loadData() }
        )
        ForEach(statusOptions.dropFirst(), id: \.self) { status in
            SmartFilterCard(
                title: status.replacingOccurrences(of: "_", with: " ").capitalized,
                count: statusCounts[status] ?? 0,
                isSelected: statusFilter == status,
                action: { statusFilter = status; loadData() }
            )
        }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
}
```

`SmartFilterCard` is defined in `Weird Parts IOS/Weird Parts IOS/Shared/SmartFilterCard.swift`. It already exists — do NOT recreate it.

## Files to Modify

### 1. IOSToolRegistryPage.swift

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolRegistryPage.swift`

Search for any remaining `Capsule()` used in a filter picker context (not in badge styling). If the status picker already uses `SmartFilterCard`, verify:
- "All" card is the first option with total count
- Each status option shows its count from `statusCounts`
- Selected state highlights correctly
- The filter calls `loadData()` after changing

Also check for any **category** or **type** filter chips that still use `Capsule()` style. The `categoryBadge` and `statusBadge` helper functions that style inline badges with `Capsule()` are fine — those are row decorations, not filter pickers. Only convert filter selection UI.

### 2. IOSEmployeesPage.swift

**File:** `Weird Parts IOS/Weird Parts IOS/Features/People/IOSEmployeesPage.swift`

Same pattern. Check the status filter section. If it already uses `SmartFilterCard`, verify:
- "All" card first with total count
- Status options: Active, Inactive, Suspended (or whatever statuses exist)
- Each card shows count from loaded data
- Tapping triggers `loadData()`

Check for any remaining `Capsule()` filter chips that aren't badge decorations.

### 3. IOSJobNotebooksPage.swift

**File:** `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/IOSJobNotebooksPage.swift`

Same pattern. Check the status filter section. If it already uses `SmartFilterCard`, verify:
- "All" card first with total count
- Status options: Active, Archived, Locked (or whatever statuses exist)
- Each card shows count from loaded data
- Tapping triggers `loadData()`

Check for any remaining `Capsule()` filter chips that aren't badge decorations.

### For Each Page — Add statusCounts if Missing

If the page doesn't have a `statusCounts` dictionary, add one:

```swift
@State private var statusCounts: [String: Int] = [:]
```

And populate it in `loadData()`:

```swift
// After loading items:
var counts: [String: Int] = [:]
for item in allItems {
    counts[item.status, default: 0] += 1
}
statusCounts = counts
```

## Success Criteria

- [ ] All 3 pages use SmartFilterCard for status/type filtering (not Capsule chips)
- [ ] Each SmartFilterCard shows a count of matching items from real data
- [ ] "All" card is the first option on each page showing total count
- [ ] Selected state has accent color highlight with border
- [ ] Touch targets are at least 44px tall (SmartFilterCard handles this)
- [ ] No `Capsule()` used in filter picker contexts (badge decorations are OK)
- [ ] Counts are computed from actual loaded data, not hardcoded
- [ ] Project builds with zero errors
