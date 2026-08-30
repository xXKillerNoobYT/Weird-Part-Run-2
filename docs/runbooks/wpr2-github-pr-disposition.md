# WPR2 GitHub PR Disposition Workflow

## Purpose, owner, and non-goals

This is the canonical serialized disposition route for every open PR in
`xXKillerNoobYT/Weird-Part-Run-2` (WPR2). Use it on each CTO PR-queue pass,
before starting additional WPR2 coding work, and when a GitHub check, resolved
review, dependency completion, or explicit unblock signal wakes a merge card.

- **Accountable owner:** CTO.
- **Review lane:** `LocalFirstReviewer → GPTReviewer → ClaudeReviewer` for a
  workflow/change PR and for each merge candidate's required non-author review.
- **Sources of truth:** GitHub for PR head, checks, reviews, threads, and merge
  state; Paperclip for execution ownership, merge-chain order, and blockers.
- **Non-goals:** this workflow does not authorize retention cleanup, deletion of
  live worktrees/branches/PRs, changing protections, bypassing device gates, or
  merging an otherwise ineligible PR.

## Inputs and prerequisites

Use the canonical checkout `/Users/IA/GitHub/Weird-Part-Run-2`, an authenticated
`gh` CLI, authenticated Git remote, and the Paperclip environment variables
(`PAPERCLIP_API_URL`, `PAPERCLIP_API_KEY`, `PAPERCLIP_RUN_ID`). Do not print
credentials. Set an API base once per pass:

```bash
api="${PAPERCLIP_API_URL%/}"
case "$api" in */api) ;; *) api="$api/api" ;; esac
git fetch --prune origin
```

Required inputs for every candidate are:

1. Its PR number/URL, current `headRefOid`, base SHA, draft state, creation
   time, and current merge state.
2. Exact-head required-check evidence, including both `iOS Beta Gate (iPhone)`
   and `iOS Beta Gate (iPad)` for same-repository WPR2 PRs.
3. A current unresolved-review-thread readback, linked GitHub issues, and linked
   Paperclip implementation/review/QA/merge cards with their statuses.
4. Local-runner state whenever CI is pending, failed, unavailable, or discussed.

A missing, stale, queued, skipped, failed, cancelled, inaccessible, or
unexpectedly-shaped result is **unmeasured**, never a passing gate.

## Exact-head snapshot commands

Run and attach/summarize these read-only commands before disposition. Save full
unredacted command output only in `$PAPERCLIP_RUN_SCRATCH_DIR`; Paperclip
comments contain concise findings plus URLs/identifiers.

```bash
repo=xXKillerNoobYT/Weird-Part-Run-2

gh pr list --repo "$repo" --state open --limit 200 \
  --json number,title,url,isDraft,headRefName,headRefOid,baseRefName,baseRefOid,\
createdAt,updatedAt,mergeStateStatus,reviewDecision,statusCheckRollup

gh pr view "$PR" --repo "$repo" \
  --json number,url,isDraft,headRefName,headRefOid,baseRefName,baseRefOid,\
mergeStateStatus,reviewDecision,createdAt,updatedAt,statusCheckRollup,reviews,comments

gh api "repos/$repo/pulls/$PR" \
  --jq '{number,html_url,draft,head:{ref:.head.ref,sha:.head.sha},base:{ref:.base.ref,sha:.base.sha},mergeable,mergeable_state}'

gh api graphql -f query='query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){ pullRequest(number:$number){
    reviewThreads(first:100){ nodes { isResolved isOutdated path comments(first:1){nodes{url}} } }
  }}}' -f owner=xXKillerNoobYT -f repo=Weird-Part-Run-2 -F number="$PR"

# GitHub has no supported `GET /repos/{owner}/{repo}/pulls/{pull_number}/issues`
# endpoint. Query the PR's closing-linked issues through GraphQL instead. A query
# failure (including auth, transport, or an unavailable/404 endpoint) is
# UNMEASURED/ERROR, never an empty linked-issue result.
linked_issues_log="${PAPERCLIP_RUN_SCRATCH_DIR:?}/wpr2-pr-disposition/linked-issues-$PR.json"
mkdir -p "$(dirname "$linked_issues_log")"
if ! gh api graphql \
  -f query='query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){ pullRequest(number:$number){
      number
      closingIssuesReferences(first:100){ totalCount nodes { number title url state } }
    }}
  }' \
  -f owner=xXKillerNoobYT -f repo=Weird-Part-Run-2 -F number="$PR" \
  >"$linked_issues_log" 2>&1; then
  printf 'UNMEASURED/ERROR: closing-linked-issue query failed for PR #%s; see %s. Do not classify this as no linked issues.\n' \
    "$PR" "$linked_issues_log" >&2
  exit 1
fi
validate_closing_issues_response() {
  jq -e --argjson expected_pr "$PR" '
    (if has("errors") then (.errors | type == "array" and length == 0) else true end)
    and (.data | type == "object")
    and (.data.repository | type == "object")
    and (.data.repository.pullRequest | type == "object")
    and (.data.repository.pullRequest.number | type == "number" and . == $expected_pr)
    and (.data.repository.pullRequest.closingIssuesReferences | type == "object")
    and (.data.repository.pullRequest.closingIssuesReferences.totalCount
         | type == "number" and floor == . and . >= 0)
    and (.data.repository.pullRequest.closingIssuesReferences.nodes | type == "array")
    and ([.data.repository.pullRequest.closingIssuesReferences.nodes[]
          | type == "object"
            and (.number | type == "number" and floor == . and . > 0)
            and (.title | type == "string")
            and (.url | type == "string")
            and (.state | type == "string")]
         | all)
  ' "$1"
}

if ! validate_closing_issues_response "$linked_issues_log"; then
  printf 'UNMEASURED/ERROR: closing-linked-issue query returned an unexpected GraphQL envelope for PR #%s; see %s. Do not classify this as no linked issues.\n' \
    "$PR" "$linked_issues_log" >&2
  exit 1
fi

# Deliberately query an unavailable *non-linked-issues* resource. Its required
# 404 proves transport/API failures are visibly classified as UNMEASURED/ERROR,
# without reintroducing the invalid pulls/$PR/issues endpoint.
unavailable_probe_log="${PAPERCLIP_RUN_SCRATCH_DIR:?}/wpr2-pr-disposition/unavailable-probe-$PR.log"
if gh api "repos/$repo/pulls/$PR/__wpr2_deliberately_unavailable_probe__" \
  >"$unavailable_probe_log" 2>&1; then
  printf 'UNMEASURED/ERROR: deliberate unavailable-query probe unexpectedly succeeded for PR #%s; see %s.\n' \
    "$PR" "$unavailable_probe_log" >&2
  exit 1
fi
if ! rg --fixed-strings --quiet 'HTTP 404' "$unavailable_probe_log"; then
  printf 'UNMEASURED/ERROR: deliberate unavailable-query probe did not return the expected 404 for PR #%s; see %s.\n' \
    "$PR" "$unavailable_probe_log" >&2
  exit 1
fi
printf 'PASS: deliberate unavailable-query 404 for PR #%s is classified as UNMEASURED/ERROR; see %s.\n' \
  "$PR" "$unavailable_probe_log"

# Negative controls: each malformed response must be rejected, rather than being
# treated as an empty linked-issue connection. Keep fixtures in run scratch.
fixture_dir="${PAPERCLIP_RUN_SCRATCH_DIR:?}/wpr2-pr-disposition/linked-issue-fixtures-$PR"
mkdir -p "$fixture_dir"
jq -n '{data:{repository:{pullRequest:null}}}' >"$fixture_dir/null-pull-request.json"
jq -n --argjson pr "$PR" '{data:{repository:{pullRequest:{number:$pr,closingIssuesReferences:{totalCount:"0",nodes:[]}}}}}' >"$fixture_dir/wrong-total-count-type.json"
jq -n --argjson pr "$PR" '{errors:[{message:"deliberate GraphQL error"}],data:{repository:{pullRequest:{number:$pr,closingIssuesReferences:{totalCount:0,nodes:[]}}}}}' >"$fixture_dir/graphql-errors.json"
for fixture in "$fixture_dir"/*.json; do
  if validate_closing_issues_response "$fixture"; then
    printf 'UNMEASURED/ERROR: negative fixture was accepted: %s.\n' "$fixture" >&2
    exit 1
  fi
done
# A rejected negative control exits nonzero by design; normalize the successful
# fixture suite's final status so the surrounding snapshot script can continue.
true
```

The candidate head is authoritative only when all head-bearing responses agree
on the same SHA. Check records are admissible only when their associated SHA is
the current PR `headRefOid`; re-query after any rebase, force-push, or merge
before acting.

## Paperclip merge-chain snapshot and ordering

1. Fetch the merge/disposition card and its parent/child/root lineage through
   `GET $api/issues/{issueId}/heartbeat-context`, then read its linked issue
   statuses and `blockedByIssueIds`. Read a changed-head successor/root before
   creating any new card.
2. Inventory every open PR and its current Paperclip merge card. Classify
   priority as `critical`, `high`, `medium`, `low`, then unset; within a priority
   bucket use oldest PR/merge-card creation time first.
3. The oldest unblocked candidate is the only active serialized merge candidate.
   Later candidates must be blocked by the immediately prior merge card. Do not
   select a blocked card merely because it is assigned; a concrete unblock event
   is required.
4. Every PR gets exactly one active current-head lineage. When a head changes,
   link its successor/root to the predecessor, absorb valid evidence, and
   disposition the predecessor as superseded. Do not create parallel retry,
   review, or blocker cards for the same root cause.

## Dispositions and accountable next actions

Every open PR receives exactly one current disposition:

| Disposition | Required evidence | Accountable owner and concrete next action |
| --- | --- | --- |
| **merge now** | All predicate items below are true at one exact head. | **CTO:** perform the single squash merge, then read back GitHub/Paperclip state before selecting another PR. |
| **repair** | A reproducible code/config/review/CI defect, conflict, stale base, or unresolved thread prevents the predicate. | **CTO:** create or reuse the smallest owner-bound implementation/review-fix/CI-fix child; link it to the current merge card and block that card on it. The child states exact scope, acceptance criteria, required evidence, review lane, and pass-up trigger. |
| **await external evidence** | A physical device, provider, owner, security, credential, or external service dependency cannot be produced by the current engineering lane. | **CTO:** retain one root and only the immediate next executable child; record owner, exact required evidence, review expiry, and wake signal. Re-evaluate on evidence arrival; do not create liveness duplicates. |
| **close as superseded** | GitHub and Paperclip prove equivalent/newer work is merged or retained in a named successor, with no unique unpushed work. | **CTO:** add the successor/merged evidence to the active card, reconcile linked GitHub issues, and close only the superseded PR/card after readback. Age alone is never evidence. |

## Merge-now predicate

The active candidate may be squash-merged only if all conditions are true:

- It is non-draft, targets the intended base, and is current with `main` after
  the immediately prior serialized merge.
- GitHub reports a clean/mergeable state and all required checks pass on the
  current head SHA. Both iPhone/iPad beta gates must be current-head, completed,
  non-skipped, nonzero-test evidence; `Analyze (swift)` does not substitute for
  either device lane.
- All non-outdated review threads are resolved; required non-author reviews are
  complete in the stated lane, and no owner/security/product blocker remains.
- Every linked Paperclip implementation, review, QA, and source issue is `done`
  or `cancelled`; all lineage blockers are cleared and this is the first
  unblocked priority/age-ordered merge card.
- GitHub↔Paperclip traceability is readable: PR body/GitHub issue/Paperclip card
  reference each other and the PR's `Closes`/`Refs` keywords are correct.
