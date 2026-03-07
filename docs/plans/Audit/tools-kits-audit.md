# Tools & Kits Module Audit

> **Date:** 2026-03-06
> **Status:** ✅ Verified Complete (2026-03-07) — Job Tools tab implemented in JobDetailPage (lines 828-897). Bulk ops, tool photos, kit auto-verification, maintenance type delete all done via M3/M4 gap closure.
> **Scope:** Tool registry, kit templates, checkout/return flow, kit verification, maintenance tracking, dashboard, QR code scanning, cross-module visibility (warehouse, trucks, jobs)

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

### Router

| File | Lines | Prefix | Tag |
|------|-------|--------|-----|
| `backend/app/routers/tools.py` | 526 | `/api/tools` | Tools |

### Endpoints (27 total)

#### Dashboard & Global Queries

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tools/dashboard` | Aggregate dashboard stats (counts by status, location, category) |
| GET | `/api/tools/by-location` | Get all tools at a specific location (warehouse, truck, or job) |
| GET | `/api/tools/recent-movements` | Recent movements across all tools |
| GET | `/api/tools/maintenance-alerts` | Overdue or upcoming maintenance alerts |

#### Maintenance Types (Global Config)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tools/maintenance-types` | List all maintenance types |
| POST | `/api/tools/maintenance-types` | Create maintenance type |
| PUT | `/api/tools/maintenance-types/{id}` | Update maintenance type |

#### QR Scan

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tools/scan/{tool_number}` | Look up tool by tool number (for QR code scanning) |

#### Tool CRUD

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tools/` | Paginated tool list with filters (category, status, location, search) |
| POST | `/api/tools/` | Register a new tool |
| GET | `/api/tools/{id}` | Get tool detail |
| PUT | `/api/tools/{id}` | Update tool |
| DELETE | `/api/tools/{id}` | Retire/deactivate tool |

#### Checkout / Return

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/tools/{id}/checkout` | Check out tool to a location (warehouse→truck, truck→job, etc.) |
| POST | `/api/tools/{id}/return` | Return tool to a location |
| GET | `/api/tools/{id}/movements` | Movement history for a specific tool |

#### Kit Templates

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tools/{id}/kit` | Get kit template items for a tool |
| POST | `/api/tools/{id}/kit` | Add item to kit template |
| PUT | `/api/tools/{id}/kit/{item_id}` | Update kit template item |
| DELETE | `/api/tools/{id}/kit/{item_id}` | Remove kit template item |

#### Kit Verification

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/tools/{id}/verify` | Start verification session (generates checklist from template) |
| PUT | `/api/tools/{id}/verify/{session_id}` | Complete verification session with item statuses |
| GET | `/api/tools/{id}/verify/history` | Verification session history |

#### Per-Tool Maintenance

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/tools/{id}/maintenance/schedule` | Get maintenance schedules for a tool |
| POST | `/api/tools/{id}/maintenance/schedule` | Create/update maintenance schedule |
| POST | `/api/tools/{id}/maintenance/log` | Log a maintenance service event |
| GET | `/api/tools/{id}/maintenance/history` | Service history for a tool |

### Permission Gates

| Permission | Grants Access To |
|------------|-----------------|
| `view_tools` | Read tool registry, locations, maintenance status, dashboard |
| `checkout_tools` | Check out/return tools, perform kit verification |
| `manage_tools` | Register/edit/retire tools, manage kit templates, maintenance types, log services |

### Service

| File | Lines | Class |
|------|-------|-------|
| `backend/app/services/tools_service.py` | 644 | `ToolsService` |

Handles:
- Tool CRUD with auto-numbering (T-001, T-002...)
- Location tracking (polymorphic: warehouse, truck, job)
- Checkout/return with movement history logging
- Kit template management (sub-items for combo tools)
- Kit verification sessions (checklist generation, completion with status per item)
- Maintenance type management (global config)
- Per-tool maintenance scheduling (recurring or one-time)
- Service logging with cascade to schedule (updates `last_serviced_at`, `next_due_at`)
- Dashboard stats aggregation
- Maintenance alerts (overdue, upcoming within 7 days)

