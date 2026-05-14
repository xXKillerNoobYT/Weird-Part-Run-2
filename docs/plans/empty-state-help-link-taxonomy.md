# Empty-State Help-Link Taxonomy (UX Spec)

**Owner:** UXDesigner
**Issues:** GitHub #464, Paperclip WEI-1213, prior QA WEI-1201
**Status:** Approved convention — implementation review only
**Date:** 2026-05-13

---

## Problem

A static QA scan flagged 17 residual `EmptyStateView` / `ContentUnavailableView`
call sites that "lack help-link wiring" because they don't pass `helpLabel:` /
`helpAction:` parameters. The flagged sites are in Orders (3), Warehouse (13),
and Chat (1).

The scan applied a single rule: "every empty state must expose page help."
That rule is too broad. Not every empty state is a primary list state, and
duplicating the page-level toolbar Help button inside the empty card adds
visual noise without improving discoverability.

This spec defines the 4-category taxonomy and a per-site verdict for the 17
flagged residuals.

---

## Taxonomy

Empty states fall into 4 categories. Help-link behavior is determined by
category, not blanket rule.

### Category A — Primary list/grid empty states
**Rule:** The host page MUST have a toolbar `?` button that opens
`PageHelpSheet`. The empty state itself does NOT need a duplicate help link;
the toolbar Help is the canonical entry point.

**Examples:** `IOSJPOsPage` "No JPOs", `IOSPurchaseOrdersPage` "No POs",
`IOSEmployeesPage` "No Employees".

**Acceptance:** Page-level toolbar `?` present + `PageHelpSheet` populated
with `What This Page Does`, `How to Use It`, `Tips` sections.

### Category B — Wizard step inline guidance
**Rule:** The empty state's `description` text IS the guidance ("Tap the
button above to add your first shelf..."). No help link.

**Rationale:** The wizard itself is the guided experience. Adding a help link
would compete with the wizard's own progress affordance and introduce a
modal-on-modal pattern.

**Examples:** All `WarehouseWizardStep*`, `WizardStep*` empty states.

**Acceptance:** `description` text starts with an action verb that points to
the next step ("Tap...", "Create...", "Add...") and is unambiguous about WHERE
to act.

### Category C — Modal/picker sheet empty states
**Rule:** Copy must redirect to the source-of-truth page where the missing
data is created. No help link, but a deep-link button is encouraged when the
source page is one tap away.

**Examples:** `SupplierPickerSheet` "No Suppliers — Add suppliers in the
Parts section first", `CartManager` "Cart is Empty — Add parts or bins from
any list".

**Acceptance:** Description names the destination page explicitly
("...in the Parts section", "...from any list").

### Category D — Hard error / not-found states
**Rule:** Not an empty state. No help link. Use `ContentUnavailableView` with
a "Back" or "Retry" affordance.

**Examples:** `IOSJPODetailPage` "Movement Not Found", error-loaded states.

**Acceptance:** `systemImage` is `exclamationmark.triangle` (errors) or
`questionmark.circle` (not-found); copy explains what failed without offering
generic page help (which won't fix a missing record).

---

## Per-Site Verdict for the 17 Residuals

### Orders (3)

| Call site | Category | Verdict | Notes |
|---|---|---|---|
| `IOSJPODetailPage.swift` (Movement Not Found) | D | Exception | Hard not-found inside Movement subview; parent JPO Detail already has `?` toolbar Help. |
| `IOSUnifiedOrderPage.swift` | D | Exception | Deprecated stub redirecting to Job Orders → Create JPO. Page is retired, no help needed. |
| `SupplierPickerSheet.swift` | C | Exception | Modal picker; copy already redirects to Parts section. Optional enhancement: add deep-link "Open Parts → Suppliers" button. |

### Warehouse (13)

All 13 sites are wizard-step or cart-manager guidance (Category B/C).

| Call site | Category | Verdict |
|---|---|---|
| `CartManager.swift` (Cart is Empty) | C | Exception |
| `WarehouseOnboardingWizard.swift` (Complete Step 1 First) | B | Exception |
| `WarehouseWizardStep2.swift` (No Storage Units) | B | Exception |
| `WarehouseWizardStep3.swift` | B | Exception |
| `WarehouseWizardStep4.swift` | B | Exception |
| `WarehouseWizardStep5.swift` | B | Exception |
| `WarehouseWizardStep6.swift` | B | Exception |
| `WizardStepAreas.swift` | B | Exception |
| `WizardStepBins.swift` | B | Exception |
| `WizardStepPlacement.swift` (No Bins) | B | Exception |
| `WizardStepPlacement.swift` (No Areas) | B | Exception |
| `WizardStepShelves.swift` | B | Exception |
| `WizardStepZones.swift` | B | Exception |

### Chat (1)

| Call site | Category | Verdict | Notes |
|---|---|---|---|
| `IOSRFIListPage.swift` (No RFIs) | A | Already compliant | `IOSRFIListPage` already has toolbar `?` + `PageHelpSheet` (RFI Help). No change. |

---

## Net Result

**0 of 17 sites require code changes to wire `helpLabel` / `helpAction`.**
The static scanner's rule should be updated to recognize the 4-category
taxonomy instead of flagging every site without help-link parameters.

### Required follow-ups
1. **Implementation:** None required for the 17 residuals.
2. **Optional UX enhancement (separate ticket):** Add deep-link buttons to
   Category C modal pickers (e.g., `SupplierPickerSheet` → "Open Parts →
   Suppliers"). Low priority.
3. **Scanner update:** The QA scan that produced the WEI-1201 list should be
   updated to:
   - Skip files matching `*Wizard*.swift`, `*WizardStep*.swift`,
     `*PickerSheet.swift`, `CartManager.swift` (Categories B/C/D).
   - For Category A files, verify the host view has both an
     `EmptyStateView` and a toolbar `Button` whose label contains
     `questionmark.circle`, instead of inspecting `EmptyStateView`
     parameters.
4. **EmptyStateView API:** Do NOT add `helpLabel:` / `helpAction:`
   parameters. The page-level toolbar Help button is the canonical pattern;
   inline duplicates would dilute it.

---

## Acceptance Criteria for #464 Closure

- [x] All 17 residual sites classified by category (A/B/C/D).
- [x] Each site has a documented verdict (exception or compliant).
- [x] No code changes required — convention documented instead.
- [ ] WEI-1213 comment posted with this spec link.
- [ ] GitHub #464 closed with comment linking to this spec.
- [ ] Optional: ticket filed for Category C deep-link enhancements (low priority).
- [ ] Optional: ticket filed for QA scanner taxonomy update.
