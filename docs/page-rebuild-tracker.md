# Historical Page-by-Page Rebuild Tracker

**Agent:** page-rebuild-enforcer
**Schedule:** Daily at 4:00 PM
**Skill:** `xcode-ai/skills/page-rebuild-enforcer/SKILL.md`
**GitHub Issues:** #52-#66 (Program Review)


## Scope note added 2026-05-23 for GH#649 / WEI-2005

This tracker is a historical 44-page rebuild/pass-fail matrix from the page-rebuild-enforcer run. It is not the current full iOS page inventory and must not be used as proof that every current user-facing app page has passed human-visible QA. The live app now has a broader page/flow surface, and current beta-readiness verification is tracked forward in:

- `docs/plans/ux-audit-page-gap-list-2026-05-23.md` — reconciliation of design/prompt completion versus remaining usability confidence.
- `docs/testing/wei-1944-full-app-usability-verification-matrix.md` — current full-app usability verification matrix and evidence requirements.

Use the historical 44/44 result only as evidence that the older rebuild queue was drained. Use the WEI-1944 matrix for current page-by-page/manual simulator verification status.

---

## Current Page: Historical open-issue queue rebuild pass (44-page scope complete)
## Status: HISTORICAL PASS — 44/44 pages in the April 2026 rebuild matrix complete. Run 2026-04-15: **#149 PARTIAL + #148 FIXED** — (1) Keyboard dismiss sweep: added `.scrollDismissesKeyboard(.interactively)` to 22 files across Auth, Settings, Scheduling, Dashboard, People, Orders, and Warehouse (went from 3 → 25 files with keyboard dismiss coverage). Files fixed: IOSMovementWizard, CompanySetupWizard, BusinessProfileSetupView, CreateScheduleEntrySheet, IOSScheduleConfigPage, DashboardDailyReportPage, IOSContractorDetailPage, IOSDailyReportTemplatesPage, IOSContactDetailPage, IOSCustomerDetailPage, IOSEmployeeDetailPage (×3 lists), IOSBreakSettingsPage, CreateDispatchSheet, IOSAuditSettingsPage, IOSOrganizationThresholdsPage, IOSForecastSettingsPage, IOSClockOutQuestionsPage, IOSReportTemplatesPage, IOSPreTripChecklistPage, CompanyProfilesPage, IOSJPOCreationPage, CreatePOSheet. (2) **#148 FIXED** — IOSMovementWizard now has Save & Exit button (top-right toolbar): saves wizard draft state to UserDefaults as JSON (step, locations, parts, reason, notes, reference), restores on re-entry with a dismissible "Draft restored" banner, clears on successful execute. WizardPart made Codable. 1258/1258 tests pass. Previous run 2026-04-14: **#184 + #191 FIXED** — JSON injection fix + unauthenticated key exchange. 4 new tests. 1241/1241 passing.

---

## Progress Matrix

### Tier 1 — Revenue Core
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 1 | Parts Catalog | ✅ | 1 | 1 | 0 | 2026-04-04 |
| 2 | Parts Forecasting | ✅ | 2 | 0 | 2 | 2026-04-04 |
| 3 | Jobs List | ✅ | 1 | 0 | 1 | 2026-04-04 |
| 4 | Job Detail Dashboard | ✅ | 2 | 1 | 1 | 2026-04-04 |
| 5 | Clock In/Out | ✅ | 1 | 1 | 0 | 2026-04-04 |
| 6 | JPO Creation (3-Panel) | ✅ | 6 | 1 | 5 | 2026-04-04 |
| 7 | JPO List | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 8 | Procurement Planner | ✅ | 2 | 0 | 2 | 2026-04-04 |

### Tier 2 — Operations
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 9 | Purchase Orders | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 10 | Warehouse Dashboard | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 11 | Warehouse Movements | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 12 | Locations/Floor Plan | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 13 | Sorting/Receiving | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 14 | Staging | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 15 | Audit System | ✅ | 0 | 0 | 0 | 2026-04-04 |

