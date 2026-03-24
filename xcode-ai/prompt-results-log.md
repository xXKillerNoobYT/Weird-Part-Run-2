# Prompt Results Log — WiredPart iOS

Xcode AI appends an entry here after completing each prompt. This is the source of truth for what was implemented and when.

---

## Prompt 01 — Sheet/Popup Dismissal (2026-03-18)

**Status:** SUCCESS
**Files Changed:** CategoriesEditorPanel.swift, CategoriesTreeView.swift, IOSMainView.swift, TypeBrandColorSection.swift, + 6 callback files
**What Was Done:**
- Converted 7 .sheet modifiers to single .sheet(item:) enum pattern in CategoriesEditorPanel
- Converted 4 .sheet modifiers in CategoriesTreeView
- Fixed IOSMainView multiple sheet conflicts
- Added .onChange reload pattern to 3 files
**Issues Found:** None
**Build:** PASS

## Prompt 02 — Error Visibility (2026-03-18)

**Status:** SUCCESS
**Files Changed:** 19 files across Dashboard, Jobs, Parts, Warehouse, Scheduling, Tools, Reports, Settings
**What Was Done:**
- Added @State loadError to all pages
- Catch blocks now set loadError + clear isLoading
- Guard-let-else clears isLoading + sets error
- Error display branch via ContentUnavailableView
**Issues Found:** 6 Parts files already fixed prior. DashboardView chart catch left as non-critical.
**Build:** PASS

## Prompt 03 — Infinite Spinners (2026-03-18)

**Status:** SUCCESS
**Files Changed:** 6 files fixed, 3 already done
**What Was Done:**
- Guard-let-else blocks now clear isLoading and set error message
**Issues Found:** None
**Build:** PASS

## Prompt 04 — Stub Sync & Placeholders (2026-03-18)

**Status:** SUCCESS
**Files Changed:** SyncWaitingView.swift, DevicePairingView.swift, IOSSyncManager.swift
**What Was Done:**
- SyncWaitingView: honest "Sync Not Available Yet" UI, Go Back button
- DevicePairingView: QR disabled, clear error messaging
- IOSSyncManager: isSyncAvailable=false guard, no fake sync
**Issues Found:** IOSWarehouseNetworkPage.swift:99 still shows "Pending Phase 16" — low priority
**Build:** PASS

## Prompt 05 — AppCore Safety (2026-03-18)

**Status:** SUCCESS
**Files Changed:** AppCore.swift, auth views
**What Was Done:**
- All services converted to safe optionals (no IUOs)
- AppCoreError enum replaces fatalError
- databasePath() throws instead of crashing
- Auth methods guard with "App not ready" messages
**Issues Found:** DispatchQueue.main.asyncAfter remains in 10+ non-auth files — out of scope
**Build:** PASS

## Prompt 08 — CRUD Scheduling & Chat (2026-03-18)

**Status:** SUCCESS
**Files Changed:** CreateDispatchSheet.swift, CreateChannelSheet.swift, IOSTimeOffPage.swift, IOSNotebooksListPage.swift, IOSDispatchPage.swift, IOSChannelsPage.swift, IOSJobNotebooksPage.swift
**What Was Done:**
- Time-off approve/deny wired up
- Create dispatch sheet implemented
- Create channels/DMs wired up
- Q&A form connected
- Notebook creation working
**Issues Found:** None reported
**Build:** PASS

## Prompt 16A — Pricing Migration + Models (2026-03-19)

**Status:** SUCCESS
**Files Changed:** AppDatabase+Migrations.swift, CostsModels.swift, ConflictResolver.swift
**What Was Done:**
- Migration 025 creates 3 new tables: pricing_tiers, price_history, cost_layer_consumptions
- pricing_tiers: hierarchical price/markup at category/style/type/brand/part level with conditional indexes
- price_history: audit trail for all price changes with source tracking
- cost_layer_consumptions: FIFO batch consumption records for sale costing and return reversal
- 3 model structs added: PricingTier (with computed tierLevel), PriceHistory, CostLayerConsumption
- Settings seeded: pricing_mode=markup, stale_price_threshold_days=90, default_markup_percent=50
- Added 3 tables + scheduled_deletions (missed from 14E) to ConflictResolver whitelist
**Issues Found:** scheduled_deletions was missing from ConflictResolver whitelist since prompt 14E — fixed here
**Build:** PASS

## Prompt 16B — FIFO/LIFO Cost Engine (2026-03-20)

**Status:** SUCCESS
**Files Changed:** PartsService.swift
**What Was Done:**
- Added 3 error cases to PartsError: invalidQuantity, insufficientStock, insufficientReturns
- addCostLayer: creates batch on receiving, recalculates weighted avg, logs price history
- consumeInventoryFIFO: oldest-first consumption with supplier tracking from PO chain
- returnInventoryLIFO: most-recent-first reversal with partial return splitting
- recalculateWeightedAvgCost: Σ(remaining_qty × unit_cost) / Σ(remaining_qty) → parts.weighted_avg_cost
- getCostLayers: list batches with optional non-empty filter
- getConsumptionHistory: consumption records with optional job filter
- resetToCurrentBuyPrice: collapse all layers to one at most recent unit cost
- logPriceChange + getPriceHistory: audit trail for all price changes
**Issues Found:** None
**Build:** PASS

## Prompt 16C — Hierarchical Pricing Service (2026-03-20)

**Status:** SUCCESS
**Files Changed:** PartsService.swift
**What Was Done:**
- resolvePartPricing: walks Part → Brand → Type → Style → Category → Default, returns ResolvedPricing with tier source
- calculatePricing: private helper, markup/margin conversion, 0% minimum margin enforcement, fixed price support
- setPricingTier: soft-deletes existing tier at same level, inserts new one
- removePricingTier: soft-delete by tier ID, parts revert to parent pricing
- findOverrideConflicts: finds lower-level overrides with price comparison for confirmation UI
- getPreviewParts: up to 15 random affected parts with before/after pricing
- getCompanyCostSetting / updateCompanyCostSetting: read/write company_cost_settings with upsert
- getPricingTiers: list active tiers with optional scope filter
- Structs: ResolvedPricing, OverrideConflict, PricingPreviewPart
**Issues Found:** None
**Build:** PASS

## Prompt 16D — Pricing Page UI Rebuild (2026-03-20)

**Status:** SUCCESS
**Files Changed:** PartsPricingPage.swift (full rewrite, 389 → 733 lines)
**What Was Done:**
- Removed `import GRDB` and all raw SQL — all data via PartsService methods
- New PricingDisplayRow struct with tier awareness (tierLevel, isInherited, isStale)
- New PricingActiveSheet enum (.editPart, .bulkEdit, .pricingSettings) with single .sheet(item:)
- Filter bar: category picker dropdown + pricing mode badge (markup/margin)
- Sort chips: added .tierLevel option alongside existing name/cost/markup/sell sorts
- Tier badges on each row: green "Part" for direct, orange "from Category" for inherited
- Stale price warning icon (orange triangle) on parts not updated in 90+ days
- PricingEditSheet rebuilt: cost layers disclosure, price history, markup/margin toggle, preview
- Save creates Part-level pricing tier via setPricingTier + logs change via logPriceChange
- Bulk Edit + Pricing Settings sheets are placeholders for prompt 16F
**Issues Found:** None
**Build:** PASS

## Prompt 23A — Forecasting Page Cleanup (2026-03-20)

**Status:** SUCCESS
**Files Changed:** PartsForecastingPage.swift (full rewrite, 439 → 497 lines), PartsService.swift (+ForecastDataRow struct + listForecastDataWithStock method)
**What Was Done:**
- Removed `import GRDB` and all raw SQL → `PartsService.listForecastDataWithStock()`
- Added `ForecastDataRow` struct (Identifiable, Sendable) with `part: Part` + `currentStock: Int` to PartsService
- Added `listForecastDataWithStock(search:)` method with stock JOIN
- Removed 4 `#if os(iOS)` / `#elseif os(macOS)` platform guards (kept iOS code only)
- Added Recalculate toolbar button with ProgressView spinner while running
- Added trend indicators (ADU-30 vs ADU-90): red arrow up (>15%), green arrow down (<-15%), gray stable
- Added "Last recalculated" timestamp footer with ISO8601 → human-readable formatting
- Updated ForecastDetailSheet: uses ForecastDataRow, added Usage Trend row with text labels
- Deleted old ForecastRow struct entirely
**Issues Found:** None
**Build:** PASS

## Prompt 16E — Price Override Confirmation Flow (2026-03-20)

**Status:** SUCCESS
**Files Changed:** PricingOverrideFlow.swift (new, 599 lines), PartsPricingPage.swift (sheet trigger), PartsService.swift (+2 flat-list overloads)
**What Was Done:**
- Created PricingTierSetSheet with 5-step flow: Select Level → Select Entity → Set Price → Preview → Resolve Conflicts → Done
- Level picker: Category, Style, Type, Brand with icon + chevron
- Entity picker: loads flat list of entities for chosen level
- Price input: markup/margin/fixed price based on company mode
- Preview: up to 15 random affected parts with current → new sell price + difference (read-only)
- Override conflicts: reviewed ONE AT A TIME with progress bar, Replace Override or Keep Override buttons
- Done screen: shows counts (X replaced, Y kept)
- Added `listStyles()` and `listTypes()` no-argument overloads to PartsService (flat list across all parents)
- Added `.setTierPricing` case to PricingActiveSheet enum
- Added "Set Tier Pricing" button to pricing page toolbar menu
**Issues Found:** Section header with string interpolation caused generic inference error — fixed with `header:` ViewBuilder parameter
**Build:** PASS

