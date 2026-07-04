# Setup, Permissions & Device Sync — Fix Plan

> **Goal (owner, 2026-07-04):** Four fixes to make first-run and device-to-device sync actually work:
> 1. Ask for system permissions properly during setup.
> 2. Make the new-company welcome flow clear — no repeat questions, proper data filling; reuse already-entered data.
> 3. Find other devices on the **local network** running the app.
> 4. Find other devices over **Bluetooth** for syncing and **adding a new device to the same company**.
>
> **Design-first:** this plan is the WHAT/WHY. Direct Swift edits implement the logic fixes; the onboarding UI redesign is prompt-driven where it's visual. Tracks against `docs/plans/phase-13-sync-bluetooth.md` and `docs/plans/Mobile device bootstrap.md`.

---

## Findings (grounded in code, 2026-07-04)

### The big one — discovery was blocked at the OS level (fixes #3 and #4)
`Weird-Parts-IOS-Info.plist` was **missing `NSBonjourServices`**. On iOS 14+, both the LAN browser (`PeerDiscovery`, service `_wiredpart._tcp`) and Multipeer (`MultipeerManager`, service `wiredpart-sync` → `_wiredpart-sync._tcp/_udp`) are **silently blocked and return zero peers** without those declared. The sync/discovery code itself is fully wired (`IOSPeerBrowser` starts discovery on appear; `IOSWarehouseNetworkPage` drives it; `DevicePairingView` runs onboarding discovery). So #3/#4 were an Info.plist problem, not a code problem.
- ✅ **Done:** added `NSBonjourServices` (`_wiredpart._tcp`, `_wiredpart-sync._tcp`, `_wiredpart-sync._udp`) and `NSBluetoothAlwaysUsageDescription` to the Info.plist.

### #1 — Permissions not primed at setup
No onboarding view requests camera/location; local-network + Bluetooth are only triggered implicitly on the "join existing" path inside `DevicePairingView`. Camera has **no** `AVCaptureDevice.requestAccess` anywhere (relies on the auto-prompt when the capture session starts). Location has its own `LocationManager.requestPermission()` but onboarding never calls it.
- ✅ **Done:** new `App/PermissionsManager.swift` — one `@MainActor` object exposing camera/location/bluetooth/local-network status + request methods, with the `-UITesting` guard. iOS quirks handled (Bluetooth prompt via `CBCentralManager` init; local-network prompt via throwaway `NWBrowser`; no local-network status API).
- ⬜ **To do:** a **PermissionsPrimingView** onboarding step that explains each permission and requests it, shown on both the create-new and join paths.

### #2 — Welcome flow confusion + repeat questions
Two separate setup passes run back-to-back:
1. `OnboardingWelcomeView` → `BusinessProfileSetupView` (collects companyName, industry, address, city, state, zip, phone, email, website) → `AdminAccountSetupView` (displayName, PIN) → `OnboardingCompleteView`.
2. After bootstrap, `CompanySetupWizard` (8 steps) runs — and **Step 1 re-collects companyName / address / phone / email as empty fields** (`companyName`, `companyAddress`, `companyPhone`, `companyEmail`), not pre-filled from the BusinessProfile just created. **Confirmed repeat questions.**
- ⬜ **To do:** `CompanySetupWizard` Step 1 must **pre-fill from the existing BusinessProfile / settings** and treat already-known values as done (read, don't re-ask). If the profile is complete, Step 1 becomes a read-only confirmation ("Using: <company name> — Edit"), not a blank re-entry.

### #3 — Local-network discovery
Wired and working once the plist is fixed. `IOSWarehouseNetworkPage` "Browse Nearby Devices" → `IOSPeerBrowser` (starts discovery on appear) → `IOSSyncManager.startPeerDiscovery()` → `PeerManager.startPeerSync()` → `PeerDiscovery` (NWBrowser for `_wiredpart._tcp`).
- ✅ Unblocked by plist. ⬜ Verify on two devices on the same Wi-Fi.

### #4 — Bluetooth discovery + add-device-to-company
Multipeer wired (`MultipeerManager` started with `startMultipeer: true`). The **gap**: the pairing handshake (`issuePairingCode` on the host; `pairWithShop`/`/sync/pair` on the joiner) is **only** wired in `DevicePairingView` during onboarding. **Post-onboarding there is no UI to pair a newly-discovered device into the company** — `IOSWarehouseNetworkPage`/`IOSPeerBrowser` can only sync with peers already in the same company.
- ⬜ **To do:** a post-onboarding **"Add a Device" / pairing** path:
  - On an existing (host) device: a **"Add Device"** action that calls `issuePairingCode()` and shows the code (and optionally a QR of it).
  - On the new device: reuse the `DevicePairingView` discover→select→enter-code→`pairWithShop()` handshake, reachable from the Warehouse Network page (not just first-run).

---

## Work plan (order = highest confidence / value first)

| # | Task | Type | Status |
|---|------|------|--------|
| 0 | `NSBonjourServices` + `NSBluetoothAlwaysUsageDescription` in Info.plist | config | ✅ done |
| 1a | `PermissionsManager` service | code (new) | ✅ done |
| 1b | `PermissionsPrimingView` onboarding step + wire into create-new & join paths | UI | ✅ done (built) |
| 2 | `CompanySetupWizard` Step 1 pre-fills from BusinessProfile (no repeat) | code | ✅ done (built) |
| 3 | Verify LAN discovery end-to-end (2 devices) | verify | ⬜ needs 2 devices |
| 4a | Host "Add Device" UI (`IOSAddDeviceSheet`) → `issueShopPairingCode()` + show code | UI+code | ✅ done (built) |
| 4b | New device joins post-onboarding via Join path + host code | UI | ✅ covered (new device runs first-run Join; host shows code) |
| 5 | Build green + fresh-install launch smoke; document on-device verification | verify | ✅ build green + launches; device-sync steps below |

**Build/verify status (2026-07-04):** `** BUILD SUCCEEDED **` on all changes; app launches on a fresh simulator install with no crash and renders onboarding; regression tests pass (`OnboardingAX5LayoutRegressionTests`, `CompanySetupDraftCleanupRegressionTests`, `WarehouseNetworkPageRegressionTests` — `** TEST SUCCEEDED **`). Interactive tap-through of the priming screen, and LAN/Bluetooth peer discovery, still require XCUITest or **two real devices** — those remain `UNVERIFIED` per the verification standard.

**On-device verification steps (owner, needs two devices on the same Wi-Fi):**
1. Device A: create a company (Create New Business) and finish setup.
2. Device A: Warehouse → Network → **Add a Device** → note the pairing code (stays discoverable while open).
3. Device B (fresh install): **Join Existing Business** → grant Local Network + Bluetooth when prompted → Device A appears → tap it → enter the code → initial sync runs.
4. Confirm Device B lands in the same company with data. Repeat with Wi-Fi off to confirm the Bluetooth/Multipeer path.

## Verification standard
Per `docs/plans/e2e-ui-test-plan.md`: nothing is "verified" until driven in the running app with no issues. #3/#4 require **two real devices** on the same Wi-Fi / Bluetooth range — those steps stay `UNVERIFIED` until run on hardware; the code/plist changes are verified by build + unit tests + simulator where possible.

## Notes
- Bonjour service names must stay ≤15 chars and match the code: `wiredpart` (LAN) and `wiredpart-sync` (Multipeer). Keep the Info.plist comment in sync if these ever change.
- Free Apple Developer accounts: Multipeer/local-network work, but device provisioning profiles expire in 7 days (unrelated to this plan).
