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

### #148 — IOSMovementWizard Save & Exit (Draft Persistence for Multi-Step Wizard)

**GitHub Issue:** `#148`
**Current State:** `IOSMovementWizard.swift` has only a "Cancel" button that discards all wizard state. A user starting a multi-step movement wizard who gets interrupted (phone call, app switch) loses all progress with no recovery path.
**Proposed Change:** Add a "Save & Exit" toolbar button that persists the current wizard draft and allows re-entry to resume. Draft can be stored in UserDefaults (simple, per-device) or a `movement_wizard_drafts` DB table (more robust, syncs across devices).
**Affected Modules:** Warehouse → Movement Wizard

#### Questions:

1. **As the Owner:** Is mid-wizard draft persistence important enough to do now, or can workers reasonably restart the wizard when interrupted? Movement wizards are short flows — is losing draft state a real pain point in daily use?
   > Answer: _pending_

2. **As a Manager:** If we add draft persistence, should it be **per device** (UserDefaults — wizard resumes only on the same phone) or **cross-device** (DB table — a manager starts a wizard on their phone, hands off to a worker who can resume on their device)?
   > Answer: _pending_

3. **As a Developer:** The wizard has 4 steps (select part → select source location → select destination → confirm). Draft state is 4–6 fields. Two approaches: **(A)** UserDefaults keyed by `"movementWizardDraft"` — simple, no schema change, per-device only, or **(B)** New `movement_wizard_drafts` table — syncs, multi-device resume, requires migration. Which fits current architecture better?
   > Answer: _pending_

4. **As a Developer:** Should "Save & Exit" preserve the draft **indefinitely** (shown on next wizard open as "Resume draft?") or for a **time window** (e.g., 24 hours, then auto-discard)? Indefinite drafts risk stale data if parts move while the draft sits.
   > Answer: _pending_

**Slots to fill:**
- [ ] Priority: do now vs. defer
- [ ] Persistence scope: per-device vs. cross-device
- [ ] Storage: UserDefaults vs. DB table
- [ ] Draft lifetime: indefinite vs. time-bounded

---

<!-- ARCHIVED CLUSTERS (answered 2026-04-14, see reference log) -->

<!-- ### Colors & Parts Redesign — Reusable Colors, Per-Color Part Numbers, General Brand Default

**GitHub Issues:** `#98` `#99` `#100` `#105` `#106` `#107`
**Current State:** Colors in the parts catalog are currently nested under specific (type, brand) combinations — a color defined under "PVC Conduit → Cantex" is a separate entity from the same color under "PVC Conduit → General". There is no shared color pool. Part numbers can only be set at the type level. The "General" brand is not auto-selected when creating a new type detail. New Brand and Supplier forms have no linked counterpart picker.
**Proposed Change:** Make colors reusable across brands and types (a shared color pool). Each (color + brand) combination becomes its own unique "part" (SKU). Color detail panels gain part number + price override fields. General brand auto-selected on new type detail. Brand removal requires confirmation. New Brand/Supplier forms gain a linked picker for the counterpart.
**Affected Modules:** Parts → Catalog, Pricing, Brands, Suppliers

#### Questions:

1. **As the Owner:** Right now a "color" only exists under a specific (type, brand) pair. You want colors to be reusable — e.g., "Gray" exists once and can be linked to multiple types and brands. Does this mean we need to **migrate existing colors** into a shared pool, or start fresh (keep old data as-is, new colors use the shared pool)?
   > Answer: _pending_

2. **As the Owner:** Issue #100 says "each color under General or a Brand should be a different part." Does this mean: when you add "Gray" under type "PVC Conduit" for both General and Cantex, you get **two distinct parts** (each with their own part number, price, stock)? Or is it one part with two supplier pricing tiers?
   > Answer: _pending_

3. **As a Manager:** When creating a new part type, should selecting "General" brand be the default? And if a worker tries to remove the General brand from a type that has no other brand, should the app block it or just warn them?
   > Answer: _pending_

4. **As a Developer:** Making colors reusable would require either: **(A)** a new `shared_colors` table + migration to move existing color records there (schema change, cleaner long-term), or **(B)** a simpler approach where colors remain per-type but can be "copied/linked" to other types on demand (no schema change, no data migration needed). Option A is architecturally cleaner but riskier for existing data. Which do you prefer?
   > Answer: _pending_