### Models

| File | Lines | Content |
|------|-------|---------|
| `backend/app/models/tools.py` | 397 | 20+ Pydantic models organized into Tools, Kit Templates, Movements, Kit Verification, Maintenance, and Dashboard sections |

Key models:
- **Tools:** `ToolCreate`, `ToolUpdate`, `ToolResponse`, `ToolListItem`
- **Kit Templates:** `KitTemplateItemCreate`, `KitTemplateItemUpdate`, `KitTemplateItemResponse`
- **Movements:** `ToolCheckout`, `ToolReturn`, `ToolMovementResponse`
- **Kit Verification:** `KitVerificationStart`, `KitVerificationComplete`, `KitVerificationSessionResponse`
- **Maintenance:** `ToolMaintenanceTypeCreate/Update/Response`, `ToolMaintenanceScheduleCreate/Response`, `ToolMaintenanceRecordCreate/Response`
- **Dashboard:** `ToolsDashboardStats`, `ToolMaintenanceAlert`

### Repository

| File | Lines | Class |
|------|-------|-------|
| `backend/app/repositories/tools_repo.py` | 490 | `ToolsRepo` (extends `BaseRepo`) |

Follows the standard repository pattern with full SQL queries for:
- Paginated tool listing with JOINs for location names
- Tool creation, updates, soft-delete (retire)
- Movement history recording
- Kit template item CRUD
- Verification session management
- Maintenance schedule and service record management

### Migration

| Migration | File | Lines | Tables |
|-----------|------|-------|--------|
| 024 | `024_tools_and_kits.sql` | 301 | 6 tables |

Tables created:
1. `tools` — Core tool registry (tool_number, name, category, brand, model, serial, financials, location, status)
2. `tool_movements` — Checkout/return history (from/to location, checked_out_by/to, timestamps)
3. `kit_template_items` — Sub-items that belong to a tool (e.g., drill bits for a drill)
4. `kit_verification_sessions` — Verification session records (trigger type, result, timestamps)
5. `kit_verification_items` — Individual item checks within a session (status, notes)
6. `tool_maintenance_types` — Global maintenance type definitions (name, description)
7. `tool_maintenance_schedule` — Per-tool recurring maintenance schedules
8. `tool_maintenance_records` — Service history records

*(Note: 8 tables total including the schedule and records tables)*

---

## 2. Frontend Inventory

### Dedicated Tools Feature (`features/tools/`)

| File | Lines | Route | Description |
|------|-------|-------|-------------|
| `components/ToolScanRedirect.tsx` | 97 | `/tools/scan/:toolNumber` | QR scan resolver — looks up tool by number, redirects to warehouse/truck/job tools page based on current location |

**This is the only file in `features/tools/`.** The Tools module is unique in that its main UI lives inside the Warehouse and Trucks feature folders rather than having its own dedicated pages.

### Warehouse Tools Page (`features/warehouse/pages/`)

| File | Lines | Route | Description |
|------|-------|-------|-------------|
| `ToolsPage.tsx` | 803 | `/warehouse/tools` | **Global tool registry** — the primary management interface for all tools |

This is the de facto "Tools admin" page. It provides:
- Dashboard stats panel (total tools, checked out, in maintenance, alerts)
- Maintenance alerts list (overdue/upcoming)
- Filterable tool list (category, status, location, search)
- Tool detail panel (slide-out with full info)
- Create tool modal
- QR code generation and printing
- Pagination with selectable page sizes

### Truck Tools Page (`features/trucks/pages/`)

| File | Lines | Route | Description |
|------|-------|-------|-------------|
| `ToolsPage.tsx` | 738 | `/trucks/tools` | **Per-truck operational view** — checkout/return tools for a specific truck |

