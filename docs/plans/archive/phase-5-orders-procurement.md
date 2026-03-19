# Phase 5 — Orders & Procurement

## Overview

Full ordering lifecycle from field worker parts requests through PO generation, supplier management, receiving, staging, returns, and procurement planning.

## Architecture

### Two-Level Order Structure

```
Field Worker          Office               Supplier
──────────           ──────               ────────
JPO (Parts Request)  →  PO (Purchase Order)  →  Shipment
  - Draft               - Draft                  ↓
  - Pending Approval     - Submitted           Receiving
  - Approved             - Acknowledged          ↓
  - Ordering             - Shipped             Staging Zone
  - Fulfilled            - Partially Received     ↓
                         - Received            Warehouse/Truck
                         - Closed
```

**JPO (Job Parts Order):** Field worker requests parts for a job. Goes through approval workflow.
**PO (Purchase Order):** Office creates POs from approved JPOs (supplier-scoped) or standalone POs for restocking.

### Standalone POs
Office can create POs directly without a JPO for:
- Warehouse restocking
- Bulk orders
- Special orders

### Chain of Custody
```
Supplier → Staging Zone → Warehouse Bin → Truck → Job Site
                                          ↓
                                       Returns → Staging → Shelf or Supplier RMA
```

## Backend Implementation

### Migration: `015_orders_procurement.sql`
Tables created:
- `job_parts_orders` + `jpo_lines`
- `purchase_orders` + `po_lines`
- `staging_zones` + `staging_items`
- `return_orders` + `return_lines`
- `order_status_history`
- `notifications` + `notification_preferences`
- `company_profiles`
- `price_history`
- `supplier_contact_ratings`

### Models (Pydantic schemas)
- `models/orders.py` — JPO, PO, Return, Staging, StatusHistory, SupplierRating, PriceHistory, Procurement
- `models/notifications.py` — Notification, Badge, Preferences
- `models/company.py` — CompanyProfile CRUD schemas

### Repositories
- `repositories/orders_repo.py` — JPO + PO + Return CRUD, status tracking
- `repositories/staging_repo.py` — Staging zone management
- `repositories/notification_repo.py` — Notification CRUD, preferences

### Services (6 total)
- `services/orders_service.py` — JPO lifecycle (create, approve, reject), PO conversion
- `services/receiving_service.py` — Incoming deliveries, qty tracking, stock updates
- `services/returns_service.py` — Return workflows (job→warehouse, warehouse→supplier)
- `services/procurement_service.py` — Reorder dashboard, low-stock suggestions, supplier rankings
- `services/notification_service.py` — Create/cleanup notifications, preference defaults
- `services/pdf_service.py` — PO PDF generation (fpdf2), text fallback, 3-day auto-delete

### Routers
- `routers/orders.py` — ~25 endpoints covering JPOs, POs, receiving, returns, procurement, staging
- `routers/notifications.py` — Badge, list, mark-read, preferences
- `routers/app_settings.py` (extended) — Company profiles CRUD, staging zones CRUD

### Scheduler Jobs
- `midnight_pdf_cleanup_job` (00:15) — Delete PDFs older than 3 days
- `midnight_notification_cleanup_job` (00:20) — Delete notifications older than 30 days

## Frontend Implementation

### API Clients
- `api/orders.ts` — All order API functions (JPO, PO, receiving, returns, procurement, staging)
- `api/notifications.ts` — Badge, list, mark-read, preferences
- `api/settings.ts` (extended) — Company profile CRUD functions

### Types (`lib/types.ts`)
- Status unions: `JPOStatus`, `POStatus`, `POLineStatus`, `ReturnStatus`, etc.
- Label maps: `JPO_STATUS_LABELS`, `PO_STATUS_LABELS`, `RETURN_STATUS_LABELS`
- Full interfaces for all order entities, receiving, returns, staging, procurement

### Navigation (`lib/navigation.ts`)
Orders module: 6 tabs
1. Parts Requests → `/orders/parts-requests`
2. Draft POs → `/orders/drafts`
3. Active Orders → `/orders/active`
4. Incoming → `/orders/incoming`
5. Returns → `/orders/returns`
6. Procurement → `/orders/procurement` (requires `manage_orders`)

Settings module: added 2 tabs
- Company → `/settings/company-profile` (requires `manage_settings`)
- Notifications → `/settings/notifications`

### Pages (10 new/replaced)
| Page | Route | Purpose |
|------|-------|---------|
| PartsRequestsPage | /orders/parts-requests | JPO list with status filters |
| JPODetailPage | /orders/parts-requests/:id | JPO detail, approve/reject, generate POs |
| DraftOrdersPage | /orders/drafts | Draft POs before submission |
| ActiveOrdersPage | /orders/active | Submitted/acknowledged POs |
| IncomingOrdersPage | /orders/incoming | Receiving workflow entry |
| ReturnsPage | /orders/returns | Job and supplier returns |
| ProcurementPage | /orders/procurement | Dashboard + reorder alerts |
| PODetailPage | /orders/pos/:id | PO detail with lines, totals, timeline |
| CompanyProfilePage | /settings/company-profile | Company info for PO PDFs |
| NotificationPrefsPage | /settings/notifications | Per-user notification opt-in |

### Components
- `OrderStatusBadge` — Color-coded status chips (JPO/PO/Return)
- `NotificationBell` — Header bell icon with badge count, dropdown, 60s polling

### Supplier Ranking Formula
```
Composite Score = (Price × 0.35) + (On-time × 0.20) + (Communication × 0.20) + (Quality × 0.15) + (Lead time × 0.10)
```

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Default landing tab | Parts Requests | Field workers use JPOs most frequently |
| Notification defaults | All OFF | Opt-in prevents notification fatigue |
| PDF library | fpdf2 (text fallback) | Lightweight, no external dependencies |
| Notification cleanup | 30 days | Keeps DB lean without losing recent context |
| PDF cleanup | 3 days | PDFs are regeneratable; saves disk space |
| Staging zones | Physical + logical | QR labels on zones + job assignment in software |
| Return types | job_to_warehouse, warehouse_to_supplier | Two distinct workflows with shared infrastructure |

## Status: COMPLETE
All backend and frontend components implemented and verified.
- TypeScript: `tsc --noEmit` — zero errors
- Python: All 65 backend files — zero syntax errors
- Backend imports: All Phase 5 modules import cleanly
