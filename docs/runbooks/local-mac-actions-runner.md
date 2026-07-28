# Local Mac Actions Runner for WPR2 PR Testing

Tracking: GitHub #943 / Paperclip WEI-3097

WPR2 uses a repo-specific self-hosted Mac runner so private PR build/test/QA jobs do not get stuck on cloud GitHub Actions billing or macOS hosted-runner availability.

## Runner identity

- Repo: `xXKillerNoobYT/Weird-Part-Run-2`
- Local runner directory: `/Users/IA/actions-runner/Weird-Part-Run-2`
- macOS service name: `IA-Mac-WPR2`
- Expected labels: `self-hosted`, `macOS`, `ARM64`/`arm64`, `xcode`, `ios`, `local-mac`

## Agent rule

Before marking a PR blocked by Actions/billing, check whether the failing job should run on the local Mac runner. If the job needs iOS, Xcode, Swift, Simulator, or Mac Catalyst, the preferred path is the local runner.

If a PR is blocked:

1. Check runner state:
   ```bash
   gh api repos/xXKillerNoobYT/Weird-Part-Run-2/actions/runners      --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
   ```
2. Check workflow `runs-on` labels:
   ```bash
   grep -R "runs-on:" .github/workflows
   ```
3. Check recent runs and failed jobs:
   ```bash
   gh run list -R xXKillerNoobYT/Weird-Part-Run-2 --limit 10
   gh run view <run-id> --log-failed -R xXKillerNoobYT/Weird-Part-Run-2
   ```
4. If the workflow is still using `macos-latest` or `ubuntu-latest` for WPR2 validation, create/fix the workflow issue instead of waiting on billing.
5. If the local runner is offline, report that exact blocker: service, runner status, labels, and last run checked.

## Workflow target pattern

Use the verified labels for WPR2 iOS/macOS jobs, for example:

```yaml
runs-on: [self-hosted, macOS, ARM64, xcode, ios, local-mac]
```

Keep cloud runners only for intentionally minimal jobs that do not need the Mac runner and are not contributing to PR blockages.

## iOS beta PR gate

Tracking: GitHub #1480 / Paperclip WEI-5356. Design: `docs/plans/ios-beta-pr-gate.md`.

Every same-repository PR targeting `main` must produce both current-head checks:

- `iOS Beta Gate (iPhone)`
- `iOS Beta Gate (iPad)`

The workflow is `.github/workflows/ios-beta-gate.yml`; deterministic execution is in `scripts/ci/run-ios-beta-gate.sh`. Each lane verifies the checked-out SHA, requires at least 60 GiB free on the runner temp volume (reclaiming stale shared DerivedData first when below budget — see Disk-capacity response), creates a run-owned iOS 26.5 simulator, runs the `WiredPart-iOS` unit/regression phase plus the bounded `WiredPart-iOS-Stage9-Smokes` UI plan, and uploads logs, summaries, metadata, and `.xcresult` evidence even on failure.

Missing, queued, cancelled, stale-head, skipped-test, zero-test, disk-capacity, simulator-runtime, timeout, and runner-offline outcomes are non-mergeable. Do not substitute `Analyze (swift)` or another echo/status-only check for either device lane.

Ordinary PR gates never archive or upload to App Store Connect. TestFlight upload is a separate post-merge `main` operation and requires an authenticated App Store Connect session.

### Disk-capacity response

The preflight self-heals before failing (added via #1536). When free space on the runner temp volume is below 60 GiB, the gate script deletes top-level `~/Library/Developer/Xcode/DerivedData` entries not modified in the last 60 minutes (cutoff tunable via `DERIVED_DATA_STALE_MINUTES`), then re-checks free space and fails only if still below budget. Newer entries are never deleted because a concurrent build on the other Mac runner may still own them. Each deleted entry is logged to the lane's `gate.log`, and `metadata.txt` records `derived_data_cleanup_freed_gib` and `post_cleanup_free_gib`.

If either lane still reports less than 60 GiB free after that cleanup:

1. Keep the check red and the PR out of the merge queue.
2. Inspect the runner volume and generated caches/artifacts without deleting live worktrees or unique work. Start from the lane's `gate.log`/`metadata.txt`, which already show what stale DerivedData was removed and how much that freed.
3. Perform only evidence-backed safe cleanup; route uncertain or broad deletion through a bounded cleanup issue.
4. Rerun both device lanes at the unchanged PR head and use the new check/artifact URLs as evidence.
5. Recheck free space after the run because a successful build can still expose a capacity trend.

Review the gate on every PR. A repeated capacity failure, missing runtime, malformed result bundle, or unavailable runner creates/updates a Paperclip CI blocker after the first reproducible occurrence; do not wait for a merge attempt.

## Paperclip communication

PR-info, merge, review, and blocker issues should mention this local-runner path whenever CI status is discussed. Do not repeatedly ask Isaac to correct cloud Actions/billing blockers without first checking the local Mac runner.
