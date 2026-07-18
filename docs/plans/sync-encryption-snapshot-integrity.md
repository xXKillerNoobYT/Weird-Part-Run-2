# Sync Encryption and Bluetooth Snapshot Completion Integrity

Status: Implementing Bluetooth protocol-v4 authenticated pairing-response transcript (WEI-5192), after transport-stop capability boundary, complete LAN/Bluetooth pairing key failure-state surfacing, and idempotent identity persistence fixes (WEI-4840, WEI-4847, WEI-4855, WEI-5179, WEI-5181, WEI-5182, and WEI-5188; PR #1448; GitHub #385 and #1417); pending exact-head review/CI
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
3. Drain Multipeer's existing FIFO queue through one guarded `PeerManager` actor consumer. Decode and validate each snapshot page in order, buffer it until completion, then apply the entire snapshot in one GRDB transaction so a failed later page rolls back all earlier pages. Quarantine any queued remainder after failure until an explicit retry. A completion envelope may resume onboarding only after the one snapshot transaction commits. Decode/apply/remote-completion failure resumes the pending request with a visible retryable error.
4. Fail closed in both LAN directions: outbound sync requires successful key negotiation and AES-GCM, while the server rejects plaintext, unpaired device identities, arbitrary sender keys, and payload/header device-id mismatches. Pairing persists the peer's X25519 public key in the device registry; current trust and deactivation state are checked on every request. LAN pairing itself uses an ephemeral X25519 key and returns the accepted pairing payload only inside an AES-GCM encrypted wrapper; plaintext accepted responses are invalid.
5. Bind Bluetooth snapshot authorization to the successful pairing session with a random capability token, in addition to requiring a trusted and non-deactivated device registry entry. Reserve the token before transfer to prevent replay/concurrent snapshot duplication. A token is restored only when snapshot batch transfer fails before completion is sent. Once completion is attempted, the token remains consumed even when completion delivery or the later durable-apply acknowledgement fails or times out, preventing replay after rows may have reached the joiner.
6. If the joiner's completion-time atomic apply fails, send `fullSyncApplied(succeeded:false)` before propagating the local error through the FIFO drain. The host consumes that negative acknowledgement immediately, removes the reservation, and records the failed transfer. It does not restore the old capability; an authorized retry requires a fresh pairing-issued capability.
7. Make the protocol-critical platform identity write idempotent. If the add-first Keychain write reports `errSecDuplicateItem`, update the existing matching service/account item with the validated identity and this-device-only accessibility attributes. Any update failure remains visible as `keychainWriteFailed`; there is no ephemeral-key fallback or credential-policy weakening.
8. Give LAN pairing one fail-closed UI transition after `.syncing` begins. Secure-identity load/persistence failures and every encrypted response verification failure (wrapper decode, key derivation, AES-GCM decrypt, response decode, or explicit rejection) must clear stale progress, publish `.error`, retain a user-readable retry message, and rethrow the original error unchanged.
9. Validate the Bluetooth pairing response host key as base64-encoded 32-byte X25519 material before trusted-device registration, sync/company settings, or paired-device flags are persisted. Missing or malformed keys clear pairing progress, publish `.error`, and abort fail closed.
10. Replace Bluetooth protocol-v3 acceptance with an exact protocol-v4 floor and authenticate the complete accepted pairing response. Every attempt generates a fresh cryptographically random request nonce held only in that host-scoped pending attempt. The request proof binds a domain/version, expected host device id, client device id, client X25519 public key, and nonce. The host derives a domain-separated HMAC-SHA256 key from the X25519 shared secret and normalized pairing-code digest, then authenticates a canonical fixed-order, length-prefixed transcript containing the domain/version, request nonce and proof, `accepted=true`, client and host ids/keys, company id, snapshot token, and paired-at value. Any later field trusted by persistence or authorization must also be added to this transcript. Old, missing, malformed, or unknown versions/nonces/proofs fail before the one-time code is consumed; there is no compatibility fallback.

## Design

### Host snapshot pipeline

Add a small deterministic `BluetoothSnapshotTransfer` execution component outside the already-large `PeerManager.swift`. It accepts injected table/page/encode/send operations, returns the sent record count, and throws typed errors. Production adapters remain in `PeerManager` and use GRDB, the existing row-to-JSON conversion, `JSONEncoder`, and `MultipeerManager.send`.

The host sends `fullSyncComplete` only after all snapshot batches succeed. Its payload is a codable completion result (`success`, optional `error`). A success completion is a proposal, not final success: the joiner must return `fullSyncApplied` after durable database application. The host records success only after that acknowledgement. The capability is reserved before the first page and remains consumed once completion delivery is attempted; apply rejection, acknowledgement timeout, and completion-send failure record visible failure without restoring a replayable token. Only pre-completion batch-transfer failure restores the token.

The Bluetooth pairing request advertises exactly protocol version 4, a fresh random nonce, the expected host device id, the joiner's X25519 key, and a pairing proof bound to those values. The response carries the same protocol version, nonce, request proof, client identity/key, the host identity/key, company id, paired-at value, a random snapshot capability, and a response authenticator. Each side persists the other's key for later LAN sync only after transcript verification. The joiner returns the capability in `fullSyncRequest`; the host requires an exact capability match plus a trusted/non-deactivated registry row and binds the pairing request identity to the Multipeer session's advertised device id. This prevents a nearby peer from obtaining a snapshot by merely spoofing a known device id.

The response authenticator is HMAC-SHA256 under a domain-separated key derived from the ephemeral X25519 shared secret and normalized pairing-code digest. The MAC input is not JSON: it is a canonical fixed-order sequence of fields, each encoded as an explicit-width length prefix followed by its UTF-8/binary bytes. The transcript binds every trust-bearing field: domain/version, request nonce, request proof, accepted value, client device id/key, host device id/key, company id, snapshot token, and paired-at. Any future accepted-response field used by persistence or authorization must be added to the transcript before that field is trusted.

Bluetooth pairing validates the exact protocol, request nonce, expected host id, client key, and bound request proof before atomically consuming the one-time code. Invalid, old, or malformed requests therefore do not consume a fresh offer. After consumption, the host snapshots the exact previous device-registry row and hosted capability, prepares the new trust and token, finalizes every accepted response field, and only then generates the response authenticator. Authenticator-generation or delivery failure follows the same preparation rollback: restore the exact prior trust/token state and pairing offer, and never send an accepted unauthenticated response. Concurrent/duplicate requests can therefore produce at most one accepted response.

The joiner permits one pending pairing attempt per expected host. It removes that pending context on success or failure and verifies, in order, the exact protocol version, exact pending nonce, expected host id, client identity/key echo, structurally valid X25519 keys, request-proof echo, and response authenticator using constant-time comparison. These checks complete before `registerPeerDevice`, received snapshot-token storage, company/settings persistence, or any paired flag. A response from a prior attempt has a different nonce and is rejected before trust or persistence; a duplicate response has no pending context and cannot re-authorize. No persistent replay table is needed for this bootstrap transcript because the host's atomic one-time-code consumption is the request single-winner boundary and the joiner's per-attempt nonce/context is the response replay boundary.

### LAN authenticated pairing and traffic

Pairing is the only bootstrap exception to prior trust. The joiner keeps the manual 8-character UX but no longer transmits the one-time code in LAN plaintext. Instead, it sends a domain-separated pairing proof over `device_id` and its X25519 public key. The host verifies that proof against the active normalized code, atomically consumes the code, persists the joiner's key as trusted, and AES-GCM encrypts the accepted `SyncPairResponse`.

The accepted response key is derived from the X25519 shared secret with the pairing-code digest as HKDF salt and a domain-separated transcript containing both client and server X25519 public keys. The response also authenticates those identities as AES-GCM AAD. A spoof server that does not know the one-time code cannot produce a decryptable accepted response, and a captured proof cannot be replayed after the host consumes the pairing code once.

Each device's own X25519 identity is persistent across `PeerManager` and LAN server restarts. Production uses platform secure storage (Keychain where available) with a SwiftPM-compatible fallback for test hosts; tests can inject deterministic in-memory identities. Private X25519 keys are never stored in normal SQLite sync settings.

The Keychain writer uses add-first persistence so a clean install creates the item with the intended accessibility class. A duplicate add is completed with `SecItemUpdate` against the same class/service/account/synchronizable match query. The duplicate branch is covered through an internal status seam so SwiftPM tests can prove update success and update-error propagation without reading or mutating a developer machine's real Keychain.

After pairing, `/sync/key`, `/sync/push`, and `/sync/pull` bind `X-Device-ID` and the advertised sender key to the active trusted registry record. Missing or partial encryption headers, arbitrary keys, deactivated peers, request-body device mismatches, and wrong-company requests fail before JSON decoding, sync reads, or mutations. Discovery without a pairing-bound key may refresh metadata but never creates trust or reactivates a revoked peer.

Encrypted `/sync/push` and `/sync/pull` requests include a unique request id. AES-GCM AAD binds endpoint, direction, sender device id, and request id; responses use the same request id with `direction=response`, so request/response reflection and cross-endpoint substitution fail authentication. The server reserves request ids in `_sync_replay_guard` inside a SQLite transaction after decryption but before JSON decode, inbox mutation, or outbox reads. Exact replay returns `replay_detected`, and the unique primary key makes concurrent reservation durable and single-winner. Reservations are permanent database security state: age-based deletion is forbidden because it would make captured ciphertext fresh again. If storage compaction is needed later, it must first add an authenticated monotonic sequence/high-water design.

### Joiner ordering

`MultipeerManager` already stores received messages in a serial FIFO queue. Its callback schedules an actor-isolated drain rather than independently processing the callback argument; an explicit in-progress guard prevents actor reentrancy from starting a second consumer while the first is suspended. The drain pops messages until empty and awaits each message. Snapshot `changes` pages decode and validate into a per-peer buffer; `fullSyncComplete` applies that complete buffer through one atomic `ConflictResolver` transaction before resolving the continuation. If any page or final apply fails, the buffer is discarded and remaining queued pages/completion are ignored until retry. A completion-time apply failure first sends a negative durable-apply acknowledgement so the host releases its reservation without waiting for the timeout, then the drain fails the joiner's continuation and quarantines queued remainder. Completion therefore cannot overtake durable database application or leave a partially committed snapshot.

### Error and retry behavior

The existing `requestFullSyncOverMultipeer` API remains throwing. Send, decode, apply, remote-host, transport-shutdown, and timeout failures are surfaced to onboarding; a caller can retry the same operation. Continuations are removed before resume so late completion/timeout messages cannot double-resume. Stopping either Multipeer path explicitly fails every pending pairing and full-sync continuation.

`IOSSyncManager.pairWithShop` owns the visible LAN pairing state transition. Once it enters `.syncing`, identity acquisition and encrypted-response verification run inside one throwing boundary. Its catch path does not replace, downgrade, or recover from the underlying security error: it only clears the progress label, moves the manager to `.error`, publishes a fixed user-readable message (with a specific secure-identity diagnostic where applicable), logs the failure, and rethrows the same error.

## Dependency map

- `PeerManager.syncViaHTTP` -> `resolveSharedKey` -> `SyncCrypto` (LAN confidentiality/correctness)
- `PeerManager.handleFullSyncRequest` -> `BluetoothSnapshotTransfer` -> GRDB reads/row encoding -> `MultipeerManager.send`
- `MultipeerManager.receiveQueue` -> `PeerManager.drainMultipeerMessages` -> `ConflictResolver` -> GRDB commit -> full-sync continuation
- `PeerManagerTests` validates crypto propagation, host fault classes, capability reservation/acknowledgement, ordered durable apply, transport shutdown, and apply-failure visibility
- `SyncServerTests`/`SyncIntegrationTests` validate encrypted paired traffic plus plaintext, unpaired-key, identity, certificate, and company rejection

## Acceptance criteria and evidence

- Missing/malformed/unauthorized key exchange, invalid keys, and AES-GCM failures throw; no plaintext downgrade or ciphertext-as-JSON fallback.
- A pairing response with a missing or malformed shop key clears active progress and leaves `IOSSyncManager` in a visible `.error` state before throwing.
- A Bluetooth pairing response with a missing, malformed, or wrong-length host key is rejected before trusted-device/settings persistence; valid 32-byte X25519 public keys preserve the existing success path.
- A valid Bluetooth protocol-v4 request/response transcript authenticates successfully and preserves the current pairing and snapshot path. Missing/old/unknown versions fail closed with an update-both-devices/re-pair diagnostic; there is no downgrade path.
- Forged accepted responses, wrong code or key, missing/malformed MAC, and tampering of host id/key, client id/key, company id, snapshot token, nonce, request proof, version, accepted value, or paired-at are rejected before trusted-device, settings/company, received-token, or paired-state mutation.
- Replaying a valid response into a fresh attempt with a different nonce is rejected. Duplicate/old requests cannot produce a second accepted response or consume a fresh pairing offer incorrectly; completion or failure removes the joiner's pending context.
- Secure-identity acquisition plus encrypted pairing wrapper decode, shared-key derivation, AES-GCM decrypt, accepted-response decode, and explicit rejection all clear active progress and leave `IOSSyncManager` in a visible `.error` state while preserving the original thrown error.
- LAN pairing never sends the one-time code in plaintext; accepted responses require the pairing-code-authenticated client/server X25519 transcript.
- Device X25519 identity survives `PeerManager`/server restart through secure platform storage or deterministic injected test storage, never through normal sync settings.
- Duplicate Keychain identity writes update the existing matching item; failed updates surface the exact OSStatus through `keychainWriteFailed` rather than rotating silently or continuing with an unpersisted identity.
- Encrypted LAN push/pull rejects exact replay before a second read or mutation, including after restart and beyond the former seven-day retention horizon; rejects cross-endpoint/direction substitution through AAD; and binds encrypted responses to the originating request id.
- Host table enumeration, page read, row conversion, batch encoding, batch send, and completion-send failures cannot produce a successful transfer result.
- Joiner processes FIFO batches serially and only completes after prior database application; completion-time apply failure sends a negative acknowledgement before throwing, immediately releases the host reservation, leaves the old capability consumed, and permits only a freshly paired authorized retry.
- Focused `PeerManager`/sync/crypto tests pass, including encrypted LAN pairing, plaintext/partial-header rejection, arbitrary/deactivated peer rejection, successful trusted encrypted push/pull, undelivered Bluetooth pairing rollback, atomic code reservation, and capability replay/restoration boundaries.
- Full `core` suite passes (2,405 Swift Testing tests plus 21 XCTest tests on 2026-07-15).
- `WiredPart-iOS` builds for iPhone 17 / iOS 26.5 Simulator.
- Current-main PR includes `Closes #385`, references #1417, WEI-4839, WEI-4840, and WEI-4847; required CI, SecurityAgent/non-author review, and GitHub Copilot reviewer gate are required before merge.

## Residual verification

Physical two-device Bluetooth checks remain valuable for transport behavior, but deterministic core tests are the release gate for the failure and ordering invariants in this change. Hardware evidence tracked by #1417/#1423 is not replaced by this work.

Mixed-version behavior intentionally fails safe and is explicit at pairing. Bluetooth protocol version 4 is the exact supported floor and wire version: old, missing, or unknown versions are rejected before code consumption or persistence with an update-both-devices diagnostic. There is no v3 fallback or rolling mixed-version onboarding. Both devices must update together and re-pair so a fresh nonce, transcript-authenticated host response, pairing-issued capability, and persisted X25519 identities are established. The LAN server likewise no longer accepts plaintext sync payloads.
