# iOS Reports Pages — Design Plan

## Navigation (Categorized)
Reports: Labor (Timesheets, Labor Overview, Daily Reports Summary), Financial (Spending, Profitability, Pre-Billing, Bookkeeper Export), Fleet (Fuel Costs, Maintenance Trends, Mileage/Cost Per Mile, Vehicle Utilization), Warehouse (Inventory Value, Backorders by supplier/brand, Turnover Rates), Scheduling (Crew Utilization, Dispatch Efficiency, Pipeline Status), Custom Reports (Report Builder), Shared Reports (public links)

## Key Design Decisions

### Every Report Page Gets
- Smart cards at top
- [Export PDF] + [Export CSV] in toolbar
- Help button
- Standard filter bar (program-wide standard)

### Standard Filter Bar (PROGRAM-WIDE — applies to ALL pages with date-relevant data)
Quick filters: This Week, Last Week, This Period, Last Period, This Month, Custom
Custom range: From/To date pickers
Plus page-specific filters (Job, Employee, Vehicle, Supplier, Status, etc.)
This applies to Reports, Orders, Warehouse movements, Fleet logs, Scheduling, Notebooks, Chat history, Audit logs — everywhere.

### 15-Minute Rounding on Timesheets
Company setting. Shows both actual and rounded times side by side when enabled.
Actual: 7:02 AM — 4:28 PM (9h 26m)
Rounded: 7:00 AM — 4:30 PM (9h 30m)

### Period Locking
Already implemented in Phase 8. Verify working in prompts.

### Report Builder (V1 — Simple)
Pick report type → Pick fields → Pick filters → Generate
Not a full BI tool — configurable views of existing data.

### Fleet Reports (NEW — in Reports section, not Fleet)
- Fuel costs by vehicle
- Maintenance cost trends
- Mileage / cost per mile over time
- Vehicle utilization (days in use vs idle)

### Warehouse Reports (NEW)
- Inventory value
- Backorders by supplier and brand
- Turnover rates

### Scheduling Reports (NEW)
- Crew utilization
- Dispatch efficiency
- Pipeline status

### Code Quality
Reports is architecturally clean — zero GRDB imports in any UI file. Labor/Financial/Custom/Shared report pages use ReportsService. Fleet/Warehouse/Scheduling report pages use their domain services (FleetService, WarehouseService, SchedulingService) directly — by design, as those reports aggregate data best served by the owning service. Design enhancement only.

---

## Current Implementation Status (2026-04-19, via AUTO GO C1 supplement)

**Status:** Phase 8 (Reports & Pre-Billing) is marked complete in CLAUDE.md. iOS page set, service APIs, and export utilities are all implemented. This section captures the state of the code so C1b (plan-vs-code drift) can verify against a concrete surface.

### iOS Files (22 total in `Features/Reports/`)

| File | Purpose | Plan section |
|---|---|---|
| `IOSReportsRouter.swift` | Nav root for Reports hub | Navigation (categorized) |
| `ReportDateRange.swift` + `ReportExportUtilities.swift` | Shared: date ranges, PDF/CSV export | Standard Filter Bar + PDF/CSV exports |
| `IOSTimesheetsPage.swift` | Labor → Timesheets w/ 15-min rounding | 15-Minute Rounding section |
| `IOSLaborOverviewPage.swift` | Labor → Labor Overview | Labor category |
| `IOSDailyReportsSummaryPage.swift` | Labor → Daily Reports Summary | Labor category |
| `IOSSpendingPage.swift` | Financial → Spending | Financial category |
| `IOSProfitabilityPage.swift` | Financial → Profitability | Financial category |
| `IOSPreBillingPage.swift` | Financial → Pre-Billing | Period Locking (Phase 8) |
| `IOSBookkeeperExportPage.swift` | Financial → Bookkeeper Export | Financial category |
| `FleetFuelCostReport.swift` | Fleet → Fuel costs by vehicle | Fleet Reports |
| `FleetMaintenanceTrendsReport.swift` | Fleet → Maintenance cost trends | Fleet Reports |
| `FleetMileageSummaryReport.swift` | Fleet → Mileage / cost per mile | Fleet Reports |
| `FleetUtilizationReport.swift` | Fleet → Vehicle utilization | Fleet Reports |
| `WarehouseInventoryValueReport.swift` | Warehouse → Inventory value | Warehouse Reports |
| `WarehouseBackorderReport.swift` | Warehouse → Backorders by supplier/brand | Warehouse Reports |
| `WarehouseTurnoverReport.swift` | Warehouse → Turnover rates | Warehouse Reports |
| `SchedulingCrewUtilizationReport.swift` | Scheduling → Crew utilization | Scheduling Reports |
| `SchedulingDispatchEfficiencyReport.swift` | Scheduling → Dispatch efficiency | Scheduling Reports |
| `SchedulingPipelineReport.swift` | Scheduling → Pipeline status | Scheduling Reports |
| `ReportBuilderView.swift` | Custom Reports (Report Builder V1) | Report Builder section |
| `IOSPublicReportView.swift` | Shared Reports via public link | Navigation (categorized) |

