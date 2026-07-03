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
  -workspace "Weird Parts.xcworkspace" \
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
  -workspace "Weird Parts.xcworkspace" \
  -scheme "WiredPart-iOS-Stage9-Smokes" \
  -destination 'platform=iOS Simulator,name=WEI-2499 QA iPhone SE 375 26.4.1' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3295Stage8ReportsViewportHarness' \
  test
```

For tablet evidence, use an installed iPad destination and keep the same targeted test. If the exact iPad name differs on the runner, record the destination in the evidence ledger.

```bash
xcodebuild \
  -workspace "Weird Parts.xcworkspace" \
  -scheme "WiredPart-iOS-Stage9-Smokes" \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  -only-testing:'Weird PartsUITests/Weird_Parts_IOSUITests/testWEI3295Stage8ReportsViewportHarness' \
  test
```

Optional but recommended for Stage 6 coverage:

```bash
xcodebuild \
  -workspace "Weird Parts.xcworkspace" \
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
| `xcodebuild -list -workspace "Weird Parts.xcworkspace"` | Pass | Workspace schemes are `GRDB-Package`, `WiredPart-iOS`, `WiredPart-iOS-Stage9-Smokes`, and `WiredPartCore` |
| `cd core && swift test` | Inconclusive | Built successfully and started suites, then the SwiftPM test helper stopped producing output and was terminated after a bounded wait |
| Focused `swift test --filter 'JobsServiceTests|OrdersServiceTests|ReportsServiceTests|Database Migration Tests'` | Inconclusive | Built immediately, then the same SwiftPM test helper no-output behavior recurred and was terminated |
| `xcodebuild -workspace "Weird Parts.xcworkspace" -scheme "WiredPart-iOS" -destination 'generic/platform=iOS Simulator' build` | Pass | Simulator app build succeeded; warnings were pre-existing deprecation/result-builder/concurrency warnings |
| `xcodebuild ... -only-testing:Weird_Parts_IOSUITests/.../testWEI3295Stage8ReportsViewportHarness test` | Blocked | `Weird_Parts_IOSUITests` is not a member of the active `WiredPart-iOS` scheme/test plan |
| WEI-3374 Xcode scheme repair | Pass | Added shared `WiredPart-iOS-Stage9-Smokes` scheme with `Stage9DeterministicUISmokes.xctestplan`; `xcodebuild -showTestPlans` reports `Stage9DeterministicUISmokes`, and `xcodebuild ... -scheme "WiredPart-iOS-Stage9-Smokes" ... build-for-testing` passed on the compact phone simulator |
| Direct phone install/launch smoke | Pass | Installed and launched built app on `WEI-2499 QA iPhone SE 375 26.4.1` (`145DE584-9492-43FE-8C19-A9573D24DC7F`) with `-UITesting -UITestingWEI936AutoLogin -UITestingStage8Reports -UITestingStage8PreBilling`; `simctl launch` returned pid `24213`, and `ps` showed the process still running |

Remaining before beta go:

- Run the Stage 8 and Stage 6 targeted UI smokes through the shared `WiredPart-iOS-Stage9-Smokes` scheme on phone and tablet, using the corrected `Weird PartsUITests/...` selectors when running from CLI.
- Run the tablet install/launch smoke from this package.
- Resolve or classify the SwiftPM test-helper no-output behavior so the core service gate can produce a terminal pass/fail result.

## WEI-3389 Final Beta Smoke Rerun — 2026-06-11

Candidate:

- Branch: `WEI-3091-stage-9-gate-field-test-smoke-package-and-beta-readiness-checklist`
- SHA: `9dc62939595a249fd166bfc2fd61b53377315023` (`Fix audit summary seeded smoke`)
- Contains fix branch: `origin/WEI-3388-fix-audit-summary-seeded-smoke` is an ancestor/equal to candidate HEAD.
- Worktree note: branch is ahead 4 / behind 3 vs `origin/main`; pre-existing tracked Stage 6 screenshot artifact changes were present before this rerun and tablet Stage 6 rerun updated tablet screenshots too.

Device matrix:

- Phone A: `WEI-2499 QA iPhone SE 375 26.4.1` / `145DE584-9492-43FE-8C19-A9573D24DC7F` / iOS 26.4.1.
- Phone B: `WEI-899 iPhone 13 mini 375pt` / `98CEE4F6-D8F5-49C3-A1B3-0F4CD6C11EA8` / iOS 26.4.1.
- Tablet: `WEI936-QA-iPad-9th` / `665A02E3-FF43-4A2E-ADAA-E084ED1BCAE9` / iOS 26.4.1.

Commands and results:

- `git diff --check`: PASS.
- `python3 scripts/guard-tracked-artifacts.py`: PASS (`No tracked Paperclip/Xcode runtime artifacts found.`).
- `cd core && swift test`: INCONCLUSIVE/NO-GO. Build completed and many suites started, but the run did not complete within the 600s bound and was terminated by the harness; log: `/tmp/wei-3389-stage9-smoke/swift-test.log`.
- `xcodebuild -workspace "Weird Parts.xcworkspace" -scheme "WiredPart-iOS" -destination 'generic/platform=iOS Simulator' build`: PASS (`** BUILD SUCCEEDED **`); log: `/tmp/wei-3389-stage9-smoke/xcodebuild-ios-build.log`.
- Phone Stage 6+8 full Stage9 scheme on iPhone SE: FAIL. Result bundle: `/tmp/wei-3389-stage9-smoke/phone-stage9-smokes.xcresult`. `testWEI3144JobMaterialsWalkthroughEvidence` crashed/killed before completing.
- Phone Stage 8 only on iPhone SE: FAIL. Result bundle: `/tmp/wei-3389-stage9-smoke/phone-stage8.xcresult`. Reports hub, Pre-Billing, Bookkeeper Export started, then `testWEI3295Stage8ReportsViewportHarness` crashed/killed during the Audit Summary discrepancy step.
- Phone Stage 8 only on iPhone 13 mini: FAIL. Result bundle: `/tmp/wei-3389-stage9-smoke/phone13mini-stage8.xcresult`. Failed at `Weird_Parts_IOSUITests.swift:277` because Pre-Billing did not render seeded row `WEI-3295 Stage 8 Billing QA Job`.
- Tablet Stage 8 only on iPad 9th: PASS. Result bundle: `/tmp/wei-3389-stage9-smoke/tablet-stage8.xcresult`; `testWEI3295Stage8ReportsViewportHarness` passed in 70.703s.
- Tablet Stage 6 only on iPad 9th: PASS. Result bundle: `/tmp/wei-3389-stage9-smoke/tablet-stage6.xcresult`; `testWEI3144JobMaterialsWalkthroughEvidence` passed in 46.137s.

Critical journeys:

- Stage 5 time: INCONCLUSIVE because the full SwiftPM core suite did not complete inside the bounded 600s run.
- Stage 6 parts-on-jobs: TABLET PASS, PHONE FAIL/crash-kill in the Stage9 scheme on iPhone SE before completion.
- Stage 7 PO/JPO: Not separately proven in this rerun beyond successful iOS build and core tests starting; no PASS claim.
- Stage 8 reports/pre-billing/bookkeeper/audit: TABLET PASS, PHONE FAIL on both compact phone attempts; iPhone SE reached Audit Summary then crashed/killed, iPhone 13 mini failed to render the seeded Pre-Billing job row.

Blocking issue scan:

- Data loss: no new data-loss issue observed from this rerun, but core service test completion is inconclusive.
- Privacy/security: no new privacy/security issue observed from this rerun.
- Install/launch: iOS candidate builds and tests install/launch on simulator, but compact phone deterministic smoke is not passing.

Go/no-go:

- NO-GO for beta. Required phone deterministic Stage 6/Stage 8 smoke evidence is failing, and the full SwiftPM suite did not produce a pass within the bounded run.
- First-class blockers from this evidence: `WEI-3400` (phone Stage 8/Pre-Billing), `WEI-3402` (phone Stage 6 materials), and `WEI-3401` (core SwiftPM gate). Duplicate aggregate `WEI-3403` was cancelled.

## WEI-3406 Final Smoke Gate — 2026-06-11

Candidate:

- Branch: `WEI-3091-stage-9-gate-field-test-smoke-package-and-beta-readiness-checklist`
- SHA: `39585ab3f1d429b5b0a0f74f6d7feaf15ebf1319` (`Fix core service test gate failures`)

Commands and results:

- `git diff --check`: PASS.
- `python3 scripts/guard-tracked-artifacts.py`: PASS.
- `cd core && swift test`: PASS, 2106 tests in 62 suites after 69.336s.
- `xcodebuild -workspace "Weird Parts.xcworkspace" -scheme "WiredPart-iOS" -destination 'generic/platform=iOS Simulator' build`: PASS.
- Phone Stage 9 deterministic smokes: PASS, 2 tests / 0 failures.
- Tablet Stage 9 deterministic smokes: PASS, 2 tests / 0 failures.

Go/no-go:

- GO for Stage 9 smoke gate review and parent handoff.
- Remaining merge-lane caveat at the time of PR #984 disposition: update the branch against current `main`, then send through LocalFirst review before broader review/merge.

## Go/No-Go Rule

Go only if every required command passes, both phone and tablet install/run smokes pass, and there are no known P0/P1 data-loss, privacy, security, install, launch, or migration blockers.

No-go if any required command fails, if a target route cannot be reached, if seeded financial/reporting data renders incorrectly, or if the issue scan finds an unresolved P0/P1 blocker. Link the failing issue, leave `WEI-3091` blocked by it, and assign the fix to the correct owner.
