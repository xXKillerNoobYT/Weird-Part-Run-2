# 31C — Warehouse Locations: Service Layer + Action Buttons

> **Plan:** `docs/plans/ios-warehouse-pages.md`

## Instructions

Read the file first, then fix all issues. When done, wait for user confirmation.

## Context

The locations page imports GRDB and uses raw SQL. The location detail sheet is read-only with no action buttons. Has platform guard.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseLocationsPage.swift`

## Task

1. **Remove `import GRDB`** — replace all raw SQL with WarehouseService method calls
2. **Remove `#if os(iOS)` platform guard**
3. **Add action buttons to LocationDetailSheet** — the detail sheet currently only shows parts. Add:
   - [Transfer From Here] — opens movement wizard with this location pre-selected as source
   - [Start Audit] — opens audit setup for this specific location/zone
   - [View in Inventory Grid] — navigates to inventory grid filtered to this location
4. **Replace ContentUnavailableView with ErrorStateView** for consistency
5. **Add empty state guidance** — "No stock at this location. Use the Movement Wizard to transfer parts here."

## Success Criteria

- [ ] `import GRDB` removed
- [ ] Platform guard removed
- [ ] Location detail sheet has Transfer, Audit, View Grid action buttons
- [ ] ErrorStateView for errors (not ContentUnavailableView)
- [ ] Empty state with guidance
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 31D.**
