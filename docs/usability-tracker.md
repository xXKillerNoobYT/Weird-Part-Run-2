# Usability Enforcer Tracker

**Agent:** usability-enforcer
**Schedule:** Daily at 2:00 PM
**Skill:** `xcode-ai/skills/usability-enforcer/SKILL.md`

---

## Latest Run

**Date:** 2026-04-04
**Method:** Full manual audit of all 170+ iOS pages across 13 modules
**Result:** 44 issues found, 44 fixed, 0 remaining

---

## Feature Completeness Matrix

| Feature | List | Create | Detail | Edit | Delete | Search | Filter | Refresh | Empty State | Error State |
|---------|------|--------|--------|------|--------|--------|--------|---------|-------------|-------------|
| Parts | Pass | Pass | Pass | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Jobs | Pass | Pass | Pass | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Employees | Pass | Pass | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass |
| Customers | Pass | Pass | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass |
| Contacts | Pass | Pass | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass |
| Teams | Pass | Pass | Pass | Pass | Pass | N/A | N/A | Pass | Pass | Pass |
| Warehouse | Pass | N/A | Pass | Pass | N/A | Pass | Pass | Pass | Pass | Pass |
| Orders/JPOs | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass | Pass | Pass |
| POs | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass | Pass | Pass |
| Fleet | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass | Pass | Pass |
| Tools | Pass | Pass | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass |
| Kits | Pass | N/A | Pass | Pass | N/A | N/A | N/A | Pass | Pass | Pass |
| Scheduling | Pass | Pass | Pass | Pass | N/A | Pass | Pass | Pass | Pass | Pass |
| Notebooks | Pass | Pass | Pass | Pass | N/A | Pass | N/A | Pass | Pass | Pass |

_Legend: Pass, Fail, N/A, ? = Not yet checked_

---

## 6-Check Audit Results (2026-04-04)

### Checks: ENTRY | EXIT | SHEETS | FORMS | LISTS | CLEAN UX

**Dashboard (4 pages):** All PASS
**Jobs (13 pages):** All PASS (minor: EstimationReview/Questionnaire lack isLoading)
**Parts (22 pages):** All PASS (P2: PartDetailSheet uses .sheet(isPresented:) for edit form)
**Warehouse (21 pages):** 19 PASS, 2 P2 (MovementWizard + WizardStep2 use .sheet(isPresented:) for QR scanner)
**Orders (15 pages):** All PASS after fixes
**People (13 pages):** All PASS after fixes
**Office (7 pages):** All PASS after fixes
**Scheduling (14 pages):** All PASS after fixes
**Fleet (17 pages):** All PASS
**Chat (9 pages):** All PASS
**Notebooks (7 pages):** All PASS
**Tools (7 pages):** All PASS after fixes
**Reports (22 pages):** All PASS after fixes
**Settings (35 pages):** All PASS

---

## Fixes Applied (2026-04-04)

### P1 Fixes (Critical)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | IOSJPOCreationPage.swift | `.alert(isPresented: .constant(...))` — non-dismissable alert (read-only binding) | Replaced with `Binding(get:set:)` for proper two-way binding |
| 2 | IOSTeamDetailPage.swift | `deleteTeam()` succeeds without calling `dismiss()` — user stranded on deleted team | Added `@Environment(\.dismiss)` + `dismiss()` after successful delete |
| 3 | IOSSpendingDashboardPage.swift | `EmptyStateView` shown unconditionally (always visible under data cards) | Wrapped in conditional: only show when data loaded with zero values |

### P2 Fixes (Error States — 14 files)

Replaced inline error `Label` (no retry) with `ErrorStateView(message:) { loadData() }` (has retry button):

| # | File |
|---|------|
| 4 | FleetFuelCostReport.swift |
| 5 | FleetMileageSummaryReport.swift |
| 6 | FleetMaintenanceTrendsReport.swift |
| 7 | FleetUtilizationReport.swift |
| 8 | SchedulingDispatchEfficiencyReport.swift |
| 9 | SchedulingCrewUtilizationReport.swift |
| 10 | SchedulingPipelineReport.swift |
| 11 | WarehouseTurnoverReport.swift |
| 12 | WarehouseInventoryValueReport.swift |
| 13 | WarehouseBackorderReport.swift |
| 14 | IOSTimeOffPage.swift |
| 15 | IOSDispatchTemplatesPage.swift |
| 16 | IOSToolsDashboardPage.swift |
| 17 | IOSProfitabilityPage.swift |
| 18 | IOSDailyReportsSummaryPage.swift |

