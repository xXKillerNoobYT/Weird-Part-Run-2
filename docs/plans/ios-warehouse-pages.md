# iOS Warehouse Pages Design

> **Files:** 15 files in `Features/Warehouse/`
> **Nav:** Warehouse → (Dashboard, Movements, Locations, Staging, Receiving, Audit, Inventory, Tools, Returns, Network, Settings)
> **Status:** Review complete, design decisions captured (2026-03-22)

## Design Decisions (Confirmed)

### Dashboard (CONFIRMED)
- **Smart cards ARE the KPI cards** — 4 cards (Moves Today, Receiving Active, Audit Due, Staged Ready) act as both KPIs and filters. Tap to filter activity feed, tap again for All.
- **Quick Nav** — horizontal scroll showing ALL warehouse sub-pages (10+) with icons. Not just top 5.
- **Activity rows** — tap opens detail sheet with a [View in Movements Page] button to navigate filtered.
- **Alerts/warnings banner** — shows below smart cards: "3 parts below MIN", "Audit overdue Zone A", "2 receiving sessions waiting". Prominent, not hidden.

### Movements Page (CONFIRMED)
- **Smart cards for ALL movement types** — 6 cards + All: Transfer, Received, Consumed, Return, Adjustment, All
- **Flat list, not date-grouped** — oldest to newest within groups
- **Two groups: Active (top) + Done/Completed (bottom)** — active movements at top, completed below
- **Completed movements hidden by default** — 7-day history shown when unhidden. Want more → dig into the log.
- **Delete duplicate wizard** — the `MovementWizard` inside WarehouseMovementsPage.swift is a duplicate of `IOSMovementWizard.swift`. Delete the inline one, keep the separate file. Make sure the separate file has all rules and movement info.
- **Show linked JPO number** on receive-type movements + info for all parts
- **Staging grouping** — movements grouped by what's in the staging area
- **File should be split** — 1,364 lines. Extract wizard (use separate file), extract detail sheet.
- **Damage marking** — need a way to mark a part as damaged on this page
- **Boxes are PHYSICAL** — real boxes with handwritten labels, not just digital grouping. UI guides what to write.

**[+] Quick Log (Flow 1)** — for informal logging without approval:
- 4 options: Grabbed parts for a job, Inventory adjustment, Returned parts from job, Moved between locations
- Opens simplified form: part (search/scan), qty, from, to
- No approval needed — just records what happened
- Detailed flow: see below

**Movement Detail Sheet:**
- Shows part, qty, from, to, JPO link, who created, when
- Actions: [Confirm Move] [Cancel Move] for pending moves
- [Mark Damaged] option for any part in a movement

**Pending movements** — created automatically by receiving flow (Flow 2) and by Orders page (pull from shelf). Active group shows these at top. User confirms or cancels.

### Movement Flows — Core Warehouse Logic (CONFIRMED)

**Flow 1: Quick Log / Manual Move**
- For logging things that already happened (inventory adjustments)
- For manually grabbing parts for small jobs WITHOUT a JPO
- Quick, informal, no approval — just record what was done
- The other warehouse pages capture detail needed for auto-logging properly

**Flow 2: System-Guided Receiving + Sorting + Prepping**
- ALL incoming parts land in the **RECEIVING AREA** (physical location in warehouse)
- System guides WHERE each part goes:
  - Staging area (for a specific job, pulled for JPO)
  - Warehouse storage (back on shelf — system says which shelf/bin)
  - Returns area (damaged, wrong item, back to supplier)
- **Pull types for JPO parts:**
  - Optional: suggested for this job, worker decides
  - Mandatory: must be pulled, can't skip
  - Prep in advance: pull + box now (during slow time)
  - Wait for job: just-in-time, set per storage unit
- **Job box prepping:** Group parts into boxes for a job. JobName + Box Number (4-digit max) handwritten on box. No QR on boxes yet (future). Must see what's in each box to verify. Parts that can't be grouped (per-part or per-category setting — NEEDS TO BE ADDED) stay separate.

**Return from truck (same flow as supplier delivery):**
- Same receiving area, same flow
- Target location changes based on:
  - Shelf stock levels (does the shelf need it?)
  - Another job wanting same part (JPO order states)
  - Damaged status
  - Wrong part → identify what it actually IS, update the individual part record, route to correct location
  - Part swap between jobs → identify the missing part from each job
  - Returns to supplier → PO number written on sticky note or box

**Receiving area is a PHYSICAL LOCATION** in the warehouse — not just a system status.

**"Can't be grouped" setting:** Per-part AND per-category. Needs to be added to the parts system (new field on parts table + category-level override).

### Locations Page — Full Multi-Layer System (CONFIRMED)
- **NOT a popup** — full multi-layer process with sub-pages inside
- Info at the top, details inside sub-layers
- Top-down floor layout of the warehouse with storage units
- Storage units: shelves, gang boxes, pipe racks, staging area, returns area, other storage devices
- Per-shop-location floor plans
- Storage level % per unit (visual)
- Click into a unit → see shelves, areas, bins within that unit
- Setting areas on storage units, adding bins, numbering
- Mark bins/areas as used or not
- Link parts to area or bin (bin = one part only, area = multiple bins and/or parts)
- Bins are movable between locations
- **Movements use info from here AND update info here** — bidirectional
- **Jobs do NOT show up here** — this is storage layout only
- **A ton of details — will take significant time to design and implement**

