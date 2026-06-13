# GitHub Issue Fisher Workflow

> Status: active
> Runner: `scripts/github-issue-fisher.sh`
> Report location: `docs/github-issue-fisher/`

## Purpose

This workflow turns the WEI-2441 "keep GitHub issue work moving" prompt into a repeatable technical pass. Each run produces one to three issue-moving actions from real GitHub and repository evidence. It is not allowed to invent findings to satisfy a quota, and generated run reports stay local unless a reviewer explicitly asks for a report snapshot.

## Inputs

- Canonical plans: `docs/plans/`
- GitHub issues: `gh issue list --repo xXKillerNoobYT/Weird-Part-Run-2 --state open`
- Repo evidence: active `docs/DevTODO/`, plan markers, and Swift code markers sampled by the runner

The repo does not use a root `plans/` directory. If a caller passes a missing or empty plan directory, the runner exits with an error instead of falling back to placeholders.

## Work Order

Every run enforces this order:

1. `blocked`: open GitHub issues with the `blocked` label
2. `todo`: open issues with priority, triage, bug, or enhancement labels
3. `backlog`: remaining open issues

The runner selects at most three actions per pass. Within a bucket it prefers higher priority labels first when present, then older updated issues.

Priority labels are optional severity signals, not a filing requirement. An issue can move through the workflow with only work-type labels such as `bug`, `enhancement`, `triage`, or `blocked`. Missing `priority:P*` labels do not fail a fisher run and do not require mass relabeling. Use a priority label only when severity materially changes scheduling, release risk, or escalation.

Backlog entries are never treated as promotions by the report itself. When the pass reaches backlog because blocked/todo supply fewer than the requested limit, those entries are labeled as non-promotion candidates and require a separate human or approved-routine confirmation of concrete plan/repo evidence before any GitHub or Paperclip mutation.

## Output

Each run writes:

- `docs/github-issue-fisher/<timestamp>/open-issues.json`
- `docs/github-issue-fisher/<timestamp>/actions.json`
- `docs/github-issue-fisher/<timestamp>/evidence-findings.json`
- `docs/github-issue-fisher/<timestamp>/report.md`
- `docs/github-issue-fisher/latest-report.md`

The report is the daily/run record required by WEI-2441. It captures the selected GitHub issue-moving actions, sampled evidence, and guardrails used for the run. The `docs/github-issue-fisher/` output directory is ignored by git so repeat runs do not leave stale generated artifacts in pull requests.

## Mutation Rules

Default mode is report-only. A report can lead to GitHub comments, labels, new issues, Paperclip children, or owner assignment, but those mutations must be done by an explicit follow-up owner or approved routine path. This keeps the fisher from adding issue churn when branch or PR pressure is already high.

Valid issue-moving actions include:

- unblock or replace a blocker on a `blocked` issue;
- assign or create a small implementation child for a `todo` issue;
- mark a `backlog` issue as a non-promotion candidate pending separate plan/repo evidence confirmation;
- file a new GitHub issue only when repo evidence is concrete and not already tracked.

## Verification

Use:

```bash
scripts/github-issue-fisher.sh --dry-run
```

Successful verification proves:

- `docs/plans/` exists and contains markdown plans;
- GitHub issues can be read with `gh`;
- actions are ordered `blocked -> todo -> backlog`;
- priority-label coverage is reported without requiring every GitHub issue to have `priority:P0` through `priority:P5`;
- the local run report is written without creating fake findings, committing generated artifacts, or mutating GitHub.