This is the field worker's primary interaction point. It provides:
- Truck selector dropdown
- Tools currently on selected truck
- Available warehouse tools for checkout
- Checkout flow (select tool → confirm → move to truck)
- Return flow (select tool → confirm → return to warehouse)
- Recent movement history
- QR code generation and printing

### Navigation Config

Tools appear as **tabs within other modules**, not as a top-level nav item:

```typescript
// In Warehouse module
{ id: 'tools', label: 'Tools', path: '/warehouse/tools', permission: 'view_tools' }

// In Trucks module
{ id: 'tools', label: 'Tools', path: '/trucks/tools', permission: 'view_tools' }
```

There is **no top-level "Tools" module** in the sidebar. The `/tools/scan/:toolNumber` route is a utility route for QR code scanning.

### API Client

| File | Lines | Exported Functions |
|------|-------|--------------------|
| `api/tools.ts` | 363 | 27 functions |

Functions breakdown:
- **Tool CRUD (6):** getTools, getTool, createTool, updateTool, retireTool, scanTool
- **Dashboard (3):** getToolsDashboard, getToolsAtLocation, getRecentMovements
- **Checkout/Return (3):** checkoutTool, returnTool, getToolMovements
- **Kit Templates (4):** getKitTemplate, addKitComponent, updateKitComponent, removeKitComponent
- **Kit Verification (3):** startVerification, completeVerification, getVerificationHistory
- **Maintenance Types (3):** getMaintenanceTypes, createMaintenanceType, updateMaintenanceType
- **Per-Tool Maintenance (4):** getToolSchedule, setToolSchedule, logService, getServiceHistory
- **Alerts (1):** getMaintenanceAlerts

---

## 3. Feature Completeness

### ✅ Fully Functional

| Feature | Notes |
|---------|-------|
| **Tool Registry** | Full CRUD with auto-numbered tool IDs, categories, brand/model/serial tracking |
| **Location Tracking** | Polymorphic location (warehouse, truck, job) with movement history |
| **Checkout / Return** | Full flow with movement recording, status updates |
| **Dashboard Stats** | Aggregate counts by status, location, category |
| **Maintenance Alerts** | Overdue and upcoming (7-day window) alerts surface on warehouse tools page |
| **Maintenance Types** | Global configuration for maintenance type definitions |
| **Maintenance Scheduling** | Per-tool recurring schedules with interval tracking |
| **Service Logging** | Log maintenance events, cascade to schedule updates |
| **Kit Templates** | Define sub-items for combo tools (e.g., drill + bit set + charger) |
| **Kit Verification** | Session-based verification with per-item status tracking |
| **QR Code Generation** | Generate and print QR codes on both warehouse and truck tool pages |
| **QR Scan Redirect** | `/tools/scan/:toolNumber` resolves and redirects to correct module page |
| **Tool Filtering** | Multi-criteria filtering: category, status, location type, text search |
| **Pagination** | Server-side pagination with selectable page sizes |
| **Permission Gating** | 3-tier permissions: view, checkout, manage |

### ⚠️ Not Implemented / Potential Gaps

| Area | Status | Notes |
|------|--------|-------|
| **Job Tools Page** | Not implemented | Tools can be checked out to jobs, but there is no `/jobs/:id/tools` tab or embedded tools view on the job detail page. QR scan redirect targets `/jobs/{jobId}?tab=tools&tool={id}` but this tab doesn't exist yet. |
| **Tool Transfer (truck→truck)** | Unclear | The checkout/return model allows warehouse↔truck and truck↔job, but direct truck-to-truck transfers may require intermediate return-to-warehouse |
| **Tool Photos** | Not implemented | No image/photo upload for tools (brand logos, condition photos) |
| **Tool Depreciation** | Not tracked | Purchase cost and date are stored but there's no depreciation calculation |
| **Barcode (non-QR) Support** | Not implemented | Only QR codes; no traditional barcode generation |
| **Tool Calibration Tracking** | Not implemented | Meters and safety equipment may need calibration dates, which aren't tracked separately from general maintenance |
| **Kit Verification Triggers** | Partially implemented | `trigger_type` field exists but only manual triggering is implemented; no automated triggers (e.g., on checkout, daily schedule) |
| **Bulk Operations** | Not implemented | No bulk checkout, bulk return, or bulk maintenance logging |
| **Tool Reports/Export** | Not implemented | No export functionality for tool inventory or maintenance history |
| **Maintenance Type Delete** | Not implemented | Can create and update maintenance types but no delete endpoint |

