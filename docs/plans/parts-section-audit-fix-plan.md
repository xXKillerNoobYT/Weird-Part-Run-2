# Parts Section — Full Audit & Fix Plan

## What This Does

The Parts area is the program's catalog backbone — managing the hierarchical taxonomy of parts (categories → styles → types → colors → brands → suppliers), per-location stock tracking, forecasting/recommendation logic, pricing cascade (cost / supplier / brand / job-override), part-number generation, search/filter UI, brand-supplier carry-status, supplier scoring/traceability/contacts, color-brand SKU mapping (PE-COLORS), and part-detail editing. ~8 iOS pages and 15 supporting components, backed by `PartsService.swift` (~6500 lines, 60+ public methods) which is the single largest service in the project.

## Why

Parts is the foundational data model: jobs, orders, warehouse moves, dispatches, scheduling — every other domain references parts. A bug in the parts catalog ripples through every workflow. Pricing correctness is revenue-critical (wrong cost = lost margin); FK-integrity matters for moves and orders; forecasting feeds inventory recommendations that drive reorder timing. Beyond data, the Parts UI is the most-touched surface in the program — operators search, filter, view, and edit parts dozens of times per day. So the area gets disproportionate attention: most-tested service (250+ tests), most plan files (6 specialized plans for sub-systems), most-graduated area (16 iters first rotation, baseline for all subsequent rotations).

## Plan-Family Index

The Parts area's design is spread across 6 specialized plans rather than one monolithic doc — too much surface area for a single file. Each plan covers a sub-system:

