# Durable Bluetooth Snapshot Staging Remediation

Status: Approved architecture — implementation tracked by WEI-7025.

## Scope and intent

This plan replaces the in-memory initial Bluetooth snapshot buffer with transfer-scoped private SQLite staging. It follows the approved WEI-7024 design and applies only to initial full snapshots carried over the existing Multipeer Bluetooth/Wi-Fi P2P transport. It does not change pairing capability issuance, normal incremental sync frames, or transport discovery.

## Protocol

1. The host validates the pairing-issued one-time capability, reserves it, and emits `snapshotBegin` for a unique transfer ID.
2. The host sends one `snapshotBatch` at a time. A batch is identified by the transfer ID, a monotonically increasing zero-based sequence, and an encoded homogeneous array of `IncomingChange` values.
3. The joiner accepts staged frames only from the authorized/trusted snapshot host, validates the transfer and sequence, commits the batch payload into private staging, and only then emits `snapshotStored(transferId, sequence)`.
4. The host may send sequence N+1 only after it receives the durable stored acknowledgement for N. A missing acknowledgement retries the same sequence a bounded number of times; a repeated acknowledged sequence is idempotent only when its payload digest matches, and otherwise fails closed.
5. The host emits `snapshotComplete` only after the final stored acknowledgement. The joiner verifies staging sequence numbers are contiguous from 0 through the advertised final sequence and atomically applies all staged changes through the existing conflict resolver, deletes the staged rows, and commits.
6. Only after that commit does the joiner emit the existing final durable apply acknowledgement. The host records success only after receiving it.

## Persistence

Migration 122 creates a private `_snapshot_staging` table keyed by `(transfer_id, sequence)` with the authorized host identifier, payload/digest, and creation timestamp. The migration creates no sync triggers and the table is excluded from snapshot table enumeration and `_change_log` tracking.

## Invariants and failure handling

- There is never more than one unacknowledged host batch.
- A joiner acknowledgement proves its SQLite staging commit, not merely receipt in memory.
- No staged snapshot data reaches business tables until the final transaction commits.
- Unknown frame types, malformed frames, mixed transfer payloads, sequence gaps, mismatched duplicate data, authorization failures, and final apply errors fail visibly and do not report host success.
- Disconnect, app termination, and manager recreation leave staged rows but no partial business apply; a later authorized retry may resume/idempotently redeliver staged batches.
- Existing pairing trust/capability checks remain mandatory; legacy incremental `changes` frames remain distinct from staged snapshot frames.

## Verification matrix

Focused deterministic tests cover: window size one; host wait/retry behavior; duplicate equal versus mismatched data; disconnect after staging; manager recreation prior to completion; sequence gap rejection; final apply rollback and absent positive final acknowledgement; migration registration/readback; and the Bluetooth transport seam using injected send closures rather than real radio state.

## Review and delivery

Review chain: WEI-7026 LocalFirst → WEI-7027 Security → WEI-7028 GPT → WEI-7029 Claude → WEI-7030 Bluetooth-only device QA. GitHub umbrella: #1417. Parent work: WEI-7021, WEI-7022, WEI-7024.
