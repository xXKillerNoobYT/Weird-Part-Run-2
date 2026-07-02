# Problem Reports Inbox

Drop screenshots of app problems here (owner workflow). The hunt-fix loop's
Problems-folder scanner reads this directory and triages each item into a
GitHub issue, then removes the processed screenshot.

- This folder was previously named `docs/Problomes ` (misspelled, with a
  trailing space), which made it invisible to the scanner and un-checkoutable
  on Windows — fixed 2026-07-02 (issues #744, #1333).
- Filenames should be plain ASCII. Images anywhere else in the repo are
  blocked by `scripts/guard-tracked-artifacts.py`.
- The 33 screenshots dated 2026-03-28/29 predate the rename and are queued
  for triage (see #744).
