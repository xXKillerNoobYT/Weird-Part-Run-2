# Phase 8: Reports & Pre-Billing

> **Date:** 2026-03-06 (updated 2026-03-07)
> **Status:** ✅ Complete — all 6 pages built, period locking + bookkeeper exports implemented
> **New numbering:** Phase 8 (formerly Phase 11 in old numbering)
> **Dependencies:** Cost tracking (Phase 7D ✅), labor data (Phase 4 ✅), job parts (Phase 5 ✅), scheduling (Phase 10 ✅)
> **Estimated work:** 5-6 days (expanded from 3-4 — added period locking, bookkeeper exports, profitability)
> **Deployment plan:** `docs/plans/deployment-master-plan.md`

---

## Context

The Reports module exists in skeleton form:
- **4 stub backend endpoints** in `backend/app/routers/reports.py` that return "coming soon"
- **4 stub frontend pages** that show `<EmptyState>` with "coming soon" messages
- **1 functional tab** (Daily Reports) that already works via the scheduler/report_service

The navigation is already wired in `frontend/src/lib/navigation.ts`:
```
Reports module → 5 tabs:
  ├── Daily Reports    (✅ WORKING — served by report_service.py + scheduler.py)
  ├── Pre-Billing      (❌ STUB)
  ├── Timesheets       (❌ STUB)
  ├── Labor Overview   (❌ STUB)
  └── Exports          (❌ STUB — permission: export_reports)
```

**Goal:** Replace all 4 stubs with working pages that pull real data from existing tables. No new migrations needed — all the data already exists across labor_entries, job_parts_orders, cost_layers, parts, jobs, etc.

---

## Existing Infrastructure to Build On

### Data Sources (already in DB)

| Data | Tables | Service |
|------|--------|---------|
| Clock entries | `labor_entries` (clock_in, clock_out, total_hours, gps, job_id, user_id) | `labor_service.py` |
| Bill rates | `bill_rate_types` (name, rate, multiplier) | `labor_service.py` |
| Job parts orders | `job_parts_orders`, `jpo_line_items` | `orders_service.py` |
| Purchase orders | `purchase_orders`, `po_line_items` | `orders_service.py` |
| Cost layers | `cost_layers` (FIFO/LIFO cost per part) | `cost_tracking_service.py` |
| Part costs | `parts.weighted_avg_cost`, `parts.company_sell_price` | — |
| Stock movements | `stock_movements` (from, to, qty, part_id) | `movement_service.py` |
| Job budgets | `jobs.budget_amount`, `jobs.budget_alert_threshold` | `spending_service.py` |
| Spending analytics | Via `spending_service.py` | Already computed |
| Daily reports | `daily_reports` (JSON blobs with labor + parts + questionnaire data) | `report_service.py` |
| Employees | `users` (display_name, bill_rate_type_id, hat assignments) | — |

### Existing Services to Reuse

- `report_service.py` — Already generates daily reports with labor + parts + questionnaire data
- `spending_service.py` — Already computes job cost rollups, spending by period, budget variance
- `cost_tracking_service.py` — FIFO consumption records, weighted average costs
- `labor_service.py` — Clock entries, hours calculation, bill rate resolution

---

## Backend Implementation

### File: `backend/app/routers/reports.py` (replace stubs)

Replace all 4 stub endpoints with real data endpoints. Keep the same URL paths so navigation doesn't break.

#### Endpoint 1: Pre-Billing

```
GET /api/reports/pre-billing?job_id={id}&start_date={date}&end_date={date}
```

Returns a pre-billing bundle for one or more jobs:
```json
{
  "job": { "id": 1, "name": "Smith Residence", "job_number": "J-001" },
  "period": { "start": "2026-02-01", "end": "2026-02-28" },
  "labor": {
    "entries": [
      { "employee": "Roy", "date": "2026-02-01", "hours": 8.5, "bill_rate": "Regular", "rate": 85.00, "total": 722.50 }
    ],
    "total_hours": 340.0,
    "total_cost": 28900.00
  },
  "parts": {
    "items": [
      { "part": "Outlet 15A White", "qty": 24, "unit_cost": 2.50, "sell_price": 4.50, "total_cost": 60.00, "total_sell": 108.00 }
    ],
    "total_cost": 3200.00,
    "total_sell": 5760.00
  },
  "movements": {
    "items": [
      { "date": "2026-02-03", "part": "Outlet 15A White", "from": "Warehouse A", "to": "Truck - Roy", "qty": 12 }
    ]
  },
  "summary": {
    "total_labor_cost": 28900.00,
    "total_parts_cost": 3200.00,
    "total_parts_sell": 5760.00,
    "grand_total": 34660.00,
    "budget": 40000.00,
    "variance": 5340.00
  }
}
```

