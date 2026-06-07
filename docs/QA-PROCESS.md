# QA Process And Evidence Guide

Tracking:

- GitHub: [xXKillerNoobYT/Weird-Part-Run-2#942](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/942)
- Paperclip parent: `WEI-3096`
- Paperclip active implementation: `WEI-3099`
- Paperclip QA review: `WEI-3100`

This document defines the minimum verification handoff for code, UI, docs, and automation changes. UIExpertVerifier should use this as the review surface for `WEI-3100`.

## Evidence Required By Change Type

| Change type | Minimum evidence |
| --- | --- |
| Docs only | `git diff --check`; links resolve relative to repo; no secrets/runtime artifacts added |
| Core domain logic | relevant `swift test` suite or focused `swift test --filter ...` from `core` |
| Database/migration | migration test or seeded open/migrate smoke plus rollback/data-impact note |
| SwiftUI screen | focused app build plus screenshot or UI test evidence for the affected route |
| Navigation/routing | app build plus route smoke on phone and tablet destinations |
| Sync/conflict behavior | unit/integration coverage for merge or queue rule plus manual multi-device note if applicable |
| Security/auth | focused tests, no secret logging, least-privilege and persistence notes |
| CI/workflow | workflow syntax/readback plus local runner routing note for Xcode/iOS jobs |

## Local Commands

Run the smallest command that proves the change. Do not default to full workspace validation for docs-only or isolated edits.

```bash
# Docs and Markdown hygiene
git diff --check
python3 scripts/guard-tracked-artifacts.py

# Core package
cd core
swift test
swift test --filter "SuiteOrTestName"

# App build; choose an installed simulator
xcodebuild \
  -project "Weird Parts IOS/Weird Parts.xcodeproj" \
  -scheme "Weird Parts" \
  -destination 'generic/platform=iOS Simulator' \
  build

# App unit tests
xcodebuild \
  -project "Weird Parts IOS/Weird Parts.xcodeproj" \
  -scheme "Weird Parts" \
  -destination 'generic/platform=iOS Simulator' \
  test
```

For route-specific simulator validation, replace the generic destination with an installed iPhone/iPad from `xcrun simctl list devices available`. Record the exact destination used.

## Documentation Maintenance Cadence

QA owns a docs spot-check whenever a change adds, removes, renames, or materially changes a user-facing route, service workflow, setup command, test command, runner label, permission/security behavior, sync behavior, or release-readiness gate.

Use this checklist before approving the change:

- Update `README.md` when the repo map, feature-area summary, common commands, or top-level status changes.
- Update `docs/WORKING-AREAS.md` when code moves between app feature folders, `WiredPartCore`, tests, scripts, or workflow ownership areas.
- Update `docs/SETUP.md` when Xcode project names, schemes, destinations, package commands, runner setup, or prerequisites change.
- Update this `docs/QA-PROCESS.md` when evidence expectations, smoke commands, device matrix, artifact rules, or PR validation routes change.
- Update feature-specific docs or file a GitHub follow-up when product behavior changes faster than the guide can be fixed in the current PR.
- In the PR handoff, state `Docs checked: yes/no` and list any follow-up GitHub issue for mismatches intentionally deferred.

Minimum cadence: run this checklist for every release-candidate PR, every field-test workflow PR, every GitHub/Paperclip automation PR, and any user-facing feature PR. For purely internal refactors, document why no guide update was required.

## UI Evidence Expectations

For user-facing app changes, the handoff should include:

- Route or screen name.
- Simulator/device and OS if known.
- Viewport/orientation: at minimum phone portrait for compact surfaces; add iPad/tablet when layout changes are responsive.
- Screenshot, XCUITest attachment, or precise manual observation.
- Accessibility notes when tap targets, text size, contrast, keyboard, or VoiceOver behavior is relevant.

Expected baseline viewports:

| Device class | Minimum evidence |
| --- | --- |
| iPhone compact | portrait smoke for navigation and clipping |
| iPad/tablet | portrait or landscape when grids, split views, sidebars, or sheets change |
| Dark mode | required for visual-system, color, card, modal, chart, or dashboard work |

## PR Testing On The Local Mac Runner

For `xXKillerNoobYT/Weird-Part-Run-2`, iOS/macOS/Xcode PR checks should not be treated as blocked solely because GitHub-hosted macOS capacity or billing is unavailable. The repo has a local self-hosted Mac runner intended for this path.

Known runner context:

- Runner directory: `/Users/IA/actions-runner/Weird-Part-Run-2`
- Service: `IA-Mac-WPR2`
- Intended labels: `self-hosted`, `macOS`, `ARM64`/`arm64`, `xcode`, `ios`, `local-mac`

Useful checks:

```bash
gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'

gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 10

grep -R "runs-on:" .github/workflows
```

When a workflow needs Xcode/iOS, evidence should state whether it was routed to the local runner labels or why the local runner could not be used. Related tracking: GitHub [#943](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/943), Paperclip `WEI-3097`.

## Handoff Template

```markdown
QA handoff

- Tracking: GitHub #NNN / Paperclip WEI-NNNN
- Scope: files or screens changed
- Verification: command(s), result, device/simulator if UI
- Evidence: screenshots, logs, or exact observations
- Not run: commands skipped and why
- Residual risk: known gaps
- Next owner: reviewer or follow-up issue
```

## WEI-3100 Review Notes

For the `WEI-3099` docs upgrade, UIExpertVerifier should verify:

- README links route to the support docs added or updated in this branch.
- `docs/SETUP.md`, `docs/WORKING-AREAS.md`, and this QA guide describe the native iOS/core Swift repo rather than stale web-only startup instructions.
- GitHub [#942](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/942), `WEI-3096`, `WEI-3099`, and `WEI-3100` are traceable in the docs.
- The docs do not include secrets, `.env` values, local tokens, database files, derived data, screenshots, or runtime artifacts.
