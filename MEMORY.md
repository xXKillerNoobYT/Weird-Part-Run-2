# Memory — Wired-Part Project Context

> Re-read this file alongside `CLAUDE.md` at ~80% context usage to prevent instruction drift.
> Last updated: 2026-06-16

---

## Architecture Summary

| Layer | Technology | Details |
|-------|-----------|---------|
| Backend | Python 3.14 + FastAPI + SQLite (aiosqlite) + Pydantic v2 | 18 routers, 28 services, 19 repos, 35 migrations |
| Frontend | React 19 + TypeScript + Vite 7.3 + Tailwind CSS v4 | ~210 feature files, ~100 routes, ~107 page components |
| State | Zustand (UI: auth, clock, sidebar, theme) + TanStack Query (server) | 30s staleTime, retry=1, refetchOnWindowFocus=false |
| HTTP | Axios with JWT Bearer from localStorage | 401 interceptor auto-clears auth + reloads |
| Scheduler | APScheduler | Midnight daily reports, PDF cleanup, notification purge |
| Icons | Lucide React | Used across all pages |
| Mobile (V1.0) | Capacitor + `@capacitor-community/sqlite` + lean TS data layer | ~11 field-worker services + local SQLite (admin features stay shop-only) |
| Sync (V1.0) | HTTP push/pull over LAN | `_change_log` tracking, last-writer-wins conflicts |

### V1.0 Offline-First Architecture

Every device runs the full frontend with its own local database. Mobile gets a **lean field-worker backend** (~11 TS services), not a full mirror of the shop's 28 Python services:

- **Shop computer:** Python FastAPI + SQLite → truth anchor + sync API + serves desktop browsers. Runs ALL 28 services + APScheduler.
- **Mobile devices (Capacitor):** React frontend + lean TypeScript data layer + `@capacitor-community/sqlite` → works fully offline for field work
- **Desktop browsers:** Hit shop server directly over LAN (always at the shop)
- **API Adapter:** Frontend detects environment — Capacitor → local TS services, browser → HTTP API. Same React UI everywhere.
- **Sync:** Device ↔ Shop over HTTP on LAN when connected. Change tracking via `_change_log` table. Last-writer-wins conflict resolution.
- **TS Data Layer:** `frontend/src/local/` — ~11 field-worker services (auth, jobs, labor, movement, orders, notebooks, tools, parts-read, fleet-read, scheduling-read). Admin features (cost tracking, approvals, PDF generation, reports) stay shop-only.
- **Plan doc:** `docs/plans/deployment-master-plan.md` (comprehensive — §1-13 + appendices)

---

## Key Codebase Patterns

### Backend Patterns

- **`ApiResponse` wrapper** — Every endpoint returns `ApiResponse[T]` with `success`, `data`, `message` fields
- **`PaginatedData`** — List endpoints use `PaginatedData[T]` with `items`, `total`, `page`, `per_page`
- **Auth dependencies** — `require_user` (any logged-in user), `require_permission("key")` (specific hat permission)
- **Service → Repo → DB layering** — Most modules follow this cleanly. Exceptions noted below.
- **Lazy imports** — `jobs.py` and `orders.py` routers use `from app.services.X import Y` inside functions to avoid circular imports. This is intentional, not a bug.
- **Dynamic router registration** — `main.py` uses `importlib.import_module()` with graceful fallback, so missing routers don't crash the app
- **Migration runner** — `database.py` runs all `.sql` files in `migrations/` in numeric order on startup

### Frontend Patterns

- **Feature folder structure** — `features/{module}/pages/` for page components, some have `components/` subdirs
- **API client per domain** — `api/{module}.ts` with typed functions matching backend endpoints
- **React Query hooks** — Pages use `useQuery`/`useMutation` directly, no custom hook layer
- **Toast notifications** — `import { toast } from '@/lib/toast'` for success/error feedback
- **Permission gating** — `useAuthStore().hasPermission('key')` for conditional rendering
- **Responsive layout** — `AppShell` (sidebar + topbar + tabbar + content), sidebar collapses on mobile, tabbar scrolls

