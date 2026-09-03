# WPR2 Exact-Main iPhone/iPad Beta Gate

Tracking: GitHub #1480; Paperclip WEI-6390 / WEI-6709.

## Purpose and boundary

`.github/workflows/ios-main-beta-gate.yml` is post-merge evidence for an immutable `main` commit. It supplements—never replaces—the strict PR contexts (`Analyze (swift)`, `iOS Beta Gate (iPhone)`, `iOS Beta Gate (iPad)`, and `Tracked artifact guard`). A `main` SHA is beta-ineligible until both `Main Beta Gate (iPhone)` and `Main Beta Gate (iPad)` succeed for that exact SHA and their `main-beta-eligibility.json` says `eligible: true`.

This workflow has `contents: read` only. It does not archive, export, sign, upload, or communicate with App Store Connect/TestFlight. It accepts no secrets and must never upload device data, databases, signing material, or credentials.

## Toolchain and execution contract

The public descriptor `.github/wpr2-main-build/toolchain.env` is the single toolchain contract:

- Xcode `26.3`, build `17C529`, at `/Applications/Xcode_26.3.app/Contents/Developer`.
- iOS runtime `26.5`; iPhone 16 Pro and iPad Air 13-inch (M2).
- 60 GiB minimum free runner-temp space, run-scoped simulators/DerivedData, seven-day redacted evidence retention.
- Tracked `Weird Parts.xcworkspace`, `WiredPart-iOS`, and `WiredPart-iOS-Stage9-Smokes` schemes.

`scripts/ci/verify-wpr2-xcode-toolchain.sh` runs before `simctl`, workspace listing, dependency resolution, build, or test. It exports only the declared `DEVELOPER_DIR`, then compares both `xcodebuild -version` fields exactly. It never changes global `xcode-select`, downloads Xcode, creates symlinks, or rewrites project metadata.

A runner with only Xcode 26.6 fails red before simulator work. That is an infrastructure/toolchain condition, not permission to fall back to 26.6 or change `LastUpgradeCheck`, `LastSwiftUpdateCheck`, or `CreatedOnToolsVersion`.

## Trigger and immutable SHA rules

- A `push` to `main` uses only `github.sha` as `EXPECTED_SHA` and checks it out with `persist-credentials: false`.
- A recovery dispatch requires `commit_sha` to be lowercase 40-hex, exist as a commit, and be reachable from fetched `origin/main`. It checks out and records that exact SHA; `github.sha` is never substituted.
- The two device lanes do not cancel one another or a predecessor's evidence. Each asserts `git rev-parse HEAD == EXPECTED_SHA` before Xcode.

## Evidence and eligibility

Each lane writes sanitized `metadata.txt`, toolchain evidence, logs, compact xcresult summaries, and compressed result bundles. The shared runner rejects a missing/unreadable result, non-passed result, zero tests, failure, skip, wrong SHA, missing scheme/runtime/device, disk shortfall, or timeout. Only run-owned simulators and DerivedData are deleted.

`scripts/ci/write-main-beta-eligibility.py` is local-only. It writes an ineligible lane record if metadata is absent or invalid. The aggregation job always emits `main-beta-eligibility.json`; it becomes eligible only when both lane records have the same expected SHA, exact descriptor toolchain, and nonzero/zero-failure/zero-skip unit and smoke phases. Missing or unreadable inputs remain `eligible: false` and fail the aggregation job.

For a beta decision, record:

1. immutable `main` SHA and both `Main Beta Gate` check URLs;
2. selected Xcode version/build, runtime/device types, and per-phase test counts;
3. matching eligibility artifact URL and its `eligible: true` record.

## Triage

| Failure class | Initial action | Eligibility |
|---|---|---|
| Toolchain/configuration | Verify the descriptor and provision the named Xcode bundle; perform a same-SHA canary after provisioning. | false |
| Runner infrastructure | Check queue delay, runner labels/online state, free space, runtime, and simulator service. One same-SHA retry is allowed for a transient condition. Two failures in 24h require a linked root-cause repair. | false |
| Build/test/result | Preserve artifacts, create/update one bounded repair linked to #1480, then rerun through normal PR and post-merge paths. | false |
| Control-plane integrity | Wrong SHA, malformed metadata, missing lane, or prohibited release path is a CI repair owned by the control-plane owner. Never weaken the gate. | false |

Watch queue-to-start delay at 15 minutes. Keep PR checks strict while any post-merge SHA is ineligible. Do not create a stabilization branch/tag unless separately approved with source SHA, owner, expiry, reconciliation path, and deletion condition.
