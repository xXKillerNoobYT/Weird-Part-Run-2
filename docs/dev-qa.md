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

---

### PricingOverrideFlow — Retroactive Plan for Unplanned 616-Line Feature

**GitHub Issue:** `#133`
**Current State:** `PricingOverrideFlow.swift` (616 lines) exists and is wired into `PartsPricingPage.swift:592` as `PricingTierSetSheet`. It implements a 6-state multi-step sheet (selectLevel → selectEntity → setPrice → preview → resolveConflicts → done) that lets an admin set a price at any hierarchy level (Category / Sub-category / Part Type / Brand / Color) with conflict resolution. This file was **never in any plan** and was not requested — it appeared as an unplanned addition alongside PE-029 (CascadePriceEditSheet).
**Proposed Change:** Three options: **(A)** Write a retroactive plan for it (officially adopt it as a known feature), **(B)** Remove it (it's unused until wired into the UI more broadly), or **(C)** Keep it as a zero-plan file (carry technical debt, no owner intent documented).
**Affected Modules:** Parts → Pricing

#### Questions:

1. **As the Owner:** Do you want to keep `PricingOverrideFlow.swift` (hierarchy-level bulk price setter) as a real feature? It lets you set a price at category or brand level and push it down to all items below — a "price sweep" capability. Is that something you need, or was this added speculatively?
   > Answer: **Keep it.** Write a retroactive plan — officially adopt as a known feature.

2. **As the Owner:** If keeping it — should the plan be extended to describe when and where this is accessible? (E.g., only admins on the Pricing page, or also in the category tree editor?) Or do you want it removed until a proper design is done?
   > Answer: **Pricing page + category tree editor.** Accessible from both locations.

3. **As a Developer:** `PricingTierSetSheet` is wired in but the conflict resolution step (`resolveConflicts` state) has no tests. If we're keeping this, should coverage be added before it's used more broadly?
   > Answer: **Yes — tests required before broader use.** Block further wiring until resolveConflicts has test coverage.

**Slots to fill:**
- [x] Keep, remove, or defer? → **Keep — retroactive plan**
- [x] If keep: scope (where accessible, who can use it) → **Pricing page + category tree editor**
- [x] If keep: test coverage requirement → **Yes, tests before broader use**

---

### Cart Mode — WarehouseService Missing Service Methods (PE-030 follow-on)

**GitHub Issue:** `#138`
**Current State:** `docs/plans/ios-warehouse-setup-redesign.md` describes a "Moving Cart Mode" where a worker loads multiple bins into a virtual cart and then specifies a single destination for all of them. The plan calls for two WarehouseService methods: `saveUnitPlacement(unitId:row:col:zoneId:)` and `moveBinsToArea(binIds:[Int64], targetAreaId:Int64)`. **Neither method exists in WarehouseService.swift.** The drag-and-drop floor plan (PE-040 ✅) is done, but Cart Mode is a separate unimplemented flow.
**Proposed Change:** Build the two missing service methods + the Cart mode UI flow (tap to add bins to cart → Place Cart → specify destination → bulk move all).
**Affected Modules:** Warehouse → Setup + Movements

#### Questions:

1. **As the Owner:** Is Cart Mode a priority right now? It's designed for moving many bins at once during initial warehouse setup (e.g., "I just received 20 boxes, assign them all to Zone A"). Is that a workflow you actively need, or can it wait?
   > Answer: **Build now.** This is a priority.

2. **As a Manager:** In day-to-day use, how often would workers need to move multiple bins to the same destination vs. moving them one at a time? This helps decide whether Cart Mode is worth the implementation effort now.
   > Answer: **Frequent enough to justify.** Build it now — bulk moves are common during setup and receiving.

3. **As a Developer:** `moveBinsToArea` would need to create individual `stock_movements` records for each bin, or a batch movement record. Given the current movements schema, do you want: **(A)** one movement record per bin (auditable but verbose), or **(B)** a single batch movement record referencing all bin IDs?
   > Answer: **(A) One movement record per bin.** Full per-bin audit trail.

**Slots to fill:**
- [x] Priority: build now vs. defer to PE-030b → **Build now**
- [x] Batch vs. per-bin movement records → **Per-bin (one record each)**
- [x] Whether Cart Mode UI lives inside the warehouse wizard or as a standalone action → **Both**

---

### DIS-012 / DIS-013 / DIS-014 — PIN Hashing & Legacy Auth Path Hardening

**Plans:** `docs/DevTODO/DIS-012-pin-hashing-weak-kdf.md`, `docs/DevTODO/DIS-013-legacy-pin-salt-path.md`, `docs/DevTODO/DIS-014-unsigned-token-shim.md`
**Current State:** `AuthService.hashPin()` uses 10,000× iterated SHA-256 (fast hash, GPU-crackable in seconds for 4-6 digit PINs). `legacyHashPin()` (single salt) is still reachable for un-migrated users. Unsigned token acceptance shim from PE-008a has no removal deadline.
**Proposed Change:** Upgrade to PBKDF2 (CommonCrypto, no new deps) or Argon2id. Add `pin_hash_version` column. Re-hash on next login (transparent upgrade). Eventually remove legacy paths.
**Affected Modules:** AuthService (core Swift), AuthService migrations.

#### Questions:

1. **As the Owner (Security Priority):** For a shop app on local LAN — PINs require physical device access to crack offline. Is upgrading PIN hashing to PBKDF2 a priority now, or is the current 10k-SHA-256 + per-user-salt good enough for v1? (It's much better than most shop apps — this is a hardening improvement, not a critical vulnerability.)
   > Answer: **Defer to v2.** Current 10k-SHA-256 + per-user salt is acceptable for LAN-only shop use.

2. **As a Developer:** If we upgrade to PBKDF2, which approach: (A) CommonCrypto PBKDF2 (no new dependencies, 100k iterations) or (B) Argon2id via Swift-Argon2 package (memory-hard, harder to add as a Swift Package)? Recommendation: Option A — CommonCrypto is already available on Apple platforms, no package manager changes needed.
   > Answer: **(A) PBKDF2 via CommonCrypto** when we do upgrade in v2. No new dependencies.

3. **As the Owner (Legacy Cleanup):** The legacy single-salt PIN path (DIS-013) and unsigned token shim (DIS-014) exist for backward compatibility. Is there a version cutoff where we can remove these? (e.g., "anyone still on the app from before 2026-03-30 will need to re-login once") Or should these stay permanently?
   > Answer: **Defer decision.** Will decide on legacy path removal timing later.

**Slots to fill:**
- [x] Priority decision: upgrade now vs v2 → **Defer to v2**
- [x] KDF choice: PBKDF2 vs Argon2id → **PBKDF2 (CommonCrypto, when ready)**
- [ ] Legacy path removal: yes/no + cutoff version → **Deferred**

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