### Service API Surface

- **`ReportsService.swift`** — 13 public methods (listTimesheets, listSpending, generatePreBillingBatch, export helpers, etc.). No GRDB imports in UI; all queries routed through this service.
- **`DailyReportGenerator.swift`** — 2 methods (generateReport + helper). Already hardened via HUNT FIX iter 70 (silent-`try?` sweep replaced with `do-catch` + `isTableNotFoundError` guard for compliance-grade reliability).

### Known Issues

- None outstanding for reports area as of 2026-04-19. CLAUDE.md Phase 8 complete, HUNT FIX converged on daily-report generator reliability in iter 70.

---

## Test Plan

Tests in `core/Tests/WiredPartCoreTests/ReportsServiceTests.swift`.

Coverage targets:
- `getTimesheetData` — returns rows; 15-min rounding applied when setting enabled
- `getDailyReportSummary` — aggregates match seeded labor/job entries
- `getSpendingSummary` — total spend matches PO line items
- `getProfitabilitySummary` — job margin = revenue - materials - labor; soft-deleted parts excluded
- `getPreBillingData` — returns unlocked periods only; locked periods excluded
- `getBookkeeperLaborSummary` — correct join to billing_periods; locked filter
- `getBookkeeperMaterialPOs` — correct join; soft-deleted POs excluded
- `generateCustomReport` — returns correct columns for requested field set
- `saveReportConfig` + `getSavedReports` — round-trip; `markReportRun` updates timestamp
- `deleteSavedReport` — soft-delete; excluded from subsequent `getSavedReports`

---

## User Roles

| User | Access |
|------|--------|
| Any authenticated | View own timesheet only |
| Supervisor | Labor overview, daily reports summary |
| Office / Accounting | Financial reports (pre-billing, bookkeeper export, profitability) |
| Admin | All reports + Report Builder + delete saved reports |

Permissions enforced at UI layer (button/page visibility based on `appCore.currentUser?.permissions`).

---

## Security

- All ReportsService queries use GRDB parameterized args — no SQL injection risk
- Bookkeeper export contains sensitive financial data (wages, costs) — should only be accessible to accounting-role users
- `generateCustomReport` field list: confirm it's validated against a whitelist (not user-supplied column names injected into SQL)
- No credentials or PII in `print()` / notification payloads

---

## HIG / Accessibility

- Export toolbar buttons: `.accessibilityLabel("Export PDF")` / `.accessibilityLabel("Export CSV")`
- Stat cards at top of each report: `.isSelected` state via `.accessibilityAddTraits(.isSelected)` when filtered
- Charts: use `.chartContentAccessibilityLabel` for VoiceOver description
- Date picker for custom range: `.datePickerStyle(.compact)` for inline use
- Period locking: locked period badge (lock icon) should be `.accessibilityHidden(true)` — lockState is communicated by disabling edit actions
