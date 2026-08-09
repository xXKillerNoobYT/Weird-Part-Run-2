# Bluetooth server-free sync — verification checklist

> **Owner directive 2026-08-06:** *"lets get the Bluetooth syncing done — if
> Bluetooth is working and syncing and joining a company is working for the
> server-free offline use... updating the Wi-Fi is a convenience thing, not
> blocking users."* Plus: **"Bluetooth is required"**, **"Wi-Fi is convenient."**
>
> This is the acceptance definition for the offline-first hero claim. Every row
> states what must be true, where the code enforces it, and the **real log line**
> that proves it at runtime. Log strings below are copied from source, not
> invented — grep them to confirm.

**Scope:** two devices, aeroplane-mode-with-Bluetooth-on, no Wi-Fi, no server,
no internet. That is the electrician on a job site with no signal, which is the
core user.

---

## The rule this checklist encodes

**Bluetooth is REQUIRED. Wi-Fi is OPTIONAL and only makes it faster.**

Any screen, error, or empty state that tells the user they need Wi-Fi is a bug.
Any code path that *requires* a LAN to complete pairing or sync is a bug.

---

## Stage A — the Bluetooth transport actually starts

| # | Must be true | Code | Log evidence |
|---|---|---|---|
| A1 | Advertising + browsing start on `startPeerSync` | `PeerManager.swift` — `MultipeerManager(...)` then `mpManager.start()` | no error line from A3 |
| A2 | `serviceType` matches the declared Bonjour services | `MultipeerManager.serviceType = "wiredpart-sync"`; `Weird-Parts-IOS-Info.plist` declares `_wiredpart-sync._tcp` **and** `._udp` | — (static; verified 2026-08-06) |
| A3 | A refused start is REPORTED, never swallowed | `didNotStartAdvertisingPeer` / `didNotStartBrowsingForPeers` → `onTransportError` → `recordTransportError` | `[PeerManager] Bluetooth transport did not start: <reason>` |
| A4 | The reason reaches the UI, not just the log | `PeerManagerState.lastTransportError` | surfaced in state; **UI binding still TODO — see Gaps** |

**Red proof for A3:** deny Local Network permission in Settings, start discovery,
confirm the log line appears with the OS reason. Before #1667 this produced
*nothing at all* — both callbacks were unimplemented, which is why four builds
of fixes could not find the cause.

---

## Stage B — the host is discovered

| # | Must be true | Code | Log evidence |
|---|---|---|---|
| B1 | Host advertises identity | `startAdvertising()` publishes `device_id`, `device_name`, `company_id` | peer appears in Nearby Devices |
| B2 | Joiner may browse before it has a company | `allowAnyCompanyPeerDiscovery` bypasses the company filter | peer row visible pre-join |
| B3 | Self is excluded | `guard peerDeviceId != self.deviceId` | own device never listed |

---

## Stage C — the MCSession connects  ← **the bug fixed in #1667**

| # | Must be true | Code | Log evidence |
|---|---|---|---|
| C1 | A discovered peer SURVIVES a failed connection | `.notConnected` sets state `.found`; **never** removes | peer stays in the list after a failed attempt |
| C2 | Only `lostPeer` removes a peer | `browser(_:lostPeer:)` | peer disappears only when genuinely out of range |
| C3 | One re-invite fires when the first invitation lapses | `awaitMultipeerConnection` | `[PeerManager] Re-invited <id8> — first invitation lapsed without connecting` |
| C4 | Host accepts a not-yet-in-company joiner while a code is offered | `acceptAnyCompanyForPairing`, set by `IOSSyncManager.issueShopPairingCode` | connection reaches `.connected` |