### Database Patterns

- **`updated_at` triggers** — Migration 014 added AFTER UPDATE triggers for all tables with `updated_at`
- **Soft deletes** — Some entities use `is_active` boolean, others use hard DELETE
- **JSON columns** — `delivery_methods` on suppliers, some schedule configs
- **Generated columns** — `company_sell_price` on parts is a generated column from cost × markup

---

## Known Architectural Quirks

### Services That Bypass Repo Layer
- **`parts.py` router** — Does direct repo access without a `parts_service.py` intermediary
- **`app_settings.py` router** — Does direct repo access without a service layer

### Missing Repo Files (Services Do SQL Directly)
- **No `jobs_repo.py`** — `job_service.py` writes SQL inline
- **No `warehouse_repo.py`** — `warehouse_service.py` writes SQL inline
- **No `labor_repo.py`** — `labor_service.py` writes SQL inline
- **No `report_repo.py`** — `report_service.py` writes SQL inline

### Stub Pages (Frontend — v2.0+ Placeholders)
- `/settings/ai-config` — `AiConfigPage.tsx` (19 lines) — v2.0+ LM Studio integration
- `/settings/devices` — `DeviceManagementPage.tsx` (19 lines) — v2.0 device/PGP management

### Legacy/Superseded Pages (Still in Codebase)
- `NewPartsRequestPage.tsx` — Superseded by `UnifiedOrderPage.tsx` (Phase 7A)
- `IncomingOrdersPage.tsx`, `DraftOrdersPage.tsx`, `ActiveOrdersPage.tsx` — Superseded by `PurchaseOrdersPage.tsx`

---

## File Size Hotspots

| File | Lines | Notes |
|------|------:|-------|
| `backend/app/routers/parts.py` | 2,224 | 61 endpoints — largest router |
| `backend/app/routers/orders.py` | 1,849 | 71 endpoints — most endpoints |
| `backend/app/services/notebook_service.py` | 989 | Templates + notebooks + sections + entries |
| `backend/app/routers/trucks.py` | 974 | 44 endpoints |
| `backend/app/repositories/vehicle_repo.py` | 915 | Largest repo |
| `frontend/src/api/orders.ts` | 910 | ~60 API functions |
| `frontend/src/features/jobs/pages/JobDetailPage.tsx` | 1,463 | Largest page |
| `frontend/src/features/parts/pages/SuppliersPage.tsx` | 1,356 | Supplier CRUD + contacts |
| `frontend/src/features/trucks/pages/VehicleDetailPage.tsx` | 1,200 | 6 sub-tabs |
| `frontend/src/features/parts/pages/CatalogPage.tsx` | 1,029 | Hierarchy filters + dual views |

---

## Phase Numbering (Canonical)

> The original plan (from phase-4-jobs-labor.md) had different numbering from what was built.
> This is the authoritative numbering based on actual build order.

| Phase | Name | Migrations | Status |
|-------|------|-----------|--------|
| 1 | Foundation | 001 | ✅ Complete |
| 2 | Parts & Inventory Core | 002 | ✅ Complete |
| 2.5 | Parts Hierarchy UX | 003–004 | ✅ Complete |
| 3 | Warehouse & Movements | 005–006 | ✅ Complete |
| 3.5 | Companions & Enhancements | 007–008 | ✅ Complete |
| 4 | Jobs & Labor | 009–012 | ✅ Complete |
| 4.5 | Unified Notebook System | 013–014 | ✅ Complete |
| 5 | Orders & Procurement | 015–016 | ✅ Complete |
| 6 | Fleet & Vehicle Management | 017 | ✅ Complete |
| 7A | Core Ordering Experience | 018 | ✅ Complete |
| 7B | Office Workflow | 019 | ✅ Complete |
| 7C | Warehouse Workflow | 020 | ✅ Complete |
| 7D | Analytics & Visibility | 021 | ✅ Complete |
| 7E | Quality of Life | 022 | ✅ Complete |
| 8 | People Full | 023 | ✅ Complete |
| 9 | Tools & Kits | 024 | ✅ Complete |
| 10 | People, Contacts & Scheduling | 025–027 | ✅ Complete |
| 11 | Reports & Pre-Billing | 028–029 | ✅ Complete |
| V1.0 | Deployment + Sync | 030 | ✅ Complete (software tasks 1-22; mobile builds need Mac) |

