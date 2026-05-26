# Plan-First Branch and Approval Protocol

> **Status:** Active policy
> **Owner:** CTO / engineering coordination
> **Paperclip:** [WEI-2597](/WEI/issues/WEI-2597)
> **GitHub:** `xXKillerNoobYT/Weird-Part-Run-2`, branch `plan/WEI-2597-plan-first-protocol`
> **Obsidian:** `/Users/IA/Documents/Obsidian Vault/01_projects/Weird-Part-Run-2/Plans/Plan-First Branch and Approval Protocol.md`

## Purpose

Feature and update work starts with a repo-visible plan before implementation begins. Plan files in the repo must be updated or verified before new feature/update implementation starts. The plan gives Isaac, external owners, reviewers, and agents one durable place to check scope, acceptance criteria, approval state, and branch handoff.

This protocol applies to new features, meaningful updates, cross-cutting fixes, owner-requested product changes, and any work where a wrong assumption would create review churn. Small typo fixes, emergency production patches, and mechanical follow-ups may skip a dedicated plan only when the issue thread already contains exact scope and acceptance criteria.

## Required Sequence

1. Create or update the plan file under `docs/plans/` before implementation starts.
2. Link the plan in Paperclip, GitHub, and Obsidian/project tracking.
3. Get owner approval using the owner-specific policy below.
4. Start the implementation branch only after approval is recorded.
5. Keep status comments concise and command-prefixed so stale discussion can be cleaned up.

Agents must not treat a local-only note, chat summary, or unlinked comment as plan approval. The approval source must be visible from the repo plan or issue thread.

## Branch and File Naming

Plan branches use:

```text
plan/<issue-or-owner>-<slug>
```

Examples:

```text
plan/WEI-2597-plan-first-protocol
plan/sky-dispatch-schedule-review
plan/isaac-inventory-adjustments
```

Plan files use:

```text
docs/plans/<slug>.md
```

Implementation branches start only after approval and use normal implementation prefixes:

```text
feature/<issue-or-owner>-<slug>
fix/<issue-or-owner>-<slug>
```

Do not mix planning and implementation in the same branch for external-owner work. For Isaac-owned Weird Parts work, a combined branch is allowed only when Isaac/Paperclip approval already covers the plan and no separate plan branch was requested.

## Isaac / xXKillerNoobYT-Owned Repo Policy

For repositories owned by Isaac / `xXKillerNoobYT`, Paperclip approval by Isaac counts as plan approval unless he asks for a separate plan branch.

Acceptable approval evidence includes:

- A Paperclip assignment or approval that names the requested scope.
- An Isaac comment approving the plan, scope, or implementation direction.
- A Paperclip issue with exact acceptance criteria and no separate plan-branch request.

Even when separate branch approval is not required, the plan file must still be updated or verified before new feature/update implementation begins. The implementation issue or PR should link the plan file and state which Paperclip approval authorized the work.

## External-Owner Policy

This is the external-owner policy for work where the approving owner is not Isaac / `xXKillerNoobYT`.

For repositories, collaborations, or client areas owned by someone other than Isaac:

1. Create a dedicated `plan/<issue-or-owner>-<slug>` branch.
2. Add or update the plan under `docs/plans/<slug>.md`.
3. Open a PR or issue-thread review request against the plan branch.
4. Wait for owner/collaborator approval before creating `feature/` or `fix/` implementation work.

Approval must come from the external owner or their named collaborator. Paperclip-internal agreement is not enough for external-owner repos unless that owner has explicitly delegated approval authority.

## GitHub Comment Commands

Use these prefixes at the start of GitHub comments and PR comments so agents can parse state and clean up stale discussion.

| Prefix | Meaning |
| --- | --- |
| `PLAN_STATUS:` | Current plan state, branch, and next owner action. |
| `PLAN_QUESTION:` | A specific owner/collaborator question blocking approval. |
| `PLAN_CHANGE_REQUEST:` | Requested change before approval. |
| `PLAN_UPDATED:` | Plan branch/file was updated; include commit or PR link. |
| `PLAN_APPROVED:` | Owner approval is recorded; name approver and approved revision. |
| `IMPLEMENTATION_STARTED:` | Implementation branch has started from an approved plan. |
| `CLEANUP_DONE:` | Stale plan comments/branches were reconciled or intentionally retained. |

Keep command comments short. If the decision needs detail, link the plan section rather than repeating it in the thread.

## Open Sky Collaboration Note

For open Sky collaboration, use plan branch comments to clarify what is wrong or what needs updates before approval. Do not start implementation from ambiguous feedback. Convert unclear comments into `PLAN_QUESTION:` or `PLAN_CHANGE_REQUEST:` entries, update the plan branch, then wait for `PLAN_APPROVED:` from the owner/collaborator lane.

## Cross-System Linking

Every plan should include a short link block near the top:

```markdown
> **Paperclip:** [WEI-1234](/WEI/issues/WEI-1234)
> **GitHub:** PR/branch URL
> **Obsidian:** project note or daily log path
```

If one system does not have a link yet, write `pending` with the owner/action. Before implementation starts, all three systems should either link to the plan or explain why the link is not applicable.

## Minimum Acceptance Criteria for a Plan

A plan is ready for approval when it states:

- Scope and non-goals.
- Owner and approval lane.
- Branch/file names.
- Dependencies and blocked owner actions.
- Acceptance criteria.
- Required evidence and review lane.
- Pass-up trigger for implementation start.

Implementation can begin only after the approval lane records approval for a specific plan revision, branch, PR, or commit.
