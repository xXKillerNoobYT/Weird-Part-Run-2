# WPR2 worktree safety audit — 2026-08-21

Scope: `xXKillerNoobYT/Weird-Part-Run-2` registered worktrees. This is a point-in-time, non-destructive classification. It is not authorization to delete; any `REVIEW_DELETE_CANDIDATE` must first pass the required LocalFirstReviewer → GPTReviewer → ClaudeReviewer decision lane and be rechecked immediately before removal.

## Collection method

```sh
git worktree list --porcelain
git -C <worktree> status --porcelain
git -C <worktree> rev-parse --abbrev-ref --symbolic-full-name @{upstream}
git -C <worktree> merge-base --is-ancestor HEAD origin/main
git -C <repo> branch --merged origin/main
gh pr list -R xXKillerNoobYT/Weird-Part-Run-2 --state open
GET /api/companies/<company>/issues?status=todo,backlog,in_progress,blocked,in_review&limit=1000
```

Classification rule: preserve canonical; preserve dirty trees; preserve unmerged heads; preserve an open/running mapped Paperclip owner; only clean, merged, non-unique, non-active paths are review candidates. Unmapped paths are ambiguous and retained.

## Summary

- `RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER`: 8 paths / 0.29 GiB
- `RETAIN_CANONICAL`: 1 paths / 71.15 GiB
- `RETAIN_DIRTY`: 22 paths / 14.36 GiB
- `RETAIN_UNMAPPED_AMBIGUOUS`: 1 paths / 0.04 GiB
- `RETAIN_UNMERGED_HEAD`: 26 paths / 21.90 GiB
- `REVIEW_DELETE_CANDIDATE`: 61 paths / 25.02 GiB

## Open PR disposition

All five open PRs are `repair`; none prove the merge-now predicate. The local Mac iOS runners are online, and the listed Beta-Gate results are historical current-head evidence only—each branch is behind `main` and needs a new exact-head run after repair/rebase.

