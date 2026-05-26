# WEI-2027 Placeholder/dead-action cleanup evidence

Issue: WEI-2027
Date: 2026-05-23
Scope: P2 sweep for placeholder/dead-text markers listed by `docs/plans/ux-audit-page-gap-list-2026-05-23.md`.

## Outcome table

| Page | Marker inspected | Classification | Outcome |
| --- | --- | --- | --- |
| `IOSDashboardQRScannerPage` | Manual code field, Look Up buttons, disabled states | Real behavior / valid affordance | QR manual lookup routes through `processManualCode()` and disables empty/in-flight submits. No placeholder cleanup needed. |
| `IOSNotebookDetailPage` | `AsyncImage` placeholder, `NameInputSheet` TextField placeholders, todo/review copy | Valid SwiftUI placeholder/instructional copy | Image loading placeholder and text-entry hints are legitimate user-facing affordances. Todo review flows call `classifyTodoWork`; no dead action found. |
| `IOSSpendingDashboardPage` | Static scan page hit with no remaining placeholder/TODO markers in current source | No actionable marker | Current source contains no obvious placeholder/dead-text markers. |
| `PartsCompanionsPage` | Save/cancel disabled states in companion/alternative sheets | Real validation / valid affordance | Disabled states protect invalid or in-flight saves; no dead action found. |
| `IOSContactDetailPage` | Save disabled until first name; dirty-dismiss guard | Real validation / valid affordance | Required-field validation and `interactiveDismissDisabled(isDirty)` are intentional. |
| `IOSTeamsPage` | Save disabled until team name; dirty-dismiss guard | Real validation / valid affordance | Required-field validation and `interactiveDismissDisabled(isDirty)` are intentional. |
| `IOSAuditPage` | Count dialog disabled state, save disabled state, misplaced-part required fields | Real validation / valid affordance | Disabled states prevent incomplete audit/misplaced-part writes. No dead action found. |
| `IOSWarehouseNetworkPage` | “Device network discovery is not enabled yet” / roadmap-only connected devices panel | Confirmed dead placeholder because `IOSPeerBrowser` and `IOSSyncManager.startPeerDiscovery()` already exist | Replaced static placeholder with live sync-manager summary, Scan action, Browse Nearby Devices sheet, and updated AI/help copy. Added regression source test. |
| `NotificationPrefsPage` | Static scan page hit with no remaining placeholder/TODO markers in current source | No actionable marker | Current source contains no obvious placeholder/dead-text markers. |

## Code changes

- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseNetworkPage.swift`
  - Added `syncManager` binding.
  - Added `ActiveSheet.peerBrowser` and presents `IOSPeerBrowser()`.
  - Replaced stale “not enabled yet” copy with live discovered-peer count, sync configuration guidance, Scan button, and error notice.
  - Updated Help and AI page context to describe real actions instead of future-only roadmap behavior.
- `Weird Parts IOS/Weird Parts IOSTests/WarehouseNetworkPageRegressionTests.swift`
  - Adds a source-level regression test that guards the live peer-browser route and rejects the old stale copy.

## Verification

- RED source check before implementation failed as expected: required peer-browser strings were absent and stale copy was present.
- GREEN source check after implementation passed: `case peerBrowser`, `IOSPeerBrowser()`, `syncManager.discoveredPeers.count`, and `syncManager.startPeerDiscovery()` are present; stale `Device network discovery is not enabled yet` copy is absent.
- Swift parser check passed:
  - `xcrun swiftc -parse "Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSWarehouseNetworkPage.swift" "Weird Parts IOS/Weird Parts IOS/Sync/IOSPeerBrowser.swift" "Weird Parts IOS/Weird Parts IOSTests/WarehouseNetworkPageRegressionTests.swift"`
- iOS xcodebuild test could not run because the checkout does not contain a `.xcodeproj`/`.xcworkspace`.
- `core/swift test` was attempted; it built and started running but exceeded the 600s command timeout before completion. The changed files are iOS UI/source-test files, not core package files.

## Branch/workspace hygiene

- Started from a clean isolated worktree because the primary checkout has unrelated dirty work.
- `git fetch --prune origin` completed.
- Remote branch count at start: 59, over the soft cap of 20 but below hard cap 100.
- Open PR count at start: 0.
- Worktree: `.paperclip/worktrees/WEI-2027-page-placeholder-cleanup`.