- Required local runner evidence was checked. If a relevant job needs Apple
  tooling, it uses the trusted same-repository local Mac runner path described
  in `docs/runbooks/local-mac-actions-runner.md`.

Do not weaken, skip, substitute, or manually override branch protection,
required checks, exact-head validation, device gates, review, security,
approval, or unresolved-thread requirements.

## Serialized squash merge and readback

For exactly one candidate that meets the predicate:

```bash
# Repeat the exact-head snapshot immediately before this command.
gh pr merge "$PR" --repo xXKillerNoobYT/Weird-Part-Run-2 --squash --delete-branch

gh pr view "$PR" --repo xXKillerNoobYT/Weird-Part-Run-2 \
  --json state,mergedAt,mergeCommit,url,headRefName

gh api repos/xXKillerNoobYT/Weird-Part-Run-2/git/ref/heads/main \
  --jq '.object.sha'
```

Then read back the merge card, linked Paperclip source issues, and the next
serialized card. Mark only the merged lineage `done` with a final `GitHub sync:`
line. Rebase/update the next candidate onto the new `main`, obtain new
exact-head evidence, and only then reclassify it. Never start a second merge
while the first merge/readback is incomplete.

## GitHub issue reconciliation

Before merge, verify the PR body contains the relevant GitHub issue closing or
reference keywords and relevant `WEI-` identifiers. After GitHub readback:

1. Confirm each closing-linked GitHub issue actually closed. If a truly fixed
   issue remains open, comment with the PR/merge evidence and close it through
   normal GitHub issue controls.
2. Update the Paperclip merge/source cards with the PR URL, merge SHA, GitHub
   issue state, checks, review disposition, residual risk, cleanup state, and
   next owner action.
3. If an issue is not fixed, do not close it from merge state alone: create or
   retain the smallest bounded recovery issue and keep the original lineage
   accurate.

## Local-runner evidence

Before classifying CI as blocked or inaccessible, check:

```bash
gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 10
rg -n 'runs-on:' .github/workflows
```

For iOS/macOS/Xcode work, the trusted same-repository runner labels are
`[self-hosted, macOS, ARM64, xcode, ios, local-mac]`. An offline, busy, or
mislabelled runner is external evidence only when the comment records the
specific runner state, checked command/run URL, named owner, remediation, and
review expiry. Do not run untrusted fork code on that runner.

## Unblock semantics

A blocker child distinguishes these outcomes explicitly:

- **Proof supplied:** the named owner attached or linked the requested device,
  provider, review, credential, or runner evidence. This unblocks *evaluation*
  only; no code is claimed fixed.
- **Code fixed:** an implementation PR/current head contains the repair, focused
  validation passed, review requirements are met, and exact-head checks prove
  the fix. Only this outcome can satisfy a code/CI repair acceptance criterion.

On proof supplied, re-snapshot the current head and either promote the existing
card or create the smallest remaining repair; do not mark the implementation
issue done from an acknowledgement alone.

## Logs, artifacts, cadence, and issue threshold

- **Log location:** transient CLI/API output goes in
  `$PAPERCLIP_RUN_SCRATCH_DIR/wpr2-pr-disposition/`; durable evidence is a
  concise Paperclip issue comment with PR/run/artifact URLs. Never commit logs
  containing credentials, raw secrets, or private device data.
- **Review cadence:** run this procedure at every CTO queue pass, after a PR
  check/review/dependency wake, after a merged predecessor, and after any wrong
  disposition or cleanup failure. Do not use a timer/cron unless the CEO has
  explicitly enabled one.
- **Failure handling:** keep worktrees/branches/PRs intact, mark evidence
  unmeasured, retry with a narrower supported query or source, and create/reuse
  the smallest owner-bound repair or first-class blocker. Escalate only real
  policy, resourcing, external-access, security, or owner-decision gates.
- **Issue threshold:** create or update a Paperclip repair/blocker after the
  first reproducible missing/failed/stale device gate, CI failure, unresolved
  review defect, runner outage, or invalid lineage. Reuse the active card for
  the same root cause; never spray duplicate descendants.

