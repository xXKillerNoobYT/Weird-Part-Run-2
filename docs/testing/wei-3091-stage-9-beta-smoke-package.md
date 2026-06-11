# WEI-3091 Stage 9 Beta Field-Test Smoke Package

Tracking:

- Paperclip: `WEI-3091`
- Upstream gates: `WEI-3090` Stage 8, `WEI-3353` Stage 8 merge reconciliation
- GitHub lane: PR #939 -> PR #940 -> PR #938 -> Stage 6 -> Stage 7 -> Stage 8 -> Stage 9
- Package owner: CTO
- Evidence owner: QA or release tester executing the smoke
- Status: ready for execution after the validation commands in this file pass on the current branch

This is the Stage 9 gate package for beta field-test readiness. It is intentionally scoped to smoke verification and go/no-go evidence, not feature expansion. Do not start parallel branch work from this package; if a blocker appears, record it against the failing workflow and open or link a focused follow-up issue.

## Entry Criteria

All of these must be true before starting the field-test smoke:

- `WEI-3090` Stage 8 reports/pre-billing/export gate is `done`.
- `WEI-3353` Stage 8 merge reconciliation is `done`.
- The tester is using the repo branch or PR intended for beta, with no unrelated local changes.
- Xcode can resolve the workspace schemes `WiredPart-iOS` and `WiredPartCore`.
- Xcode can resolve the shared deterministic smoke scheme `WiredPart-iOS-Stage9-Smokes`.
- The tester has one compact iPhone simulator and one iPad simulator available.
- No known P0/P1 data-loss, privacy, security, install, launch, or migration issue is open against the beta candidate.

## Smoke Commands

Run from the repo root unless noted otherwise.

```bash
git status --short --branch
git diff --check
python3 scripts/guard-tracked-artifacts.py

cd core
swift test
cd ..

xcodebuild \
  -workspace "Wierd Parts.xcworkspace" \
  -scheme "WiredPart-iOS" \
  -destination 'generic/platform=iOS Simulator' \
  build
```

The shared `WiredPart-iOS-Stage9-Smokes` scheme is the Xcode-runnable deterministic UI smoke lane. In Xcode, select that scheme, choose a concrete iPhone or iPad simulator, and run Test. The scheme uses `Weird Parts IOS/Stage9DeterministicUISmokes.xctestplan`, which selects only:

- `Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3295Stage8ReportsViewportHarness`
- `Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3144JobMaterialsWalkthroughEvidence`

Run the deterministic UI smoke on at least one compact phone and one tablet. The phone run proves install/launch and exercises the current Stage 8 reports/pre-billing/bookkeeper/audit surface using `-UITestingStage8Reports`.

```bash
xcodebuild \
  -workspace "Wierd Parts.xcworkspace" \
  -scheme "WiredPart-iOS-Stage9-Smokes" \
  -destination 'platform=iOS Simulator,name=WEI-2499 QA iPhone SE 375 26.4.1' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3295Stage8ReportsViewportHarness' \
  test
```

For tablet evidence, use an installed iPad destination and keep the same targeted test. If the exact iPad name differs on the runner, record the destination in the evidence ledger.

```bash
xcodebuild \
  -workspace "Wierd Parts.xcworkspace" \
  -scheme "WiredPart-iOS-Stage9-Smokes" \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3295Stage8ReportsViewportHarness' \
  test
```

Optional but recommended for Stage 6 coverage:

```bash
xcodebuild \
  -workspace "Wierd Parts.xcworkspace" \
  -scheme "WiredPart-iOS-Stage9-Smokes" \
  -destination 'platform=iOS Simulator,name=WEI-2499 QA iPhone SE 375 26.4.1' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3144JobMaterialsWalkthroughEvidence' \
  test
```

## Critical User Journeys

| Area | Route or fixture | Required evidence | Pass condition |
| --- | --- | --- | --- |
| Install and launch | `WiredPart-iOS` on iPhone and iPad simulator | Xcode test log or manual launch note with device name | App installs, launches, and reaches the target screen without crash |
| Stage 5 time | Core labor/time tests and manual clock path if available | `swift test` result or linked focused test evidence | Clock/labor data can be created and read without migration or service errors |
| Stage 6 parts-on-jobs | `testWEI3144JobMaterialsWalkthroughEvidence` / Job Detail -> Materials | XCUITest result or artifact note | Ready, Used, Returns, and History segments render seeded material data |
| Stage 7 PO/JPO | Orders routes: JPOs, Procurement, POs, Receiving | Manual or automated note | JPO/PO lifecycle pages open and render seeded or current data without crash |
| Stage 8 reports | `testWEI3295Stage8ReportsViewportHarness` | XCUITest result and artifacts under `docs/testing/artifacts/wei-3295/current` unless overridden | Reports hub, Pre-Billing, Bookkeeper Export, and Audit Summary render seeded data |
| Security/privacy | Release checklist section 7 plus tracked issue scan | Reviewer note | No P0/P1 blocker for secret leakage, PII logging, data exfiltration, or unauthorized data access |
| Data-loss | Migration/core test run plus beta issue scan | Reviewer note | No P0/P1 blocker for destructive migration, silent delete, sync corruption, or irreversible overwrite |

## Beta Readiness Checklist

