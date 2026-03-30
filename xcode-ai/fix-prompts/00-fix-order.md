# Fix Prompt Order — WiredPart iOS Audit Fixes

Run these prompts in order. Each one ends with "start prompt N next" so you can chain them.

| # | Area | What It Fixes (User Perspective) | Status |
|---|------|--------------------------------|--------|
| 01 | Sheet/Popup Dismissal | Popups don't close properly, stale data after closing forms | DONE |
| 02 | Error Visibility | User sees blank screens instead of error messages | DONE |
| 03 | Infinite Spinners | Pages get stuck on loading spinner forever | DONE |
| 04 | Stub Sync & Placeholders | Fake sync fools users, visible "Phase X" placeholder text | DONE |
| 05 | AppCore Safety | App can crash on launch if database fails | DONE |
| 06 | Missing CRUD — Jobs & People | Can't add/edit employees, customers; job tabs show placeholder text | DONE |
| 07 | Missing CRUD — Orders & Warehouse | Can't add line items to orders, no receive workflow, no audit start | DONE |
| 08 | Missing CRUD — Scheduling & Chat | Can't approve time-off, can't create chat channels | DONE |
| 09 | Security Hardening | PIN hashing is weak, invalid tokens treated as valid | DONE |
| 10 | Service Layer Bugs | Wrong table names, missing columns, broken counts | DONE |
| 11A | Brand-Supplier Service | Add link/unlink methods to PartsService | DONE |
| 11B | Brand Detail Sheet | Brand detail view with supplier list | DONE |
| 11C | Brand Supplier Picker | Checkbox picker for managing brand-supplier links | DONE |
| 12A | Dashboard Nav Changes | Add 4 Dashboard tabs, remove Clock from Jobs | DONE |
| 12B | Clock Status Banner | Show clock-in status on Dashboard Overview | DONE |
| 12C | Inline Clock + GPS Jobs | GPS-sorted job picker, shop/optional job link | DONE |
| 12D | GPS Geofencing | Auto-detect job transitions, lock until answered | DONE |
| 12E | Enhanced Daily Report | My hours, team status, fast actions | DONE |
| 12F | Fast QR Scanner | Continuous camera scan with lock/auto-lock | DONE |
| 13A | Catalog Search Bar | Fixed search bar at top, always visible | DONE |
| 13B | Catalog Filter Chips | Always-visible filter row, no toggle | DONE |
| 13C | Catalog Detail Sheet | Fix part detail sheet + delete confirmation | DONE |
| 13D | Catalog NL Search | Smart natural language search → auto-filters | DONE |
| 13E | Catalog AI Context | AI assistant reads/controls catalog filters | DONE |
| 14A | Categories Brand>Color Nesting | Tree shows flat brands/colors; should nest colors under brands | DONE |
| 14B | Categories Sort + Badges + Buttons | Alphabetical sort, count badges, bigger add buttons | DONE |
| 14C | Categories Tree Search | No way to search/filter the hierarchy tree | DONE |
| 14D | Categories Form Error Feedback | Save errors invisible in all 4 form sheets | DONE |
| 14E | Categories Smart Delete | No inventory check before delete, no empty shelf mode | DONE |
| 14F | Deletion Approval Page | Office page for approving scheduled part deletions | DONE |
| 14G | Categories Help + Guidance | No onboarding guidance for new users on hierarchy concept | DONE |
| 15A | Brands+Suppliers Service Layer | Both pages use raw SQL instead of PartsService methods | DONE |
| 15B | Brands+Suppliers Delete + Errors | No delete confirmation, save/delete errors invisible | DONE |
| 15C | Supplier Detail Nested Sheet | Nested .sheet conflict in SupplierDetailSheet | DONE |
| 16A | Pricing Migration + Models | No tables for FIFO batches, hierarchical tiers, price history | DONE |
| 16B | FIFO/LIFO Cost Engine | No service methods for batch costing, weighted average, returns | DONE |
| 16C | Hierarchical Pricing Service | Can't set prices at category/style/type level with cascade | DONE |
| 16D | Pricing Page UI Rebuild | Page uses raw SQL, no tier badges, no hierarchy awareness | DONE |
| 16E | Price Override Flow | No way to set tier pricing and confirm override conflicts | DONE |
| 16F | Bulk Markup + Settings | No bulk edit, no markup/margin mode toggle, no stale threshold | DONE |
| 16G | Stale Alerts + Receiving | No stale price warnings, no price verification during receiving | DONE |
| 16H | Catalog Pricing + View Modes | No pricing on catalog page, only one pricing view layout | DONE |
| 16I | Pricing AI Integration | No AI assistant for pricing page tasks | DONE |
| 17A | Supplier Migration + Models | No account_number column, no StockMovement model, no traceability | DONE |
| 17B | Supplier Form Rebuild | Only 7 of 15+ fields editable, missing rep/delivery/account fields | DONE |
| 17C | Supplier Performance Scores | Quality/on-time/reliability not auto-calculated from real data | DONE |
| 17D | Supplier Detail Rebuild | Missing brands, PO history, part count in detail view | DONE |
| 17E | Supplier Contacts Integration | No multi-contact support, no link to People system | DONE |
| 17F | Supplier Sort + Field Fix + Pricing Display | No sort options, wrong field mapping, no supplier costs on pricing page | DONE |
| 17G | Brands Detail Sheet Fix | Double .sheet conflict, hardcoded supplierCount=0 | DONE |
| 17H | Supplier AI Integration | No AI assistant for suppliers page (read-only) | DONE |
| 18A | Review Cleanup | Error visibility in 3 category components, dead imports, minor bugs | DONE |
| 19A | Companion Migration + Models | No tables for polls, votes, auto-discovery, no type_id on sources/targets | DONE |
| 19B | Companion Rules + Points Service | 11 service methods: hierarchy rules CRUD, soft delete, co-occurrence points engine | DONE |
| 19C | Companion Polls + Voting Service | 12 methods: weekly polls, casting votes, admin lock/skip, training questions | DONE |
| 19D | Companion Page Cleanup | Raw SQL → service calls, soft delete, error banners, orphan indicators | DONE |
| 19E | Companion Rule Form Rebuild | Individual part pickers → cascading category/style/type pickers with level control | DONE |
| 19F | Companion Polls UI | 3rd tab "Polls", vote cards, admin controls (lock/skip/preview), training questions | DONE |
| 19G | Companion Clock-Out Integration | Wire questionnaire into clock-out, add companion polls as optional questions | DONE |
| 19H | Companion Testing Sandbox | "What If" scenario builder with real job data, matched rules, next level preview | DONE |
| 19I | Companion Admin Dashboard | Voting accuracy table, poll history, manual vs auto-discovered rule counts | DONE |
| 19J | Companion Auto-Discovery Engine | Style/type drill-down, runAutoDiscoveryCycle orchestrator, app launch trigger | DONE |
| 19K | Companion AI Integration | 4 read-only AI tools: rules, polls, co-occurrence explain, voting summary | DONE |
| 20A | QR Warehouse Integration | Reusable QRScanSheet, scan PO for receiving, scan part/bin for movements | DONE |
| 20B | QR Orders Integration | Scan part to add PO line item, scan supplier, scan PO for lookup | DONE |
| 20C | QR Jobs + Tools Integration | Scan job for clock-in, scan tool for checkout/return, tool registry lookup | DONE |
| 20D | QR Catalog + People Integration | Scan part/barcode in catalog, scan employee badge for lookup | DONE |
| 21A | QR Label PDF Engine | No way to print QR labels; PDF generator with 6 sizes, 11 paper types, 6 layouts | DONE |
| 21B | QR Label Print UI | Label print sheet with size/layout/paper pickers, used sticker picker, iOS print | DONE |
| 22A | Supplier Bridge Migration + Service | No supplier communication; bridge tables, channel creation, direction tracking | DONE |
| 22B | Supplier Bridge UI | Supplier channel badges, detail page messaging, PO reference attachments | DONE |
| 22C | Supplier Bridge Job Channels | Job-linked supplier channels, supplier RFI integration, unread badges on jobs | DONE |
| 23A | Forecasting Page Cleanup | Raw SQL → service layer, platform guards, recalculate button, trend indicators | DONE |
| 23B | Forecasting AI Integration | AI tool for forecast queries, page context notification, read-only | DONE |
| 23C | Forecasting Stat Card Filters | Delete chip bar, stat cards act as toggle filters | DONE |
| 23D | Forecasting Location Backbone | Migration: location_stock_targets, per-location forecast service methods | DONE |
| 23E | Forecast Settings Migration | forecast_settings (ADU/APW per location), location_free_space, seed defaults | DONE |
| 23F | Target Recommendation Engine | Daily recommendation, approve/dismiss, category changes, ADU+APW | DONE |
| 23G | Forecasting Location UI | Location picker, recommendation filter + cards, approve/dismiss actions | DONE |
| 23H | Forecast Detail Panel Redesign | Full part editor, stock health bars per location, editable MIN/TARGET/MAX | DONE |
| 24A | Import/Export Redesign | Service layer, field selection export, import preview + per-conflict resolution | DONE |
| 26A | PO List Cleanup | Platform guard, count badges, date formatting, loadError guard | DONE |
| 26B | PO List Swipe + Sort | Swipe actions with AI summary, sort options, awaiting delivery KPI | DONE |
| 26C | PO Detail Lifecycle | Status-based actions (7 states), Drafting status, cancel confirmations | DONE |
| 26D | PO Detail Supplier CRM | Supplier contact info, score bars, tabbed notes (PO + Supplier) | DONE |
| 26E | Parts Order Management | NEW page: supplier-centric cross-PO view, dual filters, multi-select actions | DONE |
| 26F | PO Detail Jobs + Timeline | Job grouping, delivery timeline bars, inline draft editing, receipt history | DONE |
| 27A | JPO List Cleanup | ActiveSheet, QR scan, count badges, Create JPO with clock auto-fill | DONE |
| 27B | JPO Per-Part Status | Migration: line_status + delivery_option, smart routing (stock → transfer vs approval) | DONE |
| 27C | JPO Detail Redesign | Per-part approve/hold/reject, bulk actions, delivery options, PO linkage | DONE |
| 27D | JPO Hold + Chat | Per-part chat thread, question prompt, auto-membership, chat indicator on list | DONE |
| 27E | Full Audit Trail | part_change_log table, who-did-what logging, PartHistoryView component (cross-cutting) | DONE |
| 28A | Procurement Redesign | Demand consolidation, stock logic, pull options, smart cards, bring-to-target buttons | DONE |
| 28B | Procurement Suppliers | Per-part supplier pick, cheapest/rated/fastest highlight, 2PM cutoff, split by JPO | DONE |
| 28C | Procurement PO Preview | Supplier-grouped preview, partial generation, save for later | DONE |
| 28D | Job Stage Planner | Stage model, category mapping, held/released parts, auto-release, stage settings | DONE |
| 29A | Receiving Fix | Hardcoded user ID, ActiveSheet pattern, platform guard | DONE |
| 29B | Returns Fix | ErrorStateView, console→UI errors, platform guard, smart cards | DONE |
| 29C | Approvals Dashboard | Smart cards, reject reason, actionError display, multi-type approvals | DONE |
| 29D | Orders Cleanup | Remove UnifiedOrderPage, update router tab order, consolidate SupplierPicker | DONE |
| 30A | JPO Creation Layout | 3-panel (search/cart/suggestions), job auto-fill, delivery options, stock indicators | DONE |
| 30B | JPO Creation Search | AI-powered search (cart + last 5 context), QR scan, ⚡ best match, internet toggle | DONE |
| 30C | JPO Creation Suggestions | Companion rules (5) + AI picks (3), context switch on cart selection | DONE |
| 30D | JPO Creation Feedback | Qty confirm dialog, companion points, ratio learning, AI→rule promotion | DONE |
| 30E | JPO Creation Submit | Create JPO + lines, smart routing, replace IOSUnifiedOrderPage | DONE |
| 31A | Warehouse Dashboard | Remove GRDB, smart cards, fix quick actions, ActiveSheet, platform guard | DONE |
| 31B | Warehouse Movements | Remove GRDB, ActiveSheet, smart cards, platform guard | DONE |
| 31C | Warehouse Locations | Remove GRDB, action buttons in detail sheet, platform guard | DONE |
| 31D | Warehouse Staging | Swipe confirmation, batch clear, smart cards, platform guard | DONE |
| 31E | Warehouse Receiving | Start/continue session actions, smart cards, platform guard | DONE |
| 31F | Warehouse Audit | Fix setup stub, finalize/adjust actions, certainty tie-in TODO, platform guards | DONE |
| 31G | Warehouse Inventory Grid | Location picker, group by type, low-stock styling, actions, smart cards | DONE |
| 31H | Warehouse Returns+Tools+Network+Settings | Actions for display-only pages, remove dummy data, fix errors | DONE |
| 31I | Warehouse Router | Fix unknown route → ErrorStateView, verify all 11 routes | DONE |
| 32A | Navigation Restructure | Sidebar order (daily→work→admin), tab reorder, rename, People consolidation | DONE |
| 32B | Empty Catch Blocks | Fix all empty catch {} and catch { print() } blocks (5+ files) | DONE |
| 32C | Guard Without Error | Fix 42 files with guard-let-service that silently returns | DONE |
| 32D | Platform Guards Batch 1 | Remove #if os(iOS) from all Features/ files (~50 files) | DONE |
| 32E | Platform Guards Batch 2 | Remove #if os(iOS) from AI/Auth/App/Nav/Scanning/Sync/Shared (~57 files) | DONE |
| 32F | ActiveSheet Conversion | Convert 19 files from showXxx Bool to ActiveSheet enum | DONE |
| 32G | Print-to-State Errors | Replace print() error logging with UI state in 25+ files | DONE |
| 32H | Refreshable + Searchable | Add missing .refreshable and .searchable to 58 list pages | DONE |
| 32I | AI Button Dedup | Remove duplicate AI buttons from page toolbars — one global button only | DONE |
| 32J | Force Unwrap + DispatchQueue | Fix force unwraps in services, replace DispatchQueue with async/await | DONE |
| 33A | Help/Info Buttons | Add PageHelpSheet component + help button to ALL pages (program standard) | DONE |
| 33B | Clock Page Fix | Fix "no such column: address" SQL error + add Lunch/Break/Supply Run buttons | DONE |
| 33C | JPO Smart Routing | Stock check before approval — transfer from shelf vs send to procurement | DONE |
| 33D | Procurement Pull Actions | Wire TODO pull option buttons to actual warehouse movements | DONE |
| 33E | PO Detail Placeholders | Wire 6 "Coming Soon" sheet stubs to real functionality | DONE |
| 33F | Receiving Routing Flow | Full condition check + smart routing (used/damaged/good → staging/shelf/returns) | DONE |
| 33G | Staging Box Management | Physical box system: sizes, labels, full/open, contents view, move-all | DONE |
| 33H | Duplicate Wizard Cleanup | Delete inline wizard from WarehouseMovementsPage, use IOSMovementWizard | DONE |
| 34A | UI Quality Audit | Sheet dismiss, sticky buttons, navigation links, data display, form validation | ✅ done (verified 2026-03-29) |
| 35A | Daily Report Submit Stubs | Wire 2 TODO submit buttons + remove service bypass + raw SQL in Dashboard | ✅ done (verified 2026-03-29) |
| 35B | Job Detail Tab Fixes | 5 print() catches → state, client-side→server-side filtering, dead code | ✅ done (verified 2026-03-29) |
| 35C | ~~Scheduling Raw SQL~~ | ~~IOSSubSchedulePage + IOSWeeklyAvailabilityPage: GRDB removal + error states~~ | **SKIP** — GRDB/DispatchQueue already removed (verified 2026-03-29) |
| 35D | GeofenceAlertView Fix | Remove GRDB + raw SQL, fix silent clock-in/out errors, show error feedback | ✅ done (verified 2026-03-29) |
| 35E | Fleet GRDB + ErrorStateView | Remove GRDB from 2 pages, wire ErrorStateView in 6 pages, remove print() | ✅ done (verified 2026-03-29) |
| 35F | Audit Session ID + PO Delete Nav | Fix hardcoded session ID 0, navigate back after draft delete, save reject reason | ✅ done (verified 2026-03-29) |
| 35G | ~~Settings GRDB Removal~~ | ~~Remove GRDB + raw SQL from 10 Settings pages, replace DispatchQueue~~ | **SKIP** — all 10 Settings pages already clean (verified 2026-03-29) |
| 35H | Companion GRDB + Hats Delete | Remove GRDB from 2 Companion sheets, add hat delete confirmation | ✅ done (verified 2026-03-29) |
| 35I | ~~Reports + Tools GRDB~~ | ~~Remove GRDB from PreBilling, BookkeeperExport, ToolKits~~ | **SKIP** — GRDB already removed (verified 2026-03-29) |
| 36A | Floor Plan Migration | 7 tables: floor_plans, features, units, levels, areas, bins, assignments + 15 service methods | ✅ done (verified 2026-03-29) |
| 36B | Floor Plan Editor UI | Grid view, drag-drop units, drill-in levels→areas→bins, sticker checklist, movable section | ✅ done (verified 2026-03-29) |
| 36C | Floor Plan Navigation | Warehouse GPS directions, QR scan full location view, user position tracking | ✅ done (verified 2026-03-29) |
| 36D | Onboarding Wizard | 6-step progressive setup, Quick Count mode, Save & Exit, AI suggestions | ✅ done (verified 2026-03-29) |
| 37A | Audit Confidence Migration | 8 tables: confidence, sessions, counts, misplaced, user ratings, org ratings, consolidation | ✅ done (verified 2026-03-29) |
| 37B | Audit Count Tab UI | Hidden counts, speed mode, misplaced cart, quick audit prompts, walking path queue | ✅ done (verified 2026-03-29) |
| 37C | Organization Tab | Consolidation voting, org checklist, rating rollup area→unit→row→warehouse | ✅ done (verified 2026-03-29) |
| 37D | User Ratings + Leaderboard | Leaderboard for all, detail for managers, multi-user consensus, training suggestions | ✅ done (verified 2026-03-29) |
| 38A | Break/Lunch Compliance | 4-tier policy (state+company), break_records, auto-fill, 15-min rounding, state presets | ✅ done (verified 2026-03-29) |
| 38B | Break/Lunch UI | Clock page buttons, settings page, clock-out questionnaire, bonus tracking | ✅ done (verified 2026-03-29) |
| 39A | Hats Permission Audit | Cross-cutting: replace hardcoded role checks with hasPermission(), seed new permission keys | ✅ done (verified 2026-03-29) |
| 40A | Clock To-Do Integration | Clock-in to-do picker, Mark Done + Pick Next, work type selector (New/Warranty) | ✅ done (verified 2026-03-29) |
| 40B | Clock Live Timer | Live elapsed timer, today's hours per job/to-do, Switch Job one-action button | ✅ done (verified 2026-03-29) |
| 41A | Teams Detail Page | IOSTeamDetailPage with members/roles/jobs, smart cards on list page, add/remove members | ✅ done (verified 2026-03-29) |
| 42A | Chat Unified Inbox | Unified inbox all message types, smart cards, unread badges, message preview | ✅ done (verified 2026-03-29) |
| 42B | Chat Thread Info | iMessage-style expandable info panel: source context, escalation, people, quick actions | ✅ done (verified 2026-03-29) |
| 42C | Chat Attachments | Photo/file/part-ref attachments, composer buttons, auto-save to job notebook | ✅ done (verified 2026-03-29) |
| 42D | Q&A Escalation | Visual escalation ladder (Worker⇄Lead⇄Manager⇄Office), push back, smart cards on Q&A/RFI | ✅ done (verified 2026-03-29) |
| 43A | Notebook Structure | Migration: section_groups, sections, block-based entries (9 block types), hierarchy service | ✅ done (verified 2026-03-29) |
| 43B | Notebook Detail Rebuild | Hierarchical layout, collapsible sections, block rendering, shortcut commands (/h1, /checklist) | ✅ done (verified 2026-03-29) |
| 43C | Notebook Templates | Job starter templates, page templates, template editor, "Create from Template" | ✅ done (verified 2026-03-29) |
| 43D | Panel Schedule | Panel schedule builder: circuit grid, breaker types, 240V spanning, PDF export | ✅ done (verified 2026-03-29) |
| 43E | Daily Report System | Auto-generated daily report from clock/to-do data, AI verification, user notes, templates | ✅ done (verified 2026-03-29) |
| 44A | People Dashboard | Who's working (live), who's off, expiring certs, team assignments, smart cards | ✅ done (verified 2026-03-29) |
| 44B | Employee Detail Rebuild | Remove GRDB/raw SQL, service layer edits, hat visibility rules, edit contact sheet | ✅ done (verified 2026-03-29) |
| 44C | Customer Detail Full | Contacts, billing (hat-gated), job history, communication log, lifetime stats | ✅ done (verified 2026-03-29) |
| 44D | Contractor Detail | Qualifications, rating (subs only), job history, notes, ActiveSheet fix | ✅ done (verified 2026-03-29) |
| 44E | Contacts Redesign | Smart cards by type, active/inactive sections, sort options, type badges | ✅ done (verified 2026-03-29) |
| 44F | Payment Tracking | Company setting enable/disable, green-to-red status bar, overdue alerts, payment records | ✅ done (verified 2026-03-29) |
| 45A | Jobs List Redesign | Smart cards (8 statuses), AI summary, stage bar, dual progress, payment hold privacy | ✅ done (verified 2026-03-29) |
| 45B | Job Detail Dashboard | Overview tab as dashboard: metrics, AI summary, today's activity, quick actions, warranty | ✅ done (verified 2026-03-29) |
| 45C | Job Types & Status | Migration: warranty fields, continuous job, payment hold, clock-in blocking | ✅ done (verified 2026-03-29) |
| 45D | Warranty To-Do | Work classification (regular/warranty), manager review, reclassification tracking, warranty timer | ✅ done (verified 2026-03-29) |
| 46A | Scheduling Calendar | Month view, day dots/badges, tap detail, half-day scheduling (AM/PM) | ✅ done (verified 2026-03-29) |
| 46B | Dispatch Board | Gantt-style board, employee bars, half-day, unassigned pool, time-off conflict warnings | ✅ done (verified 2026-03-29) |
| 46C | Short-Term Pipeline | Start Anytime/Schedule Needed/Favorite GC/Small Jobs, callback snooze, AI crew suggestions | ✅ done (verified 2026-03-29) |
| 46D | Long-Term Pipeline | 3-year timeline, monthly capacity bars, bid tracker, AI capacity warnings | ✅ done (verified 2026-03-29) |
| 46E | AI Dispatch | 3 suggestions with points scoring, dedicated AI chat, learning from picks, early finish | ✅ done (verified 2026-03-29) |
| 46F | Job Estimation | Questionnaire system, stage-aware, "?" unknowns, AI learning after 15+ jobs, capacity calc | ✅ done (verified 2026-03-29) |
| 47A | Tools Dashboard Redesign | Smart cards (Total/Checked Out/Maint Due/Missing), QR-first quick actions, recent checkouts | ✅ done (verified 2026-03-29) |
| 47B | Tool Detail Rebuild | Contents checklist, REQUIRED condition check, 2yr version history, edit-without-permission | ✅ done (verified 2026-03-29) |
| 47C | Kit Management | 4 kit types, missing tools status, full inspection checklist, restock consumables, kit history | ✅ done (verified 2026-03-29) |
| 47D | Tool Trade | Trade flow with condition checks, 7-day timeout, lost/stolen reporting (company vs personal) | ✅ done (verified 2026-03-29) |
| 47E | Tool Maintenance Types | 5 maintenance types: time/usage/schedule/decay/condition, confidence decay math | ✅ done (verified 2026-03-29) |
| 47F | Tool Management Page | Rename Admin→Management, bulk ops, categories, policies, locations, audit trail | ✅ done (verified 2026-03-29) |
| 48A | My Vehicle Primary | Smart cards, Truck Stock vs Transfer Area (MIN/TARGET/MAX), quick actions, trailer | ✅ done (verified 2026-03-29) |
| 48B | Vehicle Detail Tabs | 7 tabs: Overview, Parts, Tools, Assignments, Maintenance, Usage, Inspections | ✅ done (verified 2026-03-29) |
| 48C | Trailer Mini Warehouse | Storage units, own MIN/TARGET/MAX, shop vs field rules, location history | ✅ done (verified 2026-03-29) |
| 48D | Pre-Trip Inspection | Customizable checklist per vehicle type, 4 sections, Pass/Fail/Conditional, clock-in tie | ✅ done (verified 2026-03-29) |
| 48E | Fleet Dashboard KPIs | Smart cards (vehicles/active/maint/inspect/trailers), cost summary (hat-gated), maintenance | ✅ done (verified 2026-03-29) |
| 49A | Reports Categories | Reorganize: Labor, Financial, Fleet, Warehouse, Scheduling, Custom, Shared categories | ✅ done (verified 2026-03-29) |
| 49B | Reports Export | [Export PDF] + [Export CSV] toolbar on every report page, UIGraphicsPDFRenderer | ✅ done (verified 2026-03-29) |
| 49C | Fleet/Warehouse/Scheduling Reports | 10 new report pages: fuel, maint trends, mileage, utilization, inventory, backorders, etc. | ✅ done (verified 2026-03-29) |
| 49D | Report Builder | Pick type→fields→filters→generate, save configs, run saved reports with new dates | ✅ done (verified 2026-03-29) |
| 50A | Office Dashboard | AI daily briefing (cached 1hr), Needs Attention (priority colors), schedule, financials | ✅ done (verified 2026-03-29) |
| 50B | Unified Approvals | JPO + deletion + tool edit + warranty + time-off in one queue, inline actions, sorted by age | ✅ done (verified 2026-03-29) |
| 50C | Office Chat Channel | Auto-created Office channel, hat-gated membership, "Office" badge in inbox | ✅ done (verified 2026-03-29) |
| 50D | Office Router Cleanup | Remove report routes, add Dashboard/Approvals/Pipeline/Teams/Reports tabs | ✅ done (verified 2026-03-29) |
| 51A | Standard Filter Bar | Reusable StandardFilterBar: quick date filters + custom range + page-specific filters, apply to all pages | ✅ done (verified 2026-03-29) |
| 52A | Settings Grouped Nav | Reorganize SettingsRouter into 10 grouped sections with search | ✅ done (verified 2026-03-29) |
| 52B | Settings Operations Pages | Break/Lunch Policy, Tool Policies, Pre-Trip Checklists, Dispatch Preferences | ✅ done (verified 2026-03-29) |
| 52C | Settings Warehouse Pages | Forecast Config, Organization Thresholds, Audit Settings | ✅ done (verified 2026-03-29) |
| 52D | Settings Template Pages | Daily Report Templates, Job Estimation Questions, Report Templates | ✅ done (verified 2026-03-29) |
| 52E | Settings Functional Features | Wire Backups, Export, Update Check, AI Config, Sync Now to real code | ✅ done (verified 2026-03-29) |
| 52F | Settings Sync Classification | Sync scope indicators (company/personal/device) on all settings | ✅ done (verified 2026-03-29) |
| 53A | Safe Update System | #if DEBUG erase, backupDatabase(), restoreDatabase(), pre-migration backup | ✅ done (verified 2026-03-29) |
| 54A | Bluetooth Sync Activation | IOSSyncManager, SyncEngine, ChangeTracker, MultipeerManager wiring | ✅ done (verified 2026-03-29) |
| 54B | Sync Conflict Resolution UI | SyncConflictReviewPage, conflict notification banner, sync history | ✅ done (verified 2026-03-29) |
| 54C | Sync Device Pairing | Device pairing flow, performInitialSync, background continuous sync | ✅ done (verified 2026-03-29) |
| 54D | AI Sync Conflict Resolution | SyncConflictClassifier (5-level), AI merge, AIConflictResolutionView | ✅ done (verified 2026-03-29) |
| 55A | Final GRDB Cleanup | Remove GRDB from last 5 UI files | ✅ done — covered by 32D-E bulk passes |
| 56A | Full End-to-End Audit | Comprehensive audit specification | META — covered by 57A + 60-62 series |
| 57A | Final Cleanup Audit | Issue specification with file-by-file breakdown | META — fixes tracked in 60-62 series |
| 58A | Help Buttons All Pages | PageHelpSheet on all pages | ✅ done — same as 60G |
| **60A** | **Standard Date Filter Bar** | **Reusable StandardFilterBar component + wire to all list pages** | **✅ done (verified 2026-03-29)** |
| **60B** | **JPO Cart Builder Wiring** | **3-panel creation page: search/cart/suggestions, auto-fill from clock** | **✅ done (verified 2026-03-29)** |
| **60C** | **AI Conversation Memory** | **In-memory message history for FoundationModelsService** | **✅ done (verified 2026-03-29)** |
| **60D** | **Office Dashboard** | **IOSOfficeDashboardPage: AI briefing, attention items, schedule, financials** | **✅ done (verified 2026-03-29)** |
| **60E** | **Job Detail Dashboard** | **Overview tab with metric cards, stage progression bar, quick actions** | **✅ done (verified 2026-03-29)** |
| **60F** | **Receiving Back Confirmation** | **Confirmation dialog before discarding receiving data** | **✅ done (verified 2026-03-29)** |
| **60G** | **Help Buttons Visible** | **Help buttons in toolbar on 150+ pages** | **✅ done (verified 2026-03-29)** |
| **60H** | **First Launch Checklist** | **Getting Started checklist on dashboard for new users** | **✅ done (verified 2026-03-29)** |
| **60I** | **Silent Guard Bulk Fix** | **All guard-let-service returns set loadError/actionError** | **✅ done (verified 2026-03-29)** |
| **60J** | **Submit to Supplier Rename** | **"Mark as Submitted" + confirmation dialog + banner** | **✅ done (verified 2026-03-29)** |
| **60K** | **Stock Human Names** | **Warehouse location names from DB, "Warehouse #" fallback fixed** | **✅ done (verified 2026-03-29)** |
| **60L** | **Broken Sidebar Routes** | **/orders/parts + /orders/wishlist wired in NavigationConfig + router** | **✅ done (verified 2026-03-29)** |
| **60M** | **AI Page Context All** | **12+ page contexts in AI assistant panel** | **✅ done (verified 2026-03-29)** |
| **60N** | **AI Help Integration** | **HelpContentRegistry integrated with AI panel** | **✅ done (verified 2026-03-29)** |
| **60O** | **Wishlist Migration** | **Migration 057, WishlistService, functional IOSWishlistPage** | **✅ done (verified 2026-03-29)** |
| **60P** | **Unified Approvals** | **IOSUnifiedApprovalsPage: JPO + deletion + time-off + tool edit** | **✅ done (verified 2026-03-29)** |
| **60Q** | **Dispatch Drag Drop** | **DraggableWorker, .dropDestination, .draggable, conflict checking** | **✅ done (verified 2026-03-29)** |
| **60R** | **Flex Pool** | **Flex pool section on clock page, self-assign + clock-in** | **✅ done (verified 2026-03-29)** |
| **60S** | **Job Stage Bars** | **JobStageProgressBar component on job list + detail** | **✅ done (verified 2026-03-29)** |
| **60T** | **Background Task Log** | **Migration 058, BackgroundTaskService, dashboard integration** | **✅ done (verified 2026-03-29)** |
| **61A** | **Priority Colors Timeline** | **TimelinePriorityColor: time-based red/orange/yellow/green** | **✅ done (verified 2026-03-29)** |
| **61B** | **Old Chips to Smart Cards** | **SmartFilterCard on 10+ pages, zero old filter Capsule bars** | **✅ done (verified 2026-03-29)** |
| **61C** | **Auto-Fill Job Context** | **Q&A + Notebook forms auto-fill from active clock entry** | **✅ done (verified 2026-03-29)** |
| **61D** | **Touch Targets 44px** | **minHeight: 44 on primary action buttons** | **✅ done (verified 2026-03-29)** |
| **61E** | **Dead Buttons Fix** | **Zero empty closure buttons remain** | **✅ done (verified 2026-03-29)** |
| **61F** | **Orphaned Pages Wire** | **All pages reachable via router/navigation** | **✅ done (verified 2026-03-29)** |
| **61G** | **Placeholder NavLinks** | **Zero NavigationLinks to bare Text() placeholders** | **✅ done (verified 2026-03-29)** |
| **61H** | **People Dashboard Tab** | **people-dashboard tab in NavigationConfig, IOSPeopleDashboardPage wired** | **✅ done (verified 2026-03-29)** |
| **61I** | **Clock Break Explain** | **"End your break first to clock out" explanation shown** | **✅ done (verified 2026-03-29)** |
| **61J** | **Questionnaire Skip Guard** | **Skip hidden when hasUnansweredRequired, submit disabled until allRequiredAnswered** | **✅ done (verified 2026-03-29)** |
| **61K** | **Receiving Barcode Scan** | **Per-part barcode scan, auto-scroll to matched item** | **✅ done (verified 2026-03-29)** |
| **61L** | **Receiving Default Expected** | **Qty defaults to expectedQty, "Reset to Expected" button** | **✅ done (verified 2026-03-29)** |
| **62A** | **Refreshable Bulk** | **.refreshable on list pages, SearchableList wrapper** | **✅ done (verified 2026-03-29)** |
| **62B** | **Searchable Bulk** | **.searchable on 73+ files** | **✅ done (verified 2026-03-29)** |
| **62C** | **AI Dispatch Wire** | **AIDispatchService wired to AppCore** | **✅ done (verified 2026-03-29)** |
| **62D** | **Orphan Models Cleanup** | **CostsModels audited, all structs retained as ACTIVE** | **✅ done (verified 2026-03-29)** |
| **62E** | **Table Not Found Fallback** | **isTableNotFoundError in Break/DailyReport/AIDispatch/JobEstimation services** | **✅ done (verified 2026-03-29)** |
| **62F** | **Receiving Price Format** | **%.2f format (not %.5f)** | **✅ done (verified 2026-03-29)** |
| **62G** | **PO Number Safe** | **MAX-based generation prevents duplicates** | **✅ done (verified 2026-03-29)** |
| **62H** | **Receiving Unrouted Warning** | **showUnroutedWarning + confirmationDialog before completion** | **✅ done (verified 2026-03-29)** |
| **62I** | **PO Line Edit Sheet** | **POLineEditSheet struct, sheet(item:) pattern** | **✅ done (verified 2026-03-29)** |
| **62J** | **Notebook AI Merge** | **NotebookBlockConflict, detectBlockConflicts, resolveBlockConflict** | **✅ done (verified 2026-03-29)** |
| **62K** | **Weekly Review** | **IOSWeeklyReviewSheet, submitWeeklyReview, test coverage** | **✅ done (verified 2026-03-29)** |
| **62L** | **Multi-User Audit** | **multi_user_audit_assignments table + service methods** | **✅ done (verified 2026-03-29)** |
| **62M** | **JPO Hold Chat** | **Hold with chat thread link, lineStatus tracking** | **✅ done (verified 2026-03-29)** |
| **62N** | **PO Job Grouping** | **Line items grouped by job in PO detail** | **✅ done (verified 2026-03-29)** |
| **62O** | **PO Delivery Timeline** | **DeliveryTimelineBar component on PO detail** | **✅ done (verified 2026-03-29)** |
| **62P** | **PO Receipt History** | **receiptHistorySection in PO detail** | **✅ done (verified 2026-03-29)** |
| **62Q** | **JPO Bulk Hold Fix** | **bulkHoldReason TextEditor, all items get reason** | **✅ done (verified 2026-03-29)** |
| **62R** | **Location Permission** | **requestPermission checks .notDetermined only** | **✅ done (verified 2026-03-29)** |
| **62S** | **AI Filter All Pages** | **AIFilterRegistry on 6+ pages beyond catalog** | **✅ done (verified 2026-03-29)** |
| **62T** | **Audit Checklist Save** | **Audit results documented with 331 items** | **✅ done (verified 2026-03-29)** |
| 63A | Final Gate | Verification checkpoint (build, grep GRDB, counts) | META — gate check, not code |
| 63B | Final 9 Audit Fixes | Dashboard QR, AI dispatch, panel persist, chips, errors, guards, popups, dead code, office | ✅ done — tracked as 66A-C + 64D-F |
| 64A | Guided Onboarding Walkthrough | Getting Started checklist, NewUserWelcomeView, ModuleTourView | ✅ done — same as 65A |
| 64B | Comprehensive Per-Page Onboarding | OnboardingProgressManager, per-page tasks, OnboardingBanner, hat-aware | ✅ done — same as 65A |
| 64C | UI Stability: Errors + Popups | Silent guards, isTableNotFoundError, user-friendly errors, sheet dismiss | ✅ done — covered by 32B/C, 60I, 62E, 66C |
| 64D | Silent Guard Returns | Fix last 6 silent guard-let returns (5 in Wishlist, 1 in QR Scanner) that don't set error state | ✅ done (verified 2026-03-29) |
| 64E | Panel Schedule Persist | Wire panel schedule save through NotebooksService — create-or-update + load-on-open | ✅ done (verified 2026-03-29) |
| 64F | AI Dispatch Surface | Add Apply/Dismiss buttons to AI suggestion sheet, wire recordDispatcherChoice + dispatch creation | ✅ done (verified 2026-03-29) |
| 64G | JPO Movement Detail | Replace "Coming Soon" movement stub with real detail view using WarehouseService | ✅ done (verified 2026-03-29) |
| 65A | Guided Onboarding Walkthrough | Comprehensive per-module onboarding with hat filtering, progress tracking, post-onboarding hints | ✅ done (verified 2026-03-29) |
| 65B | Company Setup Wizard | 8-step new company data entry wizard for admins (profile, employees, hats, job, parts, warehouse, breaks) | ✅ done (verified 2026-03-29) |
| 65C | Warehouse Setup Fix | Fix broken Steps 2-6 in warehouse wizard — functional unit placement, sticker checklist, part assignment, counting, targets | ✅ done (verified 2026-03-29) |
| 67A | Audit + Notebook User Attribution | Pass real userId to createAuditSession and autoSaveToJobNotebook — two call sites using default user 1 | ✅ done |

