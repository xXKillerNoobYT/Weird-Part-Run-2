# #Isaac-14 — Notebook Block Editor Overhaul

> **Source:** Owner design spec delivered in chat, 2026-08-25, tagged `#Isaac-14`.
> **Status:** DESIGN — approved direction. §3 IMPLEMENTED (#1817); the rest not yet scheduled.
> **Supersedes:** the `2026-04-19` implementation notes in `docs/plans/ios-notebooks-pages.md`
> §2 (Shortcut Commands) and §3 (Conflict Resolution Flow) that deferred the `/` command
> palette and the AI merge. Those deferrals are now **lifted** — see §0.
> **Companion screenshot:** owner said an image of the Notebook page was incoming; it had not
> arrived when this was written. The one open item it settles is flagged in §0 as **Q1**.

---

## 0. Decisions, conflicts, and open questions

Per the design-first rule, decisions are recorded with reasoning so a later contradiction is
caught rather than silently applied.

### Decisions recorded

| # | Decision | Reasoning |
|---|----------|-----------|
| D1 | The `/` command palette becomes a **list**, not a popup/modal | Owner: *"instead of a popup there should be a list"*. Reverses the 2026-04-19 note that accepted a Picker dropdown as "more iOS-native". |
| D2 | Popups are reserved **exclusively** for elements/mini-apps (e.g. Panel Schedule) | Owner: *"the only things that should popup are elmints/miny app's"*. Gives one unambiguous rule for the whole editor. |
| D3 | A block opens **full-screen as a page**, and returns to the exact prior scroll position | Owner: *"go full screen like going to a new page in the app and go back the the exsat same locasion"*. |
| D4 | AI merge/organization is **advisory only** — every change is preview → Accept/Reject, and undoable | Owner specified before/after with Accept and Reject throughout. No AI edit ever lands unreviewed. |
| D5 | AI work is **deferrable** and may run off-device | Owner's battery/charging/server clause. AI must never block editing. |
| D6 | Suggestions are shown to the **last editing user** unless explicitly requested by someone else | Owner: *"unless asked for the last to edit user get's the sujested changes"*. |

### ⚠️ Conflict with existing architecture — needs an owner decision

**Q1 — What is "the server computer"?**
The spec says history is retained *"on at least the server computer"* and that AI work can be
*"handeled in the backgrond when charging or on the server computer"*.

**The current architecture has no server.** `CLAUDE.md` records the app as native-iOS-only with
Apple Multipeer P2P sync; **Phase 13 (Remote Sync) is ON HOLD**. Nothing today is an always-on host.

Two readings, materially different work:
- **(a)** "Server computer" = **the shop Mac** (Mac Catalyst) acting as the always-on peer in the
  local cluster. This fits the owner's stated workflow ("the Mac ... will be the main area where we
  will be adding the parts") and needs **no new infrastructure** — only a designated-host role.
- **(b)** "Server computer" = a real remote server. This **un-holds Phase 13** and is a much larger
  change touching the offline-first positioning.

**Assumed for this plan: (a).** Everything below is written against the shop-Mac reading. If the
owner means (b), §5 and §6 need re-scoping before any work starts.

**Q2 — "that info at the bottom"** (owner: *"that info att the bottom is amazing keep that"*).
Read as the existing page-level metadata strip, which the owner wants replicated **per block**.
The incoming screenshot confirms or corrects this. Low risk: the per-block field list in §3 is
explicit regardless of what the page-level strip currently shows.

---

## 1. Current state — measured, not assumed

Verified at `4a3ff3534`. **A "block" is a `notebook_entries` row.**

### Already present on the block (do NOT rebuild)

`blockType` · `blockData` (JSON, type-specific) · `createdAt` · `updatedAt` · `deletedAt` ·
`createdBy` · `updatedBy` · `deletedBy` · `isDeleted` · `sortOrder` · `taskStatus` ·
`headingLevel` · `checklistItems` · `photoPath` · `referenceType` / `referenceId`

### Already present elsewhere

- `NotebookBlockConflict` + `_conflict_log` — conflict detection exists.
- **AI merge exists AND is wired** (corrected 2026-08-25): `resolveBlockConflictWithFoundationModels`
  (:2080), `detectBlockConflicts` (:1971), called from `IOSNotebookDetailPage.swift` :1967 / :1524.
- **Advisory edit locks exist**: `notebook_entry_edit_locks` (migration 098) with
  `acquireBlockEditLock` / `releaseBlockEditLock` / `activeBlockEditLocks`.
- Panel Schedule mini-app: `PanelScheduleModels`, `PanelEditorDraft`, `DesignPanelState`,
  `PanelPrintDocument`.
- `/table` and `/panel` are **already in the block-type table** in the existing plan.

### Genuinely missing

| Owner asked for | Status |
|---|---|
| type, created/updated/deleted timestamps, editing user | ✅ **exists** |
| **Device ID on the block** | ❌ missing (exists only in `_conflict_log`) |
| **General block `status`** | ❌ missing (`taskStatus` is to-do-specific, not general) |
| **Live "currently editing" user** | ✅ **exists** — `notebook_entry_edit_locks` (migration 098). Do NOT add an `editing_user_id` column: two writers of one status slot disagree the moment a lock expires. |
| **Last 6 saved edits per user** | ❌ missing — no edit-history table |
| **90-day history/deleted retention** | ❌ missing |

> **Verify-before-building:** `blockData` (JSON, per block row) may **already satisfy** the
> "each panel schedule block has its own info even on the same page" requirement. Confirm by
> placing two Panel Schedule blocks on one page before writing any code for it. A built-but-unwired
> feature looks exactly like a missing one.

---

## 2. Block interaction model

> **Already tracked in #1662** (from the owner's own 2026-08-03 TestFlight feedback). #1643 is a
> near-duplicate of the same feedback. #Isaac-14 **extends and clarifies** these rather than
> replacing them.

| Behaviour | Detail | New? |
|---|---|---|
| **Click anywhere to edit** | Remove the requirement to click `+` to begin a block. Tapping any empty area places the caret and starts editing. | **NEW** |
| **Enter once** | New line **inside** the current block | in #1662 |
| **Enter twice** | Start a **new block** | in #1662 |
| **`/`** | Opens the block-type **list** (D1) inline at the caret | in #1662 |
| **`/panel`** | Filters that list to matching types | clarified |
| **Contextual add-block button** | Appears at the **bottom of the block containing the caret** — a touch-friendly alternative to `/` | **NEW** |
| **Press-and-hold a block** | Block info + type conversion (empty → any type; filled → only lossless targets) | in #1662/#1643 |

**Worked example from the spec** (the owner demonstrated it in the prose): a single line break
continues the same block; a blank line between paragraphs creates a new one.

---

## 3. Per-block metadata and history

Owner's rationale, verbatim in spirit: *"we want that done block by block as well that way syncing
can be done easier when several people edit."* Block-level metadata is what makes the §4 conflict
rules decidable.

### Fields to add

```
device_id     TEXT   -- device that last wrote this block
block_status  TEXT   -- general block lifecycle status (deliberately NOT task_status,
                     -- which is to-do-specific)
```

The live-editor field the owner asked for is **not** added here — `notebook_entry_edit_locks`
(migration 098) already provides it, and a column would be a second competing source of truth.

### Edit history — last 6 saved edits **per user, per block**

A ring buffer, not an unbounded log. Bounding it per-user-per-block is what keeps it syncable
over Bluetooth.

```
notebook_entry_edits
  id, entry_id, user_id, device_id,
  title_snapshot, content_snapshot, block_data_snapshot,
  saved_at, edit_ordinal   -- monotonic per (entry_id, user_id); newest 6 kept
```

**6 per user, per block** (owner clarification 2026-08-25) — three users on one block retain
6 + 6 + 6, not 6 shared. Eviction is scoped to `(entry_id, user_id)`.

`edit_ordinal` is the ordering key rather than `saved_at`: `datetime('now')` is second-resolution,
so two saves in the same second tie and "the newest six" stops being well defined.

**Sync-cost warning:** this multiplies per-block payload. The transport is Bluetooth-first and
already has open flow-control defects. The history table **must** be evaluated against
`allowedSyncTables` and the snapshot path before it ships, or it will regress join/sync times.

### Retention

History and soft-deleted blocks retained **90 days**, guaranteed on the designated host (Q1a: the
shop Mac). Device-local retention may be shorter; the host is the durable copy.

---

## 4. AI conflict resolution

> **CORRECTED 2026-08-25 after measurement.** An earlier draft of this section said AI merge was
> unimplemented, citing the `2026-04-19` deferral in `ios-notebooks-pages.md` §3 and 62J's *"future
> enhancement"* wording. **Both are stale.** AI merge is built and wired:
> `NotebooksService.resolveBlockConflictWithFoundationModels` (:2080), `detectBlockConflicts` (:1971),
> called from `IOSNotebookDetailPage.swift` :1967 / :1524, with passing tests.
>
> This section is therefore an **extension of a working feature**, not new construction. The deltas are
> below; audit the existing implementation against them before writing code (#1819).

### The four cases the owner named

1. **Big edits from different devices while out of sync**
2. **Small edits that conflict with each other**
3. **Two edits that say the same thing in different ways**
4. **Edits made on 2+ devices**

> Owner: *"the time dousnt mater for these"* — wall-clock ordering is explicitly **not** the
> tiebreaker. This is a deliberate departure from the LWW default and is the whole reason AI is
> involved.

### Behaviour

- **Case 3 → auto-merge.** Restate the same meaning once, clearly, as a single block. Still
  advisory (D4): shown as before/after with Accept/Reject.
- **Cases 1, 2, 4 → highlight the conflict** and ask the users involved to resolve it.
  - Choose **which** user to ask by **Role**, falling back to **account age**.
  - A resolution may be performed on a **different device at next sync**: show both versions to
    other users, and let any **authorized** user resolve **with confirmation**.

---

## 5. AI document organization

All suggestions follow one shared surface (see §7). One block is highlighted at a time.

| Trigger | Suggestion |
|---|---|
| Page is disorganized | Reorder blocks — with **preview** and **undo** if disliked |
| Headers unclear/absent | Add or reword headers to match the content beneath them |
| Several lists present | Group related content; suggest consolidation |
| A new block was just filled | Suggest a better location if its current one doesn't make sense |
| Text is confusing | Rewrite via **Apple's built-in rewrite** (Foundation Models / Writing Tools) |
| Content is list-shaped | Offer to convert it into a real list block |
| Images present | Use **Apple's built-in image recognition** to assist |

### Unplaceable-block fallback loop

Owner-specified, exactly:

1. Suggest a location.
2. If the first **2** suggestions are rejected → **ask the user a question** to gain context.
3. Make **1** further suggestion using that answer.
4. **Loop at most 4 times**, then give up and leave the block where it is.

### "Make this doc readable" button

One action running the full pass in order: organize → add headers → fix grammar/spelling →
rewrite where needed → suggest lists and other structure.

> Owner's stated precondition: *"as long as the user made a block per a thought it should work."*
> This is the design contract — the feature is not expected to rescue a single giant block.

Supported by a **chat agent** using fill-in-the-blank style prompting rather than open-ended chat.

### NOTE / Observation button

A quick-capture button for a free-floating note or observation, which then feeds the placement
loop above.

---

## 6. Scheduling and power policy

AI work is deferrable (D5) and must never block editing.

**Defer when:** Low Power Mode · battery < **35%** · the day's optimal-level budget is spent.
**Resume when:** charging, or on the designated host (Q1a).
**Delivery:** when work runs off-device, results wait for **sync to carry them back** before being
shown. Suggestions surface to the **last editing user** unless another user asked for them (D6).

---

## 7. Suggestion review surface (shared by §4 and §5)

One consistent control for every AI-proposed change:

- **Before / after** shown side by side.
- **Accept** and **Reject** buttons.
- **←** and **→** keyboard keys mapped to reject/accept for hardware keyboards.
- Exactly **one block highlighted at a time**.
- Every accepted change is **undoable**.

---

## 8. Tables

Owner: *"tables available as well, easy to edit, with insert column — think Excel but only as big
as needed."*

Extends the existing `/table` "simple grid table" block:
- Inline cell editing.
- **Insert / delete row and column.**
- Auto-sizing — the grid grows only to the content, no fixed oversized canvas.

---

## 9. Build order (dependencies)

```
      ┌─ §2 Interaction model (#1662, extended) ──┐
      │                                            ├─→ §8 Tables
      └─ §3 Per-block metadata + history ─┬────────┘
                                          │
                                          ├─→ §4 AI conflict resolution
                                          │
                                          └─→ §7 Suggestion surface ─→ §5 Organization ─→ §5 "Readable" button
                                                                        │
                                                                        └─→ §6 Scheduling policy
```

**§3 is the keystone.** Conflict rules and per-user suggestion routing are undecidable without
per-block device/user/history data. It should land first.

**§2 is independently shippable** and is the fastest visible win — it is already queued in #1662.

---

## 10. Risks

1. **Sync payload growth (§3)** — the edit-history ring buffer lands on a Bluetooth-first
   transport with open flow-control defects. Measure before shipping.
2. **AI advisory-only must hold (D4)** — an AI edit that lands without review on shared job
   documentation is a data-loss class bug, not a UX complaint.
3. **Q1 unresolved** — §5/§6 assume a designated host. If the owner means a real server, re-scope.
4. **Scope** — this is an epic. §2 alone is a shippable improvement; do not gate it behind the AI work.
