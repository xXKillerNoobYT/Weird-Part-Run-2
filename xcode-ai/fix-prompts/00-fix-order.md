# Fix Prompt Order — WiredPart iOS Phase 2

> **Phase 1 complete.** All 279 prompts (01–67A) are archived in `done/`.
> **Phase 2 HIG/Security work complete.** PE-009a/b/c/d/e, PE-008a/b/c/d/e, PE-022, PE-001, PE-024, PE-025, PE-026 all done. All archived to `done/`.
> Build: 0 errors, 0 warnings. Tests: 909/909 passing (hunt-fix-verify 2026-04-04).
> **Active prompts:** PE-031 EMERGENCY first (workers can't clock in). Then PE-027→028→029→030→032→033. PE-033 written this run (github-issues-sync 2026-04-04 run 5).

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
| PE-022 | *(archived)* | Hat assignment UX (GitHub #17): tappable hat rows → HatDetailSheet, People Dashboard management tiles, Employee Detail "Permissions Granted" section | ✅ done (2026-03-31) |
| PE-001 | *(archived)* | Tool page rename: "Tool Registry" → "All Tools", "Tool Admin" → "Management" | ✅ done (2026-03-31) |
| PE-008c | *(archived)* | People → Permissions banner: warns admin when users still have legacy PIN hashes (auto-upgrade on login is already in place) | ✅ done (2026-03-31) |
| PE-024 | *(archived)* | All modal/sheet popups don't close — audited 2026-04-03, all patterns already correct, no changes needed (GitHub #21 code-verified) | ✅ done (2026-04-03) — no changes needed |
| PE-025 | *(archived)* | Teams empty state, Edit Tabs layout, Settings Page Layout descriptions (GitHub #30, #31, #32) | ✅ done (2026-04-04) — IOSTeamsPage, TabBarEditorView, TabBarPreferences, UserMenuSheet updated; committed 826dd18. Also includes CategoriesTreeView @State→@Binding fix (partial #46 impl). |
| PE-026 | *(archived)* | Badge counts on all tabs (real-time, green/red tint), action button border rings, notebook update badges (GitHub #50, #51) | ✅ done (2026-04-04) — BadgeCountService + BadgeCountManager + ActionDot/actionRing on all approval/action pages |
| PE-031 | `PE-031-clock-fix-ios.md` | Clock In/Out bug fix — GPS permission race + alreadyClockedIn recovery (GitHub #20) 🚨 EMERGENCY | ⬜ **READY — trigger second (workers blocked)** |
| PE-027 | `PE-027-part-number-hierarchy.md` | Part numbers at color level, supplier part numbers per color × supplier, search by PN + abbrev (GitHub #46) | ⬜ **READY** |
| PE-028 | `PE-028-brands-suppliers-editing.md` | Brands page shows editable supplier list, Suppliers page shows editable brand list with carry status, brand_supplier_relationships table (GitHub #47) | ⬜ **READY** |
| PE-029 | `PE-029-pricing-ui.md` | Price chips on catalog color rows, PriceEditSheet with cascade (type→color→supplier), IOSPricingPage overview (GitHub #48) | ⬜ **READY** |
| PE-030 | `PE-030-warehouse-setup-redesign.md` | Remove forced setup gate, two independent flows (Parts + Floor Plan), drag-and-drop placement, cart mode, resumable (GitHub #49) | ⬜ **READY** |
| PE-032 | `PE-032-schedule-config-additive.md` | Add missing fields to Schedule Config: company hours, shift templates per hat, holiday calendar, dispatch rules, supervisor role (GitHub #29) | ⬜ **READY** |
| PE-033 | `PE-033-wishlist-section-layout.md` | Wishlist 3-section layout (User Added / Forecast / System), 14-day auto-approve, certainty badge, dismiss requires reason (GitHub #93) | ⬜ **READY** |
| PE-003 | *(write prompt)* | Flex pool self-assign — Q&A fully answered. Needs DB migration (is_flex_pool column) + SchedulingService methods before Xcode prompt | ⬜ Q&A done; awaiting DB migration before prompt |
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
