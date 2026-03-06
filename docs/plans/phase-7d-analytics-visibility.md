# Phase 7D: Analytics & Visibility — Detailed Implementation Plan

> **Date:** 2026-03-04
> **Prerequisites:** Phase 7A (Core Ordering) ✅, Phase 7B (Office Workflow) ✅, Phase 7C (Warehouse Workflow) ✅
> **Master plan:** `docs/plans/orders-redesign-master-plan.md`

---

## Goal

Implement **weighted average cost tracking** (FIFO consumption, LIFO returns), **margin management**, a **spending dashboard**, **job cost rollup with budget alerts**, and the **live daily report tab** on the Dashboard.

---

## What Already Exists (Codebase Audit)

| Item | Current State | Location |
|------|--------------|----------|
| Part pricing fields | `company_cost_price`, `company_markup_percent`, `company_sell_price` (generated) | `002_parts_and_inventory.sql` |
| Cost snapshots | `unit_cost_at_move`, `unit_sell_at_move` on stock_movements | `002_parts_and_inventory.sql` |
| Job cost snapshots | `unit_cost_at_consume`, `unit_sell_at_consume` on job_parts | `009_jobs_and_labor.sql` |
| Job response type | `total_parts_cost`, `total_labor_hours` already in `JobResponse` | `types.ts:1478-1479` |
| Permissions | `SHOW_DOLLAR_VALUES`, `EDIT_PRICING`, `VIEW_REPORTS` | `constants.ts:13-14,50` |
| PricingPage | Full inline pricing editor with permission gates | `parts/pages/PricingPage.tsx` |
| Dashboard | 4 KPI cards + FastDrive + Quick Actions | `dashboard/pages/DashboardPage.tsx` |
| Job detail | 5 sub-tabs (notebook, overview, labor, parts, questions) | `jobs/pages/JobDetailPage.tsx` |
| Office module | 5 tabs (warehouse-exec, manage-jobs, templates, clock-out, locations) | `navigation.ts:39-49` |
| Orders office tabs | approvals, all-requests, review-and-send, purchase-orders, procurement | `navigation.ts:117-122` |
| Reports module | daily-reports, pre-billing, timesheets, labor-overview, exports | `navigation.ts:138-148` |
| Report service | Daily report generation (locked daily snapshots) | `report_service.py` |
| Costs router | **Does not exist yet** | — |
| 13 routers registered | auth, settings, dashboard, parts, companions, warehouse, trucks, jobs, notebooks, orders, notifications, people, reports | `main.py:133-147` |

---

## Implementation Steps

### Step 1: Migration 021 (Database Schema)

**File:** `backend/app/migrations/021_orders_redesign_d.sql`

```sql
-- ═══════════════════════════════════════════════════
-- Phase 7D: Analytics & Visibility
-- ═══════════════════════════════════════════════════

-- Cost layers for FIFO/LIFO tracking
CREATE TABLE IF NOT EXISTS cost_layers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    purchase_date TEXT NOT NULL,
    po_line_id INTEGER REFERENCES po_line_items(id),
    original_qty INTEGER NOT NULL,
    remaining_qty INTEGER NOT NULL,
    unit_cost REAL NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    CHECK(remaining_qty >= 0)
);

CREATE INDEX IF NOT EXISTS idx_cost_layers_part ON cost_layers(part_id, remaining_qty);
CREATE INDEX IF NOT EXISTS idx_cost_layers_date ON cost_layers(part_id, purchase_date);

-- Company-wide cost settings
CREATE TABLE IF NOT EXISTS company_cost_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setting_key TEXT UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    updated_by INTEGER REFERENCES users(id),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Seed default settings
INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
VALUES
    ('default_margin_percent', '25'),
    ('cost_method', 'weighted_average'),
    ('auto_update_pricing', 'true');

-- Parts table extensions
ALTER TABLE parts ADD COLUMN weighted_avg_cost REAL DEFAULT 0;
ALTER TABLE parts ADD COLUMN custom_margin_percent REAL;
ALTER TABLE parts ADD COLUMN cost_last_updated TEXT;

-- Jobs table extensions
ALTER TABLE jobs ADD COLUMN budget_limit REAL;
ALTER TABLE jobs ADD COLUMN budget_alert_percent REAL DEFAULT 80;
```

