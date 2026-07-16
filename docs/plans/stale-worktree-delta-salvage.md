# Stale Worktree Delta Salvage

## Scope

Paperclip WEI-4980 reconciles small uncommitted deltas left in registered WPR2 worktrees after their owning tasks completed. No source worktree is reset, removed, or modified by this effort. The integration base is current `origin/main` (`ed961899`).

## User-visible flows and source direction

- Tab editor: Paperclip WEI-4508 explicitly asks for one fluid reorderable list so modules can cross the Fast Access/More boundary by drag instead of moving between separate lists.
- Beta bug reporting guide: GitHub #574 is closed and `ReportABugPage` exposes Settings → Report a Bug, Open GitHub issue, and Share report. The guide must describe the shipped flow rather than list it as unavailable.
- People add sheets: GitHub #1429 requires save failures in Customer, Contractor, Employee, Hat, Team, and Contact creation to identify the failed save operation rather than misleadingly report a load failure.
- Delivery date tests: the test class uses main-actor-isolated formatter state and should be isolated to `@MainActor` to avoid the Swift 6 actor warning found by WEI-4554.
- Repository hygiene: `.worktrees/` is generated execution state and should be ignored.

No new backend contract, data model, visual language, or navigation route is introduced.

## Classification against current main and active PRs

| Source worktree | Classification | Integration decision |
| --- | --- | --- |
| Root `fix/248-sheet-detents-central-wrappers` | `.gitignore` remains useful. QR callback changes are superseded by the stronger delivery gate and MainActor transaction in PR #1443, now integrated into open parent PR #1441. Its source-level detent test is superseded by executable `QRScanSheetRegressionTests` in that PR. | Preserve only `.gitignore`. |
| WEI-4508 | One-list tab editor is absent from main and has no PR. | Preserve. |
| WEI-4515 | Shipped in-app bug reporter exists on main, but the beta guide still says it is unavailable. No PR exists. | Preserve. |
| WEI-4532 | Geofence lunch/break behavior is superseded by merged PR #1420 / commit `d0a0166a`, whose implementation also centralizes service-unavailable handling. | Do not duplicate. |
| WEI-4542 | Six save-context corrections and regression coverage are absent from main; GitHub #1429 remains open. | Preserve. |
| WEI-4554 | Dispatch warning fix is superseded by merged PR #1438 / commit `ed961899`. The independent `DeliveryTimelineBarDateTests` MainActor annotation is absent from main. | Preserve only the test isolation annotation. |
| WEI-4563, WEI-4570, WEI-4571 | Overlapping QR actor/race changes are superseded by PR #1443's stronger `QRScanDeliveryGate`, executable callback-count coverage, and single MainActor completion path in parent PR #1441. PR #1449 adds the remaining derived-feedback preservation. | Do not duplicate. |

## State behavior and acceptance

- Tab order loads and saves as one ordered ID list. The first four entries are Fast Access and remaining entries are More. Dragging and arrow actions use the same ordering source. Empty More is valid; at least one Fast Access item remains.
- Existing reset confirmation, save behavior, labels, 44-point action targets, and accessibility descriptions remain.
- People forms retain existing loading, saving, success, disabled, and error behavior; only the error context text changes.
- Documentation matches current app entry points and retains manual GitHub fallback instructions.
- No stale worktree is cleaned up in this change.

## Verification

- `git diff --check` and focused source assertions for all preserved text/ordering behavior.
- Focused Xcode tests for `SilentLoadFailureSurfacingRegressionTests` and `DeliveryTimelineBarDateTests`.
- iOS Simulator build for the SwiftUI tab editor integration.
- User-facing tab editor follow-up through UIExpertVerifier at phone, tablet, and desktop-class simulator sizes before merge.
- Review lane: LocalFirstReviewer, then GPTReviewer.
