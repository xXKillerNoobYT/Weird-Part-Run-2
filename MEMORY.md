# Memory — Wired-Part Project Context

> Re-read this file alongside `CLAUDE.md` at ~80% context usage to prevent instruction drift.
> Last updated: 2026-03-07

---

## Architecture Summary

| Layer | Technology | Details |
|-------|-----------|---------|
| Backend | Python 3.12 + FastAPI + SQLite (aiosqlite) + Pydantic v2 | 18 routers, 28 services, 19 repos, 30 migrations |
| Frontend | React 19 + TypeScript + Vite + Tailwind CSS v4 | ~210 feature files, ~97 routes, ~81 page components |
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

**Current: 119 tests across 10 files (critical paths covered)**

| Test File | What It Covers |
|-----------|---------------|
| `test_auth_middleware.py` | Device login, PIN login, /me, user picker, permission gates |
| `test_auth_router.py` | Auth endpoints, profile update, PIN change |
| `test_orders_service.py` | JPO creation, status transitions, PO creation |
| `test_order_pipeline.py` | JPO→PO lifecycle, clock in/out integration |
| `test_labor_service.py` | Clock in/out, drive time, active clock |
| `test_jobs_router.py` | Job CRUD, clock in/out API |
| `test_parts_router.py` | Parts CRUD, supplier FK guards |
| `test_cost_tracking_service.py` | FIFO/LIFO cost layers |
| `test_movement_service.py` | Warehouse movements |
| `conftest.py` | Shared fixtures, in-memory DB setup |

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
