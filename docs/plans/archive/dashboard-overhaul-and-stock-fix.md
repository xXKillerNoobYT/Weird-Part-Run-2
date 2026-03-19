# Dashboard Overhaul + Stock Table Fix + QR Scanner

**Created:** 2026-03-18
**Status:** Draft — awaiting approval

## Goal

Fix the Dashboard to show real data, add expandable KPI cards, create a functional QR scanner page, and restructure Dashboard navigation with sub-pages for Scanner, Clock, and Daily Report.

## Problem Summary

1. **Wrong stock table**: 5 files (11 queries) reference `stock_entries` (empty table) instead of `stock` (the real inventory table)
2. **"Total Parts" KPI is misleading**: Shows catalog entry count (1) instead of physical stock units
3. **QR Scanner is broken**: "Scan QR" button navigates to warehouse module instead of opening camera
4. **Dashboard lacks sub-page navigation**: Clock In, QR Scan, and Daily Report should be navigable sub-pages

---

## Part A: Fix Stock Table Queries (5 files, 11 locations)

### The Problem

Two stock tables exist:
- `stock` (migration 002) — **the real one** with `location_type`, `location_id`, `qty`
- `stock_entries` (migration 020) — future multi-warehouse system, **never populated**

All UI queries use `stock_entries` → always returns 0.

### Files to Fix

| File | Queries | What to Change |
|------|---------|---------------|
| `DashboardView.swift` | 5 | Low stock KPI + stock chart queries |
| `DashboardService.swift` | 1 | `getKPISummary()` low stock count |
| `PartsCatalogPage.swift` | 2 | Low-stock filter + total stock display |
| `PartsForecastingPage.swift` | 1 | Current stock LEFT JOIN |
| `WarehouseMovementsPage.swift` | 1 | Available qty in parts search |

### The Fix Pattern

Replace all instances of:
```sql
FROM stock_entries se WHERE se.part_id = p.id AND se.deleted_at IS NULL
-- using se.quantity
```

With:
```sql
FROM stock s WHERE s.part_id = p.id AND s.deleted_at IS NULL
-- using s.qty
```

---

## Part B: Dashboard KPI Overhaul

### New 5-Card Layout

```
┌──────────────────────┬──────────────────────┐
│  📋 Part Types: 1    │  📦 Total Stock: 76  │
│  (catalog entries)    │  (all locations)      │
├──────────────────────┼──────────────────────┤
│  🔨 Active Jobs: 0   │  🛒 Pending Orders: 0│
├──────────────────────┴──────────────────────┤
│  ⚠️ Low Stock: 0  (below min level)         │
└─────────────────────────────────────────────┘
```

Use a 2+2+1 grid layout (or 3+2 on wider screens).

### Expandable Cards — 2 Layer Drill-Down

Each card is tappable. Tap opens a **detail sheet** with breakdown data.

**Layer 1 (tap card → sheet opens):**

| Card | Sheet Shows |
|------|-------------|
| Part Types | List of categories with part counts per category |
| Total Stock | Breakdown by location type: Warehouse X, Truck Y, Staging Z, Trailer W, Job J |
| Active Jobs | List of active jobs with status, team size, dates |
| Pending Orders | List of pending POs with supplier, item count, expected date |
| Low Stock | List of parts below min level: current qty vs min level |

**Layer 2 (tap a row in the sheet → deeper detail):**

| From | Deeper View Shows |
|------|-------------------|
| Stock by location | Individual parts at that location with quantities |
| Active job row | Job detail: budget, labor hours, materials ordered |
| Pending order row | PO detail: line items, supplier contact, status |
| Low stock part | Part detail: stock by location, last movement, reorder point |

### Data Sources (already exist in services)

- `WarehouseService.getWarehouseKPIs()` → totalStock, stockHealth, shortfallCount
- `WarehouseService.getLocationStock()` → stock by location_type, part, qty
- `JobsService.getJobsDashboardKPIs()` → activeJobs, clockedIn, todayHours, overdue
- `JobsService.listJobs(status:)` → job list filtered by status
- `OrdersService.getOrderStats()` → pendingJPOs, activePOs, pendingReturns, spend30d
- `OrdersService.listPOs(status:)` → PO list filtered by status
- `PartsService.getPartStockSummary(partId:)` → stock breakdown per part

### New KPI Queries

```sql
-- Part Types (catalog count)
SELECT COUNT(*) FROM parts WHERE deleted_at IS NULL

-- Total Stock (physical units across all locations)
SELECT COALESCE(SUM(qty), 0) FROM stock WHERE deleted_at IS NULL

-- Active Jobs (unchanged)
SELECT COUNT(*) FROM jobs WHERE status IN ('active','in_progress') AND deleted_at IS NULL

-- Pending Orders (unchanged)
SELECT COUNT(*) FROM purchase_orders WHERE status IN ('pending','draft') AND deleted_at IS NULL

-- Low Stock (FIXED — uses stock table)
SELECT COUNT(*) FROM parts p
WHERE p.deleted_at IS NULL
  AND p.min_stock_level > 0
  AND (SELECT COALESCE(SUM(s.qty), 0) FROM stock s
       WHERE s.part_id = p.id AND s.deleted_at IS NULL) < p.min_stock_level
```

---

## Part C: Dashboard Sub-Page Navigation

### Current Structure
```
Dashboard
├── Overview tab (KPIs, charts, alerts, quick actions)
└── Daily Report tab (pending actions, activity, deliveries, budget)
```

