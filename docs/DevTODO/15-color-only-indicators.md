# Add Text/Icon Alternatives to Color-Only Status Indicators
**GitHub Issue:** #15
**Priority:** Medium
**Estimated effort:** Quick (15 min)

## What's Wrong
9+ places use small colored dots to show status with no text or icon alternative. Color-blind users can't tell the states apart.

## Files to Change

### For each colored dot, add BOTH a text label AND an accessibilityLabel:

1. `Features/Warehouse/IOSWarehouseNetworkPage.swift:33-35` — green circle = "Online"
   - Add `Text("Online").font(.caption2)` next to the dot
   - Add `.accessibilityLabel("Online")`

2. `Features/Orders/IOSJPOCreationPage.swift:448` — 6x6 status dot
   - Add `.accessibilityLabel("Status: \(statusText)")`

3. `Features/Office/IOSOfficeDashboardPage.swift:157` — 6x6 colored dots
   - Add text label next to each dot

4. `Features/Office/IOSSpendingDashboardPage.swift:182` — 8x8 chart legend dots
   - These likely already have legend text — add `.accessibilityLabel()`

5. `Features/Orders/IOSPODetailPage.swift:696,1545,1708` — status dots
   - Add `.accessibilityLabel("Status: \(status)")`

6. `Features/Warehouse/IOSAuditSummaryView.swift:251` — 8x8 dots
   - Add text labels

7. `Features/Parts/PartsForecastingPage.swift:343` — 12x12 indicator
   - Add text label

8. `Features/Jobs/IOSClockPage.swift:830` — 8x8 status dot
   - Add `.accessibilityLabel("Status: \(isActive ? "clocked in" : "clocked out")")`

## AI Prompt (use per file)
```
In this file, find all Circle() or small colored dot indicators that show status. For each one:

1. Add an .accessibilityLabel() that describes the status in words
2. If the dot is the ONLY indicator of status (no nearby text), add a small Text label next to it using .font(.caption2)
3. Use the existing status variable to derive the label text

The goal: a user who can't see colors should still understand the status.
```

## How to Verify
1. Build and run
2. On each page, check that status dots have text nearby or are described by VoiceOver
3. Turn on color filters (Settings → Accessibility → Display → Color Filters → Grayscale) — all statuses should still be distinguishable
