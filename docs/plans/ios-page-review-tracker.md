# iOS Page-by-Page Review Tracker

> **Purpose:** Master tracking document for the iOS app design review, redesign, and page-level implementation process. Records what's been reviewed, design decisions made, prompts written, and what still needs work.
>
> **Workflow:** Claude reviews each page → identifies issues → records design decisions → writes Xcode AI prompts → user implements via Xcode AI → user reports results → Claude audits.
>
> **Prompt files:** `xcode-ai/fix-prompts/` (active) · `xcode-ai/fix-prompts/done/` (archived)
> **Prompt tracking:** `xcode-ai/fix-prompts/00-fix-order.md` (81 prompt entries)
> **Results log:** `xcode-ai/prompt-results-log.md`

---

## Review Progress Overview

| Area | Pages | Reviewed | Prompts | Status |
|------|-------|----------|---------|--------|
| Foundation (cross-cutting) | — | ✅ | 01-05 (5) | All DONE |
| Missing CRUD (cross-cutting) | — | ✅ | 06-08 (3) | All DONE |
| Security (cross-cutting) | — | ✅ | 09 (1) | DONE |
| Service Layer Bugs (cross-cutting) | — | ✅ | 10 (1) | DONE |
| Dashboard | 4 pages | ✅ | 12A-12F (6) | All DONE |
| Parts → Catalog | 1 page | ✅ | 13A-13E (5) | All DONE |
| Parts → Categories | 6 files | ✅ | 14A-14G (7) | All DONE |
| Parts → Brands | 1 page | ✅ | 11A-11C, 15A-15C (6) | All DONE |
| Parts → Suppliers | 1 page | ✅ | 15A-15C, 17A-17H (11) | 15A-C DONE; 17A-H queued |
| Parts → Pricing | 1 page | ✅ | 16A-16I (9) | 16A-D DONE; 16E-I queued |
| Parts → Companions | 1 page | ✅ | 19A-19K (11) | All queued |
| Parts → Forecasting | 1 page | ✅ | 23A-23B (2) | All queued |
| Parts → Import/Export | 1 page | ✅ | 24A (1) | Queued |
| QR System (cross-cutting) | multiple | ✅ | 20A-20D, 21A-21B (6) | All queued |
| Supplier Bridge (cross-cutting) | multiple | ✅ | 22A-22C (3) | All queued |
| Review Cleanup (cross-cutting) | multiple | ✅ | 18A (1) | Queued |
| Jobs | 11 files | ✅ Design | — | Design complete, prompts pending |
| People | 11 files | ✅ Design | — | Design complete, prompts pending |
| Orders | 14 files | ❌ | — | Not started |
| Warehouse | 15 files | ❌ | — | Not started |
| Scheduling | 12 files | ✅ Design | — | Design complete, prompts pending |
| Chat | 9 files | ✅ Design | — | Design complete, prompts pending |
| Tools | 7 files | ✅ Design | — | Design complete, prompts pending |
| Fleet | 17 files | ✅ Design | — | Design complete, prompts pending |
| Reports | 9 files | ❌ | — | Not started |
| Office | 6 files | ❌ | — | Not started |
| Notebooks | 7 files | ✅ Design | — | Design complete, prompts pending |
| Settings | 23 files | ❌ | — | Not started |

**Totals:** 81 prompts written · 32 DONE · 49 queued · 7 areas designed (prompts pending) · ~5 feature areas unreviewed

---

## Completed Reviews — What Was Done & Decisions Made

### Foundation Fixes (Prompts 01-05) — DONE

Cross-cutting audit of the entire app for structural issues.

| Prompt | What it fixed | Files touched |
|--------|--------------|---------------|
| 01 | Multiple `.sheet()` conflicts → single `.sheet(item:)` enum pattern | 7 files |
| 02 | Blank screens instead of errors → `@State loadError` + `ContentUnavailableView` everywhere | 19 files |
| 03 | Infinite loading spinners → timeout + retry | Multiple |
| 04 | Fake sync fools users → honest "not available yet" messages | 3 files |
| 05 | App crashes on DB failure → safe optionals, `AppCoreError` enum | AppCore |