## Prompt 01 Results (2026-03-18)

- 7 files fixed for multiple `.sheet` conflicts -> single `.sheet(item:)` enum pattern
- 3 files fixed for missing data reload on dismiss -> `.onChange` pattern
- 1 supporting change: TypeBrandColorSection binding -> closure for new enum pattern
- 6 files already had correct callbacks — no changes needed
- Build: SUCCESS

## Prompt 02 Results (2026-03-18)

- 19 files fixed across Dashboard (2), Jobs (3), Parts (6), Warehouse (1), Scheduling (2), Tools (2), Reports (4), Settings (1)
- Pattern applied everywhere: `@State private var loadError`, catch blocks set loadError + clear isLoading, guard-let-else clears isLoading + sets error, error display branch added using ContentUnavailableView
- 6 Parts files were already fixed in a prior session
- DashboardView chart catch left as non-critical (secondary data)
- Build: SUCCESS

## Prompt 04 Review (2026-03-19)

- Verified DONE: SyncWaitingView shows honest "Sync Not Available Yet" with Go Back button
- Verified DONE: DevicePairingView QR disabled, attemptPairing shows clear "requires sync infrastructure" message
- Verified DONE: IOSSyncManager.isSyncAvailable returns false, syncNow() and startPeerDiscovery() guard on it
- Minor gap: IOSWarehouseNetworkPage.swift:99 still shows "Pending Phase 16" text to user — low priority, warehouse area
- Build: SUCCESS

