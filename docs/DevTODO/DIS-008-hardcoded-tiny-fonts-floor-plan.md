---
source: dev-improvement-scanner (2026-04-05)
severity: Medium
category: Apple HIG — Typography / Dynamic Type
status: open
github_issue: PENDING (gh not available, file manually)
---

# DIS-008: Hardcoded Sub-Minimum Font Sizes in Floor Plan Views

## Problem
Two files use hardcoded font sizes far below Apple's minimum readable size (11pt) and bypass
the Dynamic Type system that was globally fixed in PE-009a.

| File | Line | Value | Issue |
|------|------|-------|-------|
| `Features/Warehouse/WizardStepPlacement.swift` | 133 | `.font(.system(size: 7))` | 7pt — unreadable at normal viewing distance |
| `Features/Jobs/JobStageProgressBar.swift` | 45 | `.font(.system(size: compact ? 6 : 10, weight: .bold))` | 6pt in compact mode is invisible to most users |

Apple HIG states interactive and informational text should be at least 11pt. VoiceOver
users relying on large text will see no scaling since these bypass Dynamic Type.

## Fix (paste into Xcode AI)

In `WizardStepPlacement.swift` (grid cell label, line ~132-134):

```swift
// BEFORE
Text(unit.name)
    .font(.system(size: 7))
    .lineLimit(1)

// AFTER — use caption2 with aggressive scale factor for the constrained 44pt cell
Text(unit.name)
    .font(.caption2)
    .minimumScaleFactor(0.4)
    .lineLimit(1)
```

In `JobStageProgressBar.swift` (stage label, line ~44-45):

```swift
// BEFORE
.font(.system(size: compact ? 6 : 10, weight: .bold))

// AFTER
.font(compact ? .system(.caption2, weight: .bold) : .system(.caption, weight: .bold))
.minimumScaleFactor(0.5)
```

Using `.caption2` with `.minimumScaleFactor` lets the text scale down only when necessary
while still respecting the user's Dynamic Type preference in larger size categories.

## Verification
1. Run on simulator with Accessibility → Larger Text set to maximum
2. Text in both views should scale up (not stay at 7pt)
3. Grid cells should still display without overflow (minimumScaleFactor handles this)