**Notes:**
- SQLite `ALTER TABLE ADD COLUMN` has no `IF NOT EXISTS` — migration runner uses try/catch for "duplicate column" errors
- `company_cost_settings` uses `INSERT OR IGNORE` for safe re-runs
- `cost_layers.remaining_qty` has a CHECK constraint to prevent negative inventory costing

---

### Step 2: Backend — Cost Tracking Service

**File:** `backend/app/services/cost_tracking_service.py` (NEW)

**Methods:**

| Method | Purpose | Details |
|--------|---------|---------|
| `add_cost_layer(part_id, qty, unit_cost, po_line_id?)` | On receive: add new cost layer | Creates layer, recalculates weighted avg |
| `consume_fifo(part_id, qty)` | On job consumption: remove oldest layers first | Returns total cost consumed |
| `return_lifo(part_id, qty, unit_cost?)` | On warehouse return: add back newest layer | If unit_cost provided, uses that; else uses last consumed cost |
| `recalculate_weighted_average(part_id)` | Recompute from remaining layers | `sum(remaining_qty * unit_cost) / sum(remaining_qty)` |
| `get_cost_layers(part_id)` | All layers with remaining_qty > 0 | For audit view |
| `get_cost_history(part_id, days?)` | Cost changes over time | For sparkline chart |
| `get_margin(part_id)` | Custom margin or company default | Reads company_cost_settings if no custom |
| `set_custom_margin(part_id, percent)` | Override margin per part | Updates parts.custom_margin_percent |
| `clear_custom_margin(part_id)` | Reset to company default | Sets custom_margin_percent = NULL |
| `enforce_default_margin()` | Reset ALL parts to company default | Bulk update, sets all custom_margin_percent = NULL |
| `get_company_settings()` | Read company cost settings | Returns dict of settings |
| `update_company_setting(key, value, user_id)` | Update a setting | For admin config |

**Integration points:**
- `receiving_service.commit_session()` → calls `add_cost_layer()` for each received line
- Existing `movement_service` (job consumption) → calls `consume_fifo()`
- `returns_service.process_sorted_return()` → calls `return_lifo()` for "restock" dispositions

**Important:** We need to hook into the existing receiving flow. Currently `receiving_service.commit_session()` calls the legacy `receive_po_items()`. After receiving, we add cost layers.

---

### Step 3: Backend — Spending Service

**File:** `backend/app/services/spending_service.py` (NEW)

**Methods:**

| Method | Purpose | Details |
|--------|---------|---------|
| `get_spending_summary(date_from, date_to)` | Top-level KPIs: total spend, order count, avg order size | For dashboard cards |
| `get_spending_by_supplier(date_from, date_to)` | Spend per supplier | For pie chart |
| `get_spending_by_category(date_from, date_to)` | Spend per part category | For bar chart |
| `get_spending_by_job(date_from, date_to)` | Spend per job | For breakdown |
| `get_spending_trend(date_from, date_to, group_by)` | Monthly/weekly trend | For line chart. group_by: 'month', 'week' |
| `get_job_cost_rollup(job_id)` | Total parts cost for a job | Sum of PO line costs via JPOs |
| `get_price_variance_report(date_from, date_to)` | Received vs quoted price diffs | Amber >5%, red >15% |
| `check_budget_alerts()` | Jobs approaching budget limits | Returns list of alerts |

**Data sources:**
- `po_line_items` (unit_cost, qty) joined through `purchase_orders` (supplier_id, created_at)
- `job_parts_orders` → `po_line_items` for per-job cost attribution
- `cost_layers` for actual received costs vs quoted

---

### Step 4: Backend — Costs Router

**File:** `backend/app/routers/costs.py` (NEW)

**Endpoints:**

| Method | Path | Purpose | Permission |
|--------|------|---------|------------|
| `GET` | `/api/costs/settings` | Company cost settings | `show_dollar_values` |
| `PUT` | `/api/costs/settings/{key}` | Update company setting | `edit_pricing` |
| `GET` | `/api/costs/part/{part_id}/layers` | Cost layers for audit | `show_dollar_values` |
| `GET` | `/api/costs/part/{part_id}/history` | Cost trend (sparkline data) | `show_dollar_values` |
| `PUT` | `/api/costs/part/{part_id}/margin` | Set custom margin | `edit_pricing` |
| `DELETE` | `/api/costs/part/{part_id}/margin` | Clear custom margin | `edit_pricing` |
| `POST` | `/api/costs/enforce-default-margin` | Reset all margins | `edit_pricing` |
| `GET` | `/api/costs/dashboard` | Spending dashboard data | `manage_orders` |
| `GET` | `/api/costs/spending/by-supplier` | Supplier spend breakdown | `manage_orders` |
| `GET` | `/api/costs/spending/by-category` | Category spend breakdown | `manage_orders` |
| `GET` | `/api/costs/spending/by-job` | Job spend breakdown | `manage_orders` |
| `GET` | `/api/costs/spending/trend` | Spending trend line | `manage_orders` |
| `GET` | `/api/costs/job/{job_id}/rollup` | Job cost rollup | `show_dollar_values` |
| `GET` | `/api/costs/job/{job_id}/budget-status` | Budget vs actual | `show_dollar_values` |
| `GET` | `/api/costs/variance-report` | Price variance report | `manage_orders` |

**Registration:** Add `app.include_router(costs.router, prefix="/api/costs", tags=["costs"])` to `main.py`

---

### Step 5: Backend — Pydantic Models

**File:** `backend/app/models/costs.py` (NEW)

**Models needed:**

```
CostLayerResponse       — id, part_id, purchase_date, po_line_id, original_qty, remaining_qty, unit_cost
CostHistoryPoint        — date, weighted_avg_cost, total_qty
MarginUpdate            — margin_percent (float)
CompanySettingResponse   — setting_key, setting_value, updated_by, updated_at
CompanySettingUpdate     — setting_value (str)
SpendingSummary          — total_spend, order_count, avg_order_size, period
SupplierSpend           — supplier_id, supplier_name, total_spend, order_count, pct_of_total
CategorySpend           — category_id, category_name, total_spend, item_count
JobSpend                — job_id, job_name, total_spend, budget_limit?, budget_pct?
SpendingTrendPoint      — period_label, total_spend, order_count
JobCostRollup           — job_id, job_name, total_parts_cost, total_labor_cost, budget_limit?, budget_remaining?, budget_pct?
BudgetAlert             — job_id, job_name, budget_limit, current_spend, pct_used, alert_level ('warning' | 'danger')
PriceVarianceItem       — part_id, part_name, supplier_name, quoted_price, actual_price, variance_pct, variance_level ('ok' | 'warning' | 'danger')
```

---

### Step 6: Frontend — Types & API Layer

**Files:**
- `frontend/src/lib/types.ts` — Add Phase 7D TypeScript interfaces (mirrors Pydantic models above)
- `frontend/src/api/costs.ts` (NEW) — All cost/spending API functions

**API functions in `costs.ts`:**

```typescript
// Cost settings
getCompanySettings()
updateCompanySetting(key, value)

// Per-part cost & margin
getCostLayers(partId)
getCostHistory(partId, days?)
setPartMargin(partId, percent)
clearPartMargin(partId)
enforceDefaultMargin()

// Spending dashboard
getSpendingDashboard(dateFrom, dateTo)
getSpendingBySupplier(dateFrom, dateTo)
getSpendingByCategory(dateFrom, dateTo)
getSpendingByJob(dateFrom, dateTo)
getSpendingTrend(dateFrom, dateTo, groupBy)

// Job cost
getJobCostRollup(jobId)
getJobBudgetStatus(jobId)

// Reports
getPriceVarianceReport(dateFrom, dateTo)
```

---

### Step 7: Frontend — Part Cost Section (PricingPage Enhancement)

**File:** `frontend/src/features/parts/pages/PricingPage.tsx` (MODIFY)

**Changes:**
- Add a **cost details expandable row** to each part in the pricing table
- When expanded, show:
  - Current weighted average cost
  - Cost trend sparkline (last 90 days)
  - Active cost layers (collapsible)
  - Margin setting: "Company Default (25%)" or custom override
  - Calculated sell price based on margin
- "Enforce Default Margin" button at page top (with confirmation modal)
- Permission gated: `show_dollar_values` to view, `edit_pricing` to modify margins

**Note:** The master plan mentions "Part detail page" but we don't have one. The PricingPage is the natural home since it already has permission gates and inline editing patterns.

---

### Step 8: Frontend — Spending Dashboard

**File:** `frontend/src/features/orders/pages/SpendingDashboardPage.tsx` (NEW)

**Location:** New tab in Orders module's Office group: `{ id: 'spending', label: 'Spending', path: '/orders/spending', permission: 'manage_orders', group: 'Office' }`

**Layout:**
1. **Date range picker** (preset: This Month, Last Month, This Quarter, Last Quarter, YTD, Custom)
2. **Summary cards** row: Total Spend, Order Count, Avg Order Size, Active Suppliers
3. **Charts section** (2-column on desktop, stacked on mobile):
   - Spending trend (line chart — simple CSS-based, no charting library needed)
   - Supplier breakdown (horizontal bar chart)
   - Category breakdown (horizontal bar chart)
4. **Price variance highlights** — table with amber/red badges for >5%/>15% variance
5. **"Enforce Default Margin"** button (bottom, with confirmation modal)

**Chart implementation:** Use simple CSS bar charts (div widths proportional to max value) — no external charting library. This matches the app's lightweight approach.

---

### Step 9: Frontend — Job Cost Rollup Tab

**File:** `frontend/src/features/jobs/pages/JobDetailPage.tsx` (MODIFY)

**Changes:**
- Add new sub-tab: `{ id: 'costs', label: 'Costs', icon: <DollarSign /> }`
- **CostsTab content:**
  - Summary cards: Total Parts Cost, Total Labor Cost, Combined Total
  - Budget progress bar (if `budget_limit` set):
    - Green: 0-70%
    - Amber: 70-90%
    - Red: 90%+
    - "No budget set" message with "Set Budget" button if null
  - "Set Budget" inline form (budget_limit input + budget_alert_percent input)
  - Parts cost breakdown table (from job_parts_orders → PO lines)
  - Labor cost estimate (total_labor_hours × billing_rate)
- Permission gated: `show_dollar_values` required to see the tab at all

---

### Step 10: Frontend — Daily Report Tab on Dashboard

**File:** `frontend/src/features/dashboard/components/DailyReportTab.tsx` (NEW)
**File:** `frontend/src/features/dashboard/pages/DashboardPage.tsx` (MODIFY)

**Changes to DashboardPage:**
- Add internal tab bar at top: "Overview" (current content) | "Daily Report"
- Default to Overview

**DailyReportTab content:**
- **Live data** (not the locked daily report — this is real-time)
- Sections:
  1. **Pending Actions**: JPOs awaiting approval, POs to submit, Returns to sort (with counts + links)
  2. **Expected Deliveries**: POs with expected delivery this week (date, supplier, line count)
  3. **Overdue Items**: POs past expected delivery with no receipt (red highlights)
  4. **Today's Activity**: Orders created, items received, returns processed (count summary)
  5. **Budget Alerts**: Jobs approaching budget limits (from `check_budget_alerts()`)
- Each section is a collapsible card
- Quick action buttons: "Go to Approvals", "Go to Receiving", etc.

**Backend endpoint:** `GET /api/dashboard/daily-report` — new endpoint in dashboard router that aggregates live data

---

### Step 11: Navigation & Route Updates

**Files:**
- `frontend/src/lib/navigation.ts` — Add spending tab to Orders Office group
- `frontend/src/App.tsx` — Add routes for SpendingDashboardPage

**Navigation change:**
```typescript
// In orders module tabs, after 'procurement':
{ id: 'spending', label: 'Spending', path: '/orders/spending', permission: 'manage_orders', group: 'Office' },
```

**Route addition:**
```tsx
<Route path="/orders/spending" element={<SpendingDashboardPage />} />
```

---

### Step 12: Integration Hooks

These are the critical integration points where Phase 7D hooks into existing code:

1. **Receiving flow** (`receiving_service.commit_session()`):
   - After creating stock movements, call `cost_tracking_service.add_cost_layer()` for each received line
   - Then call `cost_tracking_service.recalculate_weighted_average()` for affected parts

2. **Return sorting** (`returns_service.process_sorted_return()`):
   - For "restock" dispositions, call `cost_tracking_service.return_lifo()` for each restocked line
   - Then recalculate weighted average

3. **Job part consumption** (existing `movement_service` or `job_parts` flow):
   - When parts are consumed on a job, call `cost_tracking_service.consume_fifo()`
   - This will need investigation to find the exact hook point

