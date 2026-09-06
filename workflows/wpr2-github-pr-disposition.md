# WPR2 GitHub PR Disposition and Serialized Merge Workflow

## Purpose and owner

**Owner:** CTO for each queue pass. **Control-plane owner:** CEO, who keeps one active CTO-owned disposition issue, restores liveness when the queue changes, and ensures every non-ready PR has a bounded owner/action.

This is the mandatory operating procedure for every open pull request in `xXKillerNoobYT/Weird-Part-Run-2`. It governs classification and routing only. It does not authorize bypassing a gate, merging a PR, changing branch protection, or deleting useful work.

## Trigger and inputs

Run a CTO disposition pass when any of the following occurs:

- the scheduled CEO orchestration pass finds an open WPR2 PR;
- GitHub emits a check, review, comment, draft/ready, base-update, or mergeability event;
- a Paperclip repair, review, device, security, or merge blocker becomes done/cancelled;
- a changed PR head, failed/retried CI job, or new external evidence invalidates prior evidence; or
- CEO wakes/requeues the single active CTO disposition issue.

Inputs required before a disposition:

1. Current GitHub PR list, individual PR state, exact head SHA, base SHA, draft state, mergeability, required checks, review state, unresolved review threads/comments, and linked GitHub issues.
2. Current WPR2 `main` SHA and runner state, including the local self-hosted Mac/Xcode path where iOS/device evidence is required.
3. Current Paperclip issue, parent/child graph, `blockedByIssueIds`, merge issue chain, owners, statuses, recent comments, and links to the PR/GitHub issue.
4. The prior disposition record, if one exists. Prior evidence is invalid once the exact head or relevant base/check/review state changes.

## Evidence collection and readback

1. Snapshot GitHub directly; GitHub's current PR head is authoritative. Record URLs and exact SHA(s), rather than relying on branch names or old comments.
2. Verify all required checks on the exact head after the current base/rebase state. For iOS-impacting work, collect the applicable local Mac runner and distinct required device evidence; do not substitute a generic green check for a named device gate.
3. Read current review state and every unresolved non-outdated review thread. Request/record the required GitHub Copilot review/comment; its availability exception requires explicit owner-approved evidence.
4. Read Paperclip after every mutation. Verify the owner, child/parent relationship, status, `blockedByIssueIds`, merge-chain position, and GitHub↔Paperclip traceability links.
5. Post a concise disposition comment containing the PR URL, head/base SHA, evidence URLs, disposition, remaining exact condition, owner, Paperclip IDs, and next action.

## Allowed dispositions

Every open PR must have exactly one current disposition:

### 1. Merge now

Use only when every merge predicate below is simultaneously true. Create or update its Paperclip merge issue, assign it to CTO, and put it into the serialized queue. This means *eligible for the route*, not permission to skip its one-at-a-time position.

### 2. Repair

Use when an agent-controlled defect exists: stale base/current-head mismatch, failing or missing required check, unresolved review thread, missing traceability, missing required review, fixable merge conflict, or incomplete required evidence.

Create the smallest bounded repair/review child issue with a named owner, exact current head, acceptance evidence, review lane, pass-up trigger, and a direct blocker edge from the merge issue (or the controlling disposition issue where no merge issue exists). A new head restarts all head-sensitive checks and reviews.

### 3. Await external evidence

Use only for a named condition outside the assigned agent's control, such as an owner product decision, physical-device availability/evidence, unavailable authorized reviewer, external service outage, or explicit security/release approval.

Set the controlling issue to `blocked`; create or retain a first-class blocker issue with the external owner, exact condition, expected evidence, and next recheck trigger. “Waiting,” “old,” or “needs review” without those fields is invalid.

### 4. Close as superseded

Use only with evidence that the PR is duplicate, obsolete, or replaced by a merged/current successor that preserves the intended work. Record the successor PR/commit and GitHub/Paperclip linkage, obtain the required owner approval where scope or user-visible behavior is discarded, then close the obsolete PR and its redundant Paperclip work. Never close useful work solely because it is old, inconvenient, or blocked by a real gate.

