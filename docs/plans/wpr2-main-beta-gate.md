# WPR2 `main` Beta Gate Implementation and Rollback Plan

> **Status:** Draft revision 1 — awaiting CEO confirmation
>
> **Owner:** CTO
>
> **Tracking:** Paperclip WEI-5356, parent WEI-5318; GitHub [#1480](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/1480)
>
> **Decision date:** 2026-07-20

**Goal:** Make every same-repository pull request to `main` prove, at its exact current head, that the native iOS app builds and its app unit/regression tests pass on an iPhone and a regular-width iPad before GitHub or Paperclip can route it as merge-ready.

**Architecture:** Add a dedicated GitHub Actions workflow with two stable fail-closed check contexts on WPR2's self-hosted Mac runners. Each job explicitly checks out `github.event.pull_request.head.sha`, creates an isolated simulator from the newest available iOS runtime, runs the app test target, validates the resulting `.xcresult`, and publishes exact-head/device/test counts to the Actions job summary. After a canary run and independent review, add the two device contexts plus Artifact Guard to strict `main` branch protection and update the serialized PR-disposition workflow to reject stale or missing evidence.

**Tech stack:** GitHub Actions, `actions/checkout@v4`, Xcode 26.6+, `xcodebuild`, `xcrun simctl`, `xcresulttool`, Bash, GitHub branch-protection REST API, Paperclip blocker links.

---

## 1. Scope and non-goals

### In scope

- Same-repository `pull_request` events targeting `main`.
- Exact-current-head app compilation and app unit/regression tests for:
  - iPhone compact device class.
  - iPad regular-width device class.
- Stable GitHub check names, strict branch-protection requirements, runner routing, durable log/evidence conventions, failure thresholds, rollback, and Paperclip merge-readiness integration.
- Documentation updates for the new required CI path.

### Explicitly out of scope

- Xcode Cloud changes.
- `release` branch changes, tags, archives, App Store Connect uploads/submissions, tester invitations, or publishing.
- Treating a locally exported `.ipa` as TestFlight upload success.
- Collecting or entering Apple credentials.
- Running a TestFlight archive/upload for each PR.
- Replacing feature-specific physical-device, accessibility, security, migration, or beta acceptance evidence when the changed behavior requires it.

The automated jobs use isolated iOS simulators. “Real build/test” means a real `xcodebuild test` of the native app at the PR head, not an echo/status substitute. Physical iPhone/iPad evidence remains a separate scope-relevant acceptance lane because installing arbitrary PR code on owner devices has signing, data-preservation, availability, and trust implications.

## 2. Live baseline captured 2026-07-20

### GitHub and runner state

- `main` branch protection has `strict: true`, requires conversation resolution, and currently requires only `Analyze (swift)`.
- `.github/workflows/codeql.yml` implements the PR version of `Analyze (swift)` as an explicit echo-only recovery/compatibility job. It does not build or test the app and must not be described as device or security evidence.
- `.github/workflows/artifact-guard.yml` runs `Tracked artifact guard` on PRs but the context is not currently required.
- No committed workflow runs `xcodebuild test` as a PR gate (the `Approved PR Autofix` workflow calls `xcodebuild -version` but is not a test gate).
- Two repository runners are online and idle: `IA-Mac-WPR2` and `IA-Mac-WPR2-2`.
- Verified labels on both runners: `self-hosted`, `macOS`, `ARM64`, `xcode`, `ios`, `local-mac`.
- Xcode is 26.6 (build 17F113); iOS 26.5 is available.
- The project is `Weird Parts IOS/Weird Parts.xcodeproj`, scheme `Weird Parts`.
- App test target: `Weird Parts IOSTests`; UI test target: `Weird PartsUITests`.
- Project device family is `1,2`, covering iPhone and iPad.
- Available simulator types include `iPhone 17 Pro` and `iPad Pro 13-inch`; a 13-inch iPad is regular width.

### Queue/worktree hygiene

- Remote branches: 30.
- Open PRs: 13.
- Registered worktrees: 64.
- `git worktree prune -n -v` found no prunable metadata.

No additional worktree or branch will be created for implementation. The already-claimed `hermes/hermes-335da4b2` worktree/branch is the sole implementation lane. Its owning Paperclip issue must receive a final cleanup note with GitHub sync, PR/branch state, and whether the worktree is removed or intentionally retained.

## 3. Exact gate contract

### Workflow and stable check names

Create `.github/workflows/ios-beta-gate.yml` with workflow name `iOS Beta Gate` and these exact job/check names:

1. `iOS Beta Gate (iPhone)`
2. `iOS Beta Gate (iPad regular-width)`

Both checks run for every same-repository PR targeting `main`. Fork PRs do not run on trusted self-hosted runners; they remain ineligible for merge until an owner brings the change into a same-repository branch and obtains the same exact-head checks.

Runner selector for both jobs:

`[self-hosted, macOS, ARM64, xcode, ios, local-mac]`

Workflow permissions default to `contents: read`. No secrets, write permissions, archive, signing export, upload, or deployment permission is needed.

### Current-head semantics

Each job must:

1. Capture `EXPECTED_SHA=${{ github.event.pull_request.head.sha }}`.
2. Use `actions/checkout@v4` with `ref: ${{ github.event.pull_request.head.sha }}` and persisted credentials disabled.
3. Fail before Xcode starts unless `git rev-parse HEAD` equals `EXPECTED_SHA` exactly.
4. Print the expected SHA, actual SHA, PR number, Actions run URL, runner name, Xcode version, runtime identifier, simulator device type, and simulator UDID to the job summary.
5. Produce its status on that same SHA. A new PR commit creates a new required-check set; prior green runs do not satisfy the new head.

Branch protection remains `strict: true`, so GitHub also requires the PR to be current with `main` before merge.

### Device isolation and destination selection

Each job creates a disposable simulator under a unique name derived from `GITHUB_RUN_ID`, `GITHUB_RUN_ATTEMPT`, and device class, using the newest available iOS runtime reported by `simctl`.

- iPhone device type: `com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro`.
- iPad device type: use `com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch` (generic 13-inch iPad Pro; discover the exact available identifier at runtime via `simctl list devicetypes`); fall back to another installed 13-inch iPad Pro/Air type only when no 13-inch Pro type is found.
- iPad validation must record the selected 13-inch type and destination in the job summary; a compact iPad Mini is not an acceptable regular-width substitute.
- Each job boots and waits for its simulator, runs tests by UDID, and deletes only the simulator it created in an `always()` cleanup step.
- DerivedData, result bundles, and transient logs live below `$RUNNER_TEMP/wpr2-beta-gate/$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT/<device>/`, never in the repository.

### Build/test command contract

Each device job runs one fail-closed `xcodebuild test` invocation against:

- Project: `Weird Parts IOS/Weird Parts.xcodeproj`.
- Scheme: `Weird Parts`.
- Configuration: `Debug`.
- Destination: the disposable simulator UDID.
- Test scope: `-only-testing:"Weird Parts IOSTests"`.
- Result bundle: the device-specific path under `$RUNNER_TEMP`.
- Parallel testing: disabled for deterministic device accounting.

`xcodebuild test` is intentionally used instead of `build-for-testing` plus `test-without-building`; each required device context independently proves both compilation and execution for its destination. UI tests are not included in this universal gate because several are route/fixture/opt-in specific. Relevant UI, accessibility, physical-device, and beta acceptance remains linked evidence in the PR-disposition lane.

### Fail-closed result validation

The job uses `set -euo pipefail`; it has no `continue-on-error`, fallback echo, or success-on-timeout path. After `xcodebuild`, it runs:

`xcrun xcresulttool get test-results summary --path <result-bundle> --compact`

The parser must require all of the following:

- `.result == "Passed"`.
- `.totalTestCount > 0`.
- `.failedTests == 0`.
- `.skippedTests == 0`.
- `.passedTests == .totalTestCount`.
- The reported device name/identifier matches the simulator created by that job.

Any missing result bundle, malformed summary, zero-test run, unexpected skip, expected failure, device mismatch, build failure, test failure, simulator failure, runner cancellation, or 45-minute job timeout leaves the context non-successful and blocks merge.

Existing tests that use `XCTSkip` when an expected source symbol is missing will therefore fail the beta gate as an unexpected skip. That is intentional: missing-source regression coverage cannot be silently green.

## 4. Logs, evidence, and retention

### Canonical evidence

- Primary durable log: the GitHub Actions run/job URL.
- Required job-summary fields: workflow run/attempt, PR number, expected and actual SHA, runner, Xcode version, runtime, device type, simulator UDID, result, total/passed/failed/skipped/expected-failure counts, start/finish timestamps, and exact test command with sensitive values omitted.
- Raw `xcodebuild` output is streamed to the Actions log with `tee` while preserving the command exit code via `pipefail`.
- A compact sanitized `xcresult` summary and the final 500 lines of the build/test log may be uploaded with seven-day retention. Full `.xcresult` bundles are not a normal success artifact because the repository previously hit artifact-storage pressure; on failure, the workflow may upload a compressed result bundle with three-day retention only if it is below a defined size cap.
- Failure to generate the summary is itself a gate failure. Artifact upload is evidence transport, not a substitute for test success.

### Paperclip/GitHub evidence link

The implementation issue, review issues, GitHub #1480, and the eventual PR must link the canary Actions run and record both device job URLs at the same head SHA. The merge-control issue must quote that SHA and may not rely on a screenshot or status copied from an older commit.

## 5. Branch-protection change

Branch protection changes occur only after the implementation PR has emitted both new contexts successfully and independent reviewers have accepted the workflow/security behavior.

Required contexts after change:

1. `Analyze (swift)` — retained for compatibility, explicitly not treated as real PR CodeQL/device evidence while its implementation remains echo-only.
2. `Tracked artifact guard`.
3. `iOS Beta Gate (iPhone)`.
4. `iOS Beta Gate (iPad regular-width)`.

Use GitHub Actions app ID `15368` for all four checks and preserve `strict: true`. Preserve conversation resolution and all unrelated protection fields. Read the entire current protection object immediately before mutation, save a sanitized snapshot in the Paperclip run scratch directory, apply only the required-status-check delta, then read back and compare exact contexts, app IDs, strict mode, conversation resolution, and admin enforcement.

No required context is removed as part of this work. `CodeQL` remains a scope-relevant evidence lane; the echo-only PR compatibility job is not promoted as full CodeQL proof. Security-sensitive work still needs the applicable SecurityAgent/full-analysis evidence before Paperclip disposition.

## 6. Paperclip PR-disposition integration

Update the Paperclip company workflow `wpr2-github-pr-disposition` (a Paperclip-internal workflow, not a file in this repository) after the GitHub gate is proven. For every same-repository PR to `main`, the `merge now` predicate must additionally require:

- Both device check runs are `completed/success` on the exact current head SHA.
- `Tracked artifact guard` and every GitHub-required context are `completed/success` on that SHA.
- No required check is queued indefinitely, skipped, neutral, cancelled, stale, absent, or attached only to an earlier SHA.
- Required conversations are resolved.
- Linked feature-specific device, accessibility, security, migration, and beta evidence is present when relevant.
- TestFlight archive/upload is not required on a PR; authenticated App Store Connect upload proof applies only to a separately authorized validated `main` release operation.

Runner-unavailable behavior is fail closed. A required device context that remains queued for 15 minutes triggers a high-priority Paperclip CI blocker assigned to CTO with runner status, labels, queue time, run URL, and service owner action. One transient infrastructure retry is allowed on the same SHA. Two infrastructure failures on the same SHA within 24 hours require a blocker/root-cause issue rather than repeated reruns. Any test/build failure routes to a bounded engineering repair child. No manager-facing churn comment is added unless evidence changes.

## 7. Dependency-ordered execution and review chain

These children are staged in this plan but must not be created until the CEO accepts this revision through the Paperclip confirmation interaction.

### Child A — Implement exact-head iPhone/iPad beta workflow

- **Owner role:** BackendCoder (CI/infrastructure implementation).
- **Repo/project:** `xXKillerNoobYT/Weird-Part-Run-2`, existing `hermes/hermes-335da4b2` worktree/branch only.
- **Exact scope:** Add `.github/workflows/ios-beta-gate.yml`; add the smallest parser/helper under `scripts/` only if inline shell would be difficult to test; update `docs/QA-PROCESS.md` and `docs/runbooks/local-mac-actions-runner.md`.
- **Acceptance criteria:** Both stable checks run at the exact PR head; wrong SHA, zero tests, skips, failures, timeout, missing runtime/device, or runner loss fail closed; no secrets/write permissions/archive/upload; no repo-local generated artifacts.
- **Required evidence:** Workflow syntax/readback, `actionlint` if installed, parser fixture tests if a helper is added, canary Actions run with both job URLs on one SHA, branch/worktree hygiene note.
- **Review lane:** LocalFirstReviewer → GPTReviewer → ClaudeReviewer; SecurityAgent checks self-hosted-runner trust, permissions, untrusted PR execution, shell injection, and artifact privacy.
- **Pass-up trigger:** Current-head canary succeeds on both device contexts and implementation evidence is linked to WEI-5356/GitHub #1480.

### Child B — Review fail-closed semantics and device evidence

- **Owner role:** LocalFirstReviewer, followed by GPTReviewer and ClaudeReviewer as separate dependency-linked review children.
- **Repo/project:** Same PR and exact head produced by Child A.
- **Exact scope:** Verify SHA pinning, job/check names, destinations, `xcresult` assertions, skipped-test handling, timeout/cancellation behavior, concurrency, cleanup, logs, and exclusions.
- **Acceptance criteria:** Each reviewer records `Accept` or `Revise` on the exact head; any later commit invalidates prior acceptance and restarts the review chain from LocalFirstReviewer.
- **Required evidence:** Reviewed head SHA, workflow diff, canary run URLs, unresolved-thread query, and explicit confirmation that an echo-only path cannot satisfy either device context.
- **Review lane:** Sequential LocalFirstReviewer → GPTReviewer → ClaudeReviewer.
- **Pass-up trigger:** ClaudeReviewer accepts the same SHA after prior lanes accept and all review threads are resolved.

### Child C — Verify iPhone/iPad CI behavior

- **Owner role:** UIExpertVerifier.
- **Repo/project:** Same PR and exact accepted head.
- **Exact scope:** Confirm iPhone compact and 13-inch regular-width iPad job summaries/destinations, nonzero app test execution, no skips, and failure behavior using a safe canary or controlled parser fixture. No product UI sign-off is implied.
- **Acceptance criteria:** `Pass` only when both required jobs are successful on the same exact head and the iPad evidence proves regular width; otherwise `Fail` or `Blocked` with the precise owner/action.
- **Required evidence:** Both job URLs, exact SHA, device/runtime fields, result counts, and any controlled negative-test evidence.
- **Review lane:** Reports to CTO after the code-review chain.
- **Pass-up trigger:** Exact-head dual-device `Pass` recorded in Paperclip and GitHub #1480.

### Child D — Apply and verify strict branch protection

- **Owner role:** CTO.
- **Repo/project:** GitHub repository settings for `xXKillerNoobYT/Weird-Part-Run-2`.
- **Exact scope:** Snapshot protection; add Artifact Guard and the two device contexts with app ID 15368; preserve strict mode, conversations, admin enforcement, and existing `Analyze (swift)`; read back; prove a new commit invalidates old greens.
- **Acceptance criteria:** API readback exactly matches the four required contexts; a newer canary commit is blocked until all four contexts complete on the new SHA; no protection is weakened.
- **Required evidence:** Sanitized before/after API objects, current-head canary PR URL, check-run URLs, and branch-protection readback.
- **Review lane:** CEO/CTO governance confirmation before settings mutation; ClaudeReviewer reviews the readback.
- **Pass-up trigger:** Strict current-head behavior is demonstrated and linked to WEI-5356/GitHub #1480.

### Child E — Update PR disposition workflow and unblock parent

- **Owner role:** CTO.
- **Repo/project:** Paperclip company workflow `workflows/wpr2-github-pr-disposition.md` and parent WEI-5318.
- **Exact scope:** Add exact-head device/status rules, retry/failure thresholds, evidence URLs, and owner routing; run one full PR-queue reclassification under the updated policy.
- **Acceptance criteria:** Every open PR is classified `merge now`, `repair`, `await external evidence`, or `close as superseded` using the new gate; no PR without both exact-head device checks is `merge now`; parent remains blocked until this child is complete.
- **Required evidence:** Workflow diff/path, queue classification comment, required-check/readback URLs, child/blocker readback, and GitHub/Paperclip traceability.
- **Review lane:** CEO verifies control-plane behavior after CTO update.
- **Pass-up trigger:** CEO accepts the updated queue behavior; WEI-5356 can close and WEI-5318 receives a real unblock signal.

### Dependency map

`CEO plan confirmation → Child A implementation → LocalFirst review → GPT review → Claude review → Security review → Child C device verification → Child D branch protection → Child E Paperclip disposition/readback → WEI-5356 done → WEI-5318 re-evaluated`

Only the first executable child is unblocked. Every later child uses a real `blockedByIssueIds` link to its immediate prerequisite. Parallel review is not used because every review must cover the same immutable head and later commits invalidate earlier evidence.

## 8. Rollout sequence

1. CEO accepts this exact plan revision through Paperclip.
2. CTO creates the dependency-linked children above and reads all blockers back.
3. Child A implements on the existing claimed branch; no new worktree/branch.
4. Push the workflow and documentation; open one PR linked to GitHub #1480 and WEI-5356.
5. Wait for both new contexts on the exact PR head; repair only bounded defects.
6. Complete sequential code/security reviews and resolve all conversations.
7. UIExpertVerifier records exact-head dual-device evidence.
8. CTO captures branch-protection before-state and requests the settings-change confirmation named in Child D.
9. Add the required contexts; read back protection.
10. Push a harmless plan/doc commit to the canary PR or update the branch from current `main`; verify old green results no longer satisfy the new head and all required checks rerun.
11. Update the Paperclip PR-disposition workflow and reclassify the queue.
12. Close GitHub #1480 only after the implementation PR is merged and branch protection/readback is proven.
13. Leave final cleanup notes for PR/branch/worktree and re-evaluate WEI-5318.

## 9. Rollback and emergency behavior

### Normal rollback

- Freeze WPR2 merges; do not remove required contexts merely because they are red or queued.
- Revert the workflow defect through a reviewed PR on the same local-runner path.
- Keep the device contexts required so the system fails closed while the fix is reviewed.
- Re-run both device jobs at the repaired exact head and read back protection before reopening the queue.

### Misnamed/non-emitting required context

If a typo or GitHub check-name mismatch makes every PR permanently impossible to validate:

1. Record the failed/missing context and branch-protection before-state.
2. Mark WEI-5356/WEI-5318 blocked with CTO as owner and the exact repair action.
3. Obtain explicit CEO confirmation for a temporary protection correction.
4. Restore only the exact previously captured required-status-check object; preserve strict mode, conversations, admin enforcement, and all unrelated settings.
5. Keep the merge queue frozen until the corrected workflow emits the intended context and the protection delta is reapplied/read back.

This emergency correction is not authority to weaken tests, bypass conversations, merge during the gap, change release state, or publish.

## 10. Review cadence and operating thresholds

- **Per PR:** inspect both device checks, exact head SHA, required checks, and review-resolution state before disposition.
- **Daily while beta queue is active:** CTO checks runner online/labels, oldest queued device job, failure classification, and any repeat failure issue.
- **Weekly:** review median/p95 duration, queue delay, cancellation rate, infrastructure failure rate, test failure rate, skip count, artifact/storage usage, and simulator cleanup failures.
- **After Xcode/iOS runtime upgrades:** run a controlled canary before allowing the queue to resume.
- **Issue threshold:** one test/build failure creates or updates a bounded repair issue; one infrastructure failure gets one same-SHA retry; two infrastructure failures on the same SHA in 24 hours create a high-priority CI reliability issue; any unexpected skip or zero-test result is immediately blocking; any runner queue over 15 minutes creates/updates a runner blocker.
- **Success target:** 100% of same-repo PR heads to `main` emit both device contexts; 0 merge-ready classifications with stale/missing device evidence; 0 unexpected skips; 0 repo-tracked DerivedData/result bundles; p95 queue-to-start below 15 minutes.

## 11. Validation checklist

- [ ] GitHub #1480 and WEI-5356 are bidirectionally linked.
- [ ] Workflow syntax and permissions reviewed.
- [ ] Stable check names exactly match branch protection.
- [ ] Checkout SHA assertion demonstrated.
- [ ] iPhone compact job runs nonzero tests with zero failures/skips.
- [ ] iPad 13-inch regular-width job runs nonzero tests with zero failures/skips.
- [ ] Controlled negative path cannot report success.
- [ ] Both check URLs point to the same current head SHA.
- [ ] Artifact Guard is required.
- [ ] `strict: true`, conversation resolution, and admin enforcement are preserved.
- [ ] New commit invalidates previous greens and reruns all required contexts.
- [ ] Paperclip disposition workflow rejects stale, missing, skipped, cancelled, neutral, and queued-indefinitely evidence.
- [ ] No archive/upload/TestFlight/public-release action occurred.
- [ ] App Store Connect authenticated-upload prerequisite remains separately blocked/owner-gated.
- [ ] PR/branch/worktree cleanup note is present.

## 12. Residual risks

- Simulator build/test proves supported device classes but not all physical-device behaviors, signing, Bluetooth, camera, push, background execution, or TestFlight processing. Those stay scope-relevant evidence gates.
- Running the app unit/regression suite twice increases local runner load. Two online runners reduce queue time, and concurrency cancellation prevents obsolete heads from consuming capacity.
- Existing `XCTSkip` paths may reveal latent missing-source assumptions immediately. This is expected fail-closed behavior; repair the tests/source rather than allowing skipped tests.
- Hard-coded simulator device-type availability can change after Xcode upgrades. Runtime/type discovery must fail with actionable logs, and upgrades require a canary.
- Full CodeQL on PRs remains separate from these device checks. The echo-only `Analyze (swift)` context must never be represented as full CodeQL proof.
- App Store Connect upload authentication remains unresolved; this plan deliberately does not address or bypass it.
