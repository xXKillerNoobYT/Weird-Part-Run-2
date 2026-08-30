# Sync — "advance the cursor on confirmed apply, not on transport-accept" (Cluster A)

**Status:** IMPLEMENTED — production-call-site regression coverage and deterministic-refusal classification repaired; fresh exact-head iPhone/iPad gates required before review · **Issues:** #1792 (P1), #1793 (P1), #1794 (P2)
**Branch:** `fix/sync-advance-on-apply-cluster-a`
**Found by:** adversarially-verified sync + data-core review, 2026-08-21

## Problem (one root cause)

Three defects share a single source: a sync cursor is advanced or cleared based on
**transport acceptance**, not on **confirmed apply**. The design comment at
`PeerManager.swift:3348` states it plainly — *"advances on transport-accept, not on an
applied ack."*

- **#1792 (P1, `PeerManager.processInbox`)** — drains the in-memory LAN inbox, applies the
  batch, and swallows the failure in an empty `catch` whose comment ("will be retried")
  is false. The inbox is in-memory only (`LanSyncServer.drainInbox` unconditionally sets
  `inbox = []`); the sender already got HTTP 200 and advanced its send watermark, so it
  never resends. **Silent, permanent receiver-side data loss.**
- **#1793 (P1, `PeerManager.syncViaHTTP` pull)** — discards the `MergeResult`, reports
  `pulled = every received row`, and advances the receive vector clock past rows that did
  not apply. Server never re-sends them. Same silent loss, pull direction.
- **#1794 (P2, `SyncEngine.runSync`)** — the success path hardcodes `pendingCount: 0`, but
  `getPendingChanges` is capped at `LIMIT 500`. After a >500-row push it reports an empty
  backlog that is not empty.

## The landmine (why the naive fix is wrong)

The naive fix — "advance only past rows that applied" — is **wrong** and would re-introduce
the bug that got PR #1749 reverted. `MergeResult` (ConflictResolver.swift:56-109) documents
that `keyCollisions`, `schemaDrops`, and `supersededMerges` are **deterministic, expected**
non-applies. A `keyCollision` "is a deterministic function of (payload, local schema, local
rows), so every retry re-derives it"; a `schemaDrop` "a retry can never fix … only a schema
migration can." Holding the watermark for those re-sends the same rows **forever** and the
peer never converges.

Only `errors` (SQLITE_BUSY, disk full, transient DB faults) are retryable. Permanent
FOREIGN KEY / TRIGGER / missing-table refusals are separately counted in
`permanentRefusals`, alongside the existing deterministic counters. So the correct
rule is: **advance unless `errors > 0`.** This is exactly what the existing atomic paths
already do — `PeerManager.applyStagedSnapshot` (`guard result.errors == 0`, line 1602) and
`applyIncomingChanges` (line 2896). The fix makes the LAN pull + inbox paths **match the
convention the snapshot/BT paths already follow**, rather than inventing new semantics.

## Decision

| # | Site | Change |
|---|------|--------|
| #1794 | `SyncEngine.runSync` success path | Replace `pendingCount: 0` with `getPendingChangeCount(db:)` (re-read after `markSynced`), matching every error path in the same function. |
| #1793 | `PeerManager.syncViaHTTP` pull | Capture the `MergeResult`; report `pulled = mergeResult.applied`; advance the receive vector clock **only when `mergeResult.errors == 0`**. |
| #1792 | `PeerManager.processInbox` | Capture the result; on a thrown error (nothing committed) **or** `result.errors > 0`, re-append the drained batch to the inbox so the next pass retries. Stop swallowing. |

Re-queue safety: re-applying an already-applied row is LWW-idempotent; deterministic
constraint outcomes are counted as `keyCollisions`/`schemaDrops` (never `errors`), so the
re-queue converges rather than looping.

## Durable ordered receive journal (PR #1807 repair)

The preceding cursor predicate was insufficient for a valid foreign-key child whose
parent arrives in a **later delivery**: it could either hold the whole peer forever
or make the child unreachable after an acknowledgement. The receive path now has two
separate facts, persisted in migration `129_sync_receive_journal`:

1. **Durable receipt:** the transport commits `(source_peer_id, source_sequence,
   payload, audit_metadata)` with state `received`. Only after this succeeds may the
   LAN pull vector advance or a LAN push return acceptance. Receipt acknowledges
   retention, not business-data application.
2. **Apply completion:** ordered journal replay attempts rows by receipt id. A missing
   FK parent becomes `deferred`; a transient database failure becomes `retry`; a
   deterministic refusal becomes `refused` with `disposition_reason`; and only a
   confirmed apply becomes `applied`. Fixed-point passes repeat only after progress,
   preserving source order without tail-requeue or hot loops. Terminal rows stay
   queryable as audit evidence.

This means a child accepted in one batch is never discarded just because its parent
is absent. When that parent arrives later, the parent applies and a subsequent
ordered pass applies the child. Existing LWW checks remain the stale-replay fence:
an older deferred payload cannot overwrite or un-delete newer state.

## Verification signal

On 2026-08-22, branch head `999dd1155815e869beb488c18cd7aff0c2cbcb42` rebased cleanly onto `main` at `a5b674a8edfe189cdd3faee9320122965b94b5c8` before the final expectation repair below.

Focused behavior evidence:
1. `swift test --filter SyncCursorAdvanceTests` passed **11 tests**. It invokes the real `PeerManager.processInbox()`, real LAN `syncWithPeer` → `syncViaHTTP`, and real `SyncEngine.runSync` call paths.
2. A temporary revert mutation inverted both receive-cursor policy branches and restored `pendingCount: 0`; the same suite failed with five assertions: deterministic inbox clear/later-row flow, transient requeue, LAN vector advance, and remaining pending count. The mutations were restored before this update.
3. Actual SQLite FOREIGN KEY, TRIGGER, and missing-table refusals are asserted as `permanentRefusals == 1` and `errors == 0`; the two pre-existing counter expectations that still asserted `errors == 1` were corrected in this repair.
4. The focused natural-key and conflict-resolver suites report all **31** and **44** Swift Testing cases passed. Their `swift test --filter` command wrapper also prints a legacy XCTest "no matching test cases" warning, so the canonical current-head iPhone/iPad gate remains the final platform proof.

The previous exact-head iPhone and iPad gate run on `999dd1155815e869beb488c18cd7aff0c2cbcb42` completed UI smokes (5/5 each) but failed unit regression only because those two stale `errors == 1` expectations were still present. Fresh iPhone+iPad runs on the post-repair SHA are required before the SecurityAgent → LocalFirstReviewer → GPTReviewer → ClaudeReviewer sequence may begin.

Not verifiable headless: a real two-device LAN round-trip. Field confirmation on paired
hardware remains a follow-up.
