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

## Output Location
Generated snapshots are local, ignored run artifacts under `.tmp/github-issue-sync/` by default. They should not be committed.

## Canonical Local Artifacts
- `.tmp/github-issue-sync/latest-sync.md`
- `.tmp/github-issue-sync/latest-sync.json`

## Per-run Local Archive
- `.tmp/github-issue-sync/<UTC timestamp>/summary.md`
- `.tmp/github-issue-sync/<UTC timestamp>/issues.json`

## Verification
```bash
test -s .tmp/github-issue-sync/latest-sync.md && test -s .tmp/github-issue-sync/latest-sync.json
```

If either canonical artifact is missing/empty, the run is considered failed.
