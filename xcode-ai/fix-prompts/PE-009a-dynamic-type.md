# Fix Prompt PE-009a: Dynamic Type — Replace Hardcoded Font Sizes

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

55+ instances of `.font(.system(size: N))` across 24+ files bypass iOS Dynamic Type entirely. Users who set larger text sizes in iOS Settings → Accessibility → Larger Text get no benefit — text stays the same size. Some sizes are as small as 7–9pt, which are illegible for many users even at default settings.

**GitHub Issue:** #11
**PE Tracker:** PE-009a

---

## Files To Fix

Work through these files. For each instance of `.font(.system(size: N))`, replace with the closest semantic equivalent from the table below.

### Size → Semantic Mapping

| Hardcoded Size | Use Instead |
|---|---|
| ≤9pt (e.g. 7, 8, 9) | `.font(.caption2)` |
| 10–11pt | `.font(.caption)` |
| 12pt | `.font(.footnote)` |
| 13pt | `.font(.subheadline)` |
| 14–15pt | `.font(.callout)` |
| 16–17pt | `.font(.body)` |
| 18–19pt | `.font(.title3)` |
| 20–21pt | `.font(.title2)` |
| 22–25pt | `.font(.title)` |
| 26pt+ | `.font(.largeTitle)` |

If the font is bold or a specific weight, add `.fontWeight(.semibold)` / `.fontWeight(.bold)` after the font modifier. For example:
```swift
// Before
.font(.system(size: 11, weight: .semibold))

// After
.font(.caption).fontWeight(.semibold)
// Or more concisely:
.font(.caption2.weight(.semibold))
```

### Priority Files (worst offenders — fix these first)

1. **IOSChannelsPage.swift** — 7pt, 9pt instances
2. **IOSJobDetailTabView.swift** — 8pt instances
3. **IOSPODetailPage.swift** — 9pt ×4 instances
4. **PartsCatalogPage.swift** — 8pt instances
5. **WarehouseLocationsPage.swift** — 7pt, 8pt, 9pt instances

### All Affected Files

Search for `.font(.system(size:` across the entire `Weird Parts IOS/` directory and fix every match. Files confirmed to have instances include:
- IOSChannelsPage.swift
- IOSJobDetailTabView.swift
- IOSPODetailPage.swift
- PartsCatalogPage.swift
- WarehouseLocationsPage.swift
- IOSWarehouseLeaderboardPage.swift
- IOSMovementWizard.swift
- CategoriesTreeView.swift
- WarehouseMovementsPage.swift
- IOSOrganizationAuditPage.swift
- IOSAuditPage.swift
- IOSClockPage.swift
- WarehouseOnboardingWizard.swift
- ReportBuilderView.swift
- And any others found in the search

---

## What NOT To Change

- `.font(.system(.body))` — already uses semantic style, leave it
- `.font(.system(size:))` used for non-text elements (icon sizes, chart sizes) — only fix text rendering
- Custom `UIFont` in `UIViewRepresentable` wrappers — leave those alone

---

## Verification

After making all changes:
1. Search for remaining `.font(.system(size:` — should be zero or near-zero in the Features/ folder
2. Build the project — should compile with 0 errors
3. Run on simulator with Accessibility > Larger Text enabled — text should scale up

---

## Done Criteria

- All hardcoded font sizes in SwiftUI views replaced with semantic text styles
- Project builds without errors
- No new warnings introduced
