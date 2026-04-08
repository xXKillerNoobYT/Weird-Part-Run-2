# PE-038: Fix Hardcoded Tiny Font in JobStageProgressBar (DIS-008)

**Priority:** Medium
**Source:** dev-improvement-scanner run 9 (2026-04-05)
**DevTODO:** `docs/DevTODO/DIS-008-hardcoded-tiny-fonts-floor-plan.md`
**Note:** `WizardStepPlacement.swift` was already fixed (uses `.caption2` semantic style). Only `JobStageProgressBar.swift` remains.

---

## Overview

`JobStageProgressBar.swift` uses `.font(.system(size: compact ? 6 : 10, weight: .bold))` on a checkmark SF Symbol inside progress stage circles. `size: 6` bypasses Dynamic Type — users with larger accessibility text sizes get no scaling. Fix: use semantic style with `minimumScaleFactor` so Dynamic Type is respected while still fitting inside the constrained circle.

---

## Fix

**File:** `Weird Parts IOS/Shared/JobStageProgressBar.swift`

**Line ~45:**

```swift
// BEFORE
.font(.system(size: compact ? 6 : 10, weight: .bold))

// AFTER
.font(compact ? .system(.caption2, weight: .bold) : .system(.caption, weight: .bold))
.minimumScaleFactor(0.5)
```

**That's the only change.** One line replaced, one line added.

---

## Context

The checkmark appears inside a `Circle` of `frame(width: compact ? 12 : 20, ...)`. The `minimumScaleFactor(0.5)` ensures the icon still fits in the smallest circles while Dynamic Type users with large text see proper proportional scaling.

---

## Verification

1. Build and run — stage bars should look identical at default text size
2. Go to Simulator → Settings → Accessibility → Display & Text Size → Larger Text → drag to maximum
3. The checkmark in progress bars should now scale up (previously stuck at 6pt regardless)
4. Compact mode (e.g. job list cards) should still display cleanly with no overflow
