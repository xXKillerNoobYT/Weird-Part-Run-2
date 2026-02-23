# Wired-Part: Full Implementation Plan

## Context

Wired-Part is a field service management app for an electrical contracting company. It manages parts inventory, warehouse operations, truck inventories, job tracking, labor hours, procurement, and pre-billing exports for the bookkeeper. The project is **greenfield** — no code exists yet. The full specification lives in `ThePlan.md` (1100+ lines). This plan turns that spec into an actionable, phased build.

**Why now**: The business needs a single source of truth for parts, jobs, labor, and costs — all 100% local, offline-first, human-guided, with no customer-facing billing (bookkeeper handles all billouts).

---

## Decisions Made (User-Confirmed)

| Decision | Choice |
|----------|--------|
| **UI Framework** | Web-based: Python FastAPI backend + React/TypeScript/Tailwind frontend |
| **Navigation** | Left sidebar (modules) + top tab bar (sub-views). Collapsible on mobile. |
| **Design Style** | Clean Professional (Notion/Linear). Blue primary `#3B82F6`, Inter font, dark/light mode. |
| **Scale** | Medium: 5-20 employees, 500-5000 parts, 50-200 jobs |
| **Auth** | Auto-login per device + PIN for sensitive actions. Public device flag (forces full login). |
| **Roles** | 7 built-in hats (Admin→Grunt) + flexible custom hats. Additive union permissions. |
| **Ordering** | Hybrid: auto-suggest from forecasting, office always decides. Manual PO also available. |
| **Movements** | Both direct and staged patterns. ALL via Guided Movement Wizard (human-only, never auto). |
| **Job Detail** | Opens to Notebook/Notes first (field worker priority). |
| **Trucks** | Full dashboard: inventory + tools + maintenance schedule + service history + mileage. |
| **People** | Name, phone, email, hats, truck, PIN, emergency contact, certifications, hire date, pay rate. |
| **Build Order** | Full foundation first (DB + Auth + Nav shell), THEN features one by one. |

---

## Tech Stack

```
Backend:   Python 3.12 + FastAPI + SQLite (aiosqlite) + Pydantic v2
Frontend:  React 19 + TypeScript + Vite + Tailwind CSS 3
State:     Zustand (UI state) + TanStack Query (server state)
Icons:     Lucide React
Desktop:   Electron or Tauri (Phase 11)
Mobile:    Same responsive web UI as PWA (Phase 11)
```

---

## Project Structure

