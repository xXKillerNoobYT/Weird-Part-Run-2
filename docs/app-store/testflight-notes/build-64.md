# TestFlight Build 64 — What to Test

> Built locally from `main` per `docs/runbooks/testflight-upload.md`. The Xcode
> Cloud lane is still cancelling every run before it starts (#1682), so this is
> a manual archive like build 63. Build number rule: above the highest upload
> (63), below the next cloud run number, so a restored lane cannot collide.

## The point of this build

**Build 63 could not tell you why sync failed. This one can — on both devices.**

Build 63 had **neither** side of that fix. It was archived from `4d7cc3274` at
00:04Z on 2026-08-10; the joining-device fix (#1692) landed at 05:19Z and the
hosting-device fix (#1698) at 16:13Z, both after the archive was cut. So the
green checkmark you photographed on the Mac, and the reasonless "Couldn't sync
data." on the phone, were *both* still present in 63.

Build 64 is the first build carrying both. A failed sync now names its own
reason on each screen, including the host's — the screen that actually has the
data.

This build does **not** claim sync is fixed. It claims a failure is now
**legible**. If it fails again, the screens should finally tell us where.

## What's changed

- **The joining device now says WHY a sync failed** instead of the fixed
  sentence "Couldn't sync data." The specific reason was already being worked
  out and then discarded one line before it reached the Sync Error screen.
- **The host device now says WHY a sync failed**, not just that it failed. Same
  defect, other end — and this is the screen that has never once been captured.
- **A do-nothing sync can no longer paint over a real failure.** The background
  sync that runs every 60 seconds reports "success, sent 0 records" — and
  because it happened later, it was overwriting your real failure with a green
  checkmark. A sync that moved nothing is no longer treated as evidence that
  syncing works.
- **"Try Again" no longer shows you the previous attempt's error.** A second
  failure for a completely different reason was redisplaying the first attempt's
  advice, which made a leftover look like a confirmed diagnosis.
- **The joining device writes the incoming company to disk as it arrives**
  instead of holding all of it in memory. You would only notice this on a large
  company that previously ran out of memory partway through.

## Please test — in this order

1. **Bluetooth-only join, Wi-Fi OFF on both devices.** This is the one that
   matters. Turn Wi-Fi off on the host and on the joining device, generate a
   fresh code, and join.
2. **If it fails — and it may — photograph BOTH screens**, not just the one
   showing the error. The host's screen is the evidence we have never once had.
   The host should now show an orange warning with a reason, not a green tick.
3. **Tell us which device was which.** Which one displayed the pairing code, and
   which one typed it in. "The iPhone and the Mac both failed" does not say who
   was hosting, and that ambiguity has cost several rounds.
4. **Tap "Try Again" after a failure** and confirm the second message describes
   the second attempt, not the first.
5. **If a sync succeeds**, make a note on device A and confirm it appears on
   device B after both devices have tapped Sync. Sending is still one direction
   per tap — each device has to tap Sync to send its own changes.

## Known issues — you will still see these

| Issue | Status |
|---|---|
| Sending is one direction per tap; both devices must tap Sync | By design for now; the labels say so |
| Permissions page shows Local Network as "pending" after you allow it | Not fixed (P2) |
| An interrupted transfer restarts from zero rather than resuming | Planned, not built (#1695) |
| Rows that collide with existing data are skipped silently | Known gap, being tracked (#1645) |
| **A failure while _pairing_ — before the transfer starts — is still silent** | **Not fixed (#1693)** — see below |

### The one gap that could still waste your test

Everything above is about a failure *during the transfer*. If the join is
rejected **during pairing**, before any data moves, this build still tells you
nothing useful: all six rejection paths write to the device log only, and the
host's reason panel cannot even be reached until pairing has already succeeded.

**What that looks like:** you type the code, it fails quickly, and the phone
shows a generic sentence with no code while the Mac shows nothing new at all.

**If that happens, this build has not given us the reason** — say so plainly and
don't spend more attempts on it. That case is tracked on #1693 and needs one
more fix before it is legible. A failure that happens *after* "connected", once
records start moving, is the case this build does cover.

## For the record

The pairing and connection work confirmed on earlier builds is unchanged: the
peer is no longer erased when a connection drops, Bluetooth startup failures
show a `BT-*-START` code, and encryption is `.optional` so connections can form.
Nothing in this build touches those.
