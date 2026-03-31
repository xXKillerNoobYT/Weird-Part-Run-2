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

## AI REPORT
Build succeeded. Here's a summary of what was done for GitHub Issue #15:

Changes Made (5 files edited)

Already had proper accessibility (no changes needed):
• IOSWarehouseNetworkPage.swift􀰓 — already had Text("​Online") + .accessibility​Label("​Status: ​Online")
• IOSOfficeDashboardPage.swift􀰓 — blue dots are bullet points with .accessibility​Hidden(true), text right next to them
• IOSClockPage.swift􀰓 — status​Dot() already had .accessibility​Label()

Files fixed:

1. IOSJPOCreationPage.swift􀰓 — Added .accessibility​Hidden(true) to the stock indicator Circle (the Text(label) next to it already conveys the status)

2. IOSSpendingDashboardPage.swift􀰓 — Added .accessibility​Element(children: .combine) and .accessibility​Label("\(label): \(value)") to Spending​Row so VoiceOver reads the full context as one element

3. IOSPODetailPage.swift􀰓 — Fixed 3 timeline dots:
   • Line 702: timeline dot in Receiving Timeline → .accessibility​Hidden(true) (decorative)
   • Line 1561: receipt entry dot → .accessibility​Label() describing discrepancy status (color-meaningful)
   • Line 1727: legacy batch row dot → .accessibility​Hidden(true) (decorative)

4. IOSAuditPage.swift􀰓 — Added .accessibility​Element(children: .ignore) + .accessibility​Label("​Confidence: ​X%") to the confidence gauge ZStack

5. PartsForecastingPage.swift􀰓 — Added a visible Text(urgency​Text) label (.font(.system(size: 8))) below the urgency dot, plus wrapped both in a VStack with .accessibility​Label(). Now "Critical"/"Warning"/"Healthy" is visible even without color.