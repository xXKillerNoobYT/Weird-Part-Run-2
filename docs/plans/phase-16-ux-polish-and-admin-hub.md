# Phase 16 — UX Polish, Admin Hub Consolidation & Feature Completion

> **Created:** 2026-03-07
> **Status:** ✅ Complete
> **Scope:** Navigation restructure, accent-color bug fix, People/Reports/Scheduling consolidation into Office, report enhancements, warehouse improvements, team assignment, special-items wizard, Device Management v1.0, AI/Device plans.

---

## Context

All phases 1–15 are complete (V1.0 infra, 44/44 gap items, 13 audits). This phase addresses user-reported issues from real-world testing plus the admin-hub consolidation that makes the Office the single management destination.

---

## Work Breakdown

### P0 — Bugs (fix before anything else)

| ID | Issue | File | Fix |
|----|-------|------|-----|
| P0-1 | Accent color saves to backend but never applies to the UI | `theme-store.ts` | `applyTheme()` must set `--color-primary` CSS variable on `<html>` |
| P0-2 | Customer/Contractor create mutations have no success/error toast | `CustomersPage.tsx`, `ContractorsPage.tsx` | Add `toast.success` + `toast.error` to all mutations |
| P0-3 | Parts Hierarchy tree may have rendering/CRUD issues | `CategoriesPage.tsx` + category tree components | Audit and fix |

### P1 — Navigation Restructure (Office = Admin Hub)

The Office module becomes the single admin panel for non-field work. Move management-oriented tabs there. Personal/field views stay where they are.

#### Office tab additions

| Source Module | Tab | New Office Tab Label |
|--------------|-----|---------------------|
| People | Employee List | Employee List |
| People | Roles/Hats | Roles & Hats |
| People | Permissions | Permissions |
| Reports | Daily Reports | Daily Reports |
| Reports | Pre-Billing | Pre-Billing |
| Reports | Timesheets | Timesheets |
| Reports | Labor Overview | Labor Overview |
| Reports | Profitability | Profitability |
| Reports | Exports | Exports |
| Scheduling | Daily Dispatch | Daily Dispatch |
| Scheduling | Availability | Team Availability |
| Scheduling | Templates | Dispatch Templates |
| Scheduling | Default Schedules | Default Schedules |
| Scheduling | Subcontractors | Subcontractors |

#### Modules after restructure

**Office** — becomes the admin hub:
- Warehouse Executive, Manage Jobs, Notebook Templates, Clock-Out Questions, Warehouse Locations, Spending *(existing)*
- + Employee List, Roles & Hats, Permissions *(from People)*
- + Daily Reports, Pre-Billing, Timesheets, Labor Overview, Profitability, Exports *(from Reports)*
- + Daily Dispatch, Team Availability, Dispatch Templates, Default Schedules, Subcontractors *(from Scheduling)*

**People** — becomes external contacts only:
- Customers, Contractors, All Contacts
- *(Employee List, Hats, Permissions removed — now in Office)*

**Scheduling** — becomes personal/field view:
- Calendar (default: 3-week view), Time Off
- *(Dispatch/Templates/Schedules/Subs moved to Office)*

**Reports** — remove as standalone module from sidebar (all tabs now in Office)

**Note on URLs:** Existing page URLs stay the same (`/people/employees`, `/reports/pre-billing`, `/scheduling/dispatch`). Only the navigation config changes — tabs in Office point to those same paths. Old module entries that become empty are removed from the sidebar.

### P2 — Calendar 3-Week Default

- Change `ScheduleCalendarPage` default span from 1 week to 3 weeks
- Keep week nav arrows (step by 1 week)
- Add "3 weeks" label to the header

### P3 — Warehouse Enhancements

#### P3-1: Audit Status Dashboard Summary

On `WarehouseDashboardPage`, add an **Audit Health** card showing:
- ✅ Good (audited within threshold — green count)
- ⚠️ Coming Up (due within 30 days — amber count)
- ❌ Needs Audit (overdue — red count)
- Drill-down: clicking opens Audit page pre-filtered

Backend: extend `/api/warehouse/dashboard/kpis` or add a new `/api/warehouse/dashboard/audit-summary` endpoint that queries `last_audited_at` on parts.

#### P3-2: Spot Check — Pull Oldest 3, Prioritize Low-Stock

Change spot check selection logic in `audit_service.py`:
1. Among items needing ordering (stock ≤ min_stock_level), pull the 3 with the oldest `last_audited_at` regardless of recency
2. Then fill remaining spots with the oldest-audited items overall
3. Frontend: update `AuditSetup` to show the 3 pre-selected parts for spot check with their last-audit dates

