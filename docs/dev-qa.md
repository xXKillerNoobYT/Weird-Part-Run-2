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

> Added 2026-04-06 (dev-pipeline-manager run 13): 2 design questions for GitHub issues #22 and #36 that have been open without plans.

---

### GitHub #22 — Warehouse Setup Wizard: Unit Layout Assumptions

**Issue:** `Warehouse Setup Wizard assumes all items on Row 1` (filed 2026-04-04)
**Current State:** `WizardStepPlacement.swift` has a tap-to-place grid where the user taps cells to assign storage units to floor plan positions. The wizard currently does not pre-fill any positions — it starts with an empty grid. The plan (`docs/plans/ios-warehouse-setup-redesign.md`) describes drag-and-drop placement as "remaining" work.
**Proposed Change:** Before writing a prompt, need to understand what layout input is actually needed and what "Row 1" assumption means in practice.
**Affected Modules:** Warehouse (WizardStepPlacement.swift, WarehouseService)

#### Questions:

1. **As the Owner:** When you set up the warehouse wizard, what do you mean by "assumes all items on Row 1"? Is it that the wizard pre-fills all units into the first row instead of letting you drag them into position? Or is there a different behavior you've observed?
   > Answer: Yes — the wizard pre-fills all units into Row 1 instead of leaving them unplaced. That is the bug.

2. **As an Owner/Designer:** What should the ideal layout input look like? Should the user type in the number of rows and columns first (e.g., "my warehouse is 3 rows × 5 columns"), then drag units into that grid? Or should it auto-calculate a reasonable layout from the count of units?
   > Answer: Dimensions first. User enters rows × cols (e.g. 3×5), then drags units into that explicit grid. Do not auto-calculate.

3. **As a Developer:** The current `WizardStepPlacement.swift` already has a tap-to-place grid with dynamic rows/columns. Is PE-030 (warehouse setup redesign prompt) still needed, or is the grid functional enough and #22 is a different/specific bug in that grid?
   > Answer: PE-030 (or a successor prompt) is still needed. Tap-to-place is insufficient — the redesign must implement dimensions-first input followed by true drag-and-drop placement. Tap-to-place becomes legacy.

**Slots to fill:**
- [ ] What "assumes Row 1" means specifically — bug or design gap?
- [ ] Whether drag-and-drop is still needed or tap-to-place is acceptable
- [ ] What happens to the current tap-to-place grid if this changes

---

### GitHub #36 — Receiving Session: Back Button Discards Work

**Issue:** `Receiving back button discards work with no confirmation` (filed 2026-04-04)
**Current State:** `IOSReceivingSessionPage.swift` (or related receiving flow) allows the user to navigate back while a receiving session is in progress, discarding all scanned quantities without warning. This is a data-loss risk.
**Proposed Change:** Add a confirmation dialog when the user taps Back or swipes to dismiss during an active receiving session. The dialog should offer: "Save Draft", "Discard Changes", "Cancel".
**Affected Modules:** Warehouse receiving flow

#### Questions:

1. **As the Owner:** During receiving, if a worker accidentally taps Back, should their scanned quantities be auto-saved as a draft (so they can resume), or just confirmed before discarding? Is a simple "Are you sure? Your scanned quantities will be lost" dialog enough, or do you need a save-and-resume capability?
   > Answer: Auto-save draft + resume. Silent draft persistence on any dismiss (Back tap, swipe, app backgrounding). No confirm dialog needed if drafts are reliable. User can resume from where they left off.

2. **As an Employee (warehouse):** How often does the Back button get accidentally tapped during receiving? Is this a real pain point, or just a theoretical risk?
   > Answer: Real, recurring pain — happens regularly in the field. High priority.

**Slots to fill:**
- [ ] Confirm/discard only, or save-draft-and-resume?
- [ ] Which file handles the receiving session dismiss gesture

---


---

### DIS-012 / DIS-013 / DIS-014 — PIN Hashing & Legacy Auth Path Hardening

**Plans:** `docs/DevTODO/DIS-012-pin-hashing-weak-kdf.md`, `docs/DevTODO/DIS-013-legacy-pin-salt-path.md`, `docs/DevTODO/DIS-014-unsigned-token-shim.md`
**Current State:** `AuthService.hashPin()` uses 10,000× iterated SHA-256 (fast hash, GPU-crackable in seconds for 4-6 digit PINs). `legacyHashPin()` (single salt) is still reachable for un-migrated users. Unsigned token acceptance shim from PE-008a has no removal deadline.
**Proposed Change:** Upgrade to PBKDF2 (CommonCrypto, no new deps) or Argon2id. Add `pin_hash_version` column. Re-hash on next login (transparent upgrade). Eventually remove legacy paths.
**Affected Modules:** AuthService (core Swift), AuthService migrations.

#### Questions:

1. **As the Owner (Security Priority):** For a shop app on local LAN — PINs require physical device access to crack offline. Is upgrading PIN hashing to PBKDF2 a priority now, or is the current 10k-SHA-256 + per-user-salt good enough for v1? (It's much better than most shop apps — this is a hardening improvement, not a critical vulnerability.)
   > Answer: _pending_

2. **As a Developer:** If we upgrade to PBKDF2, which approach: (A) CommonCrypto PBKDF2 (no new dependencies, 100k iterations) or (B) Argon2id via Swift-Argon2 package (memory-hard, harder to add as a Swift Package)? Recommendation: Option A — CommonCrypto is already available on Apple platforms, no package manager changes needed.
   > Answer: _pending_

3. **As the Owner (Legacy Cleanup):** The legacy single-salt PIN path (DIS-013) and unsigned token shim (DIS-014) exist for backward compatibility. Is there a version cutoff where we can remove these? (e.g., "anyone still on the app from before 2026-03-30 will need to re-login once") Or should these stay permanently?
   > Answer: _pending_

**Slots to fill:**
- [ ] Priority decision: upgrade now vs v2
- [ ] KDF choice: PBKDF2 vs Argon2id
- [ ] Legacy path removal: yes/no + cutoff version

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
