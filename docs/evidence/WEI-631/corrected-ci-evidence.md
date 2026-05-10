# WEI-631 Corrected CI Evidence for WEI-139

Artifact Links:
- [PR #373](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/373)
- [PR #373 files changed](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/373/files)
- [Commit 32ea8768017c0614fab5b1c262e279a2c1c22274](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/commit/32ea8768017c0614fab5b1c262e279a2c1c22274)
- [PR #373 current-head commit 8c7b6074b2245cbeacc249c7495272b0a8612a59](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/commit/8c7b6074b2245cbeacc249c7495272b0a8612a59)
- [PR #373 current-head CodeQL workflow run 25615262920](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/actions/runs/25615262920)
- [PR #373 current-head Analyze (swift) job 75194353798](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/actions/runs/25615262920/job/75194353798)

Acceptance Checklist:
- [x] Rechecked exact commit `32ea8768017c0614fab5b1c262e279a2c1c22274` for direct GitHub Actions runs, commit statuses, and check suites.
- [x] Confirmed exact commit `32ea8768017c0614fab5b1c262e279a2c1c22274` belongs to PR #373 and PR #374, while the cited `958b66049c3e2ee171d0c56af323db8ba741e90b` CI belongs to a different PR head and must not be used as proof for PR #373 commit `32ea876`.
- [x] Captured PR #373 current-head CI status for commit `8c7b6074b2245cbeacc249c7495272b0a8612a59`, which includes `32ea8768017c0614fab5b1c262e279a2c1c22274` in PR #373 history.
- [x] Captured a reproducible local Xcode simulator build transcript from a detached worktree at exact commit `32ea8768017c0614fab5b1c262e279a2c1c22274`.

Corrected CI Status:
- Exact commit `32ea8768017c0614fab5b1c262e279a2c1c22274`: no direct GitHub Actions workflow runs, commit statuses, or check suites were available as of `2026-05-10T05:29:49Z`.
- PR #373 current head `8c7b6074b2245cbeacc249c7495272b0a8612a59`: CodeQL Security Scan run `25615262920` completed successfully. Workflow status `completed`, conclusion `success`, created `2026-05-10T00:12:30Z`, updated `2026-05-10T01:21:41Z`.
- PR #373 current-head job `Analyze (swift)` `75194353798`: status `completed`, conclusion `success`, started `2026-05-10T01:01:03Z`, completed `2026-05-10T01:21:40Z`.

Exact-Commit GitHub API Evidence:
- `gh run list --repo xXKillerNoobYT/Weird-Part-Run-2 --commit 32ea8768017c0614fab5b1c262e279a2c1c22274 --limit 20 --json ...` returned `[]`.
- `gh api repos/xXKillerNoobYT/Weird-Part-Run-2/commits/32ea8768017c0614fab5b1c262e279a2c1c22274/status` returned `state: pending`, `total_count: 0`, `statuses: []`.
- `gh api repos/xXKillerNoobYT/Weird-Part-Run-2/commits/32ea8768017c0614fab5b1c262e279a2c1c22274/check-suites` returned no check suites.
- `gh api repos/xXKillerNoobYT/Weird-Part-Run-2/commits/32ea8768017c0614fab5b1c262e279a2c1c22274/pulls` returned PR #373 and PR #374.

Reproducible Xcode Execution Transcript:
- Worktree: `/tmp/wei631-32ea876`
- Commit: `32ea8768017c0614fab5b1c262e279a2c1c22274`
- Command: `xcodebuild -project 'Weird Parts IOS/Weird Parts.xcodeproj' -scheme 'Weird Parts' -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/wei631-32ea876-derived build`
- Result: `** BUILD SUCCEEDED **`
- Log: `/tmp/wei631-32ea876-xcodebuild.log`
- Log SHA-256: `1204dc68d0314fc009f21b5b42383269ddc2b467fe7dcbebc45805dd5da2d1c7`
- Log lines: `6335`
- Noted warnings: existing Swift warnings only, including `nonisolated(unsafe)` warnings in `IOSSyncManager.swift`, deprecated `onChange(of:perform:)`, and result-builder explicit `return` warnings. No build errors were emitted.

Unresolved Risks: Exact commit `32ea8768017c0614fab5b1c262e279a2c1c22274` still has no direct hosted CI run URL or job log URL. The corrected disposition should use PR #373 current-head CI plus this exact-commit Xcode build transcript, or request a new hosted workflow/PR run if exact-SHA hosted CI is mandatory.

Reproduction:
Command: `./scripts/qa-closure-bundle-validator.sh docs/evidence/WEI-631/corrected-ci-evidence.md`
Path: `docs/evidence/WEI-631/corrected-ci-evidence.md`
