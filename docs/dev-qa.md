# WiredPart Q&A — Requirements & Design Questions

> **Purpose:** Before building any feature, questions are generated here for the owner to answer.
> Questions are organized by feature/change with role-based perspectives.
> **Auto-maintained by:** dev-pipeline-manager scheduled task

---

## How This Works

1. When a new plan is added or a GitHub issue is filed, questions appear here
2. Each question includes context about the current build and proposed changes
3. Questions are tagged by role perspective: Owner, Manager, Employee, Developer, User
4. Answer the questions by editing this file (write answers below each question)
5. Once answered, the dev-pipeline-manager integrates answers into the plan and **removes the question from this file**
6. Unanswered questions block the feature from being auto-built
7. **This file only contains unanswered/unprocessed questions.** Once processed, they're gone — design decisions live in `docs/plans/`.

---

## Pending Questions

_None. All clusters have been answered — see Answered Clusters below and Processed / Closed Q&A reference log at the bottom._

---

## Answered Clusters (awaiting pipeline-manager archival)

> These clusters received full answers; the `dev-pipeline-manager` agent can move them to the Processed / Closed log on its next run. Per-POV answers are preserved inline so the design rationale stays grep-able against each role.

### Automation Recommendations — Inventory Area (2026-04-27, rotation 2)

**Status:** ✅ ANSWERED 2026-04-27 via AskUserQuestion ratification + `approve all` confirmation. Source: `docs/automation-recommendations.md` → "Area: inventory — 2026-04-27 (rotation 2 — C13 close)". Format: APPROVE/DEFER/REJECT per item.