**Key decisions:**
- **Single `.sheet(item:)` rule:** SwiftUI only respects the first `.sheet()` modifier. Use `ActiveSheet` enum.
- **Error visibility:** Every `loadData()` must have `@State private var loadError: String?` with UI display.
- **44px touch targets:** All tappable elements use `.frame(minHeight: 44)`.
- **Smart Cards are a PROGRAM STANDARD:** Stat card filters (tap to filter, tap again for all, counts on each card) replace horizontal chip bars on ALL list pages. This is the standard filter pattern across the entire app.
- **Help/Info button on ALL pages:** Every page gets a help button explaining what it does and how to use it.
- **Full audit trail on ALL parts:** `part_change_log` table tracks who changed what, when, across the entire app. Visible in part detail view.
- **AI Assistant capabilities (PROGRAM STANDARD):**
  - Has access to page-specific detailed info for the OPEN page
  - Has general read-only info for everything else in the program
  - Can activate/change card filters to surface relevant info on the current page
  - Can give instructions on what to click (but CANNOT navigate for the user)
  - Knows the full program layout and can guide users to the right page
  - LOCKED to user-specific info (respects hat permissions)
  - CANNOT edit, modify, or delete any data — strictly read + filter activation
  - Needs significant work — this is an ongoing feature, not a one-prompt fix

### CRUD & Security (Prompts 06-10) — DONE

| Prompt | What it fixed |
|--------|--------------|
| 06 | Missing add/edit/delete for employees, customers, job tabs |
| 07 | Missing PO line items, receive workflow, audit start |
| 08 | Missing time-off approval, chat channel creation |
| 09 | Weak PIN hashing → per-user salt + 10K iterations |
| 10 | Wrong table names, missing columns, broken counts in services |

### Dashboard (Prompts 12A-12F) — DONE

Full redesign of the Dashboard tab with 4 sub-tabs.

| Prompt | Feature |
|--------|---------|
| 12A | Navigation restructure: Overview, Clock, Daily Report, QR Scanner tabs. Clock removed from Jobs. |
| 12B | Clock-in status banner on Dashboard Overview |
| 12C | Inline clock-in with GPS-sorted job picker, shop/optional job link |
| 12D | GPS geofencing: auto-detect job transitions, lock until questionnaire answered |
| 12E | Enhanced Daily Report: my hours, team status, fast actions |
| 12F | Continuous QR scanner with lock/auto-lock |

