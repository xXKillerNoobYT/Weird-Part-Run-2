# WPR2 serialized GitHub PR disposition

- Status: canonical operating workflow
- Owner: CTO
- Repository: `xXKillerNoobYT/Weird-Part-Run-2`
- Paperclip project: WPR2 / `WEI`
- Review lane for workflow changes: `LocalFirstReviewer → GPTReviewer → ClaudeReviewer`
- Source issue: WEI-7451

## Purpose and trigger

This workflow is the only canonical route for WPR2 GitHub PR queue disposition. It prevents stale-head merges, parallel merge races, duplicate Paperclip control cards, and unsupported claims that a physical-device gate has passed.

Run one serialized queue pass when any of the following occurs:

- a Paperclip merge issue is assigned or wakes due to a dependency resolution;
- a GitHub PR receives a new commit, review/comment/resolution, or required-check update;
- a local Mac runner starts, fails, recovers, changes labels, or reports disk/runtime capacity changes;
- a new or changed PR needs its first merge-chain record; or
- the CTO performs the scheduled operational review cadence below.

Do not start a queue pass solely because an already-blocked evidence-access issue receives a no-delta status comment. A blocked card becomes actionable only on an explicit resume/reopen, a CTO @mention with an implementation delta, `issue_blockers_resolved`, newly attached evidence/credentials/artifacts, or a concrete source/head/check change.

## Scope and non-goals

- GitHub is authoritative for exact PR head/base SHA, diff, check-runs, branch protection, review state, unresolved threads, merge result, and linked GitHub issue state.
- Paperclip is authoritative for ownership, dependency chain, child/blocker lifecycle, and the execution disposition.
- This workflow never weakens GitHub protections, required checks, review requirements, security controls, or iPhone/iPad physical/simulator gates.
- This workflow does not authorize direct pushes to `main`, destructive worktree/branch deletion, production release, or App Store submission.
- Merges are allowed only through the one-at-a-time squash route after every predicate below is true.

## Prerequisites and current-source snapshot

1. Confirm GitHub CLI/API authentication and repository identity before any mutation:

   ```bash
   git remote get-url origin
   gh auth status
   gh repo view xXKillerNoobYT/Weird-Part-Run-2 --json nameWithOwner,defaultBranchRef
   ```

2. Fetch current Git refs; never use a stale local checkout as PR evidence:

   ```bash
   git fetch origin --prune
   git rev-parse origin/main
   ```

3. For every open PR, capture a current, exact-head snapshot. The queue record must include PR number/URL, author, draft state, created time, base ref/SHA, head ref/SHA, merge state, review decision, required-check state, and linked GitHub issues:

   ```bash
   gh pr list --repo xXKillerNoobYT/Weird-Part-Run-2 --state open --limit 100 \
     --json number,url,title,isDraft,createdAt,headRefName,headRefOid,baseRefName,baseRefOid,mergeStateStatus,reviewDecision,statusCheckRollup
   gh pr view <PR> --repo xXKillerNoobYT/Weird-Part-Run-2 \
     --json number,url,title,body,isDraft,createdAt,headRefName,headRefOid,baseRefName,baseRefOid,mergeStateStatus,reviewDecision,statusCheckRollup
   gh pr checks <PR> --repo xXKillerNoobYT/Weird-Part-Run-2 --required
   ```

4. Query unresolved review threads separately. `reviewDecision` and visible review summaries are insufficient evidence:

   ```bash
   gh api graphql -F owner=xXKillerNoobYT -F name=Weird-Part-Run-2 -F number=<PR> -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){headRefOid reviewThreads(first:100){nodes{isResolved isOutdated comments(first:1){nodes{url body}}}}}}}'
   ```

   Record any unresolved non-outdated thread as a blocker. Resolve a thread only when its exact concern is demonstrably addressed on the current head; record the evidence URL in Paperclip.

5. Read the linked GitHub issue acceptance criteria and all linked Paperclip work/review/QA/security issues. A green check does not replace unmet acceptance criteria, device evidence, or a real blocker.

6. Inspect current-head scope before disposition:

   ```bash
   gh pr diff <PR> --repo xXKillerNoobYT/Weird-Part-Run-2
   git diff --check origin/main...<HEAD_SHA>
   ```

   Record the exact head SHA in every comment, child issue, and review request. A changed head invalidates previous readiness evidence until the exact-head snapshot is refreshed.

## Local Mac runner and device evidence

For iOS/macOS/Xcode checks, inspect the repository workflow routes and runner availability before calling cloud capacity a blocker:

```bash
gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 20
rg -n "runs-on:" .github/workflows
gh pr checks <PR> --repo xXKillerNoobYT/Weird-Part-Run-2 --required
```

The intended trusted iOS path is `[self-hosted, macOS, ARM64, xcode, ios, local-mac]`. Current-head iPhone and iPad contexts must be completed and successful when the PR is subject to the iOS beta gate. Missing, queued, cancelled, stale-head, skipped, or failed contexts are not merge-ready. Preserve one physical-device root plus only the immediate next executable child; do not fan out duplicate device blockers while hardware is unavailable.

