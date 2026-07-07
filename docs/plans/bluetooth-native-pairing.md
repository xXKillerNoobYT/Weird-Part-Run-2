# Bluetooth-Native Pairing & Sync — Design

> **Owner direction (2026-07-04):** Device sync must work **100% over Bluetooth** (Apple Multipeer, no Wi-Fi/router needed). Wi-Fi/LAN should be used **only as a speed boost** when both devices happen to be on the same network. Hit while testing tablet↔Mac: joining a Bluetooth-discovered peer errors with "Needs Wi-Fi address."

## Current state (verified in code)
- **Data sync over Bluetooth already works:** `PeerManager.syncWithPeer` has a Multipeer path (sends changes over the MCSession when `peer.transport == "multipeer"` and connected). LAN HTTP is the fallback/speed path.
- **Pairing is Wi-Fi-only (the gap):** the trust handshake (`IOSSyncManager.pairWithShop` → HTTP `POST /sync/pair`) needs the host's IP. `DevicePairingView` rejects a Bluetooth-only peer (`peer.address == nil` → "Needs Wi-Fi address", line ~124/137).
- **Multipeer channel has no message types:** `PeerManager.handleMultipeerMessage` blindly decodes every message as `[IncomingChange]`. So pairing cannot currently ride the Bluetooth channel at all — a typed envelope is a prerequisite.
- Host pairing validation to mirror: `SyncServerState.consumePairingCode(code)` (one-time, digest-compared) → respond `{serverDeviceId = state.deviceId, companyId = state.companyId}` (see `LanSyncServer.handlePair`).

## Design

### 1. Typed Multipeer message envelope (prerequisite)
Introduce a small Codable envelope so the Bluetooth channel can carry more than sync changes:
```
MPEnvelope { type: String, payload: Data }   // types: "changes", "pairRequest", "pairResponse"
```
- `syncWithPeer` Multipeer send → wrap changes as `type:"changes"`.
- `handleMultipeerMessage` → decode envelope, dispatch by type. **Backwards-compat:** if envelope decode fails, fall back to decoding raw `[IncomingChange]` (older senders).

### 2. Pairing over Bluetooth (mirror the HTTP handshake)
- **Joiner** (`PeerManager.pairViaMultipeer(deviceId:code:deviceName:) async throws -> SyncPairResponse`): ensure MCSession connected to the host, send `type:"pairRequest"` `{code, deviceId, deviceName, platform}`, await `pairResponse` (continuation keyed by host deviceId, with timeout).
- **Host** (`handleMultipeerMessage` `pairRequest`): `serverState.consumePairingCode(code)`; on success register the joiner (`ChangeTracker.registerPeerDevice`) and reply `type:"pairResponse"` `{accepted, serverDeviceId, companyId}`; on failure reply `accepted:false`.
- **Joiner on accept:** adopt host `companyId` (write `company_id` in the "company" category — same as the LAN path fix), register host as trusted peer, mark `device_paired`. Then normal Multipeer sync flows.

### 3. Connection trigger
The joiner must have a connected MCSession to the host before sending. `MultipeerManager` auto-invites when advertising; add/confirm an explicit `connect(toPeer:)` so pairing can force a connect on peer selection, and wait for `.connected` before sending the pairRequest.

### 4. UI (`DevicePairingView`)
- Allow selecting a **Bluetooth-only** peer (drop the `address == nil` block for the Multipeer path).
- On select: if the peer has a Wi-Fi address AND same network → keep fast LAN pair; else → `pairViaMultipeer`. Prefer Bluetooth as the always-available default; treat Wi-Fi as the optimization.
- Post-onboarding: the `IOSAddDeviceSheet` host already advertises; the joiner path above covers joining without Wi-Fi.

## Files
- `core/Sources/WiredPartCore/Sync/PeerManager.swift` — envelope, dispatch, `pairViaMultipeer`, host pairRequest handling.
- `core/Sources/WiredPartCore/Sync/MultipeerManager.swift` — explicit connect(toPeer:), expose connection state.
- `Weird Parts IOS/.../Sync/IOSSyncManager.swift` — `pairWithPeerOverBluetooth`, store company_id + paired state.
- `Weird Parts IOS/.../Auth/DevicePairingView.swift` — allow BT-only peer selection, route to BT pairing.

## Test (needs the two real devices)
1. Turn **Wi-Fi off** on both (or use different networks). Mac: Devices → Add a Device → code. Tablet: Join → allow Bluetooth → Mac appears (Bluetooth) → enter code → pairs + initial sync over Bluetooth.
2. Then turn Wi-Fi on (same network) → confirm sync auto-uses LAN for speed, still works.

## Status
- [x] Design captured (2026-07-04).
- [ ] Envelope + dispatch.
- [ ] BT pairing handshake (host + joiner).
- [ ] Connection trigger.
- [ ] UI.
- [ ] 2-device verification.