**Key decisions:**
- Clock is a Dashboard feature, not a Jobs feature (users clock in/out all day regardless of which job they're browsing)
- GPS geofencing triggers questionnaire — can't ignore a location change
- QR scanner runs continuously with auto-lock after scan (prevents accidental double-scans)

### Parts → Catalog (Prompts 13A-13E) — DONE

| Prompt | Feature |
|--------|---------|
| 13A | Fixed search bar at top, always visible (was collapsible) |
| 13B | Always-visible filter chips row (was hidden behind toggle) |
| 13C | Part detail sheet with delete confirmation |
| 13D | Natural language search → auto-detects filters ("red copper fittings") |
| 13E | AI assistant reads/controls catalog filters via NotificationCenter |

**Key decisions:**
- Search always visible — users search constantly in the field
- NL search parses color, category, brand, type from natural language
- AI integration uses `NotificationCenter` for page context (`.catalogPageActive` / `.catalogPageInactive`)

### Parts → Categories (Prompts 14A-14G) — DONE

| Prompt | Feature |
|--------|---------|
| 14A | Brand > Color nesting (was flat list) |
| 14B | Alphabetical sort, count badges, bigger add buttons |
| 14C | Tree search / filter |
| 14D | Save error feedback in all 4 form sheets |
| 14E | Smart Delete: inventory check before delete, empty shelf mode with scheduled_deletions table |
| 14F | Office page for approving scheduled deletions (Admin/Manager) |
| 14G | Help button + hierarchy explainer for new users |

**Key decisions:**
- **Smart Delete:** Can't delete a category/brand/etc with active inventory. Instead: "Empty Shelf Mode" — schedule for deletion after stock depletes, with office approval workflow
- **Hierarchy:** Category → Style → Type → Brand → Color (5 levels). Brands nest under types, colors nest under brands.

### Parts → Brands & Suppliers (Prompts 11A-11C, 15A-15C) — DONE

| Prompt | Feature |
|--------|---------|
| 11A | Service methods for brand-supplier link/unlink |
| 11B | Brand detail view with linked suppliers list |
| 11C | Checkbox picker for managing brand-supplier links |
| 15A | Removed raw SQL from both pages → PartsService methods |
| 15B | Delete confirmations, save error feedback on both pages |
| 15C | Fixed nested .sheet conflict in SupplierDetailSheet |

### Parts → Pricing (Prompts 16A-16I) — 16A-D DONE, 16E-I QUEUED

| Prompt | Feature | Status |
|--------|---------|--------|
| 16A | Migration: pricing_tiers, price_history, cost_layer_consumptions tables | ✅ DONE |
| 16B | FIFO/LIFO cost engine: 9 service methods | ✅ DONE |
| 16C | Hierarchical pricing: Category→Style→Type→Brand→Part resolution | ✅ DONE |
| 16D | Pricing page UI rebuild: raw SQL removed, full rewrite (389→733 lines) | ✅ DONE |
| 16E | Price override flow: set tier pricing, confirm conflicts | ⏳ Queued |
| 16F | Bulk markup + settings: bulk edit, markup/margin toggle, stale threshold | ⏳ Queued |
| 16G | Stale alerts + receiving: price age warnings, verification during receive | ⏳ Queued |
| 16H | Catalog pricing + view modes: pricing columns on catalog, layout options | ⏳ Queued |
| 16I | Pricing AI integration: read-only AI for pricing questions | ⏳ Queued |

**Key decisions:**
- **FIFO for consumption:** Oldest cost batches consumed first when parts go to jobs
- **LIFO for returns only:** Most recent consumed batches restored first
- **Hierarchical pricing:** Category → Style → Type → Brand → Part. Most specific wins. Higher-level changes DON'T auto-replace lower overrides.
- **Override confirmation:** Strictly one-at-a-time. Each override shows old vs new, user picks Replace or Keep.
- **Markup vs Margin:** Company-wide setting (toggle in Settings). Markup default. Minimum margin = 0%.
- **Stale alerts:** Parts not price-updated in X days (default 90) flagged during ordering.

### Parts → Companions (Prompts 19A-19K) — ALL QUEUED

Companion rules: "when you buy X, you probably also need Y."

| Prompt | Feature |
|--------|---------|
| 19A | Migration: polls, votes, auto-discovery tables, type_id on sources/targets |
| 19B | Rules + points service: hierarchy CRUD, soft delete, co-occurrence engine |
| 19C | Polls + voting service: weekly polls, vote casting, admin controls |
| 19D | Page cleanup: raw SQL → service, error banners, orphan indicators |
| 19E | Rule form rebuild: cascading category/style/type pickers |
| 19F | Polls UI: 3rd tab, vote cards, admin lock/skip/preview |
| 19G | Clock-out integration: companion polls as optional Yes/No questions |
| 19H | Testing sandbox: "What If" scenario builder with real job data |
| 19I | Admin dashboard: voting accuracy, poll history, rule counts |
| 19J | Auto-discovery engine: style/type drill-down, app-launch trigger |
| 19K | AI integration: 4 read-only tools |

**Key decisions:**
- **Points-based auto-discovery:** Scans `job_parts` co-occurrences. 1 point per min(qty_A, qty_B) pair. Thresholds: 100 pts, 15+ co-occurrences, 15% confidence, 3-48 month window.
- **Weekly polls:** One new poll/week from highest-point pair. 30-day or all-voted expiry. `companion_vote_power` permission (Admin, Manager, Lead) controls weight.
- **Admin controls:** Lock result (vote_veto permission), Skip (-50 points), Preview next week.
- **Hierarchical cascade:** Category → Style → Type → Brand. Each level gets its own poll. Parent delete → children flagged red for 30 days, then auto-purge.
- **Training questions:** When no qualifying poll exists, show practice question from closest-to-threshold pairs.
- **Clock-out:** Polls 7+ days old appear as optional Yes/No during clock-out questionnaire.
- **Tied polls:** Don't re-ask for 2 months (`tied_cooldown_until`).
- **Rejection:** -100 points AND -100 likelihood per rejection. 5 rejections = permanently blocked (admin can reset).

### Parts → Forecasting (Prompts 23A-23H) — 23A DONE, 23B-H QUEUED

| Prompt | Feature | Status |
|--------|---------|--------|
| 23A | Cleanup: raw SQL → service, platform guards, recalculate button, trend indicators | ✅ DONE |
| 23B | AI integration: GetForecastDataTool, page context notifications, read-only | ⏳ Queued |
| 23C | Stat cards as toggle filters (replace chip bar) | ⏳ Queued |
| 23D | Per-location backbone: migration, per-location forecast service methods | ⏳ Queued |
| 23E | Forecast settings: per-location-type defaults + per-truck overrides, ADU vs APW, free space | ⏳ Queued |
| 23F | Target recommendation engine: daily pick, all 3 values, cooldown, category changes | ⏳ Queued |
| 23G | Location picker UI, recommendation cards with approve/dismiss | ⏳ Queued |
| 23H | Detail panel redesign: full part editor, stock health bars per location | ⏳ Queued |

**Key decisions:**
- **Trend indicators:** ADU-30 vs ADU-90 comparison. >15% = trending up (red arrow), <85% = trending down (green arrow), else stable.
- **Stat cards as filters:** Cards ARE the filters. Tap to filter, tap again to deselect. Chip bar deleted.
- **Per-location forecasting:** `location_stock_targets` table with per-location MIN/TARGET/MAX + forecast data.
- **Background recalc:** Daily auto-run + Dashboard task card. Manual button stays for on-demand.
- **Forecast auto-approve:** Per-part auto-add toggle + below MIN at location + ≥80% certainty. Below 80% → physical audit first. Auto-approve is per-location.
- **Truck/trailer below MIN:** Check if shop has stock first → stage movement. If shop doesn't have it → wishlist item.
- **Wishlist:** Separate from Procurement, feeds into it. 3 sections (User/Forecast/Auto). Per-location auto-approve.
- **Procurement redesign:** Demand consolidation (JPO + Wishlist + Forecast + Auto). Groups by part. All suppliers shown. Generic=supplier locked per job, Branded=any supplier.
- **Shop ADU (parts/day)** vs **Truck APW (parts/X-weeks)**. Per-truck configurable window (1-6 weeks).
- **Common vs Critical** per part per location. Auto-suggest category changes at 6 months.
- **Full plan:** See `docs/plans/inventory-intelligence-system.md`

### QR System (Prompts 20A-20D, 21A-21B) — ALL QUEUED

| Prompt | Feature |
|--------|---------|
| 20A | Reusable `QRScanSheet` component + Warehouse integration (PO scan, part/bin scan) |
| 20B | Orders integration (line item scan, supplier scan, PO lookup, JPO scan) |
| 20C | Jobs (clock-in scan) + Tools (checkout/return/registry scan) |
| 20D | Catalog (part/barcode/UPC/EAN scan) + People (badge scan) |
| 21A | QR Label PDF Engine: 6 sizes, 11 paper types, 6 layouts, sticker sheet support |
| 21B | QR Label Print UI: size/layout/paper pickers, used sticker picker, iOS native print |

**Key decisions:**
- **QRScanSheet:** Reusable component wrapping `IOSQRScanner` + `QRAutoFillService`. `expectedType: QREntityType?` filter — nil accepts any type.
- **Label sizes:** Square (2×2"), Tall (1.5×3"), Wide (3×1.5"), Long (4×1"), Small (1×1"), Standard (2×1")
- **Paper sizes:** Letter, Legal, A4, Avery 5160/5163/5164/5165/5167/8160, Thermal 2×1/4×6
- **Partial sheet printing:** `usedPositions: Set<Int>` — user taps visual grid to mark used sticker positions
- **Barcode support:** Catalog scan accepts manufacturer UPC/EAN in addition to WiredPart QR codes

### Supplier Communication Bridge (Prompts 22A-22C) — ALL QUEUED

| Prompt | Feature |
|--------|---------|
| 22A | Migration: `supplier_channel_bridges` + `supplier_messages` tables. Service methods for bridge channels. |
| 22B | UI: orange "Supplier" badges, detail page messaging, direction indicators, PO reference attachments |
| 22C | Job-linked supplier channels, supplier RFI integration, unread badges on job detail |

**Key decisions:**
- **Bridge approach:** No supplier user accounts. Internal users act as intermediaries. `direction` field (inbound/outbound) tracks message flow.
- **`invite_token`:** Reserved for future direct supplier access without full accounts.
- **Job context:** Supplier channels can be linked to specific jobs for job-scoped communication.

### Review Cleanup (Prompt 18A) — QUEUED

| Prompt | Feature |
|--------|---------|
| 18A | Error visibility in 3 category components, dead imports, minor bugs across reviewed pages |

---

## Designed Pages — Design Complete, Prompts Pending

These areas have comprehensive design plans saved in `docs/plans/`. Next step: read current code, write Xcode AI prompts.

### Jobs (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-jobs-pages.md`
**Files:** `JobsListPage`, `IOSJobDetailPage`, `IOSJobDetailTabView`, `IOSCreateJobSheet`, `IOSEditJobSheet`, `IOSClockPage`, `IOSDailyReportsPage`, `IOSQuestionnairePage`, `JobReportsPage`, `LaborPage`

**Key design decisions:**
- 7 job statuses: Active, On Hold, Payment Hold (workers see "On Hold", managers see "$"), Completed, Cancelled, Warranty, Continuous
- Smart cards on list page with AI summary per card (cached 1hr), stage progression bar, dual progress bars (hours + budget, only if data exists)
- Per-job dashboard with stage progression, smart cards, AI summary, today's activity, quick actions (hat-gated), warranty info, financial summary
- Continuous jobs: to-do driven, per-to-do warranty, only qualified workers, light gray appearance
- Payment hold: red banner, workers can't clock in, resume hat-locked
- Clock integration: to-do picker on clock-in, mark done + pick next, switch to-do, work type (New/Warranty), live timer, one-action job switch
- Warranty: default 1 year adjustable, continuous jobs get per-to-do warranty, warranty work classification with manager review
- Swipe actions: AI summary (right), status change (left, managers only)

### Chat (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-chat-pages.md`
**Files:** `IOSChannelsPage`, `IOSMessageThreadView`, `CreateChannelSheet`, `IOSQuestionsPage`, `IOSQAQuestionForm`, `IOSRFIListPage`

**Key design decisions:**
- Unified inbox: all messages/Q&A/RFI/supplier/DM in one sorted stream, unread float to top
- Smart cards: Unread, Messages, Q&A, RFI, Supplier, DMs, Job, All
- Thread info: iMessage-style inline expandable (tap header inside thread), shows source context, escalation ladder, quick actions
- Escalation: bidirectional up AND down chain (Worker <-> Lead <-> Manager <-> Office)
- Attachments: photos, PDFs, part/PO/job references (tappable links), auto-save to job notebook, mobile offload 3mo, auto-delete 5yr
- JPO Hold threads show in BOTH JPO detail AND Channels page (dual-homed)
- Auto-fill job context when clocked in (program-wide rule)
- Real-time via sync engine (no polling)

### Notebooks (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-notebooks-pages.md`
**Files:** `IOSNotebooksListPage`, `IOSNotebookDetailPage`, `IOSJobNotebooksPage`, `IOSNotebookTemplatesPage`, `AddNotebookEntrySheet`, `CreateNotebookSheet`

**Key design decisions:**
- Hierarchy: Section Groups -> Sections -> Pages (OneNote-style)
- Block-based editing: each block = one type (text, heading, photo, checklist, etc.), Notion-style
- Sync conflicts: per-block resolution, AI merge with Apple AI glow, version comparison, manual rewrite option
- Shortcut commands: /h1, /h2, /checklist, /photo, /part, /panel, /divider, etc.
- Two to-do types: Regular Work + Warranty Work. Question is a tag (not separate type).
- Panel Schedule Builder: dedicated tool, drag-drop circuits, dual breakers, multiple panel types (MDP to 2-space disconnect), custom paper sizes, company header with drag-drop designer
- Daily Report: system-generated from clock/to-do data, AI compiled + self-verified, template-driven (Office configures), user adds notes below system section
- Templates: job starter templates, page templates, report templates, configurable per job type/status in Office

### People (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-people-pages.md`
**Files:** `IOSEmployeesPage`, `IOSEmployeeDetailPage`, `IOSCustomersPage`, `IOSCustomerDetailPage`, `IOSContractorsPage`, `IOSContractorDetailPage`, `IOSContactsPage`, `IOSHatsPage`, `IOSPermissionsPage`, `IOSTeamsPage`, `PeopleRouter`

**Key design decisions:**
- People Dashboard: working today, off today, certs expiring, team assignments
- Employee detail: hat visibility (employees see own hats read-only, managers can toggle), GRDB removal needed
- Customer detail: full page with contact info, additional contacts, business info, billing & payment (hat-gated), job history, communication history, documents, stats
- Payment tracking: company setting (enable/disable), green-to-red bar showing on-time %, overdue alerts
- Contractor detail: subcontractors get full ratings (quality/on-time/reliability), GC and contractors get notes only
- Contacts: unified list with active/inactive sections, smart cards by type, sort by recently updated
- Teams: full detail page with member management, job assignments, team stats

### Scheduling (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-scheduling-pages.md`
**Files:** `IOSScheduleCalendarPage`, `IOSDispatchPage`, `IOSTimeOffPage`, `IOSWeeklyAvailabilityPage`, `IOSSubSchedulePage`, `IOSDispatchTemplatesPage`, `IOSTemplateBuilderSheet`, `CreateScheduleEntrySheet`, `CreateDispatchSheet`, `RequestTimeOffSheet`

**Key design decisions:**
- Calendar: week + month views, half-day support
- Dispatch: drag-and-drop Gantt-style board, job stage shown, crew history (3mo), crew continuity tracking, time-off conflict popup
- Short-Term Pipeline: Start Anytime (target 3+), Schedule Needed (target 2+), Favorite GC (target 1+), Small Jobs pool
- Long-Term Pipeline: 3-year timeline view, capacity bars by month, callback tracking, bid tracking (simple)
- AI dispatch: 3 options with points-based reasoning, dedicated AI chat for modifications, learns from dispatcher picks
- Flex pool: unassigned jobs for self-assign (hat-gated), ready-to-start vs needs-contact types
- Capacity: work-days (person-days), based on historical job averages not estimates
- Job estimation questionnaire: grouped questions, stage-aware, "?" for unknowns, AI learns which questions matter
- Weekly reviews: delay factors, unanswered questions, on-track check
- End-of-job reviews: estimate vs actual, categorized delays, crew feedback, GC rating
- AI Smart Question System: suggests new questions after 15+ jobs, stage-specific, rejected questions log with AI reconsideration, history-based suggestions (GC/area/type)

### Tools (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-tools-pages.md`
**Files:** `IOSToolsDashboardPage`, `IOSToolRegistryPage`, `IOSToolCheckoutsPage`, `IOSToolMaintenancePage`, `IOSToolKitsPage`, `IOSToolAdminPage`, `IOSToolsRouter`

**Key design decisions:**
- Dashboard quick actions: pick action FIRST (Checkout/Return/Report Issue), then scan QR or type ID
- Tool detail: full checkout history, maintenance log, version history (2yr), attached parts
- Edit verification: any user can edit, but without hat → PENDING → manager notified → must scan QR to unlock approve/reject
- Four kit types: Consumable-Only, Tool+Consumable, Mixed, Tools-Only
- Kit features: missing tools status, inspection checklist, restock consumables, condition check on checkout AND return
- Tool trade: initiator condition check → request → receiver condition check → accept/decline. 7-day auto-complete if no response.
- Five maintenance types: time-based, usage-based, schedule-based, decreasing-based (confidence decay), condition-triggered
- Management page (renamed from Admin): bulk actions, categories/types config, company policies, location assignment, audit trail

### Fleet (Design: 2026-03-23)

**Plan file:** `docs/plans/ios-fleet-pages.md`
**Files:** `IOSFleetDashboardPage`, `IOSVehiclesPage`, `IOSVehicleDetailPage`, `IOSMyTruckPage`, `IOSTruckToolsPage`, `IOSFuelPage`, `IOSMileagePage`, `IOSMaintenancePage`, `IOSInspectionsPage`, `IOSTelematicsPage`, `IOSTrailersPage`, `IOSTrailerDetailPage`, `IOSTrailerLocationsPage`, `IOSCreateVehicleSheet`, `IOSCreateTrailerSheet`, `IOSAssignDriverSheet`, `FleetRouter`

**Key design decisions:**
- My Vehicle = primary worker view, opens first for field workers, smart cards (Tools On Board, Parts On Board, Tank, Maintenance Due)
- Two truck inventory types: Truck Stock (permanent, MIN/TARGET/MAX) vs Transfer Area (temporary logistics)
- Trailers = mini warehouses with own shelves/drawers, own MIN/TARGET/MAX, AT SHOP uses target only, NOT AT SHOP uses full MIN/MAX
- Vehicle detail: 7 tabs (Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections)
- Pre-trip inspections: residential-sized checklist, customizable per vehicle/trailer type, ties into clock-in
- Fleet dashboard KPIs: smart cards for vehicles/active/maintenance due/overdue inspect/trailers/fuel/miles/cost
- Fleet reports live in Reports section (not Fleet)
- Code quality: cleanest section — zero GRDB imports, zero raw SQL, design enhancement only

---

## Unreviewed Pages — What Still Needs Review

Each area below needs: (1) read every file, (2) identify issues, (3) record design decisions, (4) write prompts.

### Parts → Import/Export
**Files:** `PartsImportExportPage.swift`
**Expected issues:** Raw SQL, service layer violations, error handling, file picker UX


### Orders (14 files)
**Files:** `IOSPurchaseOrdersPage`, `IOSPODetailPage`, `CreatePOSheet`, `IOSJPOsPage`, `IOSJPODetailPage`, `IOSUnifiedOrderPage`, `IOSProcurementPage`, `IOSReceiveShipmentPage`, `IOSOrderStagingPage`, `IOSApprovalsPage`, `IOSReturnsPage`, `CreateReturnSheet`, `SupplierPickerSheet`, `OrdersRouter`
**Expected issues:** PO lifecycle completeness, JPO→PO flow, receiving UX, approval workflow, return flow

### Warehouse (15 files)
**Files:** `WarehouseDashboardPage`, `IOSMovementWizard`, `WarehouseMovementsPage`, `WarehouseLocationsPage`, `IOSStagingPage`, `IOSReceivingPage`, `IOSAuditPage`, `IOSAuditSetupView`, `IOSAuditSummaryView`, `IOSInventoryGridPage`, `IOSWarehouseReturnsPage`, `IOSWarehouseToolsPage`, `IOSWarehouseNetworkPage`, `IOSWarehouseSettingsPage`, `WarehouseRouter`
**Expected issues:** Movement wizard flow, location management, audit workflow, dashboard KPIs


### Reports (9 files)
**Files:** `IOSTimesheetsPage`, `IOSLaborOverviewPage`, `IOSPreBillingPage`, `IOSBookkeeperExportPage`, `IOSSpendingPage`, `IOSProfitabilityPage`, `IOSDailyReportsSummaryPage`, `IOSPublicReportView`, `IOSReportsRouter`
**Expected issues:** Date range pickers, export functionality, period locking, data accuracy

### Office (6 files)
**Files:** `IOSManageJobsPage`, `IOSSpendingDashboardPage`, `IOSWarehouseExecPage`, `IOSDeletionApprovalsPage`, `OfficePlaceholderView`, `OfficeRouter`
**Expected issues:** Manager-level views, approval workflows, executive summaries


### Settings (23 files)
**Files:** `AppConfigPage`, `ThemesPage`, `NotificationPrefsPage`, `CompanyProfilesPage`, `SyncPage`, `BluetoothPage`, `SecurityAdminPage`, `AuditLogPage`, `IOSAIConfigPage`, `IOSBackupsPage`, `IOSDataExportPage`, `IOSDatabaseResetPage`, `IOSDeviceManagementPage`, `IOSIntegrationsPage`, `IOSKeyManagementPage`, `IOSRemoteSyncPage`, `IOSSharedChannelsPage`, `IOSSupplierBridgePage`, `IOSUpdateProtocolPage`, `IOSBootstrapAdminPage`, `IOSClockOutQuestionsPage`, `PDFSettingsPage`, `BillingPayPage`, `AboutPage`, `SettingsRouter`
**Expected issues:** Settings persistence, sync configuration, security admin completeness, AI config

---

## Common Issues Found Across Reviews

These patterns recur and should be checked on every page:

1. **`import GRDB` in UI files** — must use service layer, not raw SQL
2. **Multiple `.sheet()` modifiers** — only one per view, use `ActiveSheet` enum
3. **Missing error visibility** — `loadError` state + UI display in every page
4. **`#if os(iOS)` / `#elseif os(macOS)` guards** — app is iOS-only, remove
5. **Missing delete confirmations** — every delete needs `.alert` confirmation
6. **Missing save/edit error feedback** — form sheets need `saveError` + `isSaving` state
7. **Missing `.refreshable`** — every list should support pull-to-refresh
8. **Missing `.searchable`** — lists with 10+ items need search
9. **Hardcoded zero counts** — badges showing 0 instead of querying real data
10. **No AI integration** — each page should post context notifications for the AI panel

---

## Implementation Order

The prompt chains should be implemented in this order (dependencies flow downward):

```
DONE:  01-05 (foundation) → 06-10 (CRUD + security)
DONE:  11A-C (brands-suppliers) → 12A-F (dashboard) → 13A-E (catalog) → 14A-G (categories)
DONE:  15A-C (brands+suppliers cleanup) → 16A-D (pricing foundation)

NEXT:  16E-I (pricing advanced)
THEN:  17A-H (suppliers)
THEN:  18A (cleanup pass)
THEN:  19A-K (companion rules)
THEN:  20A-D (QR per-module)
THEN:  21A-B (QR labels)
THEN:  22A-C (supplier bridge)
THEN:  23A-B (forecasting)

DESIGNED (need prompts written):
  - Jobs (see docs/plans/ios-jobs-pages.md)
  - Chat (see docs/plans/ios-chat-pages.md)
  - Notebooks (see docs/plans/ios-notebooks-pages.md)
  - People (see docs/plans/ios-people-pages.md)
  - Scheduling (see docs/plans/ios-scheduling-pages.md)
  - Tools (see docs/plans/ios-tools-pages.md)
  - Fleet (see docs/plans/ios-fleet-pages.md)

THEN:  Page-by-page reviews for remaining 5 feature areas (Orders, Warehouse, Reports, Office, Settings)
```

---

*Last updated: 2026-03-23*