**Service method:** `report_service.generate_pre_billing_bundle(job_id, start_date, end_date)`

- Queries `labor_entries` for clock records in date range for that job
- Joins with `bill_rate_types` to compute billable amounts
- Queries `po_line_items` + `jpo_line_items` for parts consumed on that job
- Queries `cost_layers` for actual part costs
- Queries `stock_movements` for movement history
- Queries `jobs` for budget info
- Computes totals, variance, margin

#### Endpoint 2: Timesheets

```
GET /api/reports/timesheets?employee_id={id}&start_date={date}&end_date={date}&group_by={day|week|pay_period}
```

Returns employee timesheet data:
```json
{
  "employee": { "id": 5, "name": "Roy", "default_bill_rate": "Regular" },
  "period": { "start": "2026-02-24", "end": "2026-03-01" },
  "entries": [
    {
      "date": "2026-02-24",
      "job": "Smith Residence",
      "clock_in": "07:00",
      "clock_out": "15:30",
      "total_hours": 8.5,
      "overtime_hours": 0.5,
      "bill_rate": "Regular",
      "gps_in": { "lat": 34.05, "lng": -118.24 },
      "gps_out": { "lat": 34.05, "lng": -118.24 }
    }
  ],
  "summary": {
    "total_hours": 42.5,
    "regular_hours": 40.0,
    "overtime_hours": 2.5,
    "total_billable": 3825.00
  }
}
```

**Service method:** `report_service.generate_timesheet(employee_id, start_date, end_date, group_by)`

- Queries `labor_entries` for the employee in date range
- Joins with `jobs` for job names
- Joins with `bill_rate_types` for rate calculation
- Groups by day/week/pay-period as requested
- Computes overtime (>8h/day or >40h/week configurable)

#### Endpoint 3: Labor Overview

```
GET /api/reports/labor-overview?start_date={date}&end_date={date}&job_id={id?}
```

Cross-job labor analytics:
```json
{
  "period": { "start": "2026-02-01", "end": "2026-02-28" },
  "by_employee": [
    { "employee": "Roy", "total_hours": 168.0, "overtime_hours": 8.0, "jobs_worked": 3, "avg_hours_per_day": 8.4 }
  ],
  "by_job": [
    { "job": "Smith Residence", "total_hours": 340.0, "employees": 4, "labor_cost": 28900.00 }
  ],
  "by_bill_rate": [
    { "rate_type": "Regular", "hours": 640.0, "cost": 54400.00 },
    { "rate_type": "Overtime", "hours": 32.0, "cost": 4080.00 }
  ],
  "totals": {
    "total_hours": 672.0,
    "total_employees": 8,
    "total_jobs": 5,
    "total_cost": 58480.00
  }
}
```

**Service method:** `report_service.generate_labor_overview(start_date, end_date, job_id=None)`

- Aggregates `labor_entries` across all employees and jobs
- Breaks down by employee, by job, by bill rate type
- Computes overtime thresholds
- Computes averages and totals

#### Endpoint 4: Exports

```
POST /api/reports/exports
Body: { "type": "pre-billing"|"timesheet"|"labor-overview", "format": "csv"|"pdf", "params": {...} }

Returns: File download (CSV or PDF)
```

**Service method:** `report_service.generate_export(export_type, format, params)`

- Calls the appropriate report generator
- Formats as CSV (simple table) or PDF (formatted report with headers/totals)
- For PDF: use `reportlab` or `weasyprint` (add to requirements.txt)
- Returns file as a streaming response

---

## Frontend Implementation

### Page 1: `PreBillingPage.tsx` (replace stub)

**Layout:**
- **Top controls:** Job selector dropdown, date range picker (start/end), "Generate" button
- **Results area:** 4 collapsible sections:
  1. **Labor Summary** — Table: Employee | Date | Hours | Bill Rate | Amount
  2. **Parts Summary** — Table: Part | Qty | Unit Cost | Sell Price | Cost Total | Sell Total
  3. **Movement History** — Table: Date | Part | From | To | Qty
  4. **Cost Summary** — Card with totals: Labor + Parts Cost + Parts Sell + Grand Total vs Budget
- **Actions:** "Export CSV" button, "Export PDF" button, "Copy Summary" button (clipboard text)