## Prompt 05 Review (2026-03-19)

- Verified DONE: AppCore uses safe optionals (no IUOs), AppCoreError enum replaces fatalError
- Verified DONE: databasePath() throws instead of crashing, auth methods guard with "App not ready"
- Verified DONE: DispatchQueue.main.asyncAfter removed from auth views
- Note: 10+ DispatchQueue.main.asyncAfter still in non-auth files (AI panel, settings) — out of scope for this prompt
- Build: SUCCESS

## Prompts 06, 07, 09, 10 Review (2026-03-19)

- Verified DONE: All 10 People pages have add/edit/delete CRUD (Employees, Customers, Contractors, Contacts, Teams, Hats, Permissions, detail pages)
- Verified DONE: All service methods exist (AuthService.createUser, PeopleService.createCustomer/Contractor/Contact/Team, JobsService.getTeamMembers/getJobsForCustomer)
- Verified DONE: JPO detail has Add Line Item + Approve/Reject, PO detail has Receive Shipment, Procurement has Generate PO, Returns has Create Return, Audit has Start Audit
- Verified DONE: PIN hashing uses per-user salt with 10K iterations, generateLocalToken returns nil not "invalid_token"
- Verified DONE: ConflictResolver + SyncEngine have table name whitelist (140+ tables), ChangeTracker uses safe ?? 0 unwrapping, DeviceIdentity persists in UserDefaults
- Verified DONE: OrdersService uses correct "order_status_history" table, ToolsService.getToolsStats filters active checkouts only, SchedulingService.createTimeOffRequest correctly expands date range into individual rows
- Build: SUCCESS

