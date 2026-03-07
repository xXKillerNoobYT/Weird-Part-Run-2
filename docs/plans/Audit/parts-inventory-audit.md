# Parts & Inventory Audit

> **Date:** 2026-03-06
> **Status:** ✅ Complete
> **Scope:** Full audit of Parts & Inventory module (Hierarchy, Catalog, Brands, Suppliers, Companions, Alternatives, Import/Export)
> **Phases:** Phase 2 (core), Phase 2.5 (hierarchy UX), Phase 3.5 (companions, alternatives), Phase 7D (cost display)

---

## 1. Backend Inventory

### Routers

| File | Lines | Endpoints | Prefix |
|------|------:|----------:|--------|
| `routers/parts.py` | 2,224 | 61 | `/api/parts` |
| `routers/companions.py` | 394 | 10 | `/api/parts/companions` |
| **Total** | **2,618** | **71** | |

### Endpoint Breakdown — `parts.py` (61 endpoints)

| Section | Methods | Count |
|---------|---------|------:|
| Hierarchy | GET | 1 |
| Categories | GET POST PUT DELETE | 4 |
| Styles | GET POST PUT DELETE | 4 |
| Types | GET POST PUT DELETE | 4 |
| Type↔Color Links | GET POST DELETE | 3 |
| Type↔Brand Links | GET POST DELETE + listParts, quickCreate | 5 |
| Colors | GET POST PUT DELETE | 4 |
| Catalog | GET POST PUT DELETE + stats, groups | 7 |
| Pending Part Numbers | GET list + count | 2 |
| Pricing | GET PUT | 2 |
| Stock | GET stock + summary | 2 |
| Part↔Supplier Links | POST DELETE | 2 |
| Part Alternatives | GET POST PUT DELETE | 4 |
| Brands | GET(list) GET(detail) POST PUT DELETE | 5 |
| Brand↔Supplier Links | 4 views | 4 |
| Suppliers | GET(list) GET(detail) POST PUT DELETE | 5 |
| Forecasting | GET | 1 |
| Import/Export | GET POST | 2 |

### Endpoint Breakdown — `companions.py` (10 endpoints)

| Section | Methods | Count |
|---------|---------|------:|
| Rules | GET POST PUT DELETE | 4 |
| Suggestions | POST generate, GET list, POST decide | 3 |
| Stats | GET | 1 |
| Co-occurrence | GET list, POST refresh | 2 |

### Models

| File | Lines | Description |
|------|------:|-------------|
| `models/parts.py` | 831 | ~40 Pydantic classes — hierarchy, brands, suppliers, parts, stock, movements, search params |
| `models/companions.py` | 179 | ~12 Pydantic classes — companion rules, suggestions, co-occurrence, stats |

### Repositories

| File | Lines | Key Classes |
|------|------:|-------------|
| `repositories/parts_repo.py` | 619 | `BrandRepo`, `SupplierRepo`, `PartsRepo` |
| `repositories/hierarchy_repo.py` | 475 | `PartCategoryRepo`, `PartStyleRepo`, `PartTypeRepo`, `PartColorRepo`, `BrandSupplierLinkRepo`, `TypeColorLinkRepo`, `TypeBrandLinkRepo` |
| `repositories/stock_repo.py` | 248 | `StockRepo`, `MovementRepo` |
| `repositories/alternatives_repo.py` | 124 | `PartAlternativesRepo` |
| `repositories/companions_repo.py` | 424 | `CompanionRuleRepo`, `CompanionSuggestionRepo`, `CoOccurrenceRepo` |
| `repositories/supplier_pref_repo.py` | 100 | `SupplierPrefRepo` (hierarchy-cascade resolver) |

### Services

| File | Lines | Description |
|------|------:|-------------|
| `services/companions_service.py` | 334 | Rule matching engine, suggestion generation |

> **Note:** Parts has NO dedicated service layer — router handles all business logic inline (2,224 lines). This is the largest router in the app.

### Backend Summary

| Metric | Count |
|--------|------:|
| Backend router lines | 2,618 |
| Backend model lines | 1,010 |
| Backend repo lines | 1,990 |
| Backend service lines | 334 |
| **Backend total** | **5,952** |

---

## 2. Frontend Inventory

### Pages (8 routed pages)

| Page File | Lines | Route | Status |
|-----------|------:|-------|--------|
| `CategoriesPage.tsx` | 347 | `/parts/categories` | ✅ Functional |
| `CatalogPage.tsx` | 952 | `/parts/catalog` | ✅ Functional |
| `BrandsPage.tsx` | 719 | `/parts/brands` | ✅ Functional |
| `SuppliersPage.tsx` | 1,266 | `/parts/suppliers` | ✅ Functional |
| `PricingPage.tsx` | 386 | `/parts/pricing` | ✅ Functional (permission-gated) |
| `ForecastingPage.tsx` | 239 | `/parts/forecasting` | ✅ Functional (read-only) |
| `CompanionsPage.tsx` | 71 | `/parts/companions` | ✅ Functional (sub-tab host) |
| `ImportExportPage.tsx` | 247 | `/parts/import-export` | ✅ Functional |

### Components