### Staging Page — Moving In/Out + Boxing (CONFIRMED)
- **No "clearing"** — it's MOVING parts in or out of staging
- Group parts into boxes by Job
- Or place on staging area shelves by area
- **An area may have several jobs in it** (try not to mix but sometimes necessary)
- **A job may be in several areas**
- Directly ties into movements
- No swipe-to-clear — staging is managed through movements

### Sorting/Receiving Page — Renamed (CONFIRMED)
- **Rename from "Receiving" to "Sorting/Receiving"**
- Two entry points: **PO Incoming** (supplier delivery) and **Job Return** (parts off truck)
- Several different options for processing the info
- **Knowing WHERE the part came from and confirming that is important**
- **NOTE:** The Movements page is used for cleaning parts off a job and returning everything that wasn't used

**Final Receiving Routing Flow (CONFIRMED):**
```
Part arrives in receiving (supplier OR job return)
    │
    1. CONDITION CHECK
       ├── USED → Shelf if below target, write off if not
       │          Cannot return to supplier
       ├── DAMAGED → Return to supplier (replacement OR refund)
       │              Cannot go on shelf
       └── GOOD → Continue
    │
    2. WRONG PART? → Identify correct part, check for job swaps
    │ NO
    3. Ordered FOR A JOB? (PO → JPO link)
       YES → Staging area for that job (DIRECT, skip shelf)
    │ NO
    4. Another active JPO wants this part?
       YES → Suggest staging for that job
    │ NO
    5. Put on SHELF at designated location
       ├── Below TARGET → normal restock
       ├── Above TARGET below MAX → restock, recommend return to supplier
       └── At/above MAX → flag overstock, recommend return
```

**Staging as smart buffer:** Parts returning from one job can immediately satisfy another job's demand without touching the shelf. Critical when parts are on backorder — returned parts from Job A fill Job B's need instantly.

**Key rules:**
- Staging parts do NOT count toward shelf inventory (reserved/sold)
- Parts for a job → staging directly (no double-handling)
- Parts for restock (no job link) → shelf
- "Pull from shelf" workflow (Orders page) is for parts ALREADY on shelf when new JPO arrives
- Used parts cannot be returned to supplier
- Damaged parts cannot go on shelf

### Locations — Physical Storage Hierarchy (CONFIRMED)

**Naming Convention:**
```
R[Row]-U[Unit]-S[Shelf]-A[Area]-B[Bin]
G0 = Ground Zero (floor under unit)
ST = Top of shelf
```

**Storage Hierarchy:** Warehouse → Row → Unit → Level → Area → Bin → Part

**Unit Types:**
- Shelving Unit: R-U-S-A-B (multiple shelves + G0 floor + ST top)
- Gang Box (movable): GB[num]-T[tray]-B[box] (trays with ~9 boxes each)
- Pipe Rack: R-U-T-A (horizontal tiers)
- Pallet Rack: R-U-L-A (wider spacing levels)
- Wall Mount: W-section-A (pegboard/hooks)
- Floor Area: F-zone-A (designated zones — staging, incoming, returns)
- Cabinet: R-U-D-A (drawers)
- Packout Set (movable): PK[num]-M[module]-C[compartment] (stackable modules)
- Tool Bag (movable): TB[num]-[compartment name]
- Parts Bin (movable): PB[num]-C[compartment]
- Crate/Tote: CR[num] (single open container)

**Sticker System (Physical Labels):**
- Row sticker at start of each row → scan shows all units in row
- Unit sticker on each storage unit → scan shows all levels/areas
- Shelf sticker at start of each level → scan shows areas on that shelf
- Area sticker on each area → scan shows ALL items assigned (present + checked out)
- Arrow ↑ = DEFAULT for everything. Arrow ↓ = ONLY for Ground Zero items (sticker on shelf above)
- Stickers identify the LOCATION, not the part. Parts move, locations don't.
- Phase 1: Sharpie + plain sticker with handwritten numbers. Phase 2: QR code stickers.

**Scanning shows everything at that location:**
- Parts physically present
- Tools/kits that belong here but are checked out (shows who has it + where they are)
- Empty spots where kits should be

**Directional Warehouse GPS:**
- Scan any sticker → app knows your current position
- Looking for a part → app gives directions: "Go RIGHT 9 rows, Unit 5, Shelf 2, Area 4"
- [Show on Floor Plan] button highlights the path

**Fixed vs Movable Storage:**
- FIXED: Shelves, pipe racks, wall mounts → pinned on floor plan, never move
- MOVABLE WITH HOME: Toolboxes, kits → dedicated shelf spot, shown as "checked out" when away
- MOVABLE WITHOUT HOME: Gang boxes, crates → big/bulky, go wherever there's room, approximate position on floor plan