## Verification and closeout evidence

A queue pass is complete only when every open PR has one of the four
 dispositions, an accountable owner, a concrete next action, and current-head
 evidence. Each touched Paperclip issue receives a concise markdown comment:

- status/disposition and what changed;
- exact PR/head/check/review/run or artifact URLs;
- blocker owner/evidence condition/review expiry when blocked;
- `GitHub sync:` as `pushed/PR/commented URL`, `existing PR/CI URL`, `not
  applicable with reason`, or `blocked with owner/action`;
- residual risk and explicit next owner action.

For this workflow itself, validation is: read the canonical path from the
assigned workspace and reproducibly locate the `## Logs, artifacts, cadence,
and issue threshold` heading plus each distinct requirement bullet. Each
assertion is fail-fast: a missing, duplicated, or renamed anchor stops the
validation immediately and cannot be masked by a later successful assertion.

```bash
workflow=docs/runbooks/wpr2-github-pr-disposition.md
validate_closeout_anchors() {
  local candidate="$1" section anchor matches
  section=$(sed -n \
    '/^## Logs, artifacts, cadence, and issue threshold$/,/^## Verification and closeout evidence$/p' \
    "$candidate") || return 1

  for anchor in \
    '## Logs, artifacts, cadence, and issue threshold' \
    '- **Failure handling:**' \
    '- **Review cadence:**' \
    '- **Issue threshold:**'; do
    matches=$(printf '%s\n' "$section" | rg --fixed-strings -- "$anchor" | wc -l | tr -d ' ')
    if [ "$matches" -ne 1 ]; then
      printf 'FAIL: expected exactly one closeout anchor %q in %s; found %s.\n' \
        "$anchor" "$candidate" "$matches" >&2
      return 1
    fi
  done
}

validate_closeout_anchors "$workflow" || exit 1

# Required negative controls. Each must be rejected; a control accepted by
# validate_closeout_anchors is a test failure. Fixtures stay in run scratch.
fixture_dir="${PAPERCLIP_RUN_SCRATCH_DIR:?}/wpr2-pr-disposition/closeout-anchor-controls"
mkdir -p "$fixture_dir"

# Missing anchor: remove the required bullet entirely.
perl -0pe 's/^- \*\*Review cadence:\*\*.*?^  explicitly enabled one\.\n//ms' \
  "$workflow" >"$fixture_dir/missing-review-cadence.md"

# Duplicated anchor: append a second required bullet inside the validated section.
perl -0pe 's/(^- \*\*Issue threshold:\*\*.*?^  the same root cause; never spray duplicate descendants\.\n)/$1- **Review cadence:** deliberate duplicate control.\n/ms' \
  "$workflow" >"$fixture_dir/duplicated-review-cadence.md"

# Renamed anchor: change the required literal so it is absent from the section.
perl -0pe 's/- \*\*Failure handling:\*\*/- **Failure response:**/' \
  "$workflow" >"$fixture_dir/renamed-failure-handling.md"

for control in \
  "$fixture_dir/missing-review-cadence.md" \
  "$fixture_dir/duplicated-review-cadence.md" \
  "$fixture_dir/renamed-failure-handling.md"; do
  if validate_closeout_anchors "$control"; then
    printf 'FAIL: negative closeout-anchor control was accepted: %s\n' "$control" >&2
    exit 1
  fi
done
printf 'PASS: missing, duplicated, and renamed closeout-anchor controls were rejected.\n'
exit 0
```

The scoped positive control must return one match for the heading and one match
for each named bullet. Then, in the same shell invocation, run the three
required negative controls above. They prove a missing, duplicated, or renamed
anchor fails immediately. Run
`git diff --check "$(git merge-base origin/main HEAD)" HEAD`, commit/push it,
and route its PR through `LocalFirstReviewer → GPTReviewer → ClaudeReviewer`
before any merge.