1. **SwiftUI render-perf scanner — `filter{}.count` inside `var body`** — Iter 7 of 2026-04-27 found 5 instances across 3 inventory iOS pages (PartsForecastingPage × 3, IOSInventoryGridPage × 1, IOSProcurementPage × 1), all bundled into [#328](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/328). Pattern is almost certainly systemic across the other 13 areas (jobs/people/orders/warehouse all have similar stat-card layouts). Fix is mechanical (`@State [Bucket: Int]` populated once on data change). Should AUTO GO build a Python-brace-depth scanner that walks each iOS page's `var body` block and flags `\.filter\s*\{[^}]*\}\.count`? Wire into C7b dispatch alongside the main-thread-grdb-scanner already approved 2026-04-25.
   > **Answer (2026-04-27):** **APPROVE — build now.** AUTO GO creates `~/.claude/scheduled-tasks/render-perf-scanner/SKILL.md`. Python brace-depth parser walks each iOS page's `var body`, flags `.filter{}.count` and similar O(N) ops (`.first(where:)`, `.contains(where:)` if cheap to add). Wires into C7b alongside main-thread-grdb-scanner. First project-wide run inventories all hits + files area-tagged GitHub issues. Closes #328 lineage.

2. **Free-form identity-string T1 scanner — service methods that accept `by actor: String`** — Iter 6 found 4 instances in WishlistService alone (filed [#327](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/327), T1 security; sister to Fleet's [#280](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/280)). The class: any service mutation method that writes to an audit field with the actor identity coming from a free-form `String` parameter and NO service-layer permission gate. UI-layer permission gates do not protect service callers; tests + future-coded callers can pass any name. Should AUTO GO build a scanner (greps `core/Sources/WiredPartCore/Services/*.swift` for `func \w+\(.*by \w+: String` and cross-references audit-field writes)? Wire into C8 (security review) dispatch.
   > **Answer (2026-04-27):** **APPROVE — build now.** AUTO GO creates `~/.claude/scheduled-tasks/identity-string-audit-scanner/SKILL.md`. Greps services for `func \w+\(.*by \w+: String` and cross-references audit-field writes (`created_by`, `updated_by`, `started_by`, `closed_by`, etc.). Flags any match that does NOT have a service-layer permission gate (e.g. `try AuthService.shared.requirePermission(...)`) before the audit-field write. Wires into C8 (security review). Sub-agent triages each hit (T1 severity). Closes #327 lineage + extends Fleet #280's pattern across all services.

3. **GRDB Int?/LEFT JOIN trap scanners (carried from inventory rotation 1, 2026-04-19)** — Two related defensive-coding canaries surfaced 2026-04-19 but never got Q&A: (a) the **GRDB-Nil-Default** scanner that flags `create*` methods inserting model structs with `Int?` boolean-flag fields whose Swift default is `nil` (writes NULL bypassing SQL `DEFAULT 1`); (b) the **LEFT JOIN NULL propagation** scanner that flags `WHERE joined_table.deleted_at IS NULL` after a `LEFT JOIN ... AND deleted_at IS NULL` (passes for join misses because `NULL IS NULL = TRUE`; the correct guard is `WHERE joined_table.id IS NOT NULL`). Both classes are silent bugs (no error, just wrong data). Should AUTO GO build them as one combined scanner with two checks?
   > **Answer (2026-04-27):** **APPROVE — combined scanner.** AUTO GO creates `~/.claude/scheduled-tasks/grdb-silent-bug-scanner/SKILL.md` with both checks in one skill (single AST infrastructure amortized over two checks). **Check A (GRDB-Nil-Default):** walks `create*` / `upsert*` methods, identifies inserted model structs, cross-references `Int?` boolean-flag fields with `nil` default, flags inserts that don't explicitly set the field (e.g. missing `record.isActive = 1`). **Check B (LEFT JOIN NULL propagation):** flags `WHERE joined_table.deleted_at IS NULL` after a `LEFT JOIN ... AND deleted_at IS NULL` because `NULL IS NULL = TRUE`; the correct guard is `WHERE joined_table.id IS NOT NULL`. Sits alongside `parts-sql-schema-checker` and the `is_active Defense Auditor` (approved 2026-04-25); all three are SQL/data-integrity scanners.

**Slots filled:**
- [x] Render-perf scanner: **APPROVE** — built next AUTO GO iteration with C7b wiring
- [x] Identity-string T1 scanner: **APPROVE** — built next AUTO GO iteration with C8 wiring
- [x] GRDB silent-bug scanner: **APPROVE** — combined scanner (both checks in one skill)

---

### Email-at-Rest Encryption — CodeQL `cleartext-storage-database` (2026-04-25)

**Status:** ✅ ANSWERED 2026-04-25 via AskUserQuestion ratification. Design plan: [`docs/plans/email-encryption-sqlcipher.md`](plans/email-encryption-sqlcipher.md).
**Source:** Iter 101 triage of CodeQL Code Scanning issues #292, #294, #296, #298, #303. All flag `email` columns stored plaintext in local SQLite (entity_contacts, general_contractors, users.email, company_setup_draft.email).
**Current State (pre-fix):** Emails are stored plaintext alongside other contact info. iOS Data Protection encrypts the SQLite file on-disk while the device is locked, but plaintext is readable to any process running as the app while unlocked.

1. **As an Owner:** This is a single-user, single-device local app heading to BETA. Beta testers will have their own devices. Is email encryption-at-rest worth shipping before beta, or accept iOS Data Protection as the security boundary?
   > **Answer (2026-04-25):** **Option A — SQLCipher whole-DB encryption.** Pre-beta posture: cheaper to migrate now than after beta testers have data. Whole-DB encryption protects ALL PII (11 email columns + names + wages + certs + customer/contractor contacts) in one stroke, not just email. ~1MB binary cost, 5–15% read/write overhead — acceptable. Key derived from SHA-256(user PIN + Keychain device salt). Salt stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Multipeer sync continues to work with per-device keys (sync messages travel as application-layer JSON over Multipeer's encrypted transport, decrypted in memory and re-encrypted into receiving device's DB).

**Slots filled:**
- [x] Encryption strategy: **whole-DB SQLCipher**, not per-field
- [x] Key management: **PIN + Keychain salt** with re-key on PIN change
- [x] Migration path: **`sqlcipher_export()` one-shot** with atomic rename + rollback
- [x] Sync compatibility: **per-device keys**, no shared key, sync protocol unchanged
- [x] CodeQL issues: design plan committed → status comment IN_PROGRESS on #292/#294/#296/#298/#303 → close once migration ships

---

### Orders Area C1b — Plan-vs-Code Drift (2026-04-19)

**Status:** ✅ ANSWERED 2026-04-25. Naming fix applied to `docs/plans/ios-procurement-page.md`.
**Source:** AUTO GO day 2 iter 29 (C1b). Drift check across 5 orders plan files (1,025 lines) vs 16 iOS orders files. Zero plan-ahead-of-code gaps; one tab-order drift fixed inline (Procurement before Purchase Orders in NavigationConfig).

1. **[Naming] IOSApprovalsPage vs IOSUnifiedApprovalsPage** — Both plans reference `IOSApprovalsPage` as the approvals page name. The actual file is `IOSUnifiedApprovalsPage.swift` located in `Features/Office/` rather than `Features/Orders/`. The router (`orders-approvals`) routes to it correctly. No functional issue.
   > **Answer (2026-04-25):** **UPDATE PLANS.** Plan files now reference `IOSUnifiedApprovalsPage (in Features/Office/)` for canonical name. Single heading edit on `ios-procurement-page.md` line 280 plus a naming-note callout. `ios-jpo-page.md` only mentions the user-visible "Approvals" tab name (not file name) — unchanged.

**Slots filled:**
- [x] Plan-file canonical name: **`IOSUnifiedApprovalsPage (in Features/Office/)`** with explicit naming note for future readers

---

### Automation Recommendations — Tools Area (2026-04-25, rotation 2)

**Status:** ✅ ANSWERED 2026-04-25 via AskUserQuestion ratification. Source: `docs/automation-recommendations.md` → Tools area rotation 2. Format: APPROVE/DEFER/REJECT per item.

1. **Main-thread GRDB read scanner** — should AUTO GO build a scanner that flags `try? Service.method()` calls inside `.task { }` modifiers (synchronous DB reads on the main actor → UI hitches)? 18+ occurrences across tools/parts/jobs/warehouse list pages.
   > **Answer (2026-04-25):** **APPROVE — build now.** Pre-beta UI smoothness matters. Scanner runs project-wide once + wired into C7b for ongoing protection. Closes #269. AUTO GO will create `~/.claude/scheduled-tasks/main-thread-grdb-scanner/SKILL.md`.

2. **`Formatters.formatSQLiteDatetime` helper** — should AUTO GO add a single static helper to replace 30+ duplicate `DateFormatter` instantiations parsing SQLite "yyyy-MM-dd HH:mm:ss"?
   > **Answer (2026-04-25):** **APPROVE — build now.** 30+ duplicates is a maintenance hazard. One helper in `core/Sources/WiredPartCore/Utilities/Formatters.swift` (extend if exists), then sub-agent migrates ~5 call sites per AUTO GO iteration. Closes #270.

3. **SQL perf-audit scanner** — should AUTO GO build a scanner that greps for `NOT EXISTS / EXISTS (SELECT` patterns inside service loops and cross-references `AppDatabase+Migrations.swift` for missing indexes?
   > **Answer (2026-04-25):** **APPROVE — build now.** Pre-beta is the right time. Tools (#273) is the confirmed first hit; warehouse/inventory/reports suspected. Wire into C9 (Performance) phase. AUTO GO will create `~/.claude/scheduled-tasks/sql-perf-audit/SKILL.md`.

---

### Automation Recommendations — Scheduling Area (2026-04-19)

**Status:** ✅ ANSWERED 2026-04-25. Source: `docs/automation-recommendations.md` → Scheduling area. Format: APPROVE/DEFER/REJECT.

1. **[Hook] is_active Defense Auditor** — Extend `parts-sql-check.sh` (or create `is-active-defense-check.sh`) to flag `WHERE id = ? AND deleted_at IS NULL` in `create*`/`update*` functions that don't also check `AND is_active = 1`. 4 violations in SchedulingService alone (all fixed). Per-SELECT granularity. ReportsService EXEMPT.
   > **Answer (2026-04-25):** **APPROVE — build now.** Defense-in-depth aligned with `feedback_deleted_at_defense_in_depth.md` memory note. AUTO GO will extend `.claude/hooks/parts-sql-check.sh` (or create sibling) with per-SELECT check that walks each SELECT statement individually inside functions with 3+ SELECTs. ReportsService skipped entirely (historical reports retain inactive entities by design).

---

### Automation Recommendations — Warehouse Area (2026-04-19)

**Status:** ✅ ANSWERED 2026-04-25 via AskUserQuestion ratification. Source: `docs/automation-recommendations.md` → Warehouse area. Format: APPROVE/DEFER/REJECT.

1. **[Scanner] Dismiss-Safety Struct-Aware Scanner** — Build a scanner that checks for `@State var isSaving` in each `struct ... : View` scope and verifies `.interactiveDismissDisabled(isSaving)` is present in the same scope. Current grep-based C7 check missed 3 dismiss-guard gaps in nested private structs.
   > **Answer (2026-04-25):** **APPROVE — build now.** Pairs with the smart-patcher script already approved 2026-04-18 for #143. AUTO GO will create `~/.claude/scheduled-tasks/dismiss-safety-scanner/SKILL.md` with Python brace-depth parser, add to C7 dispatch, run immediately against all 14 areas. Expected ~30 additional gaps.

2. **[Hook] WarehouseService SQL Column Validator** — Extend the existing `parts-sql-check.sh` hook to also trigger on edits to `WarehouseService.swift`. Same defense-in-depth posture as the parts hook.
   > **Answer (2026-04-25):** **APPROVE — extend existing hook.** Reuses already-built infrastructure (parts hook shipped 2026-04-18 iter 8). Add WarehouseService to the matcher and add warehouse-specific bad-column patterns verified against `AppDatabase+Migrations.swift`.

3. **[Scanner] Batch-Operation Transaction Auditor** — Find loops in iOS view files that call service `create*`/`update*`/`move*` methods without a GRDB transaction wrapper. Found in `IOSMovementWizard` (#259). Likely repeats in bulk actions, batch receives.
   > **Answer (2026-04-25):** **APPROVE — build now.** Performance + correctness pre-beta. AUTO GO will create `~/.claude/scheduled-tasks/batch-transaction-scanner/SKILL.md` using heuristic grep (for-loop + service call + no `db.write { }` block) with sub-agent triage. Wire into C9. Closes #259 lineage.

---

### Automation Recommendations — Jobs Area (2026-04-19)

**Status:** ✅ ANSWERED 2026-04-25 via AskUserQuestion ratification. Source: `docs/automation-recommendations.md` → Jobs area. Format: APPROVE/DEFER/REJECT.

1. **[Hook] Safe-GRDB-Partial-UPDATE Allowlist** — Teach the security-review scanner to recognize a comment marker (e.g. `// grdb-safe-partial-update: columns=[...]`) so it stops flagging the `setClauses.joined(",")` idiom as SQL concat when the column whitelist is visible nearby. Reduces false positives across 5+ services.
   > **Answer (2026-04-25):** **APPROVE — build now.** Permanent toil reduction across multiple services. AUTO GO will edit `~/.claude/scheduled-tasks/security-review/SKILL.md` to recognize the marker, then roll markers out to JobsService first; other services as touched. Low blast radius (changes scanner output only, not service code).

2. **[GitHub Action] Area-Label Auto-Tagger from Title Prefix** — Add a lightweight Action that reads `[Area]` prefix from new issue titles and applies matching labels; backfill existing open issues once. Unlocks `gh issue list --label` everywhere in AUTO GO, making C2b/C11 ~3× faster.
   > **Answer (2026-04-25):** **APPROVE — build now.** Compound savings across 12 remaining areas. AUTO GO will add `.github/workflows/auto-label.yml` + `execution/backfill_area_labels.py` and run the backfill once.

---

### Automation Recommendations — Parts Area (2026-04-18)

**Status:** ✅ ANSWERED 2026-04-18. Source: `docs/automation-recommendations.md`. Format uses APPROVE/DEFER/REJECT per item (not role-based — automation-tool recommendations don't need POV framing).

1. **[Hook] PartsService SQL Column Validator** — A PostToolUse hook on `PartsService.swift` edits that greps for known-bad column patterns (`first_name`, `hats.deleted_at`, etc.) and warns before the change lands. Priority: **high** (64+ historical SQL bugs). Tracked as open GitHub issue [#255](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/255).
   > **Answer (2026-04-18):** **APPROVE — build it now.** Matches beta-release posture: defense-in-depth against a category of bugs we've hit 64+ times. Low effort, high value. AUTO GO will build next iteration. Close #255 once the hook lands.
   > **✅ BUILT 2026-04-18 iter 8.** Hook at `.claude/hooks/parts-sql-check.sh` wired into `.claude/settings.local.json` as PostToolUse on Edit|Write. Tests 10 known-bad patterns, zero false positives after word-boundary fix. Issue #255 CLOSED.

2. **[Skill] parts-sql-schema-checker** — ✅ **ALREADY BUILT.** AUTO GO's first global github-issues-sync (2026-04-18 iteration 7) found that GitHub issue [#254](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/254) is CLOSED and the skill is present in the skill list.
   > **Answer:** RESOLVED — already implemented (skill exists, #254 closed). Will wire into hunt-fix Scanner 4 on next iteration running C3.

3. **[Skill] parts-xcode-phase2-generator** — A skill that reads `colors-parts-redesign.md` and outputs Xcode AI prompts for the 7 pending Phase 2 files automatically. Priority: **low** — duplicates existing `xcode-planner-and-review` capability.
   > **Answer (2026-04-18):** **REJECT — remove from list.** Matches the recommendation's own suggestion. Use existing `xcode-planner-and-review` skill which already handles this. No need for a parts-specific duplicate.

4. **[Subagent] parts-drift-detector** — An Agent-tool subagent that reads parts plans and outputs "planned-but-not-coded" and "coded-but-not-planned" items with file:line citations, to speed up C1b plan-vs-code drift checks from ~10 min to ~2 min. Priority: **medium**. Best timing: after PE-COLORS Phase 2 begins so the drift surface is active. Tracked as open GitHub issue [#256](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/256).
   > **Answer (2026-04-18):** **DEFER — build when PE-COLORS Phase 2 begins.** Matches the recommendation's own timing guidance. Drift detection is only valuable once there's actively-drifting code to detect. Leave #256 open; revisit when Phase 2 code starts landing.
   > **✅ BUILT 2026-07-03.** Project-scoped agent added at `.claude/agents/parts-drift-detector.md`. Static guard added at `tests/static/test_parts_drift_detector_agent.py` to require the four Parts plan inputs, Parts UI/service/model/schema targets, structured drift output sections, and file:line citation rules. Closes #256.

---

### Colors & Parts Redesign — Reusable Variants, Per-SKU Brand Linkage, General Mode

**Status:** ✅ ANSWERED 2026-04-14 (narrative), RE-RATIFIED 2026-04-18 (per-POV via AskUserQuestion). Design plan: [`docs/plans/colors-parts-redesign.md`](plans/colors-parts-redesign.md).
**GitHub Issues:** `#98` `#99` `#100` `#105` `#106` `#107`
**Current State (pre-redesign):** Colors in the catalog are currently presented as nested under specific (type, brand) combinations in the UI, even though `part_colors` is already a standalone table. There is no shared-color-pool UI surfacing. Part numbers can only be set at the type level. The "General" brand is not auto-selected when creating a new type detail. New Brand and Supplier forms have no linked counterpart picker.
**Proposed Change:** Rebuild as a "Variants" concept — reusable pool of variant rows (color-based AND named-only AND several additional kinds). Each (variant + brand + type) becomes a distinct SKU via a new `color_brand_skus` table. "General" becomes a MODE on order line items. New Brand/Supplier forms gain simple counterpart pickers.
**Affected Modules:** Parts → Catalog (`PartsCategoriesPage`, `CategoriesColorPicker`, `CategoriesEditorPanel`, `TypeBrandColorSection`), Brands, Suppliers, JPO/PO creation flows.

#### Questions:

1. **As the Owner:** Right now a "color" only exists under a specific (type, brand) pair. You want colors to be reusable — e.g., "Gray" exists once and can be linked to multiple types and brands. Does this mean we need to **migrate existing colors** into a shared pool, or start fresh (keep old data as-is, new colors use the shared pool)?
   > **Answer (2026-04-18, per-POV):** REBUILD the concept as **"Variants"** — a broader pool than just colors. Support multiple variant kinds on every row: (a) color-based (hex + name), (b) named-only (text), (c) named + optional color tag (visual UI chip, not physical color), (d) size/dimension variants, (e) rating/spec variants, (f) material variants. PLUS a "suitable substitute" relationship (many-to-many cross-reference table) so one part can flag another as interchangeable. No data migration needed — `part_colors` is already a standalone table; the expansion is additive columns + new `variant_substitutes` relation table.

2. **As the Owner:** Issue #100 says "each color under General or a Brand should be a different part." Does this mean: when you add "Gray" under type "PVC Conduit" for both General and Cantex, you get **two distinct parts** (each with their own part number, price, stock)? Or is it one part with two supplier pricing tiers?
   > **Answer (2026-04-18, per-POV):** **Option A — Distinct SKU per (color + brand).** A red Leviton outlet and a blue Leviton outlet are different parts; a red Leviton and a red Bosch are different parts. Each combo gets its own `part_number`, `unit_cost`, `stock_qty` via new `color_brand_skus` table with `UNIQUE(color_id, brand_id, type_id)`. Matches how every real parts retailer structures their catalog.

3. **As a Manager:** When creating a new part type, should selecting "General" brand be the default? And if a worker tries to remove the General brand from a type that has no other brand, should the app block it or just warn them?
   > **Answer (2026-04-18, per-POV):** **"General" is a MODE, not a brand-row default.** "General" on a PO/JPO line item means "no brand locked — resolve brand at supplier-pick time based on which brand the chosen supplier carries." Schema: add `brand_selection_mode: 'specific' | 'general'` column to `jpo_line_items` and `po_line_items`. No auto-select on new type creation. When a worker removes the last brand from a type, show a **warning toast but allow it** (not a hard block).

4. **As a Developer:** Making colors reusable would require either: **(A)** a new `shared_colors` table + migration to move existing color records there (schema change, cleaner long-term), or **(B)** a simpler approach where colors remain per-type but can be "copied/linked" to other types on demand (no schema change, no data migration needed). Option A is architecturally cleaner but riskier for existing data. Which do you prefer?
   > **Answer (2026-04-18, per-POV):** **Additive schema only, no data migration.** Driven by Q2=A: new `color_brand_skus` join table. Driven by Q3=Mode: new `brand_selection_mode` column on `jpo_line_items` and `po_line_items`. Driven by Q1=Variants expansion: additive columns on `part_colors` for size/rating/material + new `variant_substitutes` relation table. `part_colors` remains standalone (it already is). Drop legacy `part_number` column from `parts_types` / `parts_brands` if still present.

5. **As a Developer (for #105):** The "New Brand" and "New Supplier" forms currently save independently. Adding a linked picker means when you create a new brand you can immediately link a supplier (and vice versa). Should this be: **(A)** a simple optional picker that shows existing suppliers/brands (no inline creation), or **(B)** a full inline create-or-pick widget (create new supplier while creating a new brand in one flow)?
   > **Answer (2026-04-18, per-POV):** **Option A — Simple picker of existing counterparts, no inline-create.** New-Brand form shows existing suppliers. New-Supplier form shows existing brands. If the counterpart doesn't exist yet, user navigates to the other page, creates it, comes back and picks. Uses existing `BrandSupplierPickerSheet`. Keeps new-record sheets uncluttered.

6. **As a User (for #106):** On the Color detail panel, you want to be able to add a part number and override the type-level pricing. Should the color-level part number **replace** the type-level part number in searches, or **supplement** it (both are searchable, and the color-level wins for display)?
   > **Answer (2026-04-18, per-POV, FLIPPED from 2026-04-14 "A"):** **Option B — Supplement (both searchable, color-level wins for display).** Keep type-level `part_number` as an optional fallback / group-default. If a color has its own `part_number`, that wins for display. If it doesn't, the type-level acts as fallback default. Search queries BOTH columns (UNION) so users find parts whether they search the type-level SKU or the color-level SKU. (Changed from the earlier "Replace" intent to preserve type-level as a group default for legacy and partial-configuration scenarios.)

**Slots filled:**
- [x] Migration strategy: **no migration** (table already standalone); expand Variants concept additively
- [x] One part per (color + brand) vs. one part with multi-tier pricing: **distinct SKU per (color + brand)**
- [x] General brand default behavior: **"General" is a Mode on line items**; warn-only on last-brand remove
- [x] Schema approach: **additive only** (new `color_brand_skus`, new `brand_selection_mode` columns, new `variant_substitutes` table, additive Variant-attribute columns)
- [x] New Brand/Supplier form: **simple counterpart picker**, no inline-create
- [x] Color-level part_number: **Supplement** (both searchable, color wins for display)

---

### #143/#149 — Dismiss Safety & Keyboard Dismiss Systemic Audit (Settings, People, Chat, 30+ pages)

**Status:** ✅ ANSWERED 2026-04-14 (narrative), RE-RATIFIED 2026-04-18 (per-POV via AskUserQuestion). Design plan: [`docs/plans/dismiss-safety-campaign.md`](plans/dismiss-safety-campaign.md).
**GitHub Issues:** `#143` (also `#123`) + `#149`
**Current State:**
- **#143:** 30+ form sheets do NOT use `.interactiveDismissDisabled()` — users can swipe-down and lose all unsaved changes with no warning. PE-044 (IOSEmployeesPage AddEmployeeSheet) shipped via direct edit 2026-04-15 as canonical pattern.
- **#149:** ~30 scrollable pages with text fields do NOT use `.scrollDismissesKeyboard(.interactively)` — the keyboard stays locked up when users scroll away from a text field, blocking content below.
**Proposed Change:**
- **#143:** Add per-sheet `@State var isDirty` + `.onChange` watchers + `.interactiveDismissDisabled(isDirty)` + Discard alert. PE-044 ships as pilot; smart-patcher automation script sweeps the rest once PE-044 is validated.
- **#149:** Separate Phase 2 campaign after #143 completes. Add `.scrollDismissesKeyboard(.interactively)` to all `List` / `ScrollView` containers that contain text fields.
**Affected Modules:** Settings, People, Chat, Orders, Fleet, Scheduling (30+ sheets + 30+ pages).

#### Questions:

1. **As the Owner:** Cart Mode just shipped and program-review page rebuilds (#82–#95) are the next major phase. Is protecting users from accidental sheet dismiss (#143) and fixing keyboard lock (#149) a high priority **now**, or can this campaign wait until after the first page-rebuild wave?
   > **Answer (2026-04-18, per-POV):** **DO NOW, but pilot first.** The program is in the **development stage preparing for BETA release** — pattern quality matters because it's public-bound. Approach: PE-044 (IOSEmployeesPage, already shipped via direct edit 2026-04-15) is the pilot. Let it get real-use validation during beta prep, THEN scale. Don't write 30 prompts upfront. Campaign slots BEFORE page-rebuild wave so rebuilds inherit the validated pattern.

2. **As a Manager:** For #143, which module is the highest risk for data-loss on accidental dismiss? (Settings forms, People/HR forms, or Chat/messaging forms?) This determines which of the remaining sheets to fix first.
   > **Answer (2026-04-18, per-POV):** **People/HR → Chat → Settings (in that order).** People/HR first: cert forms, wage edits, new-employee forms are long and high-value. Chat second: composer loss mid-typing is acutely painful but shorter content. Settings last: rarely-entered config forms, lowest frequency = lowest total risk. Phase labels: 1A People/HR, 1B Chat, 1C Orders/Fleet/Scheduling, 1D Parts/Tools/Settings.

3. **As a Developer:** Two approaches for #143: **(A)** `@State var isDirty: Bool` + `.onChange` tracking on each sheet individually (precise — only blocks when data was actually changed), or **(B)** `.interactiveDismissDisabled(true)` unconditionally on all form sheets (simpler, always blocks dismiss even on untouched forms). Owner preference?
   > **Answer (2026-04-18, per-POV):** **Option A — Per-sheet dirty tracking.** `@State private var isDirty: Bool` + `.onChange(of: field) { _, _ in isDirty = true }` on every bound input + `.interactiveDismissDisabled(isDirty)` on sheet root + Discard alert on Cancel. Untouched sheets dismiss cleanly; touched sheets get the alert. Pattern proven in PE-044 (IOSEmployeesPage AddEmployeeSheet, shipped 2026-04-15).

4. **As a Developer:** Should #143 be an Xcode prompt (UI-only surgery, Xcode AI does the 30+ edits) or should we write a hunt-fix automation script that scans `.sheet { }` and auto-patches the simple cases? At 30+ locations, a script would be faster.
   > **Answer (2026-04-18, per-POV, FLIPPED from 2026-04-14 "A: Xcode prompts"):** **Smart-patcher automation script.** Python/Swift script in `execution/` per 3-layer architecture. Script reads each sheet file, detects bound inputs (TextField / Picker / Toggle / DatePicker / Stepper / Slider), injects `@State private var isDirty`, adds `.onChange(of: $binding) { _, _ in isDirty = true }` per detected binding, wires `.interactiveDismissDisabled(isDirty)` on sheet root + Discard-changes alert. Emits per-file review report. Human spot-checks before commit. PE-044 becomes the **reference output** — the script produces files shaped like PE-044. Runs only after PE-044 pilot validates the pattern.

5. **As a Developer:** For #149 (keyboard dismiss): `.scrollDismissesKeyboard(.interactively)` is a straightforward one-liner on every `List`/`ScrollView` that contains a `TextField`. Should this be added in the same campaign as #143 (same Xcode prompt or script), or handled separately since it's lower risk? The fix is mechanical enough that it could be auto-scripted independently of #143.
   > **Answer (2026-04-18, per-POV):** **Option B — Separate Phase 2 campaign**, lower priority, slots AFTER #143 completes. #143 is data-loss (critical pre-beta); #149 is UX annoyance. Kept separate to keep the #143 smart-patcher script laser-focused on dirty-tracking. #149 can be a rapid mechanical sweep (likely its own smaller script) once #143 lands.

**Slots filled:**
- [x] Priority: **do now, but pilot PE-044 first, then scale** (pre-release / pre-beta context)
- [x] Module priority order: **People/HR → Chat → Orders/Fleet/Scheduling → Parts/Tools/Settings**
- [x] Approach: **per-sheet dirty tracking** (shipped in PE-044)
- [x] Method: **smart-patcher automation script** (not Xcode prompts); PE-044 is the reference output
- [x] #149 keyboard dismiss: **separate Phase 2 campaign** after #143 completes

---

### April 2026 Audit — Architectural Decisions Needed

**Status:** ✅ ANSWERED 2026-04-14 (narrative), RE-RATIFIED 2026-04-18 (per-POV via AskUserQuestion). Design plans: [`docs/plans/april-2026-audit-closures.md`](plans/april-2026-audit-closures.md), [`docs/plans/sync-field-timestamps-upgrade.md`](plans/sync-field-timestamps-upgrade.md), [`docs/plans/pagination-cutover.md`](plans/pagination-cutover.md).
**GitHub Issues:** `#221` `#223` `#224` `#227`
**Context:** The April 2026 full program audit found 4 issues that require a design decision before a fix can be coded. These are not clear-cut bugs — each has meaningful trade-offs between approaches.
**Affected Modules:** Sync (LWW strategy), Parts (pagination + forecasting logic).

#### Questions:

1. **As the Owner — #224 (Forecasting ADU inflation):** The forecasting Average Daily Usage (ADU) calculation currently counts **transfer movements** between locations as demand. This inflates ADU and triggers false reorder alerts. Should we: **(A)** Exclude transfer movements from ADU (only count sales/installations/consumption), or **(B)** Keep transfers in ADU but show them as a separate line item so managers can see both numbers?
   > **Answer (2026-04-18, per-POV):** **Option A — Exclude transfer movements from ADU entirely.** Only `consume` and `return_to_supplier` count as real demand. Transfers are location moves, not consumption. **Already shipped** in commit `fb11761` (2026-04-14): `transfer` removed from all 6 ADU/APW movement_type filters in `PartsService.swift` (global 30d, global 90d, per-location 30d, per-location 90d, plus 2 APW queries). Issue #224 CLOSED correctly.

2. **As the Owner — #221 (LWW sync conflict resolution):** When two devices edit the same record simultaneously, the system uses "Last Write Wins" — whichever device synced last wins the whole row. **(A)** Accept this known limitation for v1, or **(B)** Upgrade to field-level conflict resolution (schema change: adds `_field_timestamps` JSON column, more complex but no data loss)?
   > **Answer (2026-04-18, per-POV):** **Option B — Upgrade to per-field timestamps.** Ground-truth correction: `ConflictResolver.swift` line 79 is ALREADY field-level merge — the limitation is that the tiebreaker uses the row's `updated_at`. Upgrade: add `_field_timestamps TEXT` JSON column to every synced table (~35 tables), every service write stamps the touched field's timestamp via a new `FieldTimestampHelper.stamp()`, `ConflictResolver.mergeField()` consults per-field timestamp with row `updated_at` fallback for pre-migration rows. Pre-beta is the right time for this migration (cheaper now than post-beta). Plan: `docs/plans/sync-field-timestamps-upgrade.md`. Issue #221 reopened 2026-04-16 by `issue-closure-verifier` Check A — remains OPEN until Phase 2 migration lands.

3. **As a Developer — #223/#227 (Pagination):** `BaseRepository.findAll()` has no row limit. **(A)** Add `LIMIT 500` as a default with explicit override opt-out (quick fix), or **(B)** Full cursor-based pagination across all service methods (correct fix, more work)?
   > **Answer (2026-04-18, per-POV):** **Option C — Phased with B-bias.** **Phase 1 (shipped in commit `fb11761` 2026-04-14):** `BaseRepository.findAll()` default changed from `limit: Int? = nil` to `limit: Int? = 1000` with `limit: nil` as explicit opt-in for truly unbounded. Note: 1000, not the 500 originally proposed. Issue #223 CLOSED correctly. **Phase 2 (in progress):** Call-site audit produces `docs/pagination-audit.md` classifying every `findAll()` caller. **Phase 3 (after audit):** One-clean-pass keyset-cursor pagination for call sites marked in Phase 2. Closes #227 fully. Plan: `docs/plans/pagination-cutover.md`.

**Slots filled:**
- [x] ADU calculation: **exclude transfers entirely** (shipped `fb11761`)
- [x] LWW granularity: **upgrade to per-field timestamps** (#221 reopened, plan active)
- [x] Pagination: **phased — Phase 1 shipped, Phase 2 audit in progress, Phase 3 cursor cutover after audit**


---

## Processed / Closed Q&A (Reference Log)

> These entries were fully answered, design decisions integrated into plan docs, and removed from Pending. Some have since been refined — check the **Answered Clusters** section above for the latest per-POV specifics.

- **PricingOverrideFlow** (#133) — Processed 2026-04-12. Keep + retroactive plan at `docs/plans/ios-pricing-override-flow.md`. Accessible from Pricing page + CategoriesTreeView. Tests required before CategoriesTreeView wiring. GitHub #133 CLOSED.
- **Cart Mode** (#138) — Processed 2026-04-12. Build now. Per-bin movement records. Both wizard + standalone. Service (commit 71aa8bf) + UI (PE-042) complete. GitHub #138 CLOSED.
- **DIS-012/013 PIN KDF** (#130/#131) — Processed 2026-04-12. Defer to v2. PBKDF2 via CommonCrypto when ready. Legacy path removal timing TBD. Issues remain open as v2 backlog.
- **Colors & Parts Redesign** (#98, #99, #100, #105, #106, #107) — **Processed 2026-04-14, REFINED 2026-04-18.** REBUILD as **Variants** concept — 2026-04-18 ratification expanded variant kinds to 6 (color-based, named-only, named+color-tag, size, rating, material) PLUS a `variant_substitutes` many-to-many relation table. Each (color + brand) is a **distinct SKU** via new `color_brand_skus` table. **"General" is a MODE** on line items (brand deferred to supplier-pick time) — NOT a brand row default. New Brand/Supplier forms use **simple counterpart picker** (no inline-create). **Color-level `part_number` SUPPLEMENTS** type-level (both searchable, color wins for display) — flipped from 2026-04-14 "Replace" per 2026-04-18 per-POV ratification. Design plan: `docs/plans/colors-parts-redesign.md`.
- **Dismiss Safety Campaign** (#143) — **Processed 2026-04-14, REFINED 2026-04-18.** **DO NOW but pilot first** — PE-044 (IOSEmployeesPage AddEmployeeSheet, shipped 2026-04-15 via direct edit) is the pilot; validation during beta prep before scaling. Module order: **People/HR → Chat → Orders/Fleet/Scheduling → Parts/Tools/Settings**. Approach: **per-sheet dirty tracking**. **Method flipped 2026-04-18 to smart-patcher automation script** (was "Xcode AI prompts" on 2026-04-14) — Python/Swift script in `execution/` per 3-layer architecture; detects bound inputs, injects pattern, emits per-file review report; PE-044 is the reference output shape. Plan: `docs/plans/dismiss-safety-campaign.md`.
- **Keyboard Dismiss Campaign** (#149) — **Processed 2026-04-14**. **Separate, lower-priority campaign slotted after #143 completes**. One-liner pattern (`.scrollDismissesKeyboard(.interactively)`) but kept separate to keep #143 Xcode prompts laser-focused on data-loss. Plan: `docs/plans/dismiss-safety-campaign.md` (phase 2 section).
- **April 2026 Audit Closures** (#221, #223, #224, #227) — **Processed 2026-04-14**. **#224 ADU:** exclude transfer movements entirely (two-line SQL filter change in `PartsService.swift` ~line 3099). **#221 LWW:** upgrade to **per-field timestamps** — new `_field_timestamps` JSON column on every synced table, `ConflictResolver` updated to consult it. **#223/#227 Pagination:** phased — ship `LIMIT 500` default to `BaseRepository.findAll()` NOW with `unlimited: true` override, then full audit of call sites, then cursor pagination cutover in one clean pass. Plans: `docs/plans/april-2026-audit-closures.md`, `docs/plans/sync-field-timestamps-upgrade.md`, `docs/plans/pagination-cutover.md`.
- **IOSMovementWizard Save & Exit** (#148) — **Processed 2026-04-17 (retroactive ratification).** Code already shipped in `IOSMovementWizard.swift`: Save & Exit toolbar button (line 121–130), `saveDraft()` → UserDefaults JSON (line 1010–1026), `restoreDraft()` via `.task` on wizard open with "Draft restored — pick up where you left off" banner (line 1028–1041), `clearDraft()` called after successful execute (line 986). Retroactive design answers: Q1 **Do now** (shipped); Q2 **Per-device** (UserDefaults, single phone); Q3 **Option A: UserDefaults** keyed `"movementWizardDraft"` (no DB table, no migration); Q4 **Indefinite** (no time-bounded auto-discard — draft persists until either successfully executed or explicitly overwritten by another Save & Exit). Mirrors the PE-041 receiving-draft-persistence pattern for consistency. Issue #148 CLOSED 2026-04-16, reopened 2026-04-16 by `issue-closure-verifier` (Check A — Q&A still Pending), now re-closeable with this log entry in place.
- **Email-at-Rest Encryption** (CodeQL #292, #294, #296, #298, #303) — **Processed 2026-04-25**. **Option A: SQLCipher whole-DB encryption.** Adds SQLCipher Swift package, refactors AppDatabase init with cipher PRAGMA, derives key from SHA-256(PIN + Keychain salt). One-time `sqlcipher_export()` migration on first launch with the new build. Multipeer sync unchanged (per-device keys, app-layer JSON over encrypted transport). Plan: [`docs/plans/email-encryption-sqlcipher.md`](plans/email-encryption-sqlcipher.md). CodeQL issues remain OPEN with IN_PROGRESS comments — close when migration ships.

- **SQLCipher Migration Approach** (PR [#320](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/320)) — **Processed 2026-04-29**. Follow-up to the 2026-04-25 whole-DB-SQLCipher decision: *how* should existing unencrypted DBs upgrade on first launch with the new build? **Option B: new-encrypted-DB-with-import.** Do NOT rekey in place. Instead: (1) detect unencrypted DB at canonical path, (2) create fresh encrypted DB at temp path with `PRAGMA key`, (3) `ATTACH` old DB read-only, (4) run schema migrator on new encrypted DB, (5) `INSERT INTO main.<table> SELECT * FROM old.<table>` per table in FK-parent-first order, (6) verify per-table row counts match, (7) detach old, (8) atomic rename: `app.db` → `app.db.unencrypted.bak`, `tmp` → `app.db`, (9) idempotent — skip if already encrypted on subsequent launches, (10) keep `.bak` 7 days OR until first successful Multipeer sync confirms health. **Why B over A (in-place rekey):** atomic, verifiable, testable, preserves user data if migration fails partway. Aligns with the multi-step DB write atomicity rule from notebooks `applyJobTemplate` learning. Decision reflected as [comment on PR #320](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/320#issuecomment-4346100078) with full algorithm spec + 5 required test cases (`MigrationCipherTests.test*`). Copilot re-assigned 2026-04-29T17:36Z to refactor the existing PR #320 work toward this approach. CodeQL alerts remain OPEN until #320 lands.
- **Orders Area Naming Drift** (C1b 2026-04-19) — **Processed 2026-04-25**. **UPDATE PLANS.** `docs/plans/ios-procurement-page.md` line 280 heading updated `IOSApprovalsPage` → `IOSUnifiedApprovalsPage (in Features/Office/)` with naming-note callout. `ios-jpo-page.md` unchanged (only mentions user-visible "Approvals" tab name).
- **Tools Area Automation Recs** (2026-04-25 rotation 2) — **Processed 2026-04-25**. All 3 APPROVED: (1) main-thread GRDB scanner (#269) wired into C7b; (2) `Formatters.formatSQLiteDatetime` helper (#270) consolidating 30+ DateFormatter duplicates; (3) SQL perf-audit scanner wired into C9 covering `NOT EXISTS`/`EXISTS` loop anti-patterns + missing indexes (#273 confirmed first hit). AUTO GO will build sequentially.
- **Scheduling Area Automation Rec** (2026-04-19) — **Processed 2026-04-25**. **APPROVED:** is_active Defense Auditor hook. Extends `.claude/hooks/parts-sql-check.sh` with per-SELECT granularity check (functions with 3+ SELECTs assert each independently). ReportsService EXEMPT. Defense-in-depth aligned with `feedback_deleted_at_defense_in_depth.md`.
- **Warehouse Area Automation Recs** (2026-04-19) — **Processed 2026-04-25**. All 3 APPROVED: (1) Dismiss-Safety Struct-Aware Scanner (Python brace-depth parser, pairs with 2026-04-18 smart-patcher script for #143, runs against all 14 areas); (2) WarehouseService SQL Validator (extends existing parts hook); (3) Batch-Operation Transaction Auditor (heuristic grep for unwrapped service-call loops, closes #259 lineage).
- **Jobs Area Automation Recs** (2026-04-19) — **Processed 2026-04-25**. Both APPROVED: (1) Safe-GRDB-Partial-UPDATE Allowlist marker recognized by security-review scanner (reduces false positives across 5+ services); (2) Area-Label Auto-Tagger GitHub Action `auto-label.yml` + one-time backfill `execution/backfill_area_labels.py` (unlocks `gh issue list --label <area>` portfolio-wide, ~3× faster C2b/C11).
- **Inventory Area Automation Recs** (2026-04-27 rotation 2) — **Processed 2026-04-27**. All 3 APPROVED: (1) **SwiftUI render-perf scanner** — Python brace-depth parser flagging `.filter{}.count` (and similar O(N) ops) inside `var body`, wires into C7b alongside main-thread-grdb-scanner; closes #328 lineage. (2) **Free-form identity-string T1 scanner** — flags service methods accepting `by actor: String` writing audit fields without service-layer permission gates; wires into C8; closes #327 lineage + extends Fleet #280. (3) **Combined GRDB silent-bug scanner** — two checks (GRDB-Nil-Default for `Int?` model fields + LEFT JOIN NULL propagation traps); single skill, single AST infrastructure. AUTO GO builds sequentially in subsequent iterations.

---

## Question Template

When generating questions, use this format:

```
### [Feature Name] — [Brief Description]
**Plan:** `docs/plans/[file].md`
**Current State:** [What exists now]
**Proposed Change:** [What would change]

#### Questions:

1. **As an Owner:** [Business/ROI question]
   > Answer: _pending_

2. **As a Manager:** [Workflow/oversight question]
   > Answer: _pending_

3. **As an Employee:** [Daily usage question]
   > Answer: _pending_

4. **As a Developer:** [Technical/integration question]
   > Answer: _pending_

5. **As a User:** [UX/experience question]
   > Answer: _pending_
```