**Kit/Toolbox Return Checklist:**
- When returning a kit to the shop: FULL parts + tools checklist
- System shows every item that should be in the kit
- User checks each item: ✅ Present, ❌ Missing, ⚠️ Damaged
- If user hits "Skip" instead of verifying → logged as "not verified"
- Managers can see: who verifies properly vs who always skips
- Missing items create alerts
- Damaged items route to replacement/repair workflow
- ALL logged — verification status, who, when, skipped items

**Onboarding Steps (physical warehouse setup):**
1. Physical measurements → room dimensions, unit counts
2. Sharpie + sticker → handwrite R01, U03, S02, A04 numbers
3. Enter in app → floor plan, units, areas match stickers
4. Generate QR codes → replace/augment handwritten stickers
5. Count bins → enter sizes, assign QR codes
6. Tie parts to locations → assign parts to areas/bins

**Areas can have multiple parts.** Bins hold one part type. Areas hold bins and/or loose parts.

**Each shelf level has different area counts** — Shelf 1 might have 4 wide areas, Shelf 2 might have 12 narrow areas.

**Under-shelf floor space (G0):** No max weight, extremely useful for heavy items. Still has areas.

**Tool storage zones:** Multiple dedicated areas for different kit types (electrical kits, panel kits, hand tools, power tools, laser equipment, conduit benders). Each zone is a storage unit on the floor plan with its own areas.

### Inventory Grid Page — Warehouse Location Picker (CONFIRMED)
- **Warehouse location picker** at top (there may be more than one warehouse)
- Parts-by-type grouped view for quick stock lookup at selected location
- Default location = last one visited (if multiple locations exist)
- NOT the same as Locations page (Grid = stock lookup, Locations = physical layout)

### Audit Pages — System Verification + Warehouse Onboarding (CONFIRMED)
- **What it does:** Verifies info and keeps records accurate for the whole program
- **Also used for warehouse onboarding** — moves user from basic job management to full warehouse integration
- **If a part's not in the system** → pretty workflow to add it
- **If a shelf doesn't say what's there** → add using shelf name + area number
- **If a part count doesn't add up and is indexed** → audit it (physical count)
- **If no count but system knows part is there** → index it, get location info so it can be properly tracked
- **Notes parts on several locations** — tracks multi-location parts
- **Doesn't just audit parts** — gets parts INTO the system, then helps ORGANIZE the warehouse
- **Makes actionable suggestions** — if rejected, asks WHY (captures the reason)
- **Uses Apple AI** to help with all of this (Foundation Models integration)
- **Area-by-area memory** for notes and other info
- **User chatting won't change the system** — but the AI assistant CAN read the notes and info
- **Ties into forecasting certainty** — below 80% certainty auto-triggers audit for that part
- **This is a major feature that powers the whole program's accuracy**

### Returns Page — Supplier Return Management (CONFIRMED)
- Seeing what goes to what supplier
- Getting boxes labeled properly
- Marking when parts have been picked up by the supplier
- NOT the same as the receiving/sorting flow — this is outbound to suppliers

### Network Page — Keep, Remove Dummy Data
Keep the page but remove fake data and "Phase 16" text. Will be one of the last things implemented.

### Warehouse Tools — Stays Separate
Warehouse-specific view of tools in the warehouse. Not a redirect to the Tools section.

## Issues Found (All Pages)

### Critical (3 pages with `import GRDB`)
1. WarehouseDashboardPage — raw SQL in UI
2. WarehouseMovementsPage — raw SQL in UI
3. WarehouseLocationsPage — raw SQL in UI

### High (display-only / non-functional)
4. IOSReceivingPage — can't start or continue receiving session
5. IOSAuditSetupView — startAudit() is a stub (dismisses without creating session)
6. IOSAuditSummaryView — no Finalize/Adjust actions
7. IOSStagingPage — no confirmation on swipe-to-clear (destructive)
8. IOSWarehouseReturnsPage — display-only, no approve/ship/complete
9. IOSWarehouseToolsPage — display-only, no checkout/return/maintenance
10. IOSInventoryGridPage — hardcoded to location ID 1

### Medium
11. IOSWarehouseNetworkPage — non-functional placeholder with fake data
12. All pages — platform guards (#if os(iOS))
13. IOSWarehouseSettingsPage — string-based settings, no type safety, print() errors
14. WarehouseDashboardPage — both quick action buttons navigate to same place

## Prompt Chain

| Prompt | What | Status |
|--------|------|--------|
| 31A | Dashboard: remove GRDB, smart cards, fix quick actions, platform guard | Queued |
| 31B | Movements: remove GRDB, ActiveSheet pattern, platform guard | Queued |
| 31C | Locations: remove GRDB, platform guard, add action buttons to detail sheet | Queued |
| 31D | Staging: add swipe confirmation, batch clear, platform guard | Queued |
| 31E | Receiving: add start/continue session actions, platform guard | Queued |
| 31F | Audit: fix setup stub, add finalize/adjust actions, platform guard, certainty tie-in | Queued |
| 31G | Inventory Grid: remove hardcoded location, group by type, location picker | Queued |
| 31H | Returns + Tools + Network + Settings: display→actionable, platform guards, cleanup | Queued |
| 31I | Router update: fix unknown route handling | Queued |
