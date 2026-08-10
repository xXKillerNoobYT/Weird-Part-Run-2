# TestFlight Build 63 — What to Test

> First build since **62** (2026-08-07). Builds 63–70 never existed: the Xcode
> Cloud lane cancelled every run before it started from 2026-08-08 onward
> (tracked in #1682). This one was archived and uploaded locally from `main`
> per `docs/runbooks/testflight-upload.md`, so the numbering skips straight
> from 62 to 63.

## What's changed

- **Bluetooth sync no longer gives up at the first hiccup.** The device sending
  a company snapshot now paces itself and retries when the radio falls behind,
  instead of aborting the whole transfer the moment one batch fails. This is
  the main fix in this build.
- **A failed sync now looks failed.** Previously "Sync with iPhone failed"
  could appear next to a green success checkmark. Failures now read as
  failures, and say which table and how far in they stopped.
- **Pairing shows you an error code when Bluetooth won't start.** If
  advertising or scanning can't start, the code is on screen instead of only
  in a log you can't reach without syncing.
- **Sending is one direction per tap, and the app now says so.** Tapping Sync
  pushes this device's changes out. The other device has to tap Sync too to
  send its own. The labels no longer imply one tap does both.
- **A database the app can't open is kept, not discarded.** If storage is ever
  unreadable, the file is preserved for recovery rather than replaced with an
  empty one.

## What to look for

- **The Mac ↔ iPhone sync you reported tonight (2026-08-09).** Same steps:
  open *Add a Device* on the Mac, join from the iPhone. Last build showed
  `iPhone connected` and then `Sync with iPhone failed` — with a green
  checkmark next to the word "failed". Two things to check now: does the
  transfer get further than before, and if it still fails, does it clearly say
  **failed** and name where it stopped? Screenshot either way.
- **iPhone ↔ iPad (2026-08-07 reports).** Both devices on this build, different
  Apple accounts is fine. Previously the transfer stalled around a quarter of
  the way. Please note roughly how far the progress gets before it stops.
- **Bluetooth-only, Wi-Fi off on both devices.** This is the one that matters
  most — it is the real job-site condition. Wi-Fi off, Bluetooth on, join a
  company, and see whether the snapshot completes.
- **After a successful sync, check both directions.** Tap Sync on device A,
  then tap Sync on device B, then confirm a record made on each shows up on
  the other. One tap only sends; it does not fetch.
- **"Sent N records" honesty (open, P1).** Last build the host claimed it sent
  records while the new device was still empty. If you see a count reported,
  check the receiving device actually has them.
- **Permissions page Local Network still "pending" (open, P2).** Not fixed in
  this build — expect to still see it. Listed so you know it is known.
- **Tablet joining a company (2026-08-01, awaiting your confirmation).** Still
  needs a verdict from you — fixed or not, on this build.
- **Mac pairing guidance with Wi-Fi off (2026-07-31, awaiting confirmation).**
  Retry Mac↔iPhone pairing with Wi-Fi ON on both and confirm the guidance reads
  correctly.
- **More → Notebooks (2026-07-31, awaiting confirmation).** Couldn't reproduce
  on recent builds; please open it once and screenshot if it still fails.

---

*Internal (not pasted into ASC):*
- Built from commit: `4d7cc3274` on `main`
- Previous build: 62 (`3dea95674`) — Xcode Cloud run #62, 2026-08-07
- Build number set locally via `CURRENT_PROJECT_VERSION=63` (Xcode Cloud
  normally injects this; `project.pbxproj` still says `2`)
- Unshipped commits now included: #1672, #1677, #1679, #1675, #1640, #1626,
  #1648, #1680
- Already shipped in build 62, contrary to the first note on #1682: #1667,
  #1669, #1671
- Open feedback / issues at time of build: #1682 (Xcode Cloud lane down),
  #1417 (sync umbrella), WEI-7022 (snapshot staged durably — not in this
  build), WEI-6916 (one-way sync), #1661 (startup report omits error)
