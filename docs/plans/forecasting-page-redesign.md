# Forecasting Page Redesign — Design Plan

> **Status:** Design CONFIRMED — Prompts 23A-23H written
> **Implements:** Part A of the Inventory Intelligence System (`inventory-intelligence-system.md`)
> **Prompts:** `xcode-ai/fix-prompts/23A` through `23H`
> **Last updated:** 2026-03-21

---

## Goals

Transform the forecasting page from a simple global stock prediction list into a **location-aware inventory intelligence dashboard** that shows per-location stock health, generates daily recommendations for stock level adjustments, and provides a full part editor with health bar visualizations.

---

## Design Decisions (Confirmed)

### 1. Stat Cards as Filters (Prompt 23C)

- **Delete** the horizontal scroll filter chip bar (All/Critical/Warning/Healthy capsules)
- Stat cards (Critical count, Warning count, Healthy count) become **tappable toggle filters**
- Tap a card → highlights it (fills with urgency color, white text), filters list
- Tap same card again → deselects, shows all parts
- Cards always show **global** counts (from unfiltered data)
- Section header changes contextually: "3 critical parts" / "60 parts"

### 2. Per-Location Data (Prompts 23D, 23E)

**New tables:**
- `location_stock_targets` — per-location MIN/TARGET/MAX overrides + per-location forecast data + `part_category` (common/critical) + `do_not_restock` flag
- `forecast_settings` — per location-type defaults (shop vs truck) + per individual location overrides
- `location_free_space` — 1-10 physical space rating per location, updated monthly

**Two calculation units (never mixed):**
- **Shop:** ADU = Average Daily Usage (parts/day, averaged over `adu_lookback_days`, default 365)
- **Truck:** APW = Average Per Window (parts per X-week window, configurable 1-6 weeks per individual truck)

**Per-location-type settings with per-truck overrides:**
- Shop defaults: Common MIN ×3.5d, TARGET ×14d (2 weeks), MAX ×21d (3 weeks)
- Truck defaults: Common MIN ×1wk, TARGET ×2wk, MAX ×3wk
- Critical parts have separate (higher) multipliers at each location type
- Each individual truck can override the truck defaults (different work = different needs)

**Part categories per location:**
- **Common:** Easy to get, used often, shorter buffers
- **Critical:** Needed in a pinch, hardly used, longer buffers, never let it run out
- Same part can be Common at shop, Critical on a truck
- Common unused 6 months → suggest marking Critical or removing
- Critical used consistently 4 of 6 months → suggest switching to Common

**Truck philosophy:** Small quantity, large variety. Truck stock is emergency backup — if you're regularly pulling from it for jobs (3+/year), the shop should stock it instead.

### 3. Target Recommendations (Prompt 23F)

**New table:** `target_recommendations`

**Engine rules:**
- Recommends all 3 values: MIN, TARGET, MAX (not just target)
- **Max 1 recommendation per day** — picks the most impactful candidate
- **Show up to 14 days** of recommendations in queue
- **60-day cooldown** per part+location after any recommendation (approved, dismissed, or ignored)
- **90 days minimum data** at that location before generating any recommendation
- **Validation:** MIN < TARGET < MAX always. MIN ≤ current inventory. MAX ≥ current inventory.
- Also recommends category changes (Common↔Critical) and add/remove part from location

**Lifecycle rules:**
- `do_not_restock` flag: any part at any location can be set to stop restocking — depletes naturally, then removed
- Parts on any truck/trailer can NEVER be recommended for removal from shop
- If truck stock consumed for jobs 3+/year → recommend adding to shop (ordering pipeline is missing it)
- Top 5 removal and top 5 addition recommendations

**Dismiss always requires a reason.**

### 4. Location Picker UI (Prompt 23G)

- Horizontal chip bar inside the List: All | Shop | Truck [Name] | Trailer [Name]
- **All** (default) — shows weighted average of parts across all locations
- **Shop/Truck/Trailer** — shows that specific location's forecast data, stock levels, and health
- Truck locations only visible to the user assigned to that truck
- Recommendation toolbar button with badge count
- Recommendation cards with Approve / Dismiss (reason required) actions

### 5. Detail Panel Redesign (Prompt 23H)