| Group | Files | Lines |
|-------|------:|------:|
| Categories tree (14 files) | 14 | ~2,892 |
| Companions (8 files) | 8 | ~1,168 |
| Alternatives (3 files) | 3 | ~667 |
| Part cost display (1 file) | 1 | 308 |
| **Total components** | **26** | **~5,035** |

### API Client

| File | Lines | Exported Functions |
|------|------:|-------------------:|
| `api/parts.ts` | 601 | 69 |

### Navigation Config

Parts module — 9 nav items:
- `/parts` → redirects to `/parts/catalog`
- `/parts/categories`
- `/parts/catalog`
- `/parts/brands`
- `/parts/suppliers`
- `/parts/pricing` (permission: `show_dollar_values`)
- `/parts/forecasting`
- `/parts/companions`
- `/parts/import-export`

### Frontend Summary

| Metric | Count |
|--------|------:|
| Page files | 8 |
| Component files | 26 |
| Total frontend files | 34 |
| Total frontend lines | ~8,799 |
| API client lines | 601 |
| **Frontend total** | **~9,400** |

---

## 3. Feature Completeness

### ✅ Fully Functional (100%)

| Feature | Notes |
|---------|-------|
| Hierarchy CRUD | Category→Style→Type→Color tree, add/edit/delete, sort ordering, images |
| Type↔Color Links | Bulk link/unlink, type-scoped valid color lists |
| Type↔Brand Links | Brand enable/disable per type, part count guards on unlink |
| Quick-Create Parts | From tree: type+brand+color → auto-generate name |
| Catalog CRUD | Full CRUD with validation, duplicate prevention, stock guard on delete |
| Catalog Search & Filter | 10+ filter dimensions, paginated, sortable |
| Catalog Groups | Category×Brand grouped card view |
| Catalog Stats | Summary statistics endpoint |
| Pending Part Numbers | Queue for branded parts missing MPN, badge count |
| Pricing | Permission-gated with PIN-gated frontend |
| Stock | Per-part levels across all location types |
| Part↔Supplier Links | Link/unlink with MPN, cost, MOQ, preferred flag |
| Part Alternatives | Bidirectional linking with relationship/preference/notes |
| Brands | Full CRUD with aggregation and deletion guards |
| Brand↔Supplier Links | Many-to-many, both directions queryable |
| Suppliers | Full CRUD with contacts, delivery methods, reliability scores |
| Companion Rules | Full CRUD with category-level sources/targets |
| Companion Suggestions | Manual trigger, suggestion board, approve/discard workflow |
| Co-occurrence | View top pairs, refresh from stock movements |
| CSV Import | Create/update by code, error reporting |
| CSV Export | Full catalog dump, pricing conditional on permissions |
| Categories Tree UI | Rich tree editor with inline CRUD, global color manager |

### ⚠️ Minor Limitations

| Feature | Status | Notes |
|---------|--------|-------|
| Forecasting | Read-only | Data computed by APScheduler; users can't manually trigger recalculation from parts UI |
| QR Images | Auto-computed | Fields exist + auto-compute; upload UX is in warehouse module (QRLabelModal) |
| CSV Import | Basic | Create/update by code only; no hierarchy auto-resolution by name (only by ID) |

---

## 4. Cross-References

Parts is a **foundational module** — at least 7 other feature areas depend on it:

| Consumer Module | What It Uses |
|----------------|-------------|
| Orders (UnifiedOrderPage) | `generateCompanionSuggestions` |
| Orders (Part search) | `listParts`, `listCategories` |
| Orders (Generate POs, New PO, New Return) | `listSuppliers` |
| Office (Warehouse Executive) | `listParts`, `updatePart`, `updatePartPricing` |
| Office (PO Management, Review & Send) | `listSuppliers` |
| Warehouse (Add Stock Modal) | `listParts` |
| Warehouse (QR Label Modal) | `updatePart` |
| Warehouse (backend) | `StockRepo`, `MovementRepo`, `SupplierPrefRepo` |
| Vehicle/Delivery services | `StockRepo` |
| Companions service | Parts table for rule matching |
| Cost tracking | `StockRepo` for cost layers |

---

## 5. Issues & Observations

| # | Issue | Severity | Notes |
|---|-------|----------|-------|
| 1 | **No service layer** — 2,224-line router handles all business logic inline | Low | Works, but largest router in app; extracting a `parts_service.py` would improve testability |
| 2 | **Supplier deletion lacks guard** — no check for FK references before delete | Medium | Could cause FK violations; brands have this guard but suppliers don't |
| 3 | **`PartSearchParams` model unused** — exists in `models/parts.py` but router uses individual `Query()` params | Low | Model only used by frontend types |
| 4 | **CSV import hierarchy resolution** — only accepts `category_id`, not `category_name` | Low | Would be a nice enhancement for user-friendliness |
| 5 | **Zero TODO/FIXME comments** in all parts files | ✅ | Code is clean |

---

## 6. Grand Total

| Metric | Count |
|--------|------:|
| API endpoints | 71 |
| Frontend API functions | 69 |
| Routed pages | 9 |
| Pydantic models | ~52 |
| Repository classes | 10 |
| DB tables touched | ~16 |
| **Total lines (backend + frontend)** | **~15,352** |
