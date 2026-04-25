# Fix Prompt Order — WiredPart iOS Phase 2

> **Phase 1 complete.** All 279 prompts (01–67A) are archived in `done/`.
> **Phase 2 HIG/Security work complete.** PE-009a/b/c/d/e, PE-008a/b/c/d/e, PE-022, PE-001, PE-024, PE-025, PE-026 all done. All archived to `done/`.
> **Phase 3 status (page-rebuild-enforcer 2026-04-06 + hunt-fix 2026-04-07):** PE-034 ✅ DONE. PE-035 ✅ DONE. PE-036 ✅ DONE — all 3 wizards verified; WarehouseOnboardingWizard already had isSaving + interactiveDismissDisabled. PE-037 ✅ DONE — all 9 Create/Form sheets confirmed to have interactiveDismissDisabled in working tree (hunt-fix run 14). PE-038 ✅ DONE — JobStageProgressBar font fixed directly. PE-039 ✅ DONE — PartsFlowWizard + CartManager both fully async. DIS-009 ✅ CLOSED — both locations verified async.
> **PE-041 ✅ DONE (page-rebuild-enforcer 2026-04-08):** Receiving session auto-save draft — auto-save on every qty change (minus/plus/All/Reset/Clear/barcode), restore from DB on resume, discard confirmation removed. 1118 tests pass.
> **PE-040 ✅ DONE (page-rebuild-enforcer 2026-04-08):** WizardStepPlacement complete rewrite — Phase A dimensions form (rows×cols steppers → Confirm Grid → saves grid_rows/grid_cols via migration 073), Phase B drag-and-drop grid via .onDrag/.dropDestination, placed units can be re-dragged, back-compat: gridDimensions auto-restored from DB on load. 1118 tests pass.
> DIS-012/013/014 security items still blocked on owner design decisions.
> **PE-COLORS Phase 2 UI (auto-go C2b 2026-04-18):** PE-046 (CategoriesTreeView SKU rows + editor), PE-047 (CategoriesColorPicker named-only variants), PE-048 (TypeBrandColorSection rewrite), PE-049 (New Supplier linked-brand picker) queued. Backend ready (migration 074 + CRUD, commit 13cd7b2). #237, #238, #239, #240 tracked. Write prompts before executing.

---

## How to Use

1. Pick the next prompt from the queue below
2. Paste the prompt file contents into Xcode AI
3. Run it, verify the result
4. Mark it DONE here and move the file to `done/`

---

## Queue

