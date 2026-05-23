# WEI-1944 Full-App Usability Verification Matrix for WEI-180

Issue: WEI-1944
Parent: WEI-180
Created: 2026-05-23
Scope: read-only QA planning deliverable; no app code changed.

## Purpose

WEI-180 asks whether every page is usable as designed, not just whether the app builds. This matrix turns the existing design docs, usability-hunter categories, pre-release checklist, and prior UI/simulator evidence into a single verification plan for every major page and flow.

The matrix is meant to answer three questions for each area:

1. What user-visible flows must be verified?
2. Which usability-hunter categories apply?
3. What can be covered by existing automated UI checks, and what still needs simulator/manual evidence?

## Source documents reviewed

- `docs/plans/usability-hunter-plan.md` — six behavioral categories and known scanner patterns.
- `docs/plans/ios-page-review-tracker.md` — 12 feature areas, reviewed files, prompt status, program-wide standards.
- `docs/usability-tracker.md` — historical usability-hunter/enforcer runs and open systemic categories.
- `docs/plans/pre-release-testing-checklist.md` — 331 pre-release items across launch, navigation, modules, standards, sync/offline, and advanced flows.
- `docs/testing/e2e-ui-test-plan.md` — existing browser/simulator/interactive evidence and gaps.
- `docs/testing/ai-page-context-coverage.md` — AI page-context/help coverage evidence and remaining slices.
- Area design plans in `docs/plans/ios-*.md` for Jobs, Chat, Notebooks, People, Scheduling, Tools, Fleet, Reports, Office, and Settings.

## Usability-hunter categories used in this matrix

| Code | Category | What must be verified |
| --- | --- | --- |
| C1 | Dismiss and sheet safety | Sheets close via visible Cancel/Done/Close, cannot be swiped away during saving, no stale dismiss-after-await behavior, one active sheet pattern. |
| C2 | Silent failure visibility | Service unavailable, DB, sync, import/export, camera, and file errors are surfaced to the user instead of ignored. |
| C3 | Save/delete feedback | Saves show success or clear completion state, destructive actions confirm first, long operations show loading/progress, failed writes keep the user in context. |
| C4 | Navigation exits | Detail pages have a back path, wizards have Cancel/Save & Exit/finish routes, unsaved work warns before leaving, deep links land on real pages. |
| C5 | Form validation | Required fields block submit, numeric/date/PIN fields use correct validation, invalid states explain how to fix, duplicate/empty submissions are prevented. |
| C6 | Keyboard/touch/accessibility basics | Keyboard can be dismissed, fields do not hide behind keyboard, tappables are at least 44px, icon-only buttons have labels, no color-only meaning. |

## Coverage labels

| Label | Meaning |
| --- | --- |
| Existing automated/UI evidence | Already covered at least partly by `docs/testing/e2e-ui-test-plan.md`, earlier simulator/Playwright evidence, static scanner docs, or current build validation docs. |
| Needs simulator/manual evidence | Must be run in iOS Simulator or on device because it involves sheets, gestures, camera/QR, share sheets, keyboard, swipe, native file dialogs, offline/network, permissions, or nuanced visual accessibility. |
| Static scanner coverage | Can be partially checked by grep/ripgrep/static rules, but must not be treated as fully verified without a focused inspection for false positives. |

## Program-wide gates before area sign-off

These gates apply to every row in the matrix and should be checked once per verification cycle plus spot-checked while testing each area.

