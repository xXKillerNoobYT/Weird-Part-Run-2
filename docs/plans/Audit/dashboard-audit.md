# Dashboard Audit

> **Date:** 2026-03-06
> **Status:** 📋 Audit complete
> **Scope:** Full audit of the Dashboard module — KPIs, Fast Drive, Daily Report tab, cert alerts

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router: `backend/app/routers/dashboard.py` (~341 lines)

Mounted in `main.py` as `app.routers.dashboard`.

| # | Method | Path | Description | Status |
|---|--------|------|-------------|--------|
| 1 | `GET` | `/api/dashboard` | KPI counts + quick actions + user context | ✅ Functional |
| 2 | `GET` | `/api/dashboard/fast-drive` | Fast Drive destination list (vehicle, top 3 destinations, all active jobs) | ✅ Functional |
| 3 | `POST` | `/api/dashboard/fast-drive/start` | Log a trip leg from Fast Drive | ✅ Functional |
| 4 | `GET` | `/api/dashboard/cert-alerts` | Certifications expiring within N days | ✅ Functional |

**Total endpoints: 4**

#### Endpoint Details

**GET `/api/dashboard`** — Live KPI counts via direct SQL queries:
- `total_parts` — count of active parts
- `active_jobs` — count of jobs with status `active` or `in_progress`
- `pending_orders` — count of purchase orders with status `pending`
- `low_stock_alerts` — parts where warehouse stock < `min_stock_level`
- Returns `quick_actions` array (hardcoded: New Job, Create PO, Stock Check, Pull Parts)
- Returns `user_name` from auth context

**GET `/api/dashboard/fast-drive`** — Builds fast-drive context for the current user:
- Looks up active vehicle assignment → vehicle info
- Builds destination list: Home (if take-home), primary shop, all active jobs
- Ranks by 30-day trip frequency from `vehicle_trip_legs` table
- Returns `suggested` (top 3) + `all_destinations`

**POST `/api/dashboard/fast-drive/start`** — Logs a trip leg:
- Creates or reuses today's mileage log via `MileageService`
- Adds a single trip leg to the log
- Request body: `leg_type`, `from_label`, `to_label`, `estimated_miles`, `to_job_id`, `from_job_id`

**GET `/api/dashboard/cert-alerts`** — Cert expiry alerts:
- Delegates to `PeopleService.get_cert_alerts(days=N)`
- Default look-ahead: 60 days
- Permission-gated: requires `view_people`

### Backend Models

- `FastDriveStartRequest` — Pydantic model for trip leg logging (defined inline in router)

### Service Dependencies

- `MileageService` — for trip leg logging
- `PeopleService` — for cert alerts
- No dedicated `DashboardService` — all KPI queries are inline SQL in the router

### API Client: `frontend/src/api/dashboard.ts` (~52 lines)

| Function | Endpoint | Returns |
|----------|----------|---------|
| `getDashboard()` | `GET /dashboard` | `DashboardData` |
| `getFastDriveContext()` | `GET /dashboard/fast-drive` | `FastDriveContext` |
| `startDrive(req)` | `POST /dashboard/fast-drive/start` | `FastDriveResult` |
| `getCertAlerts()` | `GET /dashboard/cert-alerts` | `CertAlertItem[]` |

---

## 2. Frontend Inventory

### Directory: `frontend/src/features/dashboard/`

| File | Lines | Type | Status |
|------|-------|------|--------|
| `pages/DashboardPage.tsx` | ~230 | Main page | ✅ Functional |
| `components/FastDriveCard.tsx` | ~307 | Fast Drive widget | ✅ Functional |
| `components/DailyReportTab.tsx` | ~335 | Live daily report tab | ✅ Functional |

**Total: 3 files, ~872 lines**

### Navigation Config (`frontend/src/lib/navigation.ts`)

```typescript
{
  id: 'dashboard',
  label: 'Dashboard',
  icon: 'LayoutDashboard',
  path: '/dashboard',
  tabs: [],  // No sub-tabs — dashboard is a single page
}
```

No permission required — visible to all authenticated users.

### Route Registration (`App.tsx`)

```
/                → Redirect to /dashboard
/dashboard       → DashboardPage
```

### Page: DashboardPage

Two-tab layout (Overview | Daily Report):

**Overview Tab** (always visible):
1. **Welcome Card** — shows user's display name
2. **Fast Drive Card** — vehicle assignment + destination list (see component below)
3. **KPI Grid** — 2×2 (mobile) or 4-column (desktop) grid:
   - Total Parts (blue)
   - Active Jobs (green)
   - Pending Orders (amber)
   - Low Stock Alerts (red)
4. **Cert Expiry Alerts** — shows up to 5 certifications expiring soon (permission-gated: `view_people`), each clickable → navigates to employee detail
5. **Quick Actions** — 2×2 (mobile) or 4-column (desktop) grid of shortcut buttons:
   - New Job → `/jobs/active`
   - Create PO → `/orders/purchase-orders/new`
   - Stock Check → `/warehouse/inventory`
   - Pull Parts → `/warehouse/staging`

**Daily Report Tab** (permission-gated: `show_dollar_values`):
- Auto-refreshes every 60 seconds
- Sections: Overdue Alert Banner, Pending Actions, Today's Activity, Expected Deliveries, Overdue Items, Budget Alerts
- Data comes from `GET /api/costs/daily-report` (costs router, not dashboard)

