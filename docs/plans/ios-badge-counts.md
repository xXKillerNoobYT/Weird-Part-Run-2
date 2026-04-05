# iOS Badge Counts & Action Visibility Plan

## What This Does (Plain English)
Nav tabs show badge counts (numbers) for pending items. List rows with pending actions get a red border ring around their action buttons. Badge counts update in real-time. A consistent "action required" visual language is established across the app.

## Why We Need This
Users have no visual cue that something needs their attention. There's no thread from nav → list → action. Workers miss approvals, managers miss clock-out reminders, office staff miss POs awaiting approval.

## Current State
- No badge counts on any nav tabs
- No pending-action indicators on list rows
- Action buttons (approve/reject/accept) styled uniformly with no emphasis
- No consistent visual language for "action required"

## Owner Decisions Applied
- **All tabs** get badge counts for pending items
- **Color scheme:** Newer items = green badge, oldest items = red badge (age-based color)
- **Real-time** — live DB query on each tab view (always up-to-date)
- **Native `.badge()` modifier** — SwiftUI native badge with color control (iOS 17+ allows color)
- **Action button prominence:** Bold red/green border ring around action buttons (option A)
- **Notebook updates:** Pages in a notebook that I'm part of with updates show badge

## Badge Counts Per Tab

| Tab | Badge Source | Query |
|-----|-------------|-------|
| Dashboard | Pending approvals + unread alerts | `approvals WHERE status = 'pending'` + alerts |
| Clock | Active clock entries needing attention (e.g., >12h without clock-out) | |
| Jobs | Jobs with pending actions (unread notes, pending questionnaires) | |
| Scheduling | Unassigned dispatch slots + pending time-off requests | |
| Orders | POs awaiting approval + pending JPOs | |
| Warehouse | Receiving sessions in progress + audit discrepancies | |
| Parts | Low-stock alerts (parts below min level) | |
| People | Pending time-off requests + expiring certifications | |
| Reports | Reports pending review/lock | |
| Tools | Overdue tool returns | |
| Fleet | Upcoming/overdue inspections + maintenance | |
| Chat | Unread messages | |
| Notebooks | Unread notebook updates on notebooks I'm part of | |
| Approvals | All pending approvals (if separate tab) | |

## Badge Color Logic
```
Age < 1 day  → green badge (new)
Age 1-3 days → orange badge (getting old)
Age > 3 days → red badge (old, needs attention)
```

If multiple items: badge number shown, color = oldest item's color.

## Files to Modify

### Core — BadgeService (New)
**File:** `core/Sources/WiredPartCore/Services/BadgeService.swift` (new)

```swift
public struct BadgeCounts {
    public let jobs: Int
    public let scheduling: Int
    public let orders: Int
    public let warehouse: Int
    public let parts: Int
    public let people: Int
    public let reports: Int
    public let tools: Int
    public let fleet: Int
    public let chat: Int
    public let approvals: Int
    public let notifications: Int
}

public struct BadgeInfo {
    public let count: Int
    public let oldestAgeHours: Double  // Used for color calculation
    public var color: BadgeColor { ... }  // .green / .orange / .red
}

public class BadgeService {
    public func getAllBadgeCounts(userId: Int64) throws -> BadgeCounts
    // Individual methods for each area
    public func getOrdersBadge(userId: Int64) throws -> BadgeInfo
    public func getSchedulingBadge(userId: Int64) throws -> BadgeInfo
    // etc.
}
```

### iOS UI — Tab Bar / Main Navigation
**File:** `Weird Parts IOS/Weird Parts IOS/App/IOSMainView.swift` (or nav file)

- Load badge counts on tab view appear using `BadgeService`
- Apply `.badge(count)` to each TabItem
- Refresh on `scenePhase` change to `.active`
- Use `onChange(of: scenePhase)` to refresh when app comes to foreground

### iOS UI — Action Buttons
**All pages with approve/reject/accept/clock-out actions:**

Add `ActionRingModifier`:
```swift
struct ActionRingModifier: ViewModifier {
    let color: Color  // .red for urgent, .green for confirm
    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 2))
    }
}
```

Apply to: approval buttons, clock-out reminder button, PO approve button, dispatch accept button.

Xcode prompt: `PE-032-badge-counts.md`

## Data Flow
App opens → TabView appears → `BadgeService.getAllBadgeCounts(userId:)` called → badge counts applied to tabs
User approves a PO → PO removed from pending → `BadgeService` queried again → orders badge updates

Background refresh: `BackgroundTaskService` can update badge counts every 15 minutes.

## How It Links to Other Features
- Uses `BackgroundTaskService` for periodic refresh
- Connects to Notifications (future Phase 10) — badge counts feed push notifications
- ChatService already has unread count logic — badge just surfaces it

## Test Plan
1. Create pending PO → verify Orders tab shows badge "1"
2. Add 3 pending POs (one 4 days old) → verify badge shows "3" in red
3. Approve all POs → verify badge disappears
4. Create unread chat message → verify Chat tab shows badge

## Apple HIG Notes
- `.badge()` is native iOS behavior — use it
- Red badges for action-required items is established iOS convention
- Don't badge informational tabs (Settings, Profile) — only action-required tabs
- Age-based color adds useful context without requiring extra UI elements