---

## Test Coverage Status

**Current: 218 tests across 21 files (all passing)**

| Test File | What It Covers |
|-----------|---------------|
| `test_auth_middleware.py` | Device login, PIN login, /me, user picker, permission gates |
| `test_auth_router.py` | Auth endpoints, profile update, PIN change |
| `test_auth_service.py` | Auth service layer |
| `test_base_repo.py` | Base repository CRUD |
| `test_bootstrap_router.py` | Initial setup flow |
| `test_cost_tracking_service.py` | FIFO/LIFO cost layers, margin |
| `test_device_security.py` | Device security protocols |
| `test_jobs_router.py` | Job CRUD, clock in/out API |
| `test_labor_service.py` | Clock in/out, drive time, active clock |
| `test_movement_service.py` | Warehouse movements |
| `test_order_pipeline.py` | JPO→PO lifecycle integration |
| `test_orders_service.py` | JPO creation, status transitions, PO creation |
| `test_parts_router.py` | Parts CRUD, supplier FK guards |
| `test_phase7d_verification.py` | Cost tracking, margin, analytics verification |
| `test_phase16b_multi_warehouse.py` | Multi-warehouse features |
| `test_relay_transport.py` | Relay transport layer |
| `test_security_integration.py` | Security integration |
| `test_sync_device_management.py` | Sync device management |
| `test_sync_hard_sync.py` | Hard sync backup/restore |
| `test_trailers_router.py` | Trailer CRUD |
| `test_update_protocol.py` | Update protocol |

---

## Common Commands

```bash
# Backend
cd backend && pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000

# Frontend
cd frontend && npm install
npm run dev  # port 5173

# Tests
cd backend && python -m pytest tests/ -v

# API docs
http://localhost:8000/docs
```

---

## Cross-Module Dependency Map

```
Parts ←── Warehouse (stock), Orders (JPO/PO lines), Jobs (consumption), Trucks (vehicle inventory)
Jobs ←── Labor (clock), Notebooks (lazy create), Orders (JPO source), People (employees), Scheduling (dispatch)
Orders ←── Parts (line items), Suppliers (PO targets), Jobs (JPO source), Warehouse (receiving), Costs (tracking)
Trucks ←── Parts (vehicle inventory), People (driver assignments), Tools (vehicle tools), Mileage (trip legs)
People ←── Auth (users/hats), Jobs (lead elevations), Scheduling (dispatch/time-off), Contacts (entity_contacts)
Costs ←── Parts (price data), Orders (PO receiving costs), Jobs (cost rollup), Warehouse (stock movements)
Dashboard ←── Jobs, Labor, Mileage, People (cert alerts), Costs
```

---

## Bug Audit History (2026-06-16)

### Critical Crashes Fixed (Session 1)
- **`execute_fetchone` → `await db.execute()` + `fetchone()`** — aiosqlite doesn't have `execute_fetchone`. 17 calls across services fixed.
- **`user["user_id"]` → `user["id"]` or `user.id`** — Users table uses `id` not `user_id`. 13 occurrences fixed.
- **`j.name` / `j.address`** → `j.job_name` / `j.address_line1` — Column name mismatches. 20+ SQL references fixed.
- **Pydantic `model_config` deprecation** — `config.py` updated to use `SettingsConfigDict` instead of inner `Config` class.

### Business Logic Fixes (Session 2)
- **Margin formula unification** — `cost_tracking_service.py` used markup (`cost × (1 + margin/100)`), `job_service.py` used margin (`cost / (1 - margin/100)`). Unified both to use margin formula. Edge cases: margin ≥ 100% → markup fallback, margin ≤ 0 → return cost.
- **`datetime('now')` literal string bugs** — 4 files passed `"datetime('now')"` as a parameter through `BaseRepo.update()`, storing it as a literal string instead of evaluating the SQL expression. Fixed:
  - `orders_service.py` (approved_at)
  - `vehicle_service.py` (approved_at)
  - `chat_repo.py` (deleted_at in soft_delete)
  - Note: `BaseRepo.update()` only handles datetime('now') for the `updated_at` column.

