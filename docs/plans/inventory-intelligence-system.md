# Inventory Intelligence System — Draft Plan

> **Status:** IMPLEMENTATION COMPLETE (core) / DESIGN TBD (advanced features in Part F)
> **Scope:** Forecasting backbone + Wishlist + Procurement Planner redesign + movement suggestions + smart pull
> **Related:** `ios-page-review-tracker.md`, `forecasting-page-redesign.md`
> **Last updated:** 2026-04-19

## Current Implementation Status (as of 2026-04-19)

**DB Migrations:** 029 (`location_stock_targets`), 030 (`forecast_settings`, `location_free_space`), 031 (`target_recommendations`), 057 (`wishlist_items`), 070 (`wishlist_items_v2` — adds `dismiss_reason`, `auto_approve_at`, `certainty_score`). All in `AppDatabase+Migrations.swift`.

**PartsService methods implemented:** `listForecastDataWithStock`, `listForecastData`, `recalculateForecasts`, `recalculateForecastsPerLocation`, `getForecastSettings`, `saveForecastSettings`, `getFreeSpaceRating`, `setFreeSpaceRating`, `listAllForecastSettings`, `generateDailyRecommendation`, `listPendingRecommendations`, `approveRecommendation`, `dismissRecommendation`, `pendingRecommendationCount`, location stock target CRUD.

**WishlistService methods:** `listItems`, `getItem`, `approveItem`, `dismissItem`, `sendToProcurement`, `reopenItem`, `getSectionedItems`, `addItem`, and supporting CRUD. 46 dedicated tests in `WishlistServiceTests.swift`.

**iOS pages:** `PartsForecastingPage.swift`, `ForecastSettingsSheet.swift`, `IOSWishlistPage.swift`, `IOSForecastSettingsPage.swift`, `IOSInventoryGridPage.swift`, `StockLevelChart.swift` (shared).

**Advanced features still TBD:** Background task dashboard cards, movement suggestion engine, truck HAUL vs. inventory flag, certainty rating algorithm (see Part F table below for full status).

---

## Security & Access Control

