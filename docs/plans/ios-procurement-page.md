# iOS Procurement Planner + Order Staging Design

> **Pages:** `IOSProcurementPage.swift` (238 lines — needs complete redesign), `IOSOrderStagingPage.swift` (129 lines — needs redesign as Job Stage Planner)
> **Nav:** Orders → Procurement, Orders → Order Staging
> **Status:** Design CONFIRMED (2026-03-22)

## 1. Procurement Planner — Complete Redesign

### Current Problem
The page treats procurement as "list approved JPOs and generate POs one-by-one." It needs to be a **demand consolidation engine** that groups ALL demand by PART, shows all suppliers, and lets the office batch-generate POs per supplier.

### Core Concept
The Procurement Planner is where the office turns DEMAND into ORDERS. It aggregates demand from 4 sources, groups by part, shows stock levels, suggests pull-from-shelf vs order, lets the office pick suppliers per part, and generates POs grouped by supplier.

### Demand Sources (4 types, shown as smart card filters)

| Source | Where it comes from |
|--------|-------------------|
| **JPO Parts** | Approved JPO line items that need ordering |
| **Wishlist** | Approved wishlist items (user/forecast/auto) |
| **Forecast** | Auto-approved forecast items (≥80% certainty + below MIN + auto-add=ON) |
| **Overstock** | Parts above TARGET that should be pulled from shelf instead of ordered |

### Stock Level Logic (CONFIRMED)

```
For each part in procurement:
    │
    ├── Stock ABOVE TARGET → "Good" — if JPO needs this part, pull from shelf
    │   Show: [Pull from Shelf] button
    │   Order enough to bring stock back to TARGET after pull
    │
    ├── Stock BETWEEN MIN and TARGET → "Below Target"
    │   Part is OK but not at ideal level
    │   If pulling would drop below MIN → order to cover
    │   Show: "Order to Target" option
    │
    ├── Stock BELOW MIN → "Understock"
    │   Needs ordering regardless
    │   If forecast auto-triggered → definitely understock
    │
    └── Stock ABOVE MAX → "Overstock" ⚠️
        FORCE a pull — at least enough to bring below MAX
        Show as mandatory pull, not optional

Goal: Maintain TARGET value for all parts.
Certainty must be ≥80% or physical audit triggered first.
```

### "Bring to Target" Button

Every part that can use it gets a button showing:
- **(+15)** — need to add 15 to reach target (order or pull from elsewhere)
- **(-8)** — have 8 over target (suggest pulling for JPOs or returning)

### Smart Pull Options (use TARGET as reference — CONFIRMED)

When a part has stock available and a JPO needs it:

1. **[Pull to Target + order remaining]** — ALWAYS available, RECOMMENDED (highlighted)
2. **[Pull all from shelf + order remaining]** — only if shelf has enough for the full order
3. **[Pull to MIN + order remaining]** — if pulling to target would drop below MIN
4. **[Order all (don't pull)]** — skip shelf, order everything from supplier

The `+ order remaining` portion only shows if an order will actually be made. If pulling from shelf covers everything, no order text shown.

### Supplier Selection (CONFIRMED)

Show ALL suppliers that carry each part, but highlight three:
- 🟢 **Cheapest** — lowest unit price
- ⭐ **Highest Rated** — best reliability score
- ⚡ **Fastest** — shortest delivery time considering:
  - If order sent before 2 PM today → can get on today's truck
  - After 2 PM → window closed, use standard processing time
  - Processing time + delivery day from supplier page info

**Generic parts (brand = "General"):**
- Check job tags on the related JPO
- Let supplier be set per-JPO for generic parts (supplier locked per job)

**Branded parts:**
- Any supplier OK — pick cheapest/fastest/best rated

**Split orders:**
- User can click into a part and split the order by JPO
- Example: JPO #127 is urgent → send to fastest supplier, JPO #131 normal → send to cheapest
- Default: full quantity grouped together to one supplier

### Over MAX Enforcement

If a part is over MAX at any location → **FORCE a pull** (at least enough to bring below MAX). This is not optional — it shows as a mandatory action with a warning badge.

### PO Preview Before Generation (CONFIRMED)

Before clicking "Generate POs," show a preview:
- Grouped by supplier
- Within each supplier, grouped by job
- Shows: part name, qty, unit price, total
- Shows how many POs will be created
- User can remove items before generating

### Partial Generation (CONFIRMED)

- Office can generate POs for SOME parts and leave others for later
- "Next PO Drafting" — queued items stay in procurement for the next batch
- Generated items move to PO list as Draft status

### Procurement Page Wireframe

```
┌─ Procurement Planner ────────────── [🔍] [ℹ️] ─┐
│                                                    │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│  │ 📋 12   │ │ 🛒 5    │ │ 📊 3    │ │ ⚠️ 4   │ │
│  │JPO Parts│ │Wishlist │ │Forecast │ │Overstock│ │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ │
│  ┌─────────┐                                       │
│  │  24     │                                       │
│  │  All    │                                       │
│  └─────────┘                                       │
│                                                    │
│  20 parts need ordering · Est: $2,140              │
│                                                    │
│  ── Parts (grouped by part, sorted by urgency) ── │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ ½" Copper Fitting          Total: 55      │   │
│  │ Shop: 12 (Target: 30)  (+18 to target)    │   │
│  │                                            │   │
│  │ Sources:                                   │   │
│  │ ├─ JPO #127 (Smith)     qty: 20           │   │
│  │ ├─ JPO #131 (Oak Ave)   qty: 15           │   │
│  │ └─ Forecast restock     qty: 20           │   │
│  │                                            │   │
│  │ [Pull to Target + order 43]  ← recommended│   │
│  │ [Pull all 12 + order 43]                   │   │
│  │ [Order all 55]                             │   │
│  │                                            │   │
│  │ Supplier: ○ Acme $2.14 🟢cheapest         │   │
│  │           ○ Metro $2.05 ⚡fastest          │   │
│  │           ○ BuildCo $2.38 ⭐rated          │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ┌────────────────────────────────────────────┐   │
│  │ Standard Outlet (TR)       Total: 20      │   │
│  │ Shop: 42 (MAX: 40)  ⚠️ OVER MAX (-2)     │   │
│  │                                            │   │
│  │ ⚠️ MANDATORY: Pull at least 2 from shelf  │   │
│  │ [Pull 20 from shelf (covers full order)]   │   │
│  │ No supplier needed — fully covered         │   │
│  └────────────────────────────────────────────┘   │
│                                                    │
│  ═══════════════════════════════════════════════   │
│                                                    │
│  ── Ready to Generate ──                           │
│  8 of 20 parts have suppliers selected             │
│                                                    │
│  Preview:                                          │
│  • PO for Acme (3 jobs, 35 parts) — $847          │
│  • PO for Metro (2 jobs, 12 parts) — $246         │
│  │                                                 │
│  [Generate 2 POs] [Save for Later]                 │
│                                                    │
└────────────────────────────────────────────────────┘
```

## 2. Order Staging → Job Stage Planner (Redesign)

### Core Concept

This is NOT about PO staging. It's about **job construction stages** and when parts should be ordered/delivered based on the stage of work.

### Job Stages

Construction jobs have stages. Parts are needed at different stages:

| Stage | Example Parts | When Ordered |
|-------|--------------|-------------|
| **Rough-in** (Stage 1) | Wire, boxes, conduit | Ordered immediately |
| **Prep/Makeup** (Stage 2) | Outlets, switches, devices | Held until rough-in complete |
| **Trim-out** (Stage 3) | Cover plates, finish hardware | Held until makeup complete |

### How It Works

1. When creating a JPO (parts list for a job from scratch), parts are categorized by stage
2. Stage assignment is based on **category** — configurable per company
3. Parts for the CURRENT stage → released to procurement immediately
4. Parts for FUTURE stages → held as "pending stage change"
5. When a stage completes → held parts for the next stage get released to procurement
6. Parts can be requested early — user can override the hold ("send sooner")

### Stage Rules

- A part can be ordered during ANY stage at or after its assigned stage
- Example: Cover plates (Stage 3) can't be ordered during Rough-in (Stage 1)
- But outlets (Stage 2) CAN be ordered during Rough-in if the user overrides
- The hold is informational, not a hard block — it's a recommendation

### What the Page Shows

Like a JPO list for a specific job, showing ALL parts across ALL JPOs, grouped by stage:

```
┌─ Job Stage Planner ──────────────────────────────┐
│                                                    │
│  Job: Smith Residence (#412)                       │
│  Current Stage: Rough-in                           │
│                                                    │
│  ┌─ Stage 1: Rough-in (CURRENT) ──────────────┐  │
│  │ ✅ 14/2 Romex (250ft)      qty: 3   ordered │  │
│  │ ✅ Junction Box (4x4)      qty: 12  ordered │  │
│  │ ⏳ ½" Conduit              qty: 10  pending │  │
│  │                                              │  │
│  │ All parts for this stage accounted for       │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ┌─ Stage 2: Prep/Makeup (NEXT) ──────────────┐  │
│  │ ⏸ Standard Outlet (TR)     qty: 10  HELD   │  │
│  │ ⏸ 3-Way Switch             qty: 4   HELD   │  │
│  │ ⏸ Dimmer (Lutron Caseta)   qty: 5   HELD   │  │
│  │                                              │  │
│  │ [Release to Procurement] [Request Early]     │  │
│  │ These parts will auto-release when Stage 1   │  │
│  │ is marked complete.                          │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ┌─ Stage 3: Trim-out ────────────────────────┐  │
│  │ ⏸ Cover Plate (white)      qty: 10  HELD   │  │
│  │ ⏸ Wall Plate (2-gang)      qty: 4   HELD   │  │
│  │                                              │  │
│  │ Releases after Stage 2 complete              │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  ── Missing Parts ──                               │
│  No GFCI outlets planned for Stage 2               │
│  No wire nuts planned for Stage 1                  │
│  [+ Add to JPO]                                    │
│                                                    │
└────────────────────────────────────────────────────┘
```

### Settings (per company, configurable)

```
┌─ Stage Settings (Office → Settings) ──────────────┐
│                                                     │
│  Stages:                                            │
│  1. [Rough-in    ] ← rename, reorder, add/remove   │
│  2. [Prep/Makeup ]                                  │
│  3. [Trim-out    ]                                  │
│  [+ Add Stage]                                      │
│                                                     │
│  Category → Stage Mapping:                          │
│  Wire & Cable          → Stage 1 (Rough-in)        │
│  Boxes & Enclosures    → Stage 1 (Rough-in)        │
│  Devices & Receptacles → Stage 2 (Prep/Makeup)     │
│  Switches              → Stage 2 (Prep/Makeup)     │
│  Plates & Covers       → Stage 3 (Trim-out)        │
│  [Edit Mappings]                                    │
│                                                     │
│  Auto-release: ☑ When stage marked complete         │
│  Allow early request: ☑ Yes (user can override)     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## 3. Other Orders Pages — Issues to Fix

### IOSReceiveShipmentPage (505 lines) — Fix Prompts Needed
- **CRITICAL:** Hardcoded user ID `1` → use `appCore.currentUser?.id`
- Platform guard removal
- ActiveSheet pattern (currently `.sheet(isPresented:)`)

### IOSReturnsPage (185 lines) — Fix Prompts Needed
- `loadError` exists but never displayed → add ErrorStateView
- Errors only printed to console → show to user
- Platform guard removal
- Smart cards (replace capsule chips)

### IOSUnifiedApprovalsPage (in `Features/Office/`, 191 lines) — Quick Approval Dashboard

> **Naming note (Q&A 2026-04-25):** Earlier plan revisions referenced this as `IOSApprovalsPage`. The actual file is `IOSUnifiedApprovalsPage.swift` in `Weird Parts IOS/Features/Office/`. The router (`orders-approvals`) maps to it correctly. Unified page used across both Office and Orders tabs.
- Keep as quick-approval view for managers
- Shows what needs attention across ALL approval types (not just JPOs)
- Fix: `actionError` never displayed
- Fix: No reject reason requirement
- Fix: Platform guard
- Add smart cards

### IOSUnifiedOrderPage (123 lines) — CONSOLIDATE into CreateJPOSheet
- This page duplicates what CreateJPOSheet from 27A does
- Remove and redirect to JPO creation flow
- Update any routes that point here

### SupplierPickerSheet (117 lines) — Needs Redesign
- Wrong model: generates one PO per JPO
- Fix: Force-unwrap `item.supplier.id!`
- Will be superseded by procurement planner's per-part supplier selection

### CreateReturnSheet (110 lines) — Minor Fixes
- Return types hardcoded → use constants
- Platform guard removal

### OrdersRouter (20 lines) — Update for New Tab Order
```
Orders (workflow order):
├── Job Orders (JPOs)      ← starts the process
├── Procurement            ← sorts into POs
├── Purchase Orders        ← sent to suppliers
├── Parts Management       ← track across POs
├── Job Stage Planner      ← stage-based part timing (was "Order Staging")
├── Approvals              ← quick approval dashboard
├── Returns                ← problem solving
└── Wishlist               ← background/passive (future)
```

## Prompt Chain

| Prompt | What | Status |
|--------|------|--------|
| 28A | Procurement redesign: demand consolidation, stock level logic, pull options, smart cards | Done |
| 28B | Procurement supplier selection: per-part picking, highlight cheapest/rated/fastest, 2PM cutoff | Done |
| 28C | Procurement PO preview + generation: supplier-grouped preview, partial generation, "save for later" | Done |
| 28D | Job Stage Planner: stage model, category mapping, held/released parts, auto-release on stage complete | Done |
| 29A | Receiving fix: hardcoded user ID, ActiveSheet, platform guard | Done |
| 29B | Returns fix: ErrorStateView, console print→UI, platform guard, smart cards | Done |
| 29C | Approvals quick dashboard: smart cards, reject reason, fix actionError display, multi-type approvals | Done (IOSUnifiedApprovalsPage in Office/) |
| 29D | Orders cleanup: remove UnifiedOrderPage, update router for new tab order, consolidate SupplierPickerSheet | Done (UnifiedOrderPage→stub, router updated) |
