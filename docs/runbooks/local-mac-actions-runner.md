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

## Paperclip communication

PR-info, merge, review, and blocker issues should mention this local-runner path whenever CI status is discussed. Do not repeatedly ask Isaac to correct cloud Actions/billing blockers without first checking the local Mac runner.