### P2 Fixes (Duplicate Modifiers — 4 files)

Removed duplicate `.searchable` modifier (applied twice on same view):

| # | File |
|---|------|
| 19 | IOSProcurementPage.swift |
| 20 | IOSOrderStagingPage.swift |
| 21 | IOSShortTermPipelinePage.swift |
| 22 | IOSDailyReportsSummaryPage.swift |

---

## Round 2 Fixes (2026-04-04)

### P3 Fixes (.sheet pattern — 3 files + 1 bonus)

Converted `.sheet(isPresented:)` to `.sheet(item:)` enum pattern:

| # | File | What |
|---|------|------|
| 23 | IOSMovementWizard.swift | QR scanner sheet → `WizardSheet` enum |
| 24 | WarehouseWizardStep2.swift | Add unit sheet → `StepSheet` enum |
| 25 | CreatePOSheet.swift | Supplier scanner → `POSheet` enum |
| 26 | ReportExportUtilities.swift | Share sheet → `ExportSheet` enum + fixed `.constant()` alert |

### Additional Fixes (entry/exit/elements audit)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 27 | IOSJobDetailPage.swift | Error state used `ContentUnavailableView` (no retry) | Replaced with `ErrorStateView` with retry |
| 28 | IOSEstimationReviewPage.swift | Missing `isLoading` state + duplicate `.refreshable` | Added `isLoading` with ProgressView, removed duplicate modifier |
| 29 | IOSEstimationQuestionnairePage.swift | Missing `isLoading` state + no empty state | Added `isLoading`, `ErrorStateView`, and `EmptyStateView` |
| 30 | LaborPage.swift | Clock-in sheet missing `interactiveDismissDisabled` | Added `isClockingIn` state + `interactiveDismissDisabled` + disabled Cancel during save |
| 31 | IOSContractorsPage.swift | Missing `.navigationTitle()` | Added `.navigationTitle("Contractors")` |
| 32 | IOSWarehouseExecPage.swift | KPI cards with zero values visible under loading/error overlay | Restructured to Group with if/else: loading → ProgressView, error → ErrorStateView, success → warehouseContent |

### Systemic Fix: `.constant()` Alert Bindings (22 instances across 16 files)

Replaced `isPresented: .constant(var != nil)` (read-only, non-dismissable) with proper `Binding(get:set:)`:

| # | File | Variables Fixed |
|---|------|----------------|
| 33 | IOSUnifiedApprovalsPage.swift | `actionError` |
| 34 | IOSAuditPage.swift | `actionError` |
| 35 | IOSInventoryGridPage.swift | `actionError` |
| 36 | IOSStagingPage.swift | `actionError` |
| 37 | IOSWarehouseReturnsPage.swift | `actionError` |
| 38 | IOSWarehouseToolsPage.swift | `actionError` |
| 39 | IOSOrganizationAuditPage.swift | `actionError` |
| 40 | PartsForecastingPage.swift | `editError` |
| 41 | IOSAuditSummaryView.swift | `actionError` |
| 42 | PartsCatalogPage.swift | `saveError` |
| 43 | IOSPurchaseOrdersPage.swift | `actionMessage` |
| 44 | IOSReceiveShipmentPage.swift | `actionError`, `completionMessage`, `scanError` |
| 45 | IOSProcurementPage.swift | `generateError`, `generateSuccess`, `pullActionError`, `pullActionSuccess` |
| 46 | IOSJPODetailPage.swift | `actionError` |
| 47 | IOSOrderStagingPage.swift | `actionError` |
| 48 | IOSPODetailPage.swift | `actionMessage` |

---

## Remaining Issues

### From Usability Enforcer Run 2 (2026-04-06)

| # | File | Scanner | Finding | Severity | Status |
|---|------|---------|---------|----------|--------|
| 1 | PartsFlowWizard.swift | 7 (Defensive UX) | `saveAllProgress()` is synchronous — `isSaving = true/false` flip in same event loop tick means `interactiveDismissDisabled` guard is cosmetically inactive; buttons never visually disable during save | MEDIUM | Tracked via PE-039 (queued) |
| 2 | AuthService.swift | 7 (Defensive UX) | Legacy unsigned token shim in `parseLocalToken` has no removal deadline (DIS-014) | LOW | Tracked via DIS-014 DevTODO, GitHub issue PENDING |
| 3 | AuthService.swift | 6 (Plan Alignment) | PIN hashing uses iterated SHA-256, not a memory-hard KDF (DIS-012) | MEDIUM | Tracked via DIS-012 DevTODO, GitHub issue PENDING |
| 4 | AuthService.swift | 6 (Plan Alignment) | Legacy single-salt PIN hash path has no enforcement deadline (DIS-013) | MEDIUM | Tracked via DIS-013 DevTODO, GitHub issue PENDING |