### API / Communication Fixes (Session 2)
- **`bluetooth.ts` double `/api/` prefix** — All 11 BT endpoints had `'/api/bluetooth/...'` but `apiClient` already has `baseURL: '/api'`, causing all calls to go to `/api/api/bluetooth/...` (404). Fixed all 11 endpoints.

### Frontend Fixes (Sessions 1-2)
- **6 responsive tables missing `overflow-x-auto`** — JPODetailPage, PartsRequestsPage, PODetailPage, PurchaseOrdersPage, StagingPage, ScheduleConfigPage. Fixed.
- **Sidebar icon import** — Fixed Lucide icon mismatch.
- **`/people` redirect** — Added missing redirect.
- **Vite chunk splitting** — Optimized build config for better code splitting.
- **Dynamic import warnings** — Fixed Vite dev-mode warnings.

### Key Technical Facts Confirmed
- `execute_fetchall` IS a valid aiosqlite method (false flagged by subagent)
- `companions_repo` and `qa_repo` correctly handle `datetime('now')` with their own SQL logic
- Database column names verified from migrations: `jobs.status` (not job_status), `parts.name`, `suppliers.name`, `vehicles.vehicle_name`, `users.display_name`

### Comprehensive Audit (Session 3, 2026-06-16)

**Backend audited — ALL 13 routers clean:**
- warehouse.py, orders.py, reports.py, jobs.py, tools.py, notebooks.py, sync.py, auth.py, public.py, parts.py, settings.py, people.py, contacts.py, scheduling.py, chat.py — zero crash-causing bugs found

**Frontend route audit — 138 routes verified:**
- All `navigate()` calls and `<Link>` components cross-checked against App.tsx
- No orphaned routes or dangling references remain

**Navigation fixes applied (4 broken links):**
- `PODetailPage.tsx`: `/orders/drafts` → `/orders/purchase-orders` (2 occurrences)
- `CustomerDetailPage.tsx`: `/jobs/active/${id}` → `/jobs/${id}`
- `ContractorDetailPage.tsx`: `/jobs/active/${id}` → `/jobs/${id}` (also fixed missing `)` in JSX)

**Global mutation error handler added:**
- `App.tsx`: QueryClient defaultOptions now has `mutations.onError` that shows `toast.error(msg)` for any unhandled mutation failure — covers 34 mutations that were missing individual onError handlers

**Null safety fix:**
- `SuppliersPage.tsx`: Fixed 2 delivery_methods fallback patterns that could produce `[null]` arrays when `primary_delivery_method` was null

**Final state:** 218 backend tests passing, frontend build clean (2,386 modules, 0 errors)

### Production Error Handling Hardening (Session 4, 2026-06-16)

**New infrastructure components:**
- `frontend/src/components/ui/ErrorFallback.tsx` — Reusable error UI (full-page + compact modes, retry button, error detail display)
- `frontend/src/components/ui/ErrorBoundary.tsx` — React class error boundary, catches unhandled render crashes

**App.tsx enhancements:**
- Added `QueryCache` with global `onError` — toasts background refetch failures (only when stale data exists, not on initial loads)
- Wrapped authenticated routes in `<ErrorBoundary label="application">` — catches unexpected render crashes
- Combined with Session 3's global mutation `onError` — both query and mutation failures now have global fallbacks

**23 pages fixed with proper error handling:**
- DashboardPage, ChatInboxPage, WarehouseNetworkPage, RFIListPage, MyClockPage, WarehouseExecPage, SpendingDashboardPage, WeeklyAvailabilityPage, ContactDirectoryPage, TeamsPage, ScheduleCalendarPage, SubSchedulePage, DailyDispatchPage, DispatchTemplatesPage, ScheduleConfigPage, FuelPage, TelematicsPage, InspectionsPage, CompanyProfilePage, AppConfigPage, ReturnAnalyticsPage, ReceiveShipmentPage, AiConfigPage
- Each now destructures `isError`/`refetch` and shows `<ErrorFallback onRetry={refetch}>` on query failure
- Multi-query pages (SpendingDashboard, WarehouseNetwork, SubSchedule, ScheduleConfig, Inspections) properly aggregate errors from all queries