Backend: update `get_suggested_rolling()` endpoint (or add a dedicated `get_spot_check_suggestions()` endpoint).

#### P3-3: Pulled/Staging Page — Per-Job Pull Info

Enhance `StagingPage` and `StagingCard`:
- Show per-job summary: "X parts pulled, Y still pending from warehouse"
- Show job name prominently at top of each destination group
- Show total pulled weight/count
- Parts that have not yet been pulled (still in warehouse but expected for the job) show in a "Pending Pull" section with a quick-pull action

Backend: enhance `/api/warehouse/staging` to include pending items (parts on approved JPOs not yet pulled) grouped by destination job.

#### P3-4: Warehouse Settings Tab

Add a "Settings" tab to the Warehouse navigation. New page: `WarehouseSettingsPage`.

Settings exposed:
1. **Full Inventory Logged?** — toggle (yes/no). Drives behavior for unknown parts.
2. **Pull from warehouse first or order first** — radio: "Check warehouse → then order" vs "Order immediately, find in warehouse"
3. **Auto-adjust counts** — per-location toggles. When count matches system, auto-confirm. Manual override on individual items preserved.
4. **Unknown part behavior** (shown when "Full Inventory Logged = No"):
   - Option A: "Check first — is it there before ordering?" (order held)
   - Option B: "Order but check simultaneously — if found, update inventory and cancel/redirect order"
   - Option C: "Add to inventory when found — capture location + count on discovery"
5. **Location behavior** — when found, prompt to assign to: shop warehouse, specific truck, or job site

Backend: store these as keyed settings (category: `warehouse`) in the `settings` table via `SettingsRepo`. Frontend reads via `getAllSettings()` / `PUT /api/settings/bulk`.

### P4 — Report Enhancements

#### P4-1: Pre-Billing — Billing Cycle Fast Filters + All-Jobs View

- Add fast-filter buttons: **This Billing Cycle** | **Last Billing Cycle** | **Custom Range**
- Billing cycle period (e.g. bi-weekly starting Monday) is configurable in Settings → App Config
- Add **All Jobs** aggregate view (currently requires selecting a specific job)
- Backend: add `billing_cycle_start` setting key. Frontend: compute current/previous cycle dates from it.
- PDF export: add "Export to PDF" button that generates a summary suitable for bookkeeper handoff

#### P4-2: Timesheets — Pay Schedule Filters

- Add fast-filter: **This Pay Period** | **Last Pay Period** | **Custom**
- Pay period type (weekly/bi-weekly/semi-monthly/monthly) and start day configurable in Settings → App Config
- Setting key: `pay_period_type` and `pay_period_start_day`

#### P4-3: Daily Reports — Drive Time Warnings

In `DailyReportView` and `JobReportsListPage`:
- Flag reports where total drive time > configurable threshold relative to billable hours
- Warning types:
  - 🟡 **High drive ratio** — drive time > 30% of total time worked
  - 🔴 **Excessive drive time** — drive time > 1.5× hours worked
- Show inline warning badge on the report card in the list view
- Show warning banner inside the report detail view with the specific ratio
- Threshold configurable in Settings → App Config (key: `max_drive_ratio`)

### P5 — Orders: Special Items Placement Wizard

When a special item (non-catalog item ordered via the unified order form) is flagged or submitted:
1. In the Office tab / Approvals page, show a banner: "X special items need catalog placement"
2. Clicking opens a **Part Placement Wizard** modal:
   - Step 1: Shows the special item details (description, supplier, price, specs user entered)
   - Step 2: Opens the parts hierarchy tree — user navigates to the right category
   - Step 3: Within chosen category: pick Style → Type → Brand → Color (creates hierarchy nodes as needed)
   - Step 4: Fill in standard part form (name, code, min/max stock)
   - Step 5: Creates the actual catalog part. The special item on the original order is replaced with the new catalog part ID.
3. After placement, the special item is "resolved" (linked to the new part ID in `special_items` table)

Backend: add `PUT /api/jobs/special-items/{id}/resolve` endpoint that takes a `part_id` and links the special item to the catalog.

### P6 — Jobs: Team Assignment

Add ability to assign employees to a job by **team** or **individually**:
1. On `JobDetailPage` → People tab: "Assign Team" button
2. A team is a named group of employees (e.g. "Crew A", "Crew B")
3. Create teams in Office → Employee List (or a new "Teams" tab)
4. On assignment: pick a team → all members auto-dispatched to the job for the date range

