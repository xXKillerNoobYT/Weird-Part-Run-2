# Stage 8 Reports Data Contract

Issue: WEI-3197
Owner: BackendCoder
Status: Spec complete
Last verified: 2026-06-08 against `ReportsService`, `WarehouseService`, `SettingsService`, and focused core tests.

## Scope

This contract defines the backend-owned data shapes for Stage 8 reports, pre-billing, bookkeeper export, and audit summaries in the current native iOS architecture. There are no HTTP routes in this repo; the contract boundary is the shared Swift core service API consumed by SwiftUI pages.

Primary implementation owners:

| Surface | Contract owner | Consumer |
|---|---|---|
| Labor, financial, pre-billing, bookkeeper reports | `ReportsService` | `Features/Reports/*`, `Features/Jobs/IOSDailyReportsPage.swift`, settings report templates |
| Warehouse audit summaries | `WarehouseService` | `Features/Warehouse/IOSAuditSummaryView.swift` |
| App-wide activity/audit feed | `SettingsService` | `Features/Settings/AuditLogPage.swift` |
| Fleet, warehouse analytics, scheduling analytics | Domain services | Report pages call the owning domain service directly |

## Request Conventions

All date-range report methods accept inclusive local-date strings:

```swift
startDate: String // YYYY-MM-DD
endDate: String   // YYYY-MM-DD
```

Service methods use GRDB parameter binding for date/user inputs. Dynamic custom-report fields must come from the existing whitelist in `ReportsService.generateCustomReport`, not from raw UI-supplied SQL.

Expected actor/permission model:

| Surface | Required app permission |
|---|---|
| Own timesheet | Authenticated user, limited to own row at UI/consumer layer |
| Labor overview and daily reports summary | Supervisor or office role |
| Spending, profitability, pre-billing, bookkeeper export | `view_financials` or accounting/admin role |
| Fleet financial reports | `view_fleet_financials` or admin role |
| Saved report delete | Admin or owner of saved report |
| Warehouse audit summary/actions | `perform_audit` for audit work, `manage_warehouse` for management views |
| App-wide audit log | Admin/settings access |

Current code enforces most page visibility in SwiftUI via `appCore.currentUser?.permissions`; service methods are local trusted-core methods and do not perform centralized actor checks. Any future IPC/HTTP layer must move these permission checks to the backend boundary before exposing the same data.

## Success And Error Contract

Read/report methods return typed rows and never mutate domain records.

Expected success:

- Return deterministic typed rows sorted as documented by each service method.
- Empty but valid result sets return `[]` or zero-valued aggregate structs.
- Historical joins filter `deleted_at IS NULL` where the joined entity should be hidden, but report joins must not add `is_active = 1`; historical records remain valid after users/jobs/parts become inactive.
- Pre-billing excludes labor entries covered by locked billing periods.
- Bookkeeper material exports mask soft-deleted suppliers as `Unknown`.

Expected error handling:

- Missing optional report tables may degrade to empty arrays/zero counts only where the service explicitly guards `isTableNotFoundError`.
- Schema, connection, SQL, and data-integrity errors otherwise propagate to the UI. Do not swallow these as empty reports because reports and audit pages are compliance-sensitive.
- UI consumers map thrown errors through `userFriendlyError`.

Persistence side effects:

- Report reads: none.
- Export PDF/CSV: writes generated files to a temporary/share location only; no domain data mutation.
- Saved report lifecycle: `saveReportConfig`, `markReportRun`, and `deleteSavedReport` mutate saved-report metadata only.
- Timesheet corrections are outside the read-only report contract; they must create correction audit records and require an explicit reason and actor id.

## Core Row Contracts

### Pre-Billing

Service method:

```swift
ReportsService.getPreBillingData(startDate:endDate:) throws -> [PreBillingRow]
```

Response row:

```swift
PreBillingRow {
  id: Int64              // job id
  jobName: String
  jobNumber: String
  regularHours: Double
  overtimeHours: Double
  materialCost: Double
  billableTotal: Double
  laborEntryCount: Int
  jobPartCount: Int
  jpoCount: Int
  purchaseOrderCount: Int
  auditDiscrepancyCount: Int // compatibility field; currently 0 until job-scoped audit provenance exists
  sourceSummary: String
}
```

Rules:

- Include jobs with regular or overtime labor in the requested inclusive date range.
- Include material cost, billable totals, and source counts from existing job/labor/job-parts/JPO/PO tables; do not persist a separate report source of truth.
- Exclude labor entries covered by a locked, non-deleted `billing_periods` row where `job_id` matches the labor job or where `job_id IS NULL` for a company-wide lock.
- Do not attribute `audit_counts` to a job through `part_id` alone. `auditDiscrepancyCount` remains `0` until a real job-scoped audit source exists.
- Sort by job name ascending.
- Consumers treat the output as already lock-filtered.

Verification hooks:

- `ReportsServiceTests.testPreBillingDataWithLaborEntries`
- `ReportsServiceTests.testPreBillingDataIncludesStage8ReadModelProvenance`
- `ReportsServiceTests.testPreBillingDataDoesNotExposeUnprovenSharedPartAuditAttribution`
- `ReportsServiceTests.testPreBillingDataExcludesLockedBillingPeriods`
- `ReportsServiceTests.testPreBillingDataExcludesCompanyWideLockedBillingPeriods`

