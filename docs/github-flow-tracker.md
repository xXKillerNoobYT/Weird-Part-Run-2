# GITHUB FLOW Tracker

> **Auto-maintained** by `/github-flow` STEP 8.
> **This file is COMMITTED to git** — it's the permanent audit trail of every GitHub-side action the routine took (or considered and did not take).

## Why This File Exists

When an agent acts on a public surface (comments, PR reviews, Copilot triggers, issue closures), there needs to be a durable record of:
- What it did
- What it considered doing and chose not to, and why
- What user approvals gated each decision

This is that record. Future agents, future sessions, and the user can reconstruct every GitHub-side action.

## Format

One entry per actionable event:

```
### [TIMESTAMP] [sub-task SA/SB/SC/SD/SE] [event-URL or issue #]
- Actor: {user-login | bot-name | me}
- Classification: {pending-qa-answer | design-question | apply-change | copilot-mention | bot-alert | ambiguous | merge-conflict | stale | duplicate | security-critical | ...}
- Action taken: {replied | filed-qa | committed {SHA} | xcode-prompt {PE-N} | labeled {label} | closed | nudged | NOT-fired (reason) | ...}
- Reasoning: {one-line explanation, especially for NOT-fired decisions}
```

## Entries (newest first)

_(Empty — first entry on first iteration.)_

---

## Copilot Trigger Summary (rolling — last 30 days)

| Date | Triggers fired | Deferred to Q&A | Rate-limited |
|---|---|---|---|
| _(empty — grows over time)_ | | | |

## Per-PR / Per-Issue Activity (for high-traffic items)

_(Populated as specific PRs/issues see repeated activity.)_
