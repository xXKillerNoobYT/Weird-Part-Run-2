# Bluetooth Snapshot Resume — transfer identity, windowed acks, restart recovery

**Status:** PLANNED · **Created:** 2026-08-10 · **Tracks:** #1417 (umbrella), WEI-7021/7022/7024/7025
**Builds on:** #1685 (merged 2026-08-10, `6775a2a1e`) — durable staging + caps
**Supersedes:** PR #1690, PR #1691 (both closed — see "Why those were closed")

---

## Where we are

#1685 made the joiner's initial Bluetooth snapshot **durable**: batches land in `_snapshot_staging` (migration 122) as they arrive, and `fullSyncComplete` replays them in `seq` order inside one transaction. Apply-then-acknowledge is preserved, so the host's one-time capability is never consumed against a joiner that stored nothing. #1688 added per-peer ceilings (2,000,000 records / 1 GiB). Review fixes added a UNIQUE `(peer_device_id, seq)` index, a fail-closed pre-staging clear, and `snapshotIncomplete` on any non-zero `skipped` count.

**What it deliberately does not do: resume.**

`PeerManager.startPeerSync` calls `clearAllSnapshotStaging()`, and `failPendingMultipeerOperations` does the same on transport shutdown. Anything on disk at startup is treated as scrap and deleted.

That was the correct call *at the time*, and the reasoning is worth preserving because this plan reverses it:

> Rows from a dead process cannot be attributed to a known transfer. `seq` restarts at 0 for every attempt, so surviving rows from attempt A are indistinguishable from attempt B's. Replaying them would assemble a company from two points in time and report success.

So the blocker on resume was never storage. It was **attribution**. #1683 said as much — "Once staged, resume becomes possible — the joiner knows which sequence numbers it already holds" — and that is exactly the piece #1685 left out.

## The gap this closes

A large company over Bluetooth takes a long time. Today any interruption — jetsam kill, backgrounding, walking out of range, a flaky link — discards **everything** and the retry restarts from zero. On a slow link with a real company that can mean onboarding never completes at all. Electricians on remote sites with no cell or wifi are the core user; this is their first-run experience.

## Design

### 1. Transfer identity — the enabling primitive

The host generates a `transfer_id` (UUID) when it begins a snapshot and stamps it on **every** frame. Staging rows carry it. That single addition makes disk rows attributable, which is what unlocks everything else.

**Migration 123** (122 is taken on `main` — do not reuse it):

- add `transfer_id TEXT NOT NULL DEFAULT ''` to `_snapshot_staging`
- replace `idx_snapshot_staging_peer_seq` with UNIQUE `(peer_device_id, transfer_id, seq)`
- new `_snapshot_transfer` metadata table: `peer_device_id`, `transfer_id`, `started_at`, `last_contiguous_seq`, `state` (`staging` | `applying` | `failed`), UNIQUE on `(peer_device_id, transfer_id)`

Both tables stay sync **infrastructure**: `_` prefix, absent from `ConflictResolver.allowedSyncTables`, no change-tracking triggers. A test must assert this for `_snapshot_transfer` exactly as one already does for `_snapshot_staging`.

Rows staged by a pre-resume build carry `transfer_id = ''`. Treat empty as unattributable and delete on startup — identical to today's behaviour, so the upgrade path is a no-op rather than a special case.

### 2. Startup: expire, don't wipe

`clearAllSnapshotStaging()` at startup is replaced by `expireStaleSnapshotStaging()`:

- delete every staging row whose `transfer_id` has no `_snapshot_transfer` row (orphans, and all pre-migration rows)
- delete every transfer whose `state` is `applying` or `failed` — `applying` means we died mid-apply, and the apply transaction already rolled back, so its staging is scrap
- delete every transfer older than **`snapshotResumeTTL` (24h)** — a stale half-download must not resurface days later against a company that has since moved
- **retain** `staging`-state transfers inside the TTL, as resume candidates

This is the safety-critical change in the whole plan. The invariant that replaces the wipe:

> A staged row is replayable only if its `transfer_id` matches the transfer currently in flight with that peer. Everything else is deleted before any staging begins.

### 3. Resume handshake

`FullSyncRequest` gains an optional `resumeTransferId` + `resumeFromSeq`. The joiner, on requesting a snapshot from a host it has a live `staging` transfer for, sends both.

The host decides — it owns the data, and only it knows whether that transfer is still coherent:

- unknown/expired `transfer_id`, or its own change log has moved on → reply with a **new** `transfer_id`; joiner clears the old transfer and stages from scratch
- recognised and resumable → reply with the **same** `transfer_id` and resume sending at `resumeFromSeq + 1`

