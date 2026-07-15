# Sync Encryption and Bluetooth Snapshot Completion Integrity

Status: Implemented; pending PR review/CI (WEI-4840; GitHub #385 and #1417)
Date: 2026-07-15
Owner: CTO / Sync core
Review lanes: SecurityAgent, non-author engineering review, GitHub Copilot PR reviewer

## Problem

Current `main` silently downgrades negotiated LAN encryption when key derivation or AES-GCM encryption fails, and can feed ciphertext into JSON decoding when decryption fails. The Bluetooth initial snapshot also reports success after host-side enumeration, page-read, row-encoding, or transport-send failures. On the joiner, each incoming change batch is launched in an un-awaited task, so `fullSyncComplete` can resume onboarding before earlier database writes are durable.

## Scope

1. Restore the throwing key-derive/encrypt/decrypt behavior and regression coverage from archived commit `4231a19e`, adapted to current HTTP response validation.
2. Make Bluetooth snapshot production a throwing, testable pipeline:
   - table enumeration throws;
   - page reads throw;
   - every included row must have a usable `Int64` id and JSON representation;
   - batch encoding throws;
   - every batch send and the final completion send must succeed;
   - any failure records a failed host result and, where transport remains available, sends a failure completion to the joiner.
3. Drain Multipeer's existing FIFO queue through one guarded `PeerManager` actor consumer and await each change-batch database application before processing the next envelope. Each batch applies atomically, so a failed row rolls back its successful prefix. A completion envelope may resume onboarding only after all earlier batches committed. Decode/apply/remote-completion failure resumes the pending request with a visible retryable error.
4. Fail closed on the current client path: outbound LAN sync requires successful key negotiation and AES-GCM; key-fetch, derive, encrypt, and decrypt failures cannot select plaintext. The server temporarily retains authenticated plaintext request compatibility for older installed clients. An empty legacy `fullSyncComplete` payload remains a success signal for already-started older Bluetooth hosts.
5. Bind Bluetooth snapshot authorization to the successful pairing session with a random capability token, in addition to requiring a trusted and non-deactivated device registry entry. Reserve the token before transfer to prevent replay/concurrent snapshot duplication, restoring it only after a failed transfer so the joiner can retry.

## Design

### Host snapshot pipeline

Add a small deterministic `BluetoothSnapshotTransfer` execution component outside the already-large `PeerManager.swift`. It accepts injected table/page/encode/send operations, returns the sent record count, and throws typed errors. Production adapters remain in `PeerManager` and use GRDB, the existing row-to-JSON conversion, `JSONEncoder`, and `MultipeerManager.send`.

The host sends `fullSyncComplete` only after all snapshot batches succeed. Its payload is a codable completion result (`success`, optional `error`). If snapshot production fails, the host attempts to send a failure result, records `PeerSyncResult(success: false)`, and never logs or records success. If the success-completion send itself fails, the host records failure.

The Bluetooth pairing response carries a random snapshot capability. The joiner returns it in `fullSyncRequest`; the host requires an exact capability match plus a trusted/non-deactivated registry row and binds the pairing request identity to the Multipeer session's advertised device id. This prevents a nearby peer from obtaining a snapshot by merely spoofing a known device id.

### Joiner ordering

`MultipeerManager` already stores received messages in a serial FIFO queue. Its callback schedules an actor-isolated drain rather than independently processing the callback argument; an explicit in-progress guard prevents actor reentrancy from starting a second consumer while the first is suspended. The drain pops messages until empty and awaits each message. `changes` decoding and atomic `ConflictResolver` application throw. `fullSyncComplete` then resolves the pending continuation with success or failure. Because both steps execute serially in one actor drain, completion cannot overtake durable database application.

### Error and retry behavior

The existing `requestFullSyncOverMultipeer` API remains throwing. Send, decode, apply, remote-host, and timeout failures are surfaced to onboarding; a caller can retry the same operation. Continuations are removed before resume so late completion/timeout messages cannot double-resume.

## Dependency map

- `PeerManager.syncViaHTTP` -> `resolveSharedKey` -> `SyncCrypto` (LAN confidentiality/correctness)
- `PeerManager.handleFullSyncRequest` -> `BluetoothSnapshotTransfer` -> GRDB reads/row encoding -> `MultipeerManager.send`
- `MultipeerManager.receiveQueue` -> `PeerManager.drainMultipeerMessages` -> `ConflictResolver` -> GRDB commit -> full-sync continuation
- `PeerManagerTests` validates crypto propagation, host fault classes, ordered durable apply, and apply-failure visibility

## Acceptance criteria and evidence

- Missing/malformed/unauthorized key exchange, invalid keys, and AES-GCM failures throw; no plaintext downgrade or ciphertext-as-JSON fallback.
- Host table enumeration, page read, row conversion, batch encoding, batch send, and completion-send failures cannot produce a successful transfer result.
- Joiner processes FIFO batches serially and only completes after prior database application; apply failure throws and is retryable.
- Focused `PeerManager`/sync/crypto tests pass.
- Full `core` suite passes.
- Current-main PR includes `Closes #385`, references #1417, WEI-4839, and WEI-4840; required CI, SecurityAgent/non-author review, and GitHub Copilot reviewer gate are required before merge.

## Residual verification

Physical two-device Bluetooth checks remain valuable for transport behavior, but deterministic core tests are the release gate for the failure and ordering invariants in this change. Hardware evidence tracked by #1417/#1423 is not replaced by this work.

Mixed-version behavior intentionally fails safe. A new joiner can consume an older host's empty completion payload, but an older joiner cannot present the pairing-bound snapshot capability required by a new host and will time out rather than receive company data without that authorization proof. The LAN server's authenticated plaintext compatibility path remains for older clients; current clients never choose it after key negotiation fails.