| # | File | What It Fixes | Status |
|---|------|---------------|--------|
| PE-051 | `PE-051-dismiss-guard-tools-sheets.md` | **Dismiss Guard: Phase 1D Tools sheets** — `IOSToolDetailPage.swift`: add `isDirty` + Discard alert to 5 sheets: `ToolEditSheet`, `ToolReportIssueSheet`, `LostStolenReportSheet`, `MaintenanceConfigSheet`, `ToolTradeSheet`. Sheets with only optional notes (`ToolCheckoutSheet`, `ToolReturnSheet`) already have sufficient `isSaving` guard. Plan: `docs/plans/dismiss-safety-campaign.md` Phase 1D. GitHub #143. | 🔲 **NEXT after PE-COLORS** |
| PE-049 | *(to be written)* | **PE-COLORS Phase 2D — New Supplier sheet linked-brand picker** — `PartsSuppliersPage`: mirror existing `BrandSupplierPickerSheet` (brands→suppliers) in the reverse direction — adding a new supplier should prompt "which brands does this supplier carry?" using a multi-select brand picker. GitHub #240. Plan: `docs/plans/ios-brands-suppliers-editing.md`, `docs/plans/colors-parts-redesign.md` Concept 4. Backend: `brand_supplier_links` table + BrandsService CRUD already exist. | 🔲 to be written |
| PE-048 | *(to be written)* | **PE-COLORS Phase 2C — TypeBrandColorSection rewrite** — `TypeBrandColorSection.swift`: drop the old nested brand→color mental model, replace with flat SKU list grouped by variant. Each row: variant chip (color hex fill or text-only pill for hex=NULL), brand badge, part_number. Tapping a SKU row opens `ColorBrandSKUEditorSheet` (inline create/edit: variant picker + brand picker + part_number + unit_cost). GitHub #239. Plan: `docs/plans/colors-parts-redesign.md` Concept 1+2. Backend: PartsService.upsertColorBrandSKU already exists (commit 13cd7b2). | 🔲 to be written |
| PE-047 | *(to be written)* | **PE-COLORS Phase 2B — CategoriesColorPicker named-only variants** — `CategoriesColorPicker.swift`: add a "Named-Only" chip type for colors where `hex_code IS NULL` (e.g. "Standard", "Fire-Rated", "Metal"). Picker shows full shared `part_colors` pool — not type-scoped. Color chip renders hex fill if present; text-only pill if hex=NULL. "Add New Variant" action supports creating either type (hex optional). GitHub #238. Plan: `docs/plans/colors-parts-redesign.md` Concept 1. | 🔲 to be written |
| PE-046 | *(to be written)* | **PE-COLORS Phase 2A — CategoriesTreeView SKU rows + editor panel** — `CategoriesTreeView.swift`: under each (type × brand) node render `color_brand_skus` rows; each row shows variant chip + brand badge + part_number. Tapping row opens `ColorBrandSKUEditorSheet` for part_number, unit_cost, stock_qty. Service calls: `PartsService.getColorBrandSKUs(typeId:brandId:)` + `upsertColorBrandSKU`. Subsumes #100, #106, #144. GitHub #237. Plan: `docs/plans/colors-parts-redesign.md` Concept 2. Backend: migration 074 + CRUD landed commit 13cd7b2. | 🔲 **PE-COLORS NEXT** — write prompt first |
| PE-045 | *(archived)* | **Dismiss Guard: Phase 1A remaining People/HR sheets** — ~~EditEmployeeContactSheet (IOSEmployeeDetailPage)~~ ✅, ~~AddCustomerSheet (IOSCustomersPage)~~ ✅, ~~AddContractorSheet (IOSContractorsPage)~~ ✅, ~~AddContactSheet (IOSContactsPage)~~ ✅. Also covered: AddHatSheet (IOSHatsPage), AddTeamSheet (IOSTeamsPage), EditTeamSheet (IOSTeamDetailPage), AddContractorNoteSheet (IOSContractorDetailPage), EditContactSheet (IOSContactDetailPage). Pattern: `isDirty` + `.interactiveDismissDisabled(isDirty)` + Discard alert. Plan: `docs/plans/dismiss-safety-campaign.md`. GitHub #143. | ✅ **DONE 2026-04-19** — direct Swift edit during AUTO GO people C7 sweep (all 9 sheets fixed, no Xcode AI needed) |
| PE-044 | `PE-044-dismiss-guard-ios-employees-page.md` | **CANONICAL TEMPLATE** for #143 Dismiss Safety campaign (Phase 1A, People/HR first). Adds per-sheet dirty tracking + discard-changes alert + `.interactiveDismissDisabled(isDirty)` to IOSEmployeesPage new/edit employee sheet. Follow-up prompts PE-045+ reference this as the pattern. Plan: `docs/plans/dismiss-safety-campaign.md`. GitHub #143 / #123. | ✅ **DONE 2026-04-15** — direct Swift edit (commit 7024173: usability guards pass; AddEmployeeSheet has `isDirty` + `.interactiveDismissDisabled(isDirty)` + Discard alert; verified plan-enforcer run 15) |
| PE-043 | *(archived)* | IOSMessageThreadView: wire dead photo + reference picker buttons — PhotosPicker + 3 reference list sheets. GitHub #152. | ✅ **DONE 2026-04-15** — direct Swift edit (PhotosPicker + ReferencePickerSheet wired; usability-enforcer Run 9 verified) |
| PE-042 | *(archived)* | Cart Mode UI — multi-bin tap-to-select, Place Cart sheet, area picker, async bin move (GitHub #138). WizardStepPlacement.swift fully implemented. | ✅ **DONE 2026-04-12** — direct Swift edit (commit 37ffeb7) |
| PE-041 | `PE-041-receiving-auto-save-draft.md` | Receiving session: auto-save `receivedQtys` to DB on each qty change; remove discard confirmation (GitHub #36) | ✅ **DONE 2026-04-08** — direct Swift edit |
| PE-040 | `PE-040-warehouse-wizard-dragdrop-placement.md` | Warehouse wizard step 4: dimensions-first input → true drag-and-drop placement replacing tap-to-place (GitHub #22) | ✅ **DONE 2026-04-08** — direct Swift edit + migration 073 |
| PE-022 | *(archived)* | Hat assignment UX (GitHub #17): tappable hat rows → HatDetailSheet, People Dashboard management tiles, Employee Detail "Permissions Granted" section | ✅ done (2026-03-31) |
| PE-001 | *(archived)* | Tool page rename: "Tool Registry" → "All Tools", "Tool Admin" → "Management" | ✅ done (2026-03-31) |
| PE-008c | *(archived)* | People → Permissions banner: warns admin when users still have legacy PIN hashes (auto-upgrade on login is already in place) | ✅ done (2026-03-31) |
| PE-024 | *(archived)* | All modal/sheet popups don't close — audited 2026-04-03, all patterns already correct, no changes needed (GitHub #21 code-verified) | ✅ done (2026-04-03) — no changes needed |
| PE-025 | *(archived)* | Teams empty state, Edit Tabs layout, Settings Page Layout descriptions (GitHub #30, #31, #32) | ✅ done (2026-04-04) — IOSTeamsPage, TabBarEditorView, TabBarPreferences, UserMenuSheet updated; committed 826dd18. Also includes CategoriesTreeView @State→@Binding fix (partial #46 impl). |
| PE-026 | *(archived)* | Badge counts on all tabs (real-time, green/red tint), action button border rings, notebook update badges (GitHub #50, #51) | ✅ done (2026-04-04) — BadgeCountService + BadgeCountManager + ActionDot/actionRing on all approval/action pages |
| PE-031 | *(done — direct edit)* | Clock In/Out bug fix — GPS permission race + alreadyClockedIn recovery (GitHub #20) | ✅ DONE 2026-04-04 — implemented directly: needsLocationPermission, alreadyClockedIn recovery, os.Logger, error banner |
| PE-034 | *(archived — code done)* | Quick UX fixes: loading indicators (3 pages), pull-to-refresh (templates), sheet detents (7 sheets), timer lifecycle (dashboard) | ✅ DONE 2026-04-06 — all 4 DIS fixes confirmed in code (commits 3ddbc61 + direct edits). Prompt archived to done/. |
| PE-027 | *(done — direct edit)* | Part numbers at color level, supplier part numbers per color × supplier, search by PN + abbrev (GitHub #46) | ✅ DONE 2026-04-04 — migration 065, PartsService, CategoriesTreeView, CategoriesFormSheets, 4 tests |
| PE-028 | *(archive — work done)* | Brands & Suppliers editing — Migration 066 + carry_status + bidirectional UI in PartsBrandsPage/PartsSuppliersPage (GitHub #47) | ✅ DONE 2026-04-04 — move `PE-028-brands-suppliers-editing.md` to `done/` |
| PE-029 | *(done — direct edit)* | Price chips on catalog color rows, CascadePriceEditSheet with cascade, PartsPricingPage full impl (GitHub #48) | ✅ DONE 2026-04-04 — PricingService methods, CascadePriceEditSheet, PartsPricingPage, 4 tests |
| PE-030 | *(done — direct edit)* | Warehouse setup optional, dismissable banner, onboarding wizard 6 steps, setup tiers (GitHub #49) | ✅ DONE 2026-04-04 — setup gate removed, banner on dashboard, WarehouseOnboardingWizard |
| PE-032 | *(archive — work done)* | Schedule Config additive — Migration 069 `shift_templates`+`company_holidays`, IOSScheduleConfigPage 823 lines with all sections (GitHub #29) | ✅ DONE 2026-04-04 — move `PE-032-schedule-config-additive.md` to `done/` |
| PE-033 | *(archive — work done)* | Wishlist 3-section layout — Migration 070, WishlistService methods, IOSWishlistPage 3-section layout (GitHub #93) | ✅ DONE 2026-04-04 — move `PE-033-wishlist-section-layout.md` to `done/` |
| PE-003 | *(archived — work done)* | Flex pool UI — `IOSFlexPoolPage` (209 lines) wired in SchedulingRouter + NavigationConfig. `IOSJobDetailTabView` manager toggle. Permission fix: `manage_flex_pool`/`self_assign_flex` added to AuthService. | ✅ DONE 2026-04-05 |
| PE-035 | *(archived — code done)* | Company Setup Wizard PII fix — Migration 072 + SettingsService + CompanySetupWizard fully migrated from UserDefaults to SQLite draft. | ✅ DONE 2026-04-06 — commits a7ed218 + 5135ee2. Prompt archived to done/. |
| PE-036 | *(archived — code done)* | Wizard safety — IOSMovementWizard ✅, PartsFlowWizard ✅, WarehouseOnboardingWizard ✅ (`isSaving` + `interactiveDismissDisabled` + all buttons disabled — confirmed in working tree diff 2026-04-06). GitHub #115. | ✅ DONE — all 3 wizards hardened. Working tree uncommitted. |
| PE-037 | *(archived — confirmed done 2026-04-07)* | Sheet dismiss guard batch 1 — all 9 sheets confirmed to have `.interactiveDismissDisabled(isSaving)` in working tree. Files: CreateChannelSheet, IOSCreateTrailerSheet, IOSCreateVehicleSheet, CreateNotebookSheet, CreatePOSheet, CreateReturnSheet, CascadePriceEditSheet, CreateDispatchSheet, RequestTimeOffSheet. GitHub #120/#123. | ✅ DONE — verified hunt-fix run 14 |
| PE-038 | *(fixed directly — DIS-008 fully done)* | Fix hardcoded font `.system(size: compact ? 6 : 10)` in `JobStageProgressBar.swift:45` → `.system(.caption2, weight: .bold)` with `minimumScaleFactor`. Both files now use semantic Dynamic Type. | ✅ DONE 2026-04-06 — page-rebuild-enforcer, direct Swift edit |
| PE-039 | *(archived — fully done 2026-04-07)* | PartsFlowWizard.saveAllProgress() DB loop wrapped in Task{}, isSaving lifecycle consolidated with andDismiss param. CartManager.placeAllItems() also confirmed in Task{} with isPlacingItems lifecycle. DIS-009 fully closed. | ✅ DONE — both locations confirmed async, hunt-fix run 14 |
| PE-009a | *(closed — direct edit)* | HIG: 83 hardcoded font sizes → semantic styles (GitHub #11 closed) | ✅ closed — fixed directly in 38ca2bb; archive prompt to `done/` |
| PE-009b | *(archived)* | HIG: 12 undersized tap targets (< 44×44pt) (GitHub #12) | ✅ done (2026-04-02) — direct edits 38ca2bb + contentShape pass; all 13 locations ≥44×44pt |
| PE-009c | *(archived)* | HIG: 2 remaining swipe-to-delete (all 5 files confirmed) | ✅ done (2026-04-02) — all 5 files verified with candidate+dialog pattern |
| PE-009d | *(closed — direct edit)* | HIG: 9+ color-only status indicators (GitHub #15 closed) | ✅ closed — fixed directly in 38ca2bb |
| PE-009e | *(closed — direct edit)* | Accessibility labels — 347 `.accessibilityLabel()` + 305 `.accessibilityHidden()` (GitHub #14 closed) | ✅ closed — fixed directly in 38ca2bb |
| PE-011 | *(closed)* | 12 force unwraps in `ReportDateRange.swift` — fixed in commit 4b0c71a | ✅ closed |
| PE-012 | *(closed)* | `Calendar.current.date(byAdding:)!` in 15 files — fixed in commit 4b0c71a (all 15 files updated) | ✅ closed |
| PE-013 | *(closed)* | **A1** Stale `init()` migration re-fires on fresh build — `hasSeenWelcome` now consumed (removed) after applying bypass, so a subsequent fresh DB build re-detects empty DB and clears flags | ✅ fixed (github-issues-sync 2026-03-29) |
| PE-014 | *(closed)* | **A2** `performDatabaseReset()` didn't clear UserDefaults onboarding flags — now clears `hasCompletedOnboarding`, `hasCompletedCompanySetup`, `hasSeenWelcome` | ✅ fixed (github-issues-sync 2026-03-29) |
| PE-015 | *(closed)* | **A3** Fresh DB with stale UserDefaults skipped wizards — `bootstrap()` now clears onboarding flags when DB is empty (no users + no profile) | ✅ fixed (github-issues-sync 2026-03-29) |
| PE-016 | *(closed)* | **C5** `localRow!` force unwraps in `ConflictResolver.swift` lines 358 + 414 — replaced with `guard let existingRow = localRow` pattern | ✅ fixed (github-issues-sync 2026-03-29) |
| PE-017 | *(note)* | **B3** Issue reports multi-user audit backend missing — both `getMultiUserAuditAssignments()` and `resolveMultiUserAudit()` ARE implemented (WarehouseService.swift lines 3883+, 3975+) | ✅ not an issue |
| PE-018 | *(note)* | **C3** Migration 039 `try? db.drop()` — intentional "drop if exists" pattern; GRDB wraps each migration in a transaction so `try db.create()` failure rolls back cleanly | ✅ not a risk |
| PE-019 | *(note)* | **C2** CompanySetupWizard partial save — uses `try` (not `try?`), each step has its own `do/catch` with `saveError` feedback; not a silent failure | ✅ acceptable |
| PE-020 | *(closed)* | **B1+B2+B4** Audit count recording — migration 062 added `counted_qty` to stock, all three methods fixed, 3 tests added and passing | ✅ closed (hunt-fix 2026-03-30) |
| PE-021 | *(closed)* | Token signing key now Keychain-backed — persists across restarts, 256-bit random key, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ✅ closed (hunt-fix 2026-03-30) |

---

## Security (Core Swift — not Xcode AI)

These require changes in `core/Sources/WiredPartCore/` — write and test directly, don't use Xcode AI:

| # | What | Severity |
|---|------|----------|
| PE-008a | ~~Unsigned session tokens (forgeable)~~ | ✅ **Fixed** (b3eef3b) — HMAC-SHA256 signing with `SymmetricKey` in `AuthService` |
| PE-008b | ~~No brute-force protection on PIN login~~ | ✅ **Fixed** (b3eef3b) — Exponential lockout with `lockoutDuration()` in `AuthService` |
| PE-008c | Hardcoded legacy salt in PIN hashing — `getLegacyHashedUserCount()` added to AuthService; banner added to IOSPermissionsPage.swift | ✅ done (2026-03-31) |
| PE-008d | LAN sync uses plain HTTP — **Fixed** X25519 ECDH + AES-GCM payload encryption in `SyncCrypto`, `LanSyncServer`, `PeerManager`; backward-compatible; 6 new tests | ✅ closed (github-issues-sync 2026-03-31) |
| PE-008e | ~~Data export not gated behind admin permission~~ | ✅ **Fixed** (4b0c71a) — IOSDataExportPage now checks `export_reports` permission |

---

## Phase 1 Archive

279 prompt files archived in `done/`. Covers everything from sheet dismiss (01) through user attribution (67A).
