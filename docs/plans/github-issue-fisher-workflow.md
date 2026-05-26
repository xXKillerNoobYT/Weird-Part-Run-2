# GitHub Issue Fisher Workflow

> Status: active
> Runner: `scripts/github-issue-fisher.sh`
> Report location: `docs/github-issue-fisher/`

## Purpose

This workflow turns the WEI-2441 "keep GitHub issue work moving" prompt into a repeatable technical pass. Each run produces one to three issue-moving actions from real GitHub and repository evidence. It is not allowed to invent findings to satisfy a quota.

## Inputs

- Canonical plans: `docs/plans/`
- GitHub issues: `gh issue list --repo xXKillerNoobYT/Weird-Part-Run-2 --state open`
- Repo evidence: active `docs/DevTODO/`, plan markers, and Swift code markers sampled by the runner

The repo does not use a root `plans/` directory. If a caller passes a missing or empty plan directory, the runner exits with an error instead of falling back to placeholders.

## Priority Order

Every run enforces this order:

1. `blocked`: open GitHub issues with the `blocked` label
2. `todo`: open issues with priority, triage, bug, or enhancement labels
3. `backlog`: remaining open issues

The runner selects at most three actions per pass. Within a bucket it prefers higher priority labels first, then older updated issues.

## Output

Each run writes:

- `docs/github-issue-fisher/<timestamp>/open-issues.json`
- `docs/github-issue-fisher/<timestamp>/actions.json`
- `docs/github-issue-fisher/<timestamp>/evidence-findings.json`
- `docs/github-issue-fisher/<timestamp>/report.md`
- `docs/github-issue-fisher/latest-report.md`

The report is the daily/run record required by WEI-2441. It captures the selected GitHub issue-moving actions, sampled evidence, and guardrails used for the run.

## Mutation Rules

Default mode is report-only. A report can lead to GitHub comments, labels, new issues, Paperclip children, or owner assignment, but those mutations must be done by an explicit follow-up owner or approved routine path. This keeps the fisher from adding issue churn when branch or PR pressure is already high.

Valid issue-moving actions include:

- unblock or replace a blocker on a `blocked` issue;
- assign or create a small implementation child for a `todo` issue;
- promote a `backlog` issue only after plan evidence confirms it is still relevant;
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
- the run report is written without creating fake findings or mutating GitHub.
