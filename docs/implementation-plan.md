# Wired-Part: Full Implementation Plan

## Context

Wired-Part is a field service management app for an electrical contracting company. It manages parts inventory, warehouse operations, truck inventories, job tracking, labor hours, procurement, and pre-billing exports for the bookkeeper. The full specification lives in `ThePlan.md` (1100+ lines). This plan turns that spec into an actionable, phased build.

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
| **Parts Hierarchy** | Category → Style → Type → Color = one orderable variant. General parts vs Branded parts. |
| **Suppliers** | 3-tier contacts: Business Contact → Sales Rep → Delivery Driver. Brand-supplier many-to-many. |

---

## Tech Stack

```
Backend:   Python 3.12 + FastAPI + SQLite (aiosqlite) + Pydantic v2
Frontend:  React 19 + TypeScript + Vite + Tailwind CSS v4
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

## Phase 5: Orders & Procurement

**Goal**: Full PO lifecycle from draft to close, receiving flow integrated with the Guided Movement Wizard, procurement planner with optimization algorithms, and returns/RMA management.

### Database (`migrations/011_orders.sql`)
- `purchase_orders` — po_number (auto-generated), supplier_id, status lifecycle (draft→submitted→partial→received→closed→cancelled), expected_delivery_date, shipping_method, tracking_number, notes, total cost calculations
- `po_line_items` — part_id, qty_ordered, qty_received, unit_price, line_total, received_at tracking
- `returns` — return_type (supplier/customer), linked PO, RMA number, reason, status (requested→approved→shipped→received→credited), tracking info
- `return_line_items` — part_id, qty, condition, disposition (restock/dispose/exchange)
- `price_history` — part_id, supplier_id, cost snapshots over time for trend analysis

### Backend Implementation

**Services:**
- `order_service.py` — PO CRUD, status transitions with validation (can't skip stages), auto-PO-number generation, line item management, cost calculations
- `receiving_service.py` — Partial receive handling (PO stays "partial" until all lines fulfilled), integration with stock movement system, supplier chain tracking carried forward
- `procurement_service.py` — Optimization engine: dynamic supplier ranking (reliability + cost + lead time), EOQ calculations from forecast data, volume discount bracket detection, multi-job consolidation
- `returns_service.py` — Return request lifecycle, RMA tracking, credit memo generation

**API Endpoints:**
```
ORDERS:    GET /api/orders/drafts, GET /api/orders/pending, GET /api/orders/incoming
           POST /api/orders, GET/PUT /api/orders/{id}, PATCH /api/orders/{id}/status
           POST /api/orders/{id}/submit, POST /api/orders/{id}/receive
LINE ITEMS: POST/PUT/DELETE /api/orders/{id}/items
RETURNS:   GET /api/orders/returns, POST /api/orders/returns
           PATCH /api/orders/returns/{id}/status
PROCUREMENT: GET /api/orders/procurement/suggestions
             POST /api/orders/procurement/optimize
             GET /api/orders/procurement/stats