| Gate | Owner | Status | Evidence |
| --- | --- | --- | --- |
| Stage 8 dependencies resolved | CTO | Pass | `WEI-3090` and `WEI-3353` are `done` before this package starts |
| Branch/worktree hygiene preflight recorded | CTO | Pass when recorded in WEI-3091 comment | Remote branch count, open PR count, worktree count, and prune result captured |
| Docs and artifact guard pass | CTO or QA | Pending execution | `git diff --check`; `python3 scripts/guard-tracked-artifacts.py` |
| Core service tests pass | QA | Pending execution | `cd core && swift test` |
| iOS candidate builds | QA | Pending execution | `xcodebuild ... -scheme "WiredPart-iOS" ... build` |
| Phone install/run smoke passes | QA | Pending execution | Targeted XCUITest on compact iPhone simulator |
| Tablet install/run smoke passes | QA | Pending execution | Targeted XCUITest on iPad simulator |
| Critical workflow notes complete | QA | Pending execution | Table above has pass/fail evidence for Stage 5-8 journeys |
| No known P0/P1 data-loss/privacy/security blockers | CTO + QA | Pending issue scan | Link any blocker; do not approve beta while present |

## Evidence Ledger

Copy this block into the WEI-3091 issue comment or PR handoff after execution.

```markdown
Stage 9 beta smoke evidence

- Candidate branch/SHA:
- Device matrix:
  - Phone:
  - Tablet:
- Commands:
  - `git diff --check`:
  - `python3 scripts/guard-tracked-artifacts.py`:
  - `cd core && swift test`:
  - `xcodebuild ... WiredPart-iOS ... build`:
  - Phone targeted UI smoke:
  - Tablet targeted UI smoke:
- Critical journeys:
  - Stage 5 time:
  - Stage 6 parts-on-jobs:
  - Stage 7 PO/JPO:
  - Stage 8 reports/pre-billing/bookkeeper/audit:
- Blocking issue scan:
  - Data loss:
  - Privacy/security:
  - Install/launch:
- Go/no-go:
- Next owner:
```

## WEI-3091 Heartbeat Validation - 2026-06-11

Branch/worktree hygiene preflight:

- Remote branch count: 167.
- Open PR count: 22.
- Registered worktrees: many active WPR2/Paperclip worktrees; no new branch or worktree was created for this package.
- Prunable worktrees: `git worktree prune -n -v` produced no output.

Commands run:

| Check | Result | Notes |
| --- | --- | --- |
| `git diff --check` | Pass | No whitespace errors in the Stage 9 docs diff |
| `python3 scripts/guard-tracked-artifacts.py` | Pass | `No tracked Paperclip/Xcode runtime artifacts found.` |
| `xcodebuild -list -workspace "Wierd Parts.xcworkspace"` | Pass | Workspace schemes are `GRDB-Package`, `WiredPart-iOS`, `WiredPart-iOS-Stage9-Smokes`, `WiredPart-macOS`, and `WiredPartCore` |
| `cd core && swift test` | Inconclusive | Built successfully and started suites, then the SwiftPM test helper stopped producing output and was terminated after a bounded wait |
| Focused `swift test --filter 'JobsServiceTests|OrdersServiceTests|ReportsServiceTests|Database Migration Tests'` | Inconclusive | Built immediately, then the same SwiftPM test helper no-output behavior recurred and was terminated |
| `xcodebuild -workspace "Wierd Parts.xcworkspace" -scheme "WiredPart-iOS" -destination 'generic/platform=iOS Simulator' build` | Pass | Simulator app build succeeded; warnings were pre-existing deprecation/result-builder/concurrency warnings |
| `xcodebuild ... -only-testing:Weird_Parts_IOSUITests/.../testWEI3295Stage8ReportsViewportHarness test` | Blocked | `Weird_Parts_IOSUITests` is not a member of the active `WiredPart-iOS` scheme/test plan |
| WEI-3374 Xcode scheme repair | Pass | Added shared `WiredPart-iOS-Stage9-Smokes` scheme with `Stage9DeterministicUISmokes.xctestplan`; `xcodebuild -showTestPlans` reports `Stage9DeterministicUISmokes`, and `xcodebuild ... -scheme "WiredPart-iOS-Stage9-Smokes" ... build-for-testing` passed on the compact phone simulator |
| Direct phone install/launch smoke | Pass | Installed and launched built app on `WEI-2499 QA iPhone SE 375 26.4.1` (`145DE584-9492-43FE-8C19-A9573D24DC7F`) with `-UITesting -UITestingWEI936AutoLogin -UITestingStage8Reports -UITestingStage8PreBilling`; `simctl launch` returned pid `24213`, and `ps` showed the process still running |

Remaining before beta go:

- Run the Stage 8 and Stage 6 targeted UI smokes through the shared `WiredPart-iOS-Stage9-Smokes` scheme on phone and tablet, using the corrected `Weird PartsUITests/...` selectors when running from CLI.
- Run the tablet install/launch smoke from this package.
- Resolve or classify the SwiftPM test-helper no-output behavior so the core service gate can produce a terminal pass/fail result.

## Go/No-Go Rule

Go only if every required command passes, both phone and tablet install/run smokes pass, and there are no known P0/P1 data-loss, privacy, security, install, launch, or migration blockers.

No-go if any required command fails, if a target route cannot be reached, if seeded financial/reporting data renders incorrectly, or if the issue scan finds an unresolved P0/P1 blocker. Link the failing issue, leave `WEI-3091` blocked by it, and assign the fix to the correct owner.
