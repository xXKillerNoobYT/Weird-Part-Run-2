# iOS Job Purchase Orders (JPO) Page Design

> **Pages:** `IOSJPOsPage.swift` (177 lines), `IOSJPODetailPage.swift` (331 lines)
> **Nav:** Orders → Job Orders (JPOs)
> **Status:** Design CONFIRMED (2026-03-21)

## Core Concepts

- **JPO** = Job Purchase Order — a field worker's request for parts for a specific job
- **Job** = a customer location. Parts brought to a job are billed to the customer. Parts removed = customer refund. **Jobs are NOT a valid source to pull parts from.**
- **Approval is ONLY needed for parts going to POs** (ordering from supplier). If a part is already at the shop or on the user's truck, it just creates a transfer request — no approval needed.
- **Per-part status model** — each line item in a JPO has its own status, not just the JPO overall.
- **Delivery options** — set when creating or editing a JPO BEFORE parts are delivered. Once order is completed, delivery option is locked.

## JPO Creation Flow

1. Field worker (clocked in to Job #412) taps [+ Create JPO]
2. Auto-fills: current job (from clock), requester name
3. If at shop → asks to pick a job
4. If at a different job site → asks to verify they're on the right job
5. Adds parts with quantities
6. Sets priority (Normal/High/Urgent)
7. Sets delivery option: "Deliver as parts arrive" or "Wait for full order"
8. Submits → JPO appears in list for office/manager review

**Office staff creating JPO:** Same flow but must manually pick the job. Auto-fill from clock if clocked into shop → ties into smart background system for auto-filling job context.

## Per-Part Status System

### JPO Overall Status (derived from parts)
- All pending → "Pending"
- Mix of statuses → "In Review"
- All approved/ordered → "Approved"
- All ordered+ → "Ordered"
- All delivered → "Complete"

### Per-Part Statuses

| Status | Meaning | Next |
|--------|---------|------|
| **pending** | Awaiting review | → approved, on_hold, rejected, transfer (if in stock) |
| **approved** | Approved for ordering | → in_procurement |
| **on_hold** | Question pending in Chat | → pending (after answered) |
| **rejected** | Denied with reason required | Terminal |
| **transfer** | Part is in stock, transfer request created | → staged, delivered |
| **in_procurement** | In procurement planner, being sorted into POs | → ordered |
| **ordered** | PO created and sent to supplier | → received, backorder |
| **received** | Arrived at shop | → staged, delivered |
| **backorder** | Supplier confirmed delayed | → received |
| **staged** | On truck/trailer, ready for delivery | → delivered |
| **delivered** | At the job site | Terminal |

### Smart Routing (approval vs transfer)

```
Part requested on JPO:
    │
    ├── Part is at SHOP with sufficient stock?
    │   → Auto-create transfer request (no approval needed)
    │   → Status: "transfer"
    │
    ├── Part is on USER'S TRUCK with sufficient stock?
    │   → Auto-create transfer request
    │   → Status: "transfer"
    │
    └── Part needs to be ORDERED from supplier?
        → Requires approval
        → Status: "pending" → manager reviews
```

## Hold + Chat Integration

When manager taps [Hold] on a specific part:
- Chat thread opens linked to JPO + specific part
- Manager can ask questions: "Do you need tamper-resistant?"
- Field worker responds in chat
- Manager can approve/reject after getting the answer
- Chat thread archived with resolution
- Per-part, not per-JPO — one part can be on hold while others are approved

## JPO → PO Linkage

After procurement processes approved parts:
- Each JPO line item gets linked to a PO line item
- JPO detail shows: which PO, which supplier, delivery timeline
- Per-part backorder actions: [Contact Supplier] [Double Order] (branded parts only)
- Receipt at shop updates JPO line status automatically
- Transfer to job updates JPO line status automatically

## Delivery Options (per JPO, set at creation)

- **◉ Deliver available parts as they arrive** — partial deliveries OK
- **○ Wait for complete order before delivery** — hold everything until full order received
- Set when creating or editing JPO
- **Locked once any parts are delivered** — can't change after that

## Full Part History / Audit Trail

**CRITICAL REQUIREMENT:** Every part needs a complete audit trail visible when clicking into the part:
- Who created it, when
- Every change: color, type, style, name, code, pricing changes
- Who made each change
- Example: "James made a parts list, Jarrett changed a part" → shows Jarrett did it
- Full logging — easy to see in the part detail view
- This applies across the entire app, not just JPOs

## Issues Found in Current Code

1. No "Create JPO" button on list page
2. No link between JPO and the PO it generated
3. `#if os(iOS)` platform guards (3 locations)
4. No count badges on status filter chips
5. `guard let service` doesn't set loadError (2 pages)
6. Reject has no reason requirement
7. `.sheet(isPresented:)` instead of `.sheet(item:)` ActiveSheet pattern on detail page
8. No QR scan to look up a JPO
9. No per-part status — currently only JPO-level status
10. No help/info button
11. No delivery options field

## Orders Tab Arrangement (CONFIRMED)

Tabs arranged in workflow order — process start at top, problem solving at bottom:

```
Orders
├── Job Orders (JPOs)    ← 1. Field creates request (starts process)
├── Procurement          ← 2. Office sorts approved parts into POs
├── Purchase Orders      ← 3. POs sent to suppliers
├── Parts Management     ← 4. Track parts across POs
├── Approvals            ← 5. Pending approvals
├── Returns              ← 6. Problem solving
└── Wishlist             ← 7. Background/passive
```

## Cross-Page Connections

| From | To | How |
|------|-----|-----|
| Clock Page | JPO List | [Create JPO] button, auto-fills job |
| Job Detail | JPO List | [Create JPO] button, auto-fills job |
| JPO Detail | Chat | [Hold] opens per-part chat thread |
| JPO Detail | Procurement | Approved parts flow to procurement planner |
| JPO Detail | PO Detail | Link to view the PO that contains this part |
| JPO Detail | Movement Wizard | Transfer request for in-stock parts |
| Procurement | JPO | Groups JPO parts with wishlist + forecast for PO generation |
| PO Receiving | JPO | Receiving updates JPO line status to "received" |
| Warehouse Staging | JPO | Transfer updates JPO line status to "staged" → "delivered" |
| Forecasting | JPO | JPO consumption data feeds into forecast calculations |

## Prompt Chain

| Prompt | What | Status |
|--------|------|--------|
| 27A | JPO list cleanup: ActiveSheet, QR scan, count badges, platform guards, Create JPO button, loadError guard | Queued |
| 27B | JPO per-part status model: migration for line-item statuses, smart routing (stock check → transfer vs approval) | Queued |
| 27C | JPO detail redesign: per-part approve/hold/reject, bulk actions, delivery options, PO linkage display | Queued |
| 27D | JPO Hold + Chat: per-part chat thread, question/answer flow, archive on resolution | Queued |
| 27E | JPO full audit trail: part change history logging, who-did-what display in part detail | Queued |