## Prompts 14E-14G Results (2026-03-19)

- 14E: Added migration 024_scheduled_deletions, InventoryCheck + ScheduledDeletion structs, 5 service methods (checkInventoryForDeletion, scheduleEmptyShelfDeletion, listScheduledDeletions, approveScheduledDeletion, cancelScheduledDeletion), SmartDeleteSheet UI, updated all 4 delete buttons in CategoriesEditorPanel
- 14F: Created IOSDeletionApprovalsPage (pending_approval + draining sections), added to OfficeRouter + NavigationConfig
- 14G: Added help button + HierarchyHelpView with 5-level hierarchy explanation, enhanced empty state with guidance
- Build: SUCCESS

## Prompts 15A-15C Results (2026-03-19)

- 15A: Removed raw SQL from PartsBrandsPage (loadData, deleteBrand, save) and PartsSuppliersPage (loadData, deleteSupplier, save) + BrandSupplierPickerSheet (loadSuppliers), replaced with PartsService calls, removed all `import GRDB`
- 15B: Added delete confirmation alerts to both pages (brandToDelete/supplierToDelete + showDeleteConfirm), delete error banners, save error feedback in both form sheets (saveError + isSaving + ProgressView spinner), removed all print() error statements
- 15C: Added .editSupplier case to ActiveSheet enum, replaced nested .sheet in SupplierDetailSheet with onEdit closure pattern, now only 1 .sheet(item:) on parent view
- Build: SUCCESS