### Bookkeeper Export

Service methods:

```swift
ReportsService.getBookkeeperLaborSummary(startDate:endDate:) throws -> [BookkeeperLaborRow]
ReportsService.getBookkeeperMaterialPOs(startDate:endDate:) throws -> [BookkeeperMaterialRow]
```

Response rows:

```swift
BookkeeperLaborRow {
  id: Int64              // user id
  employeeName: String
  regularHours: Double
  overtimeHours: Double
  grossPay: Double
  laborEntryCount: Int
  sourceSummary: String
}

BookkeeperMaterialRow {
  id: Int64              // purchase order id
  poNumber: String
  supplierName: String   // "Unknown" if supplier is missing or soft-deleted
  totalAmount: Double
  lineItemCount: Int
  jpoCount: Int
  jobNames: String       // distinct job names, ordered case-insensitively by name then job id, comma-separated
  sourceSummary: String
}
```

Rules:

- Labor summary groups by employee and sorts by employee name.
- Labor `grossPay` is regular hours at employee pay rate plus overtime at 1.5x pay rate.
- Material rows include non-deleted, non-cancelled purchase orders whose `COALESCE(order_date, created_at)` falls inside the inclusive date range and sort by PO number.
- Supplier names from soft-deleted supplier rows must not leak into the export.
- Material `jobNames` must be deterministic for multi-job POs: use distinct linked job names ordered by normalized name plus job id before concatenation.
- Exported currency should use exactly two fractional digits in UI/export utilities.

Verification hooks:

- `ReportsServiceTests.testBookkeeperLaborEmpty`
- `ReportsServiceTests.testBookkeeperLaborSummaryIncludesPayrollTotals`
- `ReportsServiceTests.testBookkeeperMaterialEmpty`
- `ReportsServiceTests.testBookkeeperMaterialPOs_excludesDeletedPurchaseOrders`
- `ReportsServiceTests.testBookkeeperMaterialPOs_hidesDeletedSupplierName`
- `ReportsServiceTests.testBookkeeperMaterialPOsDeterministicExportRows`

### Report Stats

Service method:

```swift
ReportsService.getReportsStats() throws -> ReportsStats
```

Response:

```swift
ReportsStats {
  openPeriods: Int
  pendingTimesheets: Int
  totalLaborHoursThisMonth: Double
}
```

Rules:

- `openPeriods` counts non-deleted billing periods where `locked_at IS NULL`.
- `pendingTimesheets` counts this-month, non-deleted labor entries still clocked in.
- `totalLaborHoursThisMonth` sums regular plus overtime hours for this month.

Verification hook:

- `ReportsServiceTests.testReportsStats`

### Warehouse Audit Summary

Service methods:

```swift
ReportsService.getAuditSummaries(startDate:endDate:) throws -> [AuditSummaryRow]
WarehouseService.getAuditSummary() throws -> AuditSummary
WarehouseService.getAuditDiscrepancies() throws -> [AuditDiscrepancy]
```

Response shapes:

```swift
AuditSummaryRow {
  partId: Int64
  partName: String
  areaId: Int64?
  areaLabel: String
  expectedQty: Int
  countedQty: Int
  variance: Int
  lastCountedAt: String
  sourceSummary: String
}

AuditSummary {
  totalParts: Int
  countedParts: Int
  discrepancies: Int
  lastAuditDate: String?
}

AuditDiscrepancy {
  partId: Int64
  partName: String
  partCode: String?
  locationType: String
  locationId: Int64
  systemQty: Int
  countedQty: Int
  difference: Int
  lastCounted: String?
}
```

Rules:

- `ReportsService.getAuditSummaries(startDate:endDate:)` reads `audit_counts` in the requested inclusive date range and groups variance by part plus area.
- Report summary rows must include deterministic labels and source summaries suitable for Stage 8 UI/export display.
- Summary scope is warehouse stock only.
- Counted/discrepancy totals are for records counted today.
- `lastAuditDate` propagates database errors except missing optional tables; do not represent real failures as "never audited".
- Discrepancy `difference` is counted quantity minus system quantity.

Verification hooks:

- `ReportsServiceTests.testAuditSummariesAggregateVarianceProvenance`
- `WarehouseAuditTests.testAuditSummaryRealDiscrepancies`

### App-Wide Audit Log

Service method:

```swift
SettingsService.listAuditLog(limit:) throws -> [AuditLogEntry]
```

Response:

```swift
AuditLogEntry {
  id: String
  entityType: String
  action: String
  timestamp: String
  deviceId: String?
}
```

Rules:

- Reads from `_change_log`.
- Sorts newest first.
- Honors caller-provided `limit`.
- Empty change logs return `[]`.

Verification hooks:

- `SettingsServiceTests.testListAuditLogEmpty`
- `SettingsServiceTests.testListAuditLogAfterWrite`
- `SettingsServiceTests.testListAuditLogLimit`

## Downstream Implementation Notes

- Frontend consumers should not recompute lock exclusion or supplier masking. These are backend contract responsibilities.
- UI export buttons can generate files from the typed rows, but they must not alter source report data.
- Any future sync/API adapter for these reports must expose the same response shapes and move role checks into the adapter boundary.
- QA/browser/simulator verification should prove page rendering and export affordances; backend verification is satisfied by the service tests named above.
