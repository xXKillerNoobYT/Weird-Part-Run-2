# Add Accessibility Labels to Interactive Elements
**GitHub Issue:** #14
**Priority:** High
**Estimated effort:** Large (ongoing — do a few pages at a time)

## What's Wrong
Only 8 `.accessibilityLabel()` exist across 180+ view files. VoiceOver users can't navigate the app because icon-only buttons have no spoken labels.

## Priority Order
Start with the most-used pages:

### Batch 1 — Core Navigation (do these first)
- `Features/Dashboard/` — all toolbar buttons, status cards
- `Features/Jobs/JobsListPage.swift` — filter buttons, action buttons
- `Features/Jobs/IOSClockPage.swift` — clock in/out buttons, timer display

### Batch 2 — Daily Use Pages
- `Features/Orders/IOSJPOsPage.swift` — create/filter buttons
- `Features/Warehouse/WarehouseDashboardPage.swift` — action buttons, stats
- `Features/Parts/PartsCatalogPage.swift` — search, filter, action buttons

### Batch 3 — Everything Else
- All remaining Feature pages with toolbar buttons

## AI Prompt (use per file)
```
In this file, add .accessibilityLabel() to every interactive element that uses an icon without text:

1. All Button { Image(systemName: "...") } — add .accessibilityLabel("Description of action")
2. All toolbar items with just an icon — add .accessibilityLabel()
3. All status indicators (colored circles/badges) — add .accessibilityLabel("Status: ...")
4. All Image(systemName:) used as decorative icons next to text — mark as .accessibilityHidden(true)

Use descriptive labels that explain the ACTION, not the icon:
- "plus" icon → .accessibilityLabel("Add new item")
- "trash" icon → .accessibilityLabel("Delete")
- "line.3.horizontal.decrease" icon → .accessibilityLabel("Filter")
- "magnifyingglass" icon → .accessibilityLabel("Search")
- Green circle → .accessibilityLabel("Online") or .accessibilityLabel("Status: active")
```

## How to Verify
1. Build and run on simulator
2. Enable VoiceOver (Settings → Accessibility → VoiceOver)
3. Swipe through each page — every button should announce its purpose
4. No element should say just "Button" or "Image"