```
Weird-Part-Run-2/
├── backend/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py                    # FastAPI entry point
│   │   ├── config.py                  # Settings, env loading
│   │   ├── database.py                # SQLite connection + migration runner
│   │   ├── models/                    # Pydantic request/response models
│   │   │   ├── __init__.py
│   │   │   ├── auth.py
│   │   │   ├── common.py
│   │   │   ├── parts.py
│   │   │   ├── warehouse.py
│   │   │   ├── jobs.py
│   │   │   └── orders.py
│   │   ├── routers/                   # FastAPI route modules
│   │   │   ├── __init__.py
│   │   │   ├── auth.py
│   │   │   ├── dashboard.py
│   │   │   ├── parts.py
│   │   │   ├── warehouse.py
│   │   │   ├── trucks.py
│   │   │   ├── jobs.py
│   │   │   ├── orders.py
│   │   │   ├── people.py
│   │   │   ├── reports.py
│   │   │   └── app_settings.py
│   │   ├── repositories/             # Data access layer
│   │   │   ├── __init__.py
│   │   │   ├── base.py
│   │   │   ├── user_repo.py
│   │   │   ├── device_repo.py
│   │   │   ├── settings_repo.py
│   │   │   ├── parts_repo.py
│   │   │   ├── stock_repo.py
│   │   │   ├── jobs_repo.py
│   │   │   └── orders_repo.py
│   │   ├── services/                 # Business logic
│   │   │   ├── __init__.py
│   │   │   ├── auth_service.py
│   │   │   ├── movement_service.py   # THE core: atomic stock moves
│   │   │   ├── forecast_service.py
│   │   │   └── optimization_service.py
│   │   ├── middleware/
│   │   │   ├── __init__.py
│   │   │   └── auth.py               # JWT + permission dependencies
│   │   └── migrations/               # Numbered SQL files
│   │       ├── 001_foundation.sql
│   │       ├── 002_parts_and_inventory.sql
│   │       ├── 003_warehouse.sql
│   │       ├── 004_jobs_and_labor.sql
│   │       └── 005_orders.sql
│   ├── tests/
│   │   ├── conftest.py
│   │   └── ...
│   ├── requirements.txt
│   └── pyproject.toml
├── frontend/
│   ├── public/
│   │   └── manifest.json
│   ├── src/
│   │   ├── main.tsx
│   │   ├── App.tsx
│   │   ├── index.css                  # Tailwind + Inter font import
│   │   ├── api/                       # Axios client + endpoint modules
│   │   │   ├── client.ts
│   │   │   ├── auth.ts
│   │   │   ├── parts.ts
│   │   │   ├── warehouse.ts
│   │   │   ├── jobs.ts
│   │   │   ├── orders.ts
│   │   │   └── settings.ts
│   │   ├── components/
│   │   │   ├── layout/
│   │   │   │   ├── AppShell.tsx       # Sidebar + TopBar + Content
│   │   │   │   ├── Sidebar.tsx
│   │   │   │   ├── SidebarItem.tsx
│   │   │   │   ├── TopBar.tsx
│   │   │   │   ├── TabBar.tsx
│   │   │   │   └── MobileMenu.tsx
│   │   │   ├── ui/                    # Shared design system
│   │   │   │   ├── Button.tsx
│   │   │   │   ├── Card.tsx
│   │   │   │   ├── Input.tsx
│   │   │   │   ├── Badge.tsx
│   │   │   │   ├── Modal.tsx
│   │   │   │   ├── Table.tsx
│   │   │   │   ├── DropdownMenu.tsx
│   │   │   │   ├── Spinner.tsx
│   │   │   │   ├── Toast.tsx
│   │   │   │   ├── PinDialog.tsx
│   │   │   │   └── EmptyState.tsx
│   │   │   ├── auth/
│   │   │   │   ├── AuthGate.tsx
│   │   │   │   ├── PinLoginForm.tsx
│   │   │   │   └── UserPicker.tsx
│   │   │   └── shared/
│   │   │       ├── ProtectedRoute.tsx
│   │   │       ├── PageHeader.tsx
│   │   │       ├── SearchBar.tsx
│   │   │       ├── NotificationBell.tsx
│   │   │       └── ThemeToggle.tsx
│   │   ├── features/                  # One folder per module
│   │   │   ├── dashboard/
│   │   │   ├── parts/
│   │   │   ├── warehouse/
│   │   │   ├── trucks/
│   │   │   ├── jobs/
│   │   │   ├── orders/
│   │   │   ├── people/
│   │   │   ├── reports/
│   │   │   └── settings/
│   │   ├── hooks/
│   │   │   ├── useAuth.ts
│   │   │   ├── usePermission.ts
│   │   │   ├── useTheme.ts
│   │   │   └── useMediaQuery.ts
│   │   ├── stores/
│   │   │   ├── auth-store.ts
│   │   │   ├── theme-store.ts
│   │   │   └── sidebar-store.ts
│   │   └── lib/
│   │       ├── types.ts
│   │       ├── navigation.ts          # All modules/tabs/permissions config
│   │       ├── constants.ts
│   │       └── utils.ts
│   ├── tailwind.config.ts
│   ├── vite.config.ts
│   ├── tsconfig.json
│   └── package.json
├── docs/
│   └── implementation-plan.md         # THIS PLAN (saved to project)
├── directives/                        # SOPs per 3-layer architecture
├── execution/                         # Deterministic Python scripts
├── .tmp/                              # Intermediate files
├── .env
├── .gitignore
├── CLAUDE.md
├── ThePlan.md
└── README.md
```

---

## Navigation Map (Every Page & Tab)

