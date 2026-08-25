# WPR2 GitHub PR Disposition Workflow

## Trigger and owner

Use during each CTO-owned WPR2 PR-queue or branch/worktree hygiene pass. CTO owns queue disposition; LocalFirstReviewer provides the non-author review lane for a proposed merge or destructive cleanup. GitHub is authoritative for PR head, checks, reviews, and merge state; Paperclip is authoritative for execution ownership and blockers.

## Inputs and prerequisites

- Repo: `xXKillerNoobYT/Weird-Part-Run-2`, canonical checkout `/Users/IA/GitHub/Weird-Part-Run-2`.
- Authenticated `gh`, authenticated Git remote, and Paperclip API environment variables.
- Fresh `git fetch --prune origin`.
- The required iPhone/iPad device checks and current-head review-thread evidence.

## Serialized process

1. Inventory all open PRs by priority then creation time. For each, record current head SHA, draft state, current base, merge state, required checks, linked GitHub/Paperclip issues, and unresolved GraphQL review threads.
2. Classify each PR as exactly one of: `merge now`, `repair`, `await external evidence`, or `close as superseded`.
3. `merge now` requires: non-draft; branch current with `main`; all required checks passing on the current head; zero unresolved non-outdated review threads; linked Paperclip implementation/review/QA issues done or cancelled; sequential merge-chain position; and all required non-author review evidence. Update the branch, re-verify exact-head checks, squash merge one PR, then read back merged state and new `main` SHA before selecting another.
4. `repair` requires one bounded Paperclip implementation/review-fix issue with owner, exact defect, acceptance criteria, evidence, review lane, pass-up trigger, and real blocker link from its merge lineage. Do not close a viable repairable PR.
5. `await external evidence` requires a named physical, provider, owner, or security dependency with owner, evidence condition, and review expiry. Keep only one root and immediate executable child for a physical multi-device dependency.
6. `close as superseded` requires GitHub/Paperclip evidence that equivalent or newer work is merged or retained in a successor. Comment with that evidence before closing the PR/branch.

## Worktree and branch hygiene

1. Before cleanup, inspect every registered worktree: branch, `git status --porcelain`, upstream/ahead/behind state, commits not in `origin/main`, GitHub PR/merge state, and Paperclip owner/run state.
2. A local worktree and branch are eligible for deletion only if all are true: clean; no active/queued Paperclip issue or heartbeat owns it; no unique commits not in `origin/main`; and GitHub evidence shows it merged, superseded, or abandoned.
3. Never delete a live worktree, unpushed work, PR, remote branch, canonical-checkout modification, source, or history without the preceding proof.
4. Use the sequential route: record candidate evidence; obtain LocalFirstReviewer review for destructive cleanup; remove only the local worktree; read back `git worktree list`; delete a merged/superseded branch only after proving no worktree retains it; read back branch state. `git worktree prune -v` is allowed only for already-missing directories.

## Evidence, logs, and failure handling

- Record command output in the Paperclip issue comment: worktree/branch totals, candidate rows, PR URLs/head/check URLs, Paperclip issue links, deletion readback, and final disk impact.
- Store transient command output in `$PAPERCLIP_RUN_SCRATCH_DIR`; commit only the durable workflow or an intentional audit artifact.
- If a command/API result is incomplete or errors, state it as unmeasured and retry with a narrower query or alternative before dispositioning. Do not infer cleanliness or merge readiness from missing evidence.
- On a failure, retain the worktree and create/reuse the smallest owner-bound repair/blocker issue.

## Cadence and thresholds

- Run before assigning new WPR2 coding work, and when a PR check/review/dependency completion wakes the queue.
- If worktrees exceed 20, remote branches exceed 25, or any candidate cannot be tied to a current owner/action, open or keep a hygiene root active until inventory and disposition are current.
- CTO reviews this workflow after any incorrect disposition, failed cleanup, or recurring queue-stall pattern.

## Completion criteria

Every open PR has a current disposition and owner action. Every candidate is either safely drained with readback or retained with evidence and an owner. The Paperclip closeout includes a GitHub sync line, residual risks, final counts, and the next owner/action.