The joiner never assumes resumability. A host that cannot resume costs one restarted transfer; a joiner that wrongly assumes it can produces a silently mixed company. Fail toward the recoverable error.

### 4. Contiguity, duplicates, windowed acks

- **Contiguity is enforced on receipt.** A frame whose `seq` is not `last_contiguous_seq + 1` fails the transfer with a typed error. Replay depends on `ORDER BY seq` being gapless; a gap must never be discovered at apply time.
- **Duplicate `seq`:** identical payload → idempotent, ignore (a resend crossing an ack in flight is normal). Different payload → fail. The UNIQUE index is the backstop.
- **Windowed acknowledgement:** the joiner acks every `snapshotAckWindow` (default 64) staged frames with its `last_contiguous_seq`. The host keeps at most one window unacknowledged and resends that window on timeout, bounded to `snapshotMaxResends` (default 3). This is flow control for the *frame* layer and is separate from the existing `fullSyncApplied` acknowledgement, which still fires exactly once, after the atomic apply.

### 5. What does not change

The parts that carry the correctness guarantees stay exactly as merged:

- apply-then-acknowledge ordering, and the single-transaction replay
- the `validate:`-inside-the-transaction completeness rule and `snapshotIncomplete`
- the #1688 caps — now additionally enforced **per transfer**, so resume cannot be used to walk past a ceiling by restarting
- the fail-closed pre-staging clear
- post-commit counter discipline (`snapshotStagedRecords` / `snapshotStagedBytes` advance only after commit)

## Why #1690 and #1691 were closed

Both implemented this same feature, and both **replaced** #1685 rather than building on it. Verified at their heads:

| | `main` | #1690 | #1691 |
|---|---|---|---|
| `122_snapshot_staging` | ✅ | absent (own `122_bluetooth_snapshot_staging`) | **removed** |
| `stageSnapshotChanges` | ✅ | rewritten | **0 refs** |
| #1688 caps | ✅ | **none** | **none** |
| cap tests | 2 | 0 | 0 |

#1691 is the more dangerous of the two: it already contains merged `main`, so git merges it **cleanly** — no conflict is ever raised — while silently reverting #1685, #1688 and the three review fixes, and returning the joiner to unbounded staging.

Their protocol ideas are good and are carried forward here. Their integration strategy was the problem.

## Risks

| Risk | Mitigation |
|---|---|
| Resuming into a company the host has since changed | Host owns the resume decision and issues a fresh `transfer_id` whenever its log has moved on |
| Stale staging resurfacing days later | 24h TTL, plus `state` expiry at startup |
| Retiring the startup wipe re-opens the mixing bug | Attribution invariant (§2) + UNIQUE `(peer_device_id, transfer_id, seq)` + contiguity check on receipt — three independent mechanisms |
| Resume used to bypass the #1688 caps | Caps enforced per transfer, not just per peer |
| Migration renumbering drift | 123, explicitly; a test asserts registration, as with 122 |

## Test plan — every case red-proofed

1. Interrupted transfer resumes from `last_contiguous_seq` and applies exactly once (break: ignore `resumeFromSeq` → duplicate rows / constraint violation)
2. Host refusing resume issues a new `transfer_id`; joiner discards old staging (break: reuse id → mixed company)
3. Startup retains an in-TTL `staging` transfer and deletes orphans, `applying`, `failed`, and expired (break: retain all → stale replay)
4. Non-contiguous `seq` fails the transfer (break: accept → gap discovered at apply)
5. Duplicate `seq`, identical payload is idempotent; differing payload fails
6. Caps still enforced across a resumed transfer (break: reset counters on resume → unbounded)
7. `_snapshot_transfer` is infrastructure: registered, not in `allowedSyncTables`, no triggers
8. Pre-migration rows (`transfer_id = ''`) are deleted at startup

Gates: full `cd core && swift test` (2592+ at time of writing, 0 failures) **and** the iOS Beta Gate — `swift test` does not execute `Weird_Parts_IOSTests`.

## Sequencing

1. Migration 123 + `_snapshot_transfer` + infrastructure test
2. Transfer identity threaded through frames and staging; startup expiry replaces the wipe (§2 is the risky half — land it with tests 3 and 8 green before anything depends on it)
3. Contiguity + duplicate handling
4. Resume handshake
5. Windowed acks + bounded resend

Steps 1–2 are the load-bearing ones. 3–5 are additive on top and can land separately if the change gets large.