```

### Frontend Implementation

**Pages:**
- `DraftOrdersPage.tsx` — Draft PO list with inline editing, "Submit" action, cost preview
- `PendingOrdersPage.tsx` — Submitted POs awaiting delivery, ETA tracking, "Mark Received" action
- `IncomingOrdersPage.tsx` — Received/partial POs → routes into Guided Movement Wizard for receiving. Shows expected vs received quantities.
- `ReturnsPage.tsx` — Return requests with RMA tracking, status timeline, credit memos
- `ProcurementPage.tsx` — Optimization dashboard: suggested orders based on forecast + reorder points, supplier ranking table, cost savings KPIs

**Key Components:**
- `POForm.tsx` — Create/edit PO with supplier selection, part search, qty/price entry
- `ReceiveWizard.tsx` — Extends Guided Movement Wizard for PO receiving: scan/select parts → enter received qty → movement to warehouse
- `SupplierReturnsWizard.tsx` — Multi-step return flow: select parts → enter qty/reason → generate RMA → ship tracking

**Advanced Features (built iteratively):**
- Smart reorder alerts — When a part hits reorder point, auto-draft a PO with optimal supplier selection
- Supplier scorecard dashboard — Reliability, cost trends, lead time graphs per supplier
- Price history tracking — Track cost changes over time, alert on >10% price increases
- Multi-job consolidation engine — Combine orders across jobs to hit volume discount brackets
- Barcode scanning for receiving — Scan parts as they arrive off the truck, auto-match to PO line items
- Split delivery handling — Partial receives with backorder tracking

### Phase 5 Deliverables
- Full PO lifecycle: draft → submitted → partial receive → closed
- Guided receive flow integrated with existing movement wizard
- Procurement planner with optimization suggestions
- Returns with RMA tracking and supplier chain visibility
- Price history and supplier scorecard

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

## Future Phases (Outline)

| Phase | Focus | Key Deliverables |
|-------|-------|-----------------|
| 7 | People (Full) | Employee detail, certifications, skills matrix, hat management, permission matrix, availability calendar, wage history |
| 8 | Reports & Export | Pre-billing bundles, timesheets, labor overview, profitability analysis, CSV/PDF export, period locking, bookkeeper export format |
| 9 | Chat | Per-job group chat, DMs, @mentions with notifications, photo/file sharing, voice messages, pinned messages, read receipts |
| 10 | AI Integration | LM Studio connection, natural language queries, smart scheduling, anomaly detection, report summarization, predictive ordering |
| 11 | PWA & Desktop | Service worker, offline-first architecture, push notifications, Electron/Tauri wrapper, keyboard shortcuts, system tray |
| 12 | Sync | File-based sync (Drive/OneDrive), real-time collaboration, selective sync, conflict detection, automatic backup, audit trail |

---

## Critical Files (Most Important to Get Right)

| File | Why |
|------|-----|
| `backend/app/migrations/001_foundation.sql` | Foundation schema — users, hats, permissions, devices. Everything depends on this. |
| `backend/app/migrations/002_parts_and_inventory.sql` | Hierarchy tables + parts with GENERATED sell price + unique constraints + seed data |
| `backend/app/repositories/hierarchy_repo.py` | 5 repo classes for hierarchy CRUD + brand-supplier links |
| `backend/app/repositories/parts_repo.py` | Parts search with hierarchy JOINs, pending queries, brand/supplier repos |
| `backend/app/middleware/auth.py` | Device auto-login + PIN + JWT + permission checking. Gates everything. |
| `backend/app/services/labor_service.py` | Clock in/out logic, hours calculation, GPS capture — core of the field workflow |
| `backend/app/services/report_service.py` | Daily report JSON assembly — aggregates workers, questions, parts into locked reports |
| `backend/app/scheduler.py` | APScheduler midnight cron + startup catch-up — generates daily reports automatically |
| `frontend/src/lib/types.ts` | Single source of truth for all TypeScript interfaces (mirrors backend Pydantic models) |
| `frontend/src/lib/navigation.ts` | All modules, tabs, and permission requirements. |
| `frontend/src/features/parts/pages/CategoriesPage.tsx` | Split-pane tree editor — hierarchy CRUD + type-color link management |
| `frontend/src/features/parts/pages/CatalogPage.tsx` | Main parts UI — dual view (card grid + table), hierarchy filters, CRUD form, pending badge |
| `frontend/src/features/jobs/pages/JobDetailPage.tsx` | Full job view with 5 sub-tabs + ClockOutFlow integration — most complex page |
| `frontend/src/features/jobs/components/ClockOutFlow.tsx` | Multi-step clock-out wizard — the core field-worker UX |
| `frontend/src/stores/clock-store.ts` | Zustand store for active clock state + real-time timer |

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

## Areas of Improvement Flagged

1. **Device fingerprinting**: Browser localStorage is not cryptographically secure. Consider WebAuthn for production.
2. **Photo storage**: File paths need sync strategy for multi-device. Consider SQLite BLOBs for small photos.
3. **SQLite concurrency**: WAL mode helps, but 5-20 users hitting one SQLite via FastAPI needs careful write handling.
4. **Generated columns**: `company_sell_price GENERATED ALWAYS AS ... STORED` requires SQLite 3.31.0+ — verify Python's bundled SQLite version.
5. **3-layer architecture fit**: `directives/` and `execution/` are for AI orchestration tasks. App code lives in `backend/` + `frontend/`. Create `directives/app_development/` for dev SOPs.
6. **Part hierarchy completeness**: ✅ Addressed in Phase 2.5 — dedicated CategoriesPage tree editor + inline quick-add on CatalogPage form.
7. **Pending MPN workflow**: Consider adding email/notification when branded parts are created without MPN, so the office knows to look up the part number.