5. **As a Developer (for #105):** The "New Brand" and "New Supplier" forms currently save independently. Adding a linked picker means when you create a new brand you can immediately link a supplier (and vice versa). Should this be: **(A)** a simple optional picker that shows existing suppliers/brands (no inline creation), or **(B)** a full inline create-or-pick widget (create new supplier while creating a new brand in one flow)?
   > Answer: _pending_

6. **As a User (for #106):** On the Color detail panel, you want to be able to add a part number and override the type-level pricing. Should the color-level part number **replace** the type-level part number in searches, or **supplement** it (both are searchable, and the color-level wins for display)?
   > Answer: _pending_

**Slots to fill:**
- [ ] Migration strategy: move existing colors vs. new pool only vs. start fresh
- [ ] One part per (color + brand) vs. one part with multi-tier pricing
- [ ] General brand default behavior: block remove vs. warn only
- [ ] Schema approach: new shared table vs. copy-on-demand
- [ ] New Brand/Supplier form: simple counterpart picker vs. inline create-or-pick

---

### #143/#149 — Dismiss Safety & Keyboard Dismiss Systemic Audit (Settings, People, Chat, 30+ pages)

**GitHub Issues:** `#143` (also `#123`) + `#149`
**Current State:**
- **#143:** 30+ form sheets do NOT use `.interactiveDismissDisabled()` — users can swipe-down and lose all unsaved changes with no warning. 33 sheets now covered (partial); systemic remainder open.
- **#149:** ~30 scrollable pages with text fields do NOT use `.scrollDismissesKeyboard(.interactively)` — the keyboard stays locked up when users scroll away from a text field, blocking content below.
**Proposed Change:**
- **#143:** Add `.interactiveDismissDisabled(hasUnsavedChanges)` to all form sheets. A `hasUnsavedChanges` computed var compares current form state to initial state.
- **#149:** Add `.scrollDismissesKeyboard(.interactively)` to all `List` / `ScrollView` containers that contain text fields.
**Affected Modules:** Settings, People, Chat, Orders, Fleet, Scheduling (30+ sheets + 30+ pages)

#### Questions:

1. **As the Owner:** Cart Mode just shipped and program-review page rebuilds (#82–#95) are the next major phase. Is protecting users from accidental sheet dismiss (#143) and fixing keyboard lock (#149) a high priority **now**, or can this campaign wait until after the first page-rebuild wave?
   > Answer: _pending_

2. **As a Manager:** For #143, which module is the highest risk for data-loss on accidental dismiss? (Settings forms, People/HR forms, or Chat/messaging forms?) This determines which of the remaining sheets to fix first.
   > Answer: _pending_

3. **As a Developer:** Two approaches for #143: **(A)** `@State var isDirty: Bool` + `.onChange` tracking on each sheet individually (precise — only blocks when data was actually changed), or **(B)** `.interactiveDismissDisabled(true)` unconditionally on all form sheets (simpler, always blocks dismiss even on untouched forms). Owner preference?
   > Answer: _pending_

4. **As a Developer:** Should #143 be an Xcode prompt (UI-only surgery, Xcode AI does the 30+ edits) or should we write a hunt-fix automation script that scans `.sheet { }` and auto-patches the simple cases? At 30+ locations, a script would be faster.
   > Answer: _pending_

5. **As a Developer:** For #149 (keyboard dismiss): `.scrollDismissesKeyboard(.interactively)` is a straightforward one-liner on every `List`/`ScrollView` that contains a `TextField`. Should this be added in the same campaign as #143 (same Xcode prompt or script), or handled separately since it's lower risk? The fix is mechanical enough that it could be auto-scripted independently of #143.
   > Answer: _pending_

**Slots to fill:**
- [ ] Priority: do now vs. after first page-rebuild wave
- [ ] Module priority order (Settings vs. People vs. Chat) for #143
- [ ] Approach: per-sheet dirty tracking vs. unconditional block
- [ ] Method: Xcode prompt vs. automated scan-and-patch script
- [ ] #149 keyboard dismiss: same campaign as #143, or separate?

---

### April 2026 Audit — Architectural Decisions Needed

**GitHub Issues:** `#221` `#223` `#224` `#227`
**Context:** The April 2026 full program audit found 4 issues that require a design decision before a fix can be coded. These are not clear-cut bugs — each has meaningful trade-offs between approaches. All other audit issues (#179–#220, #222, #225–#226, #228) are clear bugs being fixed directly by the scanner agents.
**Affected Modules:** Sync (LWW strategy), Parts (pagination + forecasting logic)

#### Questions:

1. **As the Owner — #224 (Forecasting ADU inflation):** The forecasting Average Daily Usage (ADU) calculation currently counts **transfer movements** between locations as demand. This inflates ADU and triggers false reorder alerts. For example, if you move 50 PVC fittings from warehouse to the van, that shows up as "50 units of demand." Should we: **(A)** Exclude transfer movements from ADU (only count sales/installations/consumption), or **(B)** Keep transfers in ADU but show them as a separate line item so managers can see both numbers?
   > Answer: _pending_

2. **As the Owner — #221 (LWW sync conflict resolution):** When two devices edit the same record simultaneously, the system uses "Last Write Wins" — whichever device synced last wins the whole row. This means if Device A changes the part name and Device B changes the price at the same time, one change gets lost entirely. A more precise fix would track timestamps per-field (so name from Device A + price from Device B both survive). **(A)** Accept this known limitation for v1 (row-level LWW is simpler and fast), or **(B)** Upgrade to field-level conflict resolution (schema change: adds `_field_timestamps` JSON column, more complex but no data loss)?
   > Answer: _pending_

3. **As a Developer — #223/#227 (Pagination):** `BaseRepository.findAll()` has no row limit — calling it on large tables (parts catalog with thousands of parts) loads everything into memory. Two approaches: **(A)** Add `LIMIT 500` as a default with explicit override opt-out (quick fix, low risk), or **(B)** Full cursor-based pagination with `offset` parameter across all service methods that return lists (correct fix, more work, breaks some call sites). Which approach?
   > Answer: _pending_

**Slots to fill:**
- [ ] ADU calculation: exclude transfers vs. show separately
- [ ] LWW granularity: row-level (keep) vs. field-level (upgrade)
- [ ] Pagination: default-limit band-aid vs. full cursor pagination
-->

---

## Processed / Closed Q&A (Reference Log)

> These entries were fully answered, design decisions integrated into plan docs, and removed from Pending.

- **PricingOverrideFlow** (#133) — Processed 2026-04-12. Keep + retroactive plan at `docs/plans/ios-pricing-override-flow.md`. Accessible from Pricing page + CategoriesTreeView. Tests required before CategoriesTreeView wiring. GitHub #133 CLOSED.
- **Cart Mode** (#138) — Processed 2026-04-12. Build now. Per-bin movement records. Both wizard + standalone. Service (commit 71aa8bf) + UI (PE-042) complete. GitHub #138 CLOSED.
- **DIS-012/013 PIN KDF** (#130/#131) — Processed 2026-04-12. Defer to v2. PBKDF2 via CommonCrypto when ready. Legacy path removal timing TBD. Issues remain open as v2 backlog.
- **Colors & Parts Redesign** (#98, #99, #100, #105, #106, #107) — **Processed 2026-04-14**. REBUILD with concept reframe: "colors" is actually **Variants** (color-based OR named-only, e.g. standard/fire-rated/metal boxes). Each (color + brand) is a **distinct SKU** via new `color_brand_skus` table (matches how every parts retailer works). **"General" is a MODE** (brand deferred to supplier-pick time on PO/JPO) — NOT a brand row default. New Brand/Supplier forms use **simple counterpart picker** (no inline-create). Color-level `part_number` **replaces** type-level entirely. Design plan: `docs/plans/colors-parts-redesign.md`. GitHub issues remain OPEN pending implementation.
- **Dismiss Safety Campaign** (#143) — **Processed 2026-04-14**. **DO NOW**, before page-rebuild wave (sets the pattern for rebuilds to adopt). Module order: **People/HR → Chat → Settings** (by data-loss stakes). Approach: **per-sheet dirty tracking** (`@State var isDirty` + `.onChange` watchers + `.interactiveDismissDisabled(isDirty)`). Method: **Xcode AI prompts**, one per sheet, with mandatory 4-section header (Page Overview / Broken Behavior / Goal / Exact Change). Plan: `docs/plans/dismiss-safety-campaign.md`.
- **Keyboard Dismiss Campaign** (#149) — **Processed 2026-04-14**. **Separate, lower-priority campaign slotted after #143 completes**. One-liner pattern (`.scrollDismissesKeyboard(.interactively)`) but kept separate to keep #143 Xcode prompts laser-focused on data-loss. Plan: `docs/plans/dismiss-safety-campaign.md` (phase 2 section).
- **April 2026 Audit Closures** (#221, #223, #224, #227) — **Processed 2026-04-14**. **#224 ADU:** exclude transfer movements entirely (two-line SQL filter change in `PartsService.swift` ~line 3099). **#221 LWW:** upgrade to **per-field timestamps** — new `_field_timestamps` JSON column on every synced table, `ConflictResolver` updated to consult it. **#223/#227 Pagination:** phased — ship `LIMIT 500` default to `BaseRepository.findAll()` NOW with `unlimited: true` override, then full audit of call sites, then cursor pagination cutover in one clean pass. Plans: `docs/plans/april-2026-audit-closures.md`, `docs/plans/sync-field-timestamps-upgrade.md`, `docs/plans/pagination-cutover.md`.

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
