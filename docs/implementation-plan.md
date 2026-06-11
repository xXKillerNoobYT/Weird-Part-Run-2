# Wired-Part: Full Implementation Plan

> **Paperclip staging authority (2026-05-26):** For new agent execution, use `docs/plans/staged-paperclip-goals.md` as the ordering source. Stage 1 is the only active implementation focus: app shell, identity, local DB, onboarding, and navigation. Stages 2-10 are planned/backlog until Isaac/Paperclip explicitly promotes them. Older phase/status labels below are historical implementation context, not permission to start later-stage work.

> **Last updated:** 2026-03-15
> **Status:** Phases 1–10 complete + Phase 9 Chat & Q&A complete + V1.0 infra (A–D) + gap closure M1-M4 (44/44 done) + scheduling enhancements (035) + all 13 feature audits complete + **Phase 17 orders audit closure complete (5/5 gaps)** + **Phases 13-15 Windows AI/App/Cleanup complete (Option B: Tauri/React, llama.cpp AI)**. V1.0.0 remaining: mobile builds (Tasks 16-18) + smoke test (22) + release packaging (23) + MSVC Build Tools for Windows Tauri build + approved Phase 16 add-ons (UX/Admin Hub + Multi-Warehouse/Trailers).
> **Full vision document:** `docs/The Full Plan.md`
> **New phase numbering:** Starting 2026-03-07, future phases use new numbering (Phase 7-13). Old phase files keep their original names.
> 100% local and offline first, no customer-facing billing, bookkeeper handles billouts via pre-billing export bundles.
## Context

Wired-Part is a field service management app for an electrical contracting company. It manages parts inventory, warehouse operations, truck inventories, job tracking, labor hours, procurement, and pre-billing exports for the bookkeeper. The full specification lives in `docs/The Full Plan.md` (1100+ lines). This plan tracks the phased build from foundation to production.

**Design principles:** 100% local, offline-first, human-guided, no customer-facing billing (bookkeeper handles all billouts via pre-billing export bundles).

---

## Current State (2026-03-07)

| Metric | Count |
|--------|-------|
| Backend routers | 19 (all mounted in `main.py`) |
| API endpoints | ~500 |
| Backend services | 30 |
| Repositories | 21 + base |
| Model files | 18 |
| Migrations | 38 (`001_foundation.sql` → `038_chat_system.sql`) |
| Frontend feature files | ~200 |
| Frontend routes | 104 |
| Functional pages | 89 |
| Stub pages | 1 (DeviceManagementPage — v2.0+ placeholder) |
| API client files | 19 (~350 functions) |
| Zustand stores | 4 (auth, clock, sidebar, theme) |
| Backend tests | 10 files, 125 tests (critical paths covered) |
| Total backend LOC | ~36,000 |
| Total frontend files | ~240+ |
| Gap closure | 44/44 items complete (M1-M4) |
| Feature audits | 13/13 complete (`docs/plans/Audit/`) |
| Post-audit enhancements | Scheduling lunch/supervisor/multi-job (Migration 035) |

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
| **Ordering** | Two-tier: JPO (field request) → PO (office purchase). Unified order form. |
| **Movements** | Both direct and staged patterns. ALL via Guided Movement Wizard (human-only, never auto). |
| **Job Detail** | Opens to Notebook/Notes first (field worker priority). |
| **Trucks** | Full dashboard: inventory + tools + maintenance schedule + service history + mileage. |
| **People** | Employees, customers, GCs, flexible contacts. Hat-based permissions. |
| **Build Order** | Full foundation first (DB + Auth + Nav shell), THEN features one by one. |
| **Parts Hierarchy** | Category → Style → Type → Color = one orderable variant. General parts vs Branded parts. |
| **Suppliers** | 3-tier contacts: Business Contact → Sales Rep → Delivery Driver. Brand-supplier many-to-many. |

---

## Tech Stack

```
Backend:   Python 3.12 + FastAPI + SQLite (aiosqlite) + Pydantic v2
Frontend:  React 19 + TypeScript + Vite + Tailwind CSS v4
State:     Zustand (UI state) + TanStack Query (server state)
Icons:     Lucide React
Mobile:    Capacitor + @capacitor-community/sqlite + TypeScript data layer
Offline:   Every device runs the full program with its own local SQLite database
Sync:      LAN HTTP push/pull between devices and shop (V1.0)
Desktop:   Web browser → shop server over LAN (always on-site)
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
│   │   │   └── parts.py
│   │   ├── routers/                   # FastAPI route modules
│   │   │   ├── __init__.py
│   │   │   ├── auth.py
│   │   │   ├── dashboard.py
│   │   │   ├── parts.py
│   │   │   └── app_settings.py
│   │   ├── repositories/             # Data access layer
│   │   │   ├── __init__.py
│   │   │   ├── base.py
│   │   │   ├── user_repo.py
│   │   │   ├── device_repo.py
│   │   │   ├── settings_repo.py
│   │   │   ├── hierarchy_repo.py      # Part hierarchy + brand-supplier link repos
│   │   │   └── parts_repo.py          # Parts, brands, suppliers repos
│   │   ├── services/                 # Business logic
│   │   │   └── __init__.py
│   │   ├── middleware/
│   │   │   ├── __init__.py
│   │   │   └── auth.py               # JWT + permission dependencies
│   │   └── migrations/               # Numbered SQL files
│   │       ├── 001_foundation.sql
│   │       ├── 002_parts_and_inventory.sql
│   │       └── 003_hierarchy_images.sql
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
│   │   │   ├── parts.ts              # Hierarchy, catalog, brands, suppliers, links
│   │   │   └── settings.ts
│   │   ├── components/
│   │   │   ├── layout/
│   │   │   │   ├── AppShell.tsx
│   │   │   │   ├── Sidebar.tsx
│   │   │   │   ├── SidebarItem.tsx
│   │   │   │   ├── TopBar.tsx
│   │   │   │   ├── TabBar.tsx
│   │   │   │   └── MobileMenu.tsx
│   │   │   ├── ui/
│   │   │   │   ├── Button.tsx
│   │   │   │   ├── Card.tsx
│   │   │   │   ├── Input.tsx
│   │   │   │   ├── Badge.tsx
│   │   │   │   ├── Modal.tsx
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
│   │   │       ├── NotificationBell.tsx
│   │   │       └── ThemeToggle.tsx
│   │   ├── features/                  # One folder per module
│   │   │   ├── dashboard/
│   │   │   │   └── pages/DashboardPage.tsx
│   │   │   ├── parts/
│   │   │   │   └── pages/
│   │   │   │       ├── CategoriesPage.tsx     # Split-pane tree editor
│   │   │   │       ├── CatalogPage.tsx        # Dual view: card grid + table
│   │   │   │       ├── BrandsPage.tsx
│   │   │   │       ├── SuppliersPage.tsx
│   │   │   │       ├── PricingPage.tsx
│   │   │   │       ├── ForecastingPage.tsx
│   │   │   │       └── ImportExportPage.tsx
│   │   │   ├── warehouse/
│   │   │   ├── trucks/
│   │   │   ├── jobs/
│   │   │   ├── orders/
│   │   │   ├── people/
│   │   │   ├── reports/
│   │   │   └── settings/
│   │   ├── stores/
│   │   │   ├── auth-store.ts
│   │   │   ├── theme-store.ts
│   │   │   └── sidebar-store.ts
│   │   └── lib/
│   │       ├── types.ts               # All TypeScript interfaces
│   │       ├── navigation.ts
│   │       ├── constants.ts
│   │       └── utils.ts
│   ├── vite.config.ts
│   ├── tsconfig.json
│   └── package.json
├── docs/
│   └── implementation-plan.md         # THIS PLAN
├── directives/
├── execution/
├── .tmp/
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
📦 Parts                   Categories                      Split-pane tree editor (hierarchy CRUD + type-color links)
                           Catalog                         Dual view: product card grid + table + CRUD
                           Brands                          Brand list + supplier links management
                           Suppliers                       Supplier cards + brands carried + contacts
                           Pricing                         Inline price editing (perm-gated)
                           Forecasting                     ADU, days-to-low, suggested orders
                           Import/Export                   CSV upload & download
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
📋 Jobs                    Active Jobs                     Job cards with filters + "Take Me There" nav
                           My Clock                        Active clock view / clock into a job
                           (Job #{id})                     → Opens job detail with sub-tabs:
                             → Overview                      Job info, address, GPS navigate
                             → Labor                         Clock entries + hours
                             → Parts                         Consumed parts list
                             → Reports                       Daily reports for this job
                             → One-Time Qs                   Boss-to-worker one-time questions
                           Reports                         All daily reports across jobs (date-filtered)
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

## Phase 1: Foundation ✅ COMPLETE

**Goal**: Standing app with DB, auth, full navigation shell, theme system. Every page exists (stubs). Backend serves API. Frontend renders everything.

### Deliverables (all verified working)
- ✅ Backend running at `localhost:8000` with API docs at `/docs`
- ✅ Frontend running at `localhost:5173` with full navigation shell
- ✅ Auto-login works on assigned devices
- ✅ PIN login works on public devices
- ✅ All 9 sidebar modules navigate correctly with sub-tabs
- ✅ Dark/light theme switching works
- ✅ Permission-gated nav items hidden for non-admin users
- ✅ Migration `001_foundation.sql`: users, hats, permissions, devices, settings, activity_log, notifications

---

## Phase 2: Parts & Inventory Core ✅ COMPLETE

**Goal**: Full Parts Catalog with hierarchy-aware CRUD, search, filter, brands, suppliers, pricing, stock model, forecasting, and import/export.

### Data Model — Parts Hierarchy

The electrical parts domain follows a strict hierarchy: **Category → Style → Type → Color**. Each valid combination equals one orderable variant (SKU). Parts are either **general** (no brand, no manufacturer part number, code optional) or **specific** (branded, with manufacturer part number that may be pending).

```
Hierarchy Tables:
  part_categories  — Top-level grouping (Outlet, Switch, Wire, Breaker…)
  part_styles      — Per-category visual style (Decora, Traditional…)
  part_types       — Per-style functional variety (GFI, Tamper Resistant…)
  part_colors      — Global color lookup (White, Black, Light Almond…)