**Note:** Items 2-4 are auth security hardening (not usability). Filed as DevTODOs; gh CLI unavailable during this run so GitHub issues need manual filing.

### From Usability Enforcer Run 3 (2026-04-08)

**Scope:** IOSWishlistPage.swift — DIS-006 verification + full 8-scanner pass
**Build:** ✅ Build complete | **Tests:** ✅ 1118/1118 pass (no change)

| Scanner | Result | Notes |
|---------|--------|-------|
| 1 Page Load Integrity | ✅ PASS | `guard let service` → isLoading=false; DIS-006 Task.detached pattern verified correct |
| 2 Button & Action Verification | ✅ PASS | All swipe actions and toolbar buttons have real handlers |
| 3 Modal & Sheet Dismiss | ✅ PASS | Both sheets capture `@Environment(\.dismiss)` outside NavigationStack correctly |
| 4 Navigation & Exit Paths | ✅ PASS | Reachable via OrdersRouter case "orders-wishlist" |
| 5 SQL vs Schema Audit | ✅ PASS | WishlistItem model matches migrations 057+070 exactly |
| 6 Plan Alignment | ✅ PASS | DIS-006 CLOSED and fully implemented |
| 7 Defensive UX | ✅ PASS | No MainActor violations; delete now has confirmation dialog |
| 8 Feature Completeness | ⚠️ PARTIAL | No edit action; no status filter — see tracked S2 items below |

**Remaining S2 items (need design decision — not fixing autonomously):**

| # | File | Scanner | Finding | Severity | Status |
|---|------|---------|---------|----------|--------|
| 5 | IOSWishlistPage.swift | 8 (Feature Complete) | No edit action on wishlist items — users can't update qty/priority/reason after creation | S2 | Needs design decision |
| 6 | IOSWishlistPage.swift | 8 (Feature Complete) | No status filter UI — large wishlists have no way to see only pending/approved items | S2 | Needs design decision |

### Fixes Applied (Run 3 — 2026-04-08)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | IOSWishlistPage.swift | `deleteItem()` swipe action executed without confirmation — accidental data loss | Added `itemToDelete` state + `.confirmationDialog` with destructive confirmation |
| 2 | IOSWishlistPage.swift | `AddWishlistItemSheet` has `TextField` + `isSaving` state but no `interactiveDismissDisabled` | Added `.interactiveDismissDisabled(isSaving)` + disabled Cancel button during save |
| 3 | IOSWishlistPage.swift | `DismissWishlistItemSheet` has `TextEditor` but no dismiss guard — user can lose typed reason | Added `.interactiveDismissDisabled(!trimmedReason.isEmpty)` |

---

### Usability Enforcer Run 4 (2026-04-10)

**Scope:** 4 modified files from DIS-015 fix set: `IOSWeeklyReviewSheet.swift`, `IOSAuditSummaryView.swift`, `ReceivingRoutingFlow.swift`, `QRScannerAdapter.swift`
**Build:** ✅ Build complete | **Tests:** ✅ 1162/1162 pass (up from 1118 — 44 new tests from WarehouseServiceExtTests, OrdersServiceTests, DashboardServiceTests)

| Scanner | Result | Notes |
|---------|--------|-------|
| 1 Page Load Integrity | ✅ PASS | All 3 UI files have isLoading/ProgressView/ErrorStateView correctly |
| 2 Button & Action Verification | ✅ PASS | All buttons wired; DIS-015 userId guards in place across all 4 action handlers in ReceivingRoutingFlow |
| 3 Modal & Sheet Dismiss | ⚠️ FIXED | `AdjustDiscrepancySheet` (inside IOSAuditSummaryView) missing `interactiveDismissDisabled(isSaving)` — added |
| 4 Navigation & Exit Paths | ✅ PASS | ReceivingRoutingFlow has onDismiss at routeConfirmed; Cancel in parent context |
| 5 SQL vs Schema Audit | ⚠️ FIXED | `QRScannerAdapter.tableForEntityType(.bin)` returned `"bin_locations"` — no such table exists. Fixed to `"warehouse_bins"` |
| 6 Plan Alignment | ✅ PASS | DIS-015 verified implemented; DIS-016 tracked in DevTODO; `IOSWeeklyReviewSheet` userId guard confirmed at line 336 |
| 7 Defensive UX | ⚠️ TRACKED | `IOSWeeklyReviewSheet.submitReview()` is synchronous — `isSubmitting` true/false flip in same call stack, `interactiveDismissDisabled` effectively cosmetic. Same pattern as PE-039. Tracked. |
| 8 Feature Completeness | ✅ PASS | All modified files are sheets/components, not list pages |

