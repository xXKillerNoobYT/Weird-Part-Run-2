# GitHub Issue Sync Workflow

## Purpose
Keep GitHub tracker visibility in sync with Paperclip issue state and preserve a manual fallback path.

## Inputs
- `gh` CLI authenticated for repo access
- `jq` available on PATH
- `curl` and `sha256sum` available on PATH
- Repository: `xXKillerNoobYT/Weird-Part-Run-2` (default)
- Paperclip env vars exported in heartbeat context:
  - `PAPERCLIP_API_URL`
  - `PAPERCLIP_API_KEY`
  - `PAPERCLIP_COMPANY_ID`

## Automated Tracker Sync (Primary)
```bash
scripts/paperclip-github-tracker-sync.sh
```

Repository automation:
- Workflow: `.github/workflows/paperclip-tracker-sync.yml`
- Trigger: every 30 minutes (`cron`) and manual `workflow_dispatch`
- Required repo secrets:
  - `PAPERCLIP_API_URL`
  - `PAPERCLIP_API_KEY`
  - `PAPERCLIP_COMPANY_ID`
- Optional repo variable:
  - `PAPERCLIP_WEB_URL` (for internal issue hyperlinks in tracker comment)

Optional:
```bash
scripts/paperclip-github-tracker-sync.sh --repo <owner/repo> --tracker-number <n> --state-dir <path>
```

Help:
```bash
scripts/paperclip-github-tracker-sync.sh --help
```

Dry run (no GitHub write):
```bash
scripts/paperclip-github-tracker-sync.sh --dry-run
```

## Trigger and Update Behavior
- Source set: all Paperclip issues in statuses `todo`, `in_progress`, `in_review`, `blocked`.
- Material fields mirrored to tracker comment:
  - status
  - assignee agent
  - blockers (`blockedByIssueIds` / `blockedBy`)
- Update policy:
  - Script computes SHA-256 of normalized material fields (status/owner/blockers/title).
  - If hash unchanged from prior run, no GitHub update occurs.
  - If changed, script upserts a marker comment (`# paperclip-tracker-sync:v1`) on tracker issue.

## Logs and Evidence
- Console output states one of:
  - `no material changes detected; tracker update skipped`
  - `updated tracker comment id: ...`
  - `created tracker comment on ...`
- Local state file: `.paperclip-sync/tracker-<issue>.sha256`
- Scheduled run logs: GitHub Actions → `Paperclip Tracker Sync` workflow run history

## Cadence
- Scheduled workflow runs every 30 minutes when secrets are configured.
- Run once per CTO heartbeat when issue-sync governance is active.
- Otherwise run before triage sessions or daily.

## Manual Fallback (Do Not Remove Yet)
If automated sync fails, use the existing snapshot path:
```bash
scripts/github-issue-sync.sh --repo xXKillerNoobYT/Weird-Part-Run-2 --state all
scripts/github-issue-sync.sh --repo xXKillerNoobYT/Weird-Part-Run-2 --state all --source-issue WEI-2309
```

`--source-issue` sets snapshot metadata explicitly. If omitted, the script falls back to `PAPERCLIP_TASK_ID` (when present), then to legacy default `WEI-44`.
Artifacts (local only, ignored by git):
- `.tmp/github-issue-sync/<UTC timestamp>/issues.json`
- `.tmp/github-issue-sync/latest-sync.md`

Do not commit generated snapshot artifacts; they are regenerated operational evidence, not project source.

Rollback:
1. Disable `.github/workflows/paperclip-tracker-sync.yml` (or remove required secrets).
2. Resume manual fallback command above.
3. Keep tracker continuity by posting the latest fallback summary manually.

## Triage Guidance
1. Use `latest-sync.md` to spot high-churn issues (recently updated).
2. Convert ambiguous items into bounded child issues with explicit owners.
3. Mark blocked items with clear unblock owner/action.
4. Keep parent tracking issue open until workflow and cadence are stable.