**Production audit results (confirmed safe):**
- Backend: division by zero guarded, type conversions safe, auth on all mutation endpoints, SQL fully parameterized, resources properly managed, commits systematic
- Frontend: No TODO/FIXME items, only 12 console.log calls (all appropriate device-specific warnings in BT/sync/bootstrap services)

**Final state:** 218 backend tests passing, frontend production build clean (✔ built in 14.74s)

### UI/UX Production Polish (Session 5, 2026-06-16)

**Comprehensive audit completed — scroll, overflow, responsiveness, modals, buttons, empty states:**

**Scroll & overflow architecture:** ✅ CLEAN
- AppShell uses `flex h-screen overflow-hidden` → `<main className="flex-1 overflow-y-auto">` — single scroll container for all page content
- No nested scroll traps found
- All 75 tables across 46 files have `overflow-x-auto` wrappers ✅

**Header responsiveness:** ✅ CLEAN (1 fix)
- 135 header rows audited, all use `flex-wrap gap-3` or have only 1 button
- **Fixed:** `CustomerDetailPage.tsx` line 276 — added `flex-wrap gap-3` to edit header

**Empty states:** ✅ CLEAN
- All 107 pages verified — every list/table page handles empty state properly
- `InventoryTable` and `MovementsTable` components handle empty state internally

**Modal mobile compatibility:** Fixed 6 issues
- **4 notebook modals** (CreateNotebookModal, AddSectionModal, CreateEntryModal, PermissionGrantModal) — added `max-h-[90vh] flex flex-col` + `overflow-y-auto` on form content + enlarged close buttons to 44×44px touch targets
- **ShareReportModal** — replaced emoji `✕` close button with Lucide `<X>` icon + proper 44×44px touch target + added `lucide-react` import
- **BackupsPage ConfirmDialog** — enlarged close button from `p-1` (~16px) to `p-2` with `min-h-[44px] min-w-[44px]`

**Navigation & action buttons:** Fixed 4 issues
- **NotebookDetailPage** — back button enlarged from `p-1.5` (~28px) to `p-2` (44×44px), "Add Section" and "Archive" buttons enlarged from `py-1.5` to `py-2` with `min-h-[44px]`
- **QABoardPage** — back/close button enlarged from `p-1` (~24px) to `p-2` with `min-h-[44px] min-w-[44px]`

**Not changed (acceptable as-is):**
- Inline table row action buttons (`p-1`/`p-1.5`) — secondary actions in constrained row layouts
- Dashboard tab buttons (`py-2` ≈ 32px) — standard tab bar sizing with adequate horizontal spacing
- Filter toggle buttons (`p-2` ≈ 32px) — non-primary, one-time toggles
- `calc(100vh - X)` in split-panel pages (CategoriesPage, POManagement, etc.) — intentional for independent-scroll panels

**Files modified (9 total):**
1. `features/people/pages/CustomerDetailPage.tsx` — header flex-wrap
2. `features/notebooks/components/CreateNotebookModal.tsx` — modal overflow + close button
3. `features/notebooks/components/AddSectionModal.tsx` — modal overflow + close button
4. `features/notebooks/components/CreateEntryModal.tsx` — modal overflow + close button
5. `features/notebooks/components/PermissionGrantModal.tsx` — modal overflow + close button
6. `features/reports/components/ShareReportModal.tsx` — emoji→icon close button + X import
7. `features/settings/pages/BackupsPage.tsx` — ConfirmDialog close button
8. `features/notebooks/pages/NotebookDetailPage.tsx` — back button + action buttons
9. `features/chat/pages/QABoardPage.tsx` — back button

**Final state:** 218 backend tests passing, frontend production build clean (✔ built in 15.44s)
