# WPR2 GitHub PR Disposition Workflow

## Trigger and owner

Use during each CTO-owned WPR2 PR-queue or branch/worktree hygiene pass: before assigning WPR2 coding work and whenever GitHub checks, review events, or dependency completion wake a queue item. CTO owns queue disposition; LocalFirstReviewer provides the non-author review lane for a proposed merge or destructive cleanup. GitHub is authoritative for PR head, checks, reviews, and merge state; Paperclip is authoritative for execution ownership and blockers.

## Inputs and prerequisites

- Repo: `xXKillerNoobYT/Weird-Part-Run-2`, canonical checkout `/Users/IA/GitHub/Weird-Part-Run-2`.
- Authenticated `gh`, authenticated Git remote, and Paperclip API environment variables.
- Fresh `git fetch --prune origin`.
- Current-head required-check, review-thread, and required iPhone/iPad device evidence.
- Paperclip merge/disposition issue state, including blockers, linked implementation/review/QA issues, owner, and current run.

## Serialized process

1. Inventory every open PR and its current Paperclip merge/disposition lineage. Order candidates by priority (`critical`, `high`, `medium`, `low`, then unset) and then oldest creation time. Record current head SHA, draft state, base, merge state, required checks, linked GitHub/Paperclip issues, and unresolved GraphQL review threads.
2. Classify each PR as exactly one of: `merge now`, `repair`, `await external evidence`, or `close as superseded`. Reuse and update the current-head lineage card; do not create duplicate review, retry, or blocker cards.
3. Select only the oldest unblocked candidate in that order. Do not select blocked work as routine queue work without a concrete unblock signal.
4. `merge now` requires all of: non-draft; branch current with `main`; required checks passing on the exact current head; zero unresolved non-outdated review threads; linked Paperclip implementation/review/QA issues done or cancelled; sequential merge-chain position; and all required non-author review evidence. Update the branch, re-verify exact-head checks, squash merge one PR, then read back merged GitHub state and new `main` SHA before selecting another.
5. `repair` requires the smallest bounded Paperclip implementation or review-fix issue with an owner, exact defect, acceptance criteria, required evidence, review lane, pass-up trigger, and a real blocker/link from its merge lineage. Do not close a viable repairable PR.
6. `await external evidence` requires a named physical, provider, owner, or security dependency with an owner, exact evidence condition, and review expiry. Keep only one root and the immediate executable child for a physical multi-device dependency.
7. `close as superseded` requires GitHub and Paperclip evidence that equivalent or newer work is merged or retained in a successor. Comment with that evidence before closing the PR or branch.

## No-gate-bypass rules

- Never weaken, skip, or substitute branch protection, required checks, exact-head validation, device gates, non-author review, approval requirements, security controls, or unresolved-review-thread requirements to achieve a disposition or merge.
- A missing, failed, stale, or inaccessible check is unmeasured evidence, not a passing gate. Retry with a narrower query or alternate supported source; otherwise use `repair` or `await external evidence`.
- Never merge more than one candidate at a time, merge out of priority-and-age order, or merge a candidate whose Paperclip lineage still has an unresolved blocker.
- Never close a PR merely because it is old. `close as superseded` requires the successor/merged evidence defined above.

## Stale and duplicate-run handling

1. Before creating any repair, review, retry, or blocker action, inspect the current PR head and linked Paperclip lineage. Update or reuse the existing current-head card when it covers the same root cause.
2. When a head changes, link the successor to the predecessor. Retain the predecessor only until its evidence is absorbed, then disposition it as superseded with issue-level evidence and owner acknowledgement.
3. If an earlier queue pass or API write is incomplete, leave the PR/worktree intact, record the incomplete evidence, and create or reuse only the smallest owned recovery action. Do not infer a clean state from missing output.

## Worktree and branch hygiene

1. Before cleanup, inspect every registered worktree: branch, `git status --porcelain`, upstream/ahead/behind state, commits not in `origin/main`, GitHub PR/merge state, and Paperclip owner/run state.
2. A local worktree and branch are eligible for deletion only if all are true: clean; no active or queued Paperclip issue/heartbeat owns it; no unique commits not in `origin/main`; and GitHub evidence shows it merged, superseded, or abandoned.
3. Never delete a live worktree, unpushed work, PR, remote branch, canonical-checkout modification, source, or history without the preceding proof.
4. Use the sequential route: record candidate evidence; obtain LocalFirstReviewer review for destructive cleanup; remove only the local worktree; read back `git worktree list`; delete a merged/superseded branch only after proving no worktree retains it; read back branch state. `git worktree prune -v` is allowed only for already-missing directories.

## Evidence, logs, failure handling, and escalation

- Record command output in the Paperclip disposition issue: worktree/branch totals, candidate rows, PR URLs/head/check URLs, Paperclip issue links, any deletion readback, and final disk impact.
- Store transient command output in `$PAPERCLIP_RUN_SCRATCH_DIR`; commit only the durable workflow or an intentional audit artifact.
- If a command/API result errors or returns an unexpected shape, state it as unmeasured and retry with a narrower query or supported alternative before classifying it.
- On a failure, retain the worktree and create or reuse the smallest owner-bound repair or blocker issue. Escalate to the CEO only for a real policy, resourcing, external-access, security, or owner-decision gate.
- CTO reviews this workflow after any incorrect disposition, failed cleanup, or recurring queue-stall pattern.

## Completion criteria

Every open PR has a current disposition and owner action. Every candidate is either safely drained with readback or retained with evidence and an owner. The Paperclip closeout includes a `GitHub sync:` line, residual risks, final counts, and the next owner/action.