When tapping a part, the detail sheet becomes a full editor (design modeled after the Categories page right-side editor panel — shows all relevant info with edit capability, not just read-only labels). Four sections:

**Section 1: Part Info (editable)**
- Name, code, category/brand (read-only), global MIN/TARGET/MAX (editable)
- Save button with MIN < TARGET < MAX validation

**Section 2: Stock Health Per Location**
- One row per location with stock
- Health bar: red (below MIN) → orange (below TARGET) → green (at TARGET) → yellow (above TARGET) → red (at MAX)
- CENTER marker at TARGET value
- Shows: location name, icon, current qty, MIN/TARGET/MAX, certainty %, usage rate

**Section 3: Forecast Metrics**
- ADU-30, ADU-90, trend indicator (up/down/stable)
- Days until low, suggested order qty
- Last recalculated timestamp

**Section 4: Actions**
- Add to Wishlist (placeholder — wired up during Orders review)
- View in Catalog (placeholder — navigation link)

### 6. Background Processing (Dashboard — future prompt)

- Forecast recalculation runs **once per day** automatically
- Part of a **background task dashboard card** showing all daily auto-tasks
- Groups: System tasks (shop computer) vs Your Device tasks
- Server freshness card: "Last Sync: X min ago", "Shop data as of: [timestamp]"
- Manual Recalculate button still exists for on-demand

### 7. Service Layer (Prompts 23A, 23D)

- `listForecastDataWithStock()` — global or filtered by location
- `listLocationStockTargets(partId:)` — all locations for a part with current stock + healthScore
- `getLocationStockTarget()` / `setLocationStockTarget()` — per-location CRUD
- `recalculateForecasts()` — global recalc, chains into per-location recalc
- `recalculateForecastsPerLocation()` — ADU + certainty per location
- `getForecastSettings()` / `saveForecastSettings()` — per-location-type settings
- `getFreeSpaceRating()` / `setFreeSpaceRating()` — 1-10 scale per location
- `generateDailyRecommendation()` — picks most impactful candidate, respects cooldown
- `approveRecommendation()` / `dismissRecommendation()` — with validation
- `listPendingRecommendations()` / `pendingRecommendationCount()`

---

## Prompt Chain

| Prompt | What | Status |
|--------|------|--------|
| 23A | Service layer cleanup: raw SQL → `PartsService`, platform guards, recalculate button, trend indicators | ✅ DONE |
| 23B | AI integration: `GetForecastDataTool`, page context notifications | ✅ DONE (context posting via NotificationCenter) |
| 23C | Stat cards as toggle filters, delete chip bar | ✅ DONE (3 tappable stat cards replace chip bar) |
| 23D | Per-location backbone: `location_stock_targets` migration + 4 service methods | ✅ DONE (migration 029 + service methods) |
| 23E | Forecast settings: `forecast_settings` + `location_free_space` migrations + seed data + service | ✅ DONE (ForecastSettingsSheet.swift built 12.6KB, wired into PartsForecastingPage as .forecastSettings sheet case — toolbar button + ADU/APW config form) |
| 23F | Target recommendation engine: `target_recommendations` migration + daily engine + approve/dismiss | ✅ DONE (migration 031 + engine + approve/dismiss with reason) |
| 23G | Location picker UI, recommendation filter + cards, approve/dismiss actions | ✅ DONE (location chips + recommendation cards) |
| 23H | Detail panel redesign: full part editor, stock health bars, editable MIN/TARGET/MAX | ✅ DONE (4 sections with health bars + validation) |

**Dependencies:** 23A → 23B (independent) → 23C (independent) → 23D → 23E → 23F → 23G → 23H

---

## Cross-References

- **Wishlist system:** Separate but feeds into Procurement Planner. See `inventory-intelligence-system.md` Part B.
- **Procurement Planner redesign:** Demand consolidation from 4 sources. See `inventory-intelligence-system.md` Part C.
- **Background task dashboard card:** See `inventory-intelligence-system.md` Part A5. Built during Dashboard page review.
- **Smart pull options:** During order creation. See `inventory-intelligence-system.md` Part C4. Built during Orders page review.
- **Movement suggestions:** Shop↔Truck↔Trailer. See `inventory-intelligence-system.md` Part E. Built during Warehouse page review.

---

*Design confirmed: 2026-03-21*