```
SIDEBAR                    TAB BAR                         PAGE CONTENT
─────────────────────────────────────────────────────────────────────────
📊 Dashboard               (none)                          KPI cards + quick actions
📦 Parts                   Catalog                         Searchable parts table + detail panel
                           Brands                          Brand list + CRUD
                           Pricing                         Price columns + bulk edit (perm-gated)
                           Forecasting                     ADU, days-to-low, suggested orders
                           Import/Export                   CSV/Excel upload & download
🏭 Warehouse               Dashboard                       KPI cards + action queue + AI insights
                           Inventory Grid                  Full stock table w/ filters
                           Pulled/Staging                  Staging area for job/truck prep
                           Audit                           Card-swipe audit flow (perm-gated)
                           Movements Log                   Movement history table
🚛 Trucks                  My Truck                        Personal truck dashboard
                           All Trucks                      Fleet overview table
                           Tools                           Tool tracking per truck
                           Maintenance                     Service schedule + history + costs
                           Mileage                         Mileage log
📋 Jobs                    Active Jobs                     Job list (filterable by status/type)
                           (Job #{id})                     → Opens job detail with sub-tabs:
                             → Notebook                      Section/page tree + rich editor
                             → Chat                          Per-job messaging
                             → Parts                         Consumed parts list
                             → Labor                         Clock entries + hours
                             → Billing                       Pre-billing prep view
                           Templates                       Notebook template manager (perm-gated)
🛒 Orders                  Draft POs                       Draft purchase orders
                           Pending                         Submitted POs awaiting delivery
                           Incoming                        Received/partial POs → Guided Receive
                           Returns                         Return requests + RMA tracking
                           Procurement Planner             Optimization dashboard + suggestions
👥 People                  Employee List                   Employee table + detail
                           Roles/Hats                      Hat management + assignment
                           Permissions                     Permission matrix (perm-gated)
📈 Reports                 Pre-Billing                     Job cost breakdowns for bookkeeper
                           Timesheets                      Employee timesheet view
                           Labor Overview                  Cross-job labor summary
                           Exports                         Export bundles (CSV/PDF) (perm-gated)
⚙️ Settings                App Config                      Company name, defaults (perm-gated)
                           Themes                          Light/dark toggle + color picker
                           Sync                            Sync config + status
                           AI Config                       LM Studio connection (perm-gated)
                           Device Management               Device list + public flag (perm-gated)
```

---

## Phase 1: Foundation (First Sprint)

**Goal**: Standing app with DB, auth, full navigation shell, theme system. Every page exists (stubs). Backend serves API. Frontend renders everything.

### Step 0: Project Setup
- Save this plan to `docs/implementation-plan.md`
- Create `.gitignore` (node_modules, __pycache__, .env, .tmp/, *.db, dist/)
- Create `.env` with defaults
- Create `directives/`, `execution/`, `.tmp/` directories

### Step 1: Backend Foundation

**Files**: `backend/app/config.py`, `database.py`, `main.py`, `middleware/auth.py`

**Database** (`migrations/001_foundation.sql`):
- `users` — display_name, email, phone, pin_hash, default_truck_id, emergency_contact, certification, hire_date, pay_rate, is_active
- `hats` — name, description, is_builtin (7 seed rows)
- `hat_permissions` — hat_id, permission_key (~30 permission keys seeded)
- `user_hats` — user_id, hat_id
- `devices` — device_fingerprint, assigned_user_id, **is_public**, last_seen
- `settings` — key, value (JSON), category
- `activity_log` — user_id, action, entity_type, entity_id, details, timestamp
- `notifications` — user_id, title, body, severity, source, is_read
- Seed: default Admin user (PIN: 1234), all 7 hats with permissions

**Auth Flow**:
1. Frontend generates device fingerprint → `POST /api/auth/device-login`
2. If device assigned to user AND not public → auto JWT token
3. If public or unassigned → show UserPicker → PinLoginForm → JWT token
4. PIN verification endpoint for sensitive actions (separate short-lived token)

**API Routes (Phase 1)**:
- `POST /api/auth/device-login` — auto-login by device
- `POST /api/auth/pin-login` — login with user_id + PIN
- `GET /api/auth/me` — current user + permissions
- `POST /api/auth/verify-pin` — PIN check for sensitive ops
- `GET/PUT /api/settings/*` — settings CRUD
- `GET/PUT /api/settings/theme` — theme specifically
- All other routers (`parts`, `warehouse`, etc.) return `{"status": "not_implemented"}`

**Key Dependencies**: fastapi, uvicorn, aiosqlite, pydantic, python-jose, passlib