**Note:** Integration hook #3 needs careful exploration of the existing stock movement flow. The consume_fifo call should happen when a "job_consume" type stock movement is created.

---

## Execution Order

| # | Task | Type | Est. Lines | Dependencies |
|---|------|------|-----------|--------------|
| 1 | Migration 021 | DB | ~40 | None |
| 2 | Pydantic models (`models/costs.py`) | Backend | ~100 | Migration |
| 3 | Cost tracking service | Backend | ~250 | Migration, Models |
| 4 | Spending service | Backend | ~200 | Migration, Models |
| 5 | Costs router + register in main.py | Backend | ~200 | Services, Models |
| 6 | Dashboard daily-report endpoint | Backend | ~80 | Existing services |
| 7 | Frontend types + API layer (`costs.ts`) | Frontend | ~150 | Router endpoints |
| 8 | SpendingDashboardPage | Frontend | ~450 | API layer |
| 9 | PricingPage cost expansion | Frontend | ~200 | API layer |
| 10 | Job detail costs tab | Frontend | ~250 | API layer |
| 11 | Dashboard daily report tab | Frontend | ~350 | API + daily-report endpoint |
| 12 | Navigation + route wiring | Frontend | ~20 | Pages |
| 13 | Integration hooks (receiving, returns, consumption) | Backend | ~60 | Cost tracking service |
| 14 | Responsive audit + fixes | Frontend | ~30 | All pages |

**Total estimated:** ~2,380 lines of new/modified code

---

## Verification Checklist (from master plan)

1. [ ] Receive 10 units at $100, then 5 at $80 → verify weighted avg = $93.33
2. [ ] Consume 1 unit (FIFO) → verify oldest layer decremented, avg recalculated
3. [ ] Return 1 unit (LIFO) → verify newest layer incremented, avg recalculated
4. [ ] Set custom margin on a part → verify sell price updates
5. [ ] Click "Enforce Default" → verify all custom margins cleared
6. [ ] Check job cost rollup → verify matches sum of PO costs
7. [ ] Set job budget → approach limit → verify amber/red warning
8. [ ] Verify field workers can see job costs but NOT company-wide spending
9. [ ] Daily report tab → verify live data, pending actions, deliveries
10. [ ] Full responsive + dark mode audit at 375×812, 768×1024, 1280×800

---

## Risks & Open Questions

1. **Integration hook #3 (job consumption):** Need to trace the existing stock movement flow to find where "job_consume" movements are created. This determines where `consume_fifo()` gets called.

2. **Charting approach:** The plan uses CSS-based bar/line charts (proportional divs). If the user wants richer interactivity (tooltips, hover, animations), we could add a lightweight library like `recharts` (~50KB). But the CSS approach is consistent with the app's no-external-deps style.

3. **Historical data:** When Phase 7D launches, there will be no cost layers for previously received parts. The `weighted_avg_cost` will default to 0 for existing parts. We should consider seeding from `company_cost_price` as a one-time migration step.

4. **Performance:** Spending queries aggregate across `po_line_items` × `purchase_orders` × `suppliers`. For large datasets, we may need to add materialized summary tables. For now, SQLite with proper indexes should handle the expected volume.

---

## Files Summary

### New Files (~8)
- `backend/app/migrations/021_orders_redesign_d.sql`
- `backend/app/models/costs.py`
- `backend/app/services/cost_tracking_service.py`
- `backend/app/services/spending_service.py`
- `backend/app/routers/costs.py`
- `frontend/src/api/costs.ts`
- `frontend/src/features/orders/pages/SpendingDashboardPage.tsx`
- `frontend/src/features/dashboard/components/DailyReportTab.tsx`

### Modified Files (~8)
- `backend/app/main.py` — Register costs router
- `backend/app/services/receiving_service.py` — Add cost layer hook
- `backend/app/services/returns_service.py` — Add return LIFO hook
- `backend/app/routers/dashboard.py` — Add daily-report endpoint
- `frontend/src/lib/types.ts` — Phase 7D types
- `frontend/src/lib/navigation.ts` — Spending tab
- `frontend/src/features/parts/pages/PricingPage.tsx` — Cost expansion
- `frontend/src/features/jobs/pages/JobDetailPage.tsx` — Costs sub-tab
- `frontend/src/features/dashboard/pages/DashboardPage.tsx` — Daily report tab
- `frontend/src/App.tsx` — Spending route