- **view_inventory / view_forecasting** — read access to forecast data, wishlist list view
- **manage_inventory** — approve/dismiss recommendations, set free-space ratings, send items to procurement
- **manage_orders** — approve wishlist items, create PO from wishlist
- No forecast data contains PII; location data is internal warehouse topology only.
- `wishlist_items.added_by_id` references `users.id` — soft-delete defense applies (deleted users' wishlist items stay visible under system attribution).

## User Roles

| Role | Access |
|------|--------|
| Any user | View forecasting page, add to wishlist |
| Warehouse manager | Approve/dismiss stock recommendations, set free-space ratings |
| Purchasing / office | Approve wishlist items, send to procurement, create POs |
| Driver / field | View their truck's stock health via forecasting location filter |

## HIG / Accessibility Notes

- Forecasting stat cards are tappable filters — must use `.accessibilityAddTraits(.isSelected)` when active.
- Health-bar visualizations use color only (red/orange/green) — must have text fallback (e.g. "Below minimum: 3 remaining").
- Recommendation dismiss requires a reason — `TextField` must use `accessibilityLabel`.
- `StockLevelChart` is a SwiftUI Chart — must have `.accessibilityLabel` on chart marks for VoiceOver.

## Test Plan

- Unit: every PartsService forecasting method is covered in `PartsServiceCoverageTests.swift` (recalculate, list, settings, recommendation CRUD).
- Unit: WishlistService — 46 tests in `WishlistServiceTests.swift` covering full lifecycle (add → approve/dismiss → send to procurement).
- Integration: `recalculateForecasts` and `recalculateForecastsPerLocation` must run without throwing on empty DB AND on DB with stock movement history.
- Edge cases: 90-day minimum data threshold, 60-day recommendation cooldown, MIN < TARGET < MAX validation.
- UI: PartsForecastingPage location picker, stat card filter toggle, detail panel editor round-trip (edit MIN/TARGET → save → reload).

---

---

## Overview

A location-aware inventory intelligence system that tracks stock health per location (shop, truck, trailer), calculates forecasts per location, suggests inventory movements between locations, and integrates with the ordering system for automated replenishment.

**Core principle:** The three stock fields (MIN, TARGET, MAX) exist per-location and drive different behaviors depending on location type and situation.

---

## Part A: Forecasting Page Backbone (BUILD NOW — Prompts 23A-23D)

### A1. Stat Cards as Filters (Prompt 23C — confirmed)

Replace the separate filter chip bar with tappable stat cards:
- Cards show global counts always (Critical / Warning / Healthy)
- Tap a card → highlights it, filters the list to that urgency
- Tap the same card again → deselects, shows all
- Delete the horizontal scroll filter chip bar entirely
- Section header shows: "3 critical parts" / "12 warning parts" / "60 parts" (all)

Visual treatment:
- Unselected: subtle background, number in urgency color
- Selected: urgency color fills card background, white text, slight scale/shadow

### A2. Per-Location Forecasting Data (Prompt 23D — confirmed)

**Current state:**
- `parts` table has global `min_stock_level`, `max_stock_level`, `target_stock_level`
- `stock` table already has `location_type` + `location_id` per row
- `stock_movements` tracks `from_location_type/id` → `to_location_type/id`
- Forecast fields (`forecast_adu_30`, etc.) are global on `parts` table

**What's needed — new table:**
```sql
CREATE TABLE location_stock_targets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    location_type TEXT NOT NULL,  -- 'warehouse', 'truck', 'trailer'
    location_id INTEGER NOT NULL,
    min_stock INTEGER NOT NULL DEFAULT 0,
    target_stock INTEGER NOT NULL DEFAULT 0,
    max_stock INTEGER NOT NULL DEFAULT 0,
    forecast_adu_30 REAL DEFAULT 0,
    forecast_adu_90 REAL DEFAULT 0,
    forecast_days_until_low INTEGER DEFAULT 999,
    forecast_suggested_order INTEGER DEFAULT 0,
    forecast_last_run TEXT,
    certainty_rating REAL DEFAULT 0,  -- 0.0 to 1.0, based on data quality/quantity
    part_category TEXT DEFAULT 'common',  -- 'common' or 'critical' (per part per location)
    do_not_restock INTEGER DEFAULT 0,     -- 1 = part will be removed once stock depletes
    deleted_at TEXT,
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(part_id, location_type, location_id)
);

-- Forecast settings: per location-type defaults + per individual location overrides
-- Row with location_id=NULL is the default for that location_type
-- Row with location_id set overrides for that specific truck/warehouse/trailer
--
-- USAGE CALCULATION UNITS:
--   Shop/Warehouse: ADU (Average Daily Usage) — parts per day, calculated over adu_lookback_days
--   Truck/Trailer:  APW (Average Per Window)  — parts per X weeks, user picks window_weeks (1-6)
--   These are fundamentally different units. No conversion between them.
--
CREATE TABLE forecast_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    location_type TEXT NOT NULL,           -- 'warehouse', 'truck', 'trailer'
    location_id INTEGER,                   -- NULL = default for type, set = specific location
    usage_unit TEXT DEFAULT 'daily',       -- 'daily' (shop: parts/day) or 'weekly' (truck: parts/X-weeks)
    adu_lookback_days INTEGER DEFAULT 365, -- shop: how many days of history to average over
    window_weeks INTEGER DEFAULT 3,        -- truck: averaging window 1-6 weeks
    min_data_days INTEGER DEFAULT 90,      -- minimum days of data before recommendations
    common_min_multiplier REAL DEFAULT 3.5,    -- shop: days, truck: weeks
    common_target_multiplier REAL DEFAULT 14.0,
    common_max_multiplier REAL DEFAULT 21.0,
    critical_min_multiplier REAL DEFAULT 7.0,
    critical_target_multiplier REAL DEFAULT 14.0,
    critical_max_multiplier REAL DEFAULT 30.0,
    free_space_suppress_threshold INTEGER DEFAULT 3,
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(location_type, location_id)
);

-- Free space ratings per location, updated monthly
CREATE TABLE location_free_space (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    location_type TEXT NOT NULL,
    location_id INTEGER NOT NULL,
    free_space_rating INTEGER NOT NULL DEFAULT 5,  -- 1-10 scale
    updated_by INTEGER REFERENCES users(id),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(location_type, location_id)
);
```

- Parts table `min_stock_level`/`target_stock_level`/`max_stock_level` become **company-wide defaults**
- `location_stock_targets` holds **per-location overrides**
- If no override exists for a location, fall back to the part's global defaults
- `certainty_rating` = how much data we have (few movements = low certainty, many = high)

### A3. Forecasting Page Per-Location View

The forecasting page gets a location picker:
- **All** (default) — shows weighted average across all locations
- **Shop/Warehouse** — shop-specific forecast
- **Truck [Name]** — that truck's forecast (only shows for the user assigned to that truck)
- **Trailer [Name]** — that trailer's forecast

When a location is selected, the list shows parts relevant to that location with that location's stock levels, ADU, and health indicators.

### A4. Detail Panel Redesign

When tapping a part in the forecast list, the detail sheet becomes a full part editor:

**Section 1: Part Info (editable)**
- Name, Code, Part Number
- Category/Style/Type/Brand
- Pricing (cost, markup, sell price)
- All part fields that are currently editable on the catalog detail

**Section 2: Stock Health Per Location**
- One row per location where this part exists
- Each row shows: Location name, current qty, MIN | TARGET | MAX
- Health bar visualization: red zone (below MIN) → orange (below TARGET) → green (at TARGET) → yellow (above TARGET approaching MAX) → red (at/above MAX)
- Bar has CENTER marker at TARGET value

**Section 3: Forecast Metrics**
- ADU-30, ADU-90, trend indicator
- Days until low (per selected location or global)
- Suggested order qty
- Certainty rating (visual bar)

### A5. Recalculate — Background Processing

- Runs **once per day** automatically (not manual button only)
- Tied into a **background task status bar** system for auto-tasks
- Uses pre-processed info — saves results to DB, UI reads saved data
- Manual "Recalculate" button still exists for on-demand refresh
- Status bar shows: "Forecasts: Updated 6h ago" or "Recalculating..."

**Background task system — Dashboard card (confirmed design):**

Dashboard gets a "Daily Background Tasks" card showing all auto-tasks:

- **Two groups:** System (shop computer) tasks vs Your Device tasks
- **Time range:** Today + yesterday
- **System tasks:** Forecast recalc, companion auto-discovery, audit scans — run on shop computer, results sync to devices
- **User tasks:** Sync pulls, device-specific operations
- **Each task shows:** Name, status (✅ completed / ⏳ scheduled / 🔄 running / ❌ failed), timestamp
- **Server freshness info card** at bottom: "Last Sync: X min ago", "Shop computer data as of: [timestamp]", connection status
- This tells the user exactly how up-to-date or out-of-date their device's data is

**Implementation:** Dashboard page gets new cards. The forecast `forecast_last_run` field (already saved) feeds the timestamp. New `background_task_log` table needed for tracking all task types.

NOTE: Build this when we review the Dashboard page — the forecasting backbone (23D) already saves the timestamps this card will read.

---

## Part B: Wishlist System (CONFIRMED DESIGN)

### B1. What It Is

A **company-wide "we want these parts" list** — separate from the Procurement Planner but feeds into it. Anyone can add parts. It's a suggestion box for ordering that gets reviewed and approved before becoming actual purchase orders.

**Location in nav:** Orders → Wishlist tab

**Three separate sections in the UI:**
1. **👤 User Added** — parts added manually by any user
2. **📊 Forecast Demand** — parts the forecast system says are needed (pre-approved before reaching wishlist)
3. **⚙️ System Auto-Added** — top-usage parts auto-added (per-part toggle, pre-approved)

### B2. Wishlist Table

```sql
CREATE TABLE wishlist_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    source_type TEXT NOT NULL,           -- 'user', 'forecast', 'auto'
    qty_suggested INTEGER NOT NULL DEFAULT 1,
    reason TEXT,                         -- why added (optional for add)
    added_by INTEGER REFERENCES users(id),  -- NULL for system/forecast
    location_type TEXT,                  -- which location needs it
    location_id INTEGER,
    priority TEXT DEFAULT 'normal',      -- low/normal/high
    status TEXT DEFAULT 'pending',       -- pending/approved/dismissed/ordered
    auto_added INTEGER DEFAULT 0,       -- 1 if system added
    auto_approve_at TEXT,               -- user items: created_at + 14 days
    approved_by INTEGER REFERENCES users(id),
    approved_at TEXT,
    dismissed_by INTEGER REFERENCES users(id),
    dismissed_reason TEXT,              -- ALWAYS REQUIRED when dismissing
    sent_to_procurement_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

### B3. Approval Flow by Source

**USER ADDED:**
```
User adds part → Pending (2-week auto-approval timer starts)
    → Auto-approved after 2 weeks (default, configurable)
    → OR Manager/Admin/Office clicks [Approve] early
    → OR [Dismiss] with REQUIRED reason
    → Approved items feed into Procurement Planner
```

**FORECAST:**
```
Forecast system identifies part below MIN at a location:
    Check 1: Per-part auto-add = TRUE?              → NO: stop
    Check 2: Stock at THIS LOCATION below MIN?      → NO: stop
    Check 3: Certainty at THIS LOCATION ≥ 80%?
        → YES: Auto-approved → Wishlist (approved) → Procurement
        → NO:  Physical AUDIT at that location first
               IMPORTANT: "Audit" means a PHYSICAL INVENTORY COUNT —
               someone walks to the shelf/truck and counts the actual parts.
               It is NOT a screen-based review. The purpose is to verify
               the real qty before ordering, because low certainty means
               we don't trust the number in the database.

               Shop/Trailer: anyone can do the physical count
               Truck: ONLY the user assigned to that truck can count
               After count updates the inventory →
                   if still below MIN → approve to wishlist
                   if count shows enough stock → dismiss (data was wrong)
```

**SYSTEM AUTO-ADDED (per-part toggle):**
Same rules as forecast — requires auto-add=ON, below MIN at location, ≥80% certainty.

**CRITICAL RULE: All auto-approve checks are PER-LOCATION.**
A part may be above MIN at the shop but below MIN on Truck #3.
Auto-approve only fires for the specific location that's below MIN.
The wishlist item records which location triggered it (location_type + location_id).

### B4. Truck/Trailer Below MIN — Shop Check First

**Critical rule:** When a truck or trailer is below MIN, check if the shop has the part FIRST:

```
Truck #3: Part X below MIN
    │
    ├── Shop HAS Part X in stock → Stage MOVEMENT (pull from shop to truck)
    │                               Do NOT create wishlist item
    │
    └── Shop DOES NOT have Part X → Create WISHLIST item
                                    (need to order from supplier)
```

**Same logic for trailers.** Solve internally before ordering externally.

### B5. Auto-Add Per-Part Setting

- **Per-part toggle** on part detail: "Auto-add to wishlist when low"
- NOT a global on/off — each part individually
- Permission to toggle: managed in Hats (default: Admin, Manager)
- When enabled AND stock at a location drops below MIN AND certainty ≥80% → auto-add

### B6. Permissions (all through Hats)

| Action | Default Access |
|--------|---------------|
| Add to wishlist (manual) | All users |
| View wishlist | All users |
| Approve wishlist items | Admin, Manager, Office |
| Dismiss items (reason ALWAYS required) | Admin, Manager, Office |
| Toggle per-part auto-add | Admin, Manager |
| Configure auto-approval timer | Admin |
| Truck inventory wishlist (for their truck) | All users (default ON) |

---

## Part C: Procurement Planner Redesign (CONFIRMED DESIGN)

### C1. Current State

The existing procurement page ONLY shows approved JPOs. It's a "JPO inbox" — no forecast integration, no wishlist, no demand consolidation.

### C2. Redesigned Procurement Planner

The procurement planner becomes a **demand aggregator** that groups all demand by part:

**Four demand sources:**

| Source | Where it comes from | Shows as |
|--------|-------------------|----------|
| JPO | Job crew creates JPO → Manager approves | "Job Demand" |
| Wishlist (user) | Anyone adds manually, 2-week auto or manual approve | "Wishlist" |
| Forecast | System forecast, pre-approved at ≥80% certainty | "Forecast" |
| Auto-suggested | Per-part auto-add, pre-approved | "Auto" |

**Plus overstock alerts:** Parts at/above TARGET with high certainty → "pull from shelf" instead of ordering.

### C3. Demand Consolidation (Option C — confirmed)

All demand for the same part is grouped into one row:

```
🔧 1/2" Copper Fitting                         Total: 70
├── JPO #412 (Smith Residence)              qty: 20
├── JPO #418 (Oak Ave Remodel)              qty: 15
├── Wishlist (Mike added Mar 18)            qty: 15
└── Forecast restock (Shop, to target)      qty: 20

Suppliers that carry this part:
  Acme Supply       $2.14/ea  ⭐ 94% reliability
  BuildCo           $2.38/ea  ⭐ 87% reliability
  Metro Parts       $2.52/ea  ⭐ 91% reliability

[Generate PO] [Split by Supplier] [Adjust Qty]
```

**Key rules:**
- Supplier picked **PER PART** (per line item), not per JPO
- Show **ALL suppliers** that carry that part, with pricing and reliability scores
- Group by part_id — all demand sources for the same part consolidated
- **Generic parts (no brand):** Job-supplier lock — if Job #412 already used Supplier C for this part, that line is locked to Supplier C. Can't group with other suppliers for the same job.
- **Branded parts (has brand_id):** No supplier lock — a Lutron is a Lutron. Consolidate freely, pick cheapest/best rated supplier.

### C4. Overstock — Uses TARGET Amount

When a part is overstocked and an order includes it:

Smart pull options (reference TARGET, not MAX):

1. **[Pull all from shelf + order remaining]** — Only if shelf covers full qty
2. **[Pull to MIN + order remaining]** — If full pull would drop below MIN
3. **[Pull to TARGET + order remaining]** — Always available, **RECOMMENDED** (highlighted)

NOTE: "+ order remaining" only shows if a PO will actually be created. If pulling covers everything, just show "Pull from shelf."

"Pull to TARGET" is always the recommended option — use button coloring to show that.

### C5. When PO Generated from Consolidated Demand

- All source items (JPOs, wishlist items, forecast items) marked as `ordered`
- PO line items link back to all sources they satisfy
- When PO received, parts distributed to the locations that needed them

---

## Part C2: Recommended Stock Target Changes (CONFIRMED)

System analyzes usage patterns and recommends changes to TARGET amounts per location.

**Recommends all 3 values:** MIN, TARGET, and MAX — not just TARGET.
**Also recommends adding/removing parts from locations** based on usage patterns.

**Validation rules (always enforced):**
- MIN < TARGET < MAX (strict ordering)
- MIN cannot be set above current inventory at that location
- MAX cannot be set below current inventory at that location
- System adjusts recommendations to satisfy these constraints before showing them

### Settings — Per Location Type (Shop vs Truck)

Shop and trucks use **different settings** for everything. All configurable in Settings.

**Configurable values (per location type):**

| Setting | Shop Default | Truck Default |
|---------|-------------|---------------|
| ADU period | 365 days | 180 days (shorter timeframe) |
| Min data required | 90 days | 60 days |
| Common: MIN multiplier | ×3.5 days | ×1 week |
| Common: TARGET multiplier | ×14 days (2 weeks) | ×2 weeks |
| Common: MAX multiplier | ×21 days (3 weeks) | ×3 weeks |
| Critical: MIN multiplier | ×7 days | Average usage per billing cycle* |
| Critical: TARGET multiplier | ×21 days | Based on 3-year usage frequency* |
| Critical: MAX multiplier | ×30 days | TARGET × 1.5* |

*Truck critical parts use a different formula — based on average quantity used per occurrence (e.g., crimps: 25 per use) over last 3 years of data, not daily ADU. This captures parts that are rarely used but consumed in bulk when needed.

**Truck philosophy:** Small quantity, large variety. Trucks want the minimum amount of as many different parts as possible — coverage for any job, not depth in one part.

**Per-truck settings:** Each truck can have its own settings (not just "all trucks use same defaults") because different trucks do different types of work. Settings configured by the assigned user or their manager.

**Averaging window:** Trucks use a **1-6 week averaging window** (configurable per truck, default 3 weeks) instead of the shop's 365-day window. This better captures truck-scale usage patterns where a part might be used heavily one week and not at all for several weeks.

### Two Part Categories — Common vs Critical

Each part at each location is classified as one of two types:

- **Common:** Easy to get, used often, high turnover. Aggressive restocking, shorter buffers OK because you can reorder quickly.
- **Critical:** Needed in a pinch, hardly used, usually hard to get. Higher MIN relative to usage, longer buffers, never let it run out.

This is a **per-part-per-location** setting — a part could be "common" at the shop but "critical" on a truck.

### Usage Filter — Add/Remove Part from Location

The system can recommend adding or removing parts from locations:

**Removal recommendations (top 5 list):**
- Show the 5 best candidates for removing from inventory entirely
- Any part at any location can be set to **"Don't Restock"** — part stays until stock depletes naturally, then removed
- **RULE: Parts on ANY truck or trailer can NEVER be recommended for removal from the shop.** If it's on a truck, the shop must stock it.

**Add-to-shop recommendations (top 5 list):**
- If a worker keeps a part stocked on their truck that the **shop doesn't carry** → recommend adding to shop inventory
- If truck inventory (NOT haul) is consumed for jobs **3+ times per year** → the original job orders keep missing this part. Recommend adding to shop so it flows through the normal JPO → PO ordering process. Show stats: "Used from truck stock on X jobs this year."
- Top 5 only — don't overwhelm.
- Only recommend if shop has free space.

**Key insight:** Truck stock is emergency backup. Regularly pulling from it for jobs means the shop's ordering pipeline is missing the part. The fix isn't more truck stock — it's adding the part to shop inventory.

**Category change suggestions:**
- **Common → Critical:** If a part is listed as Common at a location but **hasn't been used in 6 months** → prompt: "Consider marking as Critical or removing?"
- **Critical → Common:** If a part is listed as Critical at a location but has been **used consistently for 6+ months** (used in at least 4 of the last 6 months) → prompt: "This part is used regularly now. Consider marking as Common for more aggressive restocking?"
- A part can be **Common at the shop but Critical on a truck** — different usage patterns per location type

### Free Space Rating — Per Location

- Scale **1 to 10** per location (1 = nearly full, 10 = lots of room)
- **Monthly notification** sent to update the rating
- Constrains recommendations: low free space → don't recommend adding new parts or raising targets
- Shop: updated by warehouse manager
- Truck: updated by assigned user

### Calculation (using location-type settings and part category)

For a given part+location:
1. Determine location type (shop/truck/trailer) → load that location type's settings
2. Determine part category at this location (common/critical) → select multipliers
3. ADU = usage over configured period (365d for shop, 180d for truck, etc.)
4. Recommended MIN = ADU × MIN multiplier
5. Recommended TARGET = ADU × TARGET multiplier
6. Recommended MAX = ADU × MAX multiplier
7. Apply validation constraints (MIN < TARGET < MAX, respect current inventory)
8. Check free space rating — suppress "add part" or "raise target" if space ≤ 3

**Rules:**
- **90 days minimum data** required at that location before any recommendation is generated
- **Max 1 recommendation per day** — system picks the most impactful candidate (biggest gap)
- **Show up to 14 days** of recommendations in the queue
- **60-day cooldown** after a recommendation — don't recommend that part+location again for 2 months (whether approved, dismissed, or ignored)
- **Always manual approval** — system never auto-adjusts targets

**Daily background task flow:**
1. Calculate ADU-365 for every part+location with 90+ days data
2. Recommended target = ADU-365 × 14
3. Compare to current target — if difference > threshold → candidate
4. Exclude any part+location with recommendation in last 60 days
5. Pick the ONE most impactful candidate
6. Create recommendation record

**Who sees what:**
- Shop recommendations → Office / Manager / Admin
- Truck recommendations → Only the assigned truck user
- Trailer recommendations → Office / Manager / Admin

**Where it shows:**
- Forecasting page: filter to show parts with pending recommendations + badge count
- Part detail: "Recommended: change target from 10 → 30" with [Approve] [Dismiss (reason required)]
- Dashboard: part of the background tasks card

**New table needed:**
```sql
CREATE TABLE target_recommendations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    location_type TEXT NOT NULL,
    location_id INTEGER NOT NULL,
    current_min INTEGER NOT NULL,
    current_target INTEGER NOT NULL,
    current_max INTEGER NOT NULL,
    recommended_min INTEGER NOT NULL,
    recommended_target INTEGER NOT NULL,
    recommended_max INTEGER NOT NULL,
    adu_365 REAL NOT NULL,
    buffer_days INTEGER NOT NULL DEFAULT 14,
    data_days INTEGER NOT NULL,          -- how many days of data used
    status TEXT DEFAULT 'pending',       -- pending/approved/dismissed/expired
    approved_by INTEGER REFERENCES users(id),
    approved_at TEXT,
    dismissed_by INTEGER REFERENCES users(id),
    dismissed_reason TEXT,               -- REQUIRED when dismissing
    cooldown_until TEXT,                 -- created_at + 60 days
    created_at TEXT DEFAULT (datetime('now')),
    deleted_at TEXT
);
```

---

## Part D: MIN / TARGET / MAX Behavioral Rules (CONFIRMED)

### D1. MIN (Minimum Stock Level) — Per Location

- When stock falls below MIN at a location → trigger reorder alert
- Part should be ordered from supplier to replenish
- This is the "we need to buy more" threshold
- **Auto-approve check:** stock < MIN is a required condition for forecast auto-approve

### D2. TARGET (Target Stock Level) — Per Location

- The ideal quantity to have on hand
- **Return routing:**
  - If location is BELOW target → return goes to shelf (keeps stock healthy)
  - If location is AT or ABOVE target → return goes back to supplier
  - EXCEPTION: If part was from our own stock (not ordered for a job), it goes back to shelf since it came from our stock
- TARGET is the equilibrium point
- **Smart pull recommended option** always references TARGET

### D3. MAX (Maximum Stock Level) — Per Location

- Overstock warning threshold
- **Low certainty + near MAX** → add to physical audit list (don't trust the numbers)
- **High certainty + at/above MAX** → RED overstock warnings everywhere in the app
  - When making an order that includes this part, show overstock alert
  - Make pulling from shelf **mandatory** for that order
  - Smart pull options (see C4)

---

## Part E: Movement Suggestions (FUTURE — details TBD per page)

### E1. Shop ↔ Trailer (Tight Management)

When trailer is **at shop**:
- Suggested movements use **TARGET value** — tight, precise
- Goal: trailer leaves the shop fully stocked to target
- System compares trailer's current stock vs target, generates movement list

### E2. Shop ↔ Truck Moving Spot ↔ Trailer (On-Job, Loose Management)

When trailer is **on a job** (not at shop):
- Uses **MIN/MAX** range — less frequent, bigger changes
- More tolerance for variance since it's harder to manage in the field
- Movements happen when passing through shop or at job site

### E3. Shop ↔ Truck Inventory

- Truck **always uses TARGET amount**
- Only shows suggested movements **to the user assigned to that truck**
- Truck always pulls from shop inventory
- If shop doesn't have the part → goes to WISHLIST (not a movement order)

**IMPORTANT — Truck HAUL vs Truck Inventory:**
- **HAUL parts:** Parts being transferred through the truck for delivery to a job site. These do NOT count toward truck inventory levels. They're in transit.
- **Truck inventory:** Parts intentionally stocked on the truck for the truck's ongoing use. These count toward MIN/TARGET/MAX.
- The distinction matters because a truck might be carrying 50 HAUL parts for a job delivery but only have 5 parts as its own inventory. The forecasting system only cares about the 5.
- Implementation: movement_type or a flag distinguishes haul from stock. Details TBD when we review Warehouse/Movements pages.

### E4. PO Request from Movements

- On the movements page, if shop doesn't have stock for a requested pull
- User can create a PO request for low-value parts directly
- Links to the job that needs the part
- Feeds into the office ordering workflow

---

## Part F: Items Needing Detailed Design

| Item | Related Pages | Status |
|------|--------------|--------|
| Background task dashboard cards | Dashboard | Design CONFIRMED — see A5 |
| Wishlist UI + migration | Orders | Design CONFIRMED — see B1-B6 |
| Procurement planner redesign | Orders | Design CONFIRMED — see C1-C5 |
| Smart pull options during order creation | Orders (CreatePOSheet) | Design CONFIRMED — see C4 |
| Overstock warnings across all pages | Catalog, Movements, Orders | Design TBD |
| Truck-specific view permissions | Fleet, Forecasting | Design TBD |
| Trailer at-shop vs on-job detection | Fleet, Movements | Design TBD |
| PO request from movements page | Movements, Orders | Design TBD |
| Certainty rating calculation algorithm | Forecasting service | Design TBD |
| Movement suggestion engine | Warehouse, Fleet | Design TBD |
| Truck HAUL vs inventory flag | Warehouse, Fleet | Design TBD |
| **Supplier lock: generic vs branded** | Orders, Procurement | **CONFIRMED** — Two rules: (1) **Generic parts** (no brand): supplier matters per job — once Job #412 uses Supplier C for a generic part, that job sticks with Supplier C. Procurement can't consolidate locked lines across suppliers. (2) **Branded parts** (has a brand): supplier doesn't matter — a Lutron is a Lutron regardless of distributor. Consolidate freely, pick cheapest/best. Check `parts.brand_id` — if branded, no supplier lock; if generic (no brand), lock per job via stock_movements/po_line_items history. |

---

## Existing Schema We Build On

**Already exists:**
- `stock` table: `part_id`, `location_type` (warehouse/truck/trailer), `location_id`, `qty`
- `stock_movements` table: `from_location_type/id`, `to_location_type/id`, `movement_type`, `performed_by`
- `parts` table: `min_stock_level`, `max_stock_level`, `target_stock_level` (global defaults)
- `parts` table: `forecast_adu_30`, `forecast_adu_90`, `forecast_reorder_point`, `forecast_target_qty`, `forecast_suggested_order`, `forecast_days_until_low`, `forecast_last_run`
- `warehouse_locations` table: location registry with type/name
- `vehicles` table: trucks with assigned drivers
- `trailers` table: with `current_location_kind`
- `job_parts_orders` (JPOs), `jpo_line_items`, `purchase_orders`, `po_line_items`, `po_jpo_links`

**New (this plan):**
- `location_stock_targets` table: per-location MIN/TARGET/MAX overrides + per-location forecast data (Prompt 23D)
- `wishlist_items` table: company-wide parts wishlist with source tracking + approval flow

---

*Draft created: 2026-03-20 · Updated: 2026-03-21 — Wishlist + Procurement redesign confirmed*
