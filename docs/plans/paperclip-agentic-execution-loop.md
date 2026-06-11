# Paperclip Agentic Execution Loop

> **Status:** Active coordination plan
> **Created:** 2026-05-26
> **Tracking:** GitHub #886 / Paperclip WEI-2560
> **Goal:** Ship Wired Parts Run 2 to stable field-test beta without quality cuts.

## Purpose

This plan defines how Paperclip goals, repo plans, GitHub issues, Paperclip execution issues, PRs, CI, and closeout evidence connect. Use it when creating, selecting, delegating, or closing autonomous engineering work.

The operating rule is: field-test beta work comes first. Process or infrastructure work is valid only when it makes beta execution clearer, safer, faster to verify, or easier to land.

## Current Product Posture

- Product: native iOS shop-management app for Wired Parts Run 2.
- Primary repo: `xXKillerNoobYT/Weird-Part-Run-2`.
- Canonical local checkout: `/Users/IA/GitHub/Weird-Part-Run-2`.
- Runtime direction: iOS-native app plus shared Swift core package. Historical Tauri, React, macOS, and Windows plans are reference material unless a current issue explicitly reactivates them.
- Priority goal: Paperclip goal "Ship Wired Parts Run 2 to stable field-test beta without quality cuts".

## Execution Chain

| Layer | Source of truth | Owner | Required output |
|---|---|---|---|
| Goal | Paperclip goal hierarchy | CEO/CTO | Priority, routing rules, non-goals, blocker policy |
| Plan | `docs/plans/*.md` and `docs/paperclip-handoff.md` | CTO/engineering lead | Scope, architecture, acceptance criteria, verification lane |
| Improvement ledger | GitHub issues | CTO/engineers/QA | Field-test relevance, labels, acceptance criteria, linked plan/Paperclip issue |
| Execution | Paperclip issues and child issues | Assigned Paperclip agent | Bounded implementation/review/QA task with owner and evidence |
| Landing | Git branch, PR, CI, review | Engineer/reviewer | PR link, CI status, review disposition, merge state |
| Closeout | GitHub and Paperclip comments | Task owner | What changed, verification, residual risk, next owner action |

## Work Selection Rules

1. Pick field-test beta issues before process cleanup.
2. Prefer issues with a current repo plan and testable acceptance criteria.
3. If a GitHub issue is vague, update the issue or create a Paperclip planning child before implementation.
4. If a plan is stale against the iOS-native app, correct the plan before coding.
5. If branch or worktree pressure is high, drain/review/merge/close existing PRs before opening broad new implementation branches.

## GitHub Issue Requirements

Every new or materially updated GitHub issue created from Paperclip, QA, or autonomous findings must include:

- **Field-test relevance:** why the issue matters before beta, or why it is explicitly deferred.
- **Area label:** one of the product areas used by the beta checklist, plus severity/tier labels when applicable.
- **Acceptance criteria:** observable behavior, not only "update docs" or "investigate".
- **Plan link:** the relevant `docs/plans/*.md` file, or a statement that the issue is plan-discovery work.
- **Paperclip link:** the owning Paperclip issue identifier when execution is routed through Paperclip.
- **Verification:** smallest meaningful command, screenshot, simulator/device check, CI run, or review artifact.

## Paperclip Child Issue Requirements

Every child issue created from this loop must state:

- Owner role and lane: engineering, frontend implementation, UX design, QA, security, or review.
- Repo/project: usually Weird Parts Run 2.
- Exact scope and non-goals.
- Acceptance criteria.
- Required evidence.
- Review lane.
- Pass-up trigger back to the parent issue or GitHub issue.

For frontend/UX work, include the route or screen, expected viewport evidence, and whether UXDesigner, UIFirstRun, UIExpertVerifier, or FrontendCoder owns the next step.

## Branch And Worktree Hygiene Gate

Before starting new Weird Parts implementation work, run a preflight from the canonical checkout:

```bash
git ls-remote --heads origin | wc -l
gh pr list --state open --limit 200 --json number,title,headRefName,url
git worktree list --porcelain
git worktree prune -n -v
```

If the repo is above branch soft-cap pressure or has many active worktrees, prefer one of these outcomes:

- Review and merge an existing ready PR.
- Reconcile a stale worktree with its owning issue.
- Create a bounded cleanup issue with evidence instead of deleting uncertain branches.
- For documentation-only work, keep the branch small and link it directly to the process issue that required it.

Never delete a live worktree, local branch, remote branch, or PR without evidence that it is clean, merged, superseded, or intentionally abandoned.

## Local Mac Actions Runner Gate

For `xXKillerNoobYT/Weird-Part-Run-2`, trusted PR build/test/QA work and repo-owned Actions automation must use the local self-hosted Mac runner path before treating GitHub-hosted Actions billing or queue capacity as a blocker.

Use `docs/runbooks/local-mac-actions-runner.md` as the canonical runner reference instead of duplicating machine-specific details in plans or closeout comments.

Before calling a PR blocked by CI, run:

```bash
gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 10
rg -n "runs-on:" .github/workflows || grep -R "runs-on:" .github/workflows
```

The runner API requires a GitHub token with permission to read repository Actions runner state. If API access is unavailable, use the repository Actions UI to inspect runner status and recent runs.

Required disposition:

- If an Apple-platform or required PR-gate job is on `macos-latest`/`ubuntu-latest`, reroute it to `[self-hosted, macOS, ARM64, xcode, ios, local-mac]` or create a bounded CI child issue that does.
- Do not run untrusted fork PR code on the self-hosted runner; keep self-hosted PR jobs limited to same-repository/trusted events.
- If the local runner is online with those labels, do not escalate cloud billing as the primary blocker.
- If the local runner is offline, busy, or missing labels, record the exact runner evidence and make that the named blocker.
- PR descriptions, merge issues, review comments, and Paperclip closeout comments that mention CI must include the local-runner check result.

## PR And Closeout Requirements

A PR or closeout comment must include:

- GitHub issue link.
- Paperclip issue link or identifier.
- Files changed.
- Verification performed.
- CI state or why CI is not applicable.
- Residual risk.
- Cleanup state for any agent-created worktree.

Paperclip closeout comments for GitHub-backed work must include a `GitHub sync:` line with one of:

- `pushed/PR/commented URL`
- `existing PR/CI URL`
- `not applicable with reason`
- `blocked with owner/action`

## Verification Matrix

| Change type | Minimum evidence |
|---|---|
| Docs/process plan | Markdown diff, linked GitHub issue/PR, no stale contradiction introduced |
| Swift core behavior | Focused Swift tests or reason a narrower verification is impossible |
| SwiftUI implementation | Screenshot or simulator evidence for affected screen/viewport when visual behavior changes |
| Data migration | Migration test, rollback story, and fixture or seeded-data coverage |
| GitHub issue hygiene | Updated issue body/comment/labels with acceptance criteria and Paperclip link |
| Branch cleanup | Worktree/branch/PR evidence and owning issue final cleanup note |

## Non-Goals

- Do not restart desktop, web, or Windows work unless a current beta issue explicitly scopes it.
- Do not create process-only issues that do not help agents choose, verify, land, or close work.
- Do not broaden a small beta bug into an architecture project without a plan update and owner approval.
- Do not treat Paperclip comments as completion when a code, PR, CI, review, or GitHub update is required.