## Prompt 16A Results (2026-03-19)

- Migration 025 creates 3 tables: pricing_tiers (hierarchical with conditional indexes), price_history (audit trail), cost_layer_consumptions (FIFO batch tracking)
- 3 model structs: PricingTier (with computed tierLevel), PriceHistory, CostLayerConsumption — all with correct CodingKeys + MutablePersistableRecord
- Settings seeded: pricing_mode=markup, stale_price_threshold_days=90, default_markup_percent=50
- ConflictResolver whitelist: added pricing_tiers, price_history, cost_layer_consumptions + scheduled_deletions (gap from 14E)
- Build: SUCCESS

## Prompt 16B Results (2026-03-20)

- 9 methods added to PartsService.swift in new `// MARK: - 5b. FIFO/LIFO Cost Engine` section
- addCostLayer, consumeInventoryFIFO, returnInventoryLIFO, recalculateWeightedAvgCost, getCostLayers, getConsumptionHistory, resetToCurrentBuyPrice, logPriceChange, getPriceHistory
- 3 error cases added: invalidQuantity, insufficientStock(available:requested:), insufficientReturns(available:requested:)
- Weighted average recalculated after every add/consume/return
- FIFO order: purchase_date ASC, id ASC; LIFO returns: created_at DESC, id DESC
- Build: SUCCESS