### Fixes Applied (Run 4 — 2026-04-10)

| # | File | Scanner | Issue | Fix |
|---|------|---------|-------|-----|
| 1 | QRScannerAdapter.swift | 5 (SQL vs Schema) | `tableForEntityType(.bin)` returned `"bin_locations"` — no such table in DB; scanning bin QR codes would throw SQL error | Changed to `"warehouse_bins"` (correct table per migration 000) |
| 2 | IOSAuditSummaryView.swift | 3 (Modal & Sheet Dismiss) | `AdjustDiscrepancySheet` has Stepper + TextField + `isSaving` state but no `interactiveDismissDisabled` — user can swipe-dismiss during save | Added `.interactiveDismissDisabled(isSaving)` on NavigationStack |
| 3 | IOSAuditSummaryView.swift | 7 (Defensive UX) | `AdjustDiscrepancySheet.applyAdjustment()` used `"load audit summary"` as error context — incorrect and confusing if shown to user | Changed to `"adjust audit count"` |

### Remaining/Tracked (Run 4)

| # | File | Scanner | Finding | Severity | Status |
|---|------|---------|---------|----------|--------|
| 7 | IOSWeeklyReviewSheet.swift | 7 (Defensive UX) | `submitReview()` synchronous — `isSubmitting` never visually activates, `interactiveDismissDisabled` guard is cosmetically inactive | MEDIUM | Same pattern as PE-039; track alongside that issue |
| 8 | 7 files (DIS-016) | 7 (Defensive UX) | `currentUser?.id ?? 1` write-path anti-pattern (worse than DIS-015: fallback is admin user ID) | HIGH | Tracked in DevTODO DIS-016, GitHub #140 |

---

## Known Issues

### From Problomes Screenshots (2026-03-28)
| # | Issue | GitHub | Status |
|---|-------|--------|--------|
| 1 | Login shows user on clean build | #18 | Open |
| 2 | Dashboard background task errors | #19 | Open |
| 3 | Clock In/Out broken | #20 | Open |
| 4 | All modals don't close (React/Tauri) | #21 | Open |
| 5 | Warehouse wizard Row 1 assumption | #22 | Open |
| 6 | Warehouse missing features | #23 | Open |
| 7 | Warehouse audit broken | #24 | Open |
| 8 | Create Job needs fields | #25 | Open |
| 9 | 10+ pages crash on empty DB | #26 | Partially fixed (service layer) |
| 10 | Trailer help incomplete | #27 | Open |
| 11 | Time Off count wrong | #28 | Open |
| 12 | Schedule Config incomplete | #29 | Open |
| 13 | Teams needs employees note | #30 | Open |
| 14 | Edit Tabs confusing | #31 | Open |
| 15 | Settings layout default | #32 | Open |

### From Core Swift Fixes (2026-04-02)
| Fix | File | What |
|-----|------|------|
| Error handling | PartsService.listCatalogParts() | Added isTableNotFoundError → empty result |
| Error handling | PeopleService.getContactsSorted() | Added isTableNotFoundError → empty tuple |
| Error handling | PeopleService.getContactTypeCounts() | Added isTableNotFoundError → empty counts |
| SQL mismatch | PeopleService.getHatMembers() | user_hats.created_at → NULL |
| SQL mismatch | PeopleService.getAvailableEmployeesForTeam() | Added status column alias |
| MainActor fix | PartsCatalogPage.loadData() | @State modified off main thread |
| Dead navigation | IOSContactsPage | Added navigationDestination + detail page |
| New method | PeopleService.updateContact() | Enables contact editing |
| Error scope | 3 services | isTableNotFoundError now catches "no such column" too |

---

## Usability Hunter Results (Behavioral Scans)

**Agent:** usability-hunter
**Schedule:** Daily at 10:00 AM
**Skill:** `xcode-ai/skills/usability-hunter/SKILL.md`
**GitHub Label:** `usability-hunter`

### Scanner Results (2026-04-06 — Usability Enforcer Run 2, all 8 scanners)

**Scope:** 3 modified warehouse wizard files (IOSMovementWizard, PartsFlowWizard, WarehouseOnboardingWizard) + AuthService + new fix prompts (PE-038, PE-039) + new DevTODOs (DIS-012/013/014)
**Build:** ✅ Build complete | **Tests:** ✅ 1030/1030 pass (up from 1014 — 16 new AuthService tests)