### New Structure
```
Dashboard (NavigationStack)
├── Main View (KPIs, charts, alerts, quick actions)
│   ├── NavigationLink → QR Scanner sub-page
│   ├── NavigationLink → Clock In/Out sub-page
│   ├── NavigationLink → Daily Report sub-page
│   └── NavigationLink → Move Stock (navigates to warehouse)
│   └── NavigationLink → New Order (navigates to orders)
└── Sub-pages (pushed onto NavigationStack):
    ├── /dashboard/scanner   → IOSDashboardQRScannerPage
    ├── /dashboard/clock     → IOSClockPage (existing, reused)
    └── /dashboard/daily     → DashboardDailyReportPage (extracted)
```

### Changes

1. **Remove the segmented picker** (Overview / Daily Report tabs)
2. **Dashboard main view** shows: KPIs, charts, alerts, quick actions
3. **Quick Actions** become `NavigationLink` destinations:
   - "Scan QR" → pushes QR scanner sub-page
   - "Clock In" → pushes clock sub-page
   - "Daily Report" → pushes daily report sub-page
   - "Move Stock" → still navigates to warehouse module
   - "New Order" → still navigates to orders module
4. **Daily Report** becomes its own view (extracted from DashboardView)

---

## Part D: QR Scanner Page

### New File: `IOSDashboardQRScannerPage.swift`

Uses the existing `IOSQRScanner` infrastructure (VisionKit/DataScannerViewController).

**Layout:**
```
┌─────────────────────────────────┐
│  ← Back    QR Scanner           │
├─────────────────────────────────┤
│                                 │
│         📷 Camera View          │
│     (IOSQRScanner live feed)    │
│                                 │
│    ┌─────────────────────────┐  │
│    │ Point camera at QR code │  │
│    └─────────────────────────┘  │
│                                 │
├─────────────────────────────────┤
│  [No camera? Manual entry]      │
│  ┌─────────────────────────────┐│
│  │ Type or paste code...       ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘

   After scan → Result card slides up:

┌─────────────────────────────────┐
│  ✅ Part Found                   │
│  #14 AWG THHN Wire - Blue       │
│  Code: WIR-14-BLU               │
│                                 │
│  📍 Stock Locations:             │
│  • Warehouse: 50 units           │
│  • Truck #3: 10 units            │
│  • Job Site #12: 3 units         │
│                                 │
│  Quick Actions:                  │
│  [Move Stock] [View Details]     │
│  [View History]                  │
└─────────────────────────────────┘
```

**For different QR types:**
- **Part QR** → stock locations, move stock, view details
- **Staging QR** → staging area contents, pending pulls
- **Tool QR** → tool details, checkout status, condition check
- **Location QR** → bin/shelf contents, recent movements

Uses `QRAutoFillService` (already exists) to decode payload and look up entities.

---

## Part E: Office Page Placeholder

The Office module pages that aren't fully built out yet should show a clean placeholder:

```
┌─────────────────────────────────┐
│  🏢 Office — [Page Name]       │
│                                 │
│  ┌─────────────────────────────┐│
│  │ 🚧                          ││
│  │ Planned for future           ││
│  │ development                  ││
│  │                              ││
│  │ This feature is coming in    ││
│  │ a future update.             ││
│  └─────────────────────────────┘│
└─────────────────────────────────┘
```

NOTE: QR management (creating, editing, assigning QR codes) lives in Office and will be built out over time.

---

## Implementation Order

1. **Fix stock queries** (Part A) — quick, low risk, immediate data fix
2. **Add 5th KPI card** (Part B basics) — new Total Stock card, rename Total Parts → Part Types
3. **Extract Daily Report** to its own view
4. **Add NavigationStack sub-pages** to Dashboard
5. **Build QR Scanner page**
6. **Add expandable KPI sheets** (Layer 1 + Layer 2)
7. **Office placeholder**
8. **Build & verify**

## Files to Create

| File | Purpose |
|------|---------|
| `IOSDashboardQRScannerPage.swift` | Camera view + result card + quick actions |
| `DashboardDailyReportPage.swift` | Extracted daily report (pending actions, activity, deliveries, budget) |
| `DashboardKPIDetailSheets.swift` | Expandable detail views for each KPI card |

## Files to Modify

| File | Changes |
|------|---------|
| `DashboardView.swift` | Fix 5 queries; add 5th KPI; remove tab picker; add NavigationStack with sub-page links; add KPI tap handlers |
| `DashboardService.swift` | Fix 1 query |
| `PartsCatalogPage.swift` | Fix 2 queries |
| `PartsForecastingPage.swift` | Fix 1 query |
| `WarehouseMovementsPage.swift` | Fix 1 query |
| `IOSContentRouter.swift` | Add `/dashboard/scanner`, `/dashboard/clock`, `/dashboard/daily` routes |
| `KPICard.swift` | Add tap callback support |

## Verification

1. Build with zero errors
2. Dashboard shows 5 KPI cards with correct data from `stock` table
3. Tap each KPI card → detail sheet opens with breakdown
4. Tap row in detail sheet → deeper detail view
5. "Scan QR" quick action → pushes scanner page with camera view
6. "Clock In" quick action → pushes clock page
7. "Daily Report" → pushes daily report page
8. Parts Catalog shows correct stock numbers
9. Forecasting page shows correct current stock
10. Warehouse movements shows correct available qty