## Prompt 16C Results (2026-03-20)

- 8 methods + 3 structs added to PartsService.swift in new `// MARK: - 5c. Hierarchical Pricing` section
- resolvePartPricing walks Part → Brand → Type → Style → Category → Default, returns ResolvedPricing
- calculatePricing: private helper with markup↔margin conversion, 0% minimum margin, fixed price support
- setPricingTier/removePricingTier: CRUD with soft-delete
- findOverrideConflicts: lower-level override detection for confirmation UI
- getPreviewParts: random sample of affected parts with before/after pricing
- getCompanyCostSetting/updateCompanyCostSetting: settings CRUD with upsert
- Build: SUCCESS

## Prompt 16F Results (2026-03-20)

- Created PricingBulkEditSheet.swift: scope picker (All/By Category), markup/margin input, preview of 15 locked sample parts, optional one-at-a-time review, apply to all
- Created PricingSettingsSheet.swift: pricing mode toggle (markup/margin) with formula explanations, default markup %, stale threshold days
- Replaced placeholder sheet handlers in PartsPricingPage.swift with real sheet invocations
- Used `_ = try` for setPricingTier return value, `Section { } header: { }` for interpolated headers
- Build: SUCCESS

## Prompt 16G Results (2026-03-21)

- Service: isPartPriceStale, getStalePricedParts, markPriceVerified added to PartsService
- Added partId + unitPrice to ReceivingItemInfo struct + updated SQL query
- Receiving flow: PO list → start session → line items with qty stepper + price verification (matches/different/not shown)
- Cost layers created automatically during receiving completion
- Stale badge on PO detail line items (orange triangle)
- Removed #if os(iOS) platform guard from PO detail
- Build: SUCCESS

