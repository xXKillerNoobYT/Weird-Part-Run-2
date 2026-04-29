# Feedback: Copilot Delegation Workflow

**Updated:** 2026-04-29
**Status:** ACTIVE

---

## Summary

This document captures lessons learned from end-to-end Copilot Coding Agent (`copilot-swe-agent`) delegations on this repo, and tracks the delegation workflow conventions.

---

## Validated Workflow (as of 2026-04-26, issue #282)

1. Assign the issue to `@copilot` via the GitHub UI or GraphQL `replaceActorsForAssignable`.
2. Copilot picks up the assignment in ~30 seconds and opens a branch (`copilot/<slug>`).
3. Copilot posts an "Initial plan" commit message and begins work.
4. The issue comment only needs **acceptance criteria** — not a full context dump.

---

## Convention: No Inline Context Re-Statement Required

As of **2026-04-29**, project conventions are captured in `.github/copilot-instructions.md`. That file is read automatically by the Copilot Coding Agent as its system-prompt equivalent for every assigned issue.

**Before this file existed**, each delegated issue comment required ~70 lines of inline context:
- Build/test commands
- Schema location
- `userId` flow rules
- `isTableNotFoundError` pattern
- Soft-delete filter requirements
- Branch/PR conventions
- Tier tag format
- Agent boundary rules

**After `.github/copilot-instructions.md` was added**, delegation comments need only:
- 1–3 sentences describing the bug/feature
- Specific acceptance criteria (e.g. "the FK must be validated before save")
- Any area-specific nuance not covered by the global conventions

---

## Delegation Comment Template (post-conventions-file)

```markdown
## Context
<1–2 sentence description of the problem and where it lives>

## Acceptance Criteria
- [ ] <specific, testable criterion 1>
- [ ] <specific, testable criterion 2>
- [ ] `cd core && swift build && swift test` passes

## Notes
<any area-specific nuance — e.g. "this touches VehicleService which has a `status` column, apply the status IN filter too">
```

---

## Escalation Path

If Copilot cannot complete the issue autonomously (e.g. needs a schema migration, security review, or Xcode UI change), it should:

1. Post a comment explaining the blocker.
2. Add label `needs-human` or `copilot-blocked`.
3. Leave the PR in **Draft** state.

The human reviewer will unblock and reassign or take over.

---

## Related Files

- `.github/copilot-instructions.md` — conventions file (replaces inline re-statement)
- `CLAUDE.md` — full agent instructions (superset of copilot-instructions.md)
- `docs/plans/github-flow.md` — GITHUB FLOW routine design
- `docs/plans/auto-go-unified-loop.md` — AUTO GO + HUNT FIX loop design
