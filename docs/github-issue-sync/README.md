# GitHub Issue Sync Cadence (WEI-207)

This directory stores durable artifacts produced by `scripts/github-issue-sync.sh`.

## Cadence

- Owner: `CTO` (backup executor: `CodexEngineer1`)
- Cadence: every Monday, Wednesday, Friday at 09:00 America/Denver
- Command:
  - `cd Weird-Part-Run-2 && scripts/github-issue-sync.sh --repo xXKillerNoobYT/Weird-Part-Run-2`

## Expected Artifacts Per Run

Each run creates:

- `docs/github-issue-sync/<timestamp>/issues.json`
- `docs/github-issue-sync/<timestamp>/summary.md`
- `docs/github-issue-sync/<timestamp>/run-metadata.json`
- `docs/github-issue-sync/latest.json`
- `docs/github-issue-sync/latest.md`

## Failure Handling

If the scheduled run fails:

1. Re-run manually with the command above.
2. If `gh` auth is missing, run `gh auth status` then re-authenticate.
3. Post the failed run timestamp + error summary on WEI-44 and include the recovery ETA.

## Manual Fallback

Use this exact command path:

- `Weird-Part-Run-2/scripts/github-issue-sync.sh`

