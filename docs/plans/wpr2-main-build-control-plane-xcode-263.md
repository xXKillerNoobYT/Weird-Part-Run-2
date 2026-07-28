# WPR2 `main` Build Control Plane — Xcode 26.3 Implementation Plan

> **Status:** Draft revision 2 — owner approval required before implementation children are created.
>
> **Owner:** CTO
>
> **Tracking:** Paperclip WEI-6390; active GitHub [#1480](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/1480)
>
> **Baseline inspected:** current `origin/main` `15b2157b315730b3dd858f55eb3e1040df38beba` on 2026-07-28; `2cbfd1deb` is retained below as the historical gap-diagnosis snapshot.

**Goal:** Make every post-merge `main` SHA independently buildable and testable under the owner-selected Xcode 26.3 contract, with separate fail-closed iPhone and iPad evidence before that SHA is eligible for beta testing.

**Architecture:** Preserve the strict PR gate as pre-merge evidence and add a separate trusted `push`-to-`main` workflow. A small, version-controlled toolchain descriptor and shell preflight select/verify Xcode 26.3, while a shared runner script receives an immutable expected SHA and device class. The post-merge workflow emits two distinct checks and a SHA-stamped eligibility record; no archive, export, App Store Connect, TestFlight, signing upload, or deployment step is permitted.

**Tech stack:** GitHub Actions, self-hosted macOS runners, Xcode 26.3, `xcodebuild`, `xcrun simctl`, `xcresulttool`, Bash 3.2-compatible scripts, `jq`, GitHub Actions artifacts/check runs, Paperclip and GitHub issue links.

---

## 1. Decision and hard invariants

1. `main` is WPR2's living base-zero beta line. PR checks are necessary pre-merge proof, not proof of the resulting merge commit.
2. A `main` SHA is **beta-ineligible by default**. It becomes eligible only when its exact SHA has successful, non-skipped iPhone and iPad post-merge checks plus a valid eligibility record.
3. The project-format contract is **Xcode 26.3**. The tracked project currently declares `LastUpgradeCheck = 2630`, `LastSwiftUpdateCheck = 2630`, and target `CreatedOnToolsVersion = 26.3` in `Weird Parts IOS/Weird Parts.xcodeproj/project.pbxproj`. Implementation must not rewrite those values while using a newer Xcode.
4. Xcode 26.6 is currently installed locally. A 26.6 runner is not an acceptable substitute for the eligibility lane: it must fail before testing with an actionable “Xcode 26.3 unavailable/mismatched” result. It may be used only for non-eligibility diagnostics explicitly labelled as such; it must never create a green main-beta record.
5. Ordinary PR validation remains strict and unchanged: required PR contexts remain `Analyze (swift)`, `iOS Beta Gate (iPhone)`, `iOS Beta Gate (iPad)`, and `Tracked artifact guard`. This plan adds post-merge proof; it does not weaken, rename, remove, or replace PR checks.
6. No workflow in this plan may invoke `archive`, `-exportArchive`, `altool`, `notarytool`, App Store Connect APIs, Fastlane upload lanes, or TestFlight upload.

## 2. Evidence-based gap diagnosis

### Historical gap diagnosis at `origin/main` `2cbfd1deb`

- `.github/workflows/ios-beta-gate.yml` triggers only for `pull_request` to `main` and passes `github.event.pull_request.head.sha` to the iPhone/iPad matrix. It cannot prove the merge result.
- Main's current check-run list contains maintenance/tracker/autofix checks only; it contains no `iOS Beta Gate (iPhone)` or `iOS Beta Gate (iPad)` record on `2cbfd1deb`.
- `main` branch protection is strict and requires the four PR contexts listed above. The two trusted local Mac runners are online with the intended labels.
- The existing gate already supplies useful deterministic behavior: a fixed iOS 26.5 runtime, iPhone 16 Pro / iPad Air 13-inch M2 device types, a run-owned simulator and DerivedData directory, exact-SHA assertion, nonzero-test/zero-failure/zero-skip result validation, seven-day artifacts, and no archive/upload.
- Current shared schemes are `WiredPart-iOS` (unit/regression scope) and `WiredPart-iOS-Stage9-Smokes` (the bounded `Stage9DeterministicUISmokes.xctestplan`). Both are defined in the tracked `Weird Parts.xcworkspace`; the workspace explicitly links the iOS project and local `core` package.

**Conclusion:** the historical gap is missing post-merge control-plane coverage, not evidence of an app build failure. The implementation baseline is the current SHA named above; adding a `push`-to-`main` workflow while leaving the PR gate intact is the smallest reversible correction.

## 3. Version-controlled configuration contract

### Files to add or modify

| Path | Responsibility |
|---|---|
| `.github/wpr2-main-build/toolchain.env` | Non-secret canonical toolchain, runtime, simulator, timeout, disk, artifact, and test-selection values. |
| `scripts/ci/verify-wpr2-xcode-toolchain.sh` | Bash 3.2-compatible selector/verifier. It sets `DEVELOPER_DIR` only to the declared Xcode 26.3 bundle and fails closed if the version/build does not match the allowlisted contract. |
| `.github/workflows/ios-main-beta-gate.yml` | Separate post-merge `push` workflow, exact `github.sha` checkout, two-device matrix, artifact publishing, and no release/upload permissions. |
| `scripts/ci/run-ios-beta-gate.sh` | Refactor only as needed so PR and main modes share the same deterministic test implementation and accept `EXPECTED_SHA`; preserve all current fail-closed checks. |
| `scripts/ci/write-main-beta-eligibility.py` | Pure local formatter/validator for a machine-readable SHA-stamped record; it must have fixture/self-tests and no network or credential access. |
| `scripts/ci/validate-ios-beta-gate-source.py` | Extend source-policy assertions so PR and main workflows retain their required trust, SHA, toolchain, and no-upload invariants. |
| `docs/runbooks/wpr2-main-beta-gate.md` | Operations/triage contract, log locations, thresholds, reviewer handoff, and stabilization cleanup procedure. |
| `docs/runbooks/local-mac-actions-runner.md` | Link to the new main-gate runbook and state the Xcode 26.3 provisioning requirement without duplicating machine-specific recovery commands. |

### Toolchain descriptor requirements

`.github/wpr2-main-build/toolchain.env` is the sole source of truth for the eligibility lane and contains only public/non-secret values, for example:

- `WPR2_XCODE_VERSION=26.3`
- `WPR2_XCODE_BUILD=<verified-26.3-build>`
- `WPR2_XCODE_DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer`
- `IOS_RUNTIME_VERSION=26.5`
- existing device type identifiers for iPhone 16 Pro and iPad Air 13-inch M2
- `MINIMUM_FREE_GIB=60`
- scheme/test-plan identifiers, phase timeouts, and artifact retention period.

The implementation must verify the exact Xcode 26.3 build during provisioning and commit it before enabling the workflow. It must not invent a build number in code or accept a prefix match. The script must call `xcodebuild -version` after exporting `DEVELOPER_DIR`, compare both version and build, and write the selected toolchain into metadata.

**Runner 26.6 policy:** existing 26.6 hosts retain their standard developer path for unrelated jobs. The main-beta workflow explicitly invokes the verifier before `simctl`, dependency resolution, build, or test. If the 26.3 bundle/runtime is absent, malformed, unselected, or mismatched, both matrix lanes fail and upload a redacted diagnostic (expected contract, discovered version/build, runner name, available free space). No automatic `xcode-select --switch`, symlink overwrite, download, or project-format migration is allowed in CI. Provisioning/replacement of the 26.3 bundle is a separately recorded runner-maintenance action and requires a canary before re-enabling eligibility.

## 4. Deterministic shared build/test contract

Both PR and post-merge modes must consume the same descriptor and runner logic. The main workflow must use:

- **Checkout and expected SHA:** for `push`, set `EXPECTED_SHA=github.sha`, use `actions/checkout@v4` at that immutable SHA with `persist-credentials: false`, then assert `git rev-parse HEAD == EXPECTED_SHA` before invoking Xcode. For recovery dispatch, use only the validated `inputs.commit_sha` contract in Section 5; do not use `github.sha` as the requested commit.
- **Workspace and schemes:** `Weird Parts.xcworkspace`; `WiredPart-iOS` for all unit/regression tests with `-skip-testing:"Weird PartsUITests"`; `WiredPart-iOS-Stage9-Smokes` for the bounded Stage 9 UI smoke test plan. The script runs `xcodebuild -list` under the selected Xcode 26.3 and fails if either chosen scheme is unavailable.
- **Destinations:** run-owned, unique iPhone 16 Pro and iPad Air 13-inch M2 simulators using the descriptor runtime. Boot with `simctl bootstatus -b`; no fallback to a smaller iPad or cached/shared simulator is allowed.
- **Dependency resolution:** resolve only from the tracked workspace and local `core` package. Use a run-scoped derived-data path under `$RUNNER_TEMP`; do not mutate shared DerivedData, the repo checkout, Xcode project metadata, or SwiftPM state outside the run-scoped directory.
- **Build/test:** `xcodebuild test`, Debug configuration, `CODE_SIGNING_ALLOWED=NO`, `-parallel-testing-enabled NO`, a distinct result bundle per phase/device, and the existing bounded timeouts/recovery rules.
- **Result validation:** every phase must provide a readable `.xcresult` summary with `result == Passed`, `totalTestCount > 0`, `failedTests == 0`, `skippedTests == 0`, and successful `xcodebuild`/`tee` statuses. A missing bundle, parse error, cancelled/timeout result, zero test, skip, runner failure, disk shortfall, wrong SHA, missing scheme/runtime/device, or toolchain mismatch is a failure.
- **Cleanup:** delete only the run-owned simulator and derived-data directory in `always()`/trap cleanup. Upload redacted metadata, logs, compact summaries, and compressed results for success and failure with the configured retention. No database, device data, signing material, tokens, or unchecked source artifacts may be uploaded.

## 5. Post-merge workflow and beta-eligibility record

### Workflow shape

`.github/workflows/ios-main-beta-gate.yml`:

- `on: push: branches: [main]` plus an explicit `workflow_dispatch` input named `commit_sha` for recovery. Dispatch must reject an empty/non-40-hex input, fetch `origin/main`, and reject a SHA that is not reachable from `origin/main`. It must check out that validated SHA with `persist-credentials: false`, set `EXPECTED_SHA` to the resolved checkout SHA, and bind every lane, metadata file, check annotation, and eligibility record to that SHA. `github.sha` is the expected SHA only in `push` mode; it must never stand in for `inputs.commit_sha` during dispatch.
- `permissions: contents: read` only; no `pull-requests`, `checks`, `statuses`, deployment, package, or repository-write permissions.
- concurrency group includes the immutable SHA, so two independent matrix lanes run for the same commit while a newer `main` commit does not cancel its predecessor's evidence.
- stable post-merge check names: `Main Beta Gate (iPhone)` and `Main Beta Gate (iPad)`. They are intentionally distinct from the required PR check names.
- each lane resolves the expected SHA by trigger mode, checks out and asserts that SHA, invokes `verify-wpr2-xcode-toolchain.sh`, then calls the shared runner for its device class.

### Eligibility record

After both lanes succeed, a small aggregation job creates `main-beta-eligibility.json` from the two validated per-lane metadata files. It must contain:

- `schemaVersion`, `repository`, `commitSha`, `ref`, `workflowRunId`, `workflowAttempt`, creation time, and selected Xcode version/build;
- the exact workspace, schemes/test-plan, runtime, device types, test totals, failure/skip counts, and artifact/job URLs for both lanes;
- `eligible: true` only if **both** lanes independently pass all assertions for the same `commitSha` and the toolchain exactly equals the descriptor;
- `eligible: false` plus an explicit machine-readable reason for missing/mismatched/incomplete metadata or a failed prerequisite.

The aggregation job must run with `if: always()`, write an ineligible record on every failure path where metadata can be collected, and itself fail if it cannot safely determine eligibility. The Actions check runs are the durable GitHub SHA association; the JSON artifact is supporting evidence, not a replacement for the two green checks. A beta decision for a SHA must cite both successful check URLs and the matching artifact. A missing/unreadable record is beta-ineligible.

## 6. Failure triage, observability, and control-plane response

The runbook must classify from logs/artifacts rather than rerun blindly:

| Class | Examples | Initial owner/action | Eligibility |
|---|---|---|---|
| Configuration/toolchain | no Xcode 26.3 bundle, version/build mismatch, missing scheme/runtime/device | BackendCoder repairs the descriptor/provisioning path; CTO retains gate control | false |
| Runner infrastructure | offline runner, <60 GiB free, simulator service outage, artifact transport failure | BackendCoder and the runner operator supply a bounded repair; one same-SHA retry only | false until a complete rerun succeeds |
| Deterministic test/build | compile failure, test failure, zero tests, unexpected skip, bad xcresult | implementation owner creates/updates one bounded code/test repair linked to GitHub #1480 | false |
| Control-plane integrity | wrong checkout SHA, malformed record, missing lane, workflow permission/upload violation | CTO owns a dedicated CI repair; do not downgrade the gate | false |

Required signals: queue delay, runner selection, Xcode version/build, free disk, expected/actual SHA, simulator IDs/runtime/device, phase status/counts, retry count, artifact URLs, and final eligibility reason. The runbook must set a 15-minute queue-to-start watch threshold, one transient infrastructure retry per SHA, and a high-priority root-cause issue after two infrastructure failures for the same SHA in 24 hours. It must update the existing linked issue where the root cause is shared rather than create duplicate manager churn.

## 7. Ownership, change control, and secrets boundary

- **CTO:** owns this plan, baseline contract, workflow governance, failure classification, and final disposition evidence. CTO does not approve its own implementation evidence.
- **BackendCoder:** owns implementation/configuration/provisioning work on a short-lived main-based branch and cannot modify `main` directly.
- **LocalFirstReviewer → GPTReviewer → ClaudeReviewer:** sequential non-author review of the exact implementation head; any material head change restarts the chain.
- **SecurityAgent:** independent review of self-hosted-runner trust boundary, `DEVELOPER_DIR` behavior, workflow permissions, artifact privacy, shell injection, and confirmation that no archive/upload or secret flow was added.
- **UIExpertVerifier:** independent exact-head verification that both device classes are the specified phone/tablet classes and execute nonzero, zero-skip tests. This is CI evidence, not a product UI sign-off.

Any change to descriptor values, workspace/scheme/test-plan selection, Xcode version/build, runtime/device matrix, result schema, retention, permissions, upload behavior, or required contexts requires a reviewed PR, exact-head PR evidence, a post-merge canary, and an updated runbook. A newer local Xcode must never update the project file incidentally; if a project-format upgrade is proposed, it is a separate owner-approved plan/PR with explicit rollback and compatibility evidence.

No source-controlled file may contain Apple credentials, signing certificates/profiles, App Store Connect identifiers/tokens, SSH keys, database contents, device backups, or absolute user-home paths. Workflow configuration is public/non-secret; operational secrets remain outside the repository and are not needed by this gate.

## 8. Temporary stabilization branches/tags

A stabilization branch/tag is exceptional, not a second beta line. It may be created only after explicit CTO + CEO approval when a `main` SHA cannot become eligible promptly and work must be isolated.

The approval comment and the branch/tag must name:

1. exact source SHA and the blocking defect;
2. designated owner and intended use (diagnosis or bounded repair only);
3. required main reconciliation/validation steps;
4. expiry/review time; and
5. removal condition: the repaired commit is merged to `main`, `Main Beta Gate (iPhone)` and `(iPad)` are successful for that merged SHA, the eligibility JSON is valid, and no unique unmerged work remains.

The owner must delete the temporary branch/tag immediately after satisfying the removal condition, then add the owning issue cleanup note: GitHub sync URL, final branch/tag state, whether the local worktree was removed/retained, and next owner if retained. A tag/branch may not be used to bypass a red/missing main gate, to upload TestFlight, or to make a build beta-eligible.

## 9. Approval-gated delegated task graph

Do **not** create these implementation issues until the CEO accepts this draft revision through the Paperclip confirmation on WEI-6390. Each child must carry `parentId=WEI-6390`, the current goal, exact `blockedByIssueIds`, and bidirectional GitHub #1480 linkage.

### A. Toolchain and post-merge gate implementation — BackendCoder

- **Repo/project:** `xXKillerNoobYT/Weird-Part-Run-2`; a new short-lived branch based on then-current `origin/main`.
- **Exact scope:** Implement all paths in Section 3; preserve PR workflow behavior and required contexts; add only the smallest tests/self-tests required for the descriptor/parser/refactor.
- **Acceptance criteria:** Xcode 26.3 is asserted before test work; 26.6 fails ineligible; `push` main workflow uses exact `github.sha`; recovery dispatch validates, checks out, and records only `inputs.commit_sha`; iPhone/iPad run the shared deterministic contract; no archive/upload/secrets; invalid result states remain red; eligible/ineligible JSON validates by fixture tests.
- **Required evidence:** branch/PR URL linked to GitHub #1480 and WEI-6390; source-policy/self-test output; a trusted exact-head PR canary; post-merge canary evidence only after merge; sanitized artifact URLs and worktree cleanup note.
- **Review lane:** LocalFirstReviewer → GPTReviewer → ClaudeReviewer; SecurityAgent in parallel after LocalFirst passes.
- **Pass-up trigger:** all reviewers accept one immutable head and the PR is eligible for serialized merge disposition.

### B. Independent code/control-plane review — LocalFirstReviewer, GPTReviewer, ClaudeReviewer, SecurityAgent

- **Repo/project:** the immutable PR head produced by A.
- **Exact scope:** Verify Xcode 26.3 enforcement, SHA correctness, workflow trust/permissions, matrix/device/scheme behavior, result/record failure modes, no-upload boundary, and project-format non-mutation.
- **Acceptance criteria:** reviewers issue explicit `Accept` or `Revise` for the current head. SecurityAgent confirms no credentials/write permissions/archive/upload path. A new head invalidates all prior accepts.
- **Required evidence:** exact head/base SHA, diff, test outputs, current-head check URLs, unresolved-thread check, and a precise action for every `Revise` finding.
- **Review lane:** sequential LocalFirstReviewer → GPTReviewer → ClaudeReviewer; SecurityAgent reviews the same immutable head after LocalFirst acceptance.
- **Pass-up trigger:** all four lanes accept, with no unresolved review thread.

### C. Exact merged-main verification — UIExpertVerifier

- **Repo/project:** resulting `origin/main` SHA after A's PR is squash-merged through the serialized queue.
- **Exact scope:** Read the `Main Beta Gate (iPhone)` and `(iPad)` check runs, metadata/artifacts, and eligibility JSON; confirm the specified iPhone/iPad classes, Xcode 26.3 build, exact SHA, nonzero tests, zero skips/failures, and no archive/upload action.
- **Acceptance criteria:** `Pass` only if both post-merge lanes and the JSON agree on one exact main SHA. It must report `Fail`/`Blocked` with the actual failing invariant otherwise.
- **Required evidence:** both check URLs, commit SHA, selected Xcode build, device/runtime, result counts, record URL, and a redacted log/metadata reference.
- **Review lane:** independent non-author verification reporting to CTO.
- **Pass-up trigger:** verified pass causes CTO to mark WEI-6390 done and mark that exact SHA beta-eligible; any failure creates/updates the bounded repair/blocker.

### Dependency map

`CEO plan confirmation → A implementation → LocalFirst → GPT → Claude + Security → serialized merge → C exact-main verification → WEI-6390 done`

Only A is initially executable. Later children are first-class blocked dependencies, not status comments or repeated liveness cards.

## 10. Implementation validation checklist

- [ ] Current PR branch protection remains strict and contains all four existing required PR contexts.
- [ ] Project format remains at 2630/CreatedOnToolsVersion 26.3 after implementation and canary.
- [ ] A runner with only Xcode 26.6 produces a red/ineligible preflight before simulator/build execution.
- [ ] A provisioned Xcode 26.3 runner records the exact version/build and can list the workspace schemes.
- [ ] `push` to `main` checks out/asserts `github.sha`, not a PR SHA or moving branch ref; recovery dispatch validates a reachable `inputs.commit_sha`, checks out that exact SHA, and never substitutes `github.sha`.
- [ ] Main iPhone and iPad checks are distinct, exact-SHA checks and both use run-owned simulators/DerivedData.
- [ ] Each lane records nonzero tests with zero failures/skips and a readable xcresult.
- [ ] A missing lane, bad metadata, wrong SHA, toolchain mismatch, skip, timeout, or failed upload/record is ineligible.
- [ ] Eligibility JSON contains the exact SHA and both matching lane records; artifact/check URLs are readable.
- [ ] No project-format upgrade, archive, export, TestFlight/App Store Connect action, secret, or device data is committed or run.
- [ ] Review chain and post-merge independent verification are completed on immutable heads/SHAs.
- [ ] Any temporary stabilization branch/tag has a documented expiry and final cleanup evidence.

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Xcode 26.3 is not currently installed while 26.6 is | Explicit fail-closed preflight, dedicated provisioning/canary, and no 26.6 eligibility fallback. |
| Two device matrices consume local runner capacity | Keep per-SHA evidence non-cancelled, use current two-runner capacity, record queue delay, and repair capacity rather than skipping lanes. |
| Simulator/XCTest flake masks a real failure | Preserve bounded retries only for already-known fingerprints, retain first-attempt evidence, and reject missing bundles/statuses. |
| Artifact retention creates storage pressure | Upload compact redacted metadata/summaries by default, bound retention, and treat failed artifact transport/record generation as ineligible. |
| Post-merge workflow code changes its own behavior | Exact `github.sha` checkout and SHA-stamped record ensure the workflow source and tested source are the merge commit. |
| A new project format accidentally arrives with an Xcode upgrade | Immutable descriptor validation plus project metadata assertions and separate approval required for format changes. |

## 12. Rollback and incident posture

Do not remove or weaken PR requirements when this gate is red. Freeze beta eligibility for affected `main` SHAs, classify the failure, and ship the smallest reviewed repair through the normal PR path. If the post-merge workflow itself is malformed, fix it through a reviewed PR and retest the new merged SHA; previous PR green checks remain insufficient. A temporary stabilization branch/tag requires the explicit procedure in Section 8 and cannot substitute for recovery on `main`.
