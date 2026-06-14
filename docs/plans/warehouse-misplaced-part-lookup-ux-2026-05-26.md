# Warehouse Misplaced-Part Lookup UX Spec

Issue: WEI-1998
Date: 2026-05-26
Owner: UXDesigner

## Problem

`IOSAuditPage` has a beta-safe guard for the misplaced-part sheet, but quick logging cannot be re-enabled until the user selects real records for `partId` and `foundAtAreaId`. The current picker-only sheet is not safe enough because it is limited to the active audit queue. A warehouse worker can find a misplaced part that is not currently in the audit queue or at the current walking-path stop.

UX risk: the wrong default would create audit noise or hide the recovery path. This flow must bias toward explicit selection, visible confirmation, and reversible error recovery.

## Entry Points

- `+ Found Misplaced Part` from the audit overview opens an empty lookup flow.
- `Report Issue` from a counted item opens the sheet with that part and area preselected, but still editable.
- `Report Count` / `Report Issue` from a walking-path stop opens with `foundAtAreaId` preselected and part empty.
- Future scan entry should route into the same sheet after resolving a QR/barcode to a part or area candidate.

## Sheet Structure

Use one `NavigationStack` sheet with three visible sections in this order.

1. `Part found`
   - Search field: `Scan or search part`
   - Results rows show part name, part code/SKU, color or brand if available, and total stock when available.
   - Selected row becomes a compact selected-part summary with `Change` action.
   - Do not auto-select the first result from a general search.

2. `Found at`
   - Primary control: scan area/bin QR, then resolve to `warehouse_storage_areas.id`.
   - Fallback control: searchable location picker.
   - Row label should use `full_location_code` when available, falling back to unit / level / area.
   - If launched from a walking-path stop or count item, preselect that area and show it as editable.

3. `Expected home`
   - Default to the selected part's home assignment when exactly one home assignment exists.
   - If multiple assignments exist, show them as radio rows with `Home` badge on home rows.
   - If none exists, default to `Sort later`; do not block save.
   - Include `Sort later` as the first option so a worker can log safely without guessing.

## Required Fields

Save is enabled only when:

- A non-deleted part has been selected.
- A non-deleted found-at area has been selected.
- Quantity is between `1...999`.
- Current user and warehouse service are available.

Optional:

- `homeAreaId`, nullable when the user chooses `Sort later`.
- Resolution action, default `sort_later`.

## Validation And Feedback

- Disabled save text state: keep the button disabled until required fields are present. VoiceOver hint should name the missing field.
- Inline validation:
  - No part: `Select the part you found.`
  - No found-at area: `Select where you found it.`
  - Quantity outside range: `Quantity must be at least 1.`
  - Part lookup failed: `Part lookup failed. Try again or scan the label.`
  - Area lookup failed: `Location lookup failed. Try again or choose from the list.`
- Save progress: replace `Save` with a spinner and disable all inputs.
- Save success: dismiss the sheet, refresh audit data, and show the existing audit page feedback path if available.
- Save failure: keep the user's selections intact and show the service error inline above the toolbar.

## Empty And Error States

- Empty query: show recent/contextual candidates only:
  - preselected count item if present,
  - parts in current walking-path area,
  - low-confidence audit queue candidates.
- No part results: `No matching parts` with secondary text `Check the label or scan the part QR.`
- No locations: `No warehouse locations found` with secondary text `Set up storage areas before logging misplaced parts.`
- Deleted/stale result selected: clear selection and show `That part or location is no longer available. Search again.`
- Offline/local database unavailable: keep the current beta-safe blocked state and do not call `logMisplacedPart`.

## Mobile Interaction Details

- Search and scan controls must be reachable without scrolling at sheet open.
- Use `.presentationDetents([.medium, .large])`; expand to large when search is focused.
- Keep tap targets at least 44 pt.
- Quantity should use a stepper plus a numeric text field for faster correction.
- Keyboard should dismiss interactively; dirty selections should use `interactiveDismissDisabled(isSaving)` and should not block cancel when not saving.
- Dynamic Type: selected summaries wrap to two lines before truncating codes.
- Accessibility: scan buttons need explicit labels, icons are decorative, and selected rows expose `Selected` state.

## Engineering Wiring

Implementation should stay in the iOS layer and reuse existing services before adding new backend behavior:

- Use `PartsService.searchParts(query:limit:)` for part lookup and `PartsService.getPart(id:)` when resolving a scanned part ID.
- Use `WarehouseService.getPartAssignments(partId:)` for home-location suggestions.
- Add or expose a small active-area lookup if needed; current code only has `listAreasForLevel(levelId:)`, so the sheet may need a helper that returns active areas with `id`, `fullLocationCode`, unit, level, and area label.
- Preserve the existing `WarehouseService.logMisplacedPart(partId:foundAtAreaId:homeAreaId:qtyFound:foundBy:)` call shape.
- Do not send placeholder IDs. `0`, negative IDs, and nil required IDs must never reach `logMisplacedPart`.

## Acceptance Criteria

- From each entry point, save remains disabled until a real part and real found-at area are selected.
- A part outside the current audit queue can be searched, selected, and logged.
- A found-at area outside the current audit queue can be searched or scanned and logged.
- Home location is suggested from assignments and can be left as `Sort later`.
- Search empty, no-results, lookup-error, save-error, and service-unavailable states are visible and recoverable.
- Mobile sheet works at compact width with no clipped primary controls.
- Regression tests prove `partId=0` and `foundAtAreaId=0` are not submitted from the sheet.
- Targeted service/UI tests cover successful quick log, missing part, missing area, no search results, and save failure.
