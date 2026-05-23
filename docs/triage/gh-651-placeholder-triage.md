# GH#651 Placeholder and dead-text triage

Paperclip: WEI-1996

Scope: iOS pages named in GitHub issue #651. The goal is to keep beta-facing paths free of ambiguous TODO/FIXME/Coming Soon/placeholder copy unless the page explicitly explains that the capability is planned and not currently interactive.

## Triage results

| Page | Marker reviewed | Decision |
| --- | --- | --- |
| `IOSDashboardQRScannerPage` | Inline comment said "Camera preview placeholder". | Not user-facing. The page uses `IOSQRScanner` / VisionKit `DataScannerViewController` for scanning and keeps the in-page black viewfinder as the status/controls surface. Comment renamed so it no longer reads like unfinished beta work. |
| `IOSNotebookDetailPage` | SwiftUI `AsyncImage` placeholder closure and input placeholder labels. | Intentional framework/UI terminology, not user-visible placeholder copy. No TODO/FIXME/Coming Soon text found. |
| `IOSSpendingDashboardPage` | Comment said charts placeholder. | Empty state is intentional: charts appear when cost data exists. Comment renamed to "no-data empty state". |
| `PartsCompanionsPage` | Comment documents fallback names for deleted hierarchy rows. | Intentional data-quality fallback; visible text is specific (`Unknown category/style/type (#id)`) rather than ambiguous placeholder text. No code change needed. |
| `IOSContactDetailPage` | Comment said edit sheet placeholder. | Edit sheet loads and saves contact fields through `PeopleService`; stale placeholder comment renamed. |
| `IOSTeamsPage` | `My Teams` filter returned all teams with a placeholder comment. | Real UX gap. Removed the misleading My Teams smart card and updated help copy; the remaining filters now only advertise behavior the page actually supports (`All` and `Staffed`). |
| `IOSAuditPage` | Misplaced-part save used `partId: 0` / `foundAtAreaId: 0` with a production placeholder comment. | Real missing implementation. Added explicit beta-safe blocking copy that tells the user to use guided count/search workflows until part/location lookup is wired, instead of logging placeholder IDs. |
| `IOSWarehouseNetworkPage` | User-visible future/coming-soon/planned placeholder copy. | Intentional planned-feature messaging. Copy now clearly says network sync is not active in this beta, this page is read-only, and no pairing/sync action is available here. Removed "coming soon" wording. |
| `NotificationPrefsPage` | File header said informational placeholder. | Stale. Preferences are loaded/saved through `SettingsService`; comment updated to describe current local storage behavior and sync-service requirement for push delivery. |

## Follow-up split-outs

- Paperclip follow-up `WEI-1998`: implement the misplaced-part report flow by resolving selected part and found/home locations before calling `logMisplacedPart`. This is now blocked in UI rather than silently writing placeholder IDs.
- `IOSWarehouseNetworkPage` remains planned/read-only pending the network sync infrastructure. Its current beta copy is intentionally explicit about that limitation.