## Prompt 32A Results (2026-03-22)
- Reordered 13 modules in sidebar (daily use → work tools → management)
- Reordered tabs in Orders (Job Orders first, Wishlist last), Tools (Dashboard first, Admin last), Warehouse (Dashboard → Sorting → Staging flow)
- Moved Employees/Hats & Roles/Permissions from Office → People module
- Renamed 4 tabs: Requests→Job Orders, Registry→All Tools, Receiving→Sorting, Deletion Approvals→Deletions
- Created IOSWishlistPage placeholder
- Updated 4 routers: PeopleRouter (employees first, fixed em-dash typo), OfficeRouter (removed HR routes), OrdersRouter (+wishlist, ErrorStateView), IOSToolsRouter (ErrorStateView)
- Build: PASS

## Prompt 32B Results (2026-03-22)
- Fixed 8 empty catch blocks across 6 files (IOSJPOsPage, IOSJPOCreationPage, PartHistoryView, CompanionSandboxSheet, IOSOrderStagingPage, PartsCatalogPage)
- Fixed 13 print-only catch blocks across 7 files (GeofenceAlertView, DashboardView, IOSJobDetailTabView×5, CreatePOSheet, PartsPricingPage, PricingOverrideFlow, PartsCatalogPage×3)
- Added loadError/actionError/saveError state to 9 sub-structs that lacked them
- Build: PASS

