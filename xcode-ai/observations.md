# WiredPart iOS — Observations & Progress Log

## Initial Audit: 2026-03-18

**180+ issues** across ~160 Swift files. Backend/service layer is solid. Issues are in the UI layer: missing actions, swallowed errors, stubs, sheet conflicts.

### Systemic Patterns Found

1. "Catch and Forget" — ~25 catch blocks print to console only
2. "Guard and Abandon" — ~10 guard-let-else-return leave infinite spinners
3. "Read-Only Pages" — ~30 pages missing create/edit/delete
4. "no such table" Suppression — ~15 files silently eat errors
5. Multiple `.sheet` on one view — CategoriesEditorPanel (7), IOSMainView (5+)
6. Fake Sync — SyncWaitingView, IOSSyncManager simulate without working
7. Duplicate utilities — formatDate, formatCurrency copy-pasted 12+ times

---

## Fix Log

### Prompt 01 — Sheet/Popup Dismissal (DONE - 2026-03-18)

- 7 files fixed: CategoriesEditorPanel, CategoriesTreeView, IOSMainView, PartsCatalogPage, PartsSuppliersPage, PartsBrandsPage, PartsCompanionsPage → single `.sheet(item:)` enum
- 3 files fixed: IOSClockPage, LaborPage, IOSVehicleDetailPage → `.onChange` data reload
- 1 supporting: TypeBrandColorSection binding → closure pattern
- 6 files already correct — no changes needed
- Build: SUCCESS

### Prompt 02 — Error Visibility (DONE - 2026-03-18)

- 19 files fixed: Dashboard (2), Jobs (3), Parts (6, prior session), Warehouse (1), Scheduling (2), Tools (2), Reports (4), Settings (1)
- Consistent pattern: `loadError` state + catch sets it + guard clears isLoading + `ContentUnavailableView` error branch
- "Catch and Forget" pattern now eliminated across the codebase
- Build: SUCCESS
### Prompt 03 — Infinite Spinners (DONE - 2026-03-18)

- 6 files fixed: IOSEmployeeDetailPage, IOSToolRegistryPage, IOSToolCheckoutsPage, IOSToolMaintenancePage, IOSToolAdminPage, IOSSpendingPage
- 3 already fixed by Prompt 02: IOSToolsDashboardPage, IOSProfitabilityPage, IOSDailyReportsSummaryPage
- "Guard and Abandon" pattern now eliminated
- Build: SUCCESS
### Prompt 04 — Stub Sync & Placeholders (PENDING)
### Prompt 05 — AppCore Safety (PENDING)
### Prompt 06-08 — Missing CRUD (PENDING)
### Prompt 09 — Security Hardening (PENDING)
### Prompt 10 — Service Layer Bugs (PENDING)
### Prompt 11A-C — Brand-Supplier Linking (PENDING)
### Prompt 12A-F — Dashboard Hub (PENDING)

---

## What Worked Well

- Architecture: AppCore → Services → GRDB is solid
- Design system exists (DS tokens, styles, components)
- Navigation routing comprehensive with legacy redirects
- Permission gating infrastructure in place
- ErrorStateView and EmptyStateView components exist (just underused)
- QR auto-fill pipeline already built in core package
- Sync infrastructure exists in core (just not wired to iOS UI)
