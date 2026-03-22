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

## 5. PO Lifecycle Workflow (Confirmed)

### JPO → PO Relationship

- **JPO** = Purchase Order for the JOB (what the job crew needs)
- **PO** = Purchase Order for the SUPPLIER (what we send to the supplier)
- Multiple JPOs get consolidated → grouped by supplier → POs created per supplier
- If 3 suppliers are needed, at least 3 POs are created
- Supplier is picked **per part** (not per PO)

### Status Flow

```
DRAFT → SUBMITTED → ORDERED → PARTIAL → RECEIVED
                                  ↓
                              CANCELLED (from any state except RECEIVED)
                              DRAFTING (needs clarification, usually one job's items)
```

### Status Details

| Status | Description | Actions Available |
|--------|------------|-------------------|
| **Draft** | PO created, not sent. Office can edit on Job Order Sheet. Parts grouped by job. | [Submit] [Delete Draft] — parts return to procurement, still need ordering |
| **Submitted** | Sent to supplier, awaiting confirmation | [Mark Ordered] [Cancel (reason required)] [Drafting/Unclear] |
| **Ordered** | Supplier confirmed. Parts on the way. | [Add Tracking] [Receive] [Cancel (reason required)] [Contact Supplier] |
| **Partial** | Some items received, some still coming. DEFAULT state = waiting. | [Receive More (default)] [Cancel Remaining (requires supplier contact)] [Contact Supplier (recommended)] [Double Order (branded parts only)] |
| **Received** | All items received. Historical record. | [Report Issue] [View History] |
| **Cancelled** | Cancelled at any point. Reason stored. | None (read-only) |
| **Drafting** | Needs more info from job creator. Usually affects one job. | [Resume Draft] [Contact Job Creator] |

### Draft Rules
- Edit happens on Job Order Sheet, Wishlist, or Forecast sources
- Wishlist and forecast items: combined or separate orders, up to target amount
- Expected delivery date set from supplier info UNLESS part is marked as "placed order" with custom date
- Parts grouped by job in the draft view
- Deleting a draft does NOT delete the parts need — they return to procurement planner

### Partial Rules (Office manages)
- **[Receive More]** is a DEFAULT STATE — not a button the user clicks. PO sits quietly until items arrive or remaining is cancelled.
- **[Cancel Remaining]** — requires contacting supplier first. Must confirm cancellation before marking.
- **[Contact Supplier]** — RECOMMENDED action. Opens supplier bridge channel. Purpose: get updated timeline/ETA.
- **[Double Order]** — NOT available for generic parts (supplier-locked per job). Creates a NEW PO with a DIFFERENT supplier for remaining parts. When both deliver: extra goes to shelf or returned, manager decides. Must email/call office to cancel late order.

### Receiving Rules
- Scan PO QR or select from list
- For each line item:
  - Enter qty received (may differ from ordered)
  - Some parts may be on backorder → confirm, add backorder row to PO
  - Verify price (matches PO? different? → update incoming price for that part from supplier)
  - Note any damaged items
- Confirm receipt
- If all received → RECEIVED, cost layers created (FIFO), stock added
- If partial → PARTIAL, remaining items tracked

### Part Removal from PO
- Removing a part from a PO ≠ cancelling the part order
- The part was put on the wrong PO/supplier by accident
- It gets held for a different PO with a different supplier, or held back temporarily
- **The part still needs to be ordered** — goes back to procurement planner

### Generic vs Branded Parts — Supplier Rules
- **Generic parts** (no brand): supplier locked per job. Once Job #412 uses Supplier C, stick with Supplier C for that part on that job.
- **Branded parts** (e.g., Lutron dimmer): any supplier OK. The brand IS the identity. Can consolidate freely, pick cheapest supplier.

## 6. Supplier CRM on PO Detail (Confirmed)

Mini-CRM section on PO detail page:
- Phone, email, rep name, account number
- Per-PO notes with timestamps (communication history for THIS order)
- [Add Note] [Call] [Message] [View Supplier Profile]
- Reliability/On-Time/Quality score bars
- Fast actions for the PO itself (Submit, Cancel, Receive, etc.)
- "Show POs for this supplier" button — defaults to non-closed states

### PO Detail — Fast Actions

PO-level fast actions ONLY on the detail page:
- [Submit] [Cancel] [Receive] [Contact Supplier] [Double Order]
- Part-level actions go on the Parts Order Management page (see below)

## 7. Parts Order Management Page (NEW)

Supplier-centric view showing ALL parts across ALL POs for one supplier.

- Shows all active POs for the supplier
- Parts grouped by PO, then by Job within each PO
- Checkboxes for multi-select → part-level fast actions appear
- Click individual part for detailed changes
- Smart filters: defaults to hiding Received + Cancelled POs
- Button on PO Detail opens this page filtered to that supplier

Part-level fast actions (when parts selected):
- [Move to Different PO]
- [Change Qty]
- [Remove + Hold] (returns to procurement for different supplier)

### Where it lives: TBD
Options under consideration:
- Orders → dedicated tab (alongside POs, JPOs, Procurement)
- Only accessible from PO Detail via "Manage Parts" button

### Export to Supplier
- Parts grouped by job in the export
- Supplier sees: "Job #412: 20 copper fittings, Job #418: 15 copper fittings"

## 8. Help/Info Button (Cross-Cutting)

**ALL pages in the program** should have a help/info button (like the AI button) that provides:
- What the page is used for
- How to use it (key workflows)
- Tips and best practices

This is a global requirement, not PO-specific.

## Prompt Chain

| Prompt | What |
|--------|------|
| 26A | PO page cleanup: platform guard, count badges, date formatting, loadError guard |
| 26B | Swipe actions with AI summary confirmation, sort options, awaiting delivery KPI |
| 26C | PO lifecycle: status transitions, Drafting status, backorder tracking |
| 26D | Supplier CRM section on PO detail: notes, fast actions, score bars |
| 26E | Parts Order Management Page: supplier-centric view, multi-select, part-level actions |
| 26F | PO export: job grouping, supplier communication format |