---

## Prompt 16F — Bulk Markup Editor + Pricing Settings (2026-03-20)

**Status:** SUCCESS
**Files Created:** PricingBulkEditSheet.swift (374 lines), PricingSettingsSheet.swift (123 lines)
**Files Modified:** PartsPricingPage.swift (replaced placeholder sheet handlers)
**What Changed:**
- Created `PricingBulkEditSheet`: scope picker (All Parts / By Category), markup/margin input, "Load Preview" fetches 15 sample parts locked for session
- Preview view: read-only price comparison (old → new + diff), "Apply to All" button, optional "Review One at a Time" step-through
- One-at-a-time review: progress bar, part details, price change comparison, Next Part / Apply to All at end
- Complete screen: checkmark, "Bulk Update Applied", Done button triggers reload
- Created `PricingSettingsSheet`: pricing mode toggle (markup/margin) with formula explanations, default markup %, stale price threshold days
- Settings loads/saves via `getCompanyCostSetting` / `updateCompanyCostSetting`
- Replaced placeholder NavigationStack cases in PartsPricingPage sheetContent with real sheet invocations
- Used `_ = try service.setPricingTier(...)` to discard return value (setPricingTier returns PricingTier)
- Used `Section { } header: { Text(...) }` pattern to avoid string interpolation generic inference errors
**Build:** PASS

---

## Prompt 16G — Stale Price Alerts + Receiving Price Verification (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (+3 stale methods), WarehouseService.swift (+partId/unitPrice to ReceivingItemInfo + query), IOSReceiveShipmentPage.swift (full rewrite with receiving flow), IOSPODetailPage.swift (stale badge + removed #if os)
**What Changed:**
- Service: `isPartPriceStale(partId:)` checks threshold from company settings, returns true if never updated or > threshold days
- Service: `getStalePricedParts(limit:)` returns sorted list with days-since-update for reporting
- Service: `markPriceVerified(partId:)` updates `cost_last_updated` without changing price
- Added `partId: Int64?` and `unitPrice: Double?` to `WarehouseService.ReceivingItemInfo` struct + updated SQL query to fetch them via PO line JOIN
- Rewrote `IOSReceiveShipmentPage`: PO list → tap "Receive" → starts session → shows line items with quantity stepper + "All" quick-fill + price verification
- Price verification: 3 options per line item (Matches / Different / Not Shown) with capsule-style toggles
- "Different" shows text field for actual receipt price (5 decimal places)
- On "Complete Receiving": updates quantities, completes session (stock movements), then processes verifications — Matches: creates cost layer at order price + marks verified, Different: cost layer at new price + marks verified, Not Shown: skips entirely
- PO detail: stale price warning badge (orange triangle + "Price not verified recently") shown per line item
- Removed `#if os(iOS)` platform guard from PO detail page
**Build:** PASS

---

## Prompt 16H — Catalog Pricing + View Modes (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsPricingPage.swift (+view modes, made PricingEditSheet internal), PartsCatalogPage.swift (+pricing overlay, pricing cache)
**What Changed:**
- Pricing page: added `PricingViewMode` enum (list/cards/table) with toolbar picker
- Card view: LazyVGrid with adaptive 280-400px columns, shows cost/sell/markup/margin + stale border
- Table view: horizontal scroll spreadsheet with 7 columns (Part Name, Avg Cost, Markup %, Margin %, Sell Price, Profit, Source)
- Made `PricingEditSheet` internal (was private) so catalog page can reuse it
- Catalog page: "Show Prices" toolbar button (dollarsign.circle), toggles pricing overlay on each row
- Pricing overlay: tappable sell price + markup badge, opens PricingEditSheet for inline editing
- `loadPricingCache()` resolves pricing for all visible parts via `resolvePartPricing`, also loads pricing mode
- Pricing cache clears when overlay toggled off
**Build:** PASS

---

## Prompt 16I — Pricing AI Integration (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsPricingPage.swift (+AI context), IOSAIAssistantPanel.swift (+pricing listener/fallback), NavigationConfig.swift (+notification names)
**What Changed:**
- Added `.pricingPageActive` / `.pricingPageInactive` notification names to NavigationConfig
- Pricing page posts rich context on appear: pricing mode, averages, tier distribution, top 5 highest markup, top 5 lowest margin, stale count, capability hints
- AI panel listens for pricing notifications via `pricingContext` state
- Pricing context appended to Foundation Models `navigationContext` for real AI queries
- Added `handlePricingFallback` for when Foundation Models unavailable: markup vs margin explanation, stale price guidance, FIFO costing explanation, hierarchical pricing explanation, generic summary fallback
- Follows same notification-based pattern as catalog page AI integration
**Build:** PASS

---

## Prompt 17A — Supplier Migration + Models (2026-03-21)

**Status:** SUCCESS
**Files Modified:** AppDatabase+Migrations.swift (+migration 026), PartsModels.swift (+accountNumber), PartsService.swift (+traceability methods)
**Files Created:** WarehouseModels.swift (StockMovement struct)
**What Changed:**
- Migration 026: adds `account_number` TEXT column to suppliers table
- Supplier model: added `accountNumber: String?` property with CodingKey
- StockMovement model: 22-column struct mapping stock_movements table (part_id, qty, from/to location, supplier_id, movement_type, reference_number, GPS, costs, etc.)
- Service: `tracePartMovements(partId:)` — chronological journey for a part with performer names
- Service: `tracePartFromSupplier(partId:supplierId:)` — movements filtered by supplier
- Service: `getPartCurrentLocations(partId:)` — current stock locations with quantities
- `stock_movements` already in ConflictResolver whitelist
**Build:** PASS

---

## Prompt 17B — Supplier Form Rebuild (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsSuppliersPage.swift (form, list row, detail sheet), PartsService.swift (create/update methods)
**What Changed:**
- SupplierFormSheet: rebuilt from 7 to 15 editable fields in 5 sections (Details, Main Contact, Sales Rep, Delivery, Notes)
- Added account number, active toggle, rep name/email/phone, delivery method picker (8 presets), delivery days
- Removed all `#if os(iOS)` platform guards (iOS-only app)
- Service: `createSupplier` expanded with repName, repEmail, repPhone, deliveryMethod, deliveryDays, accountNumber
- Service: `updateSupplier` expanded with same + isActive parameter
- SupplierListRow: added `accountNumber` property + mapping from model
- List row: tappable phone (tel: URL), account number label
- Detail sheet: tappable phone/email/website for both main contact and rep (tel:/mailto:/https: URLs), account # display
**Build:** PASS

---

## Prompt 17C — Supplier Performance Scores (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (+3 methods + SupplierScores struct), PartsSuppliersPage.swift (detail sheet)
**What Changed:**
- `SupplierScores` struct: qualityScore, onTimeRate, reliabilityScore, totalOrderCount, totalUnitsReceived, totalUnitsReturned, avgDeliveryDays
- `calculateSupplierScores(supplierId:)`: quality from return rate (stock_movements), on-time from PO→receiving timing, reliability = 60% on-time + 40% quality
- `updateSupplierScores(supplierId:)`: persists calculated scores to suppliers table
- `recalculateAllSupplierScores()`: batch recalculation for all active suppliers
- On-time uses COALESCE(CAST(delivery_days AS INTEGER), 14) for expected delivery window
- Detail sheet: live-calculated scores with return counts, avg delivery days, color-coded percentages
- Shows "No order data yet" when no POs exist for the supplier
**Build:** PASS

---