| Plan | Scope |
|------|-------|
| `parts-section-audit-fix-plan.md` (this file) | Cross-cutting audit + critical-fix tracker |
| `colors-parts-redesign.md` | PE-COLORS variants/SKU redesign (Phase 1 complete; Phase 2 UI #237-#240) |
| `ios-part-number-hierarchy.md` | Part-number generation rules (category/style/type/color/brand/supplier hierarchy) |
| `ios-brands-suppliers-editing.md` | Brand-supplier link UI + carry-status workflow |
| `ios-supplier-system.md` | Supplier scoring, traceability, contacts, communication bridge |
| `supplier-communication-bridge-plan.md` | Supplier comm channels (email/PDF/portal) |
| `inventory-intelligence-system.md` (lives outside parts/) | Forecasting backbone — referenced by parts forecasting pages |

For dev-pipeline-manager 9-section coverage: each sub-plan covers Test Plan + User Roles + Security + HIG within its scope. The aggregate-level What/Why is captured here.

## Context

Thorough audit of all 8 Parts pages, 15 supporting components, PartsService (6500+ lines), and PartsModels comparing built code against plan documents. Found critical backend bugs, unbuilt forecasting features (prompts 23B-23H still queued), pricing gaps, and 18+ silent error locations. User wants everything fixed: bugs, plan alignment, and deeper audit.

**Plans referenced:**
- `docs/plans/inventory-intelligence-system.md` — forecasting backbone, per-location intelligence
- `docs/plans/forecasting-page-redesign.md` — prompts 23A-23H spec
- `docs/plans/ios-pricing-ui.md` — cascade pricing, catalog price chips
- `docs/plans/ios-pricing-override-flow.md` — PricingOverrideFlow wiring
- `docs/plans/ios-catalog-page.md` — catalog search/filter/detail
- `docs/plans/ios-brands-suppliers-editing.md` — brand-supplier linking
- `docs/plans/ios-supplier-system.md` — scores, traceability, contacts

---

## Phase 1: Critical Backend Fixes

### 1A. BrandSupplierLink missing carryStatus (BLOCKING)
**File:** `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift`
- Add `public var carryStatus: String?` to `BrandSupplierLink` struct
- Add `case carryStatus = "carry_status"` to CodingKeys enum
- **Impact:** Without this, `getBrandSuppliersWithStatus()` and `updateBrandSupplierCarryStatus()` silently fail

### 1B. getHierarchy() ignores type_color_links
**File:** `core/Sources/WiredPartCore/Services/PartsService.swift` (~line 413-452)
- Current code builds color lists from `parts` table only
- Must also query `type_color_links` table to include colors explicitly linked to types (even if no parts exist yet)
- Merge both sources: colors from existing parts UNION colors from type_color_links

### 1C. Deep SQL/Schema Audit
- Audit ALL 212+ SQL queries in PartsService against actual migration schema
- Check for: wrong column names, missing columns, ambiguous table references (stock vs stock_entries)
- Document stock table strategy: clarify which is authoritative (stock vs stock_entries)
- Check all `try?` locations (18+ found) and replace with proper error propagation or user-facing error messages

**Files to audit:**
- `core/Sources/WiredPartCore/Services/PartsService.swift` (all SQL)
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` (all models vs migrations)
- Migrations 002, 016, 020, 025, 026, 027, 029, 030, 031, 065, 066, 067

---

## Phase 2: Forecasting Backbone (Prompts 23B-23H)

Per `forecasting-page-redesign.md` — only 23A is done. Build the rest:

### 2A. AI Integration (Prompt 23B)
**File:** `PartsForecastingPage.swift`
- Add `GetForecastDataTool` for AI panel
- Post `.forecastPageActive` / `.forecastPageInactive` notifications with context
- Wire AI filter commands via NotificationCenter

### 2B. Stat Cards as Toggle Filters (Prompt 23C)
**File:** `PartsForecastingPage.swift`
- **DELETE** the urgency filter chip bar (All/Critical/Warning/Healthy capsules)
- Replace with 3 tappable stat cards: Critical count, Warning count, Healthy count
- Tap card → fills with urgency color + white text, filters list
- Tap again → deselects, shows all
- Cards always show global counts (unfiltered data)
- Section header: "3 critical parts" / "60 parts" (contextual)

### 2C. Per-Location Backbone (Prompt 23D)
**Files:** New migration + PartsService
- Verify `location_stock_targets` table exists (Migration 029) — it does
- Verify `forecast_settings` table exists (Migration 030) — it does
- Add/verify service methods:
  - `listForecastDataWithStock()` — global or filtered by location
  - `listLocationStockTargets(partId:)` — all locations for a part with current stock + healthScore
  - `getLocationStockTarget()` / `setLocationStockTarget()` — per-location CRUD
  - `recalculateForecastsPerLocation()` — per-location ADU + certainty

### 2D. Forecast Settings & Free Space (Prompt 23E)
**Files:** PartsService + new UI
- Verify `location_free_space` table exists (check migrations)
- If missing: add migration for `location_free_space` table (1-10 scale per location)
- Service methods: `getForecastSettings()`, `saveForecastSettings()`, `getFreeSpaceRating()`, `setFreeSpaceRating()`
- Seed default settings for warehouse and truck location types

### 2E. Target Recommendation Engine (Prompt 23F)
**Files:** PartsService
- Verify `target_recommendations` table exists (Migration 031) — it does
- Build/verify recommendation engine rules:
  - Max 1 recommendation per day (picks most impactful)
  - Show up to 14 days in queue
  - 60-day cooldown per part+location
  - 90 days minimum data before generating
  - Validation: MIN < TARGET < MAX
  - Recommends all 3 values + category changes (Common↔Critical)
  - Dismiss always requires reason
- Service methods: `generateDailyRecommendation()`, `approveRecommendation()`, `dismissRecommendation()`, `listPendingRecommendations()`, `pendingRecommendationCount()`

### 2F. Location Picker UI (Prompt 23G)
**File:** `PartsForecastingPage.swift`
- Horizontal chip bar: All | Shop | Truck [Name] | Trailer [Name]
- "All" default → weighted average across locations
- Location-specific → that location's forecast data and stock levels
- Truck locations only visible to assigned user
- Recommendation toolbar button with badge count
- Recommendation cards with Approve / Dismiss (reason required)

### 2G. Detail Panel Rebuild (Prompt 23H)
**File:** `PartsForecastingPage.swift` (ForecastDetailSheet)
- **Section 1: Part Info (editable)** — name, code, category/brand (read-only), global MIN/TARGET/MAX (editable), Save button with validation
- **Section 2: Stock Health Per Location** — one row per location, health bar (red→orange→green→yellow→red), CENTER marker at TARGET, current qty, MIN/TARGET/MAX, certainty %, usage rate
- **Section 3: Forecast Metrics** — ADU-30, ADU-90, trend indicator, days until low, suggested order qty, last recalculated timestamp
- **Section 4: Actions** — Add to Wishlist (placeholder), View in Catalog (navigation link)

---

## Phase 3: Pricing Gaps

### 3A. Catalog Color Row Price Chips
**File:** `PartsCatalogPage.swift`
- Per `ios-pricing-ui.md` gap: color rows must show current effective price chip (e.g., "$4.25/ea")
- Tap price chip → inline edit or price edit sheet
- Type row shows default cost badge + "all colors inherit unless overridden"
- Supplier sub-section under color (if expanded): per-supplier cost

### 3B. Wire PricingOverrideFlow into CategoriesTreeView
**File:** `CategoriesTreeView.swift` + `PricingOverrideFlow.swift`
- Per `ios-pricing-override-flow.md`: "Still needs wiring into CategoriesTreeView"
- Add entry point from Categories tree to launch PricingOverrideFlow for selected Category/Style/Type/Brand
- Test the `resolveConflicts` step (noted as needing test coverage)

---

## Phase 4: Silent Error Cleanup

### 4A. Replace try? with proper error handling
**Files:** All 8 Parts pages + PartsService

Found 18+ locations using `try?` to silently swallow errors:
- `PartsCatalogPage.swift`: pricing mode defaults to "markup", warehouse locations default to empty
- `PartsPricingPage.swift`: pricing mode silently defaults, categories silently default to empty, stale threshold defaults to "90"
- `PartsForecastingPage.swift`: forecast context building silently defaults
- `PartsCompanionsPage.swift`: polling state silently defaults
- `PartsImportExportPage.swift`: import sleep + part lookup silently default
- `PartsSuppliersPage.swift`: context posting silently defaults

**Fix pattern:** Replace `try?` with `do/catch` that either:
1. Shows `loadError`/`actionError` to user, OR
2. Logs the error + uses fallback with documented reason

### 4B. Error message context mismatches
**File:** `PartsBrandsPage.swift`
- Line ~277: delete error shows "load brands" context
- Line ~783: supplier picker error shows "load brands" context
- Fix: use correct operation context in error messages

---

## Progress Log

### Session 1 (2026-04-12) — Phases 1, 2 (audit), 3, 4 Complete

**Phase 1 — Backend Fixes:**
- **5 bugs fixed:** #156 (carryStatus model), #157 (hierarchy type_color_links), #159 (catalog type_name), #160 (import duplicate detection), #161 (LocationStockTarget model)
- **1 non-bug confirmed:** #158 (stock vs stock_entries is by design)
- **Deep SQL audit complete:** 212+ queries checked, all column references verified

**Phase 2 — Forecasting Audit:**
- **Surprise finding:** Prompts 23B-23H were marked "Queued" but are LARGELY BUILT
- Stat cards, location picker, recommendations, detail panel with health bars — all implemented
- Updated plan docs + GitHub #68 to reflect reality
- Remaining gaps: forecast settings UI (#162), free space rating UI (#163), View in Catalog nav (fixed)

**Phase 3 — Pricing Gaps:**
- Catalog price chips: already built (cascade price chips on color rows)
- PricingOverrideFlow: wired into CategoriesTreeView via context menu on category + type rows

**Phase 4 — Error Handling:**
- **14 of 15 try? instances** replaced with proper do/catch in Parts pages
- **3 error context mismatches** fixed in BrandsPage
- Only remaining try? is harmless Task.sleep cancellation

**Housekeeping:**
- CLAUDE.md updated: GitHub Issues = Master Todo List section added
- 8 GitHub issues created total, 6 closed as fixed, 1 closed as not-a-bug, 2 new feature gaps filed

---

## Recommended Next Steps (Priority Order with Reasoning)

### Step 1: Phase 4 — try? Cleanup in Parts Pages (DO FIRST)
**Why first:** This is the fastest win with highest reliability impact. 18+ silent failures across 8 pages mean users hit "nothing happens" bugs constantly. Issue #121 tracks 198 instances across the whole app, but fixing the Parts subset now makes the Parts section production-ready sooner. Estimated: 1-2 hours.

### Step 2: Phase 2 — Forecasting Backbone (23B-23H)
**Why second:** This is the biggest gap between plan and implementation. Issue #68 has the full checklist — stat cards, location picker, per-location data, recommendation engine, full detail panel. This is 7 prompts of work (23B through 23H). The service layer methods mostly exist, but the UI needs significant rebuild. Estimated: 2-3 sessions.

### Step 3: Phase 3 — Pricing Gaps
**Why third:** Pricing works but is missing the catalog inline price chips and the PricingOverrideFlow wiring into CategoriesTreeView. These are user-facing polish items that complete the pricing story. Estimated: 1 session.

### Step 4: Broader Audit of Other Sections
**Why after Parts:** The same audit pattern (plan vs implementation comparison, SQL/schema check, try? cleanup) should be applied to Orders, Warehouse, Jobs, and Scheduling. Each section likely has similar model-migration drift and silent error patterns. The Parts audit methodology is now proven and can be templated.

---

## Phase 5: Deferred Items (NOT in this plan — noted for future)

- APW calculation unit for truck/trailer forecasting (user chose to defer)
- Wishlist system (Part B of Inventory Intelligence — separate plan)
- Procurement Planner redesign (Part C — separate plan)
- Movement suggestions (Part E — separate plan)
- Background task dashboard card (build during Dashboard review)
- Supplier performance score auto-recalculation
- Part traceability UI

---

## Verification Plan

### After Phase 1:
- Build project — zero compile errors
- Run all 1217+ tests — zero failures
- Test carry status toggle on Brands page (create brand → link supplier → toggle carry status)
- Test hierarchy tree (verify colors shown match type_color_links)

### After Phase 2:
- Forecasting page loads with stat cards (not chips)
- Tap stat card → filters list → tap again → shows all
- Location picker shows all locations
- Select specific location → data changes to per-location
- Tap part → full detail panel with 4 sections
- Health bars render correctly (red/orange/green/yellow/red zones)
- Recommendations show with badge count
- Approve/dismiss recommendations with required reason

### After Phase 3:
- Catalog color rows show price chips
- Tap price chip → edit sheet opens
- Categories tree has entry point to PricingOverrideFlow

### After Phase 4:
- No more `try?` in Parts pages (grep verification)
- All error paths show user-facing feedback
- Error messages reference correct operations

### Final:
- Full test suite passes (1217+)
- Zero compile warnings in Parts files
- Manual walkthrough of all 8 Parts pages on iPhone + iPad layouts
