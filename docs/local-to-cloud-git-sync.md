# Local-to-Cloud Git Sync Runbook

This repo uses local Paperclip worktrees plus GitHub as the cloud source of truth. Before closing a sync task, verify the exact local branch state and push only the branch/commits that belong to the active issue.

## Audit

Run the sync audit from the active worktree:

```bash
scripts/git-cloud-sync-audit.sh
```

The audit fetches `origin`, reports dirty worktree state, shows whether the current branch has an upstream, lists local branches that are ahead/behind or lack upstreams, and compares local/remote tag counts.

## Push the Active Issue Branch

If the worktree is clean and the current branch is the intended issue branch:

```bash
git push -u origin HEAD
git ls-remote --heads origin "$(git branch --show-current)"
git rev-parse HEAD
```

The `git ls-remote` SHA must match `git rev-parse HEAD`. If the current branch already tracks `origin/<branch>`, use `git push` and verify the same way.

## Guardrails

- Do not force-push `main`.
- Do not commit or push unrelated dirty/untracked files just to clear status.
- Treat local branches with no upstream as separate decisions unless the current issue explicitly owns them.
- Treat divergent `main` as a reconciliation task, not as part of a feature-branch sync.
- Fetch before reporting branch state so ahead/behind counts use fresh remote refs.

## Current Baseline from WEI-1033

On 2026-05-13, the task worktree was clean, had no tags, and branch `WEI-1032-get-github-synced-from-this-computer-to-the-cloud` initially had no upstream. Other local branches had separate divergence/no-upstream state and were not pushed under this issue because their ownership was ambiguous.
