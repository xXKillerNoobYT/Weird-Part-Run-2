# TestFlight Build <N> — What to Test

> Copy this file to `build-<N>.md`, fill it in BEFORE uploading, then paste the
> two sections below into App Store Connect → TestFlight → build → Test Details
> ("What to Test") once the build finishes processing. Keep it under ~4000
> characters — ASC truncates long notes. Write for the tester, not the repo:
> no PR numbers, no internal jargon.

## What's changed

- <User-visible change 1 — one line, plain language>
- <User-visible change 2>

## What to look for

- <Specific screen/flow to exercise, with the expected result>
- <Re-test line for each open beta-feedback item: "Last build you reported X —
  please try it again and send feedback either way">

---

*Internal (not pasted into ASC):*
- Built from commit: `<sha>` on `main`
- Previous build: <N-1> (`<sha>`)
- Open feedback at time of build: <list of GitHub issue #s from beta feedback>