### Component: FastDriveCard

- Queries `GET /api/dashboard/fast-drive` for vehicle + destinations
- Shows "No vehicle assigned" message if no assignment
- Shows vehicle name/number header
- Suggested destinations (top 3 by frequency) with two actions each:
  - **GPS & Log** — logs trip AND opens Google Maps (Android) or Apple Maps (iOS)
  - **Just Log** — logs trip only
- Expandable "All Destinations" section for full list
- Success badge on recent logs (auto-clears after 5s)
- Handles Home, Shop, and Job destination types with appropriate icons

### Component: DailyReportTab

- Fetches from `GET /api/costs/daily-report` (not the dashboard router)
- Shows: Pending Actions (JPOs awaiting approval, POs to submit, returns to sort, overdue deliveries), Today's Activity (orders created, items received, returns processed), Expected Deliveries this week, Overdue Deliveries, Budget Alerts
- Live refresh indicator at bottom

---

## 3. Feature Completeness

| Feature | Status | Notes |
|---------|--------|-------|
| KPI cards (4 metrics) | ✅ Complete | Real-time SQL counts |
| Quick Actions (4 shortcuts) | ✅ Complete | Hardcoded in backend response |
| Welcome header | ✅ Complete | Shows user's display_name |
| Fast Drive widget | ✅ Complete | Full GPS + logging flow |
| Fast Drive GPS opening | ✅ Complete | iOS (Apple Maps) + Android (Google Maps) detection |
| Fast Drive trip logging | ✅ Complete | Creates mileage logs + trip legs |
| Cert Expiry Alerts | ✅ Complete | Permission-gated, configurable look-ahead |
| Daily Report tab | ✅ Complete | Live data from costs router |
| Overview/Report tab switching | ✅ Complete | Permission-gated (show_dollar_values) |
| Responsive layout | ✅ Complete | 2→4 column grid, mobile-friendly |
| Dark mode support | ✅ Complete | All components use dark: variants |

**Overall: 100% functional — no stubs, no placeholders**

---

## 4. Cross-References

### Backend Dependencies

| Dashboard Feature | External Service/Router | Table(s) |
|-------------------|------------------------|-----------|
| KPI: total_parts | Direct SQL | `parts` |
| KPI: active_jobs | Direct SQL | `jobs` |
| KPI: pending_orders | Direct SQL | `purchase_orders` |
| KPI: low_stock | Direct SQL | `parts`, `stock` |
| Fast Drive | `MileageService` | `vehicle_assignments`, `vehicles`, `warehouse_locations`, `jobs`, `vehicle_trip_legs`, `vehicle_mileage_logs` |
| Cert Alerts | `PeopleService` | `employee_certifications`, `users` |
| Daily Report tab | `costs` router | `purchase_orders`, `po_line_items`, `jpo_line_items`, `stock_movements`, `jobs` |

### Frontend Dependencies

| Dashboard Feature | API Client | Shared Component |
|-------------------|------------|------------------|
| KPIs | `api/dashboard.ts` | `Card`, `Badge` |
| Fast Drive | `api/dashboard.ts` | `Card`, `CardHeader` |
| Cert Alerts | `api/dashboard.ts` | `Card`, `CardHeader`, `Badge` |
| Daily Report | `api/costs.ts` | `Card`, `CardHeader`, `Badge`, `Spinner`, `EmptyState` |

### Navigation Cross-references

- Quick Actions link to: `/jobs/active`, `/orders/purchase-orders/new`, `/warehouse/inventory`, `/warehouse/staging`
- Cert Alerts link to: `/people/employees/:id`
- Pending Actions link to: `/office/requests`, `/office/purchase-orders`, `/warehouse/returns`

---

## 5. Issues & TODOs

### No TODO/FIXME Comments Found

Zero TODO, FIXME, HACK, or TEMP comments in any dashboard file.

### Architectural Notes

1. **No dedicated service layer** — KPI queries are raw SQL inline in the router. For a small dashboard this is fine, but if more KPIs are added, consider extracting a `DashboardService`.

2. **Quick Actions are hardcoded** — The routes are returned from the backend but are static. If user-specific or role-specific quick actions are desired in the future, this needs a more dynamic approach.

3. **Daily Report tab uses costs router, not dashboard** — The `DailyReportTab` component calls `GET /api/costs/daily-report`, not a dashboard endpoint. This is logically correct (it IS cost/spending data) but creates a cross-module dependency.

4. **Low stock KPI has a rewritten query** — The code contains both the original GROUP BY query and a rewritten subquery version. The first one is dead code (immediately overwritten). Minor cleanup opportunity.

5. **No caching on KPI queries** — KPIs hit the database on every request. The frontend caches for 30s via react-query `staleTime`, but the backend has no caching. At scale, consider caching.

6. **Fast Drive "from" label inference is simplistic** — `inferFromLabel()` assumes: going to shop = from home, going to job = from shop, going home = from shop. Real trip chains (job → job) would need smarter inference or user input.

### Feature Gaps

- **No activity feed** — Despite many dashboards having an activity log, there's no recent-activity timeline. The DailyReportTab partially fills this role but only for the current day.
- **No customizable dashboard** — Users can't rearrange or hide cards/widgets.
- **No weather widget** — For an HVAC company, weather data could be valuable.
- **No "my tasks today" widget** — No scheduling/dispatch integration on the dashboard.
