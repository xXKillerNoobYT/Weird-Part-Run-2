# TestFlight Build 65 — What to Test

> Built locally from `main` @ `57621592d` per `docs/runbooks/testflight-upload.md`.
> Xcode Cloud is still cancelling every run before it starts (#1682), so this is
> a manual archive. Build number 65: above the highest upload (63), below the
> next cloud run number (76), so a restored lane cannot collide.
>
> **Supersedes build 64, which was never uploaded.** `build-64.md` describes a
> build that does not exist on TestFlight; three further fixes landed after it.

## Read this first — your last test was probably sabotaged by our own CI

The single most important change this round **is not in the app at all.**

Our automated test suite was broadcasting **fake devices onto the real Bluetooth
mesh**, from the Mac sitting next to your devices. Your build-63 screenshot shows
seven peers in "Join a Business" — `Test Device`, `Shop Mac`, `Host`,
`Local Device`, `WPR2-CI-iPad-…` — and **every one of them was a test fixture,
not a real device.** The app had auto-selected one of those ghosts while your Mac
was displaying pairing code `QNCP–YQDZ`.

**Typing a real code into a ghost device cannot work.** It fails with exactly the
blank, reasonless error you kept photographing.

That is fixed (#1701/#1707) and the fix is **already live** — it is a change to
how our tests run, so it protects you no matter which build you install. Your
device picker should now list only real devices.

**This means we do not actually know whether device-to-device sync is broken.**
An unknown number of "still not syncing" reports may have been this. Please treat
this round as a fresh first test, not the seventh attempt.

## What's changed in the app since build 63

- **A pairing failure now names itself.** Nine different causes used to collapse
  into one blank sentence. Each now shows a code like `BT-PAIR-REJECTED` or
  `BT-PAIR-VERSION`, plus what to do about it.
- **Both devices now say WHY a sync failed.** Build 63 could not do this on
  either end — the joining device's fix and the hosting device's fix both landed
  after 63 was cut.
- **A do-nothing sync can no longer paint over a real failure** with a green
  checkmark.
- **The app is less likely to fail to start.** A keychain quirk could hand the
  app the *wrong* encryption key — not a missing one — leaving it unable to open
  its own database. That specific path is closed.
- **The joining device writes the incoming company to disk as it arrives**
  instead of holding all of it in memory.

## Please test — in this order

1. **Bluetooth-only join, Wi-Fi OFF on both devices.** The real scenario, and the
   one our automated tests can never cover.
2. **Check the device list before you tap anything.** It should show only your
   real devices now. **If you still see a `Test Device`, `Host`, `Shop Mac`, or
   anything starting `WPR2-CI-`, stop and tell us** — that would mean the CI fix
   missed a path, and it is the most important thing you could report.
3. **If it fails, photograph BOTH screens.** The host's screen has still never
   been captured, and it now carries a reason.
4. **Tell us which device was which** — which displayed the code, which typed it
   in. "Both failed" doesn't say who was hosting, and that has cost several
   rounds.
5. **If a sync succeeds**, make a note on device A and confirm it appears on
   device B after both devices tap Sync.

## Known issues — you will still see these

| Issue | Status |
|---|---|
| Sending is one direction per tap; both devices must tap Sync | **Now a defect, not by design** — you asked for any-device-to-any-device (#1684) |
| A failure while *pairing* on the **hosting** device is still silent | Partly fixed — the joining device now shows a code; the host's own screen does not (#1693) |
| Permissions page shows Local Network as "pending" after you allow it | Not fixed (P2) |
| An interrupted transfer restarts from zero rather than resuming | Planned, not built (#1695) |
| Rows that collide with existing data are skipped silently | Known gap (#1645) |

## Note on "any device to any device"

You said every device in a company must sync with every other one. That is now
recorded as a requirement (#1684) and it reclassifies the one-way-per-tap
behaviour above as a **defect** rather than a design choice. It is not built yet
— this build does not change it — but nothing will be shipped that assumes a
permanent host/joiner split.

## For the record

Mac Catalyst is **not** distributed (`docs/KEY-PRINCIPLES.md`). If you want to
test on the Mac, install this iOS build through TestFlight on Apple Silicon
rather than archiving a Mac Catalyst target — two of the three archives cut on
2026-08-10 were Catalyst, and all three carried build number `2`, which App Store
Connect rejects because it must exceed 63.
