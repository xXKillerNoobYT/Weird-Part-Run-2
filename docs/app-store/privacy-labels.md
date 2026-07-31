# WiredPart — App Privacy (nutrition labels + policy basis)

WiredPart is local-first: every business record lives in an encrypted SQLite
database inside the app sandbox on the user's device. There is no backend, no
account service, no analytics SDK, and no ad SDK. Device-to-device sync moves
data directly between the user's own devices (Apple Multipeer Connectivity,
end-to-end encrypted); it never transits a server we operate.

## ASC "App Privacy" questionnaire answers

**Do you or your third-party partners collect data from this app?** → **No** →
label: **Data Not Collected**.

Rationale per Apple's definition of "collect" (transmitted off-device to the
developer or partners): nothing is transmitted to us or anyone else.

| On-device data | Purpose | Leaves the user's devices? |
|---|---|---|
| Business records (parts, orders, jobs, people) | App functionality | Never — device + user's own paired devices only |
| GPS location at clock-in/out | Attached to the user's own labor entries | Never |
| Camera (QR scanning) | Part/bin lookup | Never — frames processed on device, not stored |
| Bluetooth / local network | Device-to-device sync | Peer devices only, encrypted |
| AI assistant prompts | Apple on-device Foundation Models | Never sent to third-party services |

**Tracking (ATT):** none. No `AppTrackingTransparency` prompt required.

## Permission strings (already in Weird-Parts-IOS-Info.plist)
- `NSLocationWhenInUseUsageDescription` — clock-in/out GPS stamps
- `NSCameraUsageDescription` — QR part scanning
- `NSBluetoothAlwaysUsageDescription`, `NSLocalNetworkUsageDescription`,
  `NSBonjourServices` — device-to-device sync

## Privacy Policy page (required URL before App Store submission)
A single page with, at minimum:
1. WiredPart stores all data locally on your device, encrypted at rest.
2. We collect nothing: no analytics, no ads, no accounts, no servers.
3. Sync is direct between your own devices and end-to-end encrypted.
4. Permissions (location, camera, Bluetooth/local network) are used only for
   the features above and their data never leaves your devices.
5. Contact: weirdtoocompany@gmail.com

Owner action: host this (GitHub Pages page in this repo is sufficient) and put
the URL in ASC → App Privacy → Privacy Policy.
