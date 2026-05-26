# Working with the xXKillerNoob Team — Plan-First Collaboration Protocol

> **For Paperclip/Hermes/Copilot agents:** Use this plan before starting new feature/update implementation work. This document defines when repo plans are automatically approved, when an external owner must approve a dedicated plan branch, and how to communicate plan updates cleanly.

**Goal:** Make feature planning, owner approval, and implementation handoff predictable for Isaac/xXKillerNoobYT-owned work and for collaborations with other owners.

**Architecture:** Treat repo plan files as the contract before implementation. Paperclip issues coordinate agent work; GitHub issues/PRs preserve owner-visible plan approval and implementation evidence; Obsidian is the cross-company handoff layer when frontend/backend Paperclip companies both need context.

**Tech Stack:** GitHub issues/branches/PRs, Paperclip goals/issues, repo docs under `docs/plans/`, Obsidian shared notes.

---

## 1. Non-negotiable rule: plans before feature work

Plan files in the repo must be updated or verified before new feature/update implementation starts.

Before starting any new feature, feature update, workflow change, or risky refactor:

1. Search for an existing plan in `docs/plans/`, `docs/paperclip-handoff.md`, `docs/dev-qa.md`, and related GitHub issues/PRs.
2. If the plan exists and is current, cite it in the Paperclip issue / GitHub issue / PR.
3. If the plan is stale, wrong, or incomplete, update the plan first.
4. If no plan exists for non-trivial work, create a plan first.
5. Do not start implementation until the approval path below is satisfied.

Small bug fixes can be implemented directly only when all are true:

- the behavior is clearly broken,
- the fix is narrow,
- the risk is low,
- the issue has acceptance criteria,
- and the fix does not change product/design direction.

If any of those are false, create or update the plan first.

## 2. Ownership / approval policy

### 2.1 Isaac / xXKillerNoobYT-owned repos

For repos owned by Isaac / `xXKillerNoobYT`, Paperclip approval from Isaac counts as plan approval unless Isaac explicitly asks for a separate plan branch or external review.

Meaning:

- If Isaac approves the work in Paperclip, agents may update the repo plan and proceed.
- The plan still must exist or be updated before implementation starts.
- The PR should cite the Paperclip issue and the plan file.
- If Isaac later says the plan is wrong, stop implementation, update the plan, and resume only after the updated plan is accepted.

### 2.2 External-owner policy / collaborator repos

For repos, features, or product decisions owned by someone else, agents must use a dedicated plan branch and get approval before implementation.

Examples:

- A collaborator owns the feature direction.
- A third-party repo owner must approve design direction.
- A teammate such as Sky needs to review/clarify the plan before work proceeds.
- The repo is not under Isaac / `xXKillerNoobYT` ownership.

Required flow:

1. Create a plan branch.
2. Update/add the plan file only.
3. Open a plan PR or post the plan branch in the GitHub issue.
4. Ask the owner/collaborator for approval or change requests.
5. If they request changes, update the plan branch and summarize the delta.
6. Start implementation only after explicit plan approval.

## 3. Branch naming

Use separate branch types for planning and implementation.

### Plan branches

Use:

```bash
git checkout -B plan/<issue-or-owner>-<short-slug> origin/main
```

Examples:

```bash
git checkout -B plan/886-agentic-goal-alignment origin/main
git checkout -B plan/sky-receiving-workflow-clarification origin/main
git checkout -B plan/external-owner-job-return-flow origin/main
```

Plan branches should usually touch only:

- `docs/plans/*.md`
- `docs/plan/<slug>` only when a legacy instruction uses that singular shorthand; in this repo, normalize new plan files to `docs/plans/<slug>.md`
- `docs/dev-qa.md` if questions need owner answers
- small index/linking docs when needed

Do not mix implementation code into a plan branch unless the owner explicitly requests a proof-of-concept.

### Implementation branches

After plan approval, create a separate implementation branch:

```bash
git checkout -B feat/<issue>-<short-slug> origin/main
# or
git checkout -B fix/<issue>-<short-slug> origin/main
```

Examples:

```bash
git checkout -B feat/886-agentic-goal-docs origin/main
git checkout -B fix/sky-receiving-workflow-gap origin/main
```

## 4. GitHub communication commands

Use GitHub issue/PR comments as the durable, parseable communication channel. Prefer clear prefixes so humans and agents can skim or grep the thread.

### Status update

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/plan-status.md
```

`/tmp/plan-status.md`:

```markdown
PLAN_STATUS

