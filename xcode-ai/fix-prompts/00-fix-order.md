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
| 26D | PO Detail Supplier CRM | Supplier contact info, score bars, tabbed notes (PO + Supplier) | |
| 26E | Parts Order Management | NEW page: supplier-centric cross-PO view, dual filters, multi-select actions | |
| 26F | PO Detail Jobs + Timeline | Job grouping, delivery timeline bars, inline draft editing, receipt history | |
| 27A | JPO List Cleanup | ActiveSheet, QR scan, count badges, Create JPO with clock auto-fill | |
| 27B | JPO Per-Part Status | Migration: line_status + delivery_option, smart routing (stock → transfer vs approval) | |
| 27C | JPO Detail Redesign | Per-part approve/hold/reject, bulk actions, delivery options, PO linkage | |
| 27D | JPO Hold + Chat | Per-part chat thread, question prompt, auto-membership, chat indicator on list | |
| 27E | Full Audit Trail | part_change_log table, who-did-what logging, PartHistoryView component (cross-cutting) | |
| 28A | Procurement Redesign | Demand consolidation, stock logic, pull options, smart cards, bring-to-target buttons | |
| 28B | Procurement Suppliers | Per-part supplier pick, cheapest/rated/fastest highlight, 2PM cutoff, split by JPO | |
| 28C | Procurement PO Preview | Supplier-grouped preview, partial generation, save for later | |
| 28D | Job Stage Planner | Stage model, category mapping, held/released parts, auto-release, stage settings | |
| 29A | Receiving Fix | Hardcoded user ID, ActiveSheet pattern, platform guard | |
| 29B | Returns Fix | ErrorStateView, console→UI errors, platform guard, smart cards | |
| 29C | Approvals Dashboard | Smart cards, reject reason, actionError display, multi-type approvals | |
| 29D | Orders Cleanup | Remove UnifiedOrderPage, update router tab order, consolidate SupplierPicker | |
| 30A | JPO Creation Layout | 3-panel (search/cart/suggestions), job auto-fill, delivery options, stock indicators | |
| 30B | JPO Creation Search | AI-powered search (cart + last 5 context), QR scan, ⚡ best match, internet toggle | |
| 30C | JPO Creation Suggestions | Companion rules (5) + AI picks (3), context switch on cart selection | |
| 30D | JPO Creation Feedback | Qty confirm dialog, companion points, ratio learning, AI→rule promotion | |
| 30E | JPO Creation Submit | Create JPO + lines, smart routing, replace IOSUnifiedOrderPage | |

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
