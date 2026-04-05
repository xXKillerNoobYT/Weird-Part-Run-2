# WiredPart Development Pipeline

> **Last updated:** 2026-04-05 (github-issues-sync run 6 — #40 verified resolved (iOS routes correct), #44 core done comment added, #87/#90/#93 status comments added. DeviceResetService: isTableNotFoundError guards on 3 methods. 970/970 tests. 44 open issues: 5 enhancement/bug + 39 program-review specs.)
> **Auto-maintained by:** dev-pipeline-manager (orchestrator)

---

## The 13-Step Lifecycle

Every feature, bug, or improvement follows this cycle:

```
 1. IDEAS & BUGS IN        ← GitHub issues, plans, scanner findings
 2. PLAN MADE              ← Detailed plan in docs/plans/
 3. Q&A ASKED              ← Role-based questions in docs/dev-qa.md
 4. Q&A ANSWERED           ← Owner fills in answers (loop 3↔4 as needed)
 5. IT GETS CODED          ← Auto-built or Xcode prompts
 6. ALL BUGS FOUND         ← hunt-fix-verify scanners
 7. FINE TUNED             ← Test coverage, edge cases
 8. IMPROVED               ← dev-improvement-scanner polish
 9. LOOKS GOOD + SECURE    ← Apple HIG compliance, security audit
10. XCODE TASKS SENT       ← Prompts for UI work user triggers
11. AUDIT THE CHANGES      ← plan-enforcer verifies against spec
12. SELF-IMPROVE           ← Find gaps, reorganize agents, fill holes
13. SYNC TO GITHUB         ← Commit, review, push
```

---

## Master Status

| Area | Status | Last Checked |
|------|--------|-------------|
| Build | 0 errors, 0 warnings | 2026-04-04 |
| Tests | **970/970 passing** — dev-pipeline-manager run 11 (2026-04-04): +6 flex pool tests (fetchFlexPool, markJobFlexPool, claimFlexJob). Previous: hunt-fix 29 iters + test-coverage-maintenance + plan-enforcer all contributed. | 2026-04-04 |
| Plan Alignment | PE-026 ✅ DONE. PE-033 ✅ DONE. PE-032 ✅ DONE. PE-028 ✅ DONE. **PE-003 CORE DONE** — migration 071 + SchedulingService flex pool methods; UI Xcode prompt still needed. **PE-027/PE-029/PE-030/PE-031** prompts still needed (UI work pending). | 2026-04-04 |
| Feature Polish | **5 Xcode prompts:** PE-031 (🚨 clock GPS banner), PE-027 (part number UI), PE-029 (price chips), PE-030 (warehouse setup redesign), PE-034 (DIS-001/002/003/004 quick UI fixes — NEW). | 2026-04-04 |
| Xcode Prompts | **5 active prompts:** PE-031 (🚨 EMERGENCY), PE-027, PE-029, PE-030, PE-034 (new — DIS-001 loading indicators, DIS-002 pull-to-refresh, DIS-003 sheet detents, DIS-004 timer lifecycle). | 2026-04-04 |
| GitHub Issues | **44 open** — #40 ✅ verified resolved (iOS routes correct, already closed). #44 PE-003 core done comment added. #87/#90/#93 status comments added (PE-028/032/033 done). #41 (AI memory), #45 (job card AI+stage bars): tracked, not yet implemented. #42/#43 (T2/T3 gaps): backlog. #52–#95 program-review: 39 open specs, tracked in page-rebuild-tracker.md. | 2026-04-05 |
| Q&A Backlog | **4 pending questions** — DIS-005 (2 questions: UserDefaults PII cleanup), DIS-007 (2 questions: IOSMainView logout lifecycle). | 2026-04-04 |
| Working Tree | ⚠️ Many modified files — see git status. Key changes this run: WishlistService.swift (DIS-006 fix), AppDatabase+Migrations.swift (migration 071), SchedulingModels.swift (FlexPoolJob struct), SchedulingService.swift (flex pool methods), SchedulingServiceTests.swift (6 new tests). | 2026-04-04 |
| Agent Health | All 8 agents enabled | 2026-04-04 |

---

## Active Work Items

> Each item tracks which lifecycle step it's on.

| ID | Item | Step | Status | Owner |
|----|------|------|--------|-------|
| PE-001 | ~~Tool naming drift: "Tool Registry"→"All Tools", "Tool Admin"→"Management"~~ **DONE** | 13 — complete | ✅ Closed 2026-03-31 — `IOSToolRegistryPage`, `IOSToolAdminPage`, `IOSToolCheckoutsPage`, `HelpContentRegistry` updated; prompt archived to `done/` |
| PE-002 | ~~Verify 35C-35I still needed~~ **RESOLVED** | 13 — complete | ✅ Closed | All prompts run or skipped |
| PE-003 | Flex pool self-assign — Scheduling tab "Flex Pool" tab + job detail manager action | 10 — Xcode prompt ready | 🟡 **Core DONE** (run 11): Migration 071 + `FlexPoolJob` struct + `fetchFlexPool`/`claimFlexJob`/`markJobFlexPool` in SchedulingService. 6 tests. Prompt written: `fix-prompts/PE-003-flex-pool-scheduling-ui.md`. Trigger after PE-027/029/030. |
| PE-024 | ~~Modal dismiss audit~~ **DONE** — all sheets audited 2026-04-03; all dismiss patterns already correct (struct-level `@Environment(\.dismiss)`, `ActiveSheet` enum, `SheetDismissWrapper`). No changes needed. GitHub #21 code-verified. | 13 — complete | ✅ Closed 2026-04-03 — no changes needed. Prompt archived. |
| PE-025 | ~~Empty states + settings UI: Teams "requires employees", Edit Tabs clarity, Page Layout descriptions (GitHub #30, #31, #32)~~ **DONE** | 13 — complete | ✅ Closed 2026-04-04 — committed 826dd18. Also included CategoriesTreeView @State→@Binding (partial #46). Prompt archived. |
| PE-026 | ~~Badge counts on all tabs (real-time, green=recent/red=overdue), action button border rings, notebook update badges (GitHub #50, #51)~~ **DONE** | 13 — complete | ✅ Closed 2026-04-04 — `BadgeCountService.swift` (307 lines) + `BadgeCountManager.swift` (71 lines, EnvironmentObject) implemented. `IOSMainView.swift` wired with `.badge()` modifier. Prompt archived to `done/`. |
| PE-031 | Clock In/Out bug fix — GPS permission race + alreadyClockedIn recovery (GitHub #20) | 10 — Xcode prompt ready | 🚨 **EMERGENCY — core done, UI pending** — prompt at `fix-prompts/PE-031-clock-fix-ios.md`. Core fixes confirmed: 24 `isTableNotFoundError` guards in JobsService, `alreadyClockedIn` recovery in IOSClockPage:1151. Remaining: GPS permission banner UI + recovery alert UI (Xcode prompt still needed). |
| PE-027 | Part numbers at Color level + per-supplier part numbers + search by PN/abbreviation (GitHub #46) | 10 — Xcode prompt ready | 🔴 **PARTIAL** — migration 065 adds `part_number` to colors table ✅. `PartsModels.PartColor.partNumber` exists ✅. UI work (catalog color row display + edit) still pending via prompt at `fix-prompts/PE-027-part-number-hierarchy.md`. |
| PE-028 | ~~Brands & Suppliers editing — brand-supplier bidirectional linking, carry status, orange warning (GitHub #47)~~ **DONE** | 13 — complete | ✅ Closed 2026-04-04 — Migration 066 adds `carry_status` to `brand_supplier_links`. Service: `getBrandSuppliers`, `getBrandSuppliersWithStatus`, `getSupplierBrands` in PartsService. UI: full carry status display + toggle in `PartsBrandsPage` and `PartsSuppliersPage`. Schema note: uses `brand_supplier_links` + `carry_status` column instead of new `brand_supplier_relationships` table (plan drift; functionally equivalent). |
| PE-029 | Pricing UI — price chips on catalog color rows, PriceEditSheet cascade (type→color→supplier), IOSPricingPage overview (GitHub #48) | 10 — Xcode prompt ready | 🔴 **PARTIAL** — `CascadePriceEditSheet.swift` (359 lines) implemented ✅. Wired in `CategoriesTreeView` via `.editColorPrice` sheet case. Catalog integration (color row price chips in `IOSPartsCatalogPage`) still pending via prompt at `fix-prompts/PE-029-pricing-ui.md`. Note: `PricingOverrideFlow.swift` exists as **unplanned addition** (hierarchy-level override flow) — no plan reference; functionally extends PE-029 scope. |
| PE-030 | Warehouse Setup Redesign — remove forced gate, two independent flows, drag-and-drop floor plan, cart mode, resumable (GitHub #49) | 10 — Xcode prompt ready | 🔴 **PARTIAL** — `WarehouseSetupTier` enum + `getSetupProgress()` in WarehouseService; `WarehouseDashboardPage` renders tier-appropriate setup banners. Missing: two independent setup flows, drag-and-drop unit placement, cart mode. Prompt at `fix-prompts/PE-030-warehouse-setup-redesign.md`. |
| PE-032 | ~~Schedule Config additive — company hours, shift templates per hat, holiday calendar, dispatch rules, supervisor role (GitHub #29)~~ **DONE** | 13 — complete | ✅ Closed 2026-04-04 — Migration 069 adds `shift_templates` + `company_holidays` tables. `IOSScheduleConfigPage.swift` (823 lines) has: `companyWorkHoursSection`, `shiftTemplatesSection`, `dispatchRulesSection`, supervisor hat assignment, holiday calendar. Prompt at `fix-prompts/PE-032-schedule-config-additive.md` is now stale (work done). |
| PE-033 | ~~Wishlist 3-section layout — User Added/Forecast Demand/System Auto-Added sections, dismiss reason, auto-approve timer, certainty score (GitHub #93)~~ **DONE** | 13 — complete | ✅ Closed 2026-04-04 — Migration 070 adds `dismiss_reason`, `auto_approve_at`, `certainty_score`. `WishlistModels.swift` updated. `WishlistService` has `getSectionedItems()`, `processAutoApprovals()`, `dismissItem(reason:)`. `IOSWishlistPage.swift` has 3-section layout. Plan at `docs/plans/ios-wishlist-enhancements.md`. |
| PE-004 | ~~Wire 2 TODO submit buttons in Daily Report (35A)~~ | 13 — complete | ✅ Closed — 35A archived 2026-03-29 | — |
| PE-005 | ~~Fix 6 dead navigation buttons on Office Dashboard (66A)~~ | 13 — complete | ✅ Closed — 66A already complete; archived 2026-03-29 | — |
| PE-006 | 67A: Pass real userId to createAuditSession + autoSaveToJobNotebook | 13 — complete | ✅ Fixed directly (2026-03-29) | IOSAuditSetupView + IOSMessageThreadView |
| PE-007 | Test coverage gaps: PeopleService 38%, ChatService 42%, SettingsService 43% | 7 — fine-tune | Open | test-coverage-maintenance agent |
| PE-008 | ~~Security core fixes~~ **ALL DONE** — unsigned tokens, brute-force, hardcoded salt banner, LAN HTTP encrypt, export guard | 13 — complete | ✅ All 5 sub-items closed — a/b: b3eef3b, c: 0b17c10, d: 0fb2dbf, e: 4b0c71a. GitHub #9 closed 2026-04-01 |
| PE-021 | ~~Session token signing key is ephemeral~~ **FIXED** — Keychain-backed 256-bit key, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | 13 — complete | ✅ Fixed cebf4e4 — #16 closed | AuthService.swift:659 |
| PE-009a | ~~Dynamic Type: 83 hardcoded fonts~~ **FIXED** — semantic text styles across all feature views (GitHub #11 closed) | 13 — complete | ✅ Fixed directly 38ca2bb | 160+ view files |
| PE-009b | ~~12 undersized tap targets~~ **DONE** — all 13 locations fixed (direct edits 38ca2bb + `.contentShape(Rectangle())` pass 2026-04-02). GitHub #12 closed. | 13 — complete | ✅ Prompt archived to `done/`. All tap targets verified ≥44×44pt. |
| PE-009c | ~~Swipe-to-delete confirmations~~ **DONE** — all 5 files verified (IOSReportsRouter, PreTrip, AddNotebook, WarehouseWizardStep2, ClockOut); all use confirmation pattern | 13 — complete | ✅ Prompt archived to `done/`. GitHub #13 confirmed resolved. |
| PE-009d | ~~Color-only status indicators~~ **FIXED** — text labels added on Audit, PODetail, Forecasting, Spending (GitHub #15 closed) | 13 — complete | ✅ Fixed directly 38ca2bb | — |
| PE-009e | ~~Accessibility labels~~ **FIXED** — 347 `.accessibilityLabel()` + 305 `.accessibilityHidden()` across 160+ views (GitHub #14 closed) | 13 — complete | ✅ Fixed directly 38ca2bb | — |
| PE-022 | ~~GitHub #17: Hat assignment discoverability~~ **DONE** — HatDetailSheet, AddEmployeeToHatSheet, People Dashboard Management tiles, EmployeeDetail Permissions Granted section | 13 — complete | ✅ iOS implemented 3db6dd1 (2026-03-31). Prompt archived to `done/`. GitHub #17 closed 2026-04-01. |
| PE-010 | `createAuditSession()` silently dropped zone/sampleSize/notes | 13 — complete | ✅ Migration 061 adds columns; SQL insert updated | Option A chosen |
| PE-011 | 12 force unwraps in `ReportDateRange.swift` | 13 — complete | ✅ Fixed in commit 4b0c71a — guard/let + addingTimeInterval fallbacks | Closed |
| PE-012 | `Calendar.current.date(byAdding:)!` in 15 files | 13 — complete | ✅ Fixed in commit 4b0c71a — all 15 files updated to addingTimeInterval | Closed |
| PE-013 | ~~Unplanned: `WarehouseLocationsPage` drag-and-drop floor plan + `StorageUnitDetailSheet` nav path~~ **DOCUMENTED** in ios-warehouse-pages.md lines 309-325 | 13 — complete | ✅ Documented (plan-enforcer 2026-03-29); confirmed this run | — |
| PE-023 | ~~DashboardService + BreakService weak test assertions~~ — **FIXED** | 13 — complete | ✅ Fixed 2026-03-31 — 9 Dashboard + 4 Break assertions now seeded with real data |

---

## PE-002 Resolution Notes

**All Phase 1 prompts archived to `done/` as of 2026-03-29.** GRDB fully removed from all iOS files. All 35A-35I, 66A-66C prompts complete or skipped as moot.

---

## Next Up (Priority Order)

> **Phase 3 underway.** Q&A: 4 pending (DIS-005, DIS-007). Tests: 970/970. 5 Xcode prompts ready. PE-003 core done — Flex Pool UI prompt still needed.

1. 🚨 **Trigger PE-031 (Clock GPS banner)** — `xcode-ai/fix-prompts/PE-031-clock-fix-ios.md` — core fixes confirmed in code; iOS UI permission banner + alreadyClockedIn recovery alert still needed. Workers may still be confused without visual GPS guidance.
2. **Trigger PE-034 (Quick UX fixes)** — `xcode-ai/fix-prompts/PE-034-dis-quick-ui-fixes.md` — DIS-001 loading indicators, DIS-002 pull-to-refresh, DIS-003 sheet detents, DIS-004 timer lifecycle.
3. **Trigger PE-027 (Part number UI)** — `xcode-ai/fix-prompts/PE-027-part-number-hierarchy.md` — migration 065 done; catalog color row UI pending.
4. **Trigger PE-029 (Price chips in catalog)** — `xcode-ai/fix-prompts/PE-029-pricing-ui.md` — CascadePriceEditSheet done; catalog integration pending.
5. **Trigger PE-030 (Warehouse setup redesign)** — `xcode-ai/fix-prompts/PE-030-warehouse-setup-redesign.md` — nothing implemented yet; complex multi-step.
6. **Write Xcode prompt for PE-003 (Flex Pool UI)** — Core done (migration 071 + service methods + tests). Need prompt for Scheduling tab "Flex Pool" third tab.
7. **Answer DIS-005 and DIS-007 Q&A** — 4 questions pending in `docs/dev-qa.md`. Owner needs to answer before fixes proceed.
8. **Improve test coverage** — PeopleService (~22/47), ChatService (~14/33), SettingsService (~17/40).

---

## Backlog

> Sorted by priority. Phase 1 Xcode prompts ALL complete. Backlog is now HIG + security only.

| Priority | Item | Source | Step | Blocked By |
|----------|------|--------|------|------------|
| — | ~~PE-009b — tap targets (12 undersized)~~ **DONE** 2026-04-02 | Accessibility | 13 | ✅ Closed — all locations ≥44×44pt |
| — | ~~PE-009c — swipe-to-delete confirmations~~ **DONE** 2026-04-02 | Data safety | 13 | ✅ Closed — all 5 files confirmed |
| 1 | **Answer PE-003 Q&A** — 5 questions for flex pool | Plan alignment | 3→4 | Owner fills in answers |
| 4 | ~~PE-022 — Hat assignment UX~~ **DONE** 3db6dd1 | UX bug | 13 | ✅ Closed 2026-04-01 |
| 5 | ~~PE-001 — Tool naming rename~~ **DONE** | Plan alignment | 13 | ✅ Closed 2026-03-31 |
| 6 | ~~PE-008c — Legacy PIN banner~~ **DONE** 0b17c10 | Security | 13 | ✅ Closed 2026-03-31 |
| 7 | ~~Strengthen PE-023 test assertions~~ **DONE** | Quality | 13 | ✅ Closed 2026-03-31 |
| — | ~~PE-009a — Dynamic Type~~ **DONE** 38ca2bb | Accessibility | 13 | ✅ Closed |
| — | ~~PE-009d — color-only indicators~~ **DONE** 38ca2bb | Accessibility | 13 | ✅ Closed |
| — | ~~PE-009e — accessibility labels~~ **DONE** 38ca2bb | VoiceOver | 13 | ✅ Closed |
| — | ~~Fix PE-008a — unsigned session tokens~~ **DONE** b3eef3b | Security (high) | 13 | ✅ Closed |
| — | ~~Fix PE-008b — no brute-force protection on PIN~~ **DONE** b3eef3b | Security (high) | 13 | ✅ Closed |
| — | ~~Fix PE-021 — ephemeral token signing key~~ **DONE** cebf4e4 | Security (medium) | 13 | ✅ Closed |
| — | ~~Fix PE-008d — LAN sync plain HTTP~~ **DONE** 0fb2dbf (X25519+AES-GCM) | Security (medium) | 13 | ✅ Closed |
| 9 | Write test coverage for PeopleService (47 methods, ~18 tested) | Quality | 7 | test-coverage-maintenance |
| 10 | Write test coverage for ChatService (33 methods, ~14 tested) | Quality | 7 | test-coverage-maintenance |
| 11 | Write test coverage for SettingsService (40 methods, ~17 tested) | Quality | 7 | test-coverage-maintenance |

---

## Recently Completed

| Date | What | Step Completed | Commits |
|------|------|----------------|---------|
| 2026-03-29 | **Phase 1 COMPLETE** — all 279 Xcode AI prompts archived in `done/` | Steps 10-13 | 740f480 |
| 2026-03-29 | PE-011 fixed: ReportDateRange.swift 12 force unwraps → guard/let + fallbacks | Steps 8-13 | 4b0c71a |
| 2026-03-29 | PE-012 fixed: Calendar force unwraps in 15 iOS files → addingTimeInterval() | Steps 8-13 | 4b0c71a |
| 2026-03-29 | PE-008e fixed: IOSDataExportPage export guard (export_reports permission) | Steps 9-13 | 4b0c71a |
| 2026-03-29 | PE-009c partial: swipe-to-delete confirmation in IOSReportsRouter | Steps 9-10 | 4b0c71a |
| 2026-03-29 | WarehouseLocationsPage: drag-and-drop floor plan + navigation path in detail | Steps 5-13 | 4b0c71a |
| 2026-03-29 | AuthService/SettingsService: `isTableNotFoundError` helper extracted | Steps 8-13 | 4b0c71a |
| 2026-03-29 | IOSClockPage: flex pool dispatch failure → visible errorMessage (silent→ UX) | Step 8 | 740f480 |
| 2026-03-29 | Fix PE-006 (67A): userId attribution in audit session + notebook auto-save | Steps 10-13 | Direct iOS fix |
| 2026-03-30 | PE-008a: HMAC-SHA256 token signing (#6 closed) | Step 13 | b3eef3b |
| 2026-03-30 | PE-008b: PIN brute-force lockout exponential backoff (#7 closed) | Step 13 | b3eef3b |
| 2026-03-30 | PE-020 closed: `counted_qty` + discrepancy calc + 3 audit tests (#4 B1/B2, prompt archived) | Steps 5-13 | 1eb051f + cebf4e4 |
| 2026-03-30 | PE-021 closed: Keychain-backed token signing key (GitHub #16 closed) | Steps 9-13 | cebf4e4 |
| 2026-03-30 | dev-improvement-scanner: 4 force unwraps fixed in core (BackgroundTaskService, ToolsService, AITools, BaseRepository) — 759/759 tests passing | Steps 6-8 | — |
| 2026-03-29 | 68 SQL bugs fixed total, 736 tests, all Phase 1 Xcode prompts done | Steps 5-7, 12-13 | Multiple |
| 2026-04-02 | **dev-improvement-scanner run 5**: Found `IOSContactDetailPage.loadData()` + `EditContactSheet.loadContact()` fetching entire contacts table to find a single contact by ID. Fixed: added `PeopleService.getContact(id:)` (parameterized `WHERE id = ? LIMIT 1` on indexed PK), updated both call sites, added 1 test (`testGetContactById`). Full sweep: 0 force unwraps, 0 force casts, 0 deprecated NavigationView, 0 missing empty states. | Steps 6-8 | Direct fix |
| 2026-04-03 | **dev-improvement-scanner run 6**: Full scan of 14 modified core services (AIDispatch, BackgroundTask, Break, Chat, Dashboard, Fleet, JobEstimation, Notebooks, Orders, Reports, Scheduling, Tools, Warehouse, Wishlist) + AppCore.swift + 2 test files (JobsServiceTests, NotebooksServiceTests). **1 bug fixed:** `BreakService.getRoundedTime()` line 422 — `TimeZone(identifier: "UTC")!` → `?? TimeZone(secondsFromGMT: 0)`. **0 force casts, 0 as!, 0 NavigationView, 0 SQL injection, 0 swallowed errors.** ToolsService dynamic-column SQL confirmed safe via allowedFields allowlist. Division-by-zero confirmed guarded in all paths. UX scan confirmed Settings page ForEach loops use static option arrays — no empty states needed. 0 new GitHub issues. | Steps 6-8 | BreakService.swift |
| 2026-04-04 | **dev-improvement-scanner run 8**: Scan of recently-modified files. **3 direct fixes:** `SchedulingService.swift` 2 post-insert force unwraps (`template.id!`, `holiday.id!`) → `guard let` with typed errors; `BadgeCountManager.refresh()` 3-second debounce added. **2 new DevTODOs:** DIS-006 (WishlistService sync main-thread writes), DIS-007 (IOSMainView NotificationCenter closure lifetime). Confirmed: all timers safe, all lists have `.refreshable`, 0 force casts, 0 deprecated NavigationView. | Steps 6-8 | SchedulingService.swift + BadgeCountManager.swift |
| 2026-04-04 | **dev-improvement-scanner run 7**: 4-agent parallel scan (runtime safety, UX, security, HIG). **8 direct fixes:** PartsService healthScore division-by-zero guard (minStock==targetStock path); SettingsService.exportTable uses DB-validated table name; NotebooksService conflict resolver uses literal-backed column map; `.gitignore` now blocks `.env`/`credentials.json`/`token.json`; AI panel 7 icon buttons given `.accessibilityLabel` (was `.help()`-only, iOS no-op); Notebook context menus now show `confirmationDialog` before deleting groups/sections/entries; NotebookTemplates swipe-delete now shows confirmation; QRLabelPrintSheet + IOSStagingPage Clear buttons now carry `.role(.destructive)`. **5 DevTODOs created** (DIS-001 to DIS-005) for items needing Xcode work: loading indicators on 3 pages, pull-to-refresh on Daily Report Templates, `.presentationDetents` on 7 sheets, DashboardDailyReportPage timer leak, CompanySetupWizard UserDefaults PII. `gh` not available — GitHub issues to be filed manually. | Steps 6-9 | 9 files modified |
| 2026-04-04 | **plan-enforcer run 5**: Audited 10 active plans vs code. **4 plans confirmed DONE (tracker was stale):** PE-026 (BadgeCountService+Manager live, IOSMainView wired), PE-028 (brand_supplier carry_status + bidirectional UI done), PE-032 (migration 069 + IOSScheduleConfigPage 823 lines with all sections), PE-033 (migration 070 + WishlistService + IOSWishlistPage 3-section). **2 partial:** PE-031 (core clock fixes done — 24 guards + alreadyClockedIn; UI banner pending), PE-029 (CascadePriceEditSheet done; catalog integration pending). **2 NOT started:** PE-030 (warehouse redesign), PE-003 (flex pool). **1 unplanned addition:** `PricingOverrideFlow.swift` (no plan reference — hierarchy-level price override flow). Plan Registry updated with 10 new entries. | Steps 11-12 | docs only |
| 2026-04-04 | **plan-enforcer run 4**: Audited PE-025 commit (826dd18) — all 3 plan items confirmed implemented ✅. **Drift noted:** CategoriesTreeView @Binding fix (partial #46 impl) bundled into PE-025 commit — retroactively documented in `ios-categories-page.md` §#46. **PE-003 Q&A confirmed fully answered** — advanced from Step 3→4, plan updated in `ios-scheduling-pages.md` §6. **PE-026 written** for badge counts (#50/#51 — all Q&A answered). Archived PE-024+PE-025 to done/. Plan Registry updated. 906 tests passing. | Steps 11-12 | docs only |
| 2026-04-03 | **plan-enforcer run 3**: Audited recent commits. Confirmed: IOSContactDetailPage navigation wired ✅, 3 new JobsServiceTests match schema ✅, QAThreadRow dueDate gap = known/deferred (7 TODOs) ✅. **Bug fixed:** `createBlockEntry` in NotebooksService.swift omitted `notebook_id` from INSERT → `detectBlockConflicts` silently returned empty. Fixed: sub-SELECT resolves `section_id→notebook_id` in same write transaction. +1 regression test `testCreateBlockEntryPopulatesNotebookId`. DevTODO 12-fix-tap-targets.md archived (PE-009b closed). 877 tests in working tree. | Steps 6-7, 11-12 | NotebooksService.swift |
| 2026-04-02 | **plan-enforcer run 2**: Audited 5 unstaged files. Confirmed: PartsCatalogPage MainActor.run concurrency fix, JobsService/PartsService/PeopleService "no such column" resilience, PeopleService.updateContact() + IOSContactDetailPage (unplanned but plan-aligned). Retroactively documented IOSContactDetailPage in ios-people-pages.md §5b. Plan Registry updated. 0 new GitHub issues. | Steps 11-12 | — |
| 2026-04-02 | **hunt-fix iter 19**: Warranty SQL column mismatch fixed in JobsService (warranty_start_date→warranty_start/end across createJob, updateJob, decode). IOSContactDetailPage URL(string:)! force-unwraps fixed. Build clean, 842/842 tests pass. | Steps 6-7 | Working tree (uncommitted) |
| 2026-04-02 | **test-coverage-maintenance**: +16 new PartsServiceExt tests (alternatives, price staleness, FIFO consumption history, stock summary, supplier contacts, change log, movement tracing, locations, scheduled deletions) + 2 NotebooksService tests (startWarrantyTimer, getTodosNeedingReview). Projected: 860 tests. | Step 7 | Working tree (uncommitted) |
| 2026-04-02 | **IOSContactsPage wired**: `.navigationDestination(for: Int64.self)` added to push `IOSContactDetailPage`. IOSContactDetailPage.swift is new untracked file. | Step 5 | Working tree (uncommitted) |
| 2026-04-02 | PE-009b CLOSED: all 13 tap targets ≥44×44pt (direct edits 38ca2bb + contentShape pass). Prompt archived. GitHub #12 resolved. | Steps 11-13 | prompt-results-log |
| 2026-04-02 | PE-009c CLOSED: all 5 swipe-to-delete files confirmed with candidate+dialog pattern. Prompt archived. GitHub #13 resolved. | Steps 11-13 | prompt-results-log |
| 2026-04-02 | Stale DevTODO cleanup: removed 9-legacy-pin-salt.md, 10-lan-sync-encryption.md, PE-023-strengthen-dashboard-break-tests.md (all backed by closed GitHub issues or closed PEs) | Step 13 | cleanup |
| 2026-04-01 | **github-issues-sync run 2**: 0 open issues, 17/17 closed verified. PE-009b/009c remaining work tracked via Xcode prompts (no new issues needed). IOSJPOCreationPage:209 "dead button" confirmed intentional (alert dismiss is sufficient). No new issues filed. | Step 13 | — |
| 2026-04-01 | PE-022 CLOSED: HatDetailSheet + AddEmployeeToHatSheet + People Dashboard Management + EmployeeDetail Permissions Granted. GitHub #17 closed. | Steps 10-13 | 3db6dd1 |
| 2026-04-01 | PE-001 CLOSED: Tool Registry → "All Tools", Tool Admin → "Management" in 4 files. Prompt archived. | Steps 10-13 | Prompt archived |
| 2026-04-01 | PE-008 ALL CLOSED: Legacy PIN banner in IOSPermissionsPage (PE-008c). Auto-migrate on login already in place. GitHub #9 closed. | Steps 9-13 | 0b17c10 |
| 2026-04-01 | +14 new tests: 12 FleetServiceTests (telematics, vehicle tools, fuel, trailer, inspection, reports), 2 PeopleServiceTests (payment status) | Step 7 | c06622c |
| 2026-03-31 | PE-009a closed: 83 hardcoded fonts → semantic styles (GitHub #11 closed) | Steps 9-13 | 38ca2bb |
| 2026-03-31 | PE-009c partial: 3 of 5 swipe-to-delete confirmations added (PreTrip, AddNotebook, ClockOut) | Step 10 | 38ca2bb |
| 2026-03-31 | PE-009d closed: color-only indicators fixed with text labels on Audit/PO/Forecasting/Spending (GitHub #15 closed) | Steps 9-13 | 38ca2bb |
| 2026-03-31 | PE-009e closed: 347 accessibilityLabel + 305 accessibilityHidden across 160+ views (GitHub #14 closed) | Steps 9-13 | 38ca2bb |
| 2026-03-31 | GitHub #14 and #15 closed by plan-enforcer | Step 13 | — |
| 2026-03-31 | dev-improvement-scanner run 2: 9 force unwraps fixed across PartsService (5), NotebooksService (1), PeopleService (1), JobsService (1), OrdersService (1), SettingsService (1). Build clean. PE-023 filed. | Steps 6-8 | — |
| 2026-03-31 | PE-022 (GitHub #17): hat discoverability triaged, `ios-hat-assignment-ux.md` plan written, 5 Q&A questions generated in `dev-qa.md`. Commit 4e0d5e0 security fix (user_hats deleted_at filter, 10 invisible permission keys fixed, 790/790 tests) logged. | Steps 1-3 | — |
| 2026-03-31 | PE-008d CLOSED: X25519 ECDH + AES-GCM payload encryption on all LAN sync HTTP (0fb2dbf). Backward-compatible. 6 new crypto tests. | Steps 9-13 | 0fb2dbf |
| 2026-03-31 | PE-009b partial direct fix: 13 tap targets expanded to ≥44×44pt across 10 iOS files (38ca2bb + working tree uncommitted). Prompt `PE-009b-tap-targets.md` may be archivable if coverage verified complete. | Steps 11 | 38ca2bb + wt |
| 2026-03-31 | DashboardService: 2 SQL column bugs found in working tree — `suppliers.contact_email` (actual: `email`) and `po_line_items.quantity` (actual: `qty_ordered`). Unstaged — needs commit. | Step 6 | WIP |
| 2026-03-31 | dev-improvement-scanner run 3: 2 force unwraps (BaseRepository:129, ConflictResolver:493 → compactMap). 4 hardcoded userId bugs fixed: AITools (userId:0→real, threaded through chatWithTools+IOSAIAssistantPanel), QRScanner (userId:1×2 → appCore.currentUser?.id). 5 files changed. 790 tests passing. | Steps 6-8 | — |
| 2026-03-31 | **PE-022 Q&A processed**: all 5 owner answers integrated into `ios-hat-assignment-ux.md` plan. Q&A removed from `dev-qa.md`. `getHatMembers(hatId:)` + `HatMember` struct added to PeopleService. Xcode prompt `PE-022-hat-assignment-ux.md` written — covers HatDetailSheet, AddEmployeeToHatSheet, People Dashboard Management tiles, EmployeeDetail Permissions Granted section. | Steps 3-10 | — |

---

## Plan Registry

> Every plan in `docs/plans/` tracked with implementation status.
> Last updated by plan-enforcer: 2026-04-04 (run 5)

| Plan File | Area | Lifecycle Step | Coverage | Notes |
|-----------|------|---------------|----------|-------|
| `ios-badge-counts.md` | Cross-cutting | Step 13 — complete ✅ | **Full** — `BadgeCountService.swift` (307 lines) + `BadgeCountManager.swift` wired as EnvironmentObject. IOSMainView uses `.badge()`. Prompt PE-026 archived to `done/`. | PE-026 DONE 2026-04-04 |
| `ios-wishlist-enhancements.md` | Orders | Step 13 — complete ✅ | **Full** — Migration 070 + WishlistModels + WishlistService (`getSectionedItems`, `processAutoApprovals`, `dismissItem(reason:)`) + IOSWishlistPage 3-section layout. | PE-033 DONE 2026-04-04 |
| `ios-clock-fix.md` | Jobs | Step 10 (Xcode prompt ready) | **Partial** — Core fixes done: 24 `isTableNotFoundError` guards in JobsService, `alreadyClockedIn` recovery handler in IOSClockPage. iOS UI: GPS permission banner + visual recovery still pending via PE-031. | PE-031 prompt at `fix-prompts/PE-031-clock-fix-ios.md` |
| `ios-fresh-install-resilience.md` | Cross-cutting | Step 7 (fine-tune) | **Partial** — Priority 1 (clock page crash) fixed. Most services have `isTableNotFoundError` guards (24 in JobsService, 3-29 in all other services). Empty-result crashes (tables exist but no rows) not yet fully addressed for gated pages. | Broad improvement; remaining gaps are UX-level (empty states, gated pages) |
| `ios-brands-suppliers-editing.md` | Parts | Step 13 — complete ✅ | **Full** — Migration 066 adds `carry_status` to `brand_supplier_links`. Service methods in PartsService. UI in PartsBrandsPage + PartsSuppliersPage. Schema drift: plan said new `brand_supplier_relationships` table; implementation extends existing `brand_supplier_links` (functionally equivalent). | PE-028 DONE 2026-04-04 |
| `ios-pricing-ui.md` | Parts | Step 10 (Xcode prompt ready) | **Partial** — `CascadePriceEditSheet.swift` (359 lines) wired in CategoriesTreeView. Unplanned: `PricingOverrideFlow.swift` adds hierarchy-level override (no plan ref). Catalog color row price chips pending via PE-029. | PE-029 prompt at `fix-prompts/PE-029-pricing-ui.md` |
| `ios-warehouse-setup-redesign.md` | Warehouse | Step 10 (Xcode prompt ready) | **Partial** — `WarehouseSetupTier` enum (none/partsOnly/floorPlanInProgress/complete) + `getSetupProgress()` exist in WarehouseService. `WarehouseDashboardPage` uses `setupTier` to show context-appropriate setup banners. Missing: two independent flows (parts-only vs floor-plan), drag-and-drop unit placement, cart mode, resume flow from last tier. Prompt at `fix-prompts/PE-030-warehouse-setup-redesign.md`. | PE-030 partial; needs Xcode prompt |
| `ios-schedule-config-redesign.md` | Scheduling | Step 13 — complete ✅ | **Full** — Migration 069 adds `shift_templates` + `company_holidays`. IOSScheduleConfigPage.swift (823 lines) has: company work hours, shift templates per hat, holiday calendar, dispatch rules, supervisor hat assignment. | PE-032 DONE 2026-04-04 |
| `ios-flex-pool.md` | Scheduling | Step 10 (Xcode prompt needed) | **Partial** — Migration 071 adds `is_flex_pool`/`flex_pool_team_filter`/`flex_pool_user_filter` to jobs ✅. `FlexPoolJob` struct in SchedulingModels ✅. `fetchFlexPool(userId:)`, `claimFlexJob(jobId:userId:)`, `markJobFlexPool` in SchedulingService ✅. 6 tests passing ✅. **Missing:** Xcode prompt for Scheduling tab "Flex Pool" tab UI. | PE-003 core DONE 2026-04-04 — UI prompt pending |
| `ios-part-number-hierarchy.md` | Parts | Step 10 (Xcode prompt ready) | **Partial** — Migration 065 adds `part_number` to colors table. `PartsModels.PartColor.partNumber` exists. Catalog UI (color row display + edit) pending via PE-027. | PE-027 prompt at `fix-prompts/PE-027-part-number-hierarchy.md` |
| `ios-scheduling-pages.md` | Scheduling | Step 4 (Q&A answered) | **Partial** — 14/14 files exist; flex pool UI pending. PE-003 Q&A fully answered (2026-04-04) — needs `is_flex_pool` migration + SchedulingService methods before Xcode prompt. Plan updated with Q&A decisions (§6). | Original plan said Dashboard; Q&A overrides to Scheduling tab |
| `ios-jobs-pages.md` | Jobs | Step 10 (prompts queued) | **Partial** — all files exist; 45A+ prompts pending (smart cards, AI summary, stage bar) | |
| `ios-people-pages.md` | People | Step 10 (prompts queued) | **Partial** — all files exist + `IOSContactDetailPage` added (2026-04-02, unplanned but aligned); 44A-F pending (dashboard, employee detail rebuild) | GRDB removed ✅; `updateContact()` added to PeopleService |
| `ios-hat-assignment-ux.md` | People/Auth | Step 13 — complete ✅ | **Full** — iOS implemented 3db6dd1 (HatDetailSheet, AddEmployeeToHatSheet, Dashboard Management tiles, Permissions Granted section). GitHub #17 closed. | PE-022 done |
| `ios-fleet-pages.md` | Fleet | Step 10 (prompts queued) | **Partial** — all 17 files exist; 48A-E pending (vehicle detail tabs, pre-trip, trailer mini-warehouse) | Cleanest section — zero GRDB, all service-based |
| `ios-warehouse-pages.md` | Warehouse | Step 10 (prompts queued) | **Partial** — all files exist; 36A-C (floor plan), 37A-D (audit confidence) pending | Onboarding wizard exists (not in plan — added by 65C) |
| `ios-chat-pages.md` | Chat | Step 10 (prompts queued) | **Partial** — all 9 files exist; 42A-D pending (unified inbox, thread info, attachments, escalation) | |
| `ios-tools-pages.md` | Tools | Step 10 (prompts queued) | **Partial** — all 8 files exist; 47A-F pending; naming drift ✅ fixed by PE-001 | Prompt 47F rename already applied |
| `ios-notebooks-pages.md` | Notebooks | Step 10 (prompts queued) | **Partial** — all files exist; 43A-E pending (block-based entries, panel schedule, daily reports) | |
| `ios-office-pages.md` | Office | Step 10 (prompts queued) | **Partial** — all files exist; 50A-D pending (dashboard AI briefing, approvals queue, office chat) | 66A pending: 6 dead buttons on office dashboard |
| `ios-reports-pages.md` | Reports | Step 10 (prompts queued) | **Partial** — all files exist; 49A-D pending (categories, export, fleet/warehouse reports, builder) | Architecturally clean — no GRDB |
| `ios-settings-pages.md` | Settings | Step 10 (prompts queued) | **Partial** — all files exist; 52A-F pending (grouped nav, operations/warehouse/template/functional pages) | |
| `forecasting-page-redesign.md` | Parts/Forecast | Step 11 (audited) | **Full** — all 8 prompts 23A-23H marked DONE | location_stock_targets, target_recommendations, location picker all built |
| `ios-catalog-page.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-categories-page.md` | Parts | Step 11 (audited) | **Partial** — 14A-14G prompts done; **#46 decisions added 2026-04-04**: part numbers at Color level, optional supplier part numbers, per-session tree state (✅ implemented 826dd18 via @Binding), enhanced search. PE-046a/b pending. | Tree state fix committed; part number schema + UI still needed |
| `ios-pricing-system.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-supplier-system.md` | Parts | Step 11 (audited) | **Full** | |
| `ios-jpo-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-jpo-creation-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-purchase-orders-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-procurement-page.md` | Orders | Step 11 (audited) | **Full** | |
| `ios-people-pages.md` | People | Step 10 | **Partial** | (see above) |
| `ios-clock-page-redesign.md` | Jobs | Step 10 | **Partial** — 40A-B pending (to-do picker, live timer) | |
| `inventory-intelligence-system.md` | Parts | Step 11 (audited) | **Partial** — Part A (forecasting) done; Parts B-D (wishlist, procurement, movements) are in Orders/Warehouse pages | |
| `testing-strategy.md` | Quality | Step 7 (fine-tuned) | **Full** — 906/906 passing (2026-04-04). 50+ suites | Coverage gaps: PeopleService (47 methods, ~22 tested), ChatService (33 methods, ~14), SettingsService (40 methods, ~17) |
| `hunt-fix-verify-loop.md` | Quality | Step 7 | **Full** — 22 iterations, 96 bugs fixed | Plan Alignment scanner not yet run in an iteration |
| `ios-foundation-fixes.md` | Cross-cutting | Step 7 | **Partial** — GRDB fully removed ✅; 35A-I still pending in prompt queue | 35C-35I may now be moot — no GRDB found anywhere in iOS app |
| `companion-rules-system.md` | Parts | Step 11 | **Full** | |
| `dashboard-hub-plan.md` | Dashboard | Step 10 | **Partial** — prompts pending for AI summary + smart cards | |
| `ios-import-export-page.md` | Parts | Step 11 | **Full** | |
| `apple-foundation-models-integration.md` | AI | Step 10 | **Partial** — AI panel exists; page context/filters done; deeper integration pending | |
| `ai-assistant-plan.md` | AI | Step 10 | **Partial** — AIDispatchService + AIFilterRegistry exist; AI chat modification flow pending (46E) | |
| `deployment-master-plan.md` | Deployment | Step 5 | **Partial** — 19/23 tasks done; 4 need Mac + physical devices | |
| `bluetooth_sync_expanded.md` | Sync | Step 2 (future) | **Missing** — not yet implemented | Future phase |
| `phase-12-pwa-desktop.md` | Desktop/PWA | Step 2 (future) | **Missing** | Future phase |
| `phase-13-sync-bluetooth.md` | Sync | Step 2 (future) | **Missing** | Future phase |
| `phase-14-ai-integration.md` | AI | Step 2 (future) | **Stub** | Partially implemented by AI assistant work |
| `phase-15-remote-sync.md` | Sync | Step 2 (on hold) | **Missing** | On hold |
| `phase-16-ux-polish-and-admin-hub.md` | UX | Step 2 (future) | **Missing** | Future phase |

---

## Feature Polish Tracker

| Area | Improvement | Impact | Effort | Step | Status |
|------|------------|--------|--------|------|--------|
| SQL Integrity | 13 wrong table/column names across 8 services | Critical — runtime crashes | Quick | 6→7 | ✅ Fixed (Iter 7) |
| SQL Integrity | 8 more schema fixes across 8 services (Iter 8) | Critical — runtime crashes | Quick | 6→7 | ✅ Fixed (Iter 8) |
| Data Integrity | createAuditSession hardcodes started_by=1 — all sessions attributed to admin | Medium — wrong audit attribution | Quick | 7 | ✅ Core fixed; Xcode 67A |
| Data Integrity | autoSaveToJobNotebook hardcodes created_by=1 — wrong note authorship | Medium — bad change tracking | Quick | 7 | ✅ Core fixed; Xcode 67A |
| Runtime Safety | Dead button in IOSJPOCreationPage.swift:209 | Medium — user confusion | Quick | 8 | 🔲 Xcode prompt needed |
| Apple HIG | ~~83 hardcoded font sizes bypass Dynamic Type~~ **DONE** 38ca2bb | High — accessibility | — | 13 | ✅ Fixed — semantic text styles (.caption/.body/.title etc.) across all feature views |
| Apple HIG | ~~12 undersized tap targets~~ **DONE** 38ca2bb + contentShape pass 2026-04-02 | High — touch usability | — | 13 | ✅ All 13 locations ≥44×44pt. PE-009b archived. |
| Apple HIG | ~~Swipe-to-delete confirmations~~ **DONE** — all 5 files confirmed with candidate+dialog pattern | Medium — data safety | — | 13 | ✅ PE-009c verified clean, archived. |
| Apple HIG | ~~Sparse accessibility labels~~ **DONE** 38ca2bb | High — VoiceOver | — | 13 | ✅ Fixed — 347 labels + 305 hidden across 160+ views |
| Apple HIG | ~~9+ color-only status indicators~~ **DONE** 38ca2bb | Medium — accessibility | — | 13 | ✅ Fixed — text labels on Audit/PO/Forecasting/Spending |
| Security | ~~Unsigned session tokens~~ **DONE** | High — auth bypass | Medium | 13 | ✅ Fixed b3eef3b |
| Security | ~~No brute-force protection on PIN login~~ **DONE** | High — account security | Quick | 13 | ✅ Fixed b3eef3b |
| Security | ~~Data export not gated behind admin permission~~ **DONE** | Medium — data exfiltration | Quick | 13 | ✅ Fixed 4b0c71a |
| Security | ~~Hardcoded legacy salt in PIN hashing~~ **DONE** 0b17c10 | Medium — rainbow tables | — | 13 | ✅ Fixed — auto-migrate on login (b3eef3b) + admin banner in IOSPermissionsPage (PE-008c). GitHub #9 closed 2026-04-01 |
| Security | ~~LAN sync uses plain HTTP~~ **DONE** 0fb2dbf | Medium — eavesdropping | — | 13 | ✅ Fixed — X25519 ECDH + AES-GCM, backward-compatible |
| Runtime Safety | 12 force unwraps in ReportDateRange.swift | Medium — crash all date-filtered pages | Quick | 13 | ✅ Fixed (4b0c71a) — guard/let + addingTimeInterval fallbacks |
| Runtime Safety | `Calendar.current.date(byAdding:)!` in 15 files | Low — practically safe | Quick | 13 | ✅ Fixed (4b0c71a) — all 15 files updated |
| IOSClockPage | Flex pool dispatch failure now shows errorMessage instead of silent print() | Low | — | 13 | ✅ Fixed (740f480) |
| Security | Data export not gated behind admin permission | Medium — data exfiltration | Quick | 13 | ✅ Fixed (4b0c71a) — export_reports permission check added |
| Unplanned | WarehouseLocationsPage drag-and-drop + StorageUnitDetailSheet nav path | Medium — UX improvement | Medium | 11 | ⬜ Document in ios-warehouse-pages.md (PE-013) |
| Performance | ~~`IOSContactDetailPage` + `EditContactSheet` full table scan to find one contact by ID~~ **FIXED** — `PeopleService.getContact(id:)` added (O(1) indexed lookup) | Medium — slow with many contacts | Quick | 8 | ✅ Fixed (run 5) |
| Runtime Safety | ~~`BreakService.getRoundedTime()` line 422: `TimeZone(identifier: "UTC")!` force unwrap~~ **FIXED** — replaced with `?? TimeZone(secondsFromGMT: 0)` fallback (non-failable) | Low — "UTC" is always valid but violates no-force-unwrap policy | Quick | 8 | ✅ Fixed (run 6) |
| Runtime Safety | ~~`PartsService.healthScore`: division by zero when `minStock == targetStock`~~ **FIXED** — `guard targetStock != minStock else { return -1.0 }` added | Medium — NaN propagates to sort/display | Quick | 8 | ✅ Fixed (run 7) |
| Security | ~~`SettingsService.exportTable` interpolated caller-supplied `tableName` after validation~~ **FIXED** — uses DB-returned validated name | Medium — structural injection mitigation | Quick | 9 | ✅ Fixed (run 7) |
| Security | ~~`NotebooksService` conflict resolver interpolated `fieldName` after allowedFields check~~ **FIXED** — literal-backed `[String: String]` column map replaces `Set<String>` | Medium — structural injection mitigation | Quick | 9 | ✅ Fixed (run 7) |
| Security | ~~`.gitignore` missing `.env`/`credentials.json`/`token.json`~~ **FIXED** | High — accidental secrets commit not blocked | Quick | 9 | ✅ Fixed (run 7) |
| Accessibility | ~~AI panel 7 icon-only buttons used `.help()` (macOS-only) with no `.accessibilityLabel()`~~ **FIXED** — all 7 buttons in sheet + overlay modes labeled | High — VoiceOver reads "pip", "trash" literally | Quick | 9 | ✅ Fixed (run 7) |
| Data Safety | ~~Notebook context menus (groups/sections/entries) deleted immediately with no confirmation~~ **FIXED** — `PendingDelete` enum + `confirmationDialog` in `IOSNotebookDetailPage` | High — permanent data loss in one tap | Quick | 9 | ✅ Fixed (run 7) |
| Data Safety | ~~Notebook template swipe-delete called `deleteTemplate()` with no confirmation~~ **FIXED** — `confirmationDialog` in `IOSNotebookTemplatesPage` | Medium — templates hard to recreate | Quick | 9 | ✅ Fixed (run 7) |
| Apple HIG | ~~QRLabelPrintSheet "Clear All" + IOSStagingPage "Clear N" missing `.role(.destructive)`~~ **FIXED** | Low — inconsistent with HIG destructive button convention | Quick | 9 | ✅ Fixed (run 7) |
| UX | Missing loading indicators on 3 detail/settings pages (Contractor Detail, Estimation Review, Estimation Settings) — brief empty-state flash before data loads | Medium | Quick | 8 | 🔲 DevTODO DIS-001 |
| UX | `IOSDailyReportTemplatesPage` loads live data but missing `.refreshable` — no retry path | Medium | Quick | 8 | 🔲 DevTODO DIS-002 |
| Apple HIG | 7 sheets missing `.presentationDetents` (IOSContactDetailPage, PartsCatalogPage, IOSHatsPage, IOSMainView ×4) | Medium | Medium | 9 | 🔲 DevTODO DIS-003 |
| Performance | `DashboardDailyReportPage` 60-sec timer continues after view popped — orphan Tasks spawned | Medium | Quick | 8 | 🔲 DevTODO DIS-004 |
| Security | `CompanySetupWizard` stores PII (company name/address/phone/email) in `UserDefaults` | Medium | Quick | 9 | 🔲 DevTODO DIS-005 — verify cleanup on wizard complete |
| Performance | `WishlistService.getSectionedItems()` calls `processAutoApprovals()` synchronously — multiple DB writes on main thread each page load | High | Medium | 8 | 🔲 DevTODO DIS-006 — split auto-approval into background task |
| Performance | `IOSMainView` NotificationCenter `.onReceive` closure captures `tabPrefs`/`appCore` strongly — no deregister on logout | Medium | Quick | 9 | 🔲 DevTODO DIS-007 — confirm lifetime or add explicit cancel |
| Runtime Safety | ~~`SchedulingService` 2 force unwraps: `template.id!` + `holiday.id!` after GRDB insert~~ **FIXED** — guard let with descriptive error | Low | Quick | 8 | ✅ Fixed (run 8) |
| Performance | ~~`BadgeCountManager.refresh()` had no debounce — rapid scene-phase transitions stacked DB reads~~ **FIXED** — 3-second minimum interval added | Medium | Quick | 8 | ✅ Fixed (run 8) |

---

## GitHub Issues

| # | Title | Type | Lifecycle Step | Action | Status |
|---|-------|------|---------------|--------|--------|
| [#4](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/4) | Start up problems (fresh build / onboarding bug report) | Bug (multi-item) | Step 13 | All sub-items fixed: A1-A3 (onboarding flags), C5 (force unwraps), B1/B2 (audit counted_qty), debug DB reset | 🟢 Closed |
| [#5](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/5) | Dead button in JPO Creation | Bug | Step 13 | Closed | 🟢 Closed |
| [#6](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/6) | Unsigned session tokens | Security | Step 13 | FIXED b3eef3b — HMAC-SHA256 token signing + legacy token migration path | 🟢 Closed |
| [#7](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/7) | No brute-force protection on PIN | Security | Step 13 | FIXED b3eef3b — exponential backoff (5s→30s→2min→5min) | 🟢 Closed |
| [#8](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/8) | Data export not gated behind admin | Security | Step 13 | FIXED 4b0c71a — export_reports permission check added | 🟢 Closed |
| [#9](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/9) | Hardcoded legacy salt in PIN hashing | Security | Step 13 | FIXED: auto-migrate on login (b3eef3b) + admin banner in IOSPermissionsPage (PE-008c, 0b17c10) | 🟢 Closed 2026-04-01 |
| [#10](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/10) | LAN sync uses plain HTTP | Security | Step 13 | FIXED 0fb2dbf — X25519 ECDH key agreement + AES-GCM payload encryption; backward-compatible; 6 crypto tests | 🟢 Closed |
| [#11](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/11) | 55 hardcoded font sizes bypass Dynamic Type | Accessibility | Step 13 | FIXED 38ca2bb — 83 hardcoded fonts → semantic text styles; PE-009a archived to done/ | 🟢 Closed |
| [#12](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/12) | 12 undersized tap targets (< 44x44pt) | Accessibility | Step 10 | Closed — verify in Xcode if tap targets are resolved by 38ca2bb; prompt PE-009b still available if needed | 🟢 Closed |
| [#13](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/13) | 5 swipe-to-delete without confirmation | UI | Step 10 | Closed — 3/5 done in 38ca2bb (PreTrip, AddNotebook, ClockOut); 2 remain (ReportTemplates ×2, WarehouseWizardStep2); prompt PE-009c ready | 🟢 Closed (partial — 2 files remain) |
| [#14](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/14) | Sparse accessibility labels (~8/180+ views) | Accessibility | Step 13 | FIXED 38ca2bb — 347 labels + 305 hidden across 160+ views | 🟢 Closed |
| [#15](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/15) | 9+ color-only status indicators | Accessibility | Step 13 | FIXED 38ca2bb — text labels added on Audit/PODetail/Forecasting/Spending | 🟢 Closed |
| [#17](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/17) | No way to add hats to users or change hat permissions | UX Bug | Step 13 | FIXED: PE-022 iOS implementation (3db6dd1) — HatDetailSheet, AddEmployeeToHatSheet, People Dashboard Management tiles, EmployeeDetail Permissions Granted section | 🟢 Closed 2026-04-01 |
| [#16](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/16) | Session token signing key ephemeral — invalidates on restart | Security | Step 13 | FIXED cebf4e4 — Keychain-backed key, survives restarts | 🟢 Closed |
| [#18](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/18) | Login page shows seeded user on clean build | Bug | Step 13 | **RESOLVED** by commit `291ed56` (2026-03-29). `AppCore.resetDatabaseIfNewBuild()` detects new binary (mod date check) and wipes DB + clears onboarding flags. No hardcoded seed found anywhere. Screenshot was from 2026-03-28 (before fix). Closed 2026-04-03. | 🟢 Closed |
| [#19](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/19) | Dashboard shows background task errors on fresh install | Bug | Step 13 | **CLOSED** (2026-04-03). Fixed in commit `52f63d0`. `ChatService.ensureOfficeChannel()` FK violation on empty DB resolved — now skips creation when no users exist and looks up real admin user ID instead of hardcoding 1. | 🟢 Closed |
| [#20](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/20) | Clock In/Out completely non-functional | Bug | Step 10 | **Core fixes confirmed** — 24 `isTableNotFoundError` guards in JobsService, `alreadyClockedIn` recovery handler in IOSClockPage:1151. iOS UI: GPS permission banner + visual recovery alert still needed via PE-031. | 🔴 PE-031 — Xcode prompt ready (EMERGENCY) |
| [#21](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/21) | All modal/sheet popups don't close when Done is tapped | Bug | Step 13 | **CODE-VERIFIED by PE-024 (2026-04-03):** Full audit found all dismiss patterns already correct — struct-level `@Environment(\.dismiss)`, `ActiveSheet` enum, `SheetDismissWrapper`. No SwiftUI conflicts found. May be resolved by earlier HIG work or isolated to a specific context not captured in testing. Needs Xcode rebuild to confirm UX. | 🟡 Open — awaiting Xcode rebuild verification |
| [#22](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/22) | Warehouse Setup Wizard assumes all items on Row 1 | Bug | Step 1 | Design issue — wizard needs layout input from user. Q&A needed. | 🟡 Open |
| [#23](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/23) | Warehouse page — floor plans not showing, missing features | Bug | Step 1 | Complex — multiple sub-issues (floor plans, copy shelves, unplaced parts, orientation). Needs detailed investigation. | 🟡 Open |
| [#24](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/24) | Warehouse Audit scanner non-functional | Bug | Step 1 | Xcode prompt needed after #21 (modal dismiss) is resolved. | 🔴 Open |
| [#25](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/25) | Create Job form needs more fields — convention job activity type | Enhancement | Step 3 | Q&A needed before implementing. | 🟡 Open |
| [#26](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/26) | 10+ pages crash with 'Something went wrong' on empty/fresh database | Bug | Step 7 | **Largely addressed** — `isTableNotFoundError` guards across all services (24 in JobsService, 3-29 in others). `WarehouseSetupTier` progressive logic exists. Remaining: gated pages with "Setup required" UX for unready warehouse/scheduling state. | 🟡 Open — `ios-fresh-install-resilience.md` |
| [#27](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/27) | Trailer Detail Help page incomplete | Enhancement | Step 1 | Low priority — add how-to content to trailer help modal. | 🟡 Open |
| [#28](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/28) | Time Off shows wrong request count — 1 multi-day counted as 3 | Bug | Step 13 | **CLOSED** (2026-04-03). Fixed in commit `52f63d0`. Migration 064 adds `request_group TEXT`. `createTimeOffRequest` assigns shared UUID per request. `listTimeOffRequests` groups by UUID → 1 row per request. `updateTimeOffStatus` cascades to all days in group. | 🟢 Closed |
| [#29](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/29) | Schedule Config page missing critical fields | Bug + Enhancement | Step 13 | **DONE** — Migration 069 adds `shift_templates` + `company_holidays`. `IOSScheduleConfigPage.swift` (823 lines) has: company work hours, shift templates per hat, holiday calendar, dispatch rules, supervisor hat assignment. PE-032 complete. | 🟢 PE-032 CLOSED 2026-04-04 |
| [#30](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/30) | Teams page needs 'requires employees' label | UI | Step 13 | **DONE** — PE-025 closed (826dd18). IOSTeamsPage empty state distinguishes "no teams" vs "no search results". | 🟢 PE-025 CLOSED |
| [#31](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/31) | Edit Tabs layout confusing in sidebar mode | UI | Step 13 | **DONE** — PE-025 closed (826dd18). TabBarEditorView adds sidebar context hint. | 🟢 PE-025 CLOSED |
| [#32](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/32) | Settings Page Layout defaults to wrong mode | UI | Step 13 | **DONE** — PE-025 closed (826dd18). UserMenuSheet shows icon + description + checkmark per layout option. | 🟢 PE-025 CLOSED |
| [#33](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/33) | Office Dashboard missing — no manager command center | Bug + Enhancement | Step 1 | Large feature. Needs plan document. Related to Phase 10+. | 🟡 Open |
| [#34](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/34) | Unified Approvals queue missing | Enhancement | Step 1 | Needs plan document — aggregate all approval types in one page. | 🟡 Open |
| [#35](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/35) | Dispatch Board has zero interactivity | Enhancement | Step 1 | Large feature — drag-and-drop scheduling. Needs plan. | 🟡 Open |
| [#36](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/36) | Receiving back button discards work with no confirmation | Bug | Step 1 | Xcode prompt needed — add dismiss guard with confirmation dialog. | 🔴 Open |
| [#37](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/37) | Standard date filter bar not implemented | Enhancement | Step 1 | Large component — touches 40+ pages. Needs plan. | 🟡 Open |
| [#38](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/38) | Wishlist page is placeholder — migration exists but no functionality | Bug | Step 13 | **DONE** — PE-033 complete. 3-section layout, auto-approve timer, dismiss reason, certainty score. Migration 070 + WishlistService + IOSWishlistPage all implemented. | 🟢 PE-033 CLOSED 2026-04-04 |
| [#39](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/39) | PO creation leaves empty order — no inline line item add | Bug + Enhancement | Step 1 | UX gap — PO creation flow should auto-open line item add. Xcode prompt needed. | 🔴 Open |
| [#40](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/40) | 2 broken sidebar routes — /orders/parts and /orders/wishlist | Bug | Step 13 | Routes ARE present in IOSContentRouter + OrdersRouter. Pages exist. Likely appears broken due to #26 (empty DB crash). Commented on issue. | 🟡 Open — see #26 |
| [#41](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/41) | AI has zero conversation memory — new session per message | Enhancement | Step 1 | Large AI system redesign. Needs plan. | 🟡 Open |
| [#42](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/42) | 20 high-priority UX/feature gaps from plan audit | Enhancement | Step 1 | Aggregate issue — individual items need separate tracking. | 🟡 Open |
| [#43](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/43) | 12 medium-priority issues from plan audit | Enhancement | Step 1 | Aggregate issue — individual items need separate tracking. | 🟡 Open |
| [#44](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/44) | Flex Pool self-assign jobs not implemented | Enhancement | Step 5 | PE-003 — **plan written** `ios-flex-pool.md`. All 5 Q&A answered. Core: DB migration (`is_flex_pool`, filters on jobs table) + SchedulingService (`fetchFlexPool`, `claimFlexJob`, `markJobFlexPool`). Then Xcode prompt PE-026. | 🟡 PE-003 — ready to code core |
| [#45](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/45) | Job cards missing AI summary and stage progression bars | Enhancement | Step 1 | Needs plan document. | 🟡 Open |
| [#46](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/46) | Part Number location — hierarchy resets, part numbers at wrong level | Bug + Design | Step 10 | Migration 065 adds `part_number` to colors table ✅. `PartsModels.PartColor.partNumber` exists ✅. Catalog UI still pending via PE-027. | 🟡 PE-027 — Xcode prompt ready |
| [#47](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/47) | Editing Brands and Suppliers — no way to edit, brand-supplier linking incomplete | Bug | Step 13 | **DONE** — Migration 066 + carry_status + bidirectional UI in PartsBrandsPage/PartsSuppliersPage. PE-028 complete. | 🟢 PE-028 CLOSED 2026-04-04 |
| [#48](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/48) | Parts → Pricing mostly unbuilt in UI | Enhancement | Step 10 | `CascadePriceEditSheet.swift` implemented in CategoriesTreeView ✅. Catalog color row price chips still pending via PE-029. | 🟡 PE-029 — Xcode prompt ready (partial) |
| [#49](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/49) | Warehouse setup — optional, needs work | Enhancement | Step 10 | `WarehouseSetupTier` + `getSetupProgress()` + dashboard banners exist ✅. Two independent flows + drag-and-drop + cart mode pending via PE-030. | 🟡 PE-030 — Xcode prompt ready (partial) |
| [#50](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/50) | No badge counts on nav tabs | Enhancement | Step 13 | **DONE** — `BadgeCountService.swift` (307 lines) + `BadgeCountManager` EnvironmentObject + IOSMainView `.badge()` wired. PE-026 complete. | 🟢 PE-026 CLOSED 2026-04-04 |
| [#51](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/51) | Action buttons not visually prominent | Enhancement | Step 13 | **DONE** — `ActionIndicator.swift` component + `actionRing` modifier created. Integrated with BadgeCountService color-coding. PE-026 complete. | 🟢 PE-026 CLOSED 2026-04-04 |

---

## Agent Health Dashboard

> Tracks if each agent is doing its job effectively.

| Agent | Last Run | Items Found | Items Fixed | Health |
|-------|----------|-------------|-------------|--------|
| hunt-fix-verify | 2026-04-02 (iter 19) | Warranty SQL mismatch in JobsService (silent data loss — `setWarranty`/`isWarrantyActive` read `warranty_start`/`end`, `createJob`/`updateJob` wrote to `warranty_start_date`/`end_date`); IOSContactDetailPage URL(string:)! force-unwraps fixed | All fixed — in working tree | ✅ Healthy |
| test-coverage-maintenance | 2026-04-02 | +16 PartsServiceExt tests (alternatives, price staleness, FIFO consumption, stock summary, supplier contacts, change log, movement tracing, locations, scheduled deletions) + 2 NotebooksService tests (warrantyTimer, todosNeedingReview) = 18 new tests | In working tree — projected total: 860/860 | ✅ Healthy — good momentum; PeopleService/ChatService/SettingsService gaps remain |
| plan-enforcer | 2026-04-02 (run 2) | Audited 5 unstaged files; confirmed all plan-aligned; IOSContactDetailPage documented in ios-people-pages.md §5b; getContact(id:) O(n)→O(1) fix applied | Plan registry updated | ✅ Healthy |
| dev-improvement-scanner | 2026-04-04 (run 8) | Full scan of recently-modified files (WishlistPage, BadgeCountManager, DispatchPage, NotebooksPages, WarehouseDashboard, MainView, WishlistService, SchedulingService). **3 direct fixes:** 2 force unwraps in SchedulingService (`template.id!`→guard, `holiday.id!`→guard), BadgeCountManager debounce (3s min interval). **2 new DevTODOs:** DIS-006 (WishlistService sync main-thread DB writes), DIS-007 (IOSMainView NotificationCenter closure lifetime). Confirmed clean: 0 force casts, 0 deprecated NavigationView, all timers properly invalidated, all lists have `.refreshable`. | 3 direct fixes, 2 DevTODOs | ✅ Healthy |
| dev-pipeline-manager | 2026-04-04 (run 11) | PE-003 core done (migration 071 + flex pool service + 6 tests). DIS-006 direct fix (WishlistService main-thread write removed). PE-034 Xcode prompt written for DIS-001/002/003/004. Q&A added for DIS-005/007. 970/970 tests. | 3 items coded, 1 prompt written, 2 Q&A added | ✅ Healthy |
| github-issues-sync | 2026-04-03 (run 4) | 29 open issues. Closed #28 (time-off grouping), #19 (dashboard errors), #18 (clean build user). Commented on #21 (PE-024 audit) + #30 (Teams empty state staged). Pipeline + issue table updated. | 3 closed, 2 commented, 29 open | ✅ Healthy |
| github-sync-and-review | 2026-04-01 | PE-022 iOS + PE-008c committed and pushed (3db6dd1, 0b17c10) | ⚠️ Working tree now has 10 modified + 1 untracked — needs commit | ⚠️ Pending commit |
| weekly-cleanup | 2026-03-29 (Sun) | 4 .DS_Store files | Removed | ✅ Healthy — next run 2026-04-05 (Sun) |

---

## Pipeline Daily Summary Log

_Appended by dev-pipeline-manager each run._

---

### 2026-04-04 — Dev-Pipeline-Manager Run 11 (PE-003 Core Done, DIS-006 Fixed, PE-034 Written)

**Input:** 7 DevTODO items (DIS-001 through DIS-007) from scanner runs 7 & 8. 0 new GitHub issues (gh unavailable). 0 new plans. Q&A backlog: 0 pending (cleared). Tests: 964/964 at start.

**Step 1 — New input gathered:**
- 7 DevTODOs in `docs/DevTODO/` awaiting routing (4 → Xcode prompt, 2 → Q&A, 1 → direct fix)
- PE-003 Q&A fully answered and plan ready for core work

**Step 5 — Coding dispatched:**

| Action | Files | Category |
|--------|-------|----------|
| Migration 071: `is_flex_pool`, `flex_pool_team_filter`, `flex_pool_user_filter` on jobs table | `AppDatabase+Migrations.swift` | PE-003 DB |
| `FlexPoolJob` struct (Identifiable, Sendable) | `SchedulingModels.swift` | PE-003 model |
| `fetchFlexPool(userId:)` — filtered pool reads | `SchedulingService.swift` | PE-003 service |
| `claimFlexJob(jobId:userId:)` — claim with approval support | `SchedulingService.swift` | PE-003 service |
| `markJobFlexPool(jobId:isFlexPool:teamFilter:userFilter:)` — manager toggle | `SchedulingService.swift` | PE-003 service |
| 6 new flex pool tests | `SchedulingServiceTests.swift` | PE-003 tests |
| DIS-006: Removed `processAutoApprovals()` inline call from `getSectionedItems()` | `WishlistService.swift` | Performance |

**Step 10 — Xcode prompts written:**
- `PE-034-dis-quick-ui-fixes.md` — covers DIS-001 (loading indicators, 3 pages), DIS-002 (pull-to-refresh, templates page), DIS-003 (sheet detents, 7 sheets), DIS-004 (timer leak, dashboard page)

**Step 3 — Q&A generated:**
- DIS-005: 2 questions about UserDefaults PII cleanup in `CompanySetupWizard`
- DIS-007: 2 questions about `IOSMainView` NotificationCenter lifetime across logout

**Agent health this run:**

| Agent | Status | Notes |
|-------|--------|-------|
| hunt-fix-verify | ✅ Healthy | Last run (iter 29) — 964/964 tests |
| test-coverage | ✅ Healthy | Coverage gaps remain: PeopleService/ChatService/SettingsService |
| plan-enforcer | ✅ Healthy | Run 5 (2026-04-04) — 10 plans audited |
| dev-improvement-scanner | ✅ Healthy | Run 8 (2026-04-04) — 3 fixes, 2 DevTODOs |
| dev-pipeline-manager | ✅ Healthy | This run (run 11) |
| github-issues-sync | ✅ Healthy | Run 5 (2026-04-04) — PE-033 written, 7 issue comments |
| github-sync-and-review | ⚠️ Pending | Working tree has 30+ modified files pending commit |
| weekly-cleanup | ✅ Healthy | Next: Sunday 2026-04-05 |

**Gaps found this run:**

| Gap | Severity | Action |
|-----|----------|--------|
| DIS-001/002/003/004 not in Xcode prompt queue | Medium | PE-034 created |
| DIS-005 — PII cleanup needs owner verification | Medium | Q&A added |
| DIS-006 — processAutoApprovals on main thread | High | **Direct fixed this run** |
| DIS-007 — IOSMainView subscription lifetime | Medium | Q&A added (owner needed) |
| PE-003 UI — Flex Pool tab not yet in Xcode prompt | Medium | Core done; UI prompt still needed |
| GitHub DIS-001 through DIS-007 issues never filed | Medium | gh unavailable — file manually |
| PE-003 tracker: still showed "Step 5 — ready to code" | — | Updated to Step 10 |

**Status:**
- Tests: **970/970 passing** (+6 flex pool tests)
- Build: 0 errors, 0 warnings
- Q&A backlog: **4 questions** (DIS-005 ×2, DIS-007 ×2)
- Active Xcode prompts: **5** (PE-031 EMERGENCY, PE-034 NEW, PE-027, PE-029, PE-030)
- Backlog size: 11 items

**Next priority:** PE-031 (GPS banner — EMERGENCY, workers blocked) → PE-034 (quick UX fixes) → PE-027 → PE-029 → PE-030

---

### 2026-04-04 — Dev-Improvement-Scanner Run 8 (3 Direct Fixes, 2 New DevTODOs)

**Scan method:** Full scan of recently-modified files from git status + force-unwrap hunt in core services.

**Direct fixes applied (3 files):**

| Fix | File | Category |
|-----|------|----------|
| `template.id!` → `guard let newId = template.id` + descriptive error | `SchedulingService.swift:1601` | Runtime Safety |
| `holiday.id!` → `guard let newId = holiday.id` + descriptive error | `SchedulingService.swift:1678` | Runtime Safety |
| `BadgeCountManager.refresh()` debounced — 3-second minimum refresh interval added | `BadgeCountManager.swift` | Performance |

**DevTODOs filed (2):**

| ID | Problem | Severity |
|----|---------|---------|
| DIS-006 | `WishlistService.getSectionedItems()` calls `processAutoApprovals()` synchronously on main thread — multiple DB writes block UI per page load | High |
| DIS-007 | `IOSMainView` NotificationCenter closure captures `tabPrefs`/`appCore` strongly — no explicit deregister on logout; confirm view lifetime or add cancel | Medium |

**Confirmed clean (no issues found):**
- 0 force casts (`as!`), 0 deprecated `NavigationView`
- All timers in IOSClockPage and IOSSyncManager properly invalidated in cleanup paths
- All list-heavy views have `.refreshable` (WishlistPage, DispatchPage, NotebooksListPage, WarehouseDashboard)
- No SQL string injection risks — all queries parameterized via GRDB
- No sensitive data in UserDefaults (beyond previously-tracked DIS-005)

**GitHub issues:** `gh` not available — DIS-006/DIS-007 to be filed manually.

---

### 2026-04-04 — Dev-Improvement-Scanner Run 7 (8 Direct Fixes, 5 DevTODOs, Best Safety Haul)

**Scan method:** 4 parallel agents — runtime safety, UX, security, Apple HIG.

**Direct fixes applied (8 files, all production code):**

| Fix | File | Category |
|-----|------|----------|
| `healthScore` division-by-zero when `minStock == targetStock` | `PartsService.swift:2873` | Runtime Safety |
| `exportTable` uses DB-validated name (not caller string) in SQL | `SettingsService.swift:413` | Security |
| Conflict resolver uses `[String: String]` column map (not `Set<String>`) | `NotebooksService.swift:1396` | Security |
| Added `.env`, `.env.*`, `credentials.json`, `token.json` to `.gitignore` | `.gitignore` | Security |
| 7 AI panel buttons: `.accessibilityLabel()` added (was `.help()` only) | `IOSAIAssistantPanel.swift` | Accessibility |
| Notebook group/section/entry context menu deletes → `confirmationDialog` | `IOSNotebookDetailPage.swift` | Data Safety |
| Template swipe-delete → `confirmationDialog` | `IOSNotebookTemplatesPage.swift` | Data Safety |
| "Clear All" + "Clear N" → `.role(.destructive)` | `QRLabelPrintSheet.swift`, `IOSStagingPage.swift` | Apple HIG |

**DevTODOs filed (5):**

| ID | Problem | Xcode Effort |
|----|---------|-------------|
| DIS-001 | Loading indicator missing on 3 pages (contractor detail, estimation review, estimation settings) | Quick |
| DIS-002 | `IOSDailyReportTemplatesPage` has no `.refreshable` | Quick |
| DIS-003 | 7 sheets missing `.presentationDetents` | Medium |
| DIS-004 | `DashboardDailyReportPage` timer fires after nav pop | Quick |
| DIS-005 | `CompanySetupWizard` stores PII in `UserDefaults` — verify cleanup | Quick |

**GitHub issues:** `gh` not available in this environment — DIS-001 through DIS-005 need to be filed manually on GitHub.

**Confirmed clean:** 0 force casts (`as!`), 0 deprecated `NavigationView`, 0 `try!`, 0 `fatalError` in production, 0 unparameterized WHERE clauses with user input, no hardcoded credentials, no `.env` files committed.

---

### 2026-04-03 — GitHub Issues Sync Run 4 (3 Issues Closed, 2 Commented)

**Issues closed (3):**
- **#28** (Time Off wrong count) — Closed. Already fixed in commit `52f63d0` (Migration 064 + `request_group` UUID grouping).
- **#19** (Dashboard background task errors) — Closed. Already fixed in commit `52f63d0` (`ChatService.ensureOfficeChannel` FK violation on empty DB).
- **#18** (Login shows seeded user on clean build) — Closed. Fixed by commit `291ed56` (2026-03-29). `AppCore.resetDatabaseIfNewBuild()` detects new binary via mod-date check and wipes stale DB. No hardcoded seed found.

**Issues commented (2):**
- **#21** — PE-024 audit confirmed all dismiss patterns already correct. Needs Xcode rebuild to confirm UX.
- **#30** — Fix staged in `IOSTeamsPage.swift` working tree (two-case empty state: no data + search-no-results).

**Issues total:** 29 open (was 32 — 3 closed this run). New issues #46-49 Q&A filed in run 3; unchanged.

---

### 2026-04-03 — Dev-Improvement-Scanner Run 6 (1 Force Unwrap Fixed, Full Safety Sweep)

**Input:** Working tree with 14 modified core services, AppCore.swift, and 2 modified test files from recent pipeline runs.

**Findings this run:**

| Finding | Detail |
|---------|--------|
| Force unwrap fixed | `BreakService.getRoundedTime()` line 422: `TimeZone(identifier: "UTC")!` → `?? TimeZone(secondsFromGMT: 0)`. While "UTC" is always valid, the `!` operator violates project no-force-unwrap policy and was unnecessary. Fixed with non-failable fallback. |
| ToolsService SQL injection review | Lines 808, 822, 855 use `\(field)` interpolation into SQL — confirmed **safe**. Both call sites (`editToolWithVerification` and `approveToolEdit`) validate `field` against a `Set<String>` allowlist of 11 known column names before use. Pattern is correct. |
| Division-by-zero audit | All division operators in modified services confirmed guarded: `BreakService` checks `roundingMinutes > 0` at line 409; `DashboardService` uses `budget > 0 ? ...` ternary; SQL uses `NULLIF(col, 0)`; `addMinutes` divides by constant 60. |
| NavigationView scan | 0 deprecated NavigationView found across all 312 iOS Swift files. All navigation uses NavigationStack. |
| SQL string concatenation | 0 SQL built with `+` string concatenation. All queries use parameterized `arguments:` arrays. |
| UserDefaults security | 0 sensitive data (PIN, token, wage, password) stored in UserDefaults. Only onboarding flags (`hasCompletedOnboarding`, etc.) stored. |
| Swallowed errors | All catch blocks in iOS feature pages assign to `loadError`/`actionError`/`errorMessage`/`saveError`. AppCore background tasks log to `backgroundTaskService.failTask()`. No silent swallowing. |
| UX empty states (false positives) | Scanner flagged 7 Settings pages with `ForEach` + no `isEmpty` — all false positives. The `ForEach` loops iterate over static option arrays (`stateOptions`, `viewOptions`, `weightOptions`, `periodOptions`) not user data. No action needed. |
| Test files audit | `JobsServiceTests.swift` (658 lines, ~25 tests) and `NotebooksServiceTests.swift` (1355 lines) both structurally correct. Tests use `E2ETestHelpers.setUp()`, proper `#expect` assertions, real seeded data. No `!` force-unwraps or silently-passing weak assertions found. |

**Actions taken:**
- Fixed `BreakService.swift` line 422 (force unwrap → safe fallback)
- Updated `dev-pipeline.md` Agent Health Dashboard + Feature Polish Tracker + Recently Completed

**Status:**
- **Tests:** 876/876 passing (unchanged)
- **Build:** 0 errors, 0 warnings (unchanged)
- **New GitHub issues filed:** 0
- **Bugs fixed:** 1 (BreakService force unwrap)

---

### 2026-04-03 — Pipeline Manager Run 10 (PE-024 Closed, PE-025 Active, 876 Tests, Q&A Backlog Audit)

**Input:** Working tree from hunt-fix-verify run 25 (4 bugs fixed: print→logger, isTableNotFoundError "no such column" guard, static lockout bleed, resetAllLoginAttempts) + plan-enforcer run 3 (NotebooksService notebook_id fix, 1 regression test) + PE-024 Xcode prompt result (no changes needed).

**Findings this run:**

| Finding | Detail |
|---------|--------|
| PE-024 CLOSED | Full modal/sheet dismiss audit ran — ALL patterns already correct: struct-level `@Environment(\.dismiss)` capture, `ActiveSheet` enum (single `.sheet(item:)`), `SheetDismissWrapper` for complex sheets, no same-hierarchy `.sheet()` conflicts in IOSMainView. "ScanBin popup" from issue description does not exist. Result: no changes made. GitHub #21 code-verified (may have been resolved by prior HIG work). |
| Tests: 876/876 | +14 previously crash-hidden tests are now visible after static lockout bleed fix in E2ETestHelpers. Net count: 862 → 876. All passing. |
| Q&A backlog: 24 questions | Pre-existing: PE-003 (5), #46 (4), #47 (3), #48 (2), #49 (2) = 16. **New this run:** #26 (3), #20 (3), #29 (3) = 8 added. Total: **24 questions across 8 features**. Nothing gets built until owner answers. |
| 3 critical issues advanced to Step 3 | #26, #20, #29 — Q&A generated and added to `dev-qa.md`. Each advanced from Step 1 (ideas in) to Step 3 (Q&A asked). Plan documents will be created after answers received. |
| Working tree uncommitted | 19 modified/untracked files from hunt-fix run 25 + plan-enforcer run 3. github-sync-and-review needs to commit. |

**Agent health this run:**

| Agent | Status | Notes |
|-------|--------|-------|
| hunt-fix-verify | ✅ Healthy | Run 25 — 4 bugs fixed, 876 tests |
| plan-enforcer | ✅ Healthy | Run 3 — NotebooksService notebook_id fix + DevTODO #12 cleanup |
| test-coverage | ✅ Healthy | 876 tests; gaps remain in PeopleService/ChatService/SettingsService |
| dev-improvement-scanner | ✅ Healthy | Last run clean (run 5) |
| github-issues-sync | ✅ Healthy | Last run processed 32 open issues |
| github-sync-and-review | ⚠️ Pending | Working tree needs commit — 19 files |
| dev-pipeline-manager | ✅ Healthy | This run |
| weekly-cleanup | ✅ Healthy | Next run 2026-04-05 (Sunday) |

**Gaps found this run:**

| Gap | Severity | Action |
|-----|----------|--------|
| #26 — fresh DB crash (10+ pages) | **Critical** | Q&A generated — 3 questions in `dev-qa.md`. Plan to be written after answers. |
| #20 — Clock In/Out non-functional | **High** | Q&A generated — 3 questions in `dev-qa.md`. Investigation needed. |
| #29 — Schedule Config redesign | **High** | Q&A generated — 3 questions in `dev-qa.md`. Plan to be written after answers. |
| Q&A backlog growing | Medium | **24 questions across 8 features** (added 8 this run). Owner-blocked. No action until answered. |
| Working tree uncommitted | Medium | github-sync-and-review to handle |
| PeopleService test coverage | Medium | ~22/47 methods tested |
| ChatService test coverage | Medium | ~14/33 methods tested |
| SettingsService test coverage | Medium | ~17/40 methods tested |

**Self-improvement notes:**
- PE-024's clean result validates the `SheetDismissWrapper` and `ActiveSheet` enum patterns introduced in earlier HIG work. When a dismiss helper is architecturally enforced (not just a convention), future sheets automatically inherit correct behavior. This is worth noting as a design win.
- The Q&A backlog has grown from 5 (PE-003 only) to 24 questions (8 features). This run added 8 new questions for 3 critical issues: #26 (fresh DB crash), #20 (clock non-functional), #29 (schedule config). The owner needs to address this to unblock the next wave of work.
- GitHub issue #21 (modal dismiss) is the most significant "investigation finds no bug" result so far. Either the issue was already resolved by prior work, or it's tied to a specific navigation flow not covered by the PE-024 audit. The fact that PE-024 found 0 issues across ALL sheet types (Dashboard, KPI, HATs, MainView) suggests the fix was already in place.

**Actions taken:**
- Closed PE-024 in Active Work Items + fix-order.md
- Activated PE-025 in Active Work Items + fix-order.md
- Updated GitHub #21 status (code-verified, needs Xcode rebuild)
- Updated GitHub #20, #26, #29 status (Step 1 → Step 3, Q&A generated)
- Added Q&A questions for #26, #20, #29 to `dev-qa.md` (8 new questions)
- Updated Master Status (tests 876, prompts, Q&A backlog 24 across 8 features)
- Updated Next Up section (4 priority items)
- Updated Agent Health Dashboard
- Added this Run 10 log

**Status:**
- **Tests:** 876/876 passing
- **Build:** 0 errors, 0 warnings
- **Open GitHub issues:** 32 (#20/#26/#29 advanced Step 1→3; #21 code-verified)
- **Active Xcode prompts:** 1 (PE-025)
- **Q&A backlog:** 24 questions across 8 features (all owner-blocked)
- **Working tree:** 19 modified/untracked — needs commit
- **Backlog size:** PE-025 (active), 7 features (Q&A-blocked), 3 critical (Q&A-blocked, plans pending)

**Next priority:**
1. **Trigger PE-025** — `fix-prompts/PE-025-empty-state-and-settings-ui.md`
2. **Owner answers Q&A** — 24 questions in `docs/dev-qa.md` blocking 8 features (most critical: #26 fresh DB crash)
3. **Commit working tree** — github-sync-and-review agent handles 19 modified files

---

### 2026-04-02 — Pipeline Manager Run 9 (18 New Tests, Warranty SQL Fix, IOSContactDetailPage Wired)

**Input:** Working tree with 10 modified files + 1 untracked (IOSContactDetailPage.swift) from hunt-fix iterations 18/19, plan-enforcer run 2, test-coverage-maintenance, and dev-improvement-scanner run 5.

**Findings this run:**

| Finding | Detail |
|---------|--------|
| Warranty SQL column split | **HIGH severity** — `JobsService` `createJob`/`updateJob`/decode were writing `warranty_start_date`/`warranty_end_date` (migration 003 columns) while `setWarranty`/`isWarrantyActive`/`warrantyDaysRemaining` all read `warranty_start`/`warranty_end` (migration 044 columns). Both column sets exist simultaneously due to schema evolution; data written at creation was never visible to warranty queries. Fixed in working tree. |
| IOSContactDetailPage URL force-unwraps | `URL(string: "tel:...")!` and `URL(string: "mailto:...")!` replaced with conditional binding. Low-impact crash risk removed. |
| 18 new tests | +16 PartsServiceExt (alternatives lifecycle, price staleness, markPriceVerified, FIFO consumption, stock summary, supplier contacts, change log, movement tracing, current locations, scheduled deletions) + 2 NotebooksService (startWarrantyTimer, getTodosNeedingReview). Projected total: **860 tests**. |
| IOSContactsPage wired | `.navigationDestination(for: Int64.self)` added — tapping a contact now pushes `IOSContactDetailPage`. New `IOSContactDetailPage.swift` is untracked. |
| PeopleService SQL resilience | `getContacts()` and `getContactTypeCounts()` wrapped in `do/catch` with `isTableNotFoundError` fallback. Prevents crash on fresh DB. |
| getHatMembers NULL fix | `user_hats` has no `created_at` column — fixed to `NULL AS assigned_at` instead of `uh.created_at`. |
| PartsService.searchCatalog resilience | Wrapped in `do/catch` with `isTableNotFoundError` fallback returning empty result set. |
| isTableNotFoundError extended | Both `JobsService` and `PartsService` extended error check to include `"no such column"` alongside `"no such table"`. |
| PartsCatalogPage concurrency | `isLoading` + `loadError` state mutations moved to `await MainActor.run {}` to satisfy Swift concurrency's actor isolation requirements. |

**Coverage impact (18 new tests):**
- `PartsServiceExt`: alternatives CRUD, price staleness lifecycle, FIFO consumption history, stock summary, supplier contact lifecycle, change log, movement trace, location query, scheduled deletion lifecycle
- `NotebooksService`: warranty timer start/end verification, todos-needing-review classification

**Gaps found this run:**

| Gap | Severity | Action |
|-----|----------|--------|
| Working tree uncommitted | Medium | github-sync-and-review should commit and push |
| PeopleService coverage | Medium | ~20-22/47 methods tested — gap improving; continue coverage runs |
| ChatService coverage | Medium | ~14/33 methods — test-coverage-maintenance next target |
| SettingsService coverage | Medium | ~17/40 methods — test-coverage-maintenance next target |
| PE-003 Q&A | Low | Owner-blocked — 5 questions pending; no action until answered |

**Self-improvement notes:**
- The warranty column split is a textbook schema evolution trap: two migrations add near-identical columns (one with `_date` suffix, one without). The write path was never updated when the read methods were refactored against the newer columns. Solution: always grep for the column name when fixing warranty-related queries.
- 18 new tests this run pushes test count from 842 → 860. The `PartsServiceExtTests` coverage is now very broad — alternatives, pricing, inventory tracing, and scheduled ops are all exercised end-to-end.
- All 8 scheduled agents are healthy. No agent has missed a run window. Q&A backlog has not grown (PE-003 is the only item, unchanged since last run).

**Actions taken:**
- Updated Master Status: tests 860 projected, plan alignment note, working tree warning
- Updated Recently Completed with 4 new entries
- Updated Agent Health Dashboard
- Added this Run 9 log

**Status:**
- **Tests:** 842/842 passing (committed) — **860/860 projected** once working tree commits
- **Build:** 0 errors, 0 warnings
- **Open GitHub issues:** 0
- **Active Xcode prompts:** 0
- **Q&A backlog:** 5 questions (PE-003 flex pool only — owner-blocked)
- **Working tree:** 10 modified + 1 untracked — needs commit
- **Backlog size:** 3 items (1 Q&A-blocked, 2 coverage gaps)

**Next priority:**
1. **Commit working tree** (github-sync-and-review) — 10 files + IOSContactDetailPage.swift
2. **Continue test coverage** — ChatService (33 methods, ~14 tested), SettingsService (40 methods, ~17 tested)
3. **Owner answers PE-003 Q&A** — unblocks flex pool feature + Xcode prompt

---

### 2026-04-02 — Pipeline Manager Run 8 (PE-009b/c Closed, DevTODO Cleanup)

**Input:** Prompt results log (PE-009b contentShape pass SUCCESS, PE-009c audit SUCCESS); stale DevTODO files review; working tree with 12 uncommitted changes

**Findings this run:**

| Finding | Detail |
|---------|--------|
| PE-009b | ✅ CLOSED — prompt-results-log confirms all 13 tap targets are now ≥44×44pt with `.contentShape(Rectangle())`. Direct edits (38ca2bb) expanded frames; 2026-04-01 contentShape pass ensured hit-testing works. Prompt archived to `done/`. |
| PE-009c | ✅ CLOSED — prompt-results-log audit confirms all 5 target files already use `showDeleteConfirmation` + `confirmationDialog`/`.alert` pattern. No changes needed. Prompt archived to `done/`. |
| Stale DevTODO files | Removed 3 files with resolved backing issues: `9-legacy-pin-salt.md` (#9 closed), `10-lan-sync-encryption.md` (#10 closed), `PE-023-strengthen-dashboard-break-tests.md` (PE-023 closed 2026-03-31). Also removed earlier: 11, 13, 14, 15, 16, 8 — all closed. |
| Working tree | 12 files modified/deleted from prior runs — committing all. |

**Self-improvement notes:**
- With PE-009b and PE-009c now done, ALL Phase 2 HIG/security work is complete. The backlog has shrunk to: (1) PE-003 Q&A (owner-blocked), (2) test coverage gaps (agent work). No active Xcode prompts for the first time in the project's history.
- The contentShape pattern is critical for SwiftUI — `.frame(minWidth:minHeight:)` alone expands the *layout* but SwiftUI clips hit-testing to the child's bounds unless `.contentShape(Rectangle())` is added. Future accessibility work should apply both modifiers together.
- DevTODO cleanup: 7 of 10 original DevTODO files have been removed. Remaining: `9-legacy-pin-salt.md` (closed), `10-lan-sync-encryption.md` (closed), `12-fix-tap-targets.md` (updated with results). All remaining reference closed issues — consider clearing folder entirely on next weekly cleanup.

**Actions taken:**
- Closed PE-009b and PE-009c in Active Work Items, Backlog, Feature Polish Tracker, Master Status
- Updated "Next Up" — removed completed prompt items, promoted PE-003 Q&A to priority 1
- Archived PE-009b and PE-009c prompts to `done/`
- Removed 3 stale DevTODO files
- Updated Agent Health Dashboard

**Status:**
- **Tests:** 842/842 passing (54 suites) — no change
- **Build:** 0 errors, 0 warnings
- **Open GitHub issues:** 0
- **Active Xcode prompts:** 0 ← no active prompts for first time
- **Q&A backlog:** 5 questions (PE-003 flex pool only)
- **Backlog size:** 3 items (1 Q&A-blocked + 2 test coverage gaps)

**Next priority:** Owner answers PE-003 Q&A → enables flex pool feature → Xcode prompt written

---

### 2026-04-02 — Dev Improvement Scanner Run 5 (Contact Detail Performance Fix)

**Input:** Full codebase scan — all iOS Swift files + core Swift services

**Key finding:** `IOSContactDetailPage.loadData()` and `EditContactSheet.loadContact()` both called `getContactsSorted(sortBy:typeFilter:)` — a full-table query returning all contacts — then used `.first { $0.id == contactId }` to find the target. This is an O(n) operation where O(1) is available via a primary key lookup.

**Findings this run:**

| Finding | Detail |
|---------|--------|
| Performance bug | `IOSContactDetailPage` + `EditContactSheet` full table scan for single-contact lookup | Fixed directly |
| Runtime safety | 0 force unwraps, 0 force casts, 0 `try!` in entire iOS codebase | Clean ✅ |
| Apple HIG | 0 deprecated `NavigationView`, 0 missing empty states, Dynamic Type in use | Clean ✅ |
| SQL integrity | All services verified clean (working tree fixes from Iteration 19 intact) | Clean ✅ |

**Fix applied:**
- `PeopleService.getContact(id:)` added — `SELECT ... FROM entity_contacts WHERE deleted_at IS NULL AND id = ? LIMIT 1`
- `IOSContactDetailPage.loadData()` updated to use new method
- `EditContactSheet.loadContact()` updated to use new method
- `testGetContactById` test added to `PeopleServiceTests.swift`

**Actions taken:**
- Fixed 2 call sites in `IOSContactDetailPage.swift`
- Added `getContact(id:)` to `PeopleService.swift`
- Added test `testGetContactById` (+1 test, now 843 passing)
- Updated `dev-pipeline.md` Feature Polish Tracker + Agent Health Dashboard
- Updated `hunt-fix-tracker.md` with Iteration 20

**Status:**
- **Tests:** 843/843 passing — +1 new test
- **Build:** 0 errors, 0 warnings
- **Open GitHub issues:** 0
- **New GitHub issues filed:** 0

---

### 2026-04-01 — Dev Improvement Scanner Run 4 (Production Logging Fix)

**Input:** Full codebase scan — 311 iOS Swift files + 65 core Swift files

**Scan results:**

| Scanner | Status | Details |
|---------|--------|---------|
| Runtime Safety (A1) | ✅ PASS | 0 force casts (`as!`), 0 `try!`, 0 `fatalError` in production paths. All force unwraps from PE-011/012 already fixed. |
| Data Integrity (A2) | ✅ PASS | SQL parameterized throughout. `exportTable()` validates name against `sqlite_master`. Notebook field update gated by `allowedFields` Set. SyncEngine table names filtered by `isAllowedTable()` allowlist. |
| Security (B1–B3) | ✅ PASS | Tokens in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). PIN uses SHA-256 ×10,000 + per-user salt (documented tradeoff vs argon2). No sensitive data in UserDefaults. No SQL injection paths. |
| Debug Code (B3) | ⚠️ FIXED | 3 `print()` calls in `PeerDiscovery.swift` not gated by `#if DEBUG` — replaced with `os.Logger` instance + proper `[logger]` capture list to avoid retain cycles. |
| Apple HIG (C1–C4) | ✅ PASS | NavigationStack used everywhere (no deprecated NavigationView). 647 accessibilityLabel annotations across features. 132 `.refreshable` pull-to-refresh. 409+ search locations. 65 destructive role buttons. |
| Dynamic Type (C2) | ✅ PASS | 0 hardcoded font sizes in feature views. `ErrorStateView`/`EmptyStateView` use `@ScaledMetric` correctly. `JobStageProgressBar` micro-font (6/10pt) is a visual affordance, not user content — acceptable. |
| UX Polish (D1–D4) | ✅ PASS | 185/214 feature files have empty state handling. All async views have `isLoading`/`ProgressView`. Jobs list uses default limit of 50 (service-level safeguard). Parts catalog fully paginated. |
| Accessibility (C4) | ✅ PASS | 647 labels / 305 hidden annotations across 214 feature files. ~50% coverage of ~1,294 interactive elements — acceptable given many elements use system accessibility (List rows, NavigationLink, Button). |

**Fix made:**
- `core/Sources/WiredPartCore/Sync/PeerDiscovery.swift` — replaced 3 `print()` calls with `logger.error()` via `Logger(subsystem:category:)` instance; added `import os.log`; used `[logger]` capture list in closures to prevent retain cycle

**No new GitHub issues needed** — all other findings clean or previously tracked.

---

### 2026-04-01 — Pipeline Manager Run 7 (PE-022/001/008c Complete, GitHub Issues All Closed)

**Input:** 3 archived Xcode prompts (PE-022/001/008c), 2 closed-ready GitHub issues (#17, #9), 14 new tests (c06622c)

**Findings this run:**

| Finding | Detail |
|---------|--------|
| PE-022 iOS | ✅ Fully implemented (3db6dd1) — HatDetailSheet + AddEmployeeToHatSheet + People Dashboard Management + EmployeeDetail Permissions Granted |
| PE-001 | ✅ Completed — Tool Registry/Admin renamed in 4 files; prompt archived to `done/` |
| PE-008c | ✅ Completed — Legacy PIN count banner in IOSPermissionsPage; prompt archived to `done/` |
| GitHub #17 | ✅ CLOSED — PE-022 implementation resolves hat assignment discoverability |
| GitHub #9 | ✅ CLOSED — PE-008c + b3eef3b auto-migration fully addresses hardcoded salt; admin banner provides visibility |
| Tests | 842/842 passing (+14 FleetService + PeopleService tests from c06622c) |
| Open issues | **0** — first time all issues closed since tracker began |

**Actions taken:**
- Closed GitHub #17 (hat UX) with implementation summary
- Closed GitHub #9 (hardcoded salt) with two-layer fix explanation
- Updated Master Status, Active Work Items, Backlog, Recently Completed, GitHub Issues table, Agent Health Dashboard

**Status:**
- **Tests:** 842/842 passing (54 suites)
- **Build:** 0 errors, 0 warnings
- **Open GitHub issues:** 0 ← all-time low
- **Q&A backlog:** 5 questions (PE-003 flex pool only)
- **Active Xcode prompts:** PE-009b (next), PE-009c

**Self-improvement notes:**
- PE-022 prompt queue system worked well: Q&A → plan → core method (`getHatMembers`) → Xcode prompt → iOS implementation → close issue. The full lifecycle from issue report (#17, 2026-03-31) to closed took ~1 day.
- With 0 open GitHub issues for the first time, the primary remaining work is: (1) PE-009b/c Xcode prompts user runs, (2) PE-003 Q&A owner answers, (3) PE-007 test coverage gaps. The project is in excellent health.
- Pattern: PE-008 security suite took 5 sub-items over 4 days to close. Grouping related security items as lettered sub-items (a/b/c/d/e) under a single PE number worked well — visible progress without fragmentation.

**PEs closed this run:** 0 new PEs (all closures were previously initiated)
**GitHub issues closed:** 2 (#17, #9)
**Tests:** 842/842 (no change this run — +14 in prior c06622c)
**Backlog size:** 4 active items (2 ready-to-run prompts + 1 Q&A blocked + 1 test coverage)
**Next priority:** User runs PE-009b in Xcode (tap targets) → PE-009c → owner answers PE-003 Q&A

---

### 2026-03-31 — Pipeline Manager Run 6 (PE-022 Prompt Written, PE-023 Closed, PE-001 Applied)

**Input:** 5 pending work items from run 5

**Work completed this run:**

| Item | Action | Result |
|------|--------|--------|
| PE-023 | Strengthen DashboardService + BreakService test assertions | ✅ 9 Dashboard + 4 Break assertions now use seeded DB fixtures (exact values). Two timezone bugs fixed: `date('now','localtime')` for Calendar.current, `date('now')||'T...'` for formatDateUTC(). 828/828 passing. |
| PE-022 Q&A | All 5 owner answers processed | ✅ Design decisions recorded in `ios-hat-assignment-ux.md`. Q&A removed from `dev-qa.md`. |
| PE-022 core | `PeopleService.getHatMembers(hatId:)` + `HatMember` struct | ✅ Added to PeopleService.swift. SQL: JOIN user_hats ON hat_id, deleted_at IS NULL on both tables. |
| PE-022 prompt | `PE-022-hat-assignment-ux.md` written | ✅ Covers: HatDetailSheet (members + permission summary + add/remove), AddEmployeeToHatSheet, People Dashboard "Management" section (Hats & Roles + Permissions tiles gated on manage_people), Employee Detail "Permissions Granted" section. |
| PE-001 | Tool page rename applied directly | ✅ "Tool Registry" → "All Tools" in IOSToolRegistryPage, IOSToolCheckoutsPage, HelpContentRegistry. "Tool Admin" → "Management" in IOSToolAdminPage. Prompt PE-001-tool-naming-rename.md written for reference. |
| PE-003 | Flex pool Q&A generated | ✅ 5 questions in dev-qa.md (location/tab, who marks flex, skills filter, dispatch_entry, confirmation UX). Xcode prompt blocked until answers. |

**Commit:** 35c1118 — 25 files changed, 1627 insertions, 139 deletions

**Status:**
- **Tests:** 828/828 passing (PE-023 closed)
- **Build:** 0 errors, 0 warnings
- **Q&A backlog:** 5 questions (PE-003 only — PE-022 answered ✅)
- **Xcode prompts ready:** PE-022, PE-001, PE-009b, PE-009c, PE-008c
- **Open GitHub issues:** 2 (#9 hardcoded salt, #17 hat UX)

**Self-improvement notes:**
- Timezone mismatch between SQLite `date('now')` (UTC) and Swift `Calendar.current` (local) caused silent test failures. Two separate patterns needed: (1) seeding for Calendar-based queries → `date('now','localtime')`, (2) seeding for formatDateUTC() queries → `date('now')||'T12:00:00'`. This pattern should be documented.
- PE-001 was already applied by a prior run before this session — the prompts system correctly prevented duplicate work since the files were already modified.

**Next priority:** User runs PE-022 prompt in Xcode → run PE-001 → run PE-009b → owner answers PE-003 Q&A

---

### 2026-03-31 — Plan Enforcer Run 5

**Commits audited:** 0fb2dbf, 4e0d5e0, 38ca2bb (3 recent commits + working tree)

**Plan vs code findings:**

| Finding | Type | Plan | Verdict |
|---------|------|------|---------|
| X25519 ECDH + AES-GCM LAN encryption (0fb2dbf) | Security | PE-008d / phase-13-sync-bluetooth.md | ✅ ALIGNED — closes PE-008d |
| Hat permissions not revoked on soft-delete (4e0d5e0) | SQL bug | ios-hat-assignment-ux.md "Recent security fix" section | ✅ ALIGNED — documented in plan |
| 3 PeopleService SQL bugs (user_hats deleted_at) | SQL bug | feedback_sql_patterns.md pattern | ✅ ALIGNED — hunt-fix pattern |
| 10 invisible permission keys in IOSPermissionsPage | UI bug | PE-022 / ios-hat-assignment-ux.md | ✅ ALIGNED — documented in plan |
| Dynamic Type pass across all feature views (38ca2bb) | HIG | PE-009a / ios-foundation-fixes.md | ✅ ALIGNED — closes PE-009a |
| 13+ tap targets expanded ≥44×44pt (38ca2bb + WD) | HIG | PE-009b / ios-foundation-fixes.md | ✅ PARTIAL — direct edits vs Xcode prompt; verify coverage |
| DashboardService `s.contact_email` → `s.email` (WD) | SQL bug | hunt-fix-verify-loop.md pattern | 🟡 Correct fix, NEEDS COMMIT |
| DashboardService `pl.quantity` → `pl.qty_ordered` (WD) | SQL bug | hunt-fix-verify-loop.md pattern | 🟡 Correct fix, NEEDS COMMIT |
| JobsService `Calendar.date(byAdding:)!` → fallback (WD) | Safety | PE-012 pattern | 🟡 Correct fix, NEEDS COMMIT |
| PartsForecastingPage font size 8 → `.caption2` (WD) | HIG | PE-009a pattern | 🟡 Correct fix, NEEDS COMMIT |

**Unplanned code scan:**
- All working tree changes are aligned with existing plans or hunt-fix patterns
- `ios-hat-assignment-ux.md` (untracked) is a new plan file — needs commit
- `docs/DevTODO/PE-023-strengthen-dashboard-break-tests.md` (untracked) is a valid DevTODO — needs commit
- No unplanned features found requiring design approval

**Q&A pipeline:**
- PE-022 has 5 unanswered questions in `dev-qa.md` — BLOCKED on owner. No code can be written for hat assignment UX until answered.
- `getHatMembers(hatId:)` is still missing from PeopleService — prerequisite for PE-022 Xcode prompt, correctly deferred until Q&A answers received.

**GitHub issues:**
- #10 (LAN plain HTTP) → CLOSED by 0fb2dbf. Updated in registry. ✅
- #17 (hat UX) → still open, correctly blocked on Q&A
- No new issues needed — all gaps tracked in DevTODO or backlog

**Actions taken:**
- Updated Master Status table (working tree count, PE-008d, PE-009b)
- Updated Active Work Items (PE-008 only c remains; PE-009b partial)
- Rebuilt Next Up and Backlog priority order
- Updated Feature Polish Tracker (LAN encryption fixed; tap targets partial)
- Updated GitHub Issues table (#10 closed)
- Updated Agent Health Dashboard
- Added Recently Completed entries (PE-008d, PE-009b partial, DashboardService SQL)

**Next priority:** Commit working tree (23 files) → verify PE-009b coverage → PE-009c → PE-008c

---

### 2026-03-31 — Pipeline Manager Run 5 (Issue #17 → PE-022, Hat Security Fixes Logged)

**Input:** 1 new GitHub issue (#17 — hat assignment/permissions UX), 1 new commit since last run (4e0d5e0), 0 new plans

**Issue #17 analysis:**

| Finding | Detail |
|---------|--------|
| User report | "No way to add a Hat or hats to a user or verify? NO way to change what permissions a hat gives the user" |
| Actual state | `IOSHatsPage` lists hats (create/delete) but rows are NOT tappable — no detail/member view |
| Actual state | `IOSPermissionsPage` has full hat×permission matrix — **functional** |
| Actual state | `IOSEmployeeDetailPage` Hats tab has toggle assignments — **functional** |
| Root cause | **Discoverability**: no tiles for Hats/Permissions on People Dashboard; hat rows not tappable for member management |
| Security fix (4e0d5e0) | `user_hats` missing `deleted_at IS NULL` in 7 auth/people queries — soft-deleted hats still granted permissions. Fixed. |
| Security fix (4e0d5e0) | 10 permission keys invisible in `IOSPermissionsPage` UI — existed in DB but not in hardcoded list. Fixed. |
| Core gap found | `PeopleService.getHatMembers(hatId:)` doesn't exist — needed for hat detail sheet. Plan notes this as a prerequisite. |

**Actions taken:**
- Created `docs/plans/ios-hat-assignment-ux.md` — full plan with design, data flow, files to modify, test plan
- Added PE-022 Q&A block (5 questions) to `docs/dev-qa.md` — blocks Xcode prompt until owner answers
- Updated Active Work Items, Backlog, GitHub Issues table, Plan Registry, Agent Health Dashboard

**Status:**
- **Tests:** 790/790 passing (49 suites) — 4e0d5e0 added 31 new tests
- **Build:** 0 errors, 0 warnings
- **Open issues:** 3 (#9, #10, #17) — all others closed
- **Uncommitted:** staged `DashboardService.swift` + unstaged `BreakServiceTests.swift`, `DashboardServiceTests.swift`, `dev-pipeline.md`

**PEs added this run:** PE-022 ✅ (plan + Q&A created)
**Plans created:** 1 (`ios-hat-assignment-ux.md`)
**Q&A generated:** 5 questions (PE-022)
**Q&A answered:** 0 — owner must fill in
**Backlog size:** 12 open items (5 blocked on PE-022 Q&A)
**Next priority:** Owner answers PE-022 Q&A → run PE-009b in Xcode → fix PE-008c (legacy salt)

**Self-improvement notes:**
- Issue #17 was filed the same day as commit 4e0d5e0 which fixed related hat security bugs. The security layer was already being hardened while the UX gap was being reported — shows the autonomous scanners are catching backend issues while user-visible UX gaps still need user reports to surface.
- Pattern: when a user files an issue saying "X doesn't work", always check if the backend exists before assuming a full feature build. In this case the feature exists, just not discoverable. This saves a full implementation cycle.
- `getHatMembers(hatId:)` is a small prerequisite core addition — these kinds of "half-built" service gaps are easy to miss. Consider adding a scanner that checks if all plan-described UI flows have corresponding service methods.

---

### 2026-03-31 — GitHub Issues Sync Run 3 (PE-008d Fixed, PE-008c Prompt Ready)

**Input:** 3 open issues (#9, #10, #17)

**Actions taken:**

| Issue | Title | Action |
|-------|-------|--------|
| #10 | LAN sync uses plain HTTP | ✅ **Closed** — X25519 ECDH + AES-GCM payload encryption implemented across `SyncCrypto`, `LanSyncServer`, `PeerManager`; backward-compat; 6 new tests |
| #9 | Hardcoded legacy salt in PIN hashing | 🟡 Core fix in place — `getLegacyHashedUserCount()` added; 4 new tests; Xcode prompt `PE-008c-legacy-pin-upgrade.md` written for admin banner UI; issue remains open until Xcode prompt is run |
| #17 | User access controls discoverability | 📝 PE-022 plan unchanged — awaiting owner Q&A answers; comment posted with status |

**Bonus fix (pre-existing BreakService test failure):**
- `autoFillBreaksForDay` used `formatDate` (local TZ) for inserted timestamps but `getBreakRecordsForDay` queries using `formatDateUTC`. Near UTC-midnight, the records would miss the query. Fixed by aligning both to `formatDateUTC`.

**Status:**
- **Tests:** 800/800 passing (up from 759 — +41 tests this session)
- **Build:** 0 errors, 0 warnings
- **Open issues:** 2 (#9 partial, #17 UX backlog)
- **Closed this run:** #10

**Encryption approach:**
- Client fetches server's X25519 public key via `GET /sync/key` (once per peer, cached)
- Client sends `X-Sync-Encrypted: 1` + `X-Sync-Sender-Key: <b64>` headers with AES-GCM encrypted body
- Server derives shared key, decrypts body, processes normally, encrypts response
- Old devices (no `/sync/key`) gracefully fall back to plaintext — no breaking changes

**Next priority:** Owner answers PE-022 Q&A → run PE-009b → PE-009c → PE-008c in Xcode

---

### 2026-03-30 — GitHub Issues Sync Run 2 (3 Xcode Prompts Written, #16 Closed)

**Input:** 8 open issues (#4, #5, #9–#15 + #16). 1 closed (#16 already fixed in cebf4e4).

**Actions taken:**

| Issue | Title | Action |
|-------|-------|--------|
| #16 | Session token signing key ephemeral | ✅ Closed — fixed in cebf4e4 (Keychain-backed key) |
| #11 | 55 hardcoded font sizes | 🟡 Xcode prompt created: `PE-009a-dynamic-type.md` |
| #12 | 12 undersized tap targets | 🟡 Xcode prompt created: `PE-009b-tap-targets.md` |
| #13 | 5 swipe-to-delete without confirmation | 🟡 Xcode prompt created: `PE-009c-swipe-confirmations.md` |
| #9 | Hardcoded legacy salt | 📝 Analysis comment posted — PE-008c, needs forced re-auth for unupgraded users |
| #10 | LAN sync plain HTTP | 📝 Analysis comment posted — PE-008d, ECDH option evaluated |
| #14 | Sparse accessibility labels | ⬜ Needs prompt series (large effort, tracked as PE-009e) |
| #15 | Color-only status indicators | ⬜ Needs prompt (tracked as PE-009d) |
| #4, #5 | Startup bugs / dead JPO button | Unchanged — #4 partial, #5 still needs prompt |

**Status:**
- **Open issues:** 7 (#4, #5, #9, #10, #14, #15 + #4 partial) — #16 closed
- **Xcode prompts ready for user:** PE-009a (fonts), PE-009b (tap targets), PE-009c (confirmations)
- **Security backlog:** PE-008c (legacy salt), PE-008d (LAN HTTP) — both open, core Swift fixes
- **Working tree:** Uncommitted changes (3 prompt files, pipeline update)

**Next priority:** User runs PE-009a → PE-009b → PE-009c in Xcode. Then write PE-009d (color indicators) and PE-009e (a11y labels). Then fix PE-008c + PE-008d in core.

---

### 2026-03-30 — Pipeline Manager Run 4 (PE-020/021 Closed, #16 Closed)

**Input:** 1 new GitHub issue (#16 — token signing key; already fixed in cebf4e4 before issue was filed), 0 new plans, 1 new commit since last run (cebf4e4)

**Changes since last pipeline run:**

| Commit | What |
|--------|------|
| cebf4e4 | PE-021: Keychain-backed token signing key (256-bit, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). PE-020: audit count prompt archived to done/. |

**Status:**
- **Tests:** 759/759 passing (49 suites) — no regressions
- **Build:** 0 errors, 0 warnings
- **Working tree:** Clean — all changes committed and pushed

**PEs closed this run:** PE-020 ✅ (archived prompt), PE-021 ✅ (Keychain signing key)
**GitHub issues closed this run:** #16 ✅
**Plans created:** 0
**Q&A generated:** 0
**Xcode prompts written:** 0
**Tests:** 759/759 passing (unchanged — fixes were core Swift, no new test needed)
**Active open issues:** #4 🟡 (partial), #5 🔴, #9 🔴, #10 🔴, #11 🔴, #12 🔴, #13 🔴, #14 🔴, #15 🔴 (8 open)
**Backlog size:** 14 items (0 blocked on Q&A)
**Next priority:** Write PE-009c prompt (5 remaining swipe-to-delete without confirmation files) and fix PE-008c (hardcoded legacy salt)

**Self-improvement notes:**
- PE-021/#16 was fixed by the hunt-fix agent (cebf4e4) BEFORE the GitHub issue was created — indicating the hunt-fix scanner is ahead of the issue tracker. This is healthy.
- The Feature Polish Tracker still had security items marked as "🔲 Core fix needed" for #6, #7, #8 which were already fixed. Updated to ✅ done.
- Next critical path: PE-008c (legacy salt), then write all Phase 2 Xcode prompts for user to run.

---

### 2026-03-29 — Pipeline Manager Run 3 (Phase 1 Complete — Phase 2 Launch)

**Input:** 0 new GitHub issues, 0 new plans, 2 new commits since last run (740f480, 4b0c71a)

**Changes since last pipeline run:**

| Commit | What |
|--------|------|
| 740f480 | IOSClockPage: flex pool failure → visible errorMessage. Archived 9 prompts (35A, 35B, 35D, 35E, 35H, 66A, 66B, 66C) to done/ |
| 4b0c71a | PE-011 fixed (ReportDateRange 12 force unwraps). PE-012 fixed (Calendar! in 15 files). PE-008e fixed (export guard). IOSReportsRouter swipe-to-delete confirmation. WarehouseLocationsPage drag-and-drop + nav path. AuthService/SettingsService isTableNotFoundError helper extracted. BreakService divide-by-zero guard. |

**Phase status:**
- **Phase 1 Xcode AI Prompts: COMPLETE** — all 279 prompts archived in `xcode-ai/fix-prompts/done/`
- **Phase 2 begins** — HIG accessibility polish, security hardening, test coverage
- Phase 2 queue: 8 items in `xcode-ai/fix-prompts/00-fix-order.md` — all need prompt files written first

**PEs closed this run:** PE-011 ✅, PE-012 ✅, PE-008e ✅ (3 items)
**PEs opened:** PE-013 (unplanned WarehouseLocations features — document in plan)
**Plans created:** 0
**Q&A generated:** 0 (no new feature work needing owner input)
**New Xcode prompts written:** 0 (Phase 2 prompts not yet written)
**Tests:** 733/733 passing (no new tests this run)
**Build:** ✅ 0 errors, 0 warnings
**Commits pushed:** ✅ origin/main up to date
**Agent health:** 7/8 healthy, github-issues-sync still pending auth
**Active PEs:** 5 open (PE-001, PE-003, PE-007, PE-008a-d, PE-009a-e, PE-013)
**Backlog size:** 15 items (0 blocked on Q&A)
**Next priority:** Write PE-009c prompt (6 remaining swipe-to-delete without confirmation)

---

### 2026-03-29 — Dev Improvement Scanner Run 3 (Safety + Security + HIG Audit)

**Scope:** Full A-F scan per SKILL.md. Focused on runtime safety, security, Apple HIG, and UX polish.

**Part A — Runtime Safety:**
- ✅ Zero `as!` force casts in core
- ✅ Zero `try!` in core
- ✅ Zero empty `catch {}` blocks — all catch blocks rethrow or use `isTableNotFoundError` pattern
- ✅ `BinarySyncManager.deserialize` protected by `guard data.count >= 36`
- ✅ `WarehouseService partAssignments[0]` safe — inside `Dictionary(grouping:)` map which guarantees non-empty groups
- ✅ `LanSyncServer parts[0]/parts[1]` safe — protected by `guard parts.count >= 2`
- 🔲 **NEW PE-011**: 12 force unwraps in `ReportDateRange.swift` (shared utility). Most benign, but `cal.dateInterval(of: .weekOfYear, for:)!` is locale-dependent and could crash on unusual calendar locales. Breaks all date-filtered pages simultaneously.
- 🔲 **NEW PE-012**: `Calendar.current.date(byAdding: .day, value: -7, to: Date())!` default value pattern in 15 files. Low risk but should be `Date().addingTimeInterval(-7*86400)`.

**Part B — Security:**
- ✅ No hardcoded user IDs (`created_by = 1`) anywhere — PE-006 fix verified clean
- ✅ PIN hashing uses 10,000-iteration SHA-256 with per-user salt (migration in place for legacy devices)
- ✅ All SQL is parameterized — no string concatenation in queries
- 🔲 PE-008 confirmed: unsigned tokens (plain base64 JSON), no brute-force protection, hardcoded legacy salt `:wiredpart`, LAN HTTP — all still open
- 🔲 `IOSDataExportPage` confirmed: zero permission check. Any active user can export the full database. `export_reports` permission key exists in the permission map but is never checked at the iOS page level.
- Note: `AuthService.listRegisteredDevices/listActiveSessions` use inline `String(describing:).contains("no such table")` instead of the `isTableNotFoundError` helper — minor inconsistency, not tracked.

**Part C — Apple HIG:**
- ✅ Zero `NavigationView` — all pages use `NavigationStack`
- ✅ Zero `print()` in Features/ — only in App/ system managers (appropriate diagnostic logs)
- ✅ Zero TODO/FIXME in iOS codebase
- 🔲 **Updated PE-009**: hardcoded `.font(.system(size:))` count is **88 occurrences across 51 files** (was previously estimated at 55 — current grep confirms higher count)
- 🔲 `IOSJPOCreationPage.swift:209` dead button confirmed: `Button("Yes, for \(selectedJobName)") { }` — empty action

**Part D — UX Polish:**
- ✅ Pull-to-refresh: 133 `.refreshable` occurrences across 123 files — excellent coverage
- ✅ `EmptyStateView`: 47 occurrences across 37 files — good but not 100% coverage
- ✅ `ErrorStateView` and `errorMessage` patterns used consistently

**Part E — IOSClockPage Uncommitted Fix:**
- Uncommitted modification in git status: `IOSClockPage.swift` changed from `print("Flex pool dispatch creation failed: ...")` to setting `errorMessage = "Clocked in, but dispatch record could not be created."` — this is a quality improvement (silent failure → visible warning).
- Needs commit. Not a new PE — already good code waiting in working tree.

**Summary:**
- New PEs added: 2 (PE-011, PE-012)
- PE-009 count updated: 55 → 88 hardcoded fonts
- Confirmed all known PE-008 security items still open
- No new SQL integrity issues found (iter 7-9 fixes held)
- No force casts, no try!, no empty catches, no hardcoded user IDs found

---

### 2026-03-29 — Pipeline Manager Run 2 (Prompt Queue Audit + Coverage Gaps)

**Input:** 0 new GitHub issues (not accessible), 0 new plans, 1 new Xcode prompt (67A), 8 uncommitted service fixes from dev-improvement-scanner run 2

**Key finding — PE-002 resolved:**
- Full grep across all 35C-35I target files confirms: zero GRDB, zero DispatchQueue, zero print() errors
- 35C, 35G, 35I: **SKIP** — work already done
- 35F: **HIGH PRIORITY** — real bugs (audit session ID 0, PO delete nav, rejection reason lost)
- 35D, 35E, 35H: **KEEP** — secondary fixes (ErrorStateView, hat delete confirmation) still needed

**Plans created:** 0 (no new features)
**Q&A generated:** 0 (no unanswered questions blocking work)
**New work items tracked:** PE-006 (67A user attribution), PE-007 (test coverage), PE-008 (security), PE-009 (HIG accessibility)
**Bugs fixed this session:** 0 new (service fixes were from previous dev-improvement-scanner run)
**Tests:** 692 on disk (688 confirmed passing in last commit)
**Agent health:** 6/8 healthy, 2 awaiting SSH push
**Backlog size:** 9 active PEs (1 closed, 3 new opened)
**Gaps found:** Prompt queue had 3 moot prompts (35C/35G/35I) flagged for skip
**Next priority:** Run 35F (session ID + PO delete bugs), then 67A (user attribution)

---

### 2026-03-29 — Plan Enforcer First Run

**Scope:** Audited all 49 plans in `docs/plans/`. Checked iOS feature files, service layer, SQL patterns, pending prompts, and recent git history.

**Findings:**

| Category | Count | Notes |
|----------|-------|-------|
| Plans with full coverage | 12 | Forecasting, catalog, pricing, supplier, orders, testing, companions |
| Plans partially implemented | 20 | All have pending Xcode prompts tracking the gaps |
| Plans pending (future phases) | 7 | bluetooth, PWA, remote sync, phase-16 |
| Drift items (plan says X, code has Y) | 2 | Tool naming + GRDB prompt queue validity |
| Unplanned code files | 4 | IOSScheduleConfigPage, WarehouseOnboardingWizard, SheetDismissWrapper, IOSWarehouseLeaderboardPage |
| Total pending Xcode prompts | 85 | Across tiers 34-52, 64-66 |

**Drift Details:**
1. **Tool naming** — `ios-tools-pages.md` specifies "All Tools" and "Management" as page titles. Code still shows `.navigationTitle("Tool Registry")` and `.navigationTitle("Tool Admin")`. Fix: Prompt 47F when ready.
2. **GRDB prompt queue** — Prompts 35C-35I in queue target GRDB removal from Settings, Fleet, Companions, Reports, Tools, Scheduling. But `import GRDB` is *already absent* from ALL iOS Swift files. Before running these prompts, manually verify if the raw SQL patterns they target still exist (may be residual SQL string usage even without GRDB import).

**Unplanned code (needs plans):**
- `IOSScheduleConfigPage.swift` — config/settings page for scheduling. Not in scheduling plan. Likely emerged from implementation. Should be folded into `ios-scheduling-pages.md` or `ios-settings-pages.md`.
- `WarehouseOnboardingWizard.swift` + 5 step files — added by Prompt 65C fix. Not in warehouse plan. Should be documented in plan.
- `SheetDismissWrapper.swift` — utility added by hunt-fix loop (commit 70869ee). Cross-cutting utility, no plan needed but document in `ios-foundation-fixes.md`.
- `IOSWarehouseLeaderboardPage.swift` — gamification for warehouse staff. Not in warehouse design plan. Document intent or add to future warehouse enhancements.

**Q&A pipeline:** No answered questions pending code integration. No unanswered questions blocking features.

**Plan registry:** Fully populated in this doc (see Plan Registry section above).

---

### 2026-03-29 — Weekly Cleanup Run 1

**Scope:** Full weekly cleanup per SKILL.md protocol.

**Part A — Xcode Prompt Archival:** No prompts eligible. All files in `xcode-ai/fix-prompts/` were created within the last 3 months (oldest: Mar 22). The `done/` subdirectory already holds 126 archived prompts from prior work.

**Part B — Dead Code Scan:** Clean. 65 Swift files scanned in `core/Sources/WiredPartCore/`. Zero commented-out code blocks, zero empty extension blocks, zero unused private functions (105 private functions all verified called).

**Part C — Stale Temporary Files:** Removed 4 `.DS_Store` files from non-git directories (root, docs/, docs/plans/, `Weird Parts IOS/`). No `.tmp/` directory exists. No .bak/.orig/.swp files. `docs/Problomes/` has 32 screenshots from 2026-03-28 — all within 3 months, retained.

**Part D — Q&A Cleanup:** `docs/dev-qa.md` is already clean — contains only template/format guidance, no pending questions.

**Part E — Documentation Freshness:** All docs in `docs/` are from March 2026 (most recent: Mar 29). No docs older than 3 months found. No stale-flag additions needed.

**Part F — Tracker Compression:** All hunt-fix-tracker.md entries are from 2026-03-28/29 — within 3 months. No historical compression needed.

**Verification:** `swift build` ✅ 0 errors, 0 warnings. `swift test` ✅ 733/733 passing.

---

### 2026-03-29 — Plan Enforcer Run 2 (Uncommitted Change Audit + New Drift Detection)

**Scope:** Delta audit of all uncommitted changes vs plans. Verified iter 7 SQL fixes. Checked for unplanned code additions. Audited service function signatures against schema.

**Uncommitted Changes Verified (all trace to plans):**

| File | Change | Plan Source |
|------|--------|-------------|
| `IOSAuditSetupView.swift` | Pass real `userId` to `createAuditSession` | PE-006 / 67A |
| `IOSMessageThreadView.swift` | Pass real `userId` to `autoSaveToJobNotebook` | PE-006 / 67A |
| `IOSInventoryGridPage.swift` | "Warehouse #1" → "Default Warehouse" (cosmetic text fix) | Warehouse plan cosmetic |
| `IOSDispatchPage.swift` | Consolidate `showAssignSheet` Bool → `ActiveSheet.assign` enum case | Pattern 32F standard |
| `ChatService.swift` | Fix `autoSaveToJobNotebook` SQL (notebook_sections, notebook_entries schema) + userId param | Iter 7 SQL / PE-006 |
| `DailyReportGenerator.swift` | `qt.question` → `qt.subject AS question` on qa_threads | Iter 7 SQL |
| `WarehouseService.swift` | `unit_price`→`unit_cost`, `audit_sessions`→`audit_sessions_v2`, userId param | Iter 7 SQL / PE-006 |
| `FleetService.swift` | `vehicle_inspections`→`inspection_records`, `odometer`→`current_odometer` | Iter 7 SQL |
| `JobsService.swift` | Remove non-existent `updated_at` from `labor_entries` UPDATEs | Iter 7 SQL |
| `PartsService.swift` | `unit_price`→`unit_cost` in `po_line_items` subquery | Iter 7 SQL |
| `ReportsService.swift` | `budget_amount`→`budget_limit`, `total_amount`→`total_cost` | Iter 7 SQL |
| `SchedulingService.swift` | Hat name 'admin'→'Admin' (case sensitivity fix) | Iter 7 SQL |

**New test additions (uncommitted, ~574 lines):**
- `ChatServiceTests.swift` +170 tests (supplier channel extended, Q&A, attachments)
- `SchedulingServiceTests.swift` +294 lines (short-term pipeline, snooze callback, capacity)
- `ReportsServiceTests.swift` +78 lines (budget_limit validation)
- `WarehouseServiceExtTests.swift` +74 lines (JPO demand qty_received fix)

**New Drift Item Found:**

**PE-010** — `createAuditSession()` function signature accepts `zone`, `sampleSize`, `includeZeroStock`, `notes` but the SQL insert only writes `session_type` and `started_by` to `audit_sessions_v2`. IOSAuditSetupView still collects zone/spotCheckCount/notes from the user — these values are silently discarded and never persisted.

- **Root cause:** `audit_sessions_v2` has a different schema from v1 (no zone/sample_size/notes columns). The iter 7 fix correctly migrated to v2 but didn't reconcile the function signature or UI.
- **Context:** The 37A-37D prompts define a full audit confidence system with its own schema. Zone/scope may be tracked differently there.
- **Decision needed:** (a) add zone/scope metadata columns to `audit_sessions_v2` now, or (b) remove the UI fields that collect zone/notes until 37A is implemented, or (c) document this as intentional — the current v2 session is just a container until 37A expands it.

**No unplanned new files found.** All iOS Feature files trace to plans. SheetDismissWrapper.swift previously documented. WarehouseOnboardingWizard previously documented.

**Q&A pipeline:** Clean — no pending questions.

**Backlog delta:** +1 item (PE-010). Total active PEs: 9 (PE-001, 003, 004, 005, 007, 008, 009, 010). PE-006 closed.

---

### End-of-Day Sync — 2026-03-29

- Files committed: 5 (AppCore.swift, dev-pipeline.md, hunt-fix-tracker.md, ios-warehouse-pages.md, 00-fix-order.md)
- Commits created: 2 (`fix(onboarding)` + `docs(pipeline)`)
- Push status: ✅ success (4b0c71a → 66ff644 → origin/main)
- Tests: 733/733 passing (49 suites, 0 failures)
- Agent runs today: 6/7 healthy (github-issues-sync ⚠️ still pending auth)
  - hunt-fix-verify ✅ — 9 iterations, 68 SQL bugs fixed, Phase 1 complete
  - test-coverage-maintenance ✅ — 733 tests, coverage gaps remain in PeopleService/ChatService/SettingsService
  - plan-enforcer ✅ — PE-013 warehouse drag-drop documented, all Phase 1 changes aligned
  - dev-improvement-scanner ✅ — PE-011, PE-012, PE-008e found and fixed
  - dev-pipeline-manager ✅ — Phase 2 queue established (8 items)
  - github-sync-and-review ✅ — this run
  - github-issues-sync ⚠️ — pending auth, 0 issues processed
- Issues processed: 0 (auth not available in automated context)
- Bugs fixed: 1 (UserDefaults stale onboarding flags causing fresh-DB devices to skip onboarding)
- Pipeline health: ✅ Phase 1 COMPLETE — 279 prompts archived, Phase 2 HIG + security queue ready

### End-of-Day Sync — 2026-03-29 (Run 2)

- Files committed: 7 (AuthService.swift, AuthServiceTests.swift, AppDatabase+Migrations.swift, WarehouseService.swift, WarehouseAuditTests.swift, AppCore.swift, dev-pipeline.md + 8 DevTODO files)
- Commits created: 4 (security, feat/audit, debug/iOS, docs)
- Push status: ✅ success (ace5318 → origin/main)
- Tests: 736/736 passing (49 suites, 0 failures)
- Agent runs today: 7/7 healthy
  - hunt-fix-verify ✅ — 9 iterations, 68 SQL bugs fixed
  - test-coverage-maintenance ✅ — 736 tests (audit tests +3 this run)
  - plan-enforcer ✅ — plans aligned, PE-020 audit schema complete
  - dev-improvement-scanner ✅ — PE-011, PE-012, PE-008e fixed
  - dev-pipeline-manager ✅ — Phase 2 queue active
  - github-issues-sync ✅ — 12 open issues (#4-#15) processed; DevTODO files created
  - github-sync-and-review ✅ — this run
- Issues processed: 12 (#4 partial, #5-#15 documented in DevTODO)
- Bugs fixed: 2 (PE-020 audit counted_qty schema + discrepancy calculation; brute-force PIN lockout + HMAC token signing)
- Pipeline health: ✅ OK — Phase 2 security (#6 #7 fixed) advancing; accessibility queue ready (#11-#15 in DevTODO)

---

### Plan Enforcer Run 3 — 2026-03-30

**Commits audited since last run:** b3eef3b, 1eb051f, 291ed56, ace5318 (4 commits)

**Plan vs code audit — all partials confirmed consistent:**

| Plan | Coverage | Notes |
|------|----------|-------|
| Security (PE-008) | ~~a~~ ~~b~~ c d pending | a/b FIXED this cycle — HMAC-SHA256 + brute-force |
| warehouse-audit-intelligence.md | Partial advancing | counted_qty + discrepancy calc now real (migration 062) |
| ios-warehouse-pages.md | Partial | PE-013 still unresolved — drag-drop floor plan unplanned |
| All other plans | Unchanged | Consistent with 2026-03-29 registry |

**New PEs opened:**

| PE | Description | File | Priority |
|----|-------------|------|----------|
| PE-021 | Token signing key is per-launch (not Keychain) — tokens invalidate on restart | AuthService.swift:656 | Medium — GitHub #16 filed |

**GitHub issues closed (3):**
- #6 — Unsigned tokens → FIXED b3eef3b ✅
- #7 — No brute-force → FIXED b3eef3b ✅
- #8 — Data export gate → FIXED 4b0c71a ✅ (retroactive close — was already fixed)

**Unplanned code noted (non-issue):**
- `AppCore.resetDatabaseIfNewBuild()` — DEBUG-only (#if DEBUG) dev utility, not in any plan. Low risk, dev-only, acceptable.

**DevTODO created:**
- `16-token-signing-key-keychain.md` — PE-021 Keychain fix with implementation snippet

**Tests:** 760 test functions found in 50 test files (736 passing on last CI build)

**Next priority:** PE-009c (swipe-to-delete confirmations), PE-001 (Tool naming), PE-021 (Keychain signing key)


---

### End-of-Day Sync — 2026-03-31
- Files committed: 198 (188 iOS Swift + 10 docs)
- Commits created: 2 (feat(ios): accessibility + Dynamic Type pass; docs(pipeline): DevTODO AI reports)
- Push status: success (origin/main updated, 3 commits ahead resolved)
- Tests: 759/759 passing (49 suites, 0 regressions)
- Agent runs today: 4/7
  - ✅ dev-improvement-scanner (iter 11): 4 force unwraps fixed in core
  - ✅ plan-enforcer (run 3): PE-013 still needs update
  - ✅ dev-pipeline-manager (run 4): PE-020/021 closed
  - ✅ github-issues-sync: #16 closed, 3 Xcode prompts written
  - ⚠️ hunt-fix-verify: last ran 2026-03-29 (no run today)
  - ⚠️ test-coverage-maintenance: no new run today (tests stable at 759)
  - ✅ ios-accessibility (ad-hoc): issues #8, #11, #13, #14, #15 completed
- Issues processed: 5 (#8 permission gate, #11 Dynamic Type, #13 swipe-delete, #14 a11y labels, #15 color indicators)
- Bugs fixed: 4 force unwraps in core (BackgroundTaskService, ToolsService, AITools, BaseRepository)
- Pipeline health: OK — hunt-fix-verify due for a run; PE-013 ios-warehouse-pages.md update pending

---

### End-of-Day Sync — 2026-03-31 (run 2)
- Files committed: 20 (7 core Swift + 1 test + 11 iOS Swift + 6 docs/plans/prompts)
- Commits created: 5 (fix/core, test/core, fix/ios, docs, chore)
- Push status: success (origin/main updated, 6 commits total including today's prior 2)
- Tests: 800/800 passing (49 suites, 0 regressions, +10 new DashboardService tests vs last sync)
- Agent runs today: 5/7
  - ✅ dev-improvement-scanner (iter 13): 9 force unwraps eliminated across 6 core service files; SQL column mismatches in DashboardService fixed; PE-023 filed (weak assertions)
  - ✅ xcode-accessibility (PE-009a/b): 1 hardcoded font size fixed (PartsForecastingPage); 13 tap targets expanded to 44×44pt across 10 iOS files
  - ✅ github-sync-and-review: this run
  - ✅ plan-enforcer: PE-022 hat assignment plan filed (docs/plans/ios-hat-assignment-ux.md)
  - ✅ dev-qa: 5 questions filed for PE-022 (awaiting owner answers)
  - ⚠️ hunt-fix-verify: last ran 2026-03-29 — 2 days overdue
  - ⚠️ test-coverage-maintenance: PE-023 filed but not yet actioned
- Issues processed: 1 (#17 — "User Aces controles" → PE-022 plan created, Q&A pending)
- Bugs fixed: 11 (9 force unwraps + 2 SQL column mismatches in DashboardService)
- Pipeline health: OK — PE-022 blocked on Q&A answers; PE-023 needs assertion strengthening; hunt-fix-verify overdue

---

### End-of-Day Sync — 2026-03-31 (run 3)
- Files committed: 0 (working tree clean — prior runs already committed all changes)
- Commits created: 0
- Push status: ✅ verified in sync (origin/main up-to-date, 77f2092 confirmed pushed)
- Tests: 800/800 passing (49 suites, 51.9s — no regressions)
- Agent runs today: 5/7 (unchanged from run 2)
  - ✅ dev-improvement-scanner: iter 13 complete
  - ✅ xcode-accessibility (PE-009a/b): complete
  - ✅ plan-enforcer: PE-022 plan filed
  - ✅ dev-qa: PE-022 Q&A filed
  - ✅ github-sync-and-review: this run (verification/watchdog)
  - ⚠️ hunt-fix-verify: 3rd day without a run — recommend manual trigger
  - ⚠️ test-coverage-maintenance: PE-023 (weak assertions) still pending
- Issues processed: 0 (no new issues since run 2)
- Bugs fixed: 0 (this was a verification run)
- Pipeline health: OK — build green, tests green, branch synced; action items: trigger hunt-fix-verify, action PE-023

---

### End-of-Day Sync — 2026-04-01 (run 1 — PE-022 iOS implementation)
- Files committed: 4 (3 iOS Swift People pages + 1 xcode-ai log)
- Commits created: 2 (feat(ios): PE-022 hat assignment UX; docs(xcode-ai): prompt results log)
- Push status: ✅ success — origin/main updated to 0b17c10 (was 13e77fe, now includes 4 commits)
- Tests: 828/828 passing (49 suites, 53.8s — no regressions)
- Agent runs today: 1/7
  - ✅ github-sync-and-review: this run — PE-022 iOS implementation committed and pushed
  - ⚠️ hunt-fix-verify: last ran 2026-03-29 — 3+ days overdue, recommend manual trigger
  - ⚠️ test-coverage-maintenance: PE-023 (weak assertions) still pending
  - ⚠️ plan-enforcer: no run today
  - ⚠️ dev-improvement-scanner: no run today
  - ⚠️ dev-pipeline-manager: no run today
  - ⚠️ github-issues-sync: no run today
- Issues processed: 0
- Bugs fixed: 0 (this run was iOS feature delivery, not bug fixing)
- Pipeline health: OK — build green, 828 tests green; PE-022 iOS implementation complete (HatDetailSheet, AddEmployeeToHatSheet, Management section in PeopleDashboard, Permissions Granted in EmployeeDetail); hunt-fix-verify overdue

---

### Plan Enforcer — 2026-04-01 (run 1)
- **Audit scope:** Recent commits c06622c, 3db6dd1, 0b17c10 + full plan registry
- **Plan alignment:** All verified ✅
  - PE-022 (ios-hat-assignment-ux.md) iOS implementation confirmed matches plan + prompt spec; EmployeeDetail adds Permissions Granted section (intentional prompt extension, not drift)
  - PE-001 (Tool naming rename) confirmed done — naming drift ✅ cleared from plan registry
  - PE-008c (legacy PIN banner) confirmed done — GitHub #9 confirmed CLOSED on GitHub
  - 14 new tests (c06622c) match test plan coverage targets for Fleet + People
- **Documentation lag fixed:**
  - Plan Registry: `ios-hat-assignment-ux.md` → Step 13 complete ✅
  - Plan Registry: `ios-tools-pages.md` → naming drift note removed ✅
  - Plan Registry: `testing-strategy.md` → updated 759 → 842 tests ✅
  - GitHub Issues table #17 → confirmed 🟢 Closed ✅ (was already updated by pipeline-manager run 7)
  - GitHub Issues table #9 → confirmed 🟢 Closed ✅ (was already updated by pipeline-manager run 7)
  - `ios-hat-assignment-ux.md` plan status → updated to COMPLETE ✅
- **Unplanned code found:** None — all recent changes trace to plans or approved PE items
- **Q&A blocked:** PE-003 flex pool — 5 questions still unanswered (correct state, no action)
- **Next enforcement priorities:**
  1. PE-009b (tap targets) — prompt `PE-009b-tap-targets.md` ready, user runs in Xcode
  2. PE-009c (swipe confirmations) — prompt `PE-009c-swipe-confirmations.md` ready
  3. PE-007 (test coverage) — PeopleService ~20/47 methods, ChatService, SettingsService still under-tested
- **Tests:** 842/842 passing (confirmed via commit message; hunt-fix-verify overdue for build verification)
- **Open GitHub issues:** 0 ✅
- **Agent health:** All 8 agents enabled; hunt-fix-verify last ran 2026-03-29 (3+ days overdue)

---

### End-of-Day Sync — 2026-04-02
- Files committed: 5 (FleetService.swift, PeerDiscovery.swift, 3 DevTODO/docs files)
- Commits created: 3
- Push status: success (32305ee pushed to origin/main)
- Tests: 842/842 passing
- Agent runs today: 4/7 (improvement-scanner run 4, pipeline-manager run 7, github-issues-sync run 2, github-sync-and-review run)
- Issues processed: 0 (0 open GitHub issues)
- Bugs fixed: 1 (FleetService UTC timezone mismatch causing test failure)
- Pipeline health: OK — build clean, all tests green, no open GitHub issues, no active Xcode prompts

### End-of-Day Sync — 2026-04-02
- Files committed: 17 (6 core services, 4 test files, 3 iOS files, 1 migration, 9 docs/xcode-ai)
- Commits created: 4 (bug fixes, new tests, iOS UI, pipeline docs)
- Push status: success (96620d4..812ab0e → origin/main)
- Tests: 862/862 passing (+20 new tests vs previous 842)
- Agent runs today: 7/7 (hunt-fix iter 19, test-coverage +18 tests, plan-enforcer run 2, improvement-scanner run 5, pipeline-manager run 9, github-issues-sync run 3, usability-enforcer scheduled)
- Issues processed: 32 open GitHub issues (28 from user testing session + 4 new); 2 core bugs fixed (#28 time-off count, #19 dashboard FK error)
- Bugs fixed: 3 (warranty SQL column mismatch, ChatService empty-DB FK violation, markPriceVerified argument order)
- Pipeline health: OK — build clean, all 862 tests green, 4 commits pushed, PE-024 active (modal dismiss audit), PE-025 queued

---

### GitHub Issues Sync — 2026-04-03 (run 4)
- **Open issues pulled:** 30 (4 new user issues #46–#49 from overnight testing session)
- **Code fixes this run:**
  1. `CategoriesTreeView.swift` + `PartsCategoriesPage.swift` — lifted 4 expansion sets from `@State` in child to `@Binding` in parent; tree no longer resets on data reload (GitHub #46 tree state bug)
  2. `BreakService.swift` — fixed pre-existing compile error: `TimeZone(secondsFromGMT: 0)` forced-unwrapped to resolve `TimeZone? → TimeZone` type mismatch on `calendar.timeZone`
- **Tests:** 877/877 passing (↑ from 876 — BreakService fix unblocked 1 previously masked test path)
- **Issue comments posted:**
  - #20 (Clock In/Out): Code looks correct; likely fresh-DB root cause — linked to #26
  - #26 (Empty DB crash): All 20 services have `isTableNotFoundError` guards; partial fix in 52f63d0; needs live device test
  - #30 (Teams empty state): Fix already in `IOSTeamsPage.swift` lines 155–167 (PE-025 working tree); will be committed with PE-025 batch
  - #43 (T3 items): T3-04 confirmed non-issue (AIDispatchService IS wired); T3-08 confirmed non-issue (UNIQUE constraint on po_number in migration)
  - #47 (Brands/Suppliers edit): Edit IS in code via swipe actions; real issue is brand-supplier linking — Q&A in dev-qa.md needs answers
- **Q&A entries confirmed:** #46, #47, #48, #49 all have entries in dev-qa.md from run 3 (24 questions total, all pending owner answers)
- **Bugs fixed:** 2 (tree state reset #46, BreakService compile error)
- **Issues closed:** 0 (no verified closures this run)
- **Pipeline health:** Build clean, 877 tests green, 30 open issues, PE-025 active

### End-of-Day Sync — 2026-04-03
- Files committed: 35 (16 core services, 6 test files, 6 iOS UI files, 7 docs/xcode-ai files)
- Commits created: 4 (core fixes, new tests, iOS UI/PE-025, pipeline docs)
- Push status: success (a485243..37c8367 → origin/main)
- Tests: 895/895 passing (+18 tests vs 877 from github-issues-sync run 4, +33 vs start of day)
- Agent runs today: 5/7 (hunt-fix-verify runs 9+10, test-coverage-maintenance, github-issues-sync run 4, end-of-day-sync)
- Issues processed: 30 open GitHub issues; 4 bugs fixed across 2 hunt-fix-verify passes
- Bugs fixed: 4 (isTableNotFoundError drift in 14 services, auth test lockout bleed, print()→logger.debug(), ToolsService doc comment)
- Pipeline health: OK — build clean, 895/895 tests green, 4 commits pushed, PE-025 complete, PE-026 (badge counts) queued, T1-02 and T1-10 closed in master-issue-list

### Pipeline Update — 2026-04-04 (dev-pipeline-manager run 10)

**Input:** 24 answered Q&A questions across 9 features (all PE-003, #20, #26, #29, #46, #47, #48, #49, #50/#51). PE-025 committed (826dd18). hunt-fix run 11 completed (WarehouseService multi-user audit consensus crash fix + 3 new tests). Tests at 909/909 before this run.

**Plans created (9):**
1. `docs/plans/ios-clock-fix.md` — #20 EMERGENCY Clock In/Out root cause diagnosis + fix plan
2. `docs/plans/ios-fresh-install-resilience.md` — #26 Full service audit + empty states + onboarding guide
3. `docs/plans/ios-flex-pool.md` — PE-003 Flex pool: DB migration + SchedulingService + Xcode UI prompt
4. `docs/plans/ios-part-number-hierarchy.md` — #46 Part numbers at color level + per-supplier part numbers + tree state
5. `docs/plans/ios-brands-suppliers-editing.md` — #47 Bidirectional brand-supplier linking + editing
6. `docs/plans/ios-pricing-ui.md` — #48 Inline pricing in Parts Catalog, cascading type→color→supplier
7. `docs/plans/ios-warehouse-setup-redesign.md` — #49 Optional/progressive warehouse setup + visual drag-and-drop
8. `docs/plans/ios-schedule-config-redesign.md` — #29 Schedule Config additive rebuild (shift templates, holidays, overtime, supervisor roles)
9. `docs/plans/ios-badge-counts.md` — #50/#51 BadgeService + all-tab badge counts + action button ring indicators

**Bug fixed:**
- `JobsService.getTodaysClockEntries()` — added `isTableNotFoundError → return []` guard. Fresh install no longer crashes clock page load. +1 test `testGetTodaysClockEntriesFreshDB`. 910/910 tests passing.

**Q&A processed:** 24 questions across 9 features → all answered → `dev-qa.md` cleared. 0 pending questions.

**New PEs assigned:** PE-026 (flex pool UI), PE-027 (badge counts), PE-028 (brands/suppliers editing), PE-029 (pricing UI), PE-030 (part number hierarchy), PE-031 (schedule config), PE-032 (fresh install resilience), PE-033 (clock bug), PE-034 (warehouse setup redesign)

**Agent health:** All 8 agents enabled. hunt-fix-verify flagged for emergency #20 investigation. github-sync-and-review has pending commit (WarehouseService + JobsService + test + docs).

**Gaps found:**
1. Clock page bug (#20/PE-033) is EMERGENCY — hunt-fix-verify should investigate first thing next run
2. Fresh install full service audit (PE-032) — `getTodaysClockEntries` fixed but ~15 other methods may be missing `isTableNotFoundError` guards
3. PE-003 core work (migration + SchedulingService) is unblocked — test-coverage-maintenance or direct implementation can proceed
4. BadgeService doesn't exist yet — needs to be written before PE-027 Xcode prompt

**Backlog size:** 9 items (0 blocked on Q&A — all unblocked)
**Next priority:** PE-033 (Clock In/Out emergency) → PE-032 (fresh install audit) → PE-003 core → PE-027 BadgeService
**Tests:** 910/910 ✅

### GitHub Issues Sync — 2026-04-04 (run 5)
- **Open issues pulled:** 46 (50 total: 44 program-review specs #52–#95, 6 actionable bugs/enhancements #46–#51)
- **Code fixes this run:** 0 (all recent bugs already have written prompts; no new core-only fixes found)
- **New Xcode prompts written:**
  - **PE-033** (`PE-033-wishlist-section-layout.md`) — Wishlist 3-section layout + 14-day auto-approve + dismiss reason (GitHub #93)
- **New plans created:**
  - `docs/plans/ios-wishlist-enhancements.md` — Wishlist design decisions for #93
- **Issue comments posted (7):**
  - #20 (Clock In/Out EMERGENCY): PE-031 READY, trigger second after PE-026
  - #46 (Part numbers): PE-027 READY, trigger after PE-031
  - #47 (Brands/Suppliers): PE-028 READY, trigger after PE-027
  - #48 (Pricing UI): PE-029 READY, trigger after PE-028
  - #49 (Warehouse setup): PE-030 READY, trigger after PE-029
  - #50 (Badge notifications): PE-026 DONE — BadgeCountService + BadgeCountManager + ActionDot/actionRing implemented
  - #51 (Visibility standards): PE-026 DONE — full visual language baseline in place
- **Program-review issue audits (4):**
  - #92 (Companion Rules): Already fully implemented in Phase 1 (19A-19K) — commented confirming status
  - #93 (Wishlist): Baseline exists, 3-section redesign → PE-033 READY
  - #94 (Categories smart delete): 10/11 checklist items done; gap = auto-cancel on inventory rise (no `checkDrainingDeletions()` hook in WarehouseService stock-add path)
  - #95 (Job Estimation): Not yet built, needs design session for questionnaire schema + plans before prompt
- **Bugs found (1):**
  - `scheduled_deletions` auto-cancel on stock rise not implemented — `WarehouseService.createMovement()` + `completeSession()` don't call any draining-deletion cleanup after stock increases. Low severity (user can manually cancel). Flag for next hunt-fix run.
- **Issues closed:** 0
- **Pipeline health:** Build clean, 909/909 tests green, 46 open issues (44 are long-lived program-review specs), prompt queue PE-031→PE-027→PE-028→PE-029→PE-030→PE-032→PE-033

---

### End-of-Day Sync — 2026-04-04
- Files committed: 88 (4 new commits: core services/models, tests, iOS UI, docs+pipeline)
- Commits created: 4 (6 total ahead of previous origin, 2 were pre-existing docs-only)
- Push status: success (de403fe → 1a571be)
- Tests: 970/970 passing (51 suites — up from 909 earlier in the day)
- Agent runs today: 7/7 active agents ran — hunt-fix-verify (×2, runs 11–12), plan-enforcer (run 5), dev-improvement-scanner (×2, runs 7–8), github-issues-sync (run 5), dev-pipeline-manager (×2, runs 10–11)
- Issues processed: PE-028 ✅ DONE (brands/suppliers editing), PE-032 ✅ DONE (schedule config), PE-033 ✅ DONE (wishlist sections), PE-034 NEW (DIS-001–004 quick UX), PE-003 core DONE (flex pool Swift + 6 tests)
- Bugs fixed: 114 total lifetime (iterations 27–29 today: multi-user audit OOB crash, SchedulingService force unwraps, BadgeCountManager debounce)
- Pipeline health: OK — 970/970 green, build clean, 5 active prompts (PE-031 EMERGENCY → PE-034 → PE-027 → PE-029 → PE-030), 7 DevTODOs tracked