### Step 2: Frontend Foundation

**Files**: All files under `frontend/src/components/layout/`, `components/ui/`, `components/auth/`, `stores/`, `hooks/`, `lib/`

**Core Components**:
- `AppShell` — Main layout composing Sidebar + TopBar + TabBar + content area
- `Sidebar` — 9 module items, permission-filtered, collapsible, mobile hamburger
- `TabBar` — Sub-tabs for active module, permission-filtered, mobile dropdown
- `AuthGate` — Orchestrates device check → user picker → PIN entry
- `ThemeToggle` — Light/dark switch, persists to backend
- `PinDialog` — Reusable PIN entry modal for sensitive actions

**All Module Stubs**: Every page from the navigation map created as a stub component showing the page title and "Coming soon" placeholder. This means the ENTIRE navigation works end-to-end from day 1.

**Design System** (`components/ui/`): Button, Card, Input, Badge, Modal, Table, DropdownMenu, Spinner, Toast, EmptyState — all themed for light/dark mode with Tailwind.

**Key Dependencies**: react, react-router-dom, zustand, @tanstack/react-query, axios, lucide-react, clsx, tailwind-merge

### Step 3: Test Phase 1
- Backend: pytest — auth flow, migrations, settings, permissions
- Frontend: vitest — sidebar rendering, auth flow, theme toggle, protected routes
- Manual: Start both servers, login as admin, navigate every module, switch themes

### Phase 1 Deliverable
✅ Backend running at `localhost:8000` with API docs at `/docs`
✅ Frontend running at `localhost:5173` with full navigation shell
✅ Auto-login works on assigned devices
✅ PIN login works on public devices
✅ All 9 sidebar modules navigate correctly
✅ All sub-tabs render within each module
✅ Dark/light theme switching works
✅ Permission-gated nav items hidden for non-admin users

---

## Phase 2: Parts & Inventory Core

**Goal**: Full Parts Catalog with CRUD, search, filter, brands, pricing, stock model.

### Database (`migrations/002_parts_and_inventory.sql`)
- `parts` — Full schema from ThePlan.md (code, name, type, brand_id, cost/markup/sell_price, forecast fields, optimization fields, deprecation status, QR tagged)
- `brands` — name, website, notes
- `suppliers` — name, contact info, reliability scores (on_time_rate, quality_score, avg_lead_days)
- `part_supplier_links` — part_id, supplier_id, supplier_pn, moq, discount_brackets JSON
- `stock` — location_type (warehouse/pulled/truck/job), location_id, part_id, qty, supplier_id
- `stock_movements` — from/to locations, part_id, qty, supplier_id, human_user_id, verified_by, photo_path, scan_confirmed, GPS

### API Endpoints
- `GET/POST/PUT/DELETE /api/parts/catalog` — Parts CRUD with search & pagination
- `GET/PUT /api/parts/catalog/{id}/pricing` — Pricing (perm-gated to `show_dollar_values`)
- `GET/POST/PUT/DELETE /api/parts/brands` — Brands CRUD
- `GET /api/parts/catalog/{id}/stock` — Stock by location for a part
- `POST /api/parts/import` + `GET /api/parts/export` — CSV/Excel

### Key Components
- `PartTable` — Sortable, filterable data table (columns: Code, Name, Type, Brand, Total Stock, Cost, Sell, Daily Use, Days Low, Suggested Order, Actions)
- `PartDetailPanel` — Split-panel on row click showing full detail
- `PartEditDialog` — Modal with tabs: Basic Info, Pricing, Suppliers, History, Attachments
- `PartFilters` — Filter bar: type, brand, low-stock, deprecated, QR tagged
- `PriceCell` — Shows price or `•••` based on `show_dollar_values` permission

### Phase 2 Deliverable
✅ Add/edit/search/filter parts in the catalog
✅ Brand management
✅ Pricing visible only to authorized users
✅ Stock model populated and queryable
✅ CSV import/export working

---

## Phase 3: Warehouse & Movements

**Goal**: Warehouse dashboard, Guided Movement Wizard, pulled staging, audit, movement log.

### Database (`migrations/003_warehouse.sql`)
- `audits` — audit_type, location_id, status, progress counters
- `audit_items` — part_id, expected_qty, actual_qty, status, photo_path

