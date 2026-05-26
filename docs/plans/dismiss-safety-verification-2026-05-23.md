# Dismiss-safety verification — WEI-2025 (2026-05-23)

Source issue: WEI-2025
Scope: `.sheet` / form-like unsaved-state audit for Tools, Fleet, Reports, Warehouse, Orders, Settings.

## Canonical checklist used

For each sheet-like presentation:

1. Identify the sheet purpose from the `.sheet` body or sheet view.
2. Classify as one of:
   - Read-only/help/share/scanner: no persisted user draft; may intentionally dismiss.
   - Action flow: selection/scan/action state is either immediately applied, recoverable from the parent page, or protected during in-flight work.
   - Form/edit flow: local user input can be lost; must block swipe dismiss when dirty/saving and Cancel must confirm discard or be intentionally safe.
3. Confirm each form/action sheet either:
   - Uses `interactiveDismissDisabled` directly,
   - Uses a guarded form wrapper/modifier, or
   - Is documented as a false positive because there is no unsaved user work.

## Static scan summary

Command pattern used:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path('Weird Parts IOS/Weird Parts IOS/Features')
for area in ['Tools','Fleet','Reports','Warehouse','Orders','Settings']:
    for p in sorted((root/area).rglob('*.swift')):
        text = p.read_text(errors='ignore')
        if '.sheet' in text:
            print(area, p.relative_to(root), text.count('.sheet'), text.count('interactiveDismissDisabled'))
PY
```

Target-area findings before this patch:

- Tools: `IOSToolDetailPage` sheet content already has local guards; unguarded Tools sheets are scanner/help/label-print surfaces with no draft text.
- Fleet: most list pages present read-only help sheets; vehicle/trailer/driver/inspection form sheets had save-only protection but not dirty-input discard confirmation.
- Reports: sheets are help/share/export surfaces. Report filters live on the page, not in the sheet, and are not lost by sheet dismissal.
- Warehouse: wizard/action sheets mostly already guard saving/moving; scanner/help/detail sheets are read-only or recoverable. Existing receiving quantity flow is documented as auto-save/no discard.
- Orders: purchase order/JPO/wishlist/return sheets already guard saving or require confirmation for destructive/cancel actions; scanners/help are false positives.
- Settings: several form pages have local dirty guards (`CompanyProfilesPage`, `IOSClockOutQuestionsPage`, `IOSReportTemplatesPage`); the rest of detected `.sheet` occurrences are help/preview/export flows or page-level forms.

## Code changes made

Added shared dismiss-safety helper:

- `Weird Parts IOS/Weird Parts IOS/Shared/DismissSafety.swift`
  - `DismissSafety.cancelOrConfirm(...)`
  - `.dismissSafety(isDirty:isSaving:showDiscardConfirmation:onDiscard:)`

Updated shared wrapper:

- `Shared/FormSheet.swift`
  - Added optional `isDirty` input.
  - Swipe dismiss now blocks while dirty or saving.
  - Default Cancel path confirms before discarding dirty input.

Hardened Fleet form/action sheets found by the scan:

- `Features/Fleet/IOSCreateVehicleSheet.swift`
  - Dirty detection includes all create-vehicle fields.
  - Swipe dismiss blocks while dirty/saving.
  - Cancel confirms discard when dirty.
- `Features/Fleet/IOSCreateTrailerSheet.swift`
  - Dirty detection includes trailer number/type/notes.
  - Swipe dismiss blocks while dirty/saving.
  - Cancel confirms discard when dirty.
- `Features/Fleet/IOSAssignDriverSheet.swift`
  - Dirty detection includes selected driver, assignment type, and take-home flag.
  - Swipe dismiss blocks while dirty/saving.
  - Cancel confirms discard when dirty.
- `Features/Fleet/PreTripInspectionView.swift`
  - Dirty detection includes odometer, fuel level, general notes, checklist statuses, and checklist notes.
  - Swipe dismiss blocks while dirty/saving.
  - Cancel confirms discard when dirty.

## False positives documented

- `PageHelpSheet` and help-only `NavigationStack` sheets: read-only educational content, no unsaved user work.
- `QRScanSheet` scanner sheets: scan result is immediately applied to parent state or dismissed; no typed draft inside scanner is discarded.
- `ReportShareSheet` / export share sheets: generated artifact URL is owned by the parent/exporter; sheet dismissal does not erase user input.
- Warehouse receiving quantities: existing code comments document auto-save behavior, so dismissal is intentionally safe.
- Page-level filters/search/pickers detected by file-level scan are not sheet-local unsaved drafts.

## Verification performed

- `swiftc -parse` on the new/changed Swift files passed.
- `git diff --check` passed.
- Branch hygiene preflight:
  - `git fetch --prune origin` performed.
  - Remote branches after prune: 57 (still above soft cap 20; no new branch cleanup attempted in this UX patch).
  - Open PRs at work start: 0.
  - Work was done in isolated worktree `/private/tmp/wei-2025-dismiss-safety-sheets` on branch `WEI-2025-dismiss-safety-sheets`, based on `origin/main`, to avoid the divergent primary `main` worktree.

## Remaining notes

The static scan still lists many `.sheet` sites because read-only help sheets are intentionally unguarded. New form sheets should use `DismissSafety` or `FormSheet(isDirty:)` rather than save-only `interactiveDismissDisabled(isSaving)`.