## Prompt 32C Results (2026-03-22)
- Fixed 11 guard-let-service silent returns across 9 files
- Added loadError state to 4 files (IOSInspectionsPage, IOSTelematicsPage, CompanionAdminDashboardSheet, PricingBulkEditSheet via saveError)
- Files: IOSInspectionsPage, IOSTelematicsPage, CreateNotebookSheet, IOSJPOCreationPage, SupplierPickerSheet, CompanionAdminDashboardSheet, PricingBulkEditSheet, PricingSettingsSheet, CreateScheduleEntrySheet
- Build: PASS

## Prompt 32D Results (2026-03-22)
- Removed 119 platform guards (#if os(iOS)/#elseif os(macOS)/#endif) from 80 files in Features/
- Kept 9 compound guards (#if os(iOS) && !targetEnvironment(macCatalyst)) in QR scanner
- Build: PASS

## Prompt 32E Results (2026-03-22)
- Removed 104 platform guard lines from 23 files in AI/Auth/App/Navigation/Scanning/Sync/Shared/WebFallback
- IOSQRScanner: kept #if !targetEnvironment(macCatalyst) guard (DataScannerViewController unavailable on Catalyst), added Catalyst stub
- QRScanSheet: replaced direct DataScannerViewController.isSupported with computed property guarded for Catalyst
- WebFallback: removed macOS NSViewRepresentable branch, kept iOS UIViewRepresentable
- Build: PASS

## Prompts 32F-32J Results (2026-03-22)
- 32F: Converted 19 files from showXxx Bool to ActiveSheet enum pattern
- 32G: Replaced print() error logging with @State error UI in 25+ files
- 32H: Added .refreshable and .searchable to 58 list pages
- 32I: Removed duplicate AI toolbar buttons — one global button per page
- 32J: Fixed force unwraps in services, replaced DispatchQueue with async/await
- Build: PASS

## Prompts 33A-33H Results (2026-03-22)
- 33A: Added PageHelpSheet component + help toolbar button to ALL feature pages (Jobs, Parts, Warehouse, Orders, etc.)
- 33B: Fixed "no such column: address" in IOSClockPage, added Lunch/Break/Supply Run activity buttons with note markers, added listActiveJobsForClock() to JobsService
- 33C: Added stock-check-first flow for JPO line approval in IOSJPODetailPage — transfer from shelf vs send to procurement
- 33D: Wired 4 pull option buttons (Pull to target/Pull all/Pull to MIN/Order all) in IOSProcurementPage to actual warehouse movements
- 33E: Replaced all 6 "Coming Soon" stubs in IOSPODetailPage with working sheets (Contact Supplier, Update ETA, Double Order, Report Issue, Receipt History, Contact Creator)
- 33F: Created ReceivingRoutingFlow.swift (1149 lines) — 6-step receiving routing wizard (condition check → wrong part → job link → JPO demand → stock level → confirmed), added routing types/methods to WarehouseService
- 33G: Added migration #035 for staging_boxes table, StagingBox model + CRUD in WarehouseService, rewrote IOSStagingPage with Items/Boxes tabs and box management UI
- 33H: Consolidated duplicate wizard — rewrote IOSMovementWizard.swift to full 994-line wizard, reduced WarehouseMovementsPage from 1364→369 lines
- Cross-agent fixes: 3 async/await errors in IOSClockPage, MARK numbering conflict in WarehouseService, public init for PartStockLevels
- Build: PASS
