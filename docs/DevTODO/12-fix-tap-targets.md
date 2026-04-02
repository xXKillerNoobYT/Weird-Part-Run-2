# Fix Undersized Tap Targets to 44x44pt Minimum
**GitHub Issue:** #12
**Priority:** High
**Estimated effort:** Quick (10 min)

## What's Wrong
12 interactive elements have frames smaller than Apple's 44x44pt minimum. Small buttons are hard to tap, especially for users with motor impairments.

## Files to Change
Each line below — change the `.frame(width: N, height: N)` to at least 44x44:

1. `Features/Reports/ReportBuilderView.swift:183` — 28x28 → add `.frame(minWidth: 44, minHeight: 44)`
2. `Features/Warehouse/IOSWarehouseLeaderboardPage.swift:198` — 28x28 → 44x44
3. `Features/Warehouse/IOSWarehouseLeaderboardPage.swift:514` — 24x24 → 44x44
4. `Features/Warehouse/IOSMovementWizard.swift:109` — 28x28 → 44x44
5. `Features/Parts/CategoriesTreeView.swift:688` — 36x36 → 44x44
6. `Features/Warehouse/WarehouseMovementsPage.swift:223` — 36x36 → 44x44
7. `Features/Warehouse/IOSOrganizationAuditPage.swift:209` — 36x36 → 44x44
8. `Features/Warehouse/IOSAuditPage.swift:628` — 36x36 → 44x44
9. `Features/Jobs/IOSJobDetailTabView.swift:1142` — 36x36 → 44x44
10. `Features/Jobs/IOSClockPage.swift:1563,1585` — 36x36 → 44x44
11. `Features/Warehouse/WarehouseOnboardingWizard.swift:429` — 28x28 → 44x44
12. `Features/Parts/CategoriesTreeView.swift:522` — 14x14 → add `.contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44)`

## AI Prompt
```
In this file, find all Button or Image elements with .frame(width: N, height: N) where N is less than 44. Change the frame to .frame(minWidth: 44, minHeight: 44). Keep the icon size the same but make the tappable area larger.

For very small elements (under 20pt), keep the visual size but add .contentShape(Rectangle()) and .frame(minWidth: 44, minHeight: 44) to expand the tap target without changing appearance.
```

## How to Verify
1. Build and run
2. Navigate to each page listed above
3. Try tapping the small buttons — they should be easy to hit
4. Visual appearance should be similar (icon size unchanged, just tap area bigger)



## AI RESOLTS
Xcode AI couldn't handle the broad search — too many .frame() matches. Use per-file prompts below.

## Per-File AI Prompts (open each file in Xcode, then use this prompt)

### File 1: ReportBuilderView.swift
```
At line ~183, there's a 28x28 button. Add .contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44) to make the tap target 44x44 while keeping the icon at 28pt.
```

### File 2: IOSWarehouseLeaderboardPage.swift
```
At line ~198 there's a 28x28 button, and at line ~514 there's a 24x24 button. For both: add .contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44) to expand tap targets.
```

### File 3: IOSMovementWizard.swift
```
At line ~109 there's a 28x28 button. Add .contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44).
```

### File 4: CategoriesTreeView.swift
```
At line ~688 there's a 36x36 button — change to 44x44. At line ~522 there's a 14x14 element — add .contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44).
```

### File 5: WarehouseMovementsPage.swift
```
At line ~223 there's a 36x36 button — change frame to 44x44.
```

### File 6: IOSOrganizationAuditPage.swift
```
At line ~209 there's a 36x36 button — change frame to 44x44.
```

### File 7: IOSAuditPage.swift
```
At line ~628 there's a 36x36 button — change frame to 44x44.
```

### File 8: IOSJobDetailTabView.swift
```
At line ~1142 there's a 36x36 button — change frame to 44x44.
```

### File 9: IOSClockPage.swift
```
At lines ~1563 and ~1585 there are 36x36 buttons — change both frames to 44x44.
```

### File 10: WarehouseOnboardingWizard.swift
```
At line ~429 there's a 28x28 button. Add .contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44).
```