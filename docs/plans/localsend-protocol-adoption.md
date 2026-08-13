# LocalSend Protocol Adoption — session model, integrity, and the Wi-Fi fast lane

**Status:** APPROVED · **Created:** 2026-08-13 · **Owner approval:** 2026-08-13 in chat — *"if it looks like it has a good chance of doing proper update to our syncing method … hell yeah. Let's apply it."*
**Reference:** [LocalSend](https://github.com/localsend/localsend) (Apache-2.0) and its published [Protocol v2.2 spec](https://github.com/localsend/protocol)
**Builds on:** #1685 (durable staging, merged), `docs/plans/bluetooth-snapshot-resume.md` (#1695, transfer identity — PLANNED)
**Feeds:** #1712/#1713 (token-policy decision), #1417 (sync umbrella)

---

## Why this document exists

The owner pointed at LocalSend as a possible source for the sync system. We evaluated it (2026-08-13). Verdict: **it cannot replace our sync — it has no Bluetooth at all and transfers files, not databases — but its protocol design validates and extends the direction we are already on.** This document records what we adopt, what we explicitly reject, and the license terms, so nobody re-litigates it.

### License

LocalSend is **Apache License 2.0**: copying, modification, and commercial use are permitted. Conditions: retain attribution, state changes, include the license text with any redistributed portions. Their code is Flutter/Dart, so nothing is copied line-for-line into our Swift codebase — what we adopt is **protocol design**, guided by their published spec. If any wire-format text or documentation is ever copied verbatim, add a NOTICE entry crediting LocalSend under Apache-2.0. Design adoption alone carries no obligation, but credit them in this plan regardless: this design is informed by LocalSend Protocol v2.2.

### What we explicitly do NOT adopt

- **Their transport.** LocalSend is LAN/Wi-Fi-only; its developers have repeatedly declined Bluetooth (their issues #144, #427). Our Bluetooth path is non-negotiable (owner 2026-08-10) and stays on Apple Multipeer Connectivity.
- **File-transfer semantics.** LocalSend has no change log, no merge, no conflict resolution, no apply-then-acknowledge. All of that stays ours, exactly as merged.
- **Their HTTP-only trust model** for the Bluetooth lane. Our pairing proof, x25519 pins, and one-time snapshot capability are stronger than LocalSend's fingerprint-remembering and stay as designed.

---

## Owner decisions recorded 2026-08-13 (chat) — transport hierarchy

The owner's words, condensed into rules; each is load-bearing for the phases below.

1. **Bluetooth is for finding each other and pairing.** Discovery/pairing must never require any network.
2. **Slow sync is acceptable.** Job-site meetings run 15–30+ minutes; incremental updates are megabytes. No total-elapsed deadline is ever justified by impatience (re-affirms the #1703 idle-based design).
3. **Peer-to-peer Wi-Fi is the preferred speedup:** *"if it taps into the Wi-Fi and uses Bluetooth to pair and then uses non-networked Wi-Fi signals — absolutely fine with that."* This is precisely what Multipeer Connectivity does today (Bluetooth discovery + AWDL peer-to-peer Wi-Fi data path, no router, no hotspot). **The current architecture already implements the owner's ideal.** No new work is required to satisfy this — it is the default whenever both radios are on.
4. **Hotspot is an OPTIONAL speedup, never a requirement.** *"Not turning on the hotspot is the preference … having to turn on the hotspot will be acceptable, but I'd prefer if that is an optional speedup."* Any screen, error, or doc implying a hotspot (or any Wi-Fi) is *needed* is a bug — same class as the Bluetooth-required rule.

Resulting transport ladder, fastest first, all reaching the same sync protocol:

| Lane | Radio reality | Status |
|---|---|---|
| A. Same LAN (shop/office) | Infrastructure Wi-Fi both ends | Phase 2 (below) — LocalSend-style HTTP lane |
| B. Peer-to-peer Wi-Fi (field) | BT pairs, AWDL carries data — **no network** | **Already shipped** (Multipeer default) |
| C. Hotspot | One device shares, others join | Optional speedup; document only (Phase 3) |
| D. Bluetooth-only | BT pairs *and* carries data | **The guaranteed floor.** Slow is fine |

---

## Phase 1 — NOW: session model deltas onto #1695

#1685 already gave us durable staging; #1695 already designs the per-attempt identity (`transfer_id` ≡ LocalSend's `sessionId`), resume handshake, contiguity, and windowed acks. **#1695 is the implementation vehicle — do not fork a second protocol PR** (that is how #1690/#1691 died). LocalSend's cross-check adds exactly three deltas, to be folded into #1695's item list:

### 1a. Snapshot manifest — accept before any data moves

LocalSend's `prepare-upload` sends metadata first; the receiver explicitly accepts or rejects, and per-file tokens exist only after acceptance. Our equivalent, host→joiner, sent immediately after `FullSyncRequest` and before frame 1:

```
SnapshotManifest {
  transferId          // the #1695 identity, minted here
  expectedRecords     // total rows
  expectedBytes       // total payload size
  tableCounts         // per-table row counts (diagnostic gold for "what did I not get")
  companyName         // what the user is about to receive
  snapshotChecksum    // SHA-256 over the full payload stream (see 1b)
}
```

The joiner checks the manifest against the #1688 caps and its own free disk **before** staging begins, and rejects with a typed, on-screen reason (`SNAP-TOO-BIG`, `SNAP-NO-SPACE`) instead of discovering the ceiling mid-transfer. Acceptance is the joiner's explicit reply; the host streams nothing until it arrives. This also gives the progress UI a real denominator — today percent-complete is guesswork.

### 1b. Integrity checksums — per batch and whole-snapshot

LocalSend carries `sha256` per file and receivers respond 422 on mismatch. Multipeer's `.reliable` mode protects bytes *in flight*, but #1695 makes staged rows live on disk **across process restarts and up to a 24 h TTL** — transport integrity says nothing about that window, and a resumed transfer must prove the old rows still match what the host sent.

- Each frame carries `SHA-256(payload)`; the joiner verifies **on receipt**, before the row is staged. Mismatch = typed failure (`SNAP-CORRUPT-FRAME`), transfer fails toward restart — never stage a frame you couldn't verify.
- `_snapshot_staging` stores the frame checksum. At apply time (and especially at **resume** time), replay re-verifies each staged row against its stored checksum, and the assembled stream against the manifest's `snapshotChecksum`, inside the existing `validate:`-in-transaction rule. A resumed transfer that fails re-verification discards staging and requests a fresh `transfer_id` — one restarted transfer beats one silently mixed company.
- Migration note for #1695's migration 123: add `payload_sha256 TEXT NOT NULL` to `_snapshot_staging` and `snapshot_sha256 TEXT` to `_snapshot_transfer` while the tables are already being touched — one migration, not two.

### 1c. `transfer_id` becomes the correlator — feeds the #1712/#1713 decision

The retracted #1703 review and the real #1713 defects share one root: the one-time capability token doubles as the only correlator for acks and timeouts. LocalSend never does this — `sessionId` correlates, tokens authorize, and the two are separate values with separate lifetimes. Adopt that separation as a rule:

> **The token authorizes; the `transfer_id` identifies.** Acknowledgements, timeout timers, retries, and `lastPeerSyncs` entries key on `transfer_id`. The capability token appears exactly twice: minted at pairing, checked at reservation. No matcher may use it as an identity.

This does not pre-empt the #1712/#1713 owner decision on *when* the token is consumed vs restored — but it removes the entire class of "stale timer/ack matches the wrong attempt" bugs regardless of which way that decision goes, and it is the design under which #1713's deferral guard becomes expressible correctly ("initial snapshot not durably applied for the *current transfer*" instead of "token outstanding").

### Phase 1 acceptance (additive to #1695's)

- A manifest precedes frame 1 on every snapshot; the joiner's accept/reject is explicit and its reject reasons reach the screen with codes
- A frame with a wrong checksum never enters `_snapshot_staging`
- A resumed transfer re-verifies every previously staged row before applying; a tampered/rotted row forces a fresh transfer, never a mixed apply
- No matcher anywhere in `PeerManager` keys on the capability token — mutation test: change a matcher to token-keying and a test must go RED

## Phase 2 — AFTER the Bluetooth exit condition passes on hardware: LAN fast lane

Once (and only once) the #1681 exit condition — full snapshot over Bluetooth with Wi-Fi off on both devices — passes on real hardware, add lane A: when both devices sit on the **same infrastructure network** (the shop, the office), discover and sync over it, LocalSend-style, at LAN speed.

Design basis is LocalSend Protocol v2.2, adapted:

- **Discovery:** UDP multicast announce on a fixed port, with their *HTTP-fallback sweep* pattern when multicast is filtered (their dual-discovery idea is the part worth copying most). iOS caveat, known in advance: UDP multicast on iOS requires the `com.apple.developer.networking.multicast` entitlement, which needs an Apple approval request — file for it early or lead with the fallback sweep.
- **Transport:** HTTPS with self-signed certs; device identity = the existing x25519 pins, not LocalSend's cert-hash fingerprints (ours are already stronger and already synced).
- **Session/auth:** the same manifest → accept → per-batch checksum → durable staging → apply-then-ack protocol from Phase 1, unchanged — the lane changes, the protocol must not. Pairing still happens over Bluetooth per owner decision 1; the LAN lane is transport for *already-paired* devices only.
- **Not a server:** both ends are peers, exactly as today. No standing daemon beyond an in-app listener while the app is foregrounded/syncing.

Scope note: this is deliberately NOT in Phase 1. The field-site speedup (lane B) already exists via Multipeer; lane A only helps the same-LAN case, which is not the hero scenario. It earns its build only after the floor is proven.

## Phase 3 — docs only: the optional hotspot flow

One page in the user docs / troubleshooting: *"Big first sync and no Wi-Fi around? One person can turn on Personal Hotspot and the others join it — the sync then runs at Wi-Fi speed with no internet needed. Entirely optional: Bluetooth alone will finish on its own."* Framed exactly per owner decision 4 — an optional speedup, never a requirement, never an error remedy. (LocalSend's docs use the same framing for their no-Wi-Fi answer; that framing is the thing being borrowed.)

## What this plan supersedes / must not regress

- Nothing is superseded: #1695's design stands and gains items 1a–1c; #1685/#1688 guarantees stay byte-for-byte (apply-then-ack, single-transaction replay, caps per peer *and* per transfer, fail-closed pre-staging clear, post-commit counters).
- The #1690/#1691 lesson is inherited verbatim: **build on the merged staging layer; any PR that rewrites it instead of extending it gets closed unread.**
- Bluetooth-only remains the supported floor (owner 2026-08-10). Idle-based timeouts only (#1703). Every failure reaches the screen with a code (#1669/#1693).

## Tracking

- Phase 1 → folded into **#1695** (comment dated 2026-08-13 lists 1a–1c); implementation PRs reference #1695 and this plan
- Phase 2 → its own issue, filed 2026-08-13, blocked-by note pointing at the exit condition
- Phase 3 → checklist item on the Phase 2 issue (same docs pass)
- Token-policy decision → stays on **#1712/#1713**; section 1c is input to it, not a resolution of it
