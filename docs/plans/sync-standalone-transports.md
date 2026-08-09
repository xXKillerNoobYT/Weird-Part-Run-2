# Sync — Standalone Transports (Wi-Fi alone AND Bluetooth alone)

> Owner requirement (chat, 2026-08-03): *"wifi & bluetooth standalone"* — pairing,
> initial snapshot, and ongoing sync must each complete over EITHER transport
> ALONE: Bluetooth-only (Wi-Fi radio off or unavailable) and Wi-Fi-only (no BT).
> Field context: the owner's shop and job sites include no-connectivity
> environments (electricians-first, offline-first); either radio may be the
> only one available. Gap analysis first posted to #1417 on 2026-08-03.
>
> Status: PLAN — implementation follows owner-visible baseline confirmation of
> build 46's join fix (the #1633 field test). Builds on the shipped fixes
> #1616 (transport fallback), #1621 (idle watchdog + live progress), #1625
> (push ordering), #1633 (id-less table skip).

## 1. Current architecture (what actually carries what)

| Function | Today's transport | Standalone-BT? | Standalone-WiFi? |
|---|---|---|---|
| Discovery ("Shop Computer Found") | Multipeer advertising — BT assists, AWDL announces | YES (BT) | PARTIAL (AWDL needs Wi-Fi radio ON; true LAN Bonjour exists in PeerDiscovery but the join UI lists Multipeer peers first) |
| Pairing code exchange | Multipeer session (code-authenticated proof) | YES — small payloads ride BT | YES over AWDL/LAN |
| Initial full snapshot | Multipeer session frames (BluetoothSnapshotTransfer pager) | UNVERIFIED — MCSession falls back to BT with Wi-Fi off but throughput drops to ~kB/s; a real company DB may take minutes-to-tens-of-minutes | YES (AWDL); LAN/HTTP path also exists (SyncEngine.runInitialSync) but needs a server address |
| Ongoing incremental sync | Multipeer push (change-log) + LAN HTTP when address known | Same as snapshot | YES |

**Key uncertainty to KILL FIRST (task T1):** does MCSession actually establish and
carry data with the Wi-Fi radio hard-off on both devices on iOS 26? Apple documents
BT fallback, but its reliability and the practical snapshot throughput ceiling must
be measured on the owner's real iPhone+iPad pair, not assumed.

## 2. Design

### 2.1 Transport preference ladder (per operation, automatic)
1. **AWDL/Multipeer with Wi-Fi radio on** — fastest, current happy path.
2. **LAN/HTTP** when a server address is known (same network) — fast, already built.
3. **Bluetooth-only Multipeer** — slow lane: permitted for pairing + snapshot with
   explicit UX ("This can take a while over Bluetooth — keep both devices close
   and awake"), chunk sizes tuned down (batchSize 50 vs 200), and the #1621 idle
   watchdog's moving-transfer tolerance doing the timeout work.

The #1616 fall-through pattern generalizes: every sync operation walks the ladder
top-down and reports which rung it used (the "Wi-Fi didn't work — downloading over
Bluetooth instead…" line becomes a general transport banner).

### 2.2 Wi-Fi-only (no BT) — discovery is the gap
- Join screen adds LAN discovery: browse `_wiredpart._tcp` via Bonjour
  (PeerDiscovery plumbing exists) alongside Multipeer results, merged into one
  "nearby devices" list (IOSSyncManager already merges peer sources for display).
- Manual-address entry (already in the join UI) remains the last-resort rung.

### 2.3 BT-only (no Wi-Fi radio) — throughput honesty is the gap
- Detect the radio state (NWPathMonitor probe from #1581's wifiRadioLooksOff())
  and preemptively set expectations in the UI before the user waits.
- Snapshot batches shrink (50 rows) so the idle watchdog sees steady progress;
  the #1621 live counter gives the user visible movement.
- If measured BT throughput makes a full snapshot impractical (>20 min for the
  owner's dataset), surface an honest recommendation: "Bluetooth-only sync will
  take about N minutes. Turning Wi-Fi ON on both devices (no network needed)
  makes this much faster." — never silently churn.

## 3. Field-test matrix (owner devices, one pass each after implementation)
| # | Host | Joiner | Expectation |
|---|---|---|---|
| M1 | Wi-Fi+BT on | Wi-Fi+BT on | current happy path, fast |
| M2 | BT only (Wi-Fi off both) | BT only | pairs + full snapshot completes (slow lane UX shown) |
| M3 | Wi-Fi only (BT off both) | Wi-Fi only | LAN discovery finds host; pairs + snapshot over LAN/AWDL |
| M4 | Wi-Fi only host | BT only joiner | honest failure with instructions (no common transport) |

## 4. Acceptance criteria
1. T1 measurement recorded (BT-only MCSession viability + throughput on iOS 26).
2. Ladder implemented with per-rung banner text; every rung red-proofed
   (disable rung N's transport in test, watch rung N+1 take over).
3. M1–M3 pass on owner hardware; M4 fails honestly with actionable text.
4. Unit tests: ladder selection logic; BT batch-size switch; Bonjour-merge of
   the nearby list. UI smoke: join screen shows merged discovery results.
5. KNOWN-ISSUES + notes updated per the feedback loop.

## 5. Out of scope (this plan)
- Internet/remote sync (Phase 15, ON HOLD).
- Mac-as-host testing beyond what iPad-on-Mac already exercises.