| Gate | Source | Automation fit | Manual/simulator requirement |
| --- | --- | --- | --- |
| Every visible button has an action; no shipped TODO/Coming Soon stubs. | Pre-release W1-W8, page review tracker common issues | Static scans for empty closures, TODO labels, PlaceholderView/Text stubs. | Tap all major page toolbar/FAB/empty-state actions on iPhone and iPad. |
| One active sheet path per view and dismiss guards during saving. | Usability C1, pre-release B4/B5/C7 | Static scans for `.sheet`, `isSaving`, `interactiveDismissDisabled`. | Swipe-dismiss and Cancel/Save behavior in forms/wizards. |
| Error/loading/empty states are user-visible. | Pre-release C8/C14/C15 | Static scans for `ErrorStateView`, `ProgressView`, `EmptyStateView`, `loadError`. | Force empty DB/no data and failed service paths where possible. |
| Search/filter/refresh standards on list pages. | Pre-release C1/C12/C13, page review standards | Static scans for `.searchable`, `.refreshable`, smart card/filter components. | Verify filters are understandable, resettable, and do not strand users. |
| 44px tap targets, keyboard dismissal, icon labels. | Usability C6, pre-release C5/LL7 | Static scans for small frames and accessibility labels. | iPhone 375-width touch pass with keyboard open, dynamic type spot-check. |
| Help and AI page context. | Page review standards, AI coverage inventory | Static mapping check for help IDs and page-active notifications. | Tap Help/AI on representative pages and verify page-specific content. |

## Major page/flow verification matrix