**Data flow:** `GET /api/reports/pre-billing?job_id=X&start_date=Y&end_date=Z` via TanStack Query

### Page 2: `TimesheetsPage.tsx` (replace stub)

**Layout:**
- **Top controls:** Employee selector (or "All"), date range, group-by toggle (Day / Week / Pay Period)
- **Results area:** 
  - Table: Date | Job | Clock In | Clock Out | Hours | OT Hours | Bill Rate | Billable Amount
  - Summary card at bottom: Total Hours / Regular / OT / Total Billable
- **Actions:** "Export CSV", "Export PDF"

**Data flow:** `GET /api/reports/timesheets?employee_id=X&start_date=Y&end_date=Z&group_by=day`

### Page 3: `LaborOverviewPage.tsx` (replace stub)

**Layout:**
- **Top controls:** Date range picker, optional job filter
- **Dashboard cards:** Total Hours | Total Employees | Total Jobs | Total Labor Cost
- **Three tabs:**
  1. **By Employee** — Table: Employee | Hours | OT | Jobs Worked | Avg Hours/Day
  2. **By Job** — Table: Job | Hours | Employees | Labor Cost
  3. **By Bill Rate** — Table: Rate Type | Hours | Cost
- **Actions:** "Export CSV", "Export PDF"

**Data flow:** `GET /api/reports/labor-overview?start_date=Y&end_date=Z`

### Page 4: `ExportsPage.tsx` (replace stub)

**Layout:**
- **Report type selector:** Pre-Billing / Timesheet / Labor Overview
- **Parameters form:** Dynamic based on report type (job, employee, dates, format)
- **Format selector:** CSV / PDF
- **"Generate & Download" button**
- **Recent exports list:** Shows last 10 exports with re-download links

**Data flow:** `POST /api/reports/exports` → file download

---

## API Client

### File: `frontend/src/api/reports.ts` (new or update existing)

```typescript
// Pre-billing
export function getPreBilling(params: { jobId: number; startDate: string; endDate: string }) 
export function getPreBillingExport(params: { jobId: number; startDate: string; endDate: string; format: 'csv' | 'pdf' })

// Timesheets
export function getTimesheets(params: { employeeId?: number; startDate: string; endDate: string; groupBy: 'day' | 'week' | 'pay_period' })
export function getTimesheetExport(params: { employeeId?: number; startDate: string; endDate: string; format: 'csv' | 'pdf' })

// Labor Overview
export function getLaborOverview(params: { startDate: string; endDate: string; jobId?: number })
export function getLaborOverviewExport(params: { startDate: string; endDate: string; format: 'csv' | 'pdf' })

// General export
export function generateExport(params: { type: string; format: string; params: Record<string, any> })
```

---

## Dependencies to Add

`backend/requirements.txt`:
```
# PDF generation (for export reports)
reportlab>=4.0.0
```

No new database migrations needed — all data already exists.

---

## NEW: Period Locking

**Why:** Once a billing period is finalized and sent to the bookkeeper/GC, nobody should be able to modify clock entries, add parts, or change costs for that period. This prevents accidental post-submission changes that break the numbers.

### Backend

#### Migration (new — `028_period_locking.sql`)

```sql
CREATE TABLE IF NOT EXISTS billing_periods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER REFERENCES jobs(id),        -- NULL = company-wide lock
    period_start TEXT NOT NULL,                 -- ISO date
    period_end TEXT NOT NULL,                   -- ISO date
    locked_at TEXT,                             -- NULL = open, timestamp = locked
    locked_by INTEGER REFERENCES users(id),
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_periods_job_range
    ON billing_periods(job_id, period_start, period_end);
```

#### Endpoints

```
GET    /api/reports/billing-periods?job_id={id?}           — List periods (open + locked)
POST   /api/reports/billing-periods                         — Create a new period
PATCH  /api/reports/billing-periods/{id}/lock               — Lock a period (sets locked_at)
PATCH  /api/reports/billing-periods/{id}/unlock             — Unlock (admin only, audit logged)
```

#### Enforcement

- Before creating/updating a `labor_entry`, check if the clock_in date falls within a locked period for that job → reject with 409 Conflict
- Before creating stock movements to a job, check if movement date falls in locked period → reject
- Pre-billing "Generate" button auto-creates an open period for the selected range if none exists
- Locking a period triggers a snapshot: store the pre-billing bundle JSON as `billing_period_snapshots.data`
- Permission: `lock_billing_periods` (default: office + admin)