| PR | Disposition | Evidence and next action |
|---|---|---|
| [#1608](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/1608) | `repair` | Draft; `DIRTY`; changes requested; iPhone/iPad gate last passed. Owner must resolve requested changes/conflict, rebase, then request the review lanes. |
| [#1635](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/1635) | `repair` | Non-draft but behind; both iOS Beta Gates failed. Repair/rebase and obtain current-head local-runner gates before a merge review. |
| [#1750](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/1750) | `repair` | Draft and behind; prior checks passed. Rebase, complete implementation, mark ready, and run current-head review/gates. |
| [#1769](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/1769) | `repair` | Draft and behind; both iOS Beta Gates failed (the PR describes a deliberately red test). Owner must choose the valid repair/supersession route; it cannot enter merge queue. |
| [#1781](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/pull/1781) | `repair` | Draft and behind; prior checks passed. Rebase and complete draft/review prerequisites before queue admission. |

## Per-worktree evidence

| Classification | Issue hint | Paperclip status / active run | Clean | Merged into main | Unique/unmerged HEAD | Branch | Approx. GiB | Path |
|---|---|---|---:|---:|---:|---|---:|---|
| RETAIN_DIRTY | WEI-2473 | no-mapped-open-issue | false | false | YES | `DETACHED` | 0.97 | `/Users/IA/.paperclip-worktrees/WEI-2473-zone-qa` |
| RETAIN_DIRTY | WEI-5218 | no-mapped-open-issue | false | false | YES | `DETACHED` | 0.03 | `/Users/IA/.paperclip/scratch/WEI-5218-pr1468-qa` |
| RETAIN_DIRTY | WEI-5356 | no-mapped-open-issue | false | true | NO | `fix/1492-testflight-test-portability` | 0.03 | `/Users/IA/.paperclip/worktrees/WEI-5356-testflight-test-portability` |
| RETAIN_CANONICAL | — | no-mapped-open-issue | true | true | NO | `main` | 71.15 | `/Users/IA/GitHub/Weird-Part-Run-2` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/compassionate-goldstine-ea2c11` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/beautiful-cannon-b8ac8b` |
| RETAIN_UNMAPPED_AMBIGUOUS | — | no-mapped-open-issue | true | false | NO | `DETACHED` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/busy-easley-c2d2be` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/friendly-lamport-5f2e7e` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/dreamy-kowalevski-caef8a` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/cool-gauss-91a047` | 1.10 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/elastic-kepler-96d373` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/focused-northcutt-7cca7b` | 1.32 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/epic-dhawan-2b4d33` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `fix/1763-stale-sync-door-doc-comments` | 0.60 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/festive-shirley-3c556a` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/peaceful-heisenberg-ec2e66` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/hungry-bhaskara-b208aa` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/jolly-lamarr-5a7551` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/jolly-lamarr-5a7551` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/kind-jepsen-a4cfdb` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/lucid-taussig-f0228e` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/musing-proskuriakova-2de5e5` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/musing-proskuriakova-2de5e5` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/priceless-wiles-9bb3be` | 1.10 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/nifty-haibt-05b3be` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/intelligent-dubinsky-e6d7a5` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/recursing-pike-048f33` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/eloquent-shirley-9bf238` | 1.08 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/stoic-clarke-51a032` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/trusting-banach-79bbcf` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/trusting-banach-79bbcf` |
| REVIEW_DELETE_CANDIDATE | — | no-mapped-open-issue | true | true | NO | `claude/upbeat-colden-81e607` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/upbeat-colden-81e607` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `wip/1760-coverage` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_053cf10c-f41-1` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_053cf10c-f41-2` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_053cf10c-f41-3` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `wip/1760-major-fix` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_165917b8-1a0-1` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_165917b8-1a0-2` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_165917b8-1a0-3` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_165917b8-1a0-4` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_165917b8-1a0-5` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `probe-1760` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_f8fe7e7f-a91-11` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `DETACHED` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_f8fe7e7f-a91-14` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `probe1760_a15` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_f8fe7e7f-a91-15` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `probe1760` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_f8fe7e7f-a91-5` |
| RETAIN_DIRTY | — | no-mapped-open-issue | false | true | NO | `worktree-wf_f8fe7e7f-a91-8` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.claude/worktrees/wf_f8fe7e7f-a91-8` |
| RETAIN_DIRTY | WEI-4039 | no-mapped-open-issue | false | true | NO | `WEI-4039-field-test-owner-approval-approve-first-controlled-beta-pass-for-pr-1095-data-safety-candidate` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4039-field-test-owner-approval-approve-first-controlled-beta-pass-for-pr-1095-data-safety-candidate` |
| RETAIN_DIRTY | WEI-4139 | no-mapped-open-issue | false | true | NO | `WEI-4139-wpr2-beta-github-issue-burn-down-merge-chain` | 3.56 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4139-wpr2-beta-github-issue-burn-down-merge-chain` |
| RETAIN_UNMERGED_HEAD | WEI-4139 | no-mapped-open-issue | true | false | YES | `hermes/hermes-3e4b037b` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4139-wpr2-beta-github-issue-burn-down-merge-chain/.worktrees/hermes-3e4b037b` |
| RETAIN_UNMERGED_HEAD | WEI-4139 | no-mapped-open-issue | true | false | YES | `hermes/hermes-9fa8dfac` | 1.14 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4139-wpr2-beta-github-issue-burn-down-merge-chain/.worktrees/hermes-9fa8dfac` |
| RETAIN_UNMERGED_HEAD | WEI-4224 | blocked | true | false | YES | `WEI-4224-085-merge-resolve-pr-1093-fix-show-active-supply-run-start-on-clock-page` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4224-085-merge-resolve-pr-1093-fix-show-active-supply-run-start-on-clock-page` |
| RETAIN_DIRTY | WEI-4469 | no-mapped-open-issue | false | true | NO | `WEI-4469-just-had-lot-of-work-done-on-the-app-and-a-lot-of-github-issues-completed-so-a-lot-of-the-tasks-your-working-on` | 2.61 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4469-just-had-lot-of-work-done-on-the-app-and-a-lot-of-github-issues-completed-so-a-lot-of-the-tasks-your-working-on` |
| RETAIN_DIRTY | WEI-4508 | no-mapped-open-issue | false | true | NO | `WEI-4508-the-edit-tabs-need-to-be-fluint-like-one-list-that-the-pages-can-move-on-right-now-you-can-move-them-but-it-a-p` | 0.58 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4508-the-edit-tabs-need-to-be-fluint-like-one-list-that-the-pages-can-move-on-right-now-you-can-move-them-but-it-a-p` |
| RETAIN_DIRTY | WEI-4515 | no-mapped-open-issue | false | true | NO | `WEI-4515-keep-github-issue-work-moving` | 1.02 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4515-keep-github-issue-work-moving` |
| RETAIN_DIRTY | WEI-4532 | no-mapped-open-issue | false | true | NO | `WEI-4532-daily-exploratory-bug-hunt` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4532-daily-exploratory-bug-hunt` |
| RETAIN_DIRTY | WEI-4542 | no-mapped-open-issue | false | true | NO | `WEI-4542-daily-exploratory-bug-hunt` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4542-daily-exploratory-bug-hunt` |
| RETAIN_DIRTY | WEI-4554 | no-mapped-open-issue | false | true | NO | `WEI-4554-daily-exploratory-bug-hunt` | 1.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4554-daily-exploratory-bug-hunt` |
| RETAIN_DIRTY | WEI-4563 | no-mapped-open-issue | false | true | NO | `WEI-4563-keep-github-issue-work-moving` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4563-keep-github-issue-work-moving` |
| RETAIN_DIRTY | WEI-4570 | no-mapped-open-issue | false | true | NO | `WEI-4570-daily-exploratory-bug-hunt` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4570-daily-exploratory-bug-hunt` |
| RETAIN_DIRTY | WEI-4571 | no-mapped-open-issue | false | true | NO | `WEI-4571-keep-github-issue-work-moving` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4571-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-4592 | no-mapped-open-issue | true | true | NO | `WEI-4592-ceo-delegation-wpr2-audit-branch-pr-merge-readiness-and-github-closure-gate` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4592-ceo-delegation-wpr2-audit-branch-pr-merge-readiness-and-github-closure-gate` |
| RETAIN_DIRTY | WEI-4692 | blocked | false | false | YES | `WEI-4692-ui-qa-pr-1441-po-clock-warehouse-scanner-flows` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4692-ui-qa-pr-1441-po-clock-warehouse-scanner-flows` |
| RETAIN_DIRTY | WEI-4745 | no-mapped-open-issue | false | false | YES | `WEI-4745-keep-github-issue-work-moving` | 1.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4745-keep-github-issue-work-moving` |
| RETAIN_DIRTY | WEI-4839 | no-mapped-open-issue | false | false | YES | `WEI-4839-keep-github-issue-work-moving` | 1.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-4839-keep-github-issue-work-moving` |
| RETAIN_UNMERGED_HEAD | WEI-5087 | no-mapped-open-issue | true | false | YES | `WEI-5087-cto-audit-wpr2-branch-and-pr-merge-readiness-control-pass` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-5087-cto-audit-wpr2-branch-and-pr-merge-readiness-control-pass` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-5729 | blocked | true | true | NO | `WEI-5729-desing-core-to-apply-to-app-exspacily-empty-location` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-5729-desing-core-to-apply-to-app-exspacily-empty-location` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-5970 | blocked | true | true | NO | `WEI-5970-hygiene-wpr2-reconcile-retained-patch-unique-worktree-heads` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-5970-hygiene-wpr2-reconcile-retained-patch-unique-worktree-heads` |
| REVIEW_DELETE_CANDIDATE | WEI-5972 | no-mapped-open-issue | true | true | NO | `WEI-5972-hygiene-wpr2-reconcile-retained-heads-batch-2` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-5972-hygiene-wpr2-reconcile-retained-heads-batch-2` |
| REVIEW_DELETE_CANDIDATE | WEI-5973 | no-mapped-open-issue | true | true | NO | `WEI-5973-hygiene-wpr2-reconcile-retained-heads-batch-3` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-5973-hygiene-wpr2-reconcile-retained-heads-batch-3` |
| REVIEW_DELETE_CANDIDATE | WEI-6537 | no-mapped-open-issue | true | true | NO | `WEI-6537-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6537-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-6908 | no-mapped-open-issue | true | true | NO | `WEI-6908-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6908-keep-github-issue-work-moving` |
| RETAIN_UNMERGED_HEAD | WEI-6916 | blocked | true | false | YES | `WEI-6916-sync-ux-bluetooth-sync-is-one-directional-per-tap-pushed-is-set-pulled-stays-0` | 1.08 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6916-sync-ux-bluetooth-sync-is-one-directional-per-tap-pushed-is-set-pulled-stays-0` |
| RETAIN_UNMERGED_HEAD | WEI-6918 | no-mapped-open-issue | true | false | YES | `WEI-6918-sync-ux-show-the-bluetooth-error-code-on-the-join-pairing-screen-too-not-just-nearby-devices` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6918-sync-ux-show-the-bluetooth-error-code-on-the-join-pairing-screen-too-not-just-nearby-devices` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-6924 | blocked | true | true | NO | `WEI-6924-security-incident-contain-credential-like-runtime-output-on-wei-6917` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6924-security-incident-contain-credential-like-runtime-output-on-wei-6917` |
| RETAIN_UNMERGED_HEAD | WEI-6971 | no-mapped-open-issue | true | false | YES | `WEI-6971-wpr2-cto-action-re-establish-current-pr-disposition-and-github-closure-control` | 1.08 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6971-wpr2-cto-action-re-establish-current-pr-disposition-and-github-closure-control` |
| REVIEW_DELETE_CANDIDATE | WEI-6998 | no-mapped-open-issue | true | true | NO | `WEI-6998-unblock-liveness-incident-for-wei-4292` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-6998-unblock-liveness-incident-for-wei-4292` |
| REVIEW_DELETE_CANDIDATE | WEI-7001 | no-mapped-open-issue | true | true | NO | `WEI-7001-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7001-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7015 | no-mapped-open-issue | true | true | NO | `WEI-7015-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7015-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7021 | no-mapped-open-issue | true | true | NO | `WEI-7021-sync-critical-bluetooth-snapshot-transfer-has-no-flow-control-floods-mcsession-and-dies-partway` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7021-sync-critical-bluetooth-snapshot-transfer-has-no-flow-control-floods-mcsession-and-dies-partway` |
| RETAIN_UNMERGED_HEAD | WEI-7022 | no-mapped-open-issue | true | false | YES | `WEI-7022-sync-critical-joiner-buffers-the-whole-snapshot-in-memory-stage-it-durably-instead` | 1.08 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7022-sync-critical-joiner-buffers-the-whole-snapshot-in-memory-stage-it-durably-instead` |
| RETAIN_UNMERGED_HEAD | WEI-7024 | no-mapped-open-issue | true | false | YES | `WEI-7024-cto-design-gate-stage-safe-bluetooth-snapshot-transfer-remediation-for-wei-7021-wei-7022` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7024-cto-design-gate-stage-safe-bluetooth-snapshot-transfer-remediation-for-wei-7021-wei-7022` |
| REVIEW_DELETE_CANDIDATE | WEI-7039 | no-mapped-open-issue | true | true | NO | `WEI-7039-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7039-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7046 | no-mapped-open-issue | true | true | NO | `WEI-7046-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7046-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7048 | no-mapped-open-issue | true | true | NO | `WEI-7048-weekly-ui-usability-verification` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7048-weekly-ui-usability-verification` |
| REVIEW_DELETE_CANDIDATE | WEI-7054 | no-mapped-open-issue | true | true | NO | `WEI-7054-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7054-keep-github-issue-work-moving` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-7059 | blocked | true | true | NO | `WEI-7059-infra-critical-execute-ceo-approved-bounded-xcode-deriveddata-purge` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7059-infra-critical-execute-ceo-approved-bounded-xcode-deriveddata-purge` |
| REVIEW_DELETE_CANDIDATE | WEI-7066 | no-mapped-open-issue | true | true | NO | `WEI-7066-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7066-keep-github-issue-work-moving` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-7079 | blocked | true | true | NO | `WEI-7079-ops-cleanup-close-the-12-stale-todo-items-9-reference-prs-already-closed-merged-gh-1711` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7079-ops-cleanup-close-the-12-stale-todo-items-9-reference-prs-already-closed-merged-gh-1711` |
| REVIEW_DELETE_CANDIDATE | WEI-7080 | no-mapped-open-issue | true | true | NO | `WEI-7080-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7080-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-7086 | blocked | true | true | NO | `WEI-7086-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7086-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7088 | no-mapped-open-issue | true | true | NO | `WEI-7088-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7088-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7090 | no-mapped-open-issue | true | true | NO | `WEI-7090-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7090-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7094 | no-mapped-open-issue | true | true | NO | `WEI-7094-daily-exploratory-bug-hunt` | 1.08 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7094-daily-exploratory-bug-hunt` |
| REVIEW_DELETE_CANDIDATE | WEI-7097 | no-mapped-open-issue | true | true | NO | `WEI-7097-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7097-keep-github-issue-work-moving` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-7109 | blocked | true | true | NO | `WEI-7109-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7109-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7113 | no-mapped-open-issue | true | true | NO | `WEI-7113-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7113-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7119 | no-mapped-open-issue | true | true | NO | `WEI-7119-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7119-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7120 | no-mapped-open-issue | true | true | NO | `WEI-7120-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7120-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7123 | no-mapped-open-issue | true | true | NO | `WEI-7123-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7123-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7126 | no-mapped-open-issue | true | true | NO | `WEI-7126-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7126-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7133 | no-mapped-open-issue | true | true | NO | `WEI-7133-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7133-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7147 | no-mapped-open-issue | true | true | NO | `WEI-7147-keep-github-issue-work-moving` | 1.08 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7147-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7149 | no-mapped-open-issue | true | true | NO | `WEI-7149-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7149-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7150 | no-mapped-open-issue | true | true | NO | `WEI-7150-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7150-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7153 | no-mapped-open-issue | true | true | NO | `WEI-7153-weekly-ui-usability-verification` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7153-weekly-ui-usability-verification` |
| REVIEW_DELETE_CANDIDATE | WEI-7154 | no-mapped-open-issue | true | true | NO | `WEI-7154-daily-exploratory-bug-hunt` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7154-daily-exploratory-bug-hunt` |
| REVIEW_DELETE_CANDIDATE | WEI-7156 | no-mapped-open-issue | true | true | NO | `WEI-7156-keep-github-issue-work-moving` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7156-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7157 | no-mapped-open-issue | true | true | NO | `WEI-7157-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7157-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7160 | no-mapped-open-issue | true | true | NO | `WEI-7160-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7160-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7170 | no-mapped-open-issue | true | true | NO | `WEI-7170-daily-exploratory-bug-hunt` | 4.13 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7170-daily-exploratory-bug-hunt` |
| REVIEW_DELETE_CANDIDATE | WEI-7173 | no-mapped-open-issue | true | true | NO | `WEI-7173-keep-github-issue-work-moving` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7173-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7175 | no-mapped-open-issue | true | true | NO | `WEI-7175-unblock-liveness-incident-for-wei-7164` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7175-unblock-liveness-incident-for-wei-7164` |
| REVIEW_DELETE_CANDIDATE | WEI-7178 | no-mapped-open-issue | true | true | NO | `WEI-7178-unblock-liveness-incident-for-wei-7164` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7178-unblock-liveness-incident-for-wei-7164` |
| REVIEW_DELETE_CANDIDATE | WEI-7183 | no-mapped-open-issue | true | true | NO | `WEI-7183-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7183-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7184 | no-mapped-open-issue | true | true | NO | `WEI-7184-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7184-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7188 | no-mapped-open-issue | true | true | NO | `WEI-7188-daily-exploratory-bug-hunt` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7188-daily-exploratory-bug-hunt` |
| REVIEW_DELETE_CANDIDATE | WEI-7191 | no-mapped-open-issue | true | true | NO | `WEI-7191-keep-github-issue-work-moving` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7191-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7193 | no-mapped-open-issue | true | true | NO | `WEI-7193-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7193-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| RETAIN_ACTIVE_OR_AMBIGUOUS_OWNER | WEI-7194 | blocked | true | true | NO | `WEI-7194-sync-bug-p0-phantom-connected-peer-iossyncmanager-957-re-adds-peers-peermanager-already-dropped-gh-1779` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7194-sync-bug-p0-phantom-connected-peer-iossyncmanager-957-re-adds-peers-peermanager-already-dropped-gh-1779` |
| REVIEW_DELETE_CANDIDATE | WEI-7196 | no-mapped-open-issue | true | true | NO | `WEI-7196-daily-blocker-topology-audit` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7196-daily-blocker-topology-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7208 | no-mapped-open-issue | true | true | NO | `WEI-7208-daily-exploratory-bug-hunt` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7208-daily-exploratory-bug-hunt` |
| REVIEW_DELETE_CANDIDATE | WEI-7212 | no-mapped-open-issue | true | true | NO | `WEI-7212-keep-github-issue-work-moving` | 1.09 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7212-keep-github-issue-work-moving` |
| REVIEW_DELETE_CANDIDATE | WEI-7220 | no-mapped-open-issue | true | true | NO | `WEI-7220-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` | 0.07 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7220-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit` |
| REVIEW_DELETE_CANDIDATE | WEI-7220 | no-mapped-open-issue | true | true | NO | `hermes/hermes-df1c927f` | 0.04 | `/Users/IA/GitHub/Weird-Part-Run-2/.paperclip/worktrees/WEI-7220-daily-paperclip-junk-file-cleanup-and-disk-pressure-audit/.worktrees/hermes-df1c927f` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `hermes/hermes-03d7492d` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.worktrees/hermes-03d7492d` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `hermes/hermes-8c14ea88` | 0.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.worktrees/hermes-8c14ea88` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `hermes/hermes-94bd0062` | 1.07 | `/Users/IA/GitHub/Weird-Part-Run-2/.worktrees/hermes-94bd0062` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `hermes/hermes-a4fc8eab` | 1.03 | `/Users/IA/GitHub/Weird-Part-Run-2/.worktrees/hermes-a4fc8eab` |
| RETAIN_DIRTY | WEI-5305 | no-mapped-open-issue | false | false | YES | `DETACHED` | 0.12 | `/Users/IA/Library/Developer/XcodeBuildMCP/workspaces/WEI-5305-exact-head-b3e766113` |
| RETAIN_DIRTY | WEI-5324 | no-mapped-open-issue | false | false | YES | `DETACHED` | 0.03 | `/Users/IA/Library/Developer/XcodeBuildMCP/workspaces/WEI-5324-exact-head-ec202db7d9` |
| RETAIN_UNMERGED_HEAD | — | no-mapped-open-issue | true | false | YES | `fix/bt-only-deadlines` | 1.10 | `/Users/IA/github/Weird-Part-Run-2/.claude/worktrees/fervent-rhodes-03a6e8` |
| RETAIN_DIRTY | — | no-mapped-open-issue | false | true | NO | `fix/beta-ai-epics-gapclose` | 1.01 | `/Users/IA/wpr2-beta/ai-epics-gapclose` |
| RETAIN_DIRTY | — | no-mapped-open-issue | false | true | NO | `fix/beta-detents-sweep-248` | 0.03 | `/Users/IA/wpr2-beta/detents-sweep-248` |

## Preconditions for a deletion batch

1. Refresh this exact evidence immediately before acting; the owner/run status can change.
2. Verify no queued/running Paperclip owner, a clean status, a merged/superseded/abandoned branch, and no unique commits.
3. Record GitHub PR/branch state and Paperclip issue cleanup note for each removed path.
4. Cap the batch at 50 GiB. Re-measure `/System/Volumes/Data` after the batch.
5. Do not delete canonical checkout, current execution worktree, dirty trees, unmerged heads, or unmapped paths.