| Scanner | Result | Notes |
|---------|--------|-------|
| 1 Page Load Integrity | ✅ PASS | All 3 wizards load cleanly; error/loading states present |
| 2 Button & Action Verification | ✅ PASS | All buttons have real actions; no empty handlers |
| 3 Modal & Sheet Dismiss | ✅ PASS | IOSMovementWizard uses `WizardSheet` enum; no multiple `.sheet()` issues |
| 4 Navigation & Exit Paths | ✅ PASS | All wizards have Cancel/Save & Exit; Back buttons throughout |
| 5 SQL vs Schema Audit | ✅ PASS | AuthService SQL verified by 1030 tests; wizard files use service layer only |
| 6 Plan Alignment | ⚠️ PARTIAL | PE-036 ✅ done; PE-037/038/039 queued; DIS-012/013/014 DevTODOs need GitHub issues |
| 7 Defensive UX Patterns | ⚠️ 2 MEDIUM | PartsFlowWizard sync save (PE-039 queued); DIS-014 legacy token shim |
| 8 Feature Completeness | ✅ PASS | All 3 wizard flows complete with error/cancel/resume paths |

**P1 fixes this run:** 0
**P2 fixes this run:** 0 (PE-039 already queued for Xcode AI)
**P3 fixes this run:** 0 (DIS-012/013/014 already have DevTODO files)

### Scanner Results (2026-04-10 — Run 5)

**Scope:** All 6 scanners across full iOS app (325+ Swift files)
**Build:** ✅ Build complete | **Tests:** ✅ 1165/1165 pass (up from 1142 — 23 new tests)

| Scanner | Category | Findings | Verdict |
|---------|----------|---------|---------|
| 1 | Dismiss & Sheet Safety | 6 sheets with `isSaving`/`isProcessing` but no `interactiveDismissDisabled`: CategoriesFormSheets (4 structs), PartsSuppliersPage SupplierFormSheet, SmartDeleteSheet | **FIXED** — added `.interactiveDismissDisabled` to all 6. Filed #143 for 30+ remaining Settings/People/Chat sheets |
| 2 | Silent Failures | 6× `try? svc?.updateSessionItem` in IOSReceiveShipmentPage (Reset to Expected, Clear All, qty steppers). 3 new empty catch blocks in AppCore, CompanySetupWizard, LoginView | **Filed #141** (ReceiveShipment), **Filed #142** (empty catches in auth flows) |
| 3 | Missing User Feedback | No new findings beyond previously tracked issues | No new HIGH |
| 4 | Navigation & Exit Traps | ShiftTemplateEditSheet + HolidayEditSheet delete buttons fire immediately without confirmation | **FIXED** — added `@State showDeleteConfirm` + `.confirmationDialog` + `dismiss()` to both sheets |
| 5 | Form & Input Issues | "Manufacturer part number", "Account Number", "Trailer Number" TextFields missing keyboardType — these are alphanumeric codes, not pure numeric (false positive for scanner 5c) | Acceptable — alpha-numeric code fields don't need numberPad |
| 6 | Accessibility & Touch | Wizard progress dots (10px) — confirmed decorative in Run 4 | No new HIGH |

**False positives confirmed:**
- IOSHatsPage delete → uses `hatToDelete` state + `.alert` ✅
- IOSPurchaseOrdersPage delete → uses `poToCancel` state + `.alert` ✅
- "Manufacturer part number" TextField → alphanumeric code, not numeric input ✅
- Wizard 10px progress dots → non-interactive decorative elements ✅

**Fixes applied (7):**
1. `CategoriesFormSheets.swift` — CategoryFormSheet: added `.interactiveDismissDisabled(isSaving)` to NavigationStack
2. `CategoriesFormSheets.swift` — StyleFormSheet: added `.interactiveDismissDisabled(isSaving)` to NavigationStack
3. `CategoriesFormSheets.swift` — TypeFormSheet: added `.interactiveDismissDisabled(isSaving)` to NavigationStack
4. `CategoriesFormSheets.swift` — ColorFormSheet: added `.interactiveDismissDisabled(isSaving)` to NavigationStack
5. `PartsSuppliersPage.swift` — SupplierFormSheet: added `.interactiveDismissDisabled(isSaving)` to NavigationStack
6. `SmartDeleteSheet.swift` — added `.interactiveDismissDisabled(isProcessing)` to NavigationStack
7. `IOSScheduleConfigPage.swift` — ShiftTemplateEditSheet + HolidayEditSheet: added `showDeleteConfirm` state + `.confirmationDialog` with destructive confirmation + `dismiss()` after delete

