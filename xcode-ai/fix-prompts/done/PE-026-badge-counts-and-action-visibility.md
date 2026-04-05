# Fix Prompt PE-026: Badge Counts + Action-Required Visual Language

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## What This Fixes

GitHub #50 + #51 — No badge counts on nav tabs, and action buttons (approve/reject/clock out) have no visual prominence. Users have no "thread" from navigation → list → action item.

**Owner decisions (Q&A answered 2026-04-04):**
- Badge counts on ALL tabs/sections — all pending items across the entire app
- Real-time (live DB query on each tab view) — always up-to-date
- Newer items = green badge tint; oldest pending items = red tint
- Action buttons: **bold red/green border ring around the button** (option A)
- Use native SwiftUI `.badge(count)` with color control

---

## Fix 1: Tab Bar Badge Counts

**Files:**
- `Navigation/IOSMainView.swift` (where `TabView` tabs are defined)
- Any file that owns the `TabView` item list

### Badge Data Needed Per Tab

Add a `@StateObject` or `@EnvironmentObject` providing live badge counts:

```swift
// In AppCore or a new BadgeCountService:
struct BadgeCounts {
    var pendingApprovals: Int      // Orders awaiting approval
    var pendingClockOuts: Int      // Workers clocked in > shift end
    var unreadMessages: Int        // Chat unread count
    var openDispatches: Int        // Scheduling: unassigned jobs today
    var pendingReceipts: Int       // Warehouse: items awaiting receiving
    var overdueOrders: Int         // Orders: overdue POs
    var expiringCerts: Int         // People: certs expiring in 7 days
    var flexPoolAvailable: Int     // Scheduling: unclaimed flex pool jobs
}
```

Query these counts once on tab appearance and on `onForeground` (use `scenePhase`). Each count maps to exactly one tab.

### Tab Badge Wiring

```swift
// In TabView { ... }
Tab("Scheduling", systemImage: "calendar") {
    IOSSchedulingPage()
}
.badge(badgeCounts.openDispatches + badgeCounts.flexPoolAvailable)

Tab("Orders", systemImage: "shippingbox") {
    IOSOrdersPage()
}
.badge(badgeCounts.pendingApprovals + badgeCounts.overdueOrders)

// etc. — 0 hides badge automatically
```

**Color rule:** Use `.tint(.red)` on tabs with count > 7 days old (items pending a long time). Use default `.tint(.green)` for recent items. If a tab has both old and new items, red wins.

---

## Fix 2: List Row Action Indicators

In list views where rows require action (approval queue, dispatch assignment, receiving queue), add a visual indicator on the row:

```swift
// For any "pending action" row:
HStack {
    // ... existing row content ...
    Spacer()
    Circle()
        .fill(isOverdue ? Color.red : Color.green)
        .frame(width: 10, height: 10)
        .accessibilityLabel(isOverdue ? "Overdue action required" : "Action required")
}
```

Apply this to:
- `IOSApprovalsPage` rows (pending approval items)
- `IOSDispatchPage` rows (unassigned job slots)
- Warehouse receiving list rows (awaiting receipt)
- `IOSClockPage` worker cards when clocked in past shift end

---

## Fix 3: Action Button Visual Prominence

For primary action buttons (Approve/Reject, Clock Out, Claim Job, Mark Received) — add a border ring:

```swift
// "Approve" button example:
Button("Approve") { approveAction() }
    .buttonStyle(.bordered)
    .tint(.green)
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.green.opacity(0.6), lineWidth: 2)
    )
    .accessibilityLabel("Approve — action required")

// "Reject" / destructive button:
Button("Reject") { rejectAction() }
    .buttonStyle(.bordered)
    .tint(.red)
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.red.opacity(0.6), lineWidth: 2)
    )
```

Apply to all pages with pending-action flows. Neutral actions (Edit, View) keep `.buttonStyle(.borderless)` with no extra ring.

---

## Fix 4: Notebook Update Badges

Notebook pages on jobs the current user is participating in should show a badge if there are unread entries since last view. This is the "updated pages in notebooks on projects I'm part of" case from Q&A.

```swift
// On the Jobs List page, per row:
.badge(job.unreadNotebookCount)

// IOSNotebooksPage tab:
.badge(totalUnreadNotebookEntries)
```

Use existing `NotebooksService` and a `last_viewed_at` column (or UserDefaults per notebook ID) to determine unread count.

---

## Success Criteria

1. All tab bar tabs show live badge counts — 0 hides the badge automatically
2. Badge tint is green for recent items, red for items pending > 7 days
3. List rows with pending actions have a colored dot indicator
4. Primary action buttons (Approve/Reject/Claim/Clock Out) have a colored border ring
5. Notebook update badges show on job rows and notebook tab
6. All changes compile with 0 errors
7. No badge count crashes on empty DB (all queries return 0, not nil, on empty tables)

---

## After Completing

Log results in `xcode-ai/prompt-results-log.md` with the standard format.
Mark PE-026 DONE in `xcode-ai/fix-prompts/00-fix-order.md`.
Comment on GitHub issues #50 and #51 noting the fix.