**C3 is the tell.** If the log shows `Re-invited` and the connection still never
forms, the transport is genuinely failing — check Stage A. If `Re-invited` never
appears at all on a failed join, the peer record was lost (the #1580 regression).

**Red proof for C1:** restore `peers.removeValue(forKey: key)` in the
`.notConnected` branch → `testNotConnectedKeepsDiscoveredPeer` fails. Verified
2026-08-06.

---

## Stage D — joining a company over Bluetooth

| # | Must be true | Code | Log evidence |
|---|---|---|---|
| D1 | Code + proof exchanged over the BT session, no HTTP | `PeerManager.pairViaMultipeer` | — |
| D2 | Wrong/used code is rejected | proof check | `[PeerManager] Bluetooth pairing rejected — invalid or already consumed code` |
| D3 | Tampered identity/key/version rejected | nonce + proof binding | `[PeerManager] Bluetooth pairing rejected — invalid identity, key, or protocol version` |
| D4 | Forged host response rejected | response authentication | `[PeerManager] Bluetooth pairing rejected — response authentication failed` |
| D5 | Success is durable on both sides | commit before accept | `[PeerManager] Bluetooth pairing committed + accepted for peer <id8>` |
| D6 | An undelivered acceptance does NOT burn the code | host state restored | `[PeerManager] Bluetooth pairing accepted response undelivered — host state restored and code kept for retry` |
| D7 | Joiner adopts the host's company id | `IOSSyncManager.pairWithPeerOverBluetooth` writes `company_id` | both devices share one company |

D2–D4 are the security gates — they must stay loud. D6 is the usability gate:
a dropped reply must not force the user to generate a new code.

---

## Stage E — the new device receives the whole company

| # | Must be true | Code | Log evidence |
|---|---|---|---|
| E1 | Host sends a full snapshot after pairing | `requestFullSyncOverMultipeer` | `[PeerManager] Sent full Bluetooth snapshot (<n> records); awaiting durable apply acknowledgement from <id8>` |
| E2 | Joiner applies it durably before acknowledging | apply-then-ack ordering | `[PeerManager] Joiner durably applied full Bluetooth snapshot for <id8>` |
| E3 | Untrusted peers cannot request a snapshot | trust check | `[PeerManager] Rejected full Bluetooth snapshot request from untrusted peer <id8>` |
| E4 | Incremental pushes wait for the snapshot ack | ordering guard | `[PeerManager] Deferring incremental push to <id8> — initial snapshot not yet acknowledged` |
| E5 | Live progress is visible during the snapshot | `state.snapshotReceivedRecords` | UI shows a moving count |
| E6 | Duplicate in-flight requests are ignored | idempotency guard | `[PeerManager] Ignored duplicate in-flight snapshot request from <id8>` |
| E7 | Stale/mismatched acks are rejected | nonce match | `[PeerManager] Ignored stale or mismatched snapshot acknowledgement from <id8>` |

**E1→E2 is the pair that proves a real join.** Seeing E1 without E2 means the
data left the host and never landed — treat as data loss, not a slow sync.

---

## Stage F — ongoing sync over Bluetooth

| # | Must be true | Code | Log evidence |
|---|---|---|---|
| F1 | Changes route over Multipeer when `transport == "multipeer"` | `syncWithPeer` BT branch | — |
| F2 | A failed send is a FAILURE, never silent success | `guard mpManager.send(...) else { throw .sendFailed }` | sync result shows the error |
| F3 | Sync tapped mid-connect waits instead of erroring | `awaitMultipeerConnection` before the guard | *"Still connecting to <name> over Bluetooth — try again in a moment."* |
| F4 | Untrusted peers cannot push changes | trust check | `[PeerManager] Rejected changes from untrusted peer <id8>` |
| F5 | Legacy unsigned payloads rejected | legacy guard | `[PeerManager] Rejected legacy changes payload from untrusted peer <id8>` |

---

## Stage G — Wi-Fi is never required

| # | Must be true | Status |
|---|---|---|
| G1 | No copy tells the user Wi-Fi is needed | **FIXED 2026-08-06** — `IOSDeviceManagementPage` help text and pairing-code sheet now say Bluetooth is required and Wi-Fi only makes it faster |
| G2 | Pairing completes with Wi-Fi off | code path is BT-only (Stage D); **needs hardware confirmation** |
| G3 | Snapshot + incremental sync complete with Wi-Fi off | Stages E/F are BT-only; **needs hardware confirmation** |
| G4 | A multipeer-only peer never falls through to HTTP | guarded — HTTP on a multipeer peer could only throw `badURL (-1000)`, the raw error previously seen from Nearby Devices | 

---

## Stage H — logs replicate to every device (the beta diagnostic loop)

> **Owner directive 2026-08-06:** *"Now that we are moving into beta we want to
> do that end to end — that's why we want to sync logs, so all devices have all
> the logs so you can check them when synced."*

This is what makes beta diagnosable: a failure on the owner's phone becomes
readable from any other device once they sync, with no cable, no Console.app,
and no shipping a build to reproduce.

**Verified wired end-to-end on 2026-08-06:**

| # | Must be true | Where | Evidence |
|---|---|---|---|
| H1 | `device_logs` table exists | migration `121_device_logs` | `AppDatabase+Migrations.swift:6295` |
| H2 | Change triggers installed for INSERT/UPDATE/DELETE | same migration | `trg_sync_device_logs_*` |
| H3 | Migration 121 is actually **registered** | `registerMigration121DeviceLogs(&migrator)` | line 165 — chain 119 → 120 → 121 intact and in order |
| H4 | The table is in the sync allowlist | `ConflictResolver.allowedSyncTables` | line 228 |
| H5 | Logs replicate like company data | test | *"Logs REPLICATE — writes are change-tracked like company data"* |
| H6 | One device can read another's logs | test | *"Fleet view: one device reads another device's synced-in logs"* |
| H7 | Secrets never reach a replicated row | `DeviceLogService.redact` applied in `log()` before insert | test: *"Secrets never reach a replicated log line"* |
| H8 | Old entries self-clean | 30-day prune | test: *"Prune removes entries past the retention window"* |

**Why H3 mattered:** migration 119 froze its table list before `device_logs`
existed, so 119 could never install these triggers — 121 exists precisely to
cover that. A defined-but-unregistered migration would have left the table
allowlisted yet never change-tracked, i.e. logs that look configured and
silently never replicate. Registration confirmed at line 165.

**H7 is a disclosure boundary, not tidiness.** Replicated logs land on every
company device, so redaction must happen *before* the row is written, and there
must be exactly one redactor — a second implementation that drifts is a leak.

**Remaining for Stage H:** confirm on hardware that a log written on device A is
readable on device B after a Bluetooth-only sync. Everything above is verified by
code and automated tests; the cross-device hop needs the two real devices.

---

## Gap status — updated 2026-08-09

Every gap this audit found now has an outcome. **Fixed** means merged to `main`;
**tracked** means it has a GitHub issue and is not lost.

| # | Gap | Status |
|---|---|---|
| 1 | `lastTransportError` not shown in the UI | **FIXED** — #1669 binds it into the Nearby Devices empty state with stable codes (`BT-ADV-START`, `BT-SCAN-START`); #1676 extends it to the Join a Business screen |
| 2 | Bluetooth sync one-directional per tap | **Wording FIXED** (#1674 — rows say "Send Changes", history no longer claims a two-way sync). **Behaviour tracked** in #1684 — `pulled` still stays `0`; whether to make it symmetric is a product decision |
| 3 | Snapshot flow control | **FIXED** — #1680 paces batches and retries a transient send instead of aborting the whole transfer |
| 4 | Joiner buffers the whole snapshot in memory | **TRACKED — #1683.** Unbounded memory plus all-or-nothing with no resume. A jetsam kill here looks identical to a transfer failure, so this is a plausible second cause of the build-62 stall |
| 5 | Orphaned database dead-ends on `SQLITE_NOTADB` | **FIXED** — #1672 adds non-destructive wrong-key detection (`isCipherKeyMismatchError`) and an archive-and-re-pair path. The file is never silently deleted |
| 6 | `NSBluetoothPeripheralUsageDescription` absent | **Not a defect** at the current deployment target — iOS 12 and earlier only. Recorded so it is not rediscovered |
| 7 | Stage G / H need real hardware | **OPEN — owner action.** Code and the automated suite cannot close these; two devices with Wi-Fi genuinely off can. See the 10-minute pass below |

### What the field evidence proved (build 62, 2026-08-07)

The chain reaches much further than when this document was written:

```
discover ✅ → connect ✅ ("iPhone connected") → pair ✅
   → snapshot transfer STARTS ✅ ("Downloading data over Bluetooth…")
   → stalls ~25% ❌
```

Connect and pair are **solved and field-confirmed**. Everything merged after
build 62 — #1667, #1669, #1671, #1680 — is **untested on hardware**, because no
build has shipped since. Cutting one is the highest-value single action
available.

---

## How to verify on hardware (the 10-minute pass)

1. Both devices: Wi-Fi **off**, Bluetooth **on**, cellular off.
2. Host: Settings → Device Management → **Pair New Device** → code appears.
3. Joiner: onboarding → **Join Existing Business** → host appears (Stage B).
4. Enter the code → watch for Stage D logs → expect D5.
5. Watch the snapshot count move (E5), expect **E1 then E2**.
6. Make a change on each device, tap **Send Changes** on each, and confirm both
   converge (Stage F). A single Bluetooth action sends only this device's
   pending changes; the UI now says so explicitly.
7. Pull device logs and confirm the exact strings above.

Any failure: capture the log line and match it to the row here. The row names
the code that owns it.

---

## Cross-references

- #1580 — pairing failure; root cause + fix (#1667)
- #1417 — offline server-free sync umbrella
- #1645 — sync-system audit umbrella (26 findings)
- #1423 — hardware-gated checks awaiting owner device time
- `core/Sources/WiredPartCore/Sync/MultipeerManager.swift`, `PeerManager.swift`
- `Weird Parts IOS/Weird Parts IOS/Sync/IOSSyncManager.swift`