Backend changes:
- New table: `employee_teams` (id, name, description)
- New table: `employee_team_members` (team_id, user_id)
- New migration: `036_employee_teams.sql`
- New endpoints (in `people.py` router):
  - `GET /api/people/teams`
  - `POST /api/people/teams`
  - `PUT /api/people/teams/{id}`
  - `DELETE /api/people/teams/{id}`
  - `POST /api/people/teams/{id}/members`
  - `DELETE /api/people/teams/{id}/members/{user_id}`
- Dispatch endpoint: `POST /api/scheduling/dispatch/team` — dispatch a whole team to a job

Frontend:
- Teams management in Office → Employee section
- Job detail People tab: "Add by Team" button → modal to pick team + date range

### P7 — Settings: AI Assistant Plan

Create `docs/plans/ai-assistant-plan.md` covering:
- What the AI Assistant will do (NL queries on inventory, anomaly detection, predictive ordering)
- Local LM Studio integration (no cloud dependency)
- AiConfigPage v1.0 scope: configure LM Studio endpoint URL, model selection, enable/disable per-feature

Update `AiConfigPage.tsx` stub with a meaningful placeholder showing the planned features.

### P8 — Settings: Device Management (v1.0)

Per user note: "everything in the plans is version 1". Implement a real v1.0 Device Management page.

`DeviceManagementPage` — show:
1. **Registered Devices** list — from `_device_registry` table (already in sync engine)
   - Device UUID, name, last-seen, sync status
   - Revoke button (removes device's access token)
2. **Active Sessions** — employees currently logged in
3. **Sync Status** — per-device: last push, last pull, pending changes count
4. **Manual Force-Sync** button — triggers immediate sync for selected device

Backend: add `/api/devices` router with:
- `GET /api/devices` — list registered devices from `_device_registry`
- `DELETE /api/devices/{device_id}` — revoke device (requires `manage_devices`)
- `GET /api/devices/{device_id}/sync-status` — sync stats for device

### P9 — Parts Hierarchy Fix

Audit the `CategoriesPage` tree editor for:
- CRUD operations (add/edit/delete category, style, type, color)
- Visual hierarchy rendering (proper nesting)
- Color assignments working
- Part links being properly maintained

Fix any issues found and verify through all levels of the hierarchy.

---

## Migration Plan

| Migration | Table(s) | Contents |
|-----------|---------|---------|
| `036_employee_teams.sql` | `employee_teams`, `employee_team_members` | Team CRUD + membership |
| `037_warehouse_settings.sql` | `settings` rows | Default warehouse settings keys |
| `038_billing_cycle_settings.sql` | `settings` rows | `billing_cycle_start`, `pay_period_type`, `pay_period_start_day`, `max_drive_ratio` |

---

## Implementation Order

1. P0 bugs (accent color CSS var, create toasts)
2. P1 navigation restructure (navigation.ts only — no page moves needed)
3. P2 calendar 3-week default
4. P3 warehouse enhancements (dashboard audit status, spot check, staging, settings tab)
5. P4 report enhancements (pre-billing filters, timesheet filters, daily report warnings)
6. P8 device management (backend + page)
7. P6 team assignment (migration + backend + frontend)
8. P5 special items placement wizard
9. P7 AI plan document
10. P9 parts hierarchy audit+fix

---

## Completion Gates

- [x] Accent color CSS variable applying across all components
- [x] Customer/Contractor create mutations show success/error feedback
- [x] Office module contains all management tabs (employees, reports, scheduling admin)
- [x] People shows only contacts (customers, contractors, directory)
- [x] Scheduling shows only calendar (3-week default) + time off
- [x] Reports module removed from sidebar (tabs in Office)
- [x] Warehouse dashboard shows audit health card
- [x] Spot check pulls 3 oldest with low-stock prioritization
- [x] Staging page shows per-job pull counts and pending items
- [x] Warehouse settings tab functional
- [x] Pre-Billing has billing cycle fast filters + all-jobs view
- [x] Timesheets has pay period fast filters
- [x] Daily Reports show drive time warning badges
- [x] Device Management page shows registered devices (real data)
- [x] Team assignment works (create team, assign to job, bulk dispatch)
- [x] Special items placement wizard opens from approvals
- [x] AI Assistant plan document created
- [x] Parts hierarchy fully functional at all levels
- [x] `npm run build` passes
- [x] `pytest tests/ -v` all pass
