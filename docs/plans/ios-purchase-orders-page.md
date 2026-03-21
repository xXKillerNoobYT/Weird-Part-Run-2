# iOS Purchase Orders Page Design

> **Page:** `IOSPurchaseOrdersPage.swift` (~180 lines)
> **Nav:** Orders → Purchase Orders
> **Status:** Design CONFIRMED (2026-03-21)

## Current State

Clean page using service layer (no raw SQL). Has ActiveSheet pattern, QR scanner, status filter chips, search, pull-to-refresh, NavigationLink to detail page. 7 status types: draft, submitted, ordered, partial, received, cancelled.

### Remaining Issues
- `#if os(iOS)` platform guard (line 134)
- No count badges on status filters
- Guard on `ordersService` doesn't set loadError
- Raw date string display (not formatted)

## Design Decisions (Confirmed)

### 1. Status Filters — Keep chips, add count badges
Keep the horizontal capsule chip pattern (7 statuses = too many for stat cards). Add count badges to each chip showing how many POs are in that status.

```
[All (23)] [Draft (3)] [Submitted (2)] [Ordered (5)] [Partial (1)] [Received (12)] [Cancelled (0)]
```

With "All" being selectable to show everything.

### 2. Summary Stats — Awaiting Delivery Count
Show a compact KPI at the top: "3 awaiting delivery" — counts POs in `ordered` + `partial` status.

### 3. Swipe Actions — Delete/Cancel with AI Summary Confirmation
- Swipe-to-cancel (or swipe-to-delete for drafts) on PO rows
- Confirmation alert includes an **AI-generated summary** of what the PO is for:
  - "PO-2024-042: 15 items from Acme Supply for Smith Residence (Job #J-042). Total: $1,247.50. Status: Ordered 3 days ago."
- The summary helps prevent accidental deletion of important POs

### 4. Sort Options
Add sort picker in toolbar or as a menu:
- Newest first (default)
- Oldest first
- By total (highest)
- By total (lowest)
- By supplier name (A-Z)
- By status

## Prompt Chain

| Prompt | What |
|--------|------|
| 26A | PO page cleanup: platform guard, count badges, date formatting, loadError guard |
| 26B | Swipe actions with AI summary confirmation, sort options, awaiting delivery KPI |
