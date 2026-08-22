# Sync — "advance the cursor on confirmed apply, not on transport-accept" (Cluster A)

**Status:** IMPLEMENTED — focused regression suite green (10 tests), PR open · **Issues:** #1792 (P1), #1793 (P1), #1794 (P2)
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

## Verification signal (current evidence)

`swift test --filter SyncCursorAdvanceTests` — 10 focused tests exercise:
1. `ConflictResolver.resolveAndApplyChanges` classifies an actual foreign-key refusal as `permanentRefusals`, not `errors`.
2. The real `PeerManager.processInbox()` path drains a permanent refusal, applies the later valid row, and leaves the inbox clear; the injected-policy companion confirms transient outcomes still requeue.
3. The real LAN `PeerManager.syncWithPeer` → `syncViaHTTP` path receives a permanent refusal, reports zero applied rows, and advances the receiver's remote vector clock to sequence 41.
4. The real `SyncEngine.runSync` success path uploads its 500-row window and reports the five remaining pending rows.
5. The capped `getPendingChanges` window differs from the true pending count.

Required before review: run and record the requested revert-mutation proof; then rebase against current `main` and obtain fresh exact-head iPhone/iPad + serialized review-lane evidence.

Not verifiable headless: a real two-device LAN round-trip. Field confirmation on paired
hardware remains a follow-up.