| Area / page or flow | Key user flows to verify | Usability categories | Existing automated/UI evidence | Needs simulator/manual evidence | Priority |
| --- | --- | --- | --- | --- | --- |
| Fresh install, bootstrap, login, logout, PIN error | Create first company/admin, log in/out, wrong PIN, return to user picker, DB/migration failure display. | C2 C3 C4 C5 C6 | E2E Test 1 has login/logout/wrong PIN PASS with fresh-bootstrap steps skipped due seed DB. Pre-release A covers full launch checklist. | Fresh install on iOS simulator/device with empty DB; keyboard overlap on PIN/admin fields; migration failure/error wording; app restart persistence. | High |
| Global navigation/sidebar/account menu/edit tabs | Expand every module, open every sub-tab, deep-link/QR route to real page, account menu opens/closes, edit tabs does not hide critical exits. | C1 C2 C4 C6 | E2E/interactive tests cover sidebar at iPad/iPhone and module navigation. Pre-release B lists exact route gates. | Full tap-through all current routes after latest iOS changes; verify no placeholder route, no dead-end detail page, no inaccessible account sheet. | High |
| Dashboard overview | KPI cards, schedule overview, quick actions, background task card, card details. | C1 C2 C3 C4 C6 | E2E Test 16 and interactive iPad/iPhone Dashboard PASS; page-context coverage includes dashboard. | Tap every KPI/quick action; verify empty/error states and card detail sheets; dynamic type/card truncation. | Medium |
| Clock in/out and daily report | Job/shop clock-in, GPS/job picker, break/lunch/supply run, live timer, switch job, clock-out questionnaire, daily report submit/problem sheets. | C1 C2 C3 C4 C5 C6 | E2E Tests 4 and pre-release E cover core clock flow; usability tracker has multiple clock runs and fixes. | Real simulator/device keyboard and location permission states; questionnaire required-field validation; break/lunch transitions; swipe-dismiss while submitting. | High |
| Dashboard QR scanner and QR labels | Open camera, continuous scan, lock/auto-lock, expected-type handling, scan to part/PO/job/tool, label print/export. | C1 C2 C3 C4 C6 | E2E Test 15/QR skipped or partial; page review says QR system prompts done; AI coverage references QR-related pages indirectly. | Camera permission allow/deny, no-camera simulator state, bad QR error feedback, native print/share sheet, scan result navigation and dismiss behavior. | High |
| Parts Catalog | Search/NL search, filter cards, part detail, create/edit/delete, audit history, barcode/QR scan. | C1 C2 C3 C4 C5 C6 | E2E Test 3 covers catalog create/search/edit partly; interactive Parts/Categories PASS; usability tracker includes Parts enforcer passes. | Part form validation, save failure feedback, delete confirmation/smart delete, keyboard on numeric fields, detail sheet dismiss during save. | High |
| Parts Categories/Styles/Types/Brands/Colors | Tree expand/collapse, hierarchy CRUD, smart delete, brand/color nesting, empty shelf approval path. | C1 C2 C3 C4 C5 C6 | E2E Test 3 and page review tracker show prompts done; usability tracker has category form dismiss guards fixed. | Delete-with-inventory confirmation, invalid hierarchy validation, accessibility labels on tree affordances/color swatches, keyboard dismissal in form sheets. | High |
| Parts Suppliers | Supplier list/detail, add/edit/delete, supplier scores, supplier-brand links, supplier bridge entry points. | C1 C2 C3 C4 C5 C6 | Page review tracker marks Suppliers done; Parts enforcer scope included suppliers. | Supplier form validation, duplicate handling, delete confirmation, score empty/error states, bridge navigation. | Medium |
| Parts Pricing | Tier rules, override flow, bulk markup, settings, stale alerts, conflict confirmation. | C1 C2 C3 C4 C5 C6 | Page review tracker marks pricing prompts done; usability tracker Run 8 verifies pricing dismiss guards. | Override/keep-replace confirmation, invalid price/margin validation, save success/failure feedback, keyboard decimal entry. | High |
| Parts Companions | Rule list, rule form cascade, polls/voting, sandbox, admin dashboard, clock-out poll. | C1 C2 C3 C4 C5 C6 | Page review tracker marks companion prompts done; usability tracker Run 1 fixed companion form dismiss guards. | Cascade validation, vote locking/skipping, empty poll states, clock-out poll path, accessibility for rule/poll controls. | Medium |
| Parts Forecasting and Inventory Intelligence | Urgency cards, per-location forecast, recalc, recommendations, MIN/TARGET/MAX validation, settings. | C1 C2 C3 C4 C5 C6 | Page review tracker marks forecasting done; E2E has parts coverage but not full intelligence; pre-release AA lists deep checks. | Recalc progress/errors, recommendation approve/dismiss, validation, per-location picker on iPhone, trend/urgency not color-only. | High |
| Parts Import/Export | Import/export buttons, CSV parsing errors, native share/file dialogs, progress/status messages. | C1 C2 C3 C4 C5 C6 | E2E Test 3.10 page loads; native file operations mostly skipped. | Native simulator/device file picker/share sheet; invalid CSV error; export success; no silent failure when permissions/files unavailable. | Medium |
| Jobs list | Smart status cards, search/filter/new job, AI summary, stage/progress bars, payment hold privacy. | C1 C2 C3 C4 C5 C6 | E2E Test 4 and interactive Jobs List PASS; AI context covers Jobs List. | Create flow validation, worker vs manager privacy, filters reset, dynamic type and card tap targets. | High |
| Job detail | Overview dashboard, tabs, edit info, status changes, team/parts/orders/notebook/labor/daily logs, payment/warranty/continuous states. | C1 C2 C3 C4 C5 C6 | E2E Test 4 job detail/labor/daily report PASS/PARTIAL; interactive Job Detail PASS; AI context covers job detail. | Back path after delete/status changes, unsaved edit warnings, tab overflow on iPhone, permission-gated actions. | High |
| Labor, questionnaire, job reports, estimation | Time entries, clock-in options, clock-out required answers, estimation questionnaire/review, reports filters. | C1 C2 C3 C4 C5 C6 | AI page-context coverage validates labor/daily/questionnaire/estimation/job reports; E2E covers labor history. | Required answer validation, keyboard dismissal, break verification, report empty/error states, warranty/new-work classification. | High |
| Warehouse dashboard | Stock health, quick actions, activity feed, receiving/staging/returns/audit counts. | C1 C2 C3 C4 C6 | E2E Test 6 and interactive Warehouse Dashboard PASS; AI context coverage validates dashboard. | Tap all quick actions/cards, no-data and DB error states, priority colors not color-only. | Medium |
| Warehouse movements and movement wizard | Source/destination/parts/qty/notes/preview/execute, save draft/exit, QR scan from wizard. | C1 C2 C3 C4 C5 C6 | E2E Test 6 movement wizard PASS; usability tracker verifies IOSMovementWizard save/exit and dismiss guards. | Quantity validation, execute failure path, cancel/save draft, QR sheet dismiss, keyboard/numeric entry on iPhone. | High |
| Warehouse locations/floor plan/onboarding | Location groups, unit/area/bin CRUD, floor plan grid, progressive onboarding, sticker checklist. | C1 C2 C3 C4 C5 C6 | AI context coverage validates Warehouse Locations; existing artifacts for WEI-1092/1182/1185/1188 include simulator screenshots. | Drag/resize/rotate grid, long-press gestures, delete confirmation, persistence after app resume, iPhone/iPad layout evidence. | High |
| Warehouse staging/receiving/audit/inventory/returns/tools/network/settings | Process receiving, stage boxes, count audits, inventory grid, returns, warehouse tools, network placeholder, settings save. | C1 C2 C3 C4 C5 C6 | AI context coverage validates these warehouse pages; E2E covers receiving/movement partially; usability tracker has fixes. | Each page's empty/error/success states, batch actions, audit hidden count behavior, settings save feedback, network planned feature messaging. | High |
| Orders JPO list/create/detail | JPO creation cart, job context, companion/AI suggestions, approve/hold/reject per line, chat on hold. | C1 C2 C3 C4 C5 C6 | E2E Test 7 covers JPO create/line/approval partly; AI context covers JPO list/create/detail. | Full cart validation, qty confirm, hold chat thread, supplier missing flow, iPhone 3-panel collapse. | High |
| Orders PO list/detail/procurement/parts management/wishlist/staging | PO lifecycle, procurement demand consolidation, supplier picker, status actions, wishlist, stage release. | C1 C2 C3 C4 C5 C6 | AI context coverage validates PO detail/procurement/parts/wishlist/staging; E2E has PO conversion partial/skips. | Supplier assignment to PO generation, status transition failure feedback, bulk actions, wishlist edit/filter gap, native share/export if present. | High |
| Orders receiving/returns | Receive sessions, discrepancy/routing flow, returns status/cards, stock update verification. | C1 C2 C3 C4 C5 C6 | AI context coverage validates receive shipment and returns; E2E receiving skipped because PO path incomplete. | End-to-end PO receiving on simulator/device, discrepancy validation, routing completion, stock count proof, no silent update failure. | High |
| People employees/customers/contractors/contacts/teams/hats/permissions | List/detail CRUD, hat assignment, permissions matrix, contacts, teams, payment/certification visibility. | C1 C2 C3 C4 C5 C6 | E2E Tests 2 and 9 cover employees/PIN/customer/contact/scheduling; AI context currently covers Employees only; page plans cover remaining. | Detail forms, permission-gated fields, delete confirmations, team member management, hat changes take effect immediately, privacy on worker account. | High |
| Chat, Q&A, RFI, supplier bridge | Unified inbox, create channel, send message, thread info, escalation ladder, attachments, supplier/JPO threads. | C1 C2 C3 C4 C5 C6 | Page review has chat design/prompts queued; usability tracker verifies attachment pickers implemented in PE-043; pre-release HH lists advanced checks. | Message send failure/offline, photo/file/part refs, thread info panel, escalation pushback, attachment auto-save, keyboard composer behavior. | High |
| Scheduling calendar/dispatch/time off/availability/config/templates/pipeline | Week/month calendar, dispatch board, assignments, time-off, weekly availability, config saves, short/long pipeline, AI dispatch. | C1 C2 C3 C4 C5 C6 | E2E Tests 9/16 include dispatch page PASS; page review has design/prompts queued; pre-release L/FF list flows. | Drag/drop dispatch, half-day, time-off conflict popup, config delete confirmations, save validation, iPhone calendar/board usability. | High |
| Tools dashboard/registry/detail/checkouts/maintenance/kits/admin | Tool checkout/return/trade, condition checks, kits, maintenance, QR verification, management page. | C1 C2 C3 C4 C5 C6 | Page plan lists all tool pages; usability tracker last run has C7 Tools evidence and PE-051 prompt filed; interactive iPhone Trucks/Tools-related tab present. | Condition check sheets, QR scan, lost/stolen, trade 7-day auto-complete, kit inspection, admin bulk actions, detents issue #268 follow-up. | High |
| Fleet dashboard/my truck/vehicles/detail/trailers/fuel/mileage/maintenance/inspections | Vehicle creation, assignment, usage, pre-trip inspections, trailer mini-warehouse, truck stock vs transfer area. | C1 C2 C3 C4 C5 C6 | E2E Test 8 PASS for vehicle/create/assign/mileage/detail; interactive Trucks PASS; AI context covers Vehicles. | My Vehicle worker account, pre-trip tied to clock-in, trailer inventory, fuel/mileage validation, inspection forms, dynamic type/tab overflow. | Medium |
| Reports timesheets/labor/pre-billing/bookkeeper/spending/profitability/daily/public/fleet/warehouse/scheduling reports | Filter, generate, export PDF/CSV, empty/error states, hat-gated financials. | C1 C2 C3 C4 C5 C6 | E2E Test 10 reports PASS/PARTIAL; page plan says Reports clean but design enhancement pending; some report pages fixed in usability tracker. | Native export/share, date filter validation, permission-gated money fields, large table horizontal scroll, public report route behavior. | Medium |
| Notebooks list/detail/job/templates/panel schedule/daily report | Create notebook, hierarchy, block editing, slash commands, job notebooks, templates, panel builder, sync conflicts. | C1 C2 C3 C4 C5 C6 | E2E Test 5 PASS for basic notebook/tasks/job notebook; interactive Notebooks PASS; AI context covers list only. | Block editor keyboard, photo attachments, unsaved block conflicts, panel schedule drag/PDF, template creation, per-block conflict UI. | High |
| Office dashboard/approvals/manage jobs/spending/warehouse exec/deletion approvals | Daily briefing, unified approvals, priority items, financial snapshot, background tasks, deletion approvals. | C1 C2 C3 C4 C5 C6 | Page plan documents design; E2E Reports via Office/spending partly PASS. | Approve/reject feedback, oldest-first queue, hat-gated financials, delete approval outcomes, empty queues, background task visibility. | Medium |
| Settings grouped router/themes/company/sync/bluetooth/security/AI/backups/export/reset/device/integrations/key/update/billing/about/templates | Search/grouped settings, save settings, sync scope, security, backup/export/reset safeguards, AI config, about/update. | C1 C2 C3 C4 C5 C6 | E2E Test 10 themes/about PASS; Sync page PASS/PARTIAL; AI coverage notes settings help gap. | Dirty tracking/discard confirmations, dangerous reset safeguards, native file backup/export, Bluetooth/device permissions, settings save success feedback, keyboard. | High |
| AI assistant and page help | Floating AI on all pages, page-specific context/help, read-only answers, filter/card activation, no mutating actions. | C2 C3 C4 C6 | `ai-page-context-coverage.md` validates 47 contexts and build checks; page review standard requires Help on all pages. | Tap AI/help on uncovered People/Office/Reports/Settings pages, verify context accuracy, verify no edit/delete actions. | Medium |
| Sync/offline/device security/native capabilities/background jobs | P2P sync, offline changes, conflict log, device registry/override, native save/import, updater/autostart, scheduler status. | C1 C2 C3 C4 C5 C6 | E2E Tests 11-15/17 mostly skipped or partial because native/two-device required. | Physical/simulator native run, two devices on LAN, network disconnect, conflict scenario, native dialogs, background job evidence. | High |