Brand-Supplier Links:
  brand_supplier_links — Which suppliers carry which brands (many-to-many)

Parts Table:
  category_id (required), style_id, type_id, color_id (hierarchy FKs)
  code (nullable — general parts don't need codes)
  part_type: 'general' | 'specific'
  brand_id, manufacturer_part_number (for specific parts)
  company_sell_price = GENERATED ALWAYS AS (cost × (1 + markup/100))
  UNIQUE constraint on (category, style, type, color, brand) with COALESCE for NULLs
  Partial index for "Pending Part Numbers" (specific parts with NULL MPN)
```

### Database (`migrations/002_parts_and_inventory.sql`)
- `part_categories` — 12 seeded: Outlet, Switch, Cover Plate, Wire, Breaker, Panel, Junction Box, Conduit, Fitting, Connector, Light Fixture, Misc
- `part_styles` — seeded per category (Decora/Traditional for Outlet, Switch, Cover Plate)
- `part_types` — seeded per style (Standard, GFI, Tamper Resistant, etc.)
- `part_colors` — 10 seeded with hex codes (White, Black, Light Almond, Gray, Ivory, etc.)
- `brands` — 10 seeded (Southwire, Leviton, Square D, Eaton, Ideal, etc.)
- `suppliers` — schema with 3-tier contacts (business, sales rep, delivery driver), delivery logistics, reliability metrics
- `parts` — hierarchy-aware with GENERATED sell price
- `part_supplier_links` — part-supplier pricing links
- `brand_supplier_links` — brand-supplier many-to-many
- `stock` — location-based inventory (warehouse, pulled, truck, job)
- `stock_movements` — movement history with supplier chain tracking
- `part_forecast_history` — forecast snapshots

### Backend Implementation

**New File: `backend/app/repositories/hierarchy_repo.py`**
Five repo classes extending BaseRepo:
- `PartCategoryRepo` — `get_all_with_counts()`, standard CRUD
- `PartStyleRepo` — `get_by_category()`, CRUD
- `PartTypeRepo` — `get_by_style()`, CRUD
- `PartColorRepo` — `get_all_with_counts()`, CRUD
- `BrandSupplierLinkRepo` — `get_by_brand()`, `get_by_supplier()`, CRUD

**Modified: `backend/app/repositories/parts_repo.py`**
- `PartsRepo.search()` — JOINs hierarchy tables, supports 10+ filter params
- `PartsRepo.get_by_id_full()` — JOINs hierarchy for names, includes supplier links
- `PartsRepo.get_pending_part_numbers()` and `count_pending_part_numbers()`
- `BrandRepo.get_all_with_counts()` — includes `supplier_count` from brand_supplier_links
- `SupplierRepo.get_all_filtered()` — includes `brand_count`
- Constants: `STOCK_SUBQUERY`, `HIERARCHY_JOINS` for DRY SQL reuse

**Modified: `backend/app/models/parts.py`**
- Hierarchy models: `PartCategory{Create,Update,Response}`, same for Style, Type, Color
- `BrandSupplierLink{Create,Response}`, `PendingPartNumberItem`
- Updated `PartCreate/Update/Response/ListItem/SearchParams` with hierarchy fields
- `CatalogStats` includes `unique_categories`, `pending_part_numbers`

### API Endpoints

```
HIERARCHY:
  GET     /api/parts/hierarchy                    — Nested JSON tree for cascading dropdowns
  GET/POST /api/parts/categories                  — Category CRUD
  PUT/DEL  /api/parts/categories/{id}
  GET      /api/parts/categories/{cat_id}/styles  — Styles scoped to category
  POST/PUT/DEL /api/parts/styles[/{id}]
  GET      /api/parts/styles/{style_id}/types     — Types scoped to style
  POST/PUT/DEL /api/parts/types[/{id}]
  GET/POST /api/parts/colors                      — Color CRUD
  PUT/DEL  /api/parts/colors/{id}

CATALOG:
  GET      /api/parts/catalog                     — Search with hierarchy filters, pagination, sort
  POST     /api/parts/catalog                     — Create part (validates hierarchy FKs, UNIQUE check)
  GET/PUT/DEL /api/parts/catalog/{id}             — Single part CRUD
  GET      /api/parts/catalog/stats               — Summary stats (total, deprecated, pending, etc.)
  PUT      /api/parts/catalog/{id}/pricing        — Price update (perm-gated)
  GET      /api/parts/catalog/{id}/stock          — Stock by location
  GET      /api/parts/catalog/{id}/stock/summary  — Aggregated stock summary
  POST/DEL /api/parts/catalog/{id}/suppliers[/{linkId}] — Part-supplier links

PENDING PART NUMBERS:
  GET      /api/parts/pending-part-numbers        — Paginated list of branded parts missing MPN
  GET      /api/parts/pending-part-numbers/count   — Badge count

BRANDS:
  GET/POST /api/parts/brands                      — Brand CRUD (includes supplier_count)
  GET/PUT/DEL /api/parts/brands/{id}
  GET      /api/parts/brands/{id}/suppliers       — Suppliers carrying this brand

SUPPLIERS:
  GET/POST /api/parts/suppliers                   — Supplier CRUD (includes brand_count)
  PUT/DEL  /api/parts/suppliers/{id}
  GET      /api/parts/suppliers/{id}/brands       — Brands carried by supplier

BRAND-SUPPLIER LINKS:
  POST     /api/parts/brand-supplier-links        — Create link
  DEL      /api/parts/brand-supplier-links/{id}   — Delete link

FORECASTING:
  GET      /api/parts/forecasting                 — Paginated forecast data

IMPORT/EXPORT:
  GET      /api/parts/export                      — CSV download (includes hierarchy columns)
  POST     /api/parts/import                      — CSV upload
```

### Frontend Implementation

**`frontend/src/lib/types.ts`** — All TypeScript interfaces:
- Hierarchy: `PartCategory`, `PartStyle`, `PartType`, `PartColor` (each with Create/Update)
- Tree: `HierarchyTree`, `HierarchyCategory`, `HierarchyStyle`, `HierarchyType`, `HierarchyColor`
- Links: `BrandSupplierLink`, `BrandSupplierLinkCreate`, `PartSupplierLink`, `PartSupplierLinkCreate`
- Parts: `Part`, `PartListItem`, `PartCreate`, `PartUpdate`, `PartSearchParams`, `PendingPartNumberItem`
- Stock: `StockEntry`, `StockSummary`
- Others: `CatalogStats`, `ForecastItem`, `ImportResult`

**`frontend/src/api/parts.ts`** — API client functions:
- Hierarchy CRUD: `getHierarchy()`, category/style/type/color CRUD, scoped list queries
- Pending: `getPendingPartNumbers()`, `getPendingPartNumbersCount()`
- Brand-supplier: `getBrandSuppliers()`, `getSupplierBrands()`, `createBrandSupplierLink()`, `deleteBrandSupplierLink()`
- All existing functions preserved

**`CatalogPage.tsx`** — Complete rebuild:
- Cascading hierarchy filter dropdowns (Category → Style → Type → Color)
- Brand filter, part_type filter, checkboxes for deprecated/QR/low-stock
- Pending Part Numbers badge (amber, toggleable filter)
- Table: Category | Style | Type | Color | Name | Code | Brand | Stock | Cost | Sell | Status | Actions
- Warning icon for pending MPN parts, "—" for nullable codes
- 3-section form: Part Classification, Part Identity, Pricing & Stock Levels
- Conditional brand/MPN fields for specific parts

**`BrandsPage.tsx`** — Enhanced:
- Expandable rows showing supplier links per brand
- "Link Supplier" inline form with dropdown of unlinked suppliers
- Account number and notes per link
- Unlink button per supplier
- New "Suppliers" column showing count

**`SuppliersPage.tsx`** — Enhanced:
- "Brands Carried" section in expanded detail showing linked brands
- Brand count in header quick-info line
- Chip-style brand badges with account numbers

**`PricingPage.tsx`** — Updated:
- Added Category column
- Nullable code handling (`code ?? '—'`)

**`ForecastingPage.tsx`** — Updated:
- Added Category and Brand columns
- Nullable code handling
- Enhanced search (searches category + brand names too)

**`ImportExportPage.tsx`** — Updated:
- CSV template includes `category_id` column
- Updated description to reflect hierarchy-based matching
- Export includes hierarchy columns

### Phase 2 Deliverables
- ✅ Parts hierarchy: Category → Style → Type → Color with cascading UI
- ✅ General vs Specific parts (branded parts need MPN, general don't need code)
- ✅ Pending Part Numbers queue with badge count
- ✅ Brand-supplier many-to-many links (manageable from both BrandsPage and SuppliersPage)
- ✅ Full catalog CRUD with hierarchy filters, search, sort, pagination
- ✅ Duplicate variant prevention (UNIQUE index with COALESCE for NULLs)
- ✅ 3-tier supplier contacts (business, sales rep, delivery driver)
- ✅ Pricing with permission gating (show_dollar_values, edit_pricing)
- ✅ Forecasting with urgency-sorted display
- ✅ CSV import/export with hierarchy columns
- ✅ All 21 backend API integration tests passing

---

## Phase 2.5: Parts Hierarchy UX Redesign ✅ COMPLETE

**Goal**: Redesign the Parts module UI based on user feedback — add a dedicated Categories tree editor, type-color junction table management, grouped product card view on catalog, and image_url fields for future file uploads.

### Design Decisions (User-Confirmed)

| Decision | Choice |
|----------|--------|
| **Type-Color linking** | Junction table (`type_color_links`) — explicitly defines which colors are valid per part type |
| **Images** | `image_url` text fields now on all hierarchy levels + type_color_links; file upload later |
| **Categories editor** | Split-pane: read-only tree nav on left, edit form on right |
| **Categories access** | Both a dedicated `/parts/categories` tab AND inline quick-add on catalog page |
| **Catalog view mode** | Toggle between product card grid and flat table view |
| **Product grouping** | Cards grouped by `(category_id, brand_id)` — General = 1 card, each brand = separate card |
| **Image cascade** | `type_color_link.image_url → type.image_url → style.image_url → category.image_url` |

### Database (`migrations/003_hierarchy_images.sql`)
- Added `image_url TEXT` to: `part_categories`, `part_styles`, `part_types`, `part_colors`
- Added `image_url TEXT` and `sort_order INTEGER DEFAULT 0` to `type_color_links`

### Backend Changes

**Modified: `backend/app/repositories/hierarchy_repo.py`**
- Added `TypeColorLinkRepo` — `get_by_type()`, `get_by_color()`, `link_exists()`, `bulk_link()`, `unlink()`

**Modified: `backend/app/models/parts.py`**
- Added `TypeColorLink`, `TypeColorLinkCreate` models
- Added `CatalogGroup`, `CatalogGroupVariant` models for grouped card view
- Added `image_url` field to all hierarchy Create/Update/Response models

**Modified: `backend/app/routers/parts.py`**
- Added `GET /api/parts/types/{type_id}/colors` — colors linked to a type
- Added `POST /api/parts/types/{type_id}/colors` — bulk link colors to type
- Added `DELETE /api/parts/types/{type_id}/colors/{color_id}` — unlink color from type
- Added `GET /api/parts/catalog/groups` — grouped product cards (category × brand)

### Frontend Changes

**Modified: `frontend/src/lib/types.ts`**
- Added `TypeColorLink`, `CatalogGroup`, `CatalogGroupVariant` interfaces
- Added `image_url` to all hierarchy interfaces

**Modified: `frontend/src/api/parts.ts`**
- Added `listTypeColors()`, `linkColorsToType()`, `unlinkColorFromType()`
- Added `getCatalogGroups()` for grouped card view

**Modified: `frontend/src/lib/navigation.ts`**
- Added `categories` tab as first item in Parts module

**Modified: `frontend/src/App.tsx`**
- Added `CategoriesPage` import and `/parts/categories` route

**New: `frontend/src/features/parts/pages/CategoriesPage.tsx`** (~830 lines)
- Split-pane tree editor with:
  - Left pane: collapsible Category → Style → Type tree with color chip counts
  - Right pane: edit forms for any selected node (category/style/type/color)
  - "Colors" toggle button to manage global color list
  - Type edit form includes linked color chip management (add/remove)
  - Lazy-loaded children with React Query (`enabled: isExpanded`)
  - Create forms via `+ Category`, `+ Style`, `+ Type` buttons

**Rebuilt: `frontend/src/features/parts/pages/CatalogPage.tsx`** (~670 lines)
- Dual view mode toggle (card grid / table):
  - **Card grid**: Uses `getCatalogGroups` API, responsive 1/2/3 column grid
  - **Table**: Uses `listParts` API with full hierarchy column headers
- Product cards show: category icon, brand badge, variant count, stock summary, price range
- Expandable cards reveal variant table with individual part details
- Pending PN filter auto-switches to table mode (groups API doesn't support it)
- Filters adapt to view mode (fewer filters in card mode)

### Phase 2.5 Deliverables
- ✅ Categories tab with split-pane tree editor (Category → Style → Type → Color)
- ✅ Type-color junction table management (linked colors as chips, add/remove inline)
- ✅ Catalog dual view: product card grid + flat table with toggle
- ✅ Product cards grouped by (category, brand) — General parts separate from branded
- ✅ `image_url` fields on all hierarchy tables (ready for Phase 3+ file upload)
- ✅ Migration 003 applied cleanly
- ✅ All existing pages (Pricing, Forecasting, Import/Export, Brands, Suppliers) still work

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

## Phase 3.5: Companions, Alternatives & Warehouse Enhancements ✅ COMPLETE

**Goal**: Fill gaps discovered during Phase 3 — companion part suggestions, part alternatives, QR scanning enhancements, warehouse exec view, and hierarchy UX improvements.

### Database
- **Migration 007** (`companions_and_alternatives.sql`):
  - `companion_rules` — explicit companion relationships (part A → suggest part B)
  - `companion_co_occurrence` — implicit suggestions learned from movement history
  - `companion_feedback` — user accept/reject signals for ML-style ranking
  - `part_alternatives` — substitute/upgrade/compatible links between parts
- **Migration 008** (`bin_location.sql`):
  - Added `bin_location TEXT` column to `parts` table

### Backend Implementation
- `companions_service.py` — Rule-based + co-occurrence companion suggestions, feedback tracking
- `companions_repo.py` — Data access for companion rules, co-occurrence mining, feedback
- `alternatives_repo.py` — Part alternatives CRUD (substitute, upgrade, compatible types)
- `companions.py` router — Full CRUD + suggestion endpoints

### Frontend Implementation
- **`CompanionsPage.tsx`** — Manage companion rules, view co-occurrence suggestions, review feedback
- **`AlternativesSection.tsx`** — Part alternatives viewer (in part detail)
- **`LinkAlternativeModal.tsx`** — Modal to search and link alternative parts
- **`WarehouseExecPage.tsx`** — Office/Warehouse exec spreadsheet view with inline editing
- **`QRScannerBubble.tsx`** — Floating QR scanner for the movement wizard Step 2
- **`qr-utils.ts`** — QR code generation and parsing utilities
- **`QRLabelModal.tsx`** — Print QR labels from inventory grid
- **`PartDetailPanel.tsx`** — Expanded part detail panel in categories tree
- **`BrandColorPanel.tsx`** — Brand color management panel

### Phase 3.5 Deliverables
- ✅ Companion rules with co-occurrence mining and feedback loop
- ✅ Part alternatives (substitute/upgrade/compatible) with search + link UI
- ✅ Warehouse Exec spreadsheet view for office managers
- ✅ QR Scanner Bubble integrated into movement wizard
- ✅ QR Label printing from inventory grid (`is_qr_tagged` tracking)
- ✅ Bin location field on parts
- ✅ Part detail panel in categories tree
- ✅ Brand-color management panel

---

## Phase 4: Jobs & Labor ✅ COMPLETE

**Goal**: Job CRUD, clock in/out with GPS, customizable clock-out questionnaires (global + one-time per-job), labor tracking with hours calculation, and auto-generated daily reports at midnight.

### Database

**Migration 009** (`009_jobs_and_labor.sql`):
- `jobs` — job_number, job_name, customer_name, address (line1/2, city, state, zip), GPS coordinates, status (active/on_hold/completed/cancelled), priority, job_type (service/new_construction/remodel/maintenance/emergency), billing_rate, estimated_hours, lead_user_id
- `job_parts` — consumption tracking with cost snapshots at time of consume
- `labor_entries` — clock_in/out times, regular_hours, overtime_hours, drive_time_minutes, GPS lat/lng for both in/out, photo paths, status lifecycle (clocked_in→clocked_out→edited→approved)

**Migration 010** (`010_clockout_and_reports.sql`):
- `clock_out_questions` — Global boss-managed question templates (text/yes_no/photo types), sort_order, required flag, active flag. Seeded with 8 default electrician questions.
- `one_time_questions` — Per-job questions that the boss can fire at specific workers (or all workers on a job). Asked once, then marked answered.
- `clock_out_responses` — Answers to global questions per labor entry (text, boolean, photo)
- `daily_reports` — Auto-generated at midnight, stores full report as JSON blob, status lifecycle (generated→reviewed→locked). UNIQUE on (job_id, report_date).

### Backend Implementation

**Services:**
- `job_service.py` — Job CRUD, status lifecycle transitions, address/GPS management
- `labor_service.py` — Clock in/out with GPS capture, automatic hours calculation (regular + overtime based on 8hr threshold), active clock lookup, labor queries by job or user
- `questionnaire_service.py` — Global question CRUD + reorder, one-time question lifecycle (create→show→answer), clock-out bundle assembly (combines global + one-time questions in single response)
- `report_service.py` — Daily report generation: assembles worker data + question responses + parts consumed + cost summary into structured JSON. Generates for all jobs with activity on a given date.

**Scheduler:**
- `scheduler.py` — APScheduler with `AsyncIOScheduler`, midnight cron job at 00:05 to generate daily reports. Includes startup catch-up logic to generate any missed reports (server was down at midnight).

**API Endpoints (26 endpoints replacing stubs):**
```
JOBS:     GET /active, POST /, GET /{id}, PUT /{id}, PATCH /{id}/status
LABOR:    POST /{id}/clock-in, POST /clock-out, GET /{id}/labor, GET /my-clock
PARTS:    GET /{id}/parts, POST /{id}/parts/consume
QUESTIONS: GET/POST /questions/global, PUT /questions/global/reorder, DELETE /questions/global/{id}
           GET/POST /{id}/questions/one-time, POST /questions/one-time/{id}/answer
           GET /{id}/clock-out-bundle
REPORTS:  GET /{id}/reports, GET /{id}/reports/{date}, POST /reports/generate-now, GET /reports/all
```

### Frontend Implementation

**Pages (6 new):**
- `ActiveJobsPage.tsx` — Job cards with status/type/priority filters, "Take Me There" Google Maps navigation, clock-in button per job
- `MyClockPage.tsx` — Active clock view with running timer, or "Not clocked in" state with job list to clock into. Clock-out button navigates to JobDetailPage with startClockOut intent.
- `JobDetailPage.tsx` — Full job view with 5 internal sub-tabs (Overview, Labor, Parts, Reports, One-Time Qs). Integrates ClockOutFlow as overlay. Shows "clocked in" banner when worker is on this job.
- `JobReportsListPage.tsx` — All daily reports across all jobs, grouped by date, with date range filtering
- `DailyReportView.tsx` — Read-only "locked notebook page" renderer: worker cards with times/GPS/question responses, parts consumed table, cost summary
- `ClockOutQuestionsPage.tsx` (in Settings) — Admin page for global question CRUD with up/down reorder, inline edit, soft-delete

**Components:**
- `JobCard.tsx` — Job card with address, status badge, navigate button, clock-in action
- `ClockOutFlow.tsx` — Multi-step clock-out wizard: Step 1 (answer all questions) → Step 2 (review + GPS + confirm)

**Stores:**
- `clock-store.ts` — Zustand store tracking active clock state, elapsed-time timer (updates every second), clock-in/out actions with backend sync

**Navigation:**
- Jobs module tabs: Active Jobs, **My Clock**, **Reports**, Templates
- Settings module: added **Clock-Out Questions** tab

### Phase 4 Deliverables
- ✅ Full job CRUD with address, GPS, status lifecycle, priority, job type
- ✅ "Take Me There" Google Maps navigation from job cards and detail page
- ✅ Clock in/out with GPS capture and location display
- ✅ Labor tracking with automatic hours calculation (regular + overtime)
- ✅ Customizable global clock-out questionnaire (8 seeded questions)
- ✅ One-time per-job questions (boss → specific worker or all workers)
- ✅ Clock-out bundle API (single request for all questions)
- ✅ Multi-step clock-out flow with question cards, yes/no toggles, review step
- ✅ Daily reports auto-generated at midnight via APScheduler
- ✅ Startup catch-up for missed reports
- ✅ Locked daily report viewer with worker details, responses, and parts consumed
- ✅ Job detail page with 5 internal sub-tabs
- ✅ Real-time elapsed clock timer in Zustand store

---

## Phase 5: Orders & Procurement ✅ COMPLETE

**Goal**: Two-tier ordering (JPO → PO), receiving, returns/RMA, procurement optimization.

> **Detailed plan:** `docs/plans/phase-5-orders-procurement.md`

### Database (`migrations/015_orders_procurement.sql`, `016_null_color.sql`)
- `job_parts_orders` (JPOs), `jpo_line_items`, `purchase_orders`, `po_line_items`
- `staging_zones`, `returns`, `return_line_items`
- `order_status_history`, `supplier_contact_ratings`, `price_history`, `company_profiles`

### Backend — 71 endpoints at `/api/orders` (largest router)
- **7 services**: orders_service, receiving_service, procurement_service, returns_service, pdf_service, po_conversation_service, job_preferences_service
- **6 repo classes** in orders_repo.py
- JPO lifecycle: draft → pending_approval → approved → ordering → closed
- PO lifecycle: draft → submitted → acknowledged → partially_received → received → closed
- Returns: job→warehouse + warehouse→supplier RMA flow
- Procurement: reorder suggestions, supplier ranking, grouped suggestions

### Frontend — 17+ pages
- `PartsRequestsPage` (JPO list), `UnifiedOrderPage` (Phase 7A), `PurchaseOrdersPage`
- `NewPurchaseOrderPage`, `ReceiveShipmentPage`, `ReturnsPage`, `NewReturnPage`, `ReturnDetailPage`
- `ProcurementPage`, `JPODetailPage`, `PODetailPage`, `GeneratePOsPage`
- Office tabs: `ApprovalsTab`, `POManagementTab`, `ReviewAndSendPage`

### Phase 5 Deliverables ✅
- Two-tier ordering (JPO for field, PO for office) ✅
- Full PO lifecycle with status transitions ✅
- Procurement planner with supplier ranking ✅
- Returns with RMA and supplier chain tracking ✅
- Price history and supplier contact ratings ✅
- Company profiles for PO branding ✅

---

## Phase 6: Fleet & Vehicle Management ✅ Complete

**Goal**: Full vehicle management — CRUD, driver assignments, per-vehicle inventory, delivery tracking, maintenance scheduling with service history, mileage logging with trip legs, private vehicle reimbursement, warehouse locations, and fleet dashboard.

**Detailed plan**: `docs/plans/phase-6-fleet-vehicles.md`

### Database (`migrations/017_fleet_vehicles.sql`) — 10 new tables
- `vehicles` — vehicle_number, vehicle_name, vehicle_type (company_truck/van/car/private_vehicle), status, make, model, year, vin, license_plate, insurance, odometer, owner_user_id
- `vehicle_assignments` — vehicle_id, user_id, assignment_type, is_take_home, home_to_shop_miles, home_address, start/end dates
- `warehouse_locations` — name, address, gps coordinates, is_primary, company_profile_id
- `vehicle_delivery_items` — vehicle_id, job_id, part_id, qty_assigned/delivered, status (assigned/loaded/in_transit/delivered/returned)
- `maintenance_types` — configurable lookup (13 seeded types: oil change, tire rotation, brake inspection, etc.)
- `vehicle_maintenance_schedules` — per-vehicle intervals (miles/months), next due tracking
- `vehicle_maintenance_records` — service history with cost, vendor, invoice
- `vehicle_mileage_logs` — daily odometer readings per vehicle/driver
- `vehicle_trip_legs` — trip segments with estimated/actual miles + drive time, billable flag
- `mileage_reimbursements` — private vehicle payback (IRS rate)

### Backend — ~35 endpoints at `/api/trucks`
- **4 services**: vehicle_service, delivery_service, maintenance_service, mileage_service
- **10 repo classes**: VehicleRepo, VehicleAssignmentRepo, WarehouseLocationRepo, VehicleDeliveryRepo, MaintenanceTypeRepo, MaintenanceScheduleRepo, MaintenanceRecordRepo, MileageLogRepo, TripLegRepo, ReimbursementRepo
- **Key design**: Manual distance input (not GPS) — `home_to_shop_miles` on assignments, `distance_from_shop_miles` on jobs
- **Route ordering**: `/{vehicle_id}` catch-all registered LAST to avoid collisions with named routes

### Frontend — 7 pages + ~20 components
- `MyTruckPage` — driver dashboard with assigned vehicle, inventory, deliveries, maintenance alerts
- `AllTrucksPage` — fleet list with type/status/driver filters, search, create
- `VehicleDetailPage` — deep dive with tabbed sections
- `ToolsPage` — placeholder (coming soon)
- `MaintenancePage` — fleet-wide upcoming/overdue, log service, maintenance types admin
- `MileagePage` — daily logs, trip legs, reimbursements
- `FleetDashboardPage` — manager KPIs (total/active/maintenance vehicles, fleet miles, costs)
- `WarehouseLocationsPage` — shop address CRUD (in Office module)

### Phase 6 Deliverables ✅
- Full vehicle CRUD with 4 vehicle types (company truck/van/car, private) ✅
- Driver assignments with take-home tracking ✅
- Per-vehicle inventory via existing stock system (location_type='truck') ✅
- Job-bound delivery item tracking ✅
- Configurable maintenance types with per-vehicle scheduling ✅
- Daily mileage logging with trip leg breakdown ✅
- Manual distance-based mileage estimation (zero API cost) ✅
- Private vehicle mileage reimbursement ✅
- Warehouse/shop location management ✅
- Fleet manager dashboard with KPIs ✅
- Responsive at desktop (1280x800), tablet (768x1024), mobile (375x812) ✅

---

## Phase 9: Tools & Kits ✅ Complete

> **Plan:** `docs/plans/phase-9-tools-and-kits.md`

Tool registry with individual asset tracking, kit verification checklists, checkout/return workflow, maintenance scheduling, and QR code scanning. Tools move between warehouse ↔ truck ↔ job with full movement audit trail.

**Backend:** 8 DB tables (`tools`, `kit_templates`, `tool_movements`, `kit_verification_sessions/items`, `tool_maintenance_types/schedules/records`), 8 repository classes, ~25 service methods, ~25 API endpoints under `/api/tools`.

**Frontend:** Warehouse Tools page (global registry with stats, filters, search, QR print), Truck Tools page (per-vehicle view with checkout/return), Job Detail tools sub-tab (read-only), Warehouse Dashboard live tools summary card, QR scan redirect component.

**Key patterns:** Polymorphic `(location_type, location_id)` for tool locations (same as `stock`), vehicle maintenance cascade pattern for tool maintenance, immutable movement log (same as `stock_movements`).

### Phase 9 Deliverables ✅
- 8 DB tables with triggers, seed data, and permission seeds ✅
- Tool CRUD with category/status/location filtering ✅
- Checkout/return workflow with location + status updates ✅
- Kit templates (charger, batteries, bits, case, etc.) per tool ✅
- Kit verification sessions triggered on checkout/return ✅
- Maintenance types, per-tool schedules, service logging ✅
- QR code generation (client-side SVG) + printable labels ✅
- QR scan URL redirect (`/tools/scan/:toolNumber`) ✅
- 3 permissions: `view_tools`, `manage_tools`, `checkout_tools` ✅
- Responsive at desktop (1280×800), tablet (768×1024), mobile (375×812) ✅
- Dark mode + light mode audit passed ✅

---

## Phase 7A: Core Ordering Experience ✅ COMPLETE

**Goal**: Replace fragmented JPO/PO creation with a unified order form with smart job memory.

> **Detailed plan:** `docs/plans/orders-redesign-master-plan.md`

### Database (`migrations/018_orders_redesign_a.sql`)
- `job_preferences` — Learns brand/color/supplier patterns per job
- `special_items` — Non-catalog items added to orders
- ALTER `job_parts_orders` — order_type, has_special_items, smart_suggestions_enabled

### Backend
- `job_preferences_service.py` — Smart suggestion memory per job (brand, color, supplier patterns)
- Updated `orders_service.py` — Unified JPO creation for both job + warehouse orders

### Frontend
- `UnifiedOrderPage.tsx` — Single form for job orders + warehouse restocking with smart suggestions toggle
- Replaces the old `NewPartsRequestPage.tsx` (kept as legacy)

---

## Phase 7B: Office Workflow ✅ COMPLETE

**Goal**: PO management, approvals, PDF bundles, Review & Send for office staff.

### Database (`migrations/019_orders_redesign_b.sql`)
- `po_conversations` — CRM-style conversation threads per PO
- `po_groups`, `po_group_members` — Bundle multiple POs for single-supplier sends
- ALTER `purchase_orders` — confirmation checklist fields

### Backend
- `po_conversation_service.py` (684 lines) — Conversation threads, follow-ups, auto-logged status changes
- `pdf_service.py` (312 lines) — PO PDF generation + clipboard text for email
- Office approval endpoints: pending approvals, count, bulk approve/reject

### Frontend
- `ApprovalsTab.tsx` — Unified approval queue in Office module
- `POManagementTab.tsx` — PO management with inline conversations
- `ReviewAndSendPage.tsx` — Batch PO generation + PDF bundling

---

## Phase 7C: Warehouse Workflow ✅ COMPLETE

**Goal**: Session-based receiving, return sorting guidance.

### Database (`migrations/020_orders_redesign_c.sql`)
- `receiving_sessions`, `receiving_session_items` — Multi-item receiving sessions
- ALTER `return_line_items` — sorting disposition tracking

### Backend
- `receiving_service.py` (588 lines) — Session-based PO receiving with staging
- Return sorting: disposition guidance, eligibility checking, below-target alerts

### Frontend
- `ReceivingPage.tsx` (802 lines) — Session-based receiving in warehouse module
- `ReturnSortingPage.tsx` (713 lines) — Return triage with disposition guidance
- `ReceiveShipmentPage.tsx` (778 lines) — 3-step receiving wizard

---

## Phase 7D: Analytics & Visibility ✅ COMPLETE

**Goal**: Weighted average cost tracking, margin management, spending dashboard, job cost rollup.

> **Detailed plan:** `docs/plans/phase-7d-analytics-visibility.md`

### Database (`migrations/021_orders_redesign_d.sql`)
- `cost_layers` — FIFO/LIFO cost layer tracking per part
- `company_cost_settings` — Company-wide cost method + default markup
- ALTER `parts` — weighted_avg_cost, custom_margin fields
- ALTER `jobs` — budget_amount, budget_alert_threshold

### Backend — 18 endpoints at `/api/costs`
- `cost_tracking_service.py` (397 lines) — FIFO consumption, LIFO returns, weighted avg calculation
- `spending_service.py` (432 lines) — Spending analytics, job rollups, variance, budget alerts

### Frontend
- `SpendingDashboardPage.tsx` (576 lines) — Full cost analytics in Office module
- Job cost rollup tab in `JobDetailPage.tsx`

---

## Phase 7E: Quality of Life ✅ COMPLETE

**Goal**: Notification sounds, QR enhancements, bulk actions.

### Database (`migrations/022_orders_redesign_e.sql`)
- `notification_sounds` — Per-event sound preferences
- ALTER `parts` — QR code tracking fields

### Backend
- Sound settings endpoints in `notifications.py` router
- Bulk operation endpoints: bulk submit POs, bulk status update, bulk return approve

### Frontend
- Notification sound settings in `NotificationPrefsPage.tsx`
- Bulk action buttons across Orders pages
- QR enhancements in warehouse and tools pages

---

## Phase 8: People Full ✅ COMPLETE

**Goal**: Employee management, certifications, wages, skills, hat/role management, permission matrix.

> **Detailed plan:** `docs/plans/phase-8-people-full.md`

### Database (`migrations/023_people_full.sql`)
- `certifications` — Cert type, issue/expiry dates, issuing body
- `wage_history` — Hourly rate tracking over time (PIN-gated)
- `employee_notes` — Manager notes on employees
- `user_skills` — Skill tracking per employee

### Backend — 32 endpoints at `/api/people`
- `people_service.py` (472 lines) — Employee, cert, wage, note, skill, hat operations
- Certification expiry alerts integrated with Dashboard

### Frontend — 4 pages
- `EmployeeListPage.tsx` (439 lines) — Employee list with CRUD
- `EmployeeDetailPage.tsx` (764 lines) — Full profile with 5 sub-tabs
- `HatsPage.tsx` (539 lines) — Role/hat management with permission assignment
- `PermissionsPage.tsx` (321 lines) — Permission matrix view

---

## Phase 10: People, Contacts & Scheduling ✅ COMPLETE

**Goal**: Customers, GCs, flexible contacts, scheduling/dispatch, time-off, subcontractors.

> **Detailed plan:** `docs/plans/phase-10-people-contacts-scheduling.md`

### Database (`migrations/025-027`)
- `customers`, `general_contractors` — Company entities with contacts
- `entity_contacts` — Polymorphic contacts (works for customers, GCs, suppliers)
- `job_customers`, `job_general_contractors` — Job↔entity linking
- `employee_default_schedules`, `schedule_exceptions` — Weekly schedules + overrides
- `job_dispatch` — Employee dispatch assignments per job per day
- `subcontractor_schedules` — External subcontractor scheduling
- Permission seeds for scheduling, contacts, dispatch

### Backend — 48 endpoints across `/api/contacts` (23) + `/api/scheduling` (25)
- `contacts_service.py` (260 lines) — Customer, GC, entity contact, job-linking logic
- `scheduling_service.py` (322 lines) — Schedules, time off, dispatch, calendar assembly

### Frontend — 14 pages
- **People module**: `CustomersPage`, `CustomerDetailPage`, `ContractorsPage`, `ContractorDetailPage`, `ContactDirectoryPage`
- **Scheduling module**: `ScheduleCalendarPage`, `DailyDispatchPage`, `TimeOffPage`, `ScheduleConfigPage`, `SubSchedulePage`
- **Job Detail**: Customer + GC linking tabs

---

## Post-Audit Enhancements: Scheduling ✅ COMPLETE

**Goal**: Add lunch break scheduling, multi-job dispatch UX, and supervisor/floater role.

> **Plan file:** `docs/plans/scheduling-enhancements.md`

### Database (`migrations/035_scheduling_enhancements.sql`)
- `lunch_start`/`lunch_end` columns on: `employee_default_schedules`, `schedule_exceptions`, `shift_pattern_days`, `dispatch_templates`
- Full `job_dispatch` table recreation (CHECK constraint change for 'supervisor' + lunch columns)

### Backend — 3 files updated
- `models/scheduling.py` — 'supervisor' in DISPATCH_ROLES, lunch fields on 14 models, enriched ScheduleConflict
- `repositories/scheduling_repo.py` — Extended bulk_upsert columns, enriched conflict queries
- `services/scheduling_service.py` — Lunch propagation in 8 methods, calendar role_on_job

### Frontend — types + 4 pages
- `lib/types.ts` — 18 edits: 'supervisor' in DispatchRoleOnJob, lunch fields on 14 interfaces
- `DailyDispatchPage.tsx` — Supervisor labels/colors, lunch inputs, "Today's Assignments" panel, overlap warning
- `ScheduleConfigPage.tsx` — Lunch start/end columns in default schedule grid
- `DispatchTemplatesPage.tsx` — Lunch state/inputs on template forms
- `ScheduleCalendarPage.tsx` — Role-based color overrides (supervisor=amber, lead=indigo)

### Local Capacitor Migration
- `006_fleet_tools_scheduling.ts` — Lunch columns + supervisor CHECK on 3 tables

---

## Remaining Work

### Phase 8: Reports & Pre-Billing ✅ COMPLETE

> **Plan file:** `docs/plans/phase-11-reports-prebilling.md`

All 6 report pages fully implemented: PreBillingPage (23KB), TimesheetsPage (14KB), LaborOverviewPage (14KB), ProfitabilityPage (12KB), ExportsPage (17KB), DailyReports (in Jobs module). Period locking + bookkeeper exports (QuickBooks IIF, GL CSV, Payroll CSV) all functional.

### Legacy Cleanup ✅ COMPLETE

> **Plan file:** `docs/plans/legacy-cleanup-plan.md`

- Superseded pages redirected/removed (4 legacy order pages locked by OneDrive but have zero imports — dead code)
- Settings stubs labeled as v2.0+ placeholders
- Route cleanup completed

### Testing Strategy ✅ COMPLETE

> **Plan file:** `docs/plans/testing-strategy.md`

119 tests across 10 test files covering: auth, base repo, orders, labor, jobs, parts, movements, costs, scheduling, and more. Critical path coverage achieved.

### Feature Audits ✅ COMPLETE

> **Audit files:** `docs/plans/Audit/*.md`

All 13 feature area audits completed and verified. 12/13 areas production-ready, Settings has 3 intentional v2.0+ stubs (AI Config, Device Management, Bluetooth).

### V1.0 Deployment & Packaging ⏳ PARTIALLY COMPLETE

> **Plan file:** `docs/plans/deployment-master-plan.md`
> **Sideloading guide:** `docs/plans/sideloading-guide.md`

**Completed tasks (19 of 23):**
- ✅ Production hardening + static serving
- ✅ PWA manifest + app icons
- ✅ Cross-platform responsive audit
- ✅ Capacitor project init + environment detection
- ✅ API adapter layer (Capacitor → local TS, browser → HTTP)
- ✅ Lean TS data layer (11 services)
- ✅ SQLite local DB + 7 consolidated migrations
- ✅ Sync engine (push/pull + conflict resolution + retry + UI indicator)
- ✅ Server URL / Wi-Fi config UI
- ✅ Customer setup guide
- ✅ Backup & restore scripts

**Remaining tasks (need physical devices / Mac):**
- Task 16: iOS Build → Free Sideloading (needs Mac + Xcode)
- Task 17: Android APK Build (needs Android Studio)
- Task 18: On-Device Testing (needs physical iOS + Android devices)
- Task 22: Smoke Test — full workflow verification
- Task 23: Release Packaging (blocked on npm install + mobile builds)

---

## V1.0 Release Roadmap

The complete path from current state to customer-ready deployment:

| Phase | # | Task | Est. Days | Plan File |
|-------|---|------|-----------|-----------|
| **A** | 1 | Phase 8: Reports & Pre-Billing (expanded) | 5-6 | `phase-11-reports-prebilling.md` | ✅ |
| | 2 | Legacy Cleanup | 0.5 | `legacy-cleanup-plan.md` | ✅ |
| | 3 | Critical Path Tests | 2 | `testing-strategy.md` | ✅ (119 tests) |
| **A total** | | | **8-9** | | **COMPLETE** |
| **B** | 4 | Production Hardening + Static Serving | 1 | `deployment-master-plan.md` §3 | ✅ |
| | 5 | PWA Manifest + App Icons | 0.5 | `deployment-master-plan.md` §2.4 | ✅ |
| | 6 | Cross-Platform Responsive Audit | 2 | Feature audit files | ✅ (2 fixes) |
| | 7 | Startup Scripts (Win + Mac) | 0.5 | `deployment-master-plan.md` §3.4-3.5 | ✅ (done in Task 4) |
| | 8 | Capacitor Project Init | 0.5 | `deployment-master-plan.md` §4 | ✅ (config + env detect) |
| | 9 | API Adapter Layer | 1-2 | `deployment-master-plan.md` §5 | ✅ |
| | 10 | Lean TS Data Layer (~11 services) | 5-7 | `deployment-master-plan.md` §6 | ✅ COMPLETE |
| | 11 | SQLite Local DB + Migrations | 2-3 | `deployment-master-plan.md` §6.3 | ✅ COMPLETE |
| **B total** | | | **13-16** | | **COMPLETE** |
| **C** | 12 | Sync Engine (change log + push/pull) | 3-4 | `deployment-master-plan.md` §9 | ✅ COMPLETE |
| | 13 | Conflict Resolution + Merge Logic | 2-3 | `deployment-master-plan.md` §9.4 | ✅ COMPLETE |
| | 14 | Offline Queue + Retry | 1-2 | `deployment-master-plan.md` §9.5 | ✅ COMPLETE |
| | 15 | Network Status UI + Sync Indicator | 1 | `deployment-master-plan.md` §9.7 | ✅ COMPLETE |
| | 16 | iOS Build → Free Sideloading | 1 | `sideloading-guide.md` Part 1 | ⏳ needs Mac |
| | 17 | Android APK Build | 0.5 | `sideloading-guide.md` Part 2 | ⏳ needs Android Studio |
| | 18 | On-Device Testing (all platforms) | 1-2 | Feature audit files | ⏳ needs devices |
| **C total** | | | **9-11** | | **12-15 done, 16-18 blocked** |
| **D** | 19 | Server URL / Wi-Fi Config UI | 1 | `deployment-master-plan.md` §4.3 | ✅ COMPLETE |
| | 20 | Customer Setup Guide | 1 | `deployment-master-plan.md` §10 | ✅ COMPLETE |
| | 21 | Backup & Restore Scripts | 1 | `deployment-master-plan.md` §11 | ✅ COMPLETE |
| | 22 | Smoke Test (full workflow) | 2 | `deployment-master-plan.md` §12 | ⏳ pending |
| | 23 | Release Packaging | 2 | `deployment-master-plan.md` §13 | ⏳ blocked on 16-18 |
| **D total** | | | **7** | | **19-21 done, 22-23 pending** |
| **TOTAL** | | | **~37-44 days** | *19 of 23 tasks complete. Remaining: ~7 days (needs Mac + physical devices)* |

---

## Future Phases (V1.x — Planned & Outlined)

> **Numbering note:** Phases 1-8 (old 1-10 + reports) are all complete. Phase 7 (People) includes completed Delta addendum. Phases 9-13 remain forward-looking roadmap items.

### V1.0.0 in-scope queued phase plans

| Track | Phase | Status | Plan File | Est. Days | Key Deliverables |
|-------|-------|--------|-----------|-----------|------------------|
| **16A** | UX Polish + Admin Hub Consolidation | 📋 Planned (V1.0.0) | `phase-16-ux-polish-and-admin-hub.md` | 8-14 | Navigation/admin consolidation, warehouse/report/scheduling enhancements, team assignment, device management |
| **16B** | Multi-Warehouse + Job Trailers | 📋 Planned (V1.0.0) | `phase-16-multi-warehouse-trailers.md` | 10-16 | Multi-warehouse inventory routing, trailer inventory preload/consume lifecycle, trailer location tracking, warehouse network UI |

### Post-V1.0.0 forward roadmap plans

| New # | Phase | Status | Plan File | Est. Days | Key Deliverables |
|-------|-------|--------|-----------|-----------|------------------|
| **7** | People (Full) | ✅ Complete (incl. Delta) | `phase-7-people-delta.md` | < 1 | GC-aware PO naming, standardized report filenames |
| **8** | Reports & Pre-Billing | ✅ Complete | `phase-11-reports-prebilling.md` | 5-6 | Pre-billing, timesheets, labor overview, profitability, period locking, bookkeeper exports |
| **9** | Chat & Q&A | ✅ Complete | `phase-9-chat.md` | 10-14 | Per-job group chat, DMs, @mentions, Q&A escalation chain, RFI bridge (voice deferred to 9.5) |
| **10** | PWA & Desktop | 📋 Outline | `phase-12-pwa-desktop.md` | 5-8 | Service worker, offline caching, keyboard shortcuts, command palette, push notifications |
| **11** | Sync & Bluetooth | 📋 Planned | `phase-13-sync-bluetooth.md` | 16-24 | BT mesh, gossip protocol, PGP encryption, device pairing, multi-PC shop cluster, device management console (primary user, storage, key visibility, error logs, manual overrides) |
| **12** | AI Integration | 📋 Outline | `phase-14-ai-integration.md` | 8-12 | Local LLM (LM Studio), NL queries, smart scheduling, anomaly detection, predictive ordering |
| **13** | Remote Sync | 🔒 On Hold | `phase-15-remote-sync.md` | 15-25 | Internet sync, shop↔shop, shared channels, cross-company RFI, file-based sync fallback |

### Related Architecture Documents

| Document | Covers |
|----------|--------|
| `Device Sync management.md` | BT mesh spec, gossip protocol, shop cluster, media routing (source for Phase 11) |
| `Device security protocols.md` | PGP, company isolation, device certificates, shared channels (source for Phase 11 + 13) |
| `windows-architecture.md` | Windows decisions: Option B (Tauri/React), llama.cpp AI, dual-platform arch |

---

## Phase 13: Windows AI Integration ✅ COMPLETE

**Goal**: On-device AI for Windows using llama.cpp sidecar (Copilot Runtime rejected — requires Copilot+ PC NPU).

> **Plan file:** `docs/plans/windows-architecture.md`
> **Continuation prompt:** `directives/windows-continuation-prompt.md`

### Decisions
- **AI Engine**: llama.cpp sidecar on localhost:8086 (OpenAI-compatible API)
- **Model format**: GGUF (quantized, 2-8GB, runs on CPU)
- **Model download**: Manual for v1 (setup instructions in Settings UI)

### Implementation
- `foundation_models.rs` — Full `windows_llm` module (11 functions, 563 lines): sidecar lifecycle, health check, request pipeline, availability detection
- `Cargo.toml` — `ureq` (sync HTTP) + `lazy_static` (global Mutex) as Windows-only deps
- `lib.rs` — 8 Tauri commands registered (5 cross-platform + 3 Windows-specific) + shutdown hook
- `foundation-models.ts` — Windows status types + helpers (329 lines)
- `AiConfigPage.tsx` — Full Settings UI for on-device AI setup (382 lines)
- AI components (AiTextarea, AiSuggestionPopover, useAITextField) — already cross-platform

---

## Phase 14: Windows App ✅ COMPLETE (Option B)

**Goal**: Windows desktop app. Decision: **Keep Tauri/React** (Option B).

> **Plan file:** `docs/plans/windows-architecture.md`

### Decision rationale
- Option B eliminates ~3-6 months of porting work
- All 86 pages + 64 TS services + Rust sync/crypto infrastructure already work
- WebView2 is pre-installed on Windows 10/11
- Tauri 2.x supports Windows NSIS installer + code signing

### What was already done (zero new code needed)
- 86 responsive React pages
- 64 TypeScript services (all CRUD, sync, business logic)
- Rust layer: mDNS discovery, Ed25519 crypto, sync server, Foundation Models bridge
- SQLite local database with 35 migrations

### Remaining (needs MSVC Build Tools)
- Windows build verification (`cargo tauri build`)
- Cross-platform sync testing (Windows ↔ macOS ↔ iOS)
- Performance benchmarks

---

## Phase 15: Cleanup ✅ COMPLETE (Modified for Option B)

**Goal**: Documentation updates. File deletions cancelled (src/ and src-tauri/ ARE the Windows app).

> **Plan file:** `docs/plans/windows-architecture.md`

### Completed
- Decision log updated in continuation prompt (3 decisions + rationale)
- All 95 tasks marked with completion statuses
- `docs/plans/windows-architecture.md` created (comprehensive decision document)
- `CLAUDE.md` updated (dual-platform architecture, AI adapter pattern)
- `MEMORY.md` updated (Session 7 + 8 notes)
- `docs/implementation-plan.md` updated (this file)

### Cancelled (Option B)
- No src/ deletion (needed for Windows builds)
- No src-tauri/ deletion (needed for Windows builds)
- No package.json, vite.config.ts, etc. deletion (still needed)

### Deferred
- Release tag v2.0.0 (after MSVC build verification)
| `Q&A Part of the App` | Q&A escalation chain concept, RFI bridge, cross-company protocol (source for Phase 9) |
| `Mobile device bootstrap.md` | Bootstrap app concept — App Store shell that downloads real program from shop |
| `Update protocol.md` | Auto-updates via mesh, shop-originated, ordered installation |
| `The supplier's rep welcome too Idea.md` | Supplier portal concept — multi-customer, rep + warehouse views |
| `full-program-gap-closure-plan.md` | Audit-driven umbrella execution plan for closing validated P2 gaps across all modules |

---

## Critical Files Reference

| File | Why |
|------|-----|
| `backend/app/main.py` | App entry point, dynamic router registration for all 19 routers |
| `backend/app/database.py` | SQLite connection, runs all 38 migrations in order on startup |
| `backend/app/middleware/auth.py` | Device auto-login + PIN + JWT + permission checking. Gates everything. |
| `backend/app/scheduler.py` | APScheduler: midnight daily reports, PDF cleanup, notification purge |
| `backend/app/routers/parts.py` | Largest router (2,224 lines, 61 endpoints) |
| `backend/app/routers/orders.py` | Most endpoints (1,849 lines, 71 endpoints) |
| `backend/app/services/movement_service.py` | Core stock movement engine — atomic transfers (745 lines) |
| `backend/app/services/notebook_service.py` | Largest service (989 lines) — templates + notebooks + entries |
| `backend/app/services/cost_tracking_service.py` | FIFO consumption, LIFO returns, weighted avg cost |
| `frontend/src/App.tsx` | All ~104 routes defined here |
| `frontend/src/lib/types.ts` | Single source of truth for all TypeScript interfaces |
| `frontend/src/lib/navigation.ts` | All modules, tabs, and permission requirements |
| `frontend/src/features/jobs/pages/JobDetailPage.tsx` | Largest page (1,463 lines), 5+ sub-tabs |
| `frontend/src/api/orders.ts` | Largest API client (910 lines, ~60 functions) |
| `frontend/src/stores/clock-store.ts` | Active clock state + real-time timer |
| `docs/FEATURES.md` | Master feature inventory + production-critical gaps + execution sequence |
| `docs/DEVELOPMENT-HANDOFF.md` | Implementation handoff checklist + file-by-file targets + release gates |
| `docs/DEPENDENCIES.md` | Backend/frontend dependency map + install/deployment checklist |
| `docs/plans/full-program-gap-closure-plan.md` | Full-program gap closure roadmap (post-audit backlog execution model) |

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
  Buttons:      Rounded-lg, subtle shadow, hover states, 44×44px min tap target
  Cards:        bg-white dark:bg-gray-800, rounded-xl, shadow-sm, border
  Tables:       Zebra stripe, hover highlight, sticky header, overflow-x-auto on mobile
  Modals:       Centered overlay, max-w-2xl, rounded-2xl
  Badges:       Rounded-full, color-coded by status
  Inputs:       Rounded-lg, border-gray-300, focus:ring-primary-500
```

---

## Known Technical Debt

1. **Test coverage** — 119 tests across 10 files covering auth, base repo, orders, labor, jobs, parts, movements, costs. See `docs/plans/testing-strategy.md`.
2. **1 stub page** — DeviceManagementPage (v2.0+ placeholder). AiConfigPage is now fully functional (Phase 13).
3. **4 legacy pages** — OneDrive lock prevents deletion: NewPartsRequestPage, DraftOrdersPage, ActiveOrdersPage, IncomingOrdersPage.
4. **Parts + Settings routers bypass service layer** — Direct repo access from route handlers.
5. **No jobs_repo / warehouse_repo / labor_repo** — Services do SQL directly.
6. **SQLite concurrency** — WAL mode helps but 5-20 simultaneous users need careful write handling.
7. **Device fingerprinting** — Browser localStorage is not cryptographically secure. Future: WebAuthn.

---

## Production Readiness Review (2026-03-06)

> Cross-audit review completed across all 13 feature audits. Conclusion: platform is production-capable for a 5-20 person electrical contractor team **if** the P0/P1 items below are completed before final V1.0 packaging.

### P0 — Must Fix Before Production ✅ ALL COMPLETE

1. ~~**Photo sync strategy**~~ — ✅ Designed and scaffolded in Phase C sync engine.
2. ~~**Supplier deletion FK guard**~~ — ✅ Returns HTTP 409 with dependency details.

### P1 — Should Fix Before Production ✅ ALL COMPLETE

1. ~~Clock-out photo input~~ — ✅ Camera/file capture implemented.
2. ~~Self-service profile editing + PIN change~~ — ✅ Implemented.
3. ~~Dispatch + time-off notifications~~ — ✅ Wired into notification service.
4. ~~Auto-init default schedule on employee create~~ — ✅ Implemented.
5. ~~Vehicle insurance/registration expiry alerts~~ — ✅ Dashboard-visible.

### Gap Hunt Reconciliation Addendum (2026-03-06)

- Completed cross-audit reconciliation across all 13 audit files.
- Confirmed release-critical scope remains the listed P0/P1 pack above.
- Verified and removed stale false positive from actionable list: **Job tools tab is already implemented** in `frontend/src/features/jobs/pages/JobDetailPage.tsx`.
- Routed non-blocking findings into post-go-live backlog buckets:
  1. Cleanup/consistency (stubs, dead comments, legacy fallbacks/pages)
  2. Missing wiring (backend↔frontend mismatches)
  3. Architecture debt (oversized routers/services, layering cleanup)
  4. Future enhancements (non-blocking capability expansion)

Planning principle: keep V1.0 release scope focused on verified P0/P1 risks; pull P2 items forward only when they materially affect production reliability, data integrity, or a critical field workflow.

### V1.0 Roadmap Impact

- Add a **Production Readiness Hotfix Pack (~2.7 days)** before Phase B Task 8 (Capacitor init).
- Revised estimate becomes roughly **~40–47 days** total for V1.0 readiness.

### Readiness Statement

With the P0/P1 pack complete, the current architecture and feature footprint are sufficient for production deployment in the target environment (shop server + LAN-connected offline-first mobile clients).
