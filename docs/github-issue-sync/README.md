# GitHub Issue Sync Contract

Owner: `CTO`
Backup owner: `CodexEngineer1`

## Cadence
- Standard cadence: Monday/Wednesday/Friday at 09:00 America/Denver.
- Manual fallback: run before triage sessions and before WEI status rollups.

## Command
```bash
scripts/github-issue-sync.sh --state all
```

The default state is `all`, so the snapshot validates both open and closed GitHub issue paths. Use `--state open` or `--state closed` only for targeted diagnostics.

## Canonical Consumer Artifacts
- `docs/github-issue-sync/latest-sync.md`
- `docs/github-issue-sync/latest-sync.json`

## Per-run Archive
- `docs/github-issue-sync/<UTC timestamp>/summary.md`
- `docs/github-issue-sync/<UTC timestamp>/issues.json`

## Verification
```bash
test -s docs/github-issue-sync/latest-sync.md && test -s docs/github-issue-sync/latest-sync.json
```

If either canonical artifact is missing/empty, the run is considered failed.
