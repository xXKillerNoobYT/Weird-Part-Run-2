# TestFlight Build 3 — What to Test

> DRAFT — finalize the "What's changed" list at upload time from the PRs merged
> since build 2, then paste both sections into App Store Connect → TestFlight →
> build 3 → Test Details.

## What's changed

- New app icon — the real WiredPart icon, replacing the placeholder.
- Fix for the Notebooks page not opening from the More menu (reported on
  build 2 — thank you for the feedback!).
- Reliability fixes to the reports/pre-billing pages around pay-period
  boundaries.
- <ADD: user-visible changes from PRs merged during the drain — finalize at
  upload time>

## What to look for

- **Notebooks (please re-test your build-2 report):** More tab → Notebooks.
  It should open the notebooks list immediately. Try it offline too (airplane
  mode) — the app is designed to work with no service at all.
- **App icon:** check the home screen and Settings show the new icon (delete
  the old install first if it looks stale).
- **Reports → Pre-Billing:** open it and confirm the jobs summary shows data
  rather than "No labor entries found".
- Anything else you touch: if a page feels slow, empty, or stuck, send a
  TestFlight screenshot with one line — that pipeline works great.

---

*Internal (not pasted into ASC):*
- Built from commit: `<fill at upload>` on `main`
- Previous build: 2 (pre-drain, 2026-07-28)
- Open feedback at time of build: #1577 (Notebooks page won't load)