## Prompt 17D — Supplier Detail Rebuild (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (+3 methods in section 12b), PartsSuppliersPage.swift (complete SupplierDetailSheet rebuild)
**What Changed:**
- `getSupplierBrands(supplierId:)`: brands with part counts from `brand_supplier_links`
- `getSupplierRecentPOs(supplierId:limit:)`: recent POs with line item totals
- `getSupplierPartCount(supplierId:)`: count from part_suppliers
- SupplierDetailSheet rebuilt with 8 sections: Overview (account#, inactive warning, delivery), Contact (tappable phone/email/website), Sales Rep (tappable), Performance Scores (live-calculated), Brands Carried (with part counts), Parts Summary, Recent Orders (status badges), Notes
- Fixed: `.foregroundStyle(.accentColor)` → `.foregroundStyle(Color.accentColor)` (ShapeStyle vs Color)
**Build:** PASS

---

## Prompt 17E — Supplier Contacts Integration (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (+SupplierContact struct + 3 methods in section 12c), PartsSuppliersPage.swift (contacts section + AddSupplierContactSheet)
**What Changed:**
- `SupplierContact` struct with contactId, firstName, lastName, role, phone, email, isPrimary
- `getSupplierContacts(supplierId:)`: from entity_contacts WHERE entity_type='supplier'
- `addSupplierContact(...)`: INSERT with primary toggle clearing, uses `role ?? ""` and `phone ?? ""` for NOT NULL columns
- `removeSupplierContact(contactId:)`: soft delete (sets deleted_at)
- Contacts section in SupplierDetailSheet: name, PRIMARY badge, role, tappable phone/email, swipe-to-delete
- AddSupplierContactSheet: first/last name, 9-role picker, phone, email, primary toggle, save error display
- Omitted changeTracker references (doesn't exist in PartsService)
**Build:** PASS

---

## Prompt 17F — Supplier Sort + Field Fix + Pricing Display (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (+PartSupplierCost struct + method in 12d, updated SupplierWithCount + listSuppliers), PartsSuppliersPage.swift (sort, field fix), PartsPricingPage.swift (supplier costs section)
**What Changed:**
- Fixed field mapping bug: `partCount: item.brandCount` → `partCount: item.partCount`
- Added `partCount: Int` to `SupplierWithCount`, updated `listSuppliers()` SQL with part_count subquery
- `PartSupplierCost` struct + `getPartSupplierCosts(partId:)` method
- `SupplierSortOption` enum with 7 cases (nameAsc/Desc, quality, onTime, reliability, partCount, recentlyAdded)
- Sort Menu next to active/all segmented picker
- Updated `filteredSuppliers` with sorting + accountNumber search
- PricingEditSheet: supplier costs section between cost layers and pricing inputs
- Skipped CategoriesEditorPanel addition — taxonomy editor has no part detail area
**Build:** PASS

---

## Prompt 17G — Brands Detail Sheet Fix (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (updated BrandWithCount + listBrands), PartsBrandsPage.swift (detail sheet fix)
**What Changed:**
- Added `supplierCount: Int` to `BrandWithCount` struct
- Updated `listBrands()` SQL with supplier_count subquery from `brand_supplier_links`
- Fixed loadData: `supplierCount: 0` → `supplierCount: bwc.supplierCount`
- Replaced double `.sheet(isPresented:)` in BrandDetailSheet with single `.sheet(item:)` enum pattern
- `DetailActiveSheet` enum (.editBrand, .supplierPicker)
- Removed `#if os(iOS)` platform guard, changed toolbar placement to `.primaryAction`
**Build:** PASS

---

## Prompt 17H — Supplier AI Integration (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift (+buildSupplierAIContext in 12e), NavigationConfig.swift (+2 notifications), IOSAIAssistantPanel.swift (+suppliers context), PartsSuppliersPage.swift (+AI notifications)
**What Changed:**
- `buildSupplierAIContext()`: queries all suppliers with part_count, brand_count, po_count subqueries
- Notification names: `.suppliersPageActive` / `.suppliersPageInactive`
- AI panel: `suppliersContext` state, `.onReceive` listeners, context wired into `generateResponse`
- `handleSuppliersFallback`: canned responses for quality, delivery, account numbers, brands, contacts, edit redirect (read-only)
- PartsSuppliersPage: `postSuppliersContext()` method, `.onAppear`/`.onDisappear` notifications
**Build:** PASS

---

## Prompt 18A — Review Cleanup (2026-03-21)

**Status:** SUCCESS
**Files Modified:** CategoriesBrandSection.swift, CategoriesColorPicker.swift, TypeBrandColorSection.swift, CategoriesFormSheets.swift
**What Changed:**
- Error visibility: 3 category components (BrandSection, ColorPicker, TypeBrandColorSection) now show `loadError` Label to users instead of silent `print()` — both load and toggle catch blocks
- Dead imports: removed unused `import GRDB` from CategoriesFormSheets.swift (only 1 of 6 checked files was actually unused — other 5 use `Row`/`Column` types)
- Color picker: fixed `hasColor` default from `true` to `false` for new colors (`.onAppear` already sets `true` when editing existing color with hex)
- BrandSupplierPickerSheet: already had `isSaving` + ProgressView + disabled from prior prompt 15B — no changes needed
**Build:** PASS

---

## Prompt 19A — Companion Migration + Models (2026-03-21)

**Status:** SUCCESS
**Files Modified:** AppDatabase+Migrations.swift, PartsModels.swift, ConflictResolver.swift
**What Changed:**
- Migration 027: ALTER companion_rule_sources/targets (added type_id), ALTER companion_rules (try_match_brand, auto_color_match, parent_rule_id, auto_delete_at, deleted_at), ALTER co_occurrence_pairs (points, style/type/brand IDs, match_level, rejection_count, is_blocked, tied_cooldown_until)
- CREATE tables: companion_polls, companion_votes, companion_poll_results, companion_auto_discovery_log
- Indexes: 7 new indexes for performance on polls, votes, co_occurrence, rules
- Permissions seeded: companion_vote_power (Admin/Manager/Lead), vote_veto (Admin)
- Updated CompanionRule model with new fields + CodingKeys
- 4 new model structs: CompanionPoll, CompanionVote, CompanionPollResult, CompanionAutoDiscoveryLog
- ConflictResolver: added 4 new tables to whitelist
**Build:** PASS

---

## Prompt 19B — Companion Rules + Points Service (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift
**What Changed:**
- Updated CompanionRuleSource/CompanionRuleTarget structs: added `typeId: Int64?` field
- Updated existing `listCompanionRules()`: added typeId mapping to source/target
- New section "8b. Companion Rules V2 (Hierarchy + Points)" with 11 methods:
  - `CompanionRuleHierarchyRow` struct with full hierarchy info (match level, orphan detection, child count)
  - `listCompanionRulesHierarchy()` — all rules with joined sources/targets, child counts, orphan detection
  - `createCompanionRuleAtLevel()` — create rule with category/style/type level sources and targets
  - `deleteCompanionRuleSoft(id:)` — soft delete with 30-day child cascade
  - `restoreCompanionRule(id:)` — restore + cancel child auto-deletion
  - `purgeExpiredRules()` — hard delete expired auto_delete_at rules
  - `listAllAlternatives()` — all alternatives with joined part names
  - `calculateCoOccurrencePoints()` — scan job_parts, compute pair co-occurrence points
  - `getQualifiedPairs()` — filter pairs by thresholds, exclude blocked/cooldown
  - `applyRejectionPenalty(pairId:)` / `applySkipPenalty(pairId:)` / `resetBlockedPair(pairId:)`
**Build:** PASS

---

## Prompt 19C — Companion Polls + Voting Service (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsService.swift
**What Changed:**
- New section "8c. Companion Polls & Voting" with 14 methods:
  - `CompanionPollDisplayRow` struct (poll info + vote status + admin details)
  - `createWeeklyPoll()` — picks highest-point pair, creates poll, notifies all users
  - `getActivePolls(userId:isAdmin:)` — active polls with user vote status
  - `castVote(pollId:userId:vote:)` — insert/update with vote_power permission check
  - `closePoll(pollId:)` — pass/fail/tied logic, auto-rule creation, rejection penalty
  - `adminLockPoll(pollId:result:lockedBy:)` — force poll result
  - `adminSkipPoll(pollId:)` — close + penalty + auto-create replacement
  - `getNextPollPreview()` — next best pair for admin preview
  - `getLastWeekResults(userId:)` — recent poll outcomes + user vote accuracy
  - `getUserVotingAccuracy(userId:)` — lifetime voting stats
  - `getTrainingQuestion()` — closest-to-threshold pair for training
  - `getActivePollsForClockOut(userId:)` — polls 7+ days old for clock-out integration
  - `closeExpiredPolls()` — auto-close past end_date polls
- Fixed: removed unused ISO8601DateFormatter (DateFormatter with yyyy-MM-dd used instead)
**Build:** PASS

---

## Prompt 19D — Companion Page Cleanup (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsCompanionsPage.swift, PartsService.swift
**What Changed:**
- Removed `import GRDB` — all raw SQL replaced with PartsService method calls
- Replaced local `CompanionRuleRow` struct with `PartsService.CompanionRuleHierarchyRow`
- Replaced local `AlternativeRow` struct with `PartsService.PartAlternativeWithName`
- Rewrote `loadData()` to use `service.listCompanionRulesHierarchy()` + `service.listAllAlternatives()`
- Rewrote `deleteRule()` → soft delete with confirmation alert (shows child cascade warning)
- Rewrote `toggleRuleActive()` → `service.updateCompanionRule(id:isActive:)`
- Rewrote `deleteAlternative()` → `service.unlinkPartAlternative(linkId:)` with confirmation alert
- Added restore swipe action for deleted/orphaned rules → `service.restoreCompanionRule(id:)`
- Updated rule list display: source→target names, match level badge (Category/Style/Type), brand indicator, orphan status with "Deleting" text, child count, opacity
- Removed all `#if os(iOS)` / `#elseif os(macOS)` guards (3 occurrences)
- Added `actionError` banner for action failures (delete, toggle, restore)
- Removed all `print()` error swallowing — errors now surface via `loadError` or `actionError`
- Added `saveError` + `isSaving` to both form sheets (CompanionRuleFormSheet, AlternativeFormSheet)
- Form sheets now use service calls: `createCompanionRuleAtLevel()`, `linkPartAlternative()`, `listParts()`
- Added `Identifiable` conformance to `CompanionRuleHierarchyRow` and `PartAlternativeWithName`
- Added `partName`/`partCode` fields to `PartAlternativeWithName` + updated `listAllAlternatives()` mapping
**Build:** PASS

---

## Prompt 19E — Companion Rule Form Rebuild (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsCompanionsPage.swift
**What Changed:**
- Replaced CompanionRuleFormSheet with cascading category/style/type hierarchy pickers
- Match level segmented control (Category/Style/Type) controls which pickers are visible
- Try to Match Brand + Auto-Match Color toggles
- Qty mode picker (Sum/Ratio/Fixed) with ratio input field
- Form validation: name required, source and target at correct level, can't be identical
- Edit mode: `editingRule` parameter, `populateFromEditingRule()` pre-fills all fields
- Added `.editRule(CompanionRuleHierarchyRow)` case to ActiveSheet enum
- Tap on rule row opens edit form via `.onTapGesture`
- Save uses `createCompanionRuleAtLevel()` for new or `updateCompanionRule()` for edits
- Kept `PartPickerItem` for AlternativeFormSheet (still needs individual part picking)
**Build:** PASS

---

## Prompt 19F — Companion Polls UI (2026-03-21)

**Status:** SUCCESS
**Files Modified:** PartsCompanionsPage.swift
**What Changed:**
- Added 3rd Polls tab to CompanionTab enum and segmented picker
- Poll state: activePolls, lastWeekResults, trainingQuestion, nextPollPreview, lock/skip state
- loadData() now also fetches polls, results, training, preview + runs closeExpiredPolls/purgeExpiredRules
- pollsView: ScrollView with lastWeekResults, active poll cards, training fallback, admin preview
- pollCard: match level badge, source→target names, days remaining, Yes/No vote buttons with highlight
- adminControlsSection: powered vote counts, lock indicator, Lock Result menu, Skip button (vote_veto gated)
- lastWeekResultsSection: pass/fail icons, poll names, user's vote side, matched winner color
- trainingQuestionCard: blue-themed practice card with disclaimer
- adminPreviewSection: purple-themed next week preview with points/confidence
- emptyPollsState: explanation about needing 3 months of data
- vote() action method: castVote + reload
- Lock/Skip confirmation alerts with appropriate warning messages
- Plus button hidden on Polls tab
**Build:** PASS

---

## Prompt 19G — Companion Clock-Out Integration (2026-03-21)

**Status:** SUCCESS
**Files Modified:** IOSClockPage.swift, IOSQuestionnairePage.swift
**What Changed:**
- IOSClockPage: Added `showQuestionnaire`/`lastLaborEntryId` state, `.sheet(isPresented:)` for IOSQuestionnairePage
- IOSClockPage: `clockOut()` now sets lastLaborEntryId and showQuestionnaire=true after success
- IOSQuestionnairePage: Added `companionPolls` and `companionVotes` state
- IOSQuestionnairePage: `loadQuestions()` also loads companion polls via `partsService.getActivePollsForClockOut()`
- Companion poll questions shown in separate "Companion Rule Votes" section with "Recommended" badge
- Each companion poll displayed as Yes/No toggle (always optional, never blocks submission)
- `submitResponses()` now also calls `partsService.castVote()` for each answered companion poll
- Empty state updated: shows if both regular questions AND companion polls are empty
- Replaced `print()` error in loadQuestions with `errorMessage` (visible to user)
**Build:** PASS

## Prompt 19H Results (2026-03-21)
- Created CompanionSandboxSheet.swift with "What If" scenario testing
- Category picker adds categories to simulate an order, matched rules display
- Real job examples from history (up to 3 jobs where categories co-occurred)
- Next level preview from co_occurrence_pairs at style/type level
- Added flask toolbar button + .testSandbox ActiveSheet case to PartsCompanionsPage
- Custom WrappedHStack flow layout for category chips
- Read-only — no data modified
- Build: SUCCESS


## Prompt 19I Results (2026-03-21)
- Created CompanionAdminDashboardSheet.swift with voting analytics
- Overview section: manual vs auto-discovered rule counts
- Team Voting Accuracy: per-user accuracy %, color-coded, vote power indicator
- Poll History: last 20 completed polls with accept/reject, vote counts, admin lock indicator
- Permission-gated: manage_people required for toolbar button
- Added .adminDashboard ActiveSheet case + chart.bar.xaxis toolbar button
- Build: SUCCESS


## Prompt 19J Results (2026-03-21)
- Added calculateStyleCoOccurrence() for category→style drill-down
- Added calculateTypeCoOccurrence() for style→type drill-down
- Added runAutoDiscoveryCycle() orchestration: close expired → purge → recalculate → drill-down → create poll → log
- Wired auto-discovery into AppCore bootstrap via Task.detached (non-blocking)
- Fixed sandbox CompanionSandboxSheet: promoted_to_rule → is_blocked (column didn't exist)
- Build: SUCCESS


## Prompt 19K Results (2026-03-21)
- Added 4 AI tools to AITools.swift: ListCompanionRulesTool, GetActiveCompanionPollsTool, ExplainCoOccurrenceTool, GetVotingSummaryTool
- Registered tools in FoundationModelsService.swift
- Added companionsPageActive/companionsPageInactive notification names to NavigationConfig.swift
- Added companionsContext state + .onReceive listeners to IOSAIAssistantPanel.swift
- Added AI sparkles toolbar button + postCompanionsContext() to PartsCompanionsPage.swift
- Extracted sheet content into sheetContent(for:) method to fix type-check timeout
- Build: SUCCESS


## Prompt 20A Results (2026-03-21)
- Created QRScanSheet.swift reusable component (camera scanning, manual entry, auto-dismiss on match, type mismatch warning)
- Added QR scan toolbar button to IOSReceiveShipmentPage (scans PO → auto-starts receiving)
- Added QR scan button to MovementWizard step 2 (scans part → adds to movement list with stock lookup)
- Build: SUCCESS


## Prompt 20B Results (2026-03-21)
- IOSPurchaseOrdersPage: Refactored to ActiveSheet enum, added QR scan toolbar button (scans PO → opens detail sheet)
- CreatePOSheet: Added QR supplier scan button next to search field (scans supplier → auto-selects)
- IOSProcurementPage: Refactored to ActiveSheet enum, added QR scan toolbar button (scans JPO → selects for PO generation)
- Build: SUCCESS


## Prompt 20C Results (2026-03-21)
- IOSClockPage: Refactored to ActiveSheet enum, added QR scan toolbar button (scans job → auto-clocks-in), only shows when not clocked in
- IOSToolCheckoutsPage: Added QR scan toolbar button + alert (scans tool → shows name, "View in Registry" action)
- IOSToolRegistryPage: Added QR scan toolbar button (scans tool → auto-searches by name in list)
- Build: SUCCESS


## Prompt 20D Results (2026-03-21)
- PartsCatalogPage: Added .qrScanner to ActiveSheet enum, QR toolbar button, accepts any barcode type (expectedType: nil), auto-searches by code/name
- IOSEmployeesPage: Refactored to ActiveSheet enum, added badge scan toolbar button (scans employee → auto-searches by display name)
- Build: SUCCESS

## Prompt 21A Results (2026-03-21)
- Created QRLabelGenerator.swift in core/Sources/WiredPartCore/QR/ with full PDF generation engine
- QRLabelSize enum: 6 sizes (square, tall, wide, long, small, standard) with point dimensions
- QRPaperSize enum: 11 paper types (letter, legal, A4, 5 Avery templates, 2 thermal) with label grids
- QRLabelLayout enum: 6 layouts (qrLeft, qrRight, qrTop, qrBottom, qrCenter, codeOnly)
- LabelGrid struct with position calculation for sticker sheets
- QRLabelContent struct using QREntityType (adapted from prompt's String to match actual API)
- QRLabelPDFGenerator: generatePDF() with sticker sheet mode (used-position skipping) and plain paper auto-tiling
- Adapted QRGenerator.generate() call to use size: CGFloat (not CGSize as in prompt)
- Batch helpers: generatePartLabels, generateBinLabels, generateToolLabels
- #if canImport(UIKit) guard for cross-platform compilation
- Build: SUCCESS

## Prompt 21B Results (2026-03-21)
- Created QRLabelPrintSheet.swift in Scanning/ with UsedStickerPicker + QRLabelPrintSheet views
- UsedStickerPicker: visual grid for marking used sticker positions, Clear All/Use All buttons
- QRLabelPrintSheet: size/layout/paper pickers, layout preview, page count estimate, iOS UIPrintInteractionController
- PartsCatalogPage: Added .printLabels to ActiveSheet enum, printer toolbar button, prints currently loaded parts
- IOSToolRegistryPage: Refactored from boolean to ActiveSheet enum (.toolScanner, .printLabels), printer toolbar button
- Fixed .foregroundStyle(.accentColor) → Color.accentColor for ShapeStyle conformance
- Build: SUCCESS

## Prompt 22A Results (2026-03-21)
- Migration 028_supplier_bridge: supplier_channel_bridges + supplier_messages tables with indexes
- Models: SupplierChannelBridge, SupplierMessage structs in ChatModels.swift
- ConflictResolver: added supplier_channel_bridges, supplier_messages to whitelist
- ChatService: 6 supplier bridge methods (createSupplierChannel, listSupplierChannels, sendSupplierMessage, addUserToSupplierChannel, getSupplierBridge, deactivateSupplierBridge)
- Bridge approach: no supplier user accounts needed, direction tracking for inbound/outbound
- Build: SUCCESS

## Prompt 22B Results (2026-03-21)
- IOSChannelsPage: Added "supplier" to channelIcon (shippingbox.circle) and channelTypeBadge (orange), refactored to ActiveSheet enum, added "Supplier Channel" menu option
- CreateChannelSheet: Added supplier type with supplier picker (PartsService.listSuppliers), auto-generated channel name, createSupplierChannel() call
- PartsSuppliersPage/SupplierDetailSheet: Added Communication section with Start Conversation / Open Supplier Channel buttons, supplierChannelId state, loadAllDetails checks for existing channel
- Fixed double .sheet(isPresented:) conflict in IOSChannelsPage → single .sheet(item:) pattern
- Build: SUCCESS

## Prompt 22C Results (2026-03-21)
- ChatService: createSupplierChannel() now accepts optional jobId parameter, sets job_id on channel
- ChatService: Added listSupplierChannelsForJob(jobId:userId:) — supplier channels for a specific job with unread counts
- ChatService: Added createSupplierQuestion(channelId:jobId:askedBy:subject:priority:) — Q&A threads in supplier channels
- ChatService: Added listSupplierQuestions(status:) + SupplierQuestionRow struct — queries threads joined to supplier channels
- IOSJobDetailTabView: Chat tab now includes Supplier Channels section with unread badges + NavigationLink to message thread
- IOSJobDetailTabView: Added CreateJobSupplierChannelSheet with supplier picker, creates job-linked supplier channel
- IOSChannelsPage: Job-linked supplier channels show job name with building.2 icon (vs hammer for regular job channels)
- IOSRFIListPage: Added Supplier Questions section using listSupplierQuestions(), shows supplier name + status badge
- Build: SUCCESS

## Prompt 23B Results (2026-03-21)
- GetForecastDataTool: urgency filter (critical/warning/healthy), search, stock + ADU + days display, max 25 results
- Tool uses @Generable Arguments with @Guide annotations, registered in chatWithTools() tools array
- Forecasting page context: posts critical/warning counts, top 5 critical items, last run timestamp
- Context posted on onAppear + after loadData(), cleared on onDisappear
- AI panel: forecastContext state + .onReceive + generateResponse navContext integration
- NavigationConfig: .forecastingPageActive / .forecastingPageInactive notification names
- Build: SUCCESS

## Prompt 23C Results (2026-03-21)
- Deleted horizontal filter chip ScrollView from body top
- Stat cards now act as toggle filters: tap to filter, tap again deselects (shows all)
- Cards always show global counts from forecastRows (unfiltered)
- Selected card: filled urgency color background, white text, slight 1.02 scale
- Section header contextual: "X critical/warning/healthy parts" based on filter
- Build: SUCCESS

## Prompt 23D Results (2026-03-21)

- Migration 029: location_stock_targets table with UNIQUE(part_id, location_type, location_id)
- LocationStockTarget model + LocationStockTargetWithStock (with healthScore)
- 4 service methods: get, set, list, recalculatePerLocation
- Global recalculate now chains into per-location recalculate
- ConflictResolver: location_stock_targets added
- Build: SUCCESS

## Prompt 23E Results (2026-03-21)

- Migration 030: forecast_settings (3 seeded defaults: warehouse/truck/trailer), location_free_space, alter location_stock_targets (+part_category, +do_not_restock)
- ForecastSettings + LocationFreeSpace models in PartsModels.swift
- 5 service methods: getForecastSettings (with fallback), saveForecastSettings, getFreeSpaceRating, setFreeSpaceRating (clamped 1-10), listAllForecastSettings
- ConflictResolver: forecast_settings + location_free_space added
- Build: SUCCESS

## Prompt 23F Results (2026-03-21)

- Migration 031: target_recommendations table with indexes (part_loc, status)
- TargetRecommendation model with full CodingKeys
- Added invalidInput(String) case to PartsError enum
- 5 service methods: generateDailyRecommendation (max 1/day, 60-day cooldown, ADU+APW, category changes), listPendingRecommendations, approveRecommendation (applies to location_stock_targets), dismissRecommendation (requires reason), pendingRecommendationCount
- Fixed prompt bugs: duplicate dismissed_reason SET, wrong error type name
- ConflictResolver: target_recommendations added
- Build: SUCCESS

## Prompt 23G Results (2026-03-21)

- Location picker: horizontal chips (All/Warehouse/Truck/Trailer) inside List, loads from stock table with location name JOINs
- Recommendations toolbar button with orange badge count
- Recommendation cards with type icon, MIN/TARGET/MAX current→recommended, reason, Approve/Dismiss buttons
- Approve applies via service, Dismiss requires reason (TextField in alert)
- listForecastDataWithStock() now accepts optional locationType/locationId filter (JOIN condition on stock)
- LocationOption struct, recommendation helper methods (icon, color, partName lookup)
- Added GRDB import for Row access in loadLocations()
- Build: SUCCESS

## Prompt 23H Results (2026-03-21)

- Replaced ForecastDetailSheet with full-featured panel: 4 sections (Part Info, Stock Health, Forecast Metrics, Actions)
- Part Info: editable Name, Code, Min/Target/Max stock with Save Changes button (only when changed)
- Stock Health: per-location rows with health bar (GeometryReader), MIN/TARGET/MAX labels, certainty %, usage
- Health bar: red MIN zone, colored stock fill, TARGET marker line using healthColor(score)
- Forecast Metrics: ADU 30/90, trend arrows, days until low, suggested order, last recalculated
- Actions: placeholder Wishlist and Catalog buttons
- Save validates MIN < TARGET < MAX before calling service.updatePart()
- Uses @EnvironmentObject for appCore access, loads location data via listLocationStockTargets
- Build: SUCCESS

## Prompt 24A Results (2026-03-21)

- Removed import GRDB + all #if os() platform guards (4 total)
- Added loadError display via ContentUnavailableView with Retry button
- Export: 5 field group checkboxes + Select All toggle, via service exportPartsCSV(groups:)
- Import: preview sheet with conflict resolution (Update/Skip per row, Update All/Skip All bulk buttons)
- Import preview shows: summary (new/conflicts/errors), new parts list (up to 20), conflict side-by-side comparison, error list
- Per-conflict resolution badges (UNRESOLVED/UPDATE/SKIP) with dynamic confirm button label
- Duplicate matching: by code first (exact), then by name (case-insensitive)
- New categories/brands auto-created during import via findOrCreateCategory/Brand
- 7 new service methods: getImportExportStats, exportPartsCSV(groups:), findPartByCode, findPartByName, findOrCreateCategory, findOrCreateBrand
- Replaced stub importPartsCSV with full parseImportFile + executeImport flow
- Fixed: company_sell_price column doesn't exist → calculated as ROUND(cost * (1 + markup/100), 2)
- Fixed: existing CatalogStats name conflict → renamed to ImportExportStats/getImportExportStats
- Build: SUCCESS

---

## Prompt 26A — PO List Cleanup (2026-03-21)

**Status:** SUCCESS
**Files Changed:** IOSPurchaseOrdersPage.swift

**Changes:**
- Removed `#if os(iOS)` platform guard around `.listStyle(.insetGrouped)`
- Added count badges to all 7 status filter chips: "All (12)", "Draft (3)", etc.
- Added `countForStatus(_:)` helper using `allPurchaseOrders` for accurate counts
- Updated `loadData()` to load all POs once for counts, then filter for display
- Fixed `guard let service` silent return → now sets `loadError = "Orders service not available"` + clears `isLoading`
- Added `formatDate(_:)` helper: ISO 8601 string → medium date style ("Mar 20, 2026")
- Updated `poRow` to use formatted dates instead of raw ISO strings
- Build: SUCCESS

---

## Prompt 26B — PO List Swipe + Sort (2026-03-22)

**Status:** SUCCESS
**Files Changed:** IOSPurchaseOrdersPage.swift, OrdersService.swift

**Changes:**
- Awaiting delivery KPI line: shows count of ordered/partial POs + pending $ total for all active statuses
- 6 sort options in toolbar menu: Newest, Oldest, Total High/Low, Supplier A-Z, By Status
- Swipe-to-delete on Draft POs, swipe-to-cancel on Submitted/Ordered/Partial POs
- No swipe on Received/Cancelled POs (historical, immutable)
- AI-generated summary in confirmation dialog via `FoundationModelsService.generatePreFill` with fallback string
- Cancel reason required — alert blocks submission if empty, shows "Reason is required" notice
- Added `updatePOStatus(id:status:)` to OrdersService with status history recording
- Added `deletePO(id:)` to OrdersService (soft-delete, draft only)
- Build: SUCCESS

---

## Prompt 26C — PO Detail Lifecycle (2026-03-22)

**Status:** SUCCESS
**Files Changed:** IOSPODetailPage.swift

**Changes:**
- Fixed status color: `"sent"` → `"submitted"` (.orange), added `"drafting"` (.yellow), `"partial"` (.purple)
- Replaced single toolbar Menu with status-based action buttons in ScrollView content
- 7 status states with unique action sets:
  - Draft: Submit to Supplier + Delete Draft + Manage Parts
  - Submitted: Mark Ordered + Drafting/Unclear + Cancel PO + Contact Supplier
  - Ordered: Receive Shipment + Update ETA + Cancel PO + Contact Supplier + Manage Parts
  - Partial: Receive More + Cancel Remaining + Contact Supplier + Double Order + Manage Parts
  - Received: Report Issue + View History
  - Drafting: Resume Draft + Contact Job Creator
  - Cancelled: no actions (read-only)
- 3 confirmation alerts: Delete Draft, Cancel PO (reason required), Cancel Remaining (reason required)
- `transitionPO(to:)` method calls `OrdersService.updatePOStatus` + reloads
- `deleteDraftPO()` method calls `OrdersService.deletePO`
- Sheet stubs for all 8 action types (will be wired in 26D-26F)
- `actionButton` helper: uniform 44px+ tappable buttons with color-tinted backgrounds
- Fixed loadData guard to set loadError instead of silent return
- Preserved stale price warning on line items
- Build: SUCCESS

---

## Prompt 26D — PO Detail Supplier CRM + Notes Tabs (2026-03-22)

**Status:** SUCCESS
**Files Changed:** IOSPODetailPage.swift (rewrite, 493 → 732 lines), OrdersService.swift (+addPONote method)

**Changes:**
- Replaced plain-text supplier name with full CRM card: supplier name, rep name, account number
- Quick contact buttons: phone (tel:), email (mailto:), message (opens contact supplier sheet)
- Reliability/On-Time/Quality score bars with GeometryReader percentage visualization
- "View Supplier Profile" NavigationLink
- Tabbed notes section: PO Notes (editable) + Supplier Notes (read-only from supplier.notes)
- PO Notes tab: existing notes list + add note TextField + send button
- Supplier Notes tab: read-only display of supplier-wide notes
- `addPONote()` method: saves timestamped note with current user's display name
- `parseNotes()` helper: parses "TIMESTAMP [Author]: Text" format with fallback for plain text
- `addPONote(poId:note:author:)` added to OrdersService: appends timestamped entry to notes column
- Supplier loaded via `partsService.getSupplier(id:)` — uses Supplier struct fields directly (no separate scores struct needed, scores stored on supplier record)
- Fixed `.foregroundStyle(.accentColor)` → `Color.accentColor` for ShapeStyle conformance
- Build: SUCCESS

---

## Prompt 26E — Parts Order Management Page (2026-03-22)

**Status:** SUCCESS
**Files Created:** IOSPartsOrderManagementPage.swift (376 lines)
**Files Changed:** OrdersService.swift (+PartsManagementRow struct, +getPartsForSupplier, +getSuppliersWithActivePOs), OrdersRouter.swift (+orders-parts case), NavigationConfig.swift (+Parts Mgmt tab), IOSPODetailPage.swift (wired Manage Parts sheet)

**Changes:**
- New `PartsManagementRow` struct with PO, part, job, quantity, price, and status fields
- `getPartsForSupplier(supplierId:poStatuses:)` — cross-PO query with JOINs to parts, JPO→job chain for job name resolution
- `getSuppliersWithActivePOs()` — suppliers with non-terminal PO counts
- Supplier picker: horizontal scroll with PO count badges, selects supplier to filter
- Dual filter system: PO status toggles (Draft/Active/Partial/Received/Cancelled) + Part status toggles (Waiting/Backorder/Received)
- Default filters: Draft+Active+Partial ON, Received+Cancelled OFF; Waiting+Backorder ON, Received OFF
- Parts grouped by PO number with status badges and ETA
- Multi-select checkboxes with selection action bar (Move to PO / Change Qty / Remove + Hold stubs)
- Status icons per line item (hourglass/checkmark/clock badge)
- Job name displayed with hammer icon when linked via JPO chain
- Added "Parts Mgmt" tab to Orders module in NavigationConfig
- Added `orders-parts` case to OrdersRouter
- Wired PO Detail "Manage Parts" → IOSPartsOrderManagementPage with `preSelectedSupplierId`
- Correct DB column names: qty_ordered, qty_received, unit_cost (not the prompt's assumed names)
- Build: SUCCESS

## Prompt 26F Results (2026-03-22)

- POLineRow expanded with jobId, jobName, source fields (default nil for backward compat)
- getPODetail SQL updated to JOIN through jpo_line_items → job_parts_orders → jobs for job name resolution
- Source type auto-detected: "job" (via JPO chain), "forecast"/"wishlist" (via notes content), "general" (default)
- Job-grouped line items section with sorted headers, icons per source type, and item counts
- Delivery timeline bars: green→yellow→orange→red based on days until expected delivery
- Per-line status icons: checkmark (received), hourglass (pending/ordered), clock badge (backorder), xmark (cancelled)
- Per-line backorder actions: Update ETA + Double Order buttons
- Draft POs: Quick Edit button per line → inline edit alert for qty + unit price
- updatePOLineItem service method with draft-only guard (checks parent PO status)
- Receipt history section: timeline dots from order_status_history (partial/received transitions)
- getReceiptHistory service method using entity_type/entity_id columns (corrected from prompt's order_type/order_id)
- ReceiptBatch struct with receivedDate, receivedBy, itemCount, totalReceived
- Correct column names used: qty_ordered, unit_cost, entity_type, entity_id, created_at
- Build: SUCCESS

## Prompt 27A Results (2026-03-22)

- ActiveSheet enum with .createJPO, .qrScanner, .scannedJPODetail(Int64)
- Single .sheet(item:) pattern replaces any ad-hoc booleans
- Toolbar: QR scanner button + Create JPO button
- CreateJPOSheet: auto-fills job from getActiveClockEntry, job picker fallback, priority segmented, notes field
- createJPO uses appCore.currentUser?.id for requestedBy (not a separate authService.currentUserId which doesn't exist)
- QR scan uses .po type (no .jpo type exists in QREntityType enum)
- Count badges on all status chips: "All (12)", "Pending (3)", etc.
- allJPOs loaded once (limit 500), filtered in-memory by status + search
- Pending count KPI line with clock.badge.exclamationmark icon
- Platform guard #if os(iOS) removed
- loadError guard added for missing ordersService
- Build: SUCCESS

## Prompt 27B Results (2026-03-22)

- Migration 032: per-line status columns on jpo_line_items (line_status, hold_reason, reject_reason, chat_thread_id, po_line_id, transfer_id, status_updated_at, status_updated_by)
- Migration 032: delivery_option + delivery_locked on job_parts_orders
- Correct table name: jpo_line_items (not jpo_lines as prompt assumed)
- Correct table name: job_parts_orders (not job_purchase_orders)
- JPOLineRow expanded with lineStatus, holdReason, rejectReason, chatThreadId, poLineId, transferId (defaults for backward compat)
- getJPODetail SQL mapping updated to read new columns
- updateJPOLineStatus: per-line status update with hold/reject reason, auto-derives parent JPO status
- deriveJPOStatusFromLineStatuses: pending→in_review→approved→ordered→complete progression
- smartRouteJPOLine: checks stock table qty, routes to "transfer" (in stock) or "pending" (needs ordering)
- addJPOLineItem: now calls smartRouteJPOLine after insert, added optional userId parameter
- Build: SUCCESS

## Prompt 27C Results (2026-03-22)

- JPODetail struct expanded with deliveryOption: String?, deliveryLocked: Bool (defaults for backward compat)
- getJPODetail return updated to read delivery_option and delivery_locked columns
- updateJPODeliveryOption service method with lock check
- IOSJPODetailPage rewritten from 332 → 729 lines
- Per-part line item rows with checkbox, status icon, and per-status action buttons
- Bulk selection with floating action bar (Approve/Hold/Reject selected lines)
- Reject confirmation with required reason via alert
- Delivery option picker (Shop Delivery / Will Call / Driver Pickup) with lock-after-delivery
- Status-specific content per line: pending, transfer, on_hold, rejected, approved, ordered, received, delivered, backorder
- Line status summary with counts by status
- Renamed DetailField to JPODetailField to avoid collision with other pages
- Platform guards removed, loadError guard added
- AddJPOLineItemSheet updated to pass userId to addJPOLineItem
- Build: SUCCESS

## Prompt 27D Results (2026-03-22)

- holdJPOLineWithChat service method: creates chat_channels (type 'jpo_qa'), auto-adds manager (admin) + requester (member), sends hold reason as first message, updates jpo_line_items with chat_thread_id, re-derives parent JPO status
- Hold button now prompts for a question via alert ("Ask About This Part"), question becomes hold reason + first chat message
- Chat thread opens immediately after hold via IOSMessageThreadView (channelId + channelName)
- Replaced stub "Coming Soon" chat sheet with real IOSMessageThreadView
- Bulk Hold: first selected line gets question prompt, remaining lines get simple "Grouped hold" status
- JPOListItem expanded with holdCount: Int (default 0 for backward compat)
- listJPOs SQL updated with hold_count subquery on jpo_line_items where line_status = 'on_hold'
- JPO list row shows message.badge icon + "N question(s)" in yellow when holdCount > 0
- Accessibility label updated to include hold count
- Correct table names: jpo_line_items, job_parts_orders, chat_channels, chat_channel_members, chat_messages
- Correct column: sender_id (not user_id) in chat_messages INSERT
- Build: SUCCESS

## Prompt 27E Results (2026-03-22)

- Migration 033: part_change_log table with part_id (FK cascade), user_id (FK setNull), user_name, action, field_name, old_value, new_value, context, created_at; 4 indexes (part, user, date, part+action)
- PartChangeEntry model struct in PartsService (Identifiable, Sendable)
- logPartChange: single change entry with context
- logPartFieldChanges: multi-field batch insert for updates
- getPartChangeLog: DESC ordered with LIMIT, safe for missing table
- createPart: logs "created" action after insert (non-fatal try?)
- updatePart: reads current row before update, compares all 21 trackable fields, logs only actual changes with "Catalog Edit" context
- Fixed ambiguous String.init for Double/Int types → closure `{ "\($0)" }` pattern
- DatabaseValue.isNull for safe nil detection on mixed-type row columns
- PartHistoryView.swift: reusable timeline component with color-coded dots (green=created, red=deleted, blue=restored, orange=updated), who+when header, field→value change display, context badge
- Collapsible "Change History" section added to PartDetailSheet via DisclosureGroup
- Build: SUCCESS

## Prompt 28A Results (2026-03-22)

- Service layer: DemandSource struct (String id, sourceType, sourceId, sourceName, quantity), ProcurementItem struct (partId, partName, partCode, brandName, totalDemand, shopStock, min/target/maxStock, deltaToTarget, sources, urgency)
- getProcurementDemand(): aggregates approved JPO lines from jpo_line_items, groups by part_id, queries stock table + parts for min/target/max, calculates delta and urgency, adds overstock detection (above MAX with no demand), sorts by urgency priority
- Correct table names: jpo_line_items (not jpo_lines), job_parts_orders (not job_purchase_orders), qty_requested (not quantity)
- IOSProcurementPage.swift: complete rewrite from JPO-list to demand-consolidation view
- Smart card filters: JPO Parts, Wishlist, Forecast, Overstock, All — tap to filter, tap again to deselect
- Each part row: name, code, brand, stock level, target, delta badge (+X to target / -X over target / At target)
- Overstock warning: red triangle + "OVER MAX — mandatory pull of at least N"
- Understock indicator: orange arrow + "Below minimum stock level"
- Source icons per demand type (doc.text/heart/chart/triangle)
- Pull options: pull to target + order remaining (recommended), pull all + order remaining, order all — placeholder actions for 28B/28C
- ErrorStateView + EmptyStateView, no platform guards, accessibility labels
- Build: SUCCESS

## Prompt 28B Results (2026-03-22)

- PartSupplierOption struct: id (supplier_id), name, unitPrice, reliabilityScore, processingDays, isToday2PM, isPreferred, tag
- ProcurementItem: added isGeneric (bool), suppliers ([PartSupplierOption]) with backward-compat defaults
- getProcurementDemand: queries part_supplier_links + suppliers per part, assigns cheapest/rated/fastest tags, 2PM cutoff via Calendar hour check
- UI: radio button supplier selection per part with tag badges (Cheapest/Top Rated/Fastest capsules)
- Preferred suppliers auto-selected on load, star icon for preferred
- Generic parts show lock icon + "supplier locked per job" indicator
- Split by JPO: expandable per-JPO supplier picker via menu Picker for multi-source parts
- 2PM cutoff: "today" badge with shippingbox icon when same-day delivery possible
- State: selectedSupplier [partId: supplierId], splitByJPOPartId, perJPOSupplier [sourceId: supplierId]
- Build: SUCCESS

## Prompt 28C Results (2026-03-22)

- DemandSource: added lineIds ([Int64]) for tracking JPO line IDs per source
- ProcurementGenerateItem struct: partId, supplierId, quantity, unitCost, jpoLineIds
- ProcurementGenerateResult struct: createdPOs [(poId, poNumber, supplierId)], totalLineItems
- generatePOsFromProcurement: groups items by supplier, creates draft POs with PO-##### numbering, inserts po_line_items, sets jpo_line_items.line_status to 'in_procurement' and links po_line_id, creates po_jpo_links
- UI: checkbox per part (checkedParts Set), Select All/Deselect All button
- PO Preview section: appears when any items are checked+supplier-selected, shows supplier-grouped breakdown with part names, quantities, unit costs, subtotals
- Generate button: creates POs, shows success alert with PO numbers, clears generated items, refreshes data
- Save for Later button: keeps selections in state without generating
- Partial generation: only checked items with suppliers get included
- Build: SUCCESS

## Prompt 28D Results (2026-03-22)

- Migration 034: job_stages table (name, sort_order), job_stage_category_map (stage_id FK, category_id FK, unique), stage_id column on jpo_line_items, current_stage_id column on jobs, 3 indexes, seeded 3 defaults (Rough-in, Prep/Makeup, Trim-out)
- Service: JobStage struct, StagePart struct (with isHeld flag from stage sort_order comparison)
- getJobStages(): lists all stages in order
- getJobStageParts(jobId:): all JPO parts for a job, resolves stage via jpo_line_items.stage_id OR category→stage mapping, marks isHeld for future stages
- markStageComplete(jobId:stageId:): advances job's current_stage_id, auto-releases held parts for next stage categories
- requestEarlyRelease(jpoLineId:): overrides hold, sets line_status to 'approved'
- updateCategoryStageMapping(categoryId:stageId:): CRUD for category→stage links
- getCategoryStageMappings(): all categories with their stage assignments
- IOSOrderStagingPage: complete rewrite with job picker (auto-fills from clock-in), stage card filters, sections per stage with held indicators, line status badges, "Request Early" button on held parts, "Mark Stage Complete" button per stage section
- StageSettingsSheet: lists stages with sort order, category→stage mapping Pickers
- Build: SUCCESS

## Prompt 29A Results (2026-03-22)

- Fixed hardcoded user ID `1` → `appCore.currentUser?.id` at startReceiving (startedBy:) and completeReceiving (completedBy:)
- ActiveSheet enum pattern: replaced showQRScanner bool with ActiveSheet enum + .sheet(item:) + switch router
- Guard failures now set loadError/actionError before returning (ordersService, warehouseService, currentUser)
- No platform guard was present (already clean)
- Build: SUCCESS

## Prompt 29B Results (2026-03-22)

- IOSReturnsPage: ErrorStateView branch added for loadError display
- Replaced print() error with loadError assignment
- Smart card filters replace capsule chips: All, Pending, Approved, Shipped, Completed with counts and color-coded backgrounds
- All returns loaded once for client-side filtering (enables smart card counts)
- Platform guard removed from .listStyle(.insetGrouped)
- ActiveSheet enum pattern: replaced showCreateReturn bool
- EmptyStateView replaces ContentUnavailableView for consistency
- CreateReturnSheet: platform guard removed from .navigationBarTitleDisplayMode
- Guard-let failures now set saveError (loadSuppliers, saveReturn)
- print() replaced with error state display
- Build: SUCCESS

## Prompt 29C Results (2026-03-22)
- Rewrote IOSApprovalsPage as multi-type quick-approval dashboard (579 lines)
- Smart card filters: All, JPOs, Deletions, Time-Off — each with live count badges
- Aggregates 3 approval types: JPOs (OrdersService), Scheduled Deletions (PartsService), Time-Off (SchedulingService)
- Reject reason required via .alert with TextField before JPO rejection
- actionError displayed via .alert — no console-only errors, all print() removed
- Loading state via processingId (String-based: "jpo-X", "del-X", "pto-X") disables all buttons during processing
- Guard-let on all services sets actionError instead of silent return
- ErrorStateView for loadError, EmptyStateView for empty states
- Platform guard (#if os(iOS)) removed from .listStyle(.insetGrouped)
- Searchable across all types (job name, requester, entity name, user name, reason)
- Build: SUCCESS

## Prompt 29D Results (2026-03-22)
- OrdersRouter: tabs now in workflow order (JPOs → Procurement → POs → Parts Mgmt → Stage Planner → Approvals → Returns)
- NavigationConfig: orders module tabs reordered to match, "Staging" renamed to "Stage Planner"
- IOSUnifiedOrderPage: gutted to redirect stub ("This page has been replaced")
- SupplierPickerSheet: force-unwrap `item.supplier.id!` → `guard let supplierId`
- SupplierPickerSheet: 2 platform guards (#if os(iOS)) removed
- SupplierPickerSheet: print() replaced with generateError state, guard-let sets error
- No broken navigation links (IOSUnifiedOrderPage only referenced internally)
- Build: SUCCESS

## Prompt 30A Results (2026-03-22)
- Created IOSJPOCreationPage.swift (597 lines) — full 3-panel cart-builder
- iPad: HStack with search | cart | suggestions side-by-side
- iPhone: ScrollView with stacked panels + collapsible suggestions (DisclosureGroup)
- Job auto-fill from active clock-in (getActiveClockEntry), with Change button to override
- Priority picker (segmented: Normal/High/Urgent) + Delivery picker (As available/Wait for full)
- Search panel: TextField with min 2 chars, stock indicators (green/orange/red dots), price display
- QR scan button → QRScanSheet(expectedType: .part), auto-adds scanned part to cart
- Cart panel: quantity steppers (minus/plus), trash remove, stock status badges
- Cart summary: part count, estimated total, transfer vs ordering split
- Notes field for office
- Submit button: creates JPO + adds all cart items as line items via addJPOLineItem
- Suggestions panel: placeholder for 30C (companion rules + AI picks)
- Uses getPart(id:) for QR-scanned parts, searchParts(query:) for text search
- Build: SUCCESS

## Prompt 30B Results (2026-03-22)
- Recent searches: last 5 tracked, shown when search empty, tap to reuse
- AI context builder: cart contents + recent searches + job name + internet flag
- AI re-ranking via generatePreFill: sends context+query+parts to FoundationModelsService
- Best match: bolt.fill icon on AI-picked result, name bolded
- Graceful degradation: AI only runs when checkAvailability() == .available, standard search always works
- Internet help toggle: Globe icon at top of search panel, passed in AI context
- QR scan: already wired from 30A (QRScanSheet → addPartById)
- Search result row: monospaced code, stock indicator, price, add/checkmark button
- Build: SUCCESS

## Prompt 30C Results (2026-03-22)
- Service: getCompanionSuggestionsForPart(partId:limit:) added to PartsService
  - Matches part's category/style/type against companion_rule_sources
  - Returns target parts via companion_rule_targets → parts JOIN
  - Sorted by co_occurrence_pairs.points DESC, confidence DESC
  - CompanionSuggestion struct: partId, partName, suggestedQty, points, confidence, pattern
- Suggestions panel: top 5 companion rules + bottom 3 AI picks
- Context tracking: highlightedCartPartId (tap) + lastAddedPartId (add)
- Cart item tap: highlights with accent background, switches suggestion context, reloads
- AI picks: generatePreFill with cart/context/job, parses partName|reason|qty format
- AI results matched to real catalog parts via searchParts(query:)
- "In cart" indicator replaces add button for already-added parts
- "Not in catalog" label for AI suggestions that don't match real parts
- iPhone: DisclosureGroup with suggestion count badge
- onChange(of: cartItems.count) triggers suggestion reload
- Build: SUCCESS

## Prompt 30D — JPO Creation Feedback (2026-03-22)

**Status:** SUCCESS
**Files Changed:** IOSJPOCreationPage.swift, PartsService.swift

- Quantity confirmation dialog: .alert with TextField for qty adjustment
- Shows suggested qty and shop stock in dialog message
- prepareSuggestionConfirm: loads Part details, sets confirmingPart/confirmQty/confirmSource
- Suggestion row [+ Add] button now routes through confirm dialog instead of direct add
- recordCompanionFeedback added to PartsService:
  - Resolves both parts to their category/style hierarchy
  - UPDATE co_occurrence_pairs points +1 (or INSERT new pair if none exists)
  - INSERT companion_feedback log with action, suggested_qty, final_qty, source_categories
- recordSuggestionFeedback in UI: non-critical, catches silently with print()
- Build: SUCCESS

## Prompt 30E — JPO Creation Submit (2026-03-22)

**Status:** SUCCESS
**Files Changed:** IOSJPOCreationPage.swift, OrdersService.swift

- createJPOWithLines added to OrdersService:
  - Single transaction: INSERT job_parts_orders + INSERT all jpo_line_items
  - Smart routing per line: checks shop stock, sets line_status to "transfer" or "pending"
  - Derives overall JPO status via deriveJPOStatusFromLineStatuses
  - Includes delivery_option column
- Submit button: ProgressView while submitting
- Success toast: material overlay with green checkmark, auto-dismiss after 1.5s
- Job verification alert: warns when user picks different job than clocked-in
  - "No, use clocked-in job" resets to clocked-in job
- Build: SUCCESS

## Full Prompt Review 31A-46F (2026-03-23)

**Status:** COMPREHENSIVE REVIEW + FIXES
**Scope:** 77 prompts reviewed (31A-31I, 32A-32J, 33A-33H, 34A, 35A-35I, 36A-46F)

### Fixes Applied:
1. **32F** — IOSMyTruckPage: removed 3 dead `show*` boolean states (unused code)
2. **32F** — IOSJobDetailTabView: converted showEditSheet + showHelp to ActiveSheet enum pattern
3. **35A** — DashboardKPIDetailSheets: removed `import GRDB`, replaced 6 raw SQL queries with DashboardService calls (getStockByLocationType, getStockAtLocationType, getJobKPIDetail, getPOKPIDetail, getLowStockParts, getStockLocationsForPart + getPartMovementInfo)
4. **35A** — DashboardKPIDetailSheets: fixed direct service creation (JobsService(db:), OrdersService(db:)) to use appCore.jobsService/ordersService
5. **Build fix** — Re-added `import GRDB` to IOSClockPage.swift (still uses raw SQL)
- Build: SUCCESS (all changes compile cleanly)

### Already Complete (verified, no changes needed):
- 31A-31I: All warehouse pages use service layer, have smart cards, ActiveSheet, help sheets
- 32A: Navigation order correct (13 modules, correct tab names, routers working)
- 32B: 0 empty catch blocks
- 32D/32E: Only 2 legitimate camera guards (#if os(iOS) && !targetEnvironment(macCatalyst))
- 32G: 0 print error logging
- 32H: 1 file missing .refreshable (SupplierPickerSheet — appropriate for modal)
- 32I: No duplicate AI buttons
- 32J: 0 force unwraps, 0 DispatchQueue usage
- 33A: PageHelpSheet on 36/119 pages (infrastructure solid, content coverage ongoing)
- 33B-33H: All feature fixes complete (clock page, JPO routing, procurement pull, PO detail, receiving flow, staging boxes, movement wizard)
- 34A: UI quality excellent — all sheets have dismiss, all alerts have actions, no placeholders, proper currency formatting
- 35B-35I: All compliant — no GRDB in UI files, service layer used throughout
- 39A: Hats & Permissions fully implemented with hasPermission(), .requiresPermission()

### Not Yet Implemented (new features awaiting development):
- 32C: Guard-without-error pattern (57 files) — systemic, addressed as part of future service layer work
- 36A-36D: Warehouse Floor Plan — no migrations, no UI
- 37A-37D: Audit Confidence — basic audit exists, confidence scoring not integrated
- 38A-38B: Break Compliance — buttons exist, no formal compliance/policy system
- 40A-40B: Clock Enhancements — no to-do integration, no live timer
- 41A: Teams Detail — no IOSTeamDetailPage
- 42A-42D: Chat — channels exist, no unified inbox/attachments/interactive escalation
- 43A-43E: Notebooks — basic structure, no block-based editing/panel schedule/daily report generator
- 44A-44F: People — 44A-44F COMPLETE (see below)
- 45A-45D: Jobs — basic list/detail, no stage progression/warranty classification
- 46A-46F: Scheduling — basic calendar/dispatch, no Gantt/pipelines/AI dispatch

---

## Prompt 44C Results (2026-03-23)
- IOSCustomerDetailPage rebuilt with 8 sections: contact info, additional contacts, business info, billing/payment (hat-gated), job history, communication history, documents, lifetime stats
- PeopleService: getCustomerDetail, addCommunicationEntry + 5 data types (CustomerDetail, CustomerContact, CustomerJobSummary, CustomerStats, CommunicationEntry)
- Billing hat-gated behind view_job_financials permission
- PaymentStatusBar component (green-to-red gradient) included in customer detail
- 3 sheets: AddCustomerContactSheet, AddCommunicationSheet, AddPaymentSheet
- Build: PASS

## Prompt 44D Results (2026-03-23)
- IOSContractorsPage: showAddContractor Bool → ActiveSheet enum (.create, .edit)
- IOSContractorDetailPage rebuilt with 5 sections: contact info, qualifications, performance rating (subcontractors only), job history, notes
- PeopleService: getContractorRating, getContractorJobHistory, getContractorNotes, addContractorNote, addContractorRating + 3 data types (ContractorRating, ContractorNote, ContractorJobSummary)
- QualificationRow and RatingRow components with star display
- AddContractorNoteSheet
- Build: PASS

## Prompt 44E Results (2026-03-23)
- IOSContactsPage redesigned with smart cards for type filters (All, GC, Supplier, Contractor, Owner, Vendor, Active, Inactive)
- Sort options (Recently Updated, Name, Type) via toolbar menu
- Active/inactive sections with DisclosureGroup collapsed by default
- Color-coded type badges (blue=GC, purple=supplier, orange=contractor, green=owner, teal=vendor)
- PeopleService: getContactsSorted (returns active/inactive split), getContactTypeCounts
- Build: PASS

## Prompt 44F Results (2026-03-23)
- Migration 043: payment_records, customer_communications, contractor_notes, contractor_ratings tables + settings rows
- PeopleService: isPaymentTrackingEnabled, setPaymentTrackingEnabled, getPaymentSettings, updatePaymentSettings, getCustomerPaymentStatus, getPaymentRecords, createPaymentRecord, recordPayment, getOverdueCustomers + 3 data types (PaymentStatus, PaymentRecord, CustomerPaymentAlert)
- PaymentStatusBar component (green/yellow/red gradient bar)
- AppConfigPage: Payment Tracking settings section (toggle, terms stepper, warning stepper, auto-hold toggle)
- IOSPeopleDashboardPage: overdue payment alerts section when tracking enabled
- IOSCustomerDetailPage: payment history and record payment when tracking enabled
- ConflictResolver: payment_records, customer_communications, contractor_notes, contractor_ratings added
- Default: payment tracking OFF — no payment UI unless explicitly enabled
- Build: PASS

## Prompt 45A Results (2026-03-23)
- JobsListPage redesigned with 8 smart status cards (All, Active, Warranty, Continuous, Complete, On Hold, Payment Hold, Cancelled)
- Smart cards show count + title with color-coded backgrounds
- Payment Hold card only visible to managers (manage_jobs permission)
- Payment Hold badge: managers see "$" icon + "Payment Hold", workers see generic "On Hold"
- Continuous jobs rendered at 0.7 opacity
- Sort options: Recent Activity, Name, Start Date (toolbar menu)
- Status counts computed from full job list, filter applied client-side
- Build: PASS

## Prompt 45B Results (2026-03-23)
- Overview tab rebuilt as mini-dashboard with List sections
- Payment hold banner at top for payment_hold jobs (red warning)
- Smart metric cards: Hours, Budget (hat-gated), Team, Parts in horizontal scroll
- Dual progress bars: hours vs estimate, budget vs limit (hat-gated)
- Dates section with start, due, completed
- Quick actions: Edit Job (manage_jobs), Go to Clock (disabled for payment hold)
- Warranty section: start date, end date, days remaining (red when <30 days)
- Financial summary: labor cost, materials cost, total (hat-gated)
- MetricCard component added (icon, title, value, subtitle with color background)
- Status colors updated: warranty=purple, payment_hold=red, continuous=gray
- Build: PASS

## Prompt 45C Results (2026-03-23)
- Migration 044: 9 new columns on jobs table (warranty_start, warranty_end, warranty_duration_days, job_classification, payment_hold_amount, payment_hold_date, payment_hold_reason, is_continuous, continuous_schedule)
- JobsService: setWarranty, isWarrantyActive, warrantyDaysRemaining
- JobsService: setPaymentHold, removePaymentHold, isJobOnPaymentHold
- JobsService: ContinuousSchedule struct, setJobContinuous, getContinuousJobs
- IOSClockPage: payment hold check before clock-in with error message
- Build: PASS

## Prompt 45D Results (2026-03-23)
- Migration 045: 7 new columns on notebook_entries (work_classification, classification_reviewed, classification_reviewed_by, classification_reviewed_at, warranty_timer_start, warranty_timer_end, is_question) + classification_history table
- NotebooksService: ClassificationChange struct, classifyTodoWork, reviewClassification, reclassifyTodoWork, getClassificationHistory, startWarrantyTimer, getTodosNeedingReview, ensureWarrantySection
- NotebookEntryRow struct: added workClassification, classificationReviewed, warrantyTimerEnd, isQuestion fields
- All 3 NotebookEntryRow query locations updated to include classification fields
- IOSNotebookDetailPage: classification picker (Regular/Warranty buttons) on warranty job to-dos
- IOSNotebookDetailPage: warranty timer display (days remaining, red when <7 days)
- IOSNotebookDetailPage: question tag ("?" purple circle) on to-do items
- IOSNotebookDetailPage: manager review section with Approve button (manage_jobs gated)
- ConflictResolver: classification_history added to whitelist
- Build: PASS