## What existing UI tests can cover now

Existing browser/Playwright-style UI tests and static checks are appropriate for:

- Route existence and page render smoke tests.
- Sidebar/account navigation at iPhone and iPad viewport sizes.
- Search/filter/reset behavior on list pages.
- Empty/loading/error component presence when seeded data can force those states.
- Basic CRUD flows that do not require native camera/file dialogs.
- Static standards: `.refreshable`, `.searchable`, `ErrorStateView`, `.sheet`, `interactiveDismissDisabled`, accessibility labels, hardcoded placeholders.
- Page-context/help registry consistency.

Recommended automated additions:

1. Add a route smoke suite that opens every route listed in pre-release B13 and fails on PlaceholderView/Text stubs, uncaught errors, or missing navigation title.
2. Add a form-sheet smoke suite per module: open create/edit sheets, submit empty, submit valid seeded data, cancel, and confirm the parent page remains usable.
3. Add static scanner reports as CI artifacts, but require manual triage before filing because prior usability runs show high false-positive rates for broad patterns.
4. Add a page-standard scanner that reports per page: help button, AI context notification, `.refreshable`, `.searchable`, `ErrorStateView`, `EmptyStateView`, `.interactiveDismissDisabled` where `isSaving` exists.

## What needs simulator/manual review evidence

