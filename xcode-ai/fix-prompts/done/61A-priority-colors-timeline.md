# 61A — Replace Label-Based Priority Colors with Time-Based Timeline Colors

> **Chain position:** **61A** (standalone)
> **Issue:** T2-03
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT change any priority label strings ("urgent", "high", "medium", "low") — only change what COLOR they map to
2. DO NOT remove any existing priority fields or enums
3. The NEW color logic is based on TIME REMAINING, not the label text
4. Create a SHARED helper so every file uses the same logic
5. Project must build with zero errors when done

## Context

The app currently uses label-based priority colors: "urgent" = red, "high" = orange, "medium" = yellow, "low" = green. This is wrong. Priority colors should reflect TIME REMAINING until due date, not the label. A "low" priority job due tomorrow should be orange. A "high" priority job due in 2 weeks should be green.

Files that currently have `priorityColor()` or priority-to-color mapping:
- `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSManageJobsPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPODetailPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSRFIListPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSEscalationTimeline.swift`

## Task

### 1. Create TimelinePriorityColor Helper

Create a new file: `Weird Parts IOS/Weird Parts IOS/Shared/TimelinePriorityColor.swift`

```swift
import SwiftUI

/// Timeline-based priority coloring.
/// Colors reflect urgency based on TIME REMAINING, not label text.
///
/// Rules:
/// - Completed items → .gray
/// - Overdue (past due date) → .red
/// - Due within 24 hours → .orange
/// - Due within 4 days → .yellow
/// - Due in 4+ days → .green
/// - No due date → .secondary (neutral)
struct TimelinePriorityColor {

    static func color(for dueDate: Date?, isCompleted: Bool = false) -> Color {
        if isCompleted { return .gray }
        guard let dueDate = dueDate else { return .secondary }

        let now = Date()
        let hoursRemaining = dueDate.timeIntervalSince(now) / 3600

        if hoursRemaining < 0 {
            return .red        // Overdue
        } else if hoursRemaining < 24 {
            return .orange     // Due within 24 hours
        } else if hoursRemaining < 96 { // 4 days
            return .yellow     // Due within 4 days
        } else {
            return .green      // Comfortable timeline
        }
    }

    /// For items that have a priority label AND a due date,
    /// the due date ALWAYS wins for color. The label is display-only.
    static func color(priority: String?, dueDate: Date?, isCompleted: Bool = false) -> Color {
        return color(for: dueDate, isCompleted: isCompleted)
    }

    /// Returns a human-readable urgency label based on time remaining
    static func urgencyLabel(for dueDate: Date?, isCompleted: Bool = false) -> String {
        if isCompleted { return "Completed" }
        guard let dueDate = dueDate else { return "No deadline" }

        let now = Date()
        let hoursRemaining = dueDate.timeIntervalSince(now) / 3600

        if hoursRemaining < 0 {
            return "Overdue"
        } else if hoursRemaining < 24 {
            return "Due today"
        } else if hoursRemaining < 96 {
            let days = Int(hoursRemaining / 24)
            return "Due in \(days)d"
        } else {
            let days = Int(hoursRemaining / 24)
            return "Due in \(days)d"
        }
    }
}
```

### 2. Replace priorityColor() in ALL 5 Files

In each file, find the `priorityColor()` function or inline color mapping. Replace the body with a call to `TimelinePriorityColor.color(for:isCompleted:)`.

**Pattern to find:**
```swift
func priorityColor() -> Color {
    switch priority?.lowercased() {
    case "urgent": return .red
    case "high": return .orange
    case "medium": return .yellow
    case "low": return .green
    default: return .gray
    }
}
```

**Replace with:**
```swift
func priorityColor() -> Color {
    // Timeline-based: color reflects time remaining, not label
    return TimelinePriorityColor.color(for: dueDate, isCompleted: status == "completed")
}
```

If the function doesn't have access to `dueDate`, find where it's called and pass `dueDate` from the data model. Every job, JPO, RFI, and escalation has a due date field — use it.

### 3. Update Color Legend (if any)

If any page shows a legend explaining priority colors (e.g., "Red = Urgent"), update it to:
- Red = Overdue
- Orange = Due within 24 hours
- Yellow = Due within 4 days
- Green = On track
- Gray = Completed

### 4. Search for Any Other Priority Color Mappings

Search the entire project for:
- `case "urgent"` with color
- `case "high"` with color
- `priority` and `.red` / `.orange` on the same line
- Any switch on priority that returns a Color

Replace ALL of them with `TimelinePriorityColor`.

## Success Criteria

- [ ] New `TimelinePriorityColor.swift` helper file created in Shared/
- [ ] ALL 5 files updated to use the new helper
- [ ] No remaining label-based priority color logic anywhere in the project
- [ ] Colors now reflect time remaining: overdue=red, 24h=orange, 4d=yellow, 4d+=green, done=gray
- [ ] Project builds with zero errors
