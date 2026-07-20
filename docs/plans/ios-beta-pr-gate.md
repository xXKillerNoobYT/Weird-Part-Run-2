# iOS Beta PR Gate

Status: Approved owner requirement captured in WEI-5356 / GitHub #1480
Owner: CTO
Repository: `xXKillerNoobYT/Weird-Part-Run-2`

## Purpose

`main` is the TestFlight beta integration branch. A pull request must not merge based on the echo-only `Analyze (swift)` compatibility context. Same-repository pull requests targeting `main` require real Xcode build/test evidence for both compact iPhone and regular-width iPad simulator classes at the exact pull-request head.

This PR gate does not archive, export, upload, or submit to App Store Connect. TestFlight archive/upload remains a separate post-merge `main` operation that requires an authenticated App Store Connect session.

## Design

### Workflow

Add `.github/workflows/ios-beta-gate.yml` with a two-entry matrix:

- `iPhone`: iPhone 16 Pro simulator on iOS 26.5
- `iPad`: iPad Air 13-inch (M2) simulator on iOS 26.5

Each matrix entry runs on the repo's self-hosted Mac labels:

`[self-hosted, macOS, ARM64, xcode, ios, local-mac]`

The workflow is limited to trusted same-repository pull requests targeting `main`. A pull request head update cancels stale in-flight work. Each lane checks out `github.event.pull_request.head.sha` explicitly and verifies `HEAD` equals that SHA before invoking Xcode.

### Deterministic runner

Add `scripts/ci/run-ios-beta-gate.sh` as the execution layer. It:

1. Records expected SHA, actual SHA, runner, Xcode, runtime, and device-class metadata.
2. Requires at least 60 GiB free on the volume backing `RUNNER_TEMP`; insufficient capacity fails before Xcode.
3. Verifies the requested iOS runtime and simulator device type exist.
4. Creates a run-owned temporary simulator and DerivedData directory; simulator boot is bounded at 15 minutes so runtime failures return control for cleanup/evidence upload.
5. Runs all app/core unit and regression tests from `WiredPart-iOS`, excluding the broad UI-test target from that phase.
6. Runs the bounded `WiredPart-iOS-Stage9-Smokes` deterministic UI plan on the same simulator; this includes the maintained viewport harness without invoking manual screenshot catalogs.
7. Writes an `.xcresult`, Xcode log, and machine-readable summary for both phases in every lane.
8. Bounds each Xcode phase at 50 minutes so the script can package partial evidence before the 120-minute job timeout.
9. Fails if Xcode fails or times out, the result bundle is missing, zero tests execute, any test fails, or any executed test is skipped.
10. Shuts down/deletes the run-owned simulator and removes DerivedData on exit; an `always()` cleanup step repeats simulator removal after an interrupted script.

### Evidence and retention

Each lane uploads its log, summary, metadata, and zipped `.xcresult` even when the gate fails. Artifacts are retained for seven days. GitHub Actions run/check URLs remain the durable audit index.

### Required checks

After the workflow has produced check runs on its own PR head, require both stable contexts on protected `main` with strict/current-head enforcement:

- `iOS Beta Gate (iPhone)`
- `iOS Beta Gate (iPad)`

Keep required conversation resolution enabled. Do not remove `Analyze (swift)` as part of this change; CodeQL policy changes are separate.

Paperclip PR disposition must classify missing, queued, cancelled, stale-head, or failed device contexts as not merge-ready.

## Dependencies

- Self-hosted runner online with labels `self-hosted`, `macOS`, `ARM64`, `xcode`, `ios`, `local-mac`.
- Xcode with iOS 26.5 simulator runtime.
- At least 60 GiB free on the runner temp volume.
- GitHub branch-administration permission to add required contexts after canary evidence exists.

Runner unavailability, simulator-runtime drift, disk pressure, or GitHub Actions outage are infrastructure failures. They remain red/pending; no echo-only substitute is permitted.

## Acceptance criteria

- A same-repository PR to `main` produces distinct phone and tablet checks at its exact head SHA.
- Both checks execute non-empty unit/regression and deterministic UI-smoke phases with zero failures and zero unexpected skips.
- Insufficient disk, absent runtime/device type, Xcode failure, missing/invalid result, timeout, cancellation, or runner outage cannot report success.
- `.xcresult`, log, summary, and provenance metadata are available on both success and failure.
- Branch protection requires both current-head contexts after the canary run.
- Ordinary PRs perform no archive, export, TestFlight upload, or App Store Connect operation.

## Validation

- Shell syntax: `bash -n scripts/ci/run-ios-beta-gate.sh`
- Workflow parse: Ruby/Psych or `actionlint` when available
- Source assertions: trusted-PR guard, exact SHA checkout, two device contexts, local runner labels, artifact upload under `if: always()`
- Local runner canary: execute one phone and one tablet lane with the current repository SHA and inspect `xcresulttool` summaries
- GitHub readback: PR check runs show both contexts on the current head; branch protection API lists both with `strict: true`

## Rollback

Revert the workflow and script only if the gate itself is defective. While repairing it, keep merges fail-closed. Do not replace it with an echo/status-only success path. Removing required contexts requires explicit owner approval because it weakens the beta gate.