Simulator/manual evidence is required for anything the existing browser/static checks cannot prove:

- iOS sheet gesture behavior, detents, and swipe-dismiss during active saves.
- Keyboard overlap/dismissal for long forms and numeric fields.
- Camera/QR permission states and scan-result navigation.
- Native share/file/print dialogs for import/export, labels, reports, backups.
- Location permission and GPS-dependent clock/dispatch behavior.
- Drag/drop, long-press, resize/rotate, and other gestures in floor plans, dispatch, panels, and tools.
- Offline/network disconnect, P2P sync, conflict resolution, and device override flows.
- Permission/privacy checks using at least Admin/Manager/Worker-style accounts.
- Dynamic Type and accessibility checks for icon-only controls, color meanings, and 44px touch targets.

## Evidence package expected for WEI-180 sign-off

For each area row above, collect:

1. Device/viewport: at minimum iPhone-width and iPad-width evidence; native iOS where the feature uses camera/file/location/share/keyboard-heavy flows.
2. Screenshot or video of the main page and at least one representative sheet/wizard/detail page.
3. A short pass/fail note for C1-C6.
4. Any failed behavior linked to a Paperclip/GitHub issue or Xcode prompt.
5. Confirmation whether existing automated evidence is enough or manual retest remains required.

## Highest-risk gaps to prioritize first

