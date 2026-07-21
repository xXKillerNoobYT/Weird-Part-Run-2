# Trusted First-Party Automation Policy

## Purpose

Trusted automation keeps Isaac-authored work moving without manual Actions approvals. It does **not** treat every GitHub event, contributor, or marketplace Action as trusted.

## Trusted PR eligibility

A PR is eligible for autonomous maintenance only when all conditions are true:

1. It targets `main` and its head repository is this repository (no fork).
2. The PR author is listed in `TRUSTED_PR_AUTHORS` (initially `xXKillerNoobYT`).
3. The head repository owner is this repository's owner.
4. It is not a draft, has no skip/security/manual labels, and its title does not match the sensitive-change pattern.
5. Its exact head has no pending or failed required checks.
6. Any branch-protection requirements are met.

A branch name, a bot review, or a same-repository checkout alone does not prove trust.

## Automation boundaries

| Change origin/type | Automation behavior |
| --- | --- |
| Trusted first-party, non-sensitive PR | May rebase, run bounded Codex repair, and queue merge after all gates pass. |
| External fork or unlisted PR author | Never checked out by a privileged automation workflow; never repaired or merged automatically. |
| Security, authentication, credentials, encryption, payments, deployment, or policy change | May receive normal read-only checks; excluded from autonomous repair and merge. |
| Untrusted review/check event | Does not trigger privileged work. Scheduled selection evaluates only eligible PRs. |

## Workflow trigger policy

Privileged maintenance workflows are scheduled from trusted default-branch workflow code and can be manually dispatched in dry-run mode. They do not use `pull_request_target`, and they do not use review/check webhook events as privileged execution triggers.

This avoids GitHub's `action_required` zero-job queue for bot/external review events while retaining the external-contributor approval boundary.

## GitHub Actions settings

- Keep external contributor approval as `all_external_contributors`.
- Allow GitHub-owned and verified Actions plus the repository owner's explicitly listed action namespace.
- Keep repository default workflow permissions at `read`; request write permissions only in the individual workflow that needs them.
- Pin third-party action references before enabling repository-wide SHA pinning.
- Self-hosted macOS runners execute only trusted repository automation or same-repository PR work after this policy's eligibility check.

## Release boundary

Autonomy never substitutes for release evidence. `main` is TestFlight eligible only after current exact-head iPhone+iPad results are 100% passing with zero unexpected skips and readable result bundles.
