# WPR2 GitHub PR Disposition

## Owner and trigger

- **Owner:** CTO
- **Trigger:** CTO heartbeat assigned to the active WPR2 PR-disposition control issue, or a GitHub/Paperclip wake showing a PR head, check, review, dependency, or merge state changed.
- **Scope:** `xXKillerNoobYT/Weird-Part-Run-2` open PRs and the directly linked Paperclip/GitHub issue lineage.
- **Non-goal:** do not weaken checks, review, device, security, or owner gates; do not close viable work for age alone.

## Inputs and prerequisites

1. Confirm the scoped Paperclip issue, current PR list, and any wake-specific PR evidence.
2. From the canonical checkout, run the hygiene preflight before creating a branch or child issue:
   - remote branch count;
   - open PR list;
   - registered worktrees and `git worktree prune -n -v` output.
3. Read current GitHub facts for every open PR: base/head SHA, draft status, merge state, required checks on the exact head, review decision, unresolved GraphQL review threads, PR body links, and linked closing GitHub issues.
4. Read directly linked Paperclip merge/repair/review/device/security issues and their blocker graph. GitHub is authoritative for PR state; Paperclip is authoritative for assigned execution ownership.
5. Before treating CI as blocked, inspect `.github/workflows` and GitHub runner state. Xcode/iOS work uses the local Mac runner labels; cloud gates remain on `ubuntu-latest` where configured.

## Serialized disposition procedure

1. Snapshot every open PR and classify it **exactly once** as:
   - `merge now`
   - `repair`
   - `await external evidence`
   - `close as superseded`
2. For every non-ready PR, reuse or update the current-head Paperclip card first. Create only the smallest bounded child or first-class external blocker when none exists. Every created child must name: owner role, repo/project, exact scope, acceptance criteria, required evidence, review lane, pass-up trigger, and any real `blockedByIssueIds` dependency.
3. A `blocked` card is valid only for a named, unresolved physical/owner/security/external dependency with an owner, evidence condition, and review expiry. Otherwise create a bounded recovery issue and keep the route actionable.
4. Keep one live lineage per PR. When the head changes, attach evidence to the current-head successor/root, preserve a predecessor only until its evidence is absorbed, then mark it superseded with issue-level evidence.
5. Queue PRs by priority (`critical`, `high`, `medium`, `low`, unset) and then oldest creation time. Exactly one earliest eligible PR may enter the merge route; later otherwise-ready merge issues must be blocked by the immediately prior merge issue.

## Merge-now predicate

A PR may be classified `merge now` only when all conditions hold simultaneously on its current head:

- it is not a draft and has no merge conflict / behind-base state;
- all linked Paperclip implementation, review, QA, and security issues are `done` or `cancelled`;
- required checks are green for the current head SHA, with no relevant pending/failed checks;
- all unresolved non-outdated GitHub review threads are resolved and the required agent review is recorded;
- applicable device, security, migration, and owner gates have concrete evidence;
- it is the sole first unblocked item in the priority/age chain.

For a qualifying candidate: update/rebase against current `main` if necessary, wait for required checks on the resulting exact head, squash-merge exactly one PR, then read back `state=MERGED`, `mergedAt`, merge commit, related GitHub closing issue state, and Paperclip dependency state before selecting the next candidate. Do not leave a proven candidate idle.

## GitHub issue and branch reconciliation

1. For each merged PR, verify closing-keyword links and close any still-open fixed GitHub issue with a PR/commit comment.
2. For remaining GitHub intake, verify whether it is active, duplicate, or already fixed before opening any Paperclip work; preserve a single existing umbrella when the root cause and fix are shared.
3. Route branch/worktree cleanup only after confirming clean, merged/superseded/abandoned status and no unique unpushed work. `git worktree prune -v` is safe only for missing-worktree metadata. Broad deletion or uncertain archaeology requires a bounded CTO/engineering issue.

## Evidence and records

- **Logs/artifacts:** Paperclip issue comment with timestamped GitHub/API readback; GitHub PR/CI/review URLs; Paperclip issue IDs and `blockedByIssueIds` readback; branch/worktree counts.
- **Cadence:** rerun on CTO PR-queue wakes and after GitHub checks/reviews/dependencies complete; do not create timer heartbeats without CEO authorization.
- **Failure handling:** if GitHub/Paperclip readback fails, record the failing endpoint/command class, keep the current card blocked only if access is genuinely required, and name the owner/action to restore access. Do not infer green state from stale evidence.
- **Issue threshold:** create a child only for a concrete current-head repair, review, device/security validation, or external decision. Reuse existing current-head cards otherwise.

## Acceptance criteria

A pass leaves one current classification per open PR with GitHub head/check/review evidence, a named next owner/action for every non-ready PR, a verified serialized merge candidate only when the predicate holds, and no weakened protection. The controller closeout includes `GitHub sync:` and explains why it should or should not wake CTO again.