## Paperclip merge-chain reconciliation

1. Read all WPR2 merge issues and their blockers. For each GitHub PR, maintain one live current-head Paperclip merge issue/card that links the PR URL, branch, GitHub issue(s), source work issues, review/QA/security issues, exact head SHA, and required gate summary.
2. Reuse and update the current-head card. When a head changes, link any successor to the root/predecessor, copy only still-live blockers, absorb useful evidence, then mark the predecessor superseded with an issue-level evidence comment. Do not create parallel cards for the same live head.
3. Verify `blockedByIssueIds` with a Paperclip GET readback after every create/update. Text-only dependency claims are not sufficient.
4. Sort eligible merge issues by priority (`critical`, `high`, `medium`, `low`, unset), then oldest ready/created timestamp. Keep the oldest eligible issue unblocked; make every later eligible issue blocked by the immediately prior merge issue. This forms exactly one serialized chain.
5. If the chain is missing, wrong, or contains a stale predecessor, repair the current cards and dependency links before selecting a candidate. Do not create a new audit/control issue for a known active merge chain.

## Allowed dispositions

Every open PR must have exactly one current disposition, an accountable owner, concrete next action, current-head evidence, and a Paperclip comment.

| Disposition | When it applies | Accountable owner | Required next action |
|---|---|---|---|
| `merge now` | The full merge-now predicate is true and this is the oldest unblocked candidate. | CTO | Immediately run the one-at-a-time squash merge and read back GitHub/Paperclip state. |
| `repair` | The PR has a source defect, conflict, failed/stale check, unresolved applicable review thread, or unmet code/acceptance criterion that an engineering/review lane can change. | Relevant implementation owner; CTO owns routing. | Create or reuse the smallest current-head repair child, link it as a real blocker, name failing invariant/log/section, and require exact-head validation. |
| `await external evidence` | A first-class external dependency remains: unavailable device/runner/runtime, required owner decision/approval, security evidence, or GitHub service evidence that cannot be produced by the assigned agent. | Named external owner; CTO owns monitoring. | Leave the merge issue blocked with owner, exact evidence condition, review expiry, and only the immediate executable successor. On proof, re-run the exact-head snapshot. |
| `close as superseded` | A PR/card is demonstrably replaced by an equivalent or better current branch/PR, merged work, or approved scope cancellation. | CTO | Record predecessor and successor/merge evidence, reconcile links/issues, verify no unique unpushed work, then close the stale PR/card only with explicit evidence. |

Never classify a viable repairable PR as superseded because it is old. Never classify a PR `merge now` from a prior-head check or review.

## Repair and unblock child requirements

Create the smallest bounded child issue only when the work is not already tracked. Every new child must include:

- owner role and named assignee;
- repo/project and exact current-head scope;
- acceptance criteria and required evidence;
- review lane (`LocalFirstReviewer → GPTReviewer → ClaudeReviewer` unless a narrower approved lane applies);
- parent/goal linkage and real `blockedByIssueIds` where applicable;
- pass-up trigger to the parent merge issue; and
- for frontend work, route/screen plus desktop, tablet, and mobile evidence expectations and named UX/implementation/verifier owner.

For an unblock task, explicitly distinguish:

- **Proof supplied:** the required external evidence/artifact is attached/readable and identifies the exact PR head/check/device/run. This unblocks re-evaluation only.
- **Code fixed:** the source change is committed/pushed, tests/checks/reviews run on its new exact head, and all stated acceptance criteria are met. This is not satisfied by a chat acknowledgement or proof-only artifact.

## Merge-now predicate

A candidate may be merged only if all statements are true on one current snapshot:

1. It is the first unblocked priority/age-ordered merge issue; every earlier candidate is merged, cancelled, or a documented non-ready disposition.
2. The PR is open, non-draft unless explicitly approved otherwise, targets current `main`, and has no conflict/dirty merge state.
3. All linked Paperclip implementation, review, QA, security, and prerequisite issues are `done` or `cancelled`; the merge issue itself has readable GitHub/Paperclip traceability.
4. The branch is current with `main` after the preceding serialized merge.
5. Every required GitHub check is successful on `headRefOid`; no check is pending, queued, cancelled, stale, skipped, or failed.
6. All unresolved applicable review threads are resolved; required independent review evidence exists on the final head.
7. The required review lane completed in order on the same exact head: `LocalFirstReviewer → GPTReviewer → ClaudeReviewer`.
8. The linked GitHub issue acceptance criteria are satisfied, including migration, security, backup/durability, and applicable user-like UI evidence.
9. Required iPhone/iPad/local-runner gate evidence is successful on the exact head; genuine hardware/owner gates remain satisfied rather than bypassed.
10. No owner, security, product, release, or external evidence blocker remains.

If any line is false, use `repair` or `await external evidence`; do not merge.