### Frontend

- **Period indicator** on Pre-Billing page: banner showing "Period: Feb 1–28 — OPEN" or "LOCKED 🔒"
- **Lock/Unlock buttons** on Pre-Billing page (gated by permission)
- **Period selector** added to Pre-Billing top controls (dropdown of existing periods + "Custom Range")
- **Visual lock indicators** on Timesheets page — locked dates show 🔒 icon, rows are non-editable

---

## NEW: Bookkeeper Export Format

**Why:** The bookkeeper needs structured data they can import into QuickBooks, Xero, or similar. Raw CSV isn't enough — it needs specific column headers, account codes, and formatting conventions.

### Export Formats

#### 1. QuickBooks-Compatible CSV (IIF-style)

For labor billing:
```
!TRNS,TRNSID,TRNSTYPE,DATE,ACCNT,NAME,CLASS,AMOUNT,MEMO
!SPL,SPLID,TRNSTYPE,DATE,ACCNT,NAME,CLASS,AMOUNT,MEMO
!ENDTRNS
TRNS,,INVOICE,02/28/2026,Accounts Receivable,Smith Residence,Labor,28900.00,Labor Feb 2026
SPL,,INVOICE,02/28/2026,Labor Revenue,Smith Residence,Labor,-28900.00,
ENDTRNS
```

For parts billing:
```
TRNS,,INVOICE,02/28/2026,Accounts Receivable,Smith Residence,Parts,5760.00,Parts Feb 2026
SPL,,INVOICE,02/28/2026,Parts Revenue,Smith Residence,Parts,-5760.00,
ENDTRNS
```

#### 2. General Ledger CSV

Simple flat format for any accounting system:
```csv
Date,Job,Category,Description,Debit,Credit,Account
2026-02-28,J-001 Smith Residence,Labor,Feb 2026 labor (340.0 hrs),28900.00,,Accounts Receivable
2026-02-28,J-001 Smith Residence,Labor,Feb 2026 labor (340.0 hrs),,28900.00,Labor Revenue
2026-02-28,J-001 Smith Residence,Parts,Feb 2026 parts (24 items),5760.00,,Accounts Receivable
2026-02-28,J-001 Smith Residence,Parts,Feb 2026 parts (24 items),,5760.00,Parts Revenue
```

#### 3. Payroll CSV

For submitting to ADP, Gusto, etc.:
```csv
Employee ID,Employee Name,Period Start,Period End,Regular Hours,Overtime Hours,Total Hours,Pay Rate,Gross Pay
5,Roy,2026-02-24,2026-03-01,40.0,2.5,42.5,25.00,1062.50
```

### Backend

#### Endpoints

```
POST /api/reports/exports/bookkeeper
Body: {
  "format": "quickbooks" | "general_ledger" | "payroll",
  "job_ids": [1, 2, 3],          // or null for all jobs
  "period_start": "2026-02-01",
  "period_end": "2026-02-28",
  "include_labor": true,
  "include_parts": true
}
Returns: File download
```

#### Configuration (future — hardcode defaults for V1.0)

Account names and codes should eventually be configurable per company. For V1.0, use sensible defaults:
- Accounts Receivable, Labor Revenue, Parts Revenue, COGS-Labor, COGS-Parts

### Frontend

- **Bookkeeper Export tab** added to Exports page (or a section within it)
- **Format selector:** QuickBooks / General Ledger / Payroll
- **Job multi-select:** Pick specific jobs or "All"
- **Date range picker**
- **Checkboxes:** Include labor? Include parts?
- **"Generate & Download" button**

---

## NEW: Profitability Analysis

**Why:** The owner needs to see which jobs are profitable, which are bleeding money, and overall company margin. This goes beyond raw cost tracking — it compares billed amounts against actual costs.

### Backend

#### Endpoints

```
GET /api/reports/profitability?start_date={date}&end_date={date}&job_id={id?}
```

Returns:
```json
{
  "period": { "start": "2026-02-01", "end": "2026-02-28" },
  "by_job": [
    {
      "job_id": 1,
      "job_name": "Smith Residence",
      "job_number": "J-001",
      "status": "active",
      "labor_cost": 12000.00,
      "labor_billed": 28900.00,
      "parts_cost": 3200.00,
      "parts_billed": 5760.00,
      "total_cost": 15200.00,
      "total_billed": 34660.00,
      "profit": 19460.00,
      "margin_pct": 56.15,
      "budget": 40000.00,
      "budget_remaining": 5340.00,
      "budget_utilization_pct": 86.65
    }
  ],
  "company_totals": {
    "total_cost": 58480.00,
    "total_billed": 112500.00,
    "total_profit": 54020.00,
    "avg_margin_pct": 48.02,
    "jobs_profitable": 4,
    "jobs_at_risk": 1,
    "jobs_over_budget": 0
  }
}
```