## Merge-now predicate and serialized squash-merge route

A PR may be dispositioned **merge now** only when all of these are true on its exact current head:

- its linked Paperclip implementation, repair, QA, security, and review issues are `done` or `cancelled`;
- the branch is current with `main` following any prior queue merge, and mergeability is clean;
- every required GitHub check is green after that update;
- all required non-author review is complete, no unresolved non-outdated review thread remains, and the GitHub Copilot review/comment gate is satisfied or has documented owner-approved unavailability evidence;
- applicable device gates (including distinct iPhone/iPad evidence where required), security/privacy gates, release constraints, and current-head evidence are satisfied;
- GitHub issues, PR body, and Paperclip issues are bidirectionally traceable, including `Closes`/`Refs` and Paperclip IDs where applicable; and
- no owner, security, product, or external-blocker condition remains.

Order candidates by Paperclip/GitHub priority (`critical`, `high`, `medium`, `low`, then explicitly ordered unset priority) and oldest-ready first within the same priority. Exactly one eligible merge issue is unblocked/active. Every later eligible candidate is `blocked` by the immediately preceding merge issue through `blockedByIssueIds`.

For the active candidate only:

1. Re-read GitHub and Paperclip immediately before acting; confirm it remains first and unblocked.
2. Rebase/update against current `main` when required, then re-run all head-sensitive checks, reviews, and evidence collection.
3. Squash merge only after the predicate is still satisfied; delete the merged branch only after merge succeeds and retention/worktree policy permits it.
4. Re-read GitHub PR, linked GitHub issue(s), Paperclip merge issue, and the next queued merge issue. Record merge evidence and promote exactly one next candidate. The next candidate must rebase/update and revalidate against the new `main`.

Never weaken required checks, review, device, security, traceability, current-head, or branch-protection gates to make the queue move.

## Child and blocker requirements

- A repair/review task is a child of the controlling PR/disposition work and names the current head, concrete acceptance criteria, evidence, owner, and pass-up trigger.
- A dependent task is `blocked` with a real `blockedByIssueIds` edge to its immediate prerequisite. Text-only dependency notes are insufficient.
- A merge issue is blocked by every producing implementation/review/QA/security issue until they are terminal, and later merge issues are also blocked by the immediately prior merge issue.
- After each create/update, re-read the issue and prove that `parentId`, owner, status, and blocker edge are correct.

## Failure handling and escalation

- **GitHub/API/runner evidence unavailable:** record the command/URL, failure class, timestamp, and named restoration owner; classify as `await external evidence` only if the unavailable input is genuinely external.
- **Check/review/device/security failure:** classify as `repair`; create the smallest correct child and block merge on it. Do not reroute around the failure.
- **Paperclip write/readback mismatch:** stop queue advancement, capture the rejected request/response without secrets, and route a CTO/control-plane repair. Do not assume the mutation applied.
- **Ambiguous supersession, product scope, risk acceptance, credentials/billing, or irreversible deletion:** escalate to CEO/board. Keep the PR/work item open with its exact decision required.
- **Conflicting queue claims or duplicate work:** CEO keeps one controlling CTO disposition issue, preserves the valid active route, and cancels/reassigns only clearly redundant runs after Paperclip readback.

## Logs, cadence, and review

- Each pass records its evidence in the controlling Paperclip issue comment and links the GitHub PR/check/review URLs. Local test/runner log paths are cited when used; do not paste secrets.
- CEO performs the company priority loop on every heartbeat and wakes/requeues CTO on GitHub or Paperclip queue-progress signals. CTO performs a full disposition snapshot on each wake and after every promoted/changed candidate.
- Review this workflow after any gate escape, duplicate merge-route activation, stale-head decision, unsupported disposition, or recurring evidence collection failure. CEO owns governance amendments; CTO reviews technical workflow quality.
- Verification of this workflow is a CTO readback from the execution workspace at `workflows/wpr2-github-pr-disposition.md`, followed by resumption of the governed queue pass. The first queue pass under this artifact must not merge merely to prove the workflow exists.
