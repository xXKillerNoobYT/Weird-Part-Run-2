# WPR2 GitHub PR disposition

## Trigger and owner

CTO runs this workflow whenever a Paperclip heartbeat, GitHub check/review event, or dependency-completion wake concerns an open WPR2 pull request. The scope is `xXKillerNoobYT/Weird-Part-Run-2`. CTO owns queue classification and serialized merge execution; implementation/review work is delegated to the appropriate engineering or review lane.

## Inputs and prerequisites

- Current GitHub PR metadata, commits, reviews, unresolved threads, checks, and merge state.
- Current Paperclip merge/source/review/QA issue states and blockers.
- Repository worktree/branch hygiene preflight: remote-branch count, open-PR count, `git worktree list --porcelain`, and `git worktree prune -v`.
- Local Mac Actions runner status and recent run URLs for iOS/Xcode work.

Never infer readiness from age, branch naming, or an old CI result. Do not modify branch protection or bypass an unresolved review/security/owner gate.

## Procedure

1. List every open PR and classify each one: `merge now`, `repair`, `await external evidence`, or `close as superseded`.
2. Record the GitHub URL, current head SHA, draft/conflict/behind state, checks, review decision, unresolved-thread state, linked GitHub issues, and linked Paperclip source/review/QA/merge issues.
3. Reuse the current-head Paperclip card. When a head changes, link its successor/root, absorb predecessor evidence, then disposition the predecessor as superseded; do not create duplicate liveness cards.
4. Apply priority (`critical`, `high`, `medium`, `low`, unset), then age, to the serialized queue. Only the oldest unblocked candidate can be promoted.
5. `merge now` requires all of: non-draft, current with `main`, conflict-free, required checks green on the current head, GitHub review requirements satisfied, unresolved threads resolved, all linked Paperclip work `done` or `cancelled`, and first position in the merge chain.
6. For a proven `merge now` candidate, perform one-at-a-time squash merge, delete the merged remote branch only through the successful merge route, then read back GitHub and Paperclip state before evaluating the next candidate.
7. `repair` requires the smallest owner-specific child issue with exact failure evidence, required validation, review lane, and pass-up trigger. `await external evidence` names the physical/owner/security dependency, evidence condition, and review expiry. `close as superseded` records the successor or merged replacement evidence before closure.
8. Update every touched Paperclip issue with status, what changed, blocker/next owner action, and a `GitHub sync:` line.

## Outputs and evidence

- A current disposition table in the owning Paperclip issue/comment, including a link for every PR.
- For each merge: squash-merge URL/SHA, post-merge GitHub state, Paperclip merge-issue disposition, and cleanup note for retained/removed worktree.
- For each repair/blocker: one bounded child issue or existing current-head card, not a duplicate escalation.
- Commands/results: `gh pr list`, `gh pr view`, `gh run list`, runner API output, `git worktree list --porcelain`, branch/upstream evidence, and relevant CI logs.

## Failure handling and cadence

- On missing runner/CI evidence, inspect the runner state and workflow `runs-on` configuration; route Xcode work to the local Mac runner when eligible.
- On an ambiguous destructive action, stop and obtain `LocalFirstReviewer → GPTReviewer → ClaudeReviewer` review before cleanup.
- On a physical multi-device block, retain one root plus only the immediate next executable child; do not fan out per-PR descendants.
- A PR check, resolved review, or dependency completion is a wake signal. Re-run the queue at that point; do not wait for manual reminder.
- The CTO reviews this workflow after any incorrect disposition, duplicate PR lineage, or cleanup-related incident.

## Acceptance criteria

- Every open PR has exactly one current classification with live GitHub/Paperclip evidence.
- No merge occurs outside the serialized oldest-unblocked route.
- Non-ready PRs have one smallest executable child or one first-class external dependency.
- No remote/local branch, PR, or worktree is removed solely due to age.