**Notes on "billed" amounts:**
- Labor billed = hours × bill rate (from `bill_rate_types`)
- Parts billed = qty × `company_sell_price`
- Labor cost = hours × employee wage (from `employee_wages` or hourly rate)
- Parts cost = qty × weighted average cost (from `cost_layers` or `parts.weighted_avg_cost`)

#### Service method: `report_service.generate_profitability(start_date, end_date, job_id=None)`

- Aggregates labor_entries by job, computes cost vs billed
- Aggregates parts consumption by job, computes cost vs sell price
- Computes margin per job and company-wide
- Flags "at risk" jobs (margin < 20%) and "over budget" jobs

### Frontend: `ProfitabilityPage.tsx` (new page)

**Layout:**
- **Top controls:** Date range picker, optional job filter
- **Summary cards:** Total Billed | Total Cost | Total Profit | Avg Margin %
- **Job profitability table:** Job | Status | Labor Cost | Parts Cost | Total Cost | Total Billed | Profit | Margin % | Budget Used %
  - Color-coded: green (margin > 30%), yellow (15-30%), red (< 15%)
  - Sortable by any column
  - Click row to drill down to Pre-Billing for that job
- **Charts (stretch goal):** Bar chart of profit by job, pie chart of cost breakdown

**Navigation update:** Add "Profitability" tab to Reports module (6 tabs total):
```
Reports module → 6 tabs:
  ├── Daily Reports    (✅ WORKING)
  ├── Pre-Billing      (building)
  ├── Timesheets       (building)
  ├── Labor Overview   (building)
  ├── Profitability    (NEW)
  └── Exports          (building — now includes bookkeeper formats)
```

**Permission:** `view_reports` gates Profitability (same as other report pages)

---

## Success Criteria

- [x] Pre-Billing page shows real labor hours + parts cost data for a selected job and date range
- [x] Timesheets page shows clock entries grouped by day with overtime calculation
- [x] Labor Overview page shows cross-job analytics with employee, job, and bill rate breakdowns
- [x] Exports page generates downloadable CSV files (PDF deferred)
- [x] Profitability page shows labor cost + parts margin per job with budget tracking
- [x] Period locking — create/lock/unlock billing periods, enforcement helper, visual indicators
- [x] Bookkeeper exports — QuickBooks IIF, General Ledger CSV, Payroll CSV
- [x] All 6 pages are responsive at desktop, tablet, and mobile breakpoints
- [x] Dark mode works correctly on all 6 pages
- [x] `view_reports` permission gates Pre-Billing, Timesheets, Labor Overview, Profitability
- [x] `export_reports` permission gates the Exports tab

NOTE: Labor reports show HOURS ONLY — the bookkeeper handles actual bill-out rates externally.
- [x] `lock_billing_periods` permission gates period locking
- [ ] Reports load within 2 seconds for typical data volumes (50 employees, 200 jobs) — needs production testing
- [ ] Export PDFs include company header, date range, and formatted tables — deferred, CSV sufficient for V1.0
- [x] Locked periods show visual indicators and reject modifications

---

## Execution Order

1. Backend: Migration `028_period_locking.sql` for billing_periods table
2. Backend: Replace stub endpoints in `reports.py` with real query logic (reuse existing services)
3. Backend: Add period locking endpoints and enforcement middleware
4. Backend: Add profitability endpoint
5. Backend: Add bookkeeper export formats (QuickBooks, GL, Payroll CSVs)
6. Backend: Add PDF export generation (reportlab)
7. Frontend: Build `PreBillingPage.tsx` — most complex page, tests the data pipeline
8. Frontend: Build `TimesheetsPage.tsx` — uses same labor_entries data
9. Frontend: Build `LaborOverviewPage.tsx` — cross-job aggregation
10. Frontend: Build `ProfitabilityPage.tsx` — new page, margin analysis
11. Frontend: Build `ExportsPage.tsx` — wraps export + bookkeeper export API calls
12. Frontend: Wire period locking UI (lock/unlock buttons, visual indicators)
13. Test all 6 pages with real data at all breakpoints
