# Fix Prompt PE-009b: Tap Target Sizes — Minimum 44×44pt

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

12 interactive elements have frames smaller than Apple's 44×44pt minimum tap target. Some are as small as 14×14pt (disclosure indicator) and 24×24pt (action buttons). On a phone, users regularly mis-tap these or can't tap them at all.

**GitHub Issue:** #12
**PE Tracker:** PE-009b

---

## Files To Fix

For each location below, expand the tappable area to at least 44×44pt without changing the visual size of the icon/element.

### The Fix Pattern

```swift
// Option A: Invisible hit area (preferred for icon buttons)
Button(action: { /* ... */ }) {
    Image(systemName: "chevron.right")
        .frame(width: 28, height: 28)
}
.frame(minWidth: 44, minHeight: 44)
.contentShape(Rectangle())

// Option B: Padding approach (when you control the full button)
Button(action: { /* ... */ }) {
    Image(systemName: "trash")
        .frame(width: 20, height: 20)
        .padding(12) // adds 24pt on each side = 44pt total
}
```

Use **Option A** (explicit `.frame(minWidth: 44, minHeight: 44)` + `.contentShape(Rectangle())`) unless the design clearly benefits from padding.

---

## Locations to Fix

| File | Line | Current Size | Fix |
|------|------|-------------|-----|
| ReportBuilderView.swift | ~183 | 28×28 | Add `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` to button |
| IOSWarehouseLeaderboardPage.swift | ~198 | 28×28 | Same |
| IOSWarehouseLeaderboardPage.swift | ~514 | 24×24 | Same |
| IOSMovementWizard.swift | ~109 | 28×28 | Same |
| CategoriesTreeView.swift | ~688 | 36×36 | Same (close but still under minimum) |
| CategoriesTreeView.swift | ~522 | 14×14 | Same — this is very small, ensure visual stays 14×14 but hit area is 44×44 |
| WarehouseMovementsPage.swift | ~223 | 36×36 | Same |
| IOSOrganizationAuditPage.swift | ~209 | 36×36 | Same |
| IOSAuditPage.swift | ~628 | 36×36 | Same |
| IOSJobDetailTabView.swift | ~1142 | 36×36 | Same |
| IOSClockPage.swift | ~1563 | 36×36 | Same |
| IOSClockPage.swift | ~1585 | 36×36 | Same |
| WarehouseOnboardingWizard.swift | ~429 | 28×28 | Same |

---

## Important Notes

- **Do not change visual appearance** — only the tappable area should grow, not the displayed icon/element
- `CategoriesTreeView.swift:522` is the most critical — 14×14 is extremely small
- `.contentShape(Rectangle())` is essential when the visual frame is smaller than the tap frame; without it, SwiftUI clips hit testing to the visual bounds
- If the element is already inside a `List` row, the full row may already be 44pt tall — confirm before patching

---

## Verification

After all fixes:
1. Build the project — 0 errors
2. Search for any remaining small fixed frames on interactive elements (look for `.frame(width: N, height: N)` on `Button` elements where N < 44)
3. Visually verify on a 375pt-wide iPhone simulator that elements look correct and don't have visible padding bleed

---

## Done Criteria

- All 12+ identified interactive elements have a minimum 44×44pt tap area
- Visual appearance unchanged
- Project builds without errors
