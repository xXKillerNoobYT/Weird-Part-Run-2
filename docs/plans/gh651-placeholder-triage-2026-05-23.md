# GH #651 Placeholder / Dead-Text Triage

Issue: [UX][P2] Triage placeholder and dead-text markers before beta (#651)
Paperclip: WEI-2004
Date: 2026-05-23

## Summary

Static audit markers in the named iOS pages were reviewed for user-visible TODO/FIXME/Coming Soon/placeholder/dead-text risk. Most hits were either SwiftUI API labels (`AsyncImage` / `TextField` placeholder parameters), comments, or valid unavailable-state copy. This branch fixes the one non-functional filter and tightens unavailable-state copy so beta users see real behavior or clear intentional states.

## Per-page triage

- `IOSDashboardQRScannerPage`
  - Finding: comment said camera preview placeholder.
  - Resolution: clarified that the scanner surface is paired with `IOSQRScanner` / `DataScannerViewController`; no user-visible placeholder string remains.

- `IOSNotebookDetailPage`
  - Finding: `AsyncImage` `placeholder` closure and `NameInputSheet` placeholder parameters.
  - Resolution: valid SwiftUI API/input prompt usage. No user-visible dead feature marker found.

- `IOSSpendingDashboardPage`
  - Finding: comment called the no-data spending state a charts placeholder.
  - Resolution: renamed to an empty state. User-visible copy already explains that charts appear once orders have cost data.

- `PartsCompanionsPage`
  - Finding: comments referenced old fallback strings for deleted hierarchy rows.
  - Resolution: renamed comment language to fallback label/fallback strings. User-visible fallback remains intentional: `Unknown category/style/type (#id)` surfaces data cleanup evidence instead of hiding missing rows.

- `IOSContactDetailPage`
  - Finding: edit sheet section marker included `(placeholder)`.
  - Resolution: removed stale marker. The edit sheet loads and saves contact fields through `PeopleService`.

- `IOSTeamsPage`
  - Finding: `My Teams` filter showed all teams while a comment admitted it was not filtering by the current user.
  - Resolution: added `PeopleService.listTeamIdsForUser(userId:)` and wired `My Teams` to active `employee_team_members` memberships for the signed-in user.

- `IOSAuditPage`
  - Finding: named by the source audit but no TODO/FIXME/Coming Soon/placeholder/dead-text hits are present in the current file.
  - Resolution: no code change needed.

- `IOSWarehouseNetworkPage`
  - Finding: planned network discovery used placeholder/coming-soon wording.
  - Resolution: replaced with an intentional unavailable-state message and roadmap language. The page now clearly says local database status is active and multi-device discovery requires configured sync infrastructure.

- `NotificationPrefsPage`
  - Finding: file comment described an informational placeholder.
  - Resolution: clarified that local notification preferences are persisted now and push delivery depends on sync service configuration.

## Verification

- Targeted static scan of named pages should no longer find TODO/FIXME/Coming Soon/dead-text markers.
- Remaining `placeholder` hits in named pages are valid SwiftUI API parameters or input prompts, not shipped dead-text markers.
