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
 the bug that got PR #1749 reverted. `MergeResult` (ConflictResolver.swift:56-162) documents
that `keyCollisions`, `schemaDrops`, and `supersededMerges` are deterministic non-applies.
Re-delivering them cannot change their outcome and can pin the sender forever.

A foreign-key failure is deliberately **not** in that terminal class: the sender may deliver a
child before its parent, including in a later payload. The LAN receive paths therefore do not
use `MergeResult.isSafeToAdvanceReceiveCursor` as an apply-ack decision. They durably record
receipt first, then the journal marks FK rows `deferred` until a later parent makes a fixed-point
replay succeed. Only `trigger`, missing-table, and schema-representation refusals become terminal
`refused` audit records. Infrastructure failures remain `retry` rows. This retains every
acknowledged row while ensuring an irreconcilable row cannot hot-loop or block its successors.

## Decision

| # | Site | Change |
|---|------|--------|
| #1794 | `SyncEngine.runSync` success path | Replace `pendingCount: 0` with `getPendingChangeCount(db:)` (re-read after `markSynced`), matching every error path in the same function. |
| #1793 | `PeerManager.syncViaHTTP` pull | Persist all received rows in `SyncReceiveJournal` before advancing the receive vector. Then apply pending rows; `pulled` is confirmed applications, not transport row count. |
| #1792 | `PeerManager.processInbox` | Persist legacy in-memory input in `SyncReceiveJournal` before applying. The in-memory drain is safe only after durable receipt; journal states retain deferred/retry/refused outcomes. |

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

Current focused behavior evidence (2026-08-29, before the next commit):

1. `swift test --filter SyncCursorAdvanceTests` passed **17 tests**. It invokes the real
   `PeerManager.processInbox()`, real LAN `syncWithPeer` → `syncViaHTTP`, and real
   `SyncEngine.runSync` call paths. The two added production-path regressions deliver a
   `part_styles` child before its `part_categories` parent and assert eventual child apply;
   the LAN test also asserts vector receipt reaches sequence 82 only after durable journal write.
2. A temporary mutation replaced the journal fixed-point condition
   `while appliedThisPass > 0` with `while false`. The same suite failed **11 assertions**,
   including the new `processInbox` child-before-parent test and the new `syncViaHTTP` LAN
   child-before-parent test. The original condition was restored, then the 17-test suite passed.
3. `swift test --filter ConflictResolverTests` passed **44 tests**; `swift test --filter
   ConflictResolverNaturalKeyTests` passed **31 tests**. The SwiftPM wrapper also prints a
   legacy XCTest "0 tests" line before Swift Testing; the `Test run with … passed` line is
   the canonical result.
4. `git diff --check` was clean before commit. The current branch still needs a post-commit
   exact-head iPhone+iPad gate and a restarted SecurityAgent → LocalFirstReviewer →
   GPTReviewer → ClaudeReviewer lane. Previous iPhone/iPad gates must not be treated as
   evidence for the next head.

Not verifiable headless: a real two-device LAN round-trip. Field confirmation on paired
hardware remains a follow-up.