### Tier 3 — People & Admin
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 16 | People Dashboard | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 17 | Employee Detail | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 18 | Customer Detail | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 19 | Contacts + Detail | ✅ | 2 | 2 | 0 | 2026-04-04 |
| 20 | Teams/Hats/Perms | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 21 | Office Dashboard | ✅ | 1 | 1 | 0 | 2026-04-04 |
| 22 | Unified Approvals | ✅ | 0 | 0 | 0 | 2026-04-04 |

### Tier 4 — Scheduling & Fleet
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 23 | Schedule Calendar | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 24 | Dispatch Board | ✅ | 1 | 1 | 0 | 2026-04-04 |
| 25 | Pipeline | ✅ | 1 | 0 | 1 | 2026-04-04 |
| 26 | Fleet Dashboard | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 27 | Vehicle Detail | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 28 | Pre-Trip Inspections | ✅ | 0 | 0 | 0 | 2026-04-04 |

### Tier 5 — Communication & Docs
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 29 | Chat (Unified Inbox) | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 30 | Q&A + RFI | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 31 | Notebooks List/Detail | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 32 | Block Editor | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 33 | Panel Schedule | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 34 | Daily Reports | ✅ | 0 | 0 | 0 | 2026-04-04 |

### Tier 6 — Tools & Settings
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 35 | Tools Dashboard | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 36 | Kit Management | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 37 | Tool Trade/Maint | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 38 | Settings (all) | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 39 | Reports (all) | ✅ | 0 | 0 | 0 | 2026-04-04 |

### Tier 7 — Cross-Cutting
| # | Page | Status | Issues Found | Fixed | Remaining | Date |
|---|------|--------|-------------|-------|-----------|------|
| 40 | Standard Filter Bar | ✅ | 0 | 0 | 0 | 2026-04-05 |
| 41 | Help Button | ✅ | 3 | 3 | 0 | 2026-04-05 |
| 42 | Save & Exit Patterns | ✅ | 2 | 2 | 0 | 2026-04-05 |
| 43 | QR Integration | ✅ | 0 | 0 | 0 | 2026-04-04 |
| 44 | First-Time Use | ✅ | 0 | 0 | 0 | 2026-04-04 |

_Legend: ? = Not started, 🔄 = In Progress, ✅ = Pass, ❌ = Blocked_

---

## Historical Summary
| Metric | Count |
|--------|-------|
| Historical rebuild matrix pages | 44 |
| Historical rebuild matrix completed | 44 |
| In Progress in this historical matrix | 0 |
| Not Started in this historical matrix | 0 |
| Blocked in this historical matrix | 0 |

Current full-app QA status lives in `docs/testing/wei-1944-full-app-usability-verification-matrix.md`; this file intentionally does not count the expanded current app page inventory.

---

## Run History