Current state: drafting plan branch `plan/<issue-or-owner>-<slug>`.

What changed:
- <bullet>

What needs approval:
- <bullet>

Next action:
- Waiting for owner review before implementation starts.
```

### Ask a plan question

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/plan-question.md
```

`/tmp/plan-question.md`:

```markdown
PLAN_QUESTION

Before implementation starts, please clarify:

1. <question>
2. <question>

Suggested default:
- <recommended answer>
```

### Record a requested change

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/plan-change-request.md
```

`/tmp/plan-change-request.md`:

```markdown
PLAN_CHANGE_REQUEST

Owner/collaborator requested changes before approval:

- <requested change>
- <requested change>

Plan branch to update:
- `plan/<issue-or-owner>-<slug>`
```

### Summarize an updated plan

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/plan-updated.md
```

`/tmp/plan-updated.md`:

```markdown
PLAN_UPDATED

Updated plan branch: `plan/<issue-or-owner>-<slug>`

Delta since last review:
- <change>
- <change>

Review request:
- Please approve with `PLAN_APPROVED` or reply with `PLAN_CHANGE_REQUEST`.
```

### Record plan approval

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/plan-approved.md
```

`/tmp/plan-approved.md`:

```markdown
PLAN_APPROVED

Approved by: <owner/collaborator>
Approved plan branch/PR: <link>
Implementation may start on a separate `feat/` or `fix/` branch.
```

### Mark implementation start

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/implementation-started.md
```

`/tmp/implementation-started.md`:

```markdown
IMPLEMENTATION_STARTED

Plan approved: <link>
Implementation branch: `<branch>`
Paperclip issue: <WEI-ID if applicable>

Verification expected:
- <test/build/check>
```

### Cleanup / communication closeout

```bash
gh issue comment <ISSUE_NUMBER> --body-file /tmp/cleanup-done.md
```

`/tmp/cleanup-done.md`:

```markdown
CLEANUP_DONE

Communication cleanup complete:
- Plan branch status: <merged/closed/still-open>
- Implementation branch status: <PR link or not started>
- Paperclip issue status: <WEI-ID/status>
- Remaining blockers: <none/list>
```

## 5. Sky / collaborator clarification pattern

When a collaborator such as Sky needs plan clarification before approval:

1. Open or update a dedicated plan branch, for example:

```bash
git checkout -B plan/sky-<short-topic>-clarification origin/main
```

2. Put the clarification directly in `docs/plans/<topic>.md` or a new `docs/plans/sky-<topic>-clarification.md` file.
3. Comment with `PLAN_QUESTION` or `PLAN_UPDATED` on the GitHub issue/PR.
4. Ask Sky to respond with one of:
   - `PLAN_APPROVED`
   - `PLAN_CHANGE_REQUEST`
   - `PLAN_QUESTION`
5. If Sky says the plan is wrong, update the plan branch before implementation.
6. Do not implement the feature until the plan is approved.

## 6. Paperclip integration

Paperclip agents should record:

- plan file path,
- GitHub issue/PR link,
- plan branch name,
- approval state,
- implementation branch name after approval,
- verification requirements,
- and closeout evidence.

For Isaac-owned repos, Paperclip approval by Isaac can be recorded as:

```text
Plan approval: Isaac/Paperclip approved; xXKillerNoobYT-owned repo policy applies.
```

For external-owner repos, record:

```text
Plan approval: waiting for external owner approval on plan branch <branch/PR link>.
```

## 7. Obsidian / cross-company handoff

Use Obsidian for cross-company memory and handoffs, especially when backend and front-end Paperclip companies both need visibility.

Rules:

- Do not assume frontend/backend Paperclip issues are shared state.
- Link related local Paperclip issues through Obsidian and/or GitHub issue links.
- Keep secrets, credentials, customer PII, and private operational details out of shared notes.

## 8. Definition of done for planning

A plan is ready for implementation when:

- the relevant `docs/plans/` file exists and is current,
- the owner approval policy above is satisfied,
- GitHub issue/PR comments show approval or Paperclip approval state,
- implementation branch name is known,
- acceptance criteria are clear,
- verification expectations are listed,
- and any open plan questions are answered or explicitly deferred.

## Related Paperclip goals/issues

- Goal: `Require repo plans and owner approval before feature implementation`
- Paperclip issue: `WEI-2597`
- Related process issue: `WEI-2560`
- Related GitHub issue: `#886`
