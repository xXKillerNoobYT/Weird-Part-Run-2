# Known Issues — reported by testers, tracked until CONFIRMED fixed

> Owner process (2026-08-01): every reported bug stays on this list, with a
> fix-confidence rating, until the tester who reported it confirms it works.
> Every build's What-to-Test notes carry the OPEN + AWAITING-CONFIRMATION
> sections verbatim. Confirmed items move to the Confirmed log below (never
> deleted). Behavior CHANGES (not bugs) are announced in the notes the build
> they ship. New feedback is checked daily.
>
> Confidence scale: **High** = root cause found and fix verified locally;
> **Medium** = fix shipped but root cause inferred, not proven; **Low** = not
> reproducible or fix speculative.

## Awaiting tester confirmation

| Issue | Reported | Fix | Confidence | Please test |
|---|---|---|---|---|
| Tablet can't join the company — fails ~2-3s after entering code (P0) | 2026-08-01, build 39, iPad | PR #1616 → first build ≥ 40 | **High** — root cause matched your exact 2-3s timing: Wi-Fi attempt failed and the app never fell back to Bluetooth; now it does, visibly | Fresh code on the iPhone, keep its Add-a-Device screen open, retry the join on the iPad. Expect "Wi-Fi didn't work — downloading over Bluetooth instead…" then completion |
| Mac pairing failed with Wi-Fi off guidance confusion | 2026-07-31, build 5, Mac | build 6 | **High** — guidance now detects the Wi-Fi radio and says exactly what to turn on | Retry Mac↔iPhone pairing with Wi-Fi ON on both |
| Notebooks page won't load from More menu | 2026-07-31, build 2, iPhone | rebuilt since; not reproducible on current builds | **Medium** — couldn't reproduce on drained main; may already be fixed | Open More → Notebooks on the current build; screenshot if it still fails |

## Open (not fixed yet — you'll see these)

| Issue | Reported | Priority | Plan |
|---|---|---|---|
| Permissions page shows Local Network as "pending" even after you allow it in Settings | 2026-08-01, build 39, iPad | P2 | Re-probe on return from Settings; issue filed |
| Host says "Sent 9 records" like a success while the new device is still empty | 2026-08-01, build 39, iPhone | P1 | Part of the #1417 sync hardening (progress + honest status, both screens) |

## Confirmed fixed (log — never deleted)

| Issue | Reported | Fixed | Confirmed |
|---|---|---|---|
| _(none yet — items land here when the reporting tester confirms)_ | | | |