| Date | Pages Worked | Issues Found | Fixed | Tests Pass | Build Pass |
|------|-------------|-------------|-------|-----------|-----------|
| 2026-04-04 | Parts Catalog | 1 | 1 | ✅ (964) | ✅ |
| 2026-04-04 | Parts Forecasting | 2 | 0 | ✅ (964) | ✅ |
| 2026-04-04 | Jobs List | 1 | 0 | ✅ (964) | ✅ |
| 2026-04-04 | Clock In/Out | 1 | 1 | ✅ (964) | ✅ |
| 2026-04-04 | Job Detail | 2 | 1 | ✅ (964) | ✅ |
| 2026-04-04 | JPO Creation | 6 | 1 | ✅ (964) | ✅ |
| 2026-04-04 | Procurement | 2 | 0 | ✅ (964) | ✅ |
| 2026-04-04 | Warehouse Dashboard | 0 | 0 | ✅ (964) | ✅ |
| 2026-04-04 | Tier 2: PO, Movements, Locations, Receiving, Staging, Audit | 0 | 0 | ✅ (964) | ✅ |
| 2026-04-04 | Tier 3: People, Employee, Customer, Contacts, Teams, Office, Approvals | 3 | 3 | ✅ (964) | ✅ |
| 2026-04-04 | Tier 4: Calendar, Dispatch, Pipeline | 1 | 1 | ✅ (964) | ✅ |
| 2026-04-04 | Tier 5: Chat, Notebooks | 0 | 0 | ✅ (964) | ✅ |
| 2026-04-04 | Tier 4: Fleet (3 pages), Tier 5: Q&A, Block Editor, Panel Schedule, Daily Reports | 0 | 0 | ✅ (970) | ✅ |
| 2026-04-04 | Tier 6: Tools (3 pages), Settings, Reports, QR, First-Time Use, JPO List | 0 | 0 | ✅ (970) | ✅ |
| 2026-04-05 | Tier 7: Standard Filter Bar, Help Button, Save & Exit Patterns | 5 | 5 | ✅ (1014) | ✅ |
| 2026-04-06 | Fix queue drain: PE-036 verified (WarehouseOnboardingWizard already done), PE-038 (JobStageProgressBar font→Dynamic Type), PE-039 partial (PartsFlowWizard DB loop→Task{}+isSaving) | 2 | 2 | ✅ (1030) | ✅ |
| 2026-04-08 | Fix queue drain: PE-041 (receiving auto-save draft: all qty mutations → updateSessionItem Task{}, restore from DB on resume, discard dialog removed), PE-040 (WizardStepPlacement rewrite: Phase A dimensions form + migration 073 + updateFloorPlanGrid, Phase B drag-and-drop via .onDrag/.dropDestination) | 2 | 2 | ✅ (1118) | ✅ |
| 2026-04-10 | DIS-016: fixed all 7 `currentUser?.id ?? 1` write-path anti-patterns (IOSMessageThreadView, IOSCustomerDetailPage ×2, IOSContractorDetailPage, IOSProcurementPage, IOSNotebookDetailPage, IOSAuditSetupView). `?? 1` eliminated from entire codebase. GitHub #140 closed. | 7 | 7 | ✅ (1162) | ✅ |
| 2026-04-12 (AM) | Open issue queue: **#145 FIXED** — `.refreshable { loadMessages() }` added to IOSMessageThreadView ScrollView. **IOSEscalationTimeline empty state** — `steps.isEmpty` branch added with EmptyStateView (steps always populated by service, but guard is correct per checklist). **#146 partial** — `Formatters.localDateFormatter` + `Formatters.localDateTimeFormatter` added to Formatters.swift; 4 inline `DateFormatter()` instances in IOSClockPage (`breakElapsedMinutes` ×1, `breakElapsedSeconds` ×1, `checkDispatchStatus` ×1, `assignFlexJob` ×1) replaced with cached formatters. 95 remaining inline instances tracked in #146 for future sweep. | 3 | 3 | ✅ (1196) | ✅ |
| 2026-04-12 (PM) | **#146 major sweep** — 9 new cached formatters added to Formatters.swift. 37 inline instances eliminated: IOSPODetailPage ×7, IOSScheduleConfigPage ×6, DashboardView ×5, IOSWishlistPage ×4, TimelinePriorityColor ×3, IOSSubSchedulePage ×3, IOSDispatchPage ×3, PartsForecastingPage ×3, IOSWeeklyReviewSheet ×3. Bonus: IOSSubSchedulePage formatter-mutation bug fixed (formatter was mutated from parse→display format on same instance). 46 non-Formatters instances remain across ~28 files. | 37 | 37 | ✅ (1217) | ✅ |
| 2026-04-14 | Open issue queue — Security sweep: **#184 FIXED** (JSON injection in cert rejection → JSONEncoder), **#191 FIXED** (unauthenticated key exchange → X-Company-ID header check). 4 new tests. | 2 | 2 | ✅ (1241) | ✅ |
| 2026-04-15 | Open issue queue — **#149 partial** (keyboard dismiss sweep: `.scrollDismissesKeyboard(.interactively)` added to 22 files, 3→25 total). **#148 FIXED** (IOSMovementWizard Save & Exit: UserDefaults draft persistence, WizardPart Codable, restore banner). | 23 | 23 | ✅ (1258) | ✅ |