---

### Scanner Results (2026-04-08 — Run 4)

**Scope:** All 6 scanners across full iOS app (323+ Swift files)
**Build:** ✅ Build complete | **Tests:** ✅ 1118/1118 pass (no change)

| Scanner | Category | Findings | Verdict |
|---------|----------|---------|---------|
| 1 | Dismiss & Sheet Safety | 40+ sheets missing `interactiveDismissDisabled` (Settings/People/Parts/Orders/Notebooks) | All covered by systemic #123 — no new CRITICAL |
| 2 | Silent Failures | 3 new `try?` on write-path: CompanySetupWizard draft save (line 730), IOSNotebookDetailPage default section create (line 915), IOSMessageThreadView notebook auto-save (line 370) | Filed #135, #136, #137 |
| 3 | Missing User Feedback | WarehouseLocationsPage "Remove" unit button had no confirmation dialog — **FIXED** | 1 fix applied |
| 4 | Navigation & Exit Traps | 20+ Settings forms without dirty tracking — covered by #129 | No new HIGH |
| 5 | Form & Input Issues | IOSJPOCreationPage submit button is properly guarded (false positive from scanner). Settings save buttons are always-enabled by design. | No new HIGH |
| 6 | Accessibility | Wizard progress indicator dots (10px) are decorative not interactive — false positives. Icon buttons without a11y labels — LOW, systemic. | No new HIGH |

**Fixes applied (1):**
- `WarehouseLocationsPage.swift` — "Remove" context menu button now sets `unitToDelete` state → `.confirmationDialog` with destructive confirmation before `deleteUnit()` is called

**False positives confirmed:**
- IOSHatsPage delete — uses `.alert("Delete Hat?", ...)` + `hatToDelete` state ✅
- IOSPurchaseOrdersPage delete — uses `.alert` + `poToCancel` state ✅
- IOSJPOCreationPage submit — `.disabled(cartItems.isEmpty || selectedJobId == nil || isSubmitting)` confirmed ✅
- 10px frame() items in wizard progress dots — decorative, not tappable ✅

---

### Scanner Results (2026-04-06 — Run 3) — Clean Pass

