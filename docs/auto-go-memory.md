# AUTO GO — Memory

> What I've learned about this project, this user, and this work. Different from `docs/auto-go-metrics.md` (raw numbers) and `docs/auto-go-soul.md` (my identity). Memory is compressed wisdom: observations, patterns, what worked, what didn't, things that aren't in the code or plans but matter.
>
> Read at the start of every iteration (STEP 0). Writeable during STEP 6 when a significant learning has occurred. The weekly `loop-self-improve` pass rolls ephemeral observations into durable memories and prunes anything that's become stale.

---

## How to read this file

Memory is organized by topic, not chronologically. Each entry includes when it was learned and, when relevant, what it implies for future iterations. Entries here represent what I currently believe is true. If I later find evidence that contradicts an entry, I update or remove it (I don't just stack new entries on top).

---

## Things I know about this project

*(Seeded with what I already know from CLAUDE.md and the existing tracker history. Will grow with iterations.)*

- **This is a beta, not a greenfield.** ~1290 tests pass. 87 functional pages. 35 services. The code is large and working. My job is convergence and polish, not construction.
- **Two platforms share one React UI** — Tauri desktop (macOS + Windows) + Tauri iOS — plus a separate native Swift iOS app (`Weird Parts IOS/`) and shared Swift core (`core/Sources/WiredPartCore/`). Cross-platform parity matters (C10 exists specifically for this).
- **SQL schema has known gotchas** (see `feedback_sql_patterns.md`): `users.display_name` not first/last, `jobs.customer_name` not customer_id, `hats` has no `deleted_at`, etc. Before writing any SQL, verify columns against `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`.
- **Hardcoded user ID `1` is an anti-pattern** (see `feedback_hardcoded_user_ids.md`). Always flow real `userId` from session for `created_by`/`updated_by`/`started_by`.
- **Plans are the source of truth for design** (`docs/plans/`). If code diverges from plan, plan wins — unless I file a Q&A and the user decides otherwise.
- **GitHub issues are the single source of truth for unfixed problems** (per CLAUDE.md). Anything unfixable gets filed.

## Things I know about the user's working style

- **The user is the designer, I am the implementer.** The user gives high-level intent; I deliver high-detail, production-grade implementation. (Source: CLAUDE.md "Working Style & Collaboration".)
- **The user prefers direct Swift edits over Xcode prompts when the change is non-visual** (source: `feedback_direct_swift_edits.md`). Xcode AI is for UI-heavy visual work.
- **The user doesn't want unplanned improvements silently applied** (source: `feedback_unplanned_improvements.md`). When I find something not in a plan, I ask: keep & develop now, remove for now, or plan for later — via Q&A.
- **The user wants a loop that self-improves and finds new automations** (source: 2026-04-18 session). Not a static scheduler. Hence `loop-self-improve` + automation-recommender chain.
- **The user is building toward a production release** of a real shop-management system. Convergence toward shippable beats breadth every time.

## Patterns I've noticed (grows as iterations accumulate)

*(Currently seeded with hard-won patterns from earlier work captured in trackers. Will be appended to as the loop runs.)*

- **SQL column mismatches are the highest-yield bug category** (~64+ historically fixed). Scanner 4 in hunt-fix-verify catches most; the rest come from code assuming schema.
- **Sheet-dismiss safety** is a recurring UI bug class — `.interactiveDismissDisabled(isSaving)` on forms-with-state. The `dismiss-safety-campaign.md` plan codifies the pattern.
- **Wizard `Save & Exit` vs. `Cancel`** is a design theme — multi-step flows need draft persistence. Tracked via #148 and related.
- **Tests sometimes pass locally but the migration fails in prod** — from the user's "don't mock the database" feedback. C4/C5 tests must be integration-level, not pure unit with mocks.

## Decisions I've made (and why)

- [2026-04-18] **First area graduation: parts (16 iterations, 1 day).** Pattern observed: 1 iteration per check, no re-runs needed, 2 genuine fixes (dismiss-safety x2) + 1 automation built + 18 new tests + 6 trackers established. 1 checklist item was N/A (C10 cross-platform). The 17-check bar is achievable for a well-maintained area in a working day of loop iterations. This is the baseline — if `jobs` takes >25 iterations to graduate, something's slowing it down and Sunday self-improve should investigate.
- [2026-04-18] **Xcode-prompt throughput signal (4 PE-COLORS prompts stalled ~12h in "to-be-written" status).** Not a fatal gap — prompts are correctly tracked in xcode-ai/fix-prompts/00-fix-order.md and GitHub #237-240. But signals that the xcode-planner-and-review skill isn't firing often enough during AUTO GO runs. The weekly loop-self-improve pass should watch this: if the queue keeps growing week-over-week without prompts being written, flag as a throughput problem for the user.
- [2026-04-18] **Repo is iOS-native only despite CLAUDE.md's dual-platform claim.** Cross-platform parity (C10) is structurally N/A — `src/`, `src-tauri/` not in working tree (git history shows they were removed). CLAUDE.md architecture section and codebase stats are stale. Filed #257 for the drift. For any area reaching C10, the right answer is: mark done (vacuously satisfied, single platform), reference tracker.
- [2026-04-18] **Automation-recommendations approval workflow (user-directed).** Every recommendation in `docs/automation-recommendations.md` must be filed as a Q&A in `docs/dev-qa.md` with APPROVE/DEFER/REJECT options. Once the user answers APPROVE, the next AUTO GO iteration builds it autonomously. If an attempt fails (skill won't compile, hook breaks something, etc.), file another Q&A documenting the failure and asking what to do instead — don't silently give up. [→ soul candidate] The guiding principle: recommendations are not silent to-dos; they are proposals that need a green light.
- [2026-04-18] **Treated C1b drift as bi-directional** — checked both "code ahead of issues" (ForecastSettingsSheet built, #162/#163 still open) AND "plan ahead of code" (PE-COLORS Phase 2 unimplemented). Both directions matter; catching only one misses half the value. Closing stale issues clears noise from the open-issue list; flagging plan gaps prevents them from being forgotten.

## Things I tried that didn't work

*(Empty — will grow. Each entry: what I tried, why it failed, what I do instead now. This is how I avoid repeating mistakes across iterations.)*

## Things I tried that worked well

*(Empty — will grow. Captures validated approaches worth reusing.)*

## Per-area notes

*(Each area gets a section as I work it. Initial stubs below.)*

### parts
- [2026-04-18] **`suggestion_id: 0` FK bug in `recordCompanionFeedback`** — the function was hardcoding `suggestion_id: 0` in the `companion_feedback` INSERT, but `companion_suggestions` has no row with id=0. Fix: made `suggestionId` an optional parameter (default nil) and skip the INSERT when nil. Filed #250. When writing tests for functions that INSERT into tables with FK constraints, check the referenced table exists in the test DB and the seed value is valid.
- [2026-04-18] **`createPart` auto-logs a "created" audit entry** — `getPartChangeLog` for a freshly seeded part returns 1 entry. Tests for `logPartFieldChanges` must filter by `action == "updated"` rather than asserting `isEmpty` or exact count.
- [2026-04-18] **`#expect` macro can't type-check complex closures with 3+ `&&` conditions** — Swift compiler times out. Break into local variables (e.g., `let entry = log.first(where:...)` then `#expect(entry?.field == value)`) for multi-condition assertions in `#expect`.
- [2026-04-18] **PE-COLORS Phase 1 is silently complete** — migration 074 (`color_brand_skus`), `ColorBrandSKU` struct + CRUD in PartsService, and `searchParts` union update (tagged "PE-COLORS #236") were all done but not explicitly noted in the plan's progress log. Phase 2 (UI) pending via #237-#240. Phase 3 (orders) pending via #242-#243.
- [2026-04-18] **ForecastSettingsSheet covers both issues #162 AND #163** — the free-space rating (issue #163 "per-location 1-10 scale editor") is implemented as a Stepper inside the ForecastSettingsSheet, not as a separate sheet. When verifying issues, check the actual implementation before assuming separate files are needed.
- [2026-04-18] **"Subsumes: #X" in issue body = close #X immediately during C2b** — When a well-written parent issue lists "Subsumes: #X, #Y" in its body, those subordinate issues can be closed during C2b ingestion without any code check needed. The parent carries all context. In the PE-COLORS family this collapsed 5 redundant issues (#144, #100, #106, #99, #105) into their parent issues (#237, #238, #240).

### jobs
- [2026-04-19] **Jobs area is a graduated-baseline reference.** 16 iterations to graduate (iter 17 yesterday through iter 7 today). Only 1 functional fix during the run (CreateJobSupplierChannelSheet dismiss-safety, commit b102dfa). 0 hunt-fix findings, 0 security findings, 0 perf findings, 0 test-coverage gaps (204 tests / 67 funcs = 3x), 0 build warnings, 0 pending Q&A. When an area shows this "all green on first sweep" profile, keep iterations short (single-check each) and don't fabricate findings.
- [2026-04-19] **JobsService.swift line 628 uses a safe GRDB partial-UPDATE idiom** — `setClauses.joined(",")` with whitelisted column names + parameterized `StatementArguments`. Looks like SQL concat (M4 flag) but is not. Future security/hunt-fix scans should recognize this pattern and not flag it. Same pattern appears in other services — confirm column-name whitelisting before flagging.
- [2026-04-19] **Repo has no per-area GitHub labels** (`jobs`, `parts`, `warehouse` etc. are not labels). Issues are filtered by title prefix `[Jobs]`/`[Parts]`/etc. C2b/C11 must use title-keyword search via `gh issue list --json title | python3 -c ...`, not `--label`. [→ soul candidate if repo never adds labels]

### warehouse
- [2026-04-19] **Service profile**: WarehouseService has 137 public methods, 195 tests (100% breadth, 1.4× ratio — best breadth coverage of any area). GRDB import refactor already complete (0 warehouse UI files import GRDB directly; #74 stays open as program-review parent).
- [2026-04-19] **WarehouseService:1702 safe GRDB partial-UPDATE idiom** — same whitelisted-setClauses + parameterized-args pattern as JobsService:628. Both are confirmed safe; don't flag as M4 SQL-concat in future security scans.
- [2026-04-19] **Dismiss-safety gaps found**: IOSAuditSetupView + WizardAddStorageUnitSheet (C7, commit 28b86d85) + OrgChecklistSheet + ConsolidationDetailSheet + ManagerOverrideSheet in IOSOrganizationAuditPage (C13, commit c96a15a3). Total 5 gaps in this area alone. File-level grep misses nested `private struct` views — must check per struct-scope boundary, not per file.
- [2026-04-19] **Batch movement atomicity bug** (#259): IOSMovementWizard creates N individual DB transactions for N parts in a batch move. No shared transaction wrapper. Partial-move risk if interrupted. Fix: add `createBatchMovements()` to WarehouseService. Not yet fixed — filed as bug.
- [2026-04-19] **31 iOS files, 15 planned**: WarehouseOnboardingWizard + 6 steps, WarehouseLeaderboardPage, WizardStepPlacement, CartManager, WarehouseRouter, ReceivingRoutingFlow, WizardStepZones/Areas/Shelves/Bins are "unplanned" but documented in ios-warehouse-pages.md. Natural decomposition of hierarchy (Unit→Row→Shelf→Area→Bin).
- [2026-04-19] **Dismiss-safety scanner needed** (C13 recommendation): 8 gaps found across 3 areas (parts×2, jobs×1, warehouse×5). The pattern is systemic — every area will have some. A struct-aware scanner (Python with brace-depth tracking) would find all in one pass instead of manual C7 sweeps. Filed as Q&A item — HIGH priority, pending user APPROVE/DEFER/REJECT.

### scheduling
- [2026-04-19] **Service profile**: SchedulingService 36 public methods, 149 tests (4.1× ratio = best coverage so far). All methods tested. Graduated in 7 iterations (compact — clean area from start).
- [2026-04-19] **is_active dual-filter gap pattern**: 4 forward-scheduling user-existence checks were missing `is_active = 1` (getWeeklyAvailability, createDispatch, createScheduleEntry, createTimeOffRequest). All checked `deleted_at IS NULL` but not `is_active`. Fixed in commit 9ee3fe46. This pattern likely repeats in other services — the is_active defense hook (filed as C13 Q&A) would catch these at write-time.
- [2026-04-19] **Dismiss-safety gaps now 10 total across 4 areas**: parts 2 + jobs 1 + warehouse 5 + scheduling 2 = 10. The pattern is systemic. Dismiss-safety scanner approval Q&A (warehouse C13) should be acted on as soon as possible — it will find ~35 more gaps across the remaining 10 areas.
- [2026-04-19] **getLongTermTimeline N+1**: 36-month loop × 2 DB queries = 72 queries/call. Filed #261 (low urgency, local SQLite, < 1s). Fix: batch into 2 GROUP BY queries.
- [2026-04-19] **AI dispatch features are planned but not implemented**: Plan sections 8-10 (generateAIDispatchSuggestions, fetchAISuggestedQuestions, end-of-job reviews with AI) have no service methods. These are future-phase items blocked on Foundation Models integration. C1b drift = acceptable (plan-ahead-of-code for future features).

### orders
- [2026-04-19] **Service profile**: OrdersService 42 public methods, 83 tests (2.0× ratio, 100% breadth — all methods tested). Graduated in 4 iterations (iter 28–31 day 2).
- [2026-04-19] **Code far ahead of plan documents**: All prompt chains (26A–30E + PE-033) were fully implemented but plan files still showed "Queued"/"Written". C1b found zero plan-ahead-of-code gaps. Pattern: mature areas often have code that raced ahead of plan status tracking.
- [2026-04-19] **Tab order drift fixed**: NavigationConfig had POs before Procurement; both plan files (ios-jpo-page.md + ios-procurement-page.md) confirmed workflow order is JPOs → Procurement → POs. Fixed in NavigationConfig. Minor UI-only fix but follows confirmed design intent.
- [2026-04-19] **Naming drift: IOSApprovalsPage → IOSUnifiedApprovalsPage in Office/**: Plan files reference IOSApprovalsPage but actual file is IOSUnifiedApprovalsPage.swift in Features/Office/ (not Features/Orders/). Router correctly maps `orders-approvals` to it. Q&A filed for user to decide whether to update plans.
- [2026-04-19] **is_active dual-filter gap**: 3 user-existence guards in OrdersService (createJPO, createJPOWithLines, createReceivingSession) were missing `AND is_active = 1`. Same pattern as SchedulingService. Running total now 7 across 2 services. Pattern is confirmed systemic — the is_active defense hook Q&A becomes more urgent with each area.
- [2026-04-19] **Safe GRDB partial-UPDATE idiom in OrdersService**: Lines 796 + 2081 use setClauses.joined — both confirmed safe (hardcoded column literals, not user input). Third service with this pattern (after jobs:628, warehouse:1702). Future security scans: recognize this pattern and skip.
- [2026-04-19] **Dismiss-safety gaps**: 3 fixes — CreatePOSheet + CreateReturnSheet (had interactiveDismissDisabled but no Cancel.disabled or ProgressView) + AddWishlistItemSheet (had interactiveDismissDisabled + Cancel.disabled but no ProgressView). Running total: 13 dismiss-safety gaps across 5 areas.
- [2026-04-19] **PE-COLORS Phase 3 UI pending**: #242 (IOSJPOCreationPage General/Specific toggle) + #243 (IOSPOCreationPage resolved-brand pill) — service done (#241 closed), UI not yet built. These are correctly open, waiting for PE-COLORS Phase 3 to begin.
- [2026-04-19] **DIS-006 DevTODO already CLOSED**: wishlist auto-approval main-thread DevTODO was already fixed 2026-04-07 — file is stale. IOSWishlistPage comment at line 477 documents the fix (processAutoApprovals moved out of getSectionedItems task scope).

### people

- [2026-04-19] **PeopleService is_active defense gaps (5)**: addTeamMember, toggleHatAssignment, addCommunicationEntry, addContractorNote, addContractorRating — all checked `deleted_at IS NULL` without `AND is_active = 1`. Running systemic total: 12 gaps across 3 services (Scheduling ×4, Orders ×3, People ×5). The pattern is: forward-creating functions that validate user existence before inserting a record. Always check both flags.
- [2026-04-19] **loadContact() isDirty reset pattern**: Edit sheets that pre-populate via `.task { loadContact() }` need `isDirty = false` reset at the END of `loadContact()` after all field assignments. Without this, `.onChange(of:)` fires when fields are set during load, falsely marking form dirty before user touches anything. This is a subtle bug in any pre-populated form sheet.
- [2026-04-19] **C1b drift — EmployeeDetail certs/skills**: IOSEmployeeDetailPage has 3 tabs (Profile, Hats, Teams). Plan + #77 call for Certifications and Skills tabs. `EmployeeDetail` struct and PeopleService have no cert/skill per-employee methods. Acceptable future-work drift — tracked in #77, not blocking.
- [2026-04-19] **Dismiss-safety people sweep (9 sheets)**: AddCustomerSheet, AddContractorSheet, AddContactSheet, AddHatSheet, AddTeamSheet, EditTeamSheet, AddContractorNoteSheet, EditContactSheet, 3 IOSCustomerDetailPage sheets. All used PE-044 pattern. Running dismiss-safety total: 22+ gaps across 6 areas.
- [2026-04-19] **C7b a11y gaps (4 fixed)**: RatingRow star images in ForEach (all 5 stars needed `.accessibilityHidden(true)` — numeric score Text adjacent makes them redundant); EmployeeDetailPage read-only checkmark status icon; HatsPage person.2.fill badge icon; PermissionsPage hat selector needed `.accessibilityAddTraits(.isSelected)` for VoiceOver to announce current selection.
- [2026-04-19] **getContactsSorted safe SQL interpolation**: PeopleService:1731 `sql += " ORDER BY \(orderClause)"` — orderClause is switch-derived with 3 hardcoded string values only. Same safe ORDER BY pattern as jobs/warehouse setClauses. Not a security finding.
- [2026-04-19] **PeopleService baseline**: 50 public funcs / 62 PeopleServiceTests = 1.24× coverage / 100% breadth. All methods tested. 0 SELECT*, 63 total SELECTs, no N+1 loops.

### tools
- [2026-04-19] **Service profile**: ToolsService 31 public methods, 71 tests (2.3× ratio, 100% breadth). 12 sections: tools list, kits, checkouts, stats, detail, kit contents, version history, condition checkout, edit-with-verification, trades, lost/stolen, maintenance. 5 migrations (006/013/048/049/050).
- [2026-04-19] **is_active defense gaps (6)**: listTools, listKits, getToolsStats (×2), initiateTrade, getPendingTradesForUser, updateConfidenceScores — all filtered by `deleted_at IS NULL` but not `is_active = 1`. Fixed in commit e4316add. Running systemic total: 18 gaps across 4 services (Scheduling ×4, Orders ×3, People ×5, Tools ×6). Pattern is especially common in JOIN clauses where the tools table is joined but not filtered.
- [2026-04-19] **allowedToolEditFields allowlist for SQL field interpolation**: `editToolWithVerification` and `approveToolEdit` use `guard Self.allowedToolEditFields.contains(field) else { continue }` before `"UPDATE tools SET \(field) = ..."`. This is the safe pattern for field-level SQL updates. Same whitelisted-setClauses idiom seen in Jobs/Warehouse/Orders. Not a security finding when present.
- [2026-04-19] **ToolsService trusts auth session**: No `SELECT COUNT(*) FROM users WHERE id = ? AND ...` pre-flight checks before writes. Calls take userId as a parameter and trust the caller. Different from PeopleService/SchedulingService which validate user existence first. Both patterns are intentional by area.
- [2026-04-19] **First area with 0 dismiss-safety gaps**: All 9 nested sheet structs in IOSToolDetailPage were built with `@State private var isSaving` + `.interactiveDismissDisabled(isSaving)` from the start. Running dismiss-safety total: 22+ gaps across 6 areas (tools=0).
- [2026-04-19] **1 a11y gap**: IOSToolCheckoutsPage `filterToggle` Active/All buttons missing `.accessibilityAddTraits(.isSelected)`. Same pattern as IOSPermissionsPage hat selector (fixed in people). Fixed in commit e4316add.
- [2026-04-19] **C9 perf fix**: IOSToolMaintenancePage was calling `listTools()` (all tools) then filtering `.filter { $0.status == "maintenance" }` in Swift. Changed to `listTools(status: "maintenance")` to push filter to SQL. The `status:` parameter existed — page just wasn't using it.

### vehicles
- [2026-04-19] **Service profile**: FleetService 33 public methods, 43 tests (2.3× ratio, including 3 new is_active defense tests). 19 logical sections covering vehicles, trailers, assignments, maintenance, mileage, fuel, inspections, stock, transfers, telematics, driver stats. Largest service is_active gap count of any area so far.
- [2026-04-19] **is_active defense gaps (13)**: listVehicles, listTrailers, getFleetStats (×5 counts + 1 JOIN), listMaintenanceRecords JOIN, listMileageLogs JOIN, listFuelLogs JOIN, listInspections JOIN, listTelematicsData JOIN, 2 vehicle existence guards, getTrailerDetail, getMyVehicleStats (×2 JOINs). Mostly in reporting JOIN clauses. Running systemic total: 31 gaps across 5 services (Scheduling ×4, Orders ×3, People ×5, Tools ×6, Fleet ×13). Pattern: reporting queries that JOIN to vehicles/trailers without `AND v.is_active = 1` in the ON clause.
- [2026-04-19] **Default limits built into all list methods**: `listMaintenanceRecords(limit: Int = 50)`, `listMileageLogs(limit: Int = 50)`, `listFuelLogs(limit: Int = 50)`, `listInspections(limit: Int = 100)`. List pages use default args → safely bounded. No unbounded fetches.
- [2026-04-19] **Two fleet permissions**: `manage_fleet` gates vehicle/trailer/driver CRUD and inspection writes. `view_fleet_financials` gates cost cards (fuel cost MTD, maintenance cost MTD, miles MTD) on dashboard. These are enforced at the UI layer via `.requiresPermission(...)`.
- [2026-04-19] **Dismiss-safety: 4 gaps fixed** — LogFuelSheet + AddTransferItemSheet (both nested structs in IOSMyTruckPage), IOSAssignDriverSheet, PreTripInspectionView. Running dismiss-safety total: 26+ gaps across 7 areas.
- [2026-04-19] **C7b a11y gaps (2)**: IOSAssignDriverSheet selection `checkmark.circle.fill` icon (decorative — font-weight cues selection) + IOSMyTruckPage `QuickActionBtn` Image children (VoiceOver would read icon name + label text).
- [2026-04-19] **No N+1 issues found**: Fleet dashboard loads in 4 sequential service calls (stats, vehicles, upcoming maintenance, recent maintenance) — all batch. No per-row loops calling DB.

### inventory
*(notes accumulate here)*

### reports
*(notes accumulate here)*

### notebooks
*(notes accumulate here)*

### chat
*(notes accumulate here)*

### settings
*(notes accumulate here)*

### cross-cutting
*(notes accumulate here)*

## Weekly reflections (newest first)

*(The `loop-self-improve` Sunday pass writes a reflection here each week: what was graduated, what got stuck, what patterns emerged, what soul or memory entries need updating.)*

---

*Seeded 2026-04-18. First entry from the loop itself: pending.*