### The Guided Movement Wizard (Most Important Feature)
A multi-step wizard modal used for ALL stock movements. Steps:
1. **Select From → To** — Dropdowns + visual flow map
2. **Select Parts** — Search catalog or QR scan, batch select up to 20
3. **Enter Quantity** — Defaults from forecast, live validation against source stock
4. **Verification Checkpoint** — QR scan + photo (mandatory for >$500 or to/from Job) + qty double-confirm
5. **Notes & Reason** — Free text + quick-pick reasons
6. **Preview & Confirm** — Before/after stock levels, supplier chain, cost impact, irreversibility warning
7. **Execute** — Atomic transaction: deduct source, add destination, log movement

Backend enforces: `human_user_id` REQUIRED (cannot be null), atomic transaction, `WHERE qty >= ?` prevents negative stock, supplier_id carried forward.

### Key Components
- `WarehouseDashboardPage` — 4 KPI cards (Stock Health, Today's Value, Forecast Shortfall, Pending Tasks) + inventory grid + sidebar with action queue + AI insights
- `GuidedMovementWizard` — 7-step modal wizard (reused everywhere)
- `AuditPage` — Card-swipe flow: large card per part, expected vs actual, photo on discrepancy, progress bar
- `MovementsLogPage` — Movement history table with user, photos, timestamps

### Phase 3 Deliverable
✅ Warehouse dashboard with live KPIs
✅ Guided Movement Wizard works for all paths (warehouse↔pulled↔truck↔job)
✅ Pulled staging area shows staged items
✅ Card-swipe audit functional
✅ Full movement history log

---

## Phase 4: Jobs & Labor

**Goal**: Job CRUD, job detail with notebook, clock in/out, labor tracking, stage enforcement.

### Database (`migrations/004_jobs_and_labor.sql`)
- `jobs` — job_number, customer_name, address, status, priority, job_type, current_stage, bro_rate, lead_user_id
- `job_parts` — consumption tracking with cost snapshots
- `labor_entries` — clock_in/out, hours, drive_time, overtime, GPS, photos
- `notebook_templates`, `template_sections`, `template_pages` — Template system
- `job_notebooks`, `notebook_sections`, `notebook_pages`, `notebook_attachments` — Per-job notebooks

### Key Components
- `ActiveJobsPage` — Job list with status/type/priority filters
- `JobDetailPage` — Opens to Notebook tab first, with sub-tabs: Notebook, Chat (stub), Parts, Labor, Billing (stub)
- `NotebookEditor` — Section/page tree + rich text editor + attachment upload
- `ClockInOutButton` — GPS check + photo + notes
- `LaborTable` — Cross-job labor entries with date filters
- `EnforcementModal` — Blocks stage change until required notebook items are complete, with Manager Override (PIN)

### Phase 4 Deliverable
✅ Create/edit/manage jobs with full lifecycle
✅ Notebook with sections, pages, photos, part references
✅ Clock in/out with GPS and photos
✅ Labor tracking with overtime and drive time
✅ Stage enforcement with manager override

---

## Phase 5: Orders & Procurement

**Goal**: Supplier management, full PO lifecycle, procurement planner with optimization.

### Database (`migrations/005_orders.sql`)
- `purchase_orders` — po_number, supplier_id, status (draft→submitted→partial→received→closed), optimization metadata
- `po_line_items` — part_id, qty_ordered, qty_received, unit_price

### Key Components
- Full PO lifecycle: Draft → Submitted → Partial Receive → Closed
- Receive flow routes through Guided Movement Wizard
- `ProcurementPlannerPage` — Optimization table + KPIs (savings, PO reduction, stockout risk)
- 5 optimization algorithms: Dynamic supplier ranking, EOQ + forecast, volume discounts, multi-job consolidation, MILP (PuLP)
- `SupplierReturnsWizard` — Specialized wizard with RMA step

### Phase 5 Deliverable
✅ Supplier CRUD with reliability scores
✅ Full PO lifecycle
✅ Guided receive flow
✅ Procurement planner with optimization suggestions
✅ Returns with supplier chain tracking

---

## Future Phases (Outline)

| Phase | Focus | Key Deliverables |
|-------|-------|-----------------|
| 6 | Trucks (Full) | Truck CRUD, tools tracking, maintenance schedule, service history, mileage |
| 7 | People (Full) | Employee detail, certifications, hat management UI, permission matrix |
| 8 | Reports & Export | Pre-billing bundles, timesheets, labor overview, CSV/PDF export, period locking |
| 9 | Chat | Per-job group chat, DMs, mentions, timeline integration |
| 10 | AI Integration | LM Studio connection, 30 read-only tools, audit/admin/reminder agents |
| 11 | PWA & Desktop | Service worker, offline caching, Electron/Tauri wrapper |
| 12 | Sync | File-based sync (Drive/OneDrive), conflict detection, mobile offline queue |

---

## Critical Files (Most Important to Get Right)

| File | Why |
|------|-----|
| `backend/app/migrations/001_foundation.sql` | Foundation schema — users, hats, permissions, devices. Everything depends on this. |
| `backend/app/services/movement_service.py` | Atomic stock moves with supplier chain. THE core business rule. |
| `backend/app/middleware/auth.py` | Device auto-login + PIN + JWT + permission checking. Gates everything. |
| `frontend/src/lib/navigation.ts` | Single source of truth for all modules, tabs, and permission requirements. |
| `frontend/src/components/layout/AppShell.tsx` | Main layout orchestrating sidebar + topbar + tabbar + content. |
| `frontend/src/features/warehouse/components/GuidedMovementWizard.tsx` | THE movement UI — used for every stock move in the entire app. |

---

## Design System Summary

```
Colors:
  Primary:      #3B82F6 (blue-500)
  Success:      #22C55E (green-500)
  Warning:      #F59E0B (amber-500)
  Danger:       #EF4444 (red-500)
  Background:   white / slate-950 (dark)
  Sidebar:      slate-50 / gray-900 (dark)
  Surface:      white / gray-800 (dark)

Typography:
  Font:         Inter (Google Fonts)
  Headings:     font-semibold
  Body:         font-normal text-gray-700 dark:text-gray-300

Components:
  Buttons:      Rounded-lg, subtle shadow, hover states
  Cards:        bg-white dark:bg-gray-800, rounded-xl, shadow-sm, border
  Tables:       Zebra stripe, hover highlight, sticky header
  Modals:       Centered overlay, max-w-2xl, rounded-2xl
  Badges:       Rounded-full, color-coded by status
  Inputs:       Rounded-lg, border-gray-300, focus:ring-primary-500
```

---

## Verification Plan

### After Phase 1 (Foundation)
1. `cd backend && pip install -r requirements.txt && uvicorn app.main:app --reload` — API docs at `/docs`
2. `cd frontend && npm install && npm run dev` — App at `localhost:5173`
3. Open browser → should auto-login as Admin (device fingerprint created)
4. Click every sidebar item → each module loads its stub page
5. Click sub-tabs within each module → correct stubs load
6. Toggle dark mode → entire app switches theme
7. Create a Worker user via API → login as Worker → confirm restricted sidebar items
8. Run `cd backend && pytest` → all auth + permission tests pass
9. Run `cd frontend && npm run test` → all component tests pass

### After Each Subsequent Phase
- Backend: `pytest` with phase-specific test files
- Frontend: `npm run test` with component tests
- Manual: Walkthrough checklist in `directives/testing/phase_N_checklist.md`
- Verify permissions: Test each new feature as Admin, Worker, and Grunt

---

## Areas of Improvement Flagged

1. **Device fingerprinting**: Browser localStorage is not cryptographically secure. Consider WebAuthn for production.
2. **Photo storage**: File paths need sync strategy for multi-device. Consider SQLite BLOBs for small photos.
3. **SQLite concurrency**: WAL mode helps, but 5-20 users hitting one SQLite via FastAPI needs careful write handling.
4. **Generated columns**: `company_sell_price GENERATED ALWAYS AS ... STORED` requires SQLite 3.31.0+ — verify Python's bundled SQLite version.
5. **3-layer architecture fit**: `directives/` and `execution/` are for AI orchestration tasks. App code lives in `backend/` + `frontend/`. Create `directives/app_development/` for dev SOPs.