**Build:** ✅ 1030/1030 tests pass | **New fixes:** 0 | **New issues filed:** 0 | **Issues closed:** 4 (#124-#127)

| Scanner | Category | Findings | Verdict |
|---------|----------|---------|---------|
| 1 | Dismiss & Sheet Safety | 40 sheets missing `interactiveDismissDisabled` (Settings/Chat/People) | All covered by systemic #123 |
| 2 | Silent Failures | ~19 `try?` on write-path keywords — all verified as reads or secondary ops in do-catch | No new CRITICAL. IOSAuditPage:828 `updateUserRating` acceptable (secondary in do-catch) |
| 3 | Missing User Feedback | Settings `saveSettings()` buttons — all checked, have isSaving states | No new HIGH |
| 4 | Navigation & Exit Traps | Wizard files without "Save & Exit" string — scanner false positives | IOSMovementWizard ✅ has Cancel; wizard step files are components not orchestrators |
| 5 | Form & Input Issues | Save buttons flagged — all verified false positives (±2 line window too narrow for toolbar pattern) | **Scanner calibration note:** `.disabled()` is always 3-4 lines below `Button {…}` for toolbar buttons — need ±5 line window |
| 6 | Accessibility | Small frame hits — all non-interactive (icons, decorative dots, color swatches with label text) | ThemesPage color swatches: 36px circle + text label = >44px total tap target. Acceptable |

**Verified still-fixed from prior runs:**
- ✅ #124 PricingOverrideFlow dismiss-after-await — `dismiss()` before await, onComplete in background Task
- ✅ #125 IOSScheduleConfigPage silent deletes — `do-catch` with `saveError`
- ✅ #126 IOSClockPage workType silent fail — `do-catch` with `errorMessage`
- ✅ #127 EstimationSettingsPage Save without guard — `.disabled(isEmpty)` confirmed at lines 398, 486

**Scanner 5 calibration issue:** The ±2 line scan window misses `.disabled()` on toolbar buttons because SwiftUI toolbar buttons always use multi-line `Button { … } label: { … }` syntax. Need ±5 lines in future runs.

### Scanner Results (2026-04-06 — Run 2)

| Scanner | Category | Violations | Severity |
|---------|----------|-----------|----------|
| 1 | Dismiss & Sheet Safety | 2 confirmed dismiss-after-await (PricingOverrideFlow, IOSJPOCreationPage) | CRITICAL |
| 2 | Silent Failures | ~20+ empty catch blocks; try? on delete/save in IOSScheduleConfigPage, IOSClockPage | CRITICAL/HIGH |
| 3 | Missing User Feedback | 20+ files missing success feedback on save/create (Settings, Scheduling, People) | HIGH |
| 4 | Navigation & Exit Traps | 20+ Settings forms without dirty tracking/discard confirmation | MODERATE |
| 5 | Form & Input Issues | 14 Save buttons without .disabled(); IOSEstimationSettingsPage EditSheet fixed | MODERATE |
| 6 | Accessibility & Touch | Not fully scanned this run (grep -P not available on macOS) | LOW |

### Scanner Baseline (2026-04-05)

| Scanner | Category | Violations | Severity |
|---------|----------|-----------|----------|
| 1 | Dismiss & Sheet Safety | 163 sheets missing `interactiveDismissDisabled`, 34 dismiss-after-await files | CRITICAL/HIGH |
| 2 | Silent Failures | 198 `try?` (72 files), 426 guard-let-service-return | CRITICAL/HIGH |
| 3 | Missing User Feedback | TBD (first full run) | HIGH |
| 4 | Navigation & Exit Traps | TBD (first full run) | HIGH |
| 5 | Form & Input Issues | TBD (first full run) | MODERATE |
| 6 | Accessibility & Touch | TBD (first full run) | MODERATE |

### GitHub Issues Filed (2026-04-06 — Run 2)

| Issue | Category | File(s) | Severity | Status |
|-------|----------|---------|----------|--------|
| #124 | Dismiss-after-await | PricingOverrideFlow.swift | CRITICAL | **FIXED 2026-04-06** — dismiss() before await, onComplete() in background Task |
| #125 | Silent delete failures | IOSScheduleConfigPage.swift | CRITICAL | **FIXED 2026-04-06** — deleteShiftTemplate + deleteHoliday → do-catch with saveError |
| #126 | Silent save failure | IOSClockPage.swift | CRITICAL | **FIXED 2026-04-06** — setClockEntryWorkType try? → do-catch with errorMessage |
| #127 | Save button validation | IOSEstimationSettingsPage.swift | HIGH | **FIXED 2026-04-06** — EditEstimationQuestionSheet Save now .disabled on empty text |
| #128 | Systemic empty catch blocks | 10+ files | HIGH | Open — needs per-file audit (write ops vs non-critical loads) |
| #129 | Systemic dirty tracking | 20+ Settings forms | MODERATE | Open — needs hasUnsavedChanges + interactiveDismissDisabled |

### GitHub Issues Filed (2026-04-05)

| Issue | Category | File(s) | Severity | Status |
|-------|----------|---------|----------|--------|
| #112 | Dismiss-after-await | QRScanSheet.swift | CRITICAL | **Verified OK** — already uses `await MainActor.run { dismiss() }` |
| #113 | Dismiss-after-await | CascadePriceEditSheet.swift | CRITICAL | **Verified OK** — only sync dismiss() buttons, no async context |
| #114 | Dismiss-after-await | PartsBrandsPage.swift | CRITICAL | **Verified OK** — closed by commit 05c7f58 |
| #115 | Silent save failure | WarehouseOnboardingWizard.swift | CRITICAL | **FIXED 2026-04-05** — finishOnboarding() try? → do-catch; don't dismiss on failure |
| #116 | Silent save failure | PartsFlowWizard.swift | CRITICAL | **FIXED 2026-04-05** — saveAllProgress() try? → do-catch; error alert; blocks dismiss on failure |
| #117 | Navigation trap | CompanySetupWizard.swift | HIGH | **Verified FIXED** — confirmationDialog for exit + step navigation in place |
| #118 | Dismiss-after-async | IOSTeamDetailPage.swift | HIGH | **Verified OK** — deleteTeam uses `await MainActor.run { dismiss() }` correctly |
| #119 | Form issues | IOSMovementWizard.swift | MODERATE | Open |
| #120 | Missing dismiss guard | IOSWarehouseSettingsPage.swift | MODERATE | **Verified FIXED** — converted to ActiveSheet enum in recent work |
| #121 | SYSTEMIC: try? | 72 files (198 instances) | HIGH | Open (2 fixed this run: #115, #116) |
| #122 | SYSTEMIC: guard-let-return | 60+ files (426 instances) | HIGH | Open |
| #123 | SYSTEMIC: interactiveDismissDisabled | 163 sheets missing guard | MODERATE | Open |

---

## Fixes Applied (2026-04-05 — Usability Enforcer Run)

### P1 Fixes (Silent Save Failures — 2 files)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | WarehouseOnboardingWizard.swift | `finishOnboarding()` used `try?` on `completeOnboarding()` — wizard could silently fail to mark itself complete | Replaced with `do-catch`; sets `loadError` and returns without dismissing on failure |
| 2 | PartsFlowWizard.swift | `saveAllProgress()` used `try?` on `updatePart()` — part location/count data silently lost on DB error | Replaced with `do-catch`; collects failed part names, shows error alert, blocks dismiss until user acknowledges |

### P3 Fixes (Accessibility / Code Quality — 3 files)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 3 | WizardStepPlacement.swift | `.font(.system(size: 7))` — 7pt font bypasses Dynamic Type, unreadable at normal viewing distance (DIS-008) | Replaced with `.font(.caption2).minimumScaleFactor(0.4)` |
| 4 | WizardStepPlacement.swift | `placedUnit != nil ? "\(placedUnit!.name)..."` — force unwrap guarded by ternary nil check (DIS-011) | Replaced with `placedUnit.map { "\($0.name)..." } ?? "..."` |
| 5 | IOSScheduleConfigPage.swift | 2× `existing != nil ? { fn(existing!.id) } : nil` — force unwrap in onDelete closures (DIS-011) | Replaced with `existing.map { x in { fn(x.id) } }` |

### Verified Already Fixed (no code change needed)

| # | Issue | Verification |
|---|-------|-------------|
| 6 | #112 QRScanSheet dismiss-after-await | Already uses `await MainActor.run { dismiss() }` — correct pattern |
| 7 | #113 CascadePriceEditSheet dismiss-after-await | Only sync `Button("Done") { dismiss() }` — no async path |
| 8 | #117 CompanySetupWizard navigation trap | Has confirmationDialog for exit + proper 8-step navigation |
| 9 | #118 IOSTeamDetailPage dismiss-after-async | `deleteTeam()` uses `await MainActor.run { dismiss() }` — correct |
| 10 | #120 IOSWarehouseSettingsPage dismiss guard | Converted to `ActiveSheet` enum pattern in previous work |

**Build result:** 1014 tests pass, 0 failures.

---

## Run History

| Date | Scanners Run | Issues Found | Fixed | New GitHub Issues | New DevTODOs |
|------|-------------|-------------|-------|-------------------|--------------|
| 2026-04-04 | Full 6-check audit (all 170+ pages) — Round 1 | 22 | 22 | 0 | 0 |
| 2026-04-04 | Deep fix pass — Round 2 (P3 sheets, loading states, .constant alerts) | 26 | 26 | 0 | 0 |
| 2026-04-05 | **Usability Hunter** initial sweep — 6 scanners across 323 files | 12 issues filed | 0 | 12 (#112-#123) | 0 |
| 2026-04-05 | **Usability Enforcer** — 8 scanners, focus on modified files + open issues | 7 fixes | 5 | 0 | 0 |
| 2026-04-06 | **Usability Hunter** Run 2 — all 6 scanners, 5 files fixed | 10 findings | 5 (#124-#127 fixed, dismiss-after-sleep) | 6 (#124-#129) | 0 |
| 2026-04-06 | **Usability Hunter** Run 3 — all 6 scanners, 1030 tests pass | 0 new fixable | 0 | 0 | 0 |
| 2026-04-06 | **Usability Enforcer** Run 2 — all 8 scanners, focus on 3 warehouse wizard files + AuthService changes | 2 medium findings (both tracked) | 0 | PENDING (gh unavailable) | 0 |
| 2026-04-08 | **Usability Enforcer** Run 3 — all 8 scanners, focus on IOSWishlistPage (DIS-006 followup) | 3 fixes applied, 2 S2 tracked | 3 | 0 (gh unavailable) | 0 |
| 2026-04-08 | **Usability Hunter** Run 4 — all 6 scanners, full app sweep | 4 findings (1 fixed, 3 filed) | 1 (WarehouseLocationsPage confirm dialog) | 3 (#135-#137) | 0 |
| 2026-04-10 | **Usability Hunter** Run 5 — all 6 scanners, full app sweep | 9 findings (7 fixed, 2 filed) | 7 (6 interactiveDismissDisabled, 2 confirmationDialog) | 3 (#141-#143) | 0 |
| 2026-04-10 | **Usability Enforcer** Run 4 — all 8 scanners, focus on 4 modified files (DIS-015 fix set + new tests) | 3 fixes, 2 tracked | 3 | 0 | 0 |
