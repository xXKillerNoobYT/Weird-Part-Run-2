# GitHub Issue Fisher Report

- Repository: `xXKillerNoobYT/Weird-Part-Run-2`
- Run timestamp (UTC): `2026-05-26T06:06:11Z`
- Mode: `dry-run`
- Plan source: `docs/plans` (82 markdown files)
- Priority order: `blocked -> todo -> backlog`
- Selected actions: `3`
- Evidence findings sampled: `80`

## Selected Issue-Moving Actions

### #717 — Parts CSV import silently converts invalid pricing values to zero
- Bucket: `todo`
- URL: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/717
- Evidence: Open GitHub issue classified as todo from labels: bug, data-integrity, priority:P1, triage
- Next action: Assign the smallest implementation owner or move into an active Paperclip child issue.

### #844 — [Sync][Security] LAN peer sync falls back to plaintext when key negotiation fails
- Bucket: `todo`
- URL: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/844
- Evidence: Open GitHub issue classified as todo from labels: bug, security, priority:P1, triage
- Next action: Assign the smallest implementation owner or move into an active Paperclip child issue.

### #750 — [Orders][Bug] Submitted PO state does not actually send or track supplier transmission
- Bucket: `todo`
- URL: https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/750
- Evidence: Open GitHub issue classified as todo from labels: bug, ui, priority:P1, triage
- Next action: Assign the smallest implementation owner or move into an active Paperclip child issue.


## Evidence Scan Sample

- `docs/plans/auto-go-unified-loop.md:118` — - **Out-of-reach tasks** (native device testing, App Store Connect, financial actions, destructive migrations) → `docs/DevTODO/` task file with instructions + optional AI prompt. User tags `done` when complete.
- `docs/plans/production-readiness.md:45` — - If any missing: file a DevTODO item with what's needed.
- `docs/plans/github-issue-fisher-workflow.md:15` — - Repo evidence: active `docs/DevTODO/`, plan markers, and Swift code markers sampled by the runner
- `docs/plans/ios-page-review-tracker.md:492` — | 31F | Warehouse audit: fix setup stub, finalize/adjust actions, certainty tie-in TODO, platform guards |
- `docs/plans/ios-page-review-tracker.md:539` — | 35A | Daily report submit stubs: wire TODO buttons + remove service bypass + raw SQL |
- `docs/plans/hunt-fix-verify-loop.md:76` — - `// TODO` / `// FIXME` / `// HACK` — unfinished work
- `docs/plans/hunt-fix-verify-loop.md:81` — - `Text("TODO")` / `Text("Placeholder")` — stub UI
- `docs/plans/hunt-fix-verify-loop.md:134` — 8. Code pattern issues (TODOs, dead buttons, etc.)
- `docs/plans/hunt-fix-verify-loop.md:166` — grep TODO/FIXME       → 0 untracked items
- `docs/plans/github-flow.md:17` — - **Handles security alerts** — Dependabot, CodeQL, secret scanning. Critical → urgent DevTODO. Low → noted and tracked.
- `docs/plans/github-flow.md:206` — - Existing `docs/DevTODO/` format — used for critical security DevTODOs
- `docs/plans/pre-release-audit-results.md:54` — | 1.17 | W2. No TODO stub buttons visible to users | PASS | Prompt 04 removed visible stubs; 33E wired all "Coming Soon" PO detail stubs |
- `docs/plans/pre-release-testing-checklist.md:272` — - [ ] W2. No TODO stub buttons visible to users
- `docs/plans/archive/orders-redesign-master-plan.md:869` — ## Remaining Project TODO (Full Roadmap)
- `docs/plans/archive/phase-4-jobs-labor.md:608` — - `InventoryGridPage.tsx` line 93: `handleSpotCheck` is empty (`// TODO: Navigate to audit page`)
- `docs/plans/security-review.md:40` — - Grep for disabled auth checks (`// TODO: auth`, `// skip auth`, commented-out `guard user.isAuthenticated`).
- `docs/plans/security-review.md:66` — - Critical findings (hardcoded secrets, SQL injection risk): also create a DevTODO for immediate user attention.
- `core/Sources/WiredPartCore/Services/SettingsService.swift:734` — let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) {
- `core/Sources/WiredPartCore/Services/SettingsService.swift:741` — let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) {
- `core/Sources/WiredPartCore/Services/SettingsService.swift:759` — let completedJSON = (try? JSONEncoder().encode(draft.completedSteps))

## Guardrails

- This run refuses to proceed when the plan directory is missing or empty.
- The workflow selects at most 3 actions per run.
- Reports are evidence; GitHub mutation still requires an explicit follow-up owner or approved routine path.
