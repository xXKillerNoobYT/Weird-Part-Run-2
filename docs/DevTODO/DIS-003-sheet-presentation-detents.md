---
source: dev-improvement-scanner (2026-04-04)
severity: Medium
category: Apple HIG — Sheet Presentation
status: DONE — .presentationDetents([.large]) + .presentationDragIndicator(.visible) added to all 7 sheets in commit 3ddbc61 (IOSMainView 4 sheets, PartsCatalogPage, IOSContactDetailPage, IOSHatsPage).
github_issue: PENDING (gh not available, file manually)
---

# DIS-003: Most Sheets Missing .presentationDetents

## Problem
Per Apple HIG, sheets should declare their intended size via `.presentationDetents`. Without this, iOS applies inconsistent default drag behavior that can vary between iOS versions and feel unpredictable.

## Sheets Missing Detents (prioritized)

| File | Sheet var | Recommended detent |
|------|-----------|-------------------|
| `Features/People/IOSContactDetailPage.swift:42` | Edit form sheet | `.large` |
| `Features/Parts/PartsCatalogPage.swift:1511` | Edit form sheet | `.large` |
| `Features/People/IOSHatsPage.swift:326` | Add employee sheet | `.large` |
| `Features/Settings/IOSMainView.swift:524` | User menu | `.medium` or `.fraction(0.4)` |
| `Features/Settings/IOSMainView.swift:464` | Tab editor | `.large` |
| `Features/Settings/IOSMainView.swift:80` | Conflict review | `.large` |
| `Features/Settings/IOSMainView.swift:146` | AI assistant | `.large` |

## Fix (paste into Xcode AI)

For each `.sheet(isPresented:) { ... }` or `.sheet(item:) { ... }` in the files above, add `.presentationDetents([.large])` (or `.medium` where appropriate) inside the sheet's content view.

Example:
```swift
.sheet(item: $activeSheet) { _ in
    SomeFormView()
        .presentationDetents([.large])  // ADD THIS
        .presentationDragIndicator(.visible)
}
```

Use `.large` for all full-screen forms. Use `.medium` or `.fraction(0.4)` for compact info sheets like the user menu.

## Verification
1. Open each sheet
2. Confirm it opens at the intended size
3. Confirm drag behavior matches the declared detent