---

## 4. Cross-References

### Tools → Other Modules

| Dependency | Details |
|-----------|---------|
| **Warehouse** | Primary management interface lives at `/warehouse/tools`; warehouse is the default "home" location for tools |
| **Trucks/Vehicles** | Per-truck tool view at `/trucks/tools`; checkout targets truck by vehicle ID |
| **Jobs** | Tools can be checked out to jobs, linking to job IDs; QR scan redirects include job routing |
| **Users/People** | Checkout records reference `checked_out_by` and `checked_out_to` user IDs |

### Other Modules → Tools

| Module | Uses Tools For |
|--------|---------------|
| **Warehouse** | Tools tab (`/warehouse/tools`) — global registry and management |
| **Trucks** | Tools tab (`/trucks/tools`) — per-truck checkout/return |
| **Jobs** | Future: Job detail should show tools checked out to that job |
| **QR Scanner** | Cross-module scan redirect via `/tools/scan/:toolNumber` |

---

## 5. Issues & TODOs

### No TODOs Found in Code
Zero `TODO`, `FIXME`, `HACK`, or `STUB` comments across all Tools frontend and backend files. The code is clean.

### Structural Observations

1. **No standalone "Tools" module in navigation:** Unlike Parts, Office, Jobs, etc., Tools doesn't have its own sidebar item. It's embedded as tabs within Warehouse and Trucks. This makes sense for field workers (who think in terms of "truck tools" and "warehouse tools") but could be limiting for office administrators who want a central tool management view.

2. **`features/tools/` is almost empty:** Only contains the QR scan redirect component (97 lines). The actual tool management UI (1,541 lines across warehouse + trucks) lives in those module folders. This is an unusual pattern — most features have their pages in their own feature folder.

3. **Job detail page gap:** The QR scan redirect component explicitly routes to `/jobs/{jobId}?tab=tools&tool={id}`, but the `JobDetailPage` doesn't have a tools tab. This means scanning a tool that's checked out to a job would redirect to the job detail page without showing the tool info.

4. **Warehouse ToolsPage is comprehensive but large:** At 803 lines, it handles dashboard stats, alerts, tool list, detail panel, create modal, and QR generation all in one file. Could benefit from component extraction.

5. **Repository follows standard pattern:** Unlike Notebooks (which has no repo), Tools properly uses `ToolsRepo` extending `BaseRepo` — following the established project pattern.

6. **API client matches backend 1:1:** 27 backend endpoints ↔ 27 API client functions. Perfect parity.

7. **Maintenance type deletion gap:** There's no `DELETE /api/tools/maintenance-types/{id}` endpoint. Types can only be created and updated.

### Size Summary

| Layer | Files | Total Lines |
|-------|-------|-------------|
| Backend Router | 1 | 526 |
| Backend Service | 1 | 644 |
| Backend Repository | 1 | 490 |
| Backend Models | 1 | 397 |
| Migration | 1 | 301 |
| Frontend — Warehouse ToolsPage | 1 | 803 |
| Frontend — Truck ToolsPage | 1 | 738 |
| Frontend — ToolScanRedirect | 1 | 97 |
| API Client | 1 | 363 |
| **Total** | **9 files** | **~4,359 lines** |
