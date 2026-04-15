# iOS Pricing Override Flow — Retroactive Plan

> **Status:** Adopted — retroactive plan written 2026-04-12 (plan-enforcer run 12)
> **GitHub Issue:** #133 (Plan Drift — PricingOverrideFlow.swift has no plan document)
> **Current file:** `Weird Parts IOS/Weird Parts IOS/Features/Parts/PricingOverrideFlow.swift` (616 lines)
> **Q&A decisions applied:** 2026-04-12 (dev-qa.md §PricingOverrideFlow — all 3 questions answered)

---

## What This Does (Plain English)

A multi-step admin sheet that lets an authorized user set a price at any hierarchy level
(Category / Style / Type / Brand) and push that price down to all affected parts.
If existing per-item price overrides conflict, the flow presents them one-at-a-time so
the user can decide Replace or Keep for each.

This is a "price sweep" capability — set once, propagate to many.

---

## Owner Decisions (Q&A 2026-04-12)

1. **Keep it** — officially adopted as a known feature (not speculative code to remove).
2. **Accessible from two places:**
   - **Pricing page** (`PartsPricingPage`) — already wired at line 592 ✅
   - **Category tree editor** (`CategoriesTreeView`) — still needs wiring (see Outstanding Work below)
3. **Tests required before broader use** — `resolveConflicts` step has no test coverage; must be covered before additional call sites are added.

---

## Current Implementation (as-built)

### File: `PricingOverrideFlow.swift`

**View:** `PricingTierSetSheet` — presented as a `.sheet` with a callback `onDone: () async -> Void`.

**State machine (6 steps):**
```
selectLevel → selectEntity → setPrice → preview → resolveConflicts → done
```

| Step | What Happens |
|------|-------------|
| `selectLevel` | User picks hierarchy level: Category / Style / Type / Brand |
| `selectEntity` | Loads matching entities (via `PartsService`); user picks one |
| `setPrice` | User enters markup %, margin %, or fixed price |
| `preview` | Shows up to 15 random affected parts (read-only) |
| `resolveConflicts` | One-at-a-time: shows existing tier conflicts (Replace or Keep each) |
| `done` | Summary: N replaced, N kept; calls `onDone` callback |

**Hierarchy levels supported:**
- `.category` — sets price across all styles/types/colors under a category
- `.style` — sets price across all types/colors under a style
- `.type` — sets price across all colors under a part type
- `.brand` — sets price across all colors linked to a brand

**Conflict resolution:**
- Uses `PartsService.OverrideConflict` struct (existing tiers that would be overwritten)
- `conflictDecisions: [Int64: Bool]` — tierId → replace (true) or keep (false)
- User steps through each conflict individually with progress bar

**Error handling:**
- `saveError: String?` shown inline (non-silent failure)
- Service guard: `guard let service = appCore.partsService else { return }`
- No `?? 0` or `?? 1` user ID fallbacks — uses auth guard

---

## Call Sites

| File | Location | Status |
|------|----------|--------|
| `PartsPricingPage.swift` | Line 592 | ✅ Wired |
| `CategoriesTreeView.swift` | Lines 348 (category row) + 488 (type row) | ⚠️ Wired but INCOMPLETE — missing tests + permission guard (GitHub #229) |

---

## Outstanding Work

### 1. Test Coverage for `resolveConflicts` Step (REQUIRED — plan violation open)
- The conflict resolution step (`resolveConflicts` state + `applyWithConflictResolution`) has **zero tests**
- Tests must be added to cover: conflict detection, Replace decision, Keep decision, mixed decisions, service unavailable, timestamp validation
- Service layer: `PartsService.OverrideConflict` + `setPricingTier` (production bug fixed 2026-04-12 — missing `createdAt`/`updatedAt` now set)
- **GitHub #229 tracks this violation** — CategoriesTreeView was wired before tests were written
- **Plan-enforcer run 14 (2026-04-14):** Drift detected. Issue filed.

### 2. Permission Guard in CategoriesTreeView (REQUIRED — plan violation open)
- Context menus at lines 348 + 488 show "Set Pricing Override" to all users
- Must be gated by `edit_pricing` permission (Admin hat only)
- **GitHub #229 also tracks this**

### 3. Wire into CategoriesTreeView (PARTIALLY DONE — see above)
- Context menus wired for category rows (line 348) AND type rows (line 488)
- `PricingTierSetSheet` presented on both with `onDone: { loadColorPrices() }`
- Only visible to users with `edit_pricing` permission
- Implementation: Xcode prompt needed (write PE-046c or similar)

---

## Service Methods Used

All in `PartsService.swift`:
- `listCategories()` — for category picker
- `listStyles()` — for style picker
- `listTypes()` — for type picker
- `listBrands()` — for brand picker
- `setPricingTier(...)` — creates/replaces a pricing tier
- `getPricingTiers(entityType:entityId:)` — reads existing tiers for conflict detection
- `removePricingTier(id:)` — called when user chooses Replace
- `OverrideConflict` struct — conflict detection model

---

## Permissions

- Requires `edit_pricing` permission (Admin hat only by default)
- Sheet is currently presented unconditionally in `PartsPricingPage` — should add permission guard before wiring additional call sites

---

## Test Plan

| Scenario | Status |
|----------|--------|
| selectLevel → selectEntity flow completes | ✅ Manual only |
| setPrice applies to category → all colors affected | ✅ Manual only |
| Preview shows up to 15 parts | ✅ Manual only |
| No conflicts → done immediately | ❌ No automated test |
| 1 conflict → Replace → applied | ❌ No automated test |
| 1 conflict → Keep → preserved | ❌ No automated test |
| Mixed conflicts → correct split | ❌ No automated test |
| Service unavailable → error shown | ❌ No automated test |

**Required before broader use:** Add tests for all 6 conflict resolution scenarios above.

---

## Priority

Medium — feature is live on Pricing page. Blocked from additional wiring until:
1. `resolveConflicts` test coverage complete
2. `edit_pricing` permission guard verified

Xcode prompt for CategoriesTreeView wiring should reference this plan.
