# Office Module Audit

> **Date:** 2026-03-06
> **Status:** Research complete
> **Scope:** Office management pages, PO workflows, approvals, spending dashboard, notebook templates, warehouse locations, clock-out questions, and bill rate types

---

## Table of Contents

1. [Backend Inventory](#1-backend-inventory)
2. [Frontend Inventory](#2-frontend-inventory)
3. [Feature Completeness](#3-feature-completeness)
4. [Cross-References](#4-cross-references)
5. [Issues & TODOs](#5-issues--todos)

---

## 1. Backend Inventory

The Office module does **not** have its own dedicated router. Instead, Office functionality is distributed across multiple routers and services. The Office is a **frontend organizational concept** — a collection of management/admin pages that invoke various backend endpoints.

### Routers Serving Office Pages

| Router | File | Lines | Office-Relevant Endpoints |
|--------|------|-------|--------------------------|
| Orders | `backend/app/routers/orders.py` | 1,849 | 71 endpoints total — the `/office/*` sub-routes (approvals, bulk-approve, pending counts) + all PO management, conversations, groups |
| Costs | `backend/app/routers/costs.py` | 330 | Spending dashboard, FIFO/LIFO cost tracking, budget alerts |
| Jobs | `backend/app/routers/jobs.py` | — | Job CRUD used by ManageJobsPage |
| Notebooks | `backend/app/routers/notebooks.py` | 604 | Template CRUD endpoints used by JobNotebookTemplatePage |
| Reports | `backend/app/routers/reports.py` | — | Clock-out questionnaire config |

### Office-Specific Endpoints in orders.py

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/orders/office/pending-approvals` | Unified pending approvals queue |
| GET | `/api/orders/office/pending-approvals/count` | Badge count for approvals tab |
| POST | `/api/orders/office/bulk-approve` | Bulk approve/reject JPOs and returns |
| POST | `/api/orders/pos/bulk-submit` | Bulk submit POs |
| POST | `/api/orders/pos/bulk-status` | Bulk update PO statuses |
| POST | `/api/orders/returns/bulk-approve` | Bulk approve returns |
| GET | `/api/orders/pos` | List all POs (PO Management tab) |
| GET | `/api/orders/drafts` | Draft POs |
| GET | `/api/orders/active` | Active POs |
| POST | `/api/orders/pos/group` | Create PO group for bundled sending |
| GET | `/api/orders/pos/group/{id}` | Get PO group details |
| GET | `/api/orders/pos/groups/by-supplier/{id}` | List groups for a supplier |
| GET | `/api/orders/pos/{id}/conversation` | PO conversation thread |
| POST | `/api/orders/pos/{id}/conversation` | Add conversation entry |
| GET | `/api/orders/suppliers/{id}/conversation` | Supplier conversation history |
| PUT | `/api/orders/conversation/{id}/follow-up` | Toggle follow-up flag |
| GET | `/api/orders/conversation/follow-ups` | List open follow-ups |
| POST | `/api/orders/pos/{id}/pdf` | Generate PDF for PO |
| GET | `/api/orders/pos/{id}/clipboard` | Get clipboard text for PO |
| GET | `/api/orders/pos/{id}/confirmation-checklist` | Get confirmation checklist |
| POST | `/api/orders/pos/{id}/confirmation-checklist` | Update confirmation checklist |

### Services Used by Office

| Service | File | Lines | Purpose |
|---------|------|-------|---------|
| OrdersService | `orders_service.py` | 451 | JPO/PO lifecycle, status transitions, audit trail |
| PDFService | `pdf_service.py` | 312 | PO PDF generation |
| POConversationService | `po_conversation_service.py` | 684 | Conversation threads, follow-ups, supplier communications |
| ProcurementService | `procurement_service.py` | 258 | Reorder dashboard, supplier ranking |
| ReceivingService | `receiving_service.py` | 588 | Session-based receiving |
| ReturnsService | `returns_service.py` | 586 | Return sorting, eligibility checks |
| SpendingService | `spending_service.py` | 432 | Cost tracking, FIFO/LIFO, budget alerts |
| NotebookService | `notebook_service.py` | 989 | Template management for notebook templates tab |

### Models

| Model File | Lines | Content |
|------------|-------|---------|
| `models/orders.py` | 974 | JPO, PO, Returns, Staging, Conversations, Groups, Approvals, Confirmation Checklist, Receiving Sessions, Return Sorting |
| `models/costs.py` | — | Cost tracking models |

### Repositories

| Repository | File | Lines |
|------------|------|-------|
| Orders Repo | `orders_repo.py` | 640 |
| Staging Repo | `staging_repo.py` | — |

### Migrations

| Migration | File | Purpose |
|-----------|------|---------|
| 015 | `015_orders_procurement.sql` | Base orders schema |
| 018 | `018_orders_redesign_a.sql` | Phase 7A — Core Ordering |
| 019 | `019_orders_redesign_b.sql` | Phase 7B — Office Workflow (conversations, groups, approvals, checklists) |
| 020 | `020_orders_redesign_c.sql` | Phase 7C — Warehouse Workflow (sessions, return sorting) |
| 021-022 | `021/022_orders_redesign_d/e.sql` | Phase 7D/7E — Analytics, QoL enhancements |

---

## 2. Frontend Inventory

### Office Pages (`features/office/pages/`)

| File | Lines | Route | Description |
|------|-------|-------|-------------|
| `WarehouseExecPage.tsx` | 411 | `/office/warehouse-exec` | Executive dashboard — parts search, stock overview, quick actions |
| `ManageJobsPage.tsx` | 550 | `/office/manage-jobs` | Job CRUD — create/edit/archive jobs with customer assignment |
| `JobNotebookTemplatePage.tsx` | 755 | `/office/notebook-templates` | Full template editor — sections, entries, field types, default content |
| `WarehouseLocationsPage.tsx` | 467 | `/office/warehouse-locations` | Warehouse location CRUD — name, address, GPS, notes |
| `SpendingDashboardPage.tsx` | 531 | `/office/spending` | Cost analytics — FIFO/LIFO spending charts, budget alerts |
| `ApprovalsTab.tsx` | 516 | `/orders/approvals` | Unified approvals queue — JPOs + Returns, bulk approve/reject |
| `POManagementTab.tsx` | 616 | `/orders/purchase-orders` | PO list with status filters, supplier search, conversation badges |
| `ReviewAndSendPage.tsx` | 428 | `/orders/review-and-send` | Review PO groups, generate PDFs, clipboard copy, send-ready workflow |

**Note:** `ClockOutQuestionsPage.tsx` lives in `features/settings/pages/` but is mounted at `/office/clock-out-questions`.

### Office Components (`features/office/components/`)

| File | Lines | Description |
|------|-------|-------------|
| `ManageBillRateTypesModal.tsx` | 220 | CRUD modal for bill rate types (used by ManageJobsPage) |

### Navigation Config

```typescript
{
  id: 'office',
  label: 'Office',
  icon: 'Building2',
  path: '/office',
  permission: 'view_warehouse',
  tabs: [
    { id: 'warehouse-exec', label: 'Warehouse Executive', permission: 'manage_warehouse' },
    { id: 'manage-jobs', label: 'Manage Jobs', permission: 'manage_jobs' },
    { id: 'notebook-templates', label: 'Notebook Templates', permission: 'manage_notebooks' },
    { id: 'clock-out-questions', label: 'Clock-Out Questions', permission: 'manage_settings' },
    { id: 'warehouse-locations', label: 'Warehouse Locations', permission: 'manage_fleet' },
    { id: 'spending', label: 'Spending', permission: 'show_dollar_values' },
  ],
}
```

The Orders module ALSO has Office tabs (visible with `manage_orders` permission):
- `approvals` → ApprovalsTab
- `review-and-send` → ReviewAndSendPage
- `purchase-orders` → POManagementTab

### API Client

| File | Lines | Exported Functions |
|------|-------|--------------------|
| `api/orders.ts` | 910 | 69 functions — covers JPOs, POs, Returns, Staging, History, Ratings, Conversations, Groups, Approvals, Checklists, Receiving Sessions, Return Sorting, Bulk Operations |
| `api/costs.ts` | — | Spending dashboard and cost tracking |

### Orders Pages (Office-adjacent, under `/orders/`)

These pages live in `features/orders/pages/` but support the Office workflow:

| File | Lines | Route | Status |
|------|-------|-------|--------|
| `GeneratePOsPage.tsx` | 416 | `/orders/parts-requests/:id/generate-pos` | Functional |
| `NewPurchaseOrderPage.tsx` | 387 | `/orders/purchase-orders/new` | Functional |
| `PODetailPage.tsx` | 385 | `/orders/pos/:id` | Functional |
| `JPODetailPage.tsx` | 304 | `/orders/parts-requests/:id` | Functional |
| `ProcurementPage.tsx` | 664 | `/orders/procurement` | Functional |
| `ReceiveShipmentPage.tsx` | 719 | `/orders/purchase-orders/receive` | Functional |

### Legacy/Superseded Pages

| File | Lines | Status |
|------|-------|--------|
| `PendingOrdersPage.tsx` | 16 | **Stub** — empty redirect, superseded by ApprovalsTab |
| `ActiveOrdersPage.tsx` | 111 | Superseded by POManagementTab |
| `DraftOrdersPage.tsx` | 126 | Superseded by POManagementTab |
| `IncomingOrdersPage.tsx` | 165 | Superseded by ReceivingPage |
| `PurchaseOrdersPage.tsx` | 297 | Legacy — kept as `purchase-orders-legacy` route |
| `NewPartsRequestPage.tsx` | 390 | Superseded by UnifiedOrderPage |

---

## 3. Feature Completeness

### ✅ Fully Functional

| Feature | Notes |
|---------|-------|
| **Warehouse Executive Dashboard** | Parts search, stock overview, quick actions |
| **Manage Jobs** | Full CRUD with customer assignment, bill rate types modal |
| **Notebook Template Editor** | Section/entry CRUD, field types, default content, sort ordering |
| **Warehouse Locations** | Full CRUD with GPS, address, notes |
| **Spending Dashboard** | FIFO/LIFO cost charts, budget alerts, job cost rollup |
| **Approvals Queue** | Unified JPO + Return approvals with bulk actions |
| **PO Management** | Status filters, supplier search, conversation badges, bulk operations |
| **Review & Send** | PO groups, PDF generation, clipboard copy for email |
| **Clock-Out Questions** | Configuration UI (mounted from Settings) |
| **Bill Rate Types** | Modal CRUD for managing rate types |
| **PDF Generation** | Per-PO PDF creation |
| **Conversations** | CRM-style threads per PO, follow-up tracking |
| **Confirmation Checklists** | Per-line tracking on POs |

### ⚠️ Partially Implemented / Potential Gaps

| Area | Status | Notes |
|------|--------|-------|
| **PO Bundled PDF** | Functional | PDF generation is per-PO; the "bundle" concept uses PO Groups but actual combined PDF is not confirmed |
| **Supplier Portal** | Not implemented | Listed as a future phase — no self-service portal for suppliers |
| **Email Sending** | Not implemented | Review & Send generates PDFs and clipboard text, but there's no email integration — users must manually email |

---

## 4. Cross-References

### Office → Other Modules

| Office Page | Depends On |
|-------------|-----------|
| ManageJobsPage | Jobs router (CRUD), People (customer selection) |
| WarehouseExecPage | Parts router (catalog search), Warehouse (stock) |
| SpendingDashboardPage | Costs router, Orders (PO data) |
| JobNotebookTemplatePage | Notebooks router (template CRUD) |
| ClockOutQuestionsPage | Jobs router (questionnaire config) |
| WarehouseLocationsPage | Vehicles/Fleet (location assignment) |
| ApprovalsTab | Orders router (JPO/Return approvals) |
| POManagementTab | Orders router (PO listing, conversations) |
| ReviewAndSendPage | Orders router (PO groups, PDF, clipboard) |

### Other Modules → Office

| Module | Uses Office For |
|--------|----------------|
| Jobs | ManageJobsPage creates jobs that field workers see |
| Notebooks | Templates created in Office spawn notebooks on jobs |
| Warehouse | Receiving/Return pages link back to PO management |
| Orders Field | JPOs submitted by field workers appear in Office approvals |

---

## 5. Issues & TODOs

### No TODOs Found in Code
Zero `TODO`, `FIXME`, `HACK`, or `STUB` comments across all Office frontend and backend files. This module is clean.

### Structural Observations

1. **Split architecture:** Office-related pages live in THREE different feature folders:
   - `features/office/` (6 pages)
   - `features/orders/` pages linked from Orders tabs (ApprovalsTab, POManagementTab, ReviewAndSendPage live in `features/office/` but route under `/orders/`)
   - `features/settings/` (ClockOutQuestionsPage)
   
   This is intentional by design but may cause confusion during maintenance.

2. **Legacy pages:** 6 order pages are superseded but still exist in the codebase:
   - `PendingOrdersPage.tsx` (16 lines — essentially empty stub)
   - `ActiveOrdersPage.tsx`, `DraftOrdersPage.tsx`, `IncomingOrdersPage.tsx`
   - `PurchaseOrdersPage.tsx` (still routed as `purchase-orders-legacy`)
   - `NewPartsRequestPage.tsx`
   
   These should be candidates for the legacy cleanup plan.

3. **Permission gating:** Office tabs use `manage_warehouse`, `manage_jobs`, `manage_notebooks`, `manage_settings`, `manage_fleet`, `show_dollar_values` — all properly configured with granular permission checks.

4. **No dedicated Tools & Kits tab in Office:** Tool management lives under Warehouse (`/warehouse/tools`) and Trucks (`/trucks/tools`) but there's no Office-level tool administration page for managing the tool registry globally (maintenance type definitions, global settings). The warehouse ToolsPage serves as the de facto global management page.

### Size Summary

| Layer | Files | Total Lines |
|-------|-------|-------------|
| Backend (Office-specific endpoints in orders.py) | ~21 endpoints | ~400 lines in orders.py |
| Backend Services (shared) | 8 services | ~4,298 lines |
| Frontend Office pages | 9 files (8 pages + 1 component) | ~4,494 lines |
| Frontend API client (orders.ts) | 1 file | 910 lines |
| Models | orders.py + costs models | ~974+ lines |