1. Native-only flows: QR/camera, file/share/print, offline/sync/device security, background jobs.
2. Complex multi-step writes: Orders receiving, movement wizard, floor plan/onboarding, dispatch, tool checkout/return/trade.
3. Permission/privacy: payment hold, financial reports, employee hats/permissions, worker vs manager navigation.
4. Keyboard-heavy forms: settings, scheduling, notebooks/block editor, job/clock questionnaires, pricing/forecasting numeric inputs.
5. Areas with queued designs/prompts rather than broad executed evidence: Chat, Scheduling advanced, Tools advanced, Fleet advanced, Reports, Office, Settings deep pages.

## Recommended execution order

1. Run static page-standard scanners and route smoke tests first; file obvious broken route/dead button issues.
2. Run iPhone + iPad simulator smoke for all high-traffic pages: Dashboard, Clock, Parts, Jobs, Warehouse, Orders, People, Scheduling, Settings.
3. Run native/device passes for QR, files, sync/offline, device management, and permissions.
4. Run area-specific deep passes in this order: Orders receiving/JPO, Warehouse movement/floor plan/audit, Clock/daily reports, Tools checkout/return, Scheduling dispatch, Notebooks editor, Settings reset/export/backup.
5. Update this matrix with PASS/PARTIAL/FAIL status and attach evidence links as WEI-180 child issues complete.

## Completion criteria for WEI-1944

This issue is complete when this planning matrix exists and can be used by follow-on QA/implementation agents to create focused verification tasks. It does not claim the app has passed all checks yet; it defines the checks and separates automated coverage from simulator/manual evidence requirements.