## Serialized squash-merge and readback

1. Re-fetch the target PR immediately before merge and confirm its head SHA still matches the selected candidate record.
2. Update/rebase it against current `main` using the repository-approved route. If the head changes, reset readiness and repeat the exact-head required-check/review sequence.
3. Re-check every merge-now predicate item after the update. Do not treat pre-update checks as transferable.
4. Squash-merge exactly one PR:

   ```bash
   gh pr merge <PR> --repo xXKillerNoobYT/Weird-Part-Run-2 --squash --delete-branch
   ```

5. Read back GitHub state before touching the next candidate:

   ```bash
   gh pr view <PR> --repo xXKillerNoobYT/Weird-Part-Run-2 --json state,mergedAt,mergeCommit,url,headRefName
   git fetch origin --prune
   git rev-parse origin/main
   ```

   Confirm `state=MERGED`, `mergedAt` is set, `mergeCommit` exists, and `origin/main` contains the merge commit. Verify GitHub branch-cleanup state separately; merge success alone is not proof that cleanup completed.

6. Reconcile GitHub issues: confirm each linked `Closes #N` issue is closed only when the merged PR actually resolved it. Comment/close a still-open truly-fixed issue with merge evidence; leave unrelated/open acceptance work open.
7. Update the Paperclip merge issue with exact head, merge commit, GitHub URLs, check/review/device evidence, cleanup state, residual risk, and next owner. Mark it done only after the readback. Then promote/re-evaluate only the next chain candidate.

## Evidence, logs, and artifacts

Keep durable evidence in GitHub/Paperclip; do not rely on an agent transcript.

- GitHub PR URL, exact head/base SHA, diff/check/review-thread queries, workflow run/check URLs, merge commit, and linked GitHub issue URLs go in the current Paperclip merge card/comment.
- Local test output belongs in the run-owned Paperclip scratch directory (`$PAPERCLIP_RUN_SCRATCH_DIR`) or CI artifact. Reference the path/URL and command/result in the Paperclip comment; do not store secrets.
- iOS gate logs, `.xcresult`, summaries, and provenance artifacts are the GitHub Actions artifacts retained by the workflow; cite their run/check URLs.
- Local runner diagnosis evidence includes runner API output, workflow `runs-on` source location, and relevant `gh run` URL/ID.
- Worktree cleanup evidence is a final owner comment stating GitHub sync, PR/branch state, whether the worktree was removed or intentionally retained, and the next owner if retained.

## Failure handling and escalation

- **GitHub/API/auth failure:** do not infer clean state. Record the command/error and use `await external evidence` with the accountable owner/action when access cannot be restored by the CTO.
- **Runner offline/mislabelled, disk/runtime shortage, or failed iOS context:** create/reuse the bounded infrastructure repair/blocker; attach exact runner/check/log evidence and preserve the real gate.
- **CI failure or review defect:** use/reuse a repair child linked to the current merge card. A new code head invalidates old readiness evidence.
- **Missing traceability or duplicate chains:** repair/reuse the live card and blockers; do not create duplicate successor/control issues.
- **Merge failure/readback mismatch:** stop the queue, keep the candidate actionable as `repair`, create/reuse a merge-recovery child with exact error evidence, and do not select another PR.
- **Uncertain destructive cleanup or branch archaeology:** do not delete. Create a bounded CTO/engineering child with evidence requirements.
- **Security, data-loss, scope, or priority conflict:** escalate to the CEO early with the exact decision needed; do not guess or bypass a gate.

## Review cadence and issue threshold

- Evaluate the queue on each qualifying wake signal and at least once per CTO operating day while any WPR2 merge issue is open.
- At each pass, classify every open PR, but select only one merge-now candidate.
- Open/reuse a Paperclip issue immediately for any failure that blocks a merge, repeats on two queue passes, causes a stale/duplicate lineage, threatens data/security, or prevents the local runner from producing required evidence.
- Do not create a new issue for a one-off transient that recovers in the same pass with durable GitHub evidence; record it on the current merge card instead.
- Revisit `await external evidence` cards by their stated review expiry or a qualifying wake signal, not by repeated no-delta polling.

## Verification checklist for this workflow

Before claiming a queue pass complete, the CTO must verify and comment:

- current-source GitHub snapshot and exact head SHA;
- disposition, owner, and concrete next action for every open PR;
- Paperclip current-head/blockedBy readback and serialized priority/age order;
- required checks, independent reviews, unresolved-thread state, linked acceptance criteria, and applicable local-runner/device evidence;
- if merged: squash merge/readback, GitHub issue reconciliation, branch/worktree cleanup state, and next candidate promotion;
- log/artifact paths or URLs, failure/escalation state, and next review cadence.

A workflow/document-only change follows the same source control evidence rule: validate the exact repository path, commit it with the Paperclip co-author trailer, push it, link the commit/PR in Paperclip, and send it through the stated review lane before treating the workflow as approved for merge use.
