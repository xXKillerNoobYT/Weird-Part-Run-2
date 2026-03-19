# Orders System Redesign — Master Plan

> **Date:** 2026-03-03
> **Scope:** Complete redesign of Orders module (JPOs, POs, Returns, Procurement, Cost Tracking)
> **Approach:** 5 pre-planned phases, executed sequentially, big-bang deployment

---

## Context & Problem Statement

The current Orders system works but is **fragmented and confusing**. Key pain points:
- Flow is spread across too many pages (12 active pages)
- Two separate order flows (JPO vs standalone PO) are unclear to users
- Office management tasks live in the wrong module
- No unified dashboard, no visual timelines, no cost tracking
- Missing: job brand/supplier memory, special items, bulk actions, QR enhancements
- Detail pages show raw data without contextual guidance

**Goal:** Rebuild Orders into a **unified, role-aware, office-centric** system that's intuitive for field workers, efficient for office staff, and provides full cost visibility.

---

## Architecture Decisions (From User Feedback)

| Decision | Choice | Notes |
|----------|--------|-------|
| Navigation model | **Field vs Office split** | Field workers -> "My Orders", Office staff -> Office module tabs |
| Order type selection | **Toggle switch** | Job Order <-> Warehouse Restock at top of unified form |
| Multi-job orders | **Order groups at PO stage** | One order = one job. POs can be bundled into group PDFs for suppliers |
| Manager approvals | **Tab in Office module** | Not standalone page. Visible to users with manage_orders permission |
| Special items | **Inline + auto-flagged** | Added in main form, auto-flagged for office review |
| Job memory | **Smart suggestions + auto-filter** | Toggle on/off at top of form. Remembers brands, colors, suppliers per job |
| Receiving location | **Warehouse module** | Quantity entry per line (not checkboxes) |
| Cost model | **Company-wide weighted average** | FIFO for consumption, LIFO for returns. Margin on Parts Catalog page |
| QR images | **Hard requirement** | Must upload device photo + box photo to save barcode link |
| Daily report | **Live view (always current)** | Tab on Dashboard, real-time data |
| Notifications | **Enhanced bell + sound alert** | Audio chime for urgent. Push notifications in future phase |
| Communication history | **Conversation thread** | CRM-style per PO. Auto-logged + manual entries |
| Phasing | **Pre-plan all, execute sequentially** | Each phase ends with audit + next phase prep |

---

## Phase Overview

| Phase | Name | Focus | Key Deliverables | Status |
|-------|------|-------|-----------------|--------|
| **7A** | Core Ordering Experience | Unified order form, job memory, special items | New order form, job_preferences table, smart suggestions | ✅ Complete |
| **7B** | Office Workflow | PO management, approvals, PDF bundles | Office tabs, conversation threads, grouped PDFs | ✅ Complete |
| **7C** | Warehouse Workflow | Enhanced receiving, returns streamlining | Packing slip mode, return sorting guidance, staging | ✅ Complete |
| **7D** | Analytics & Visibility | Cost tracking, procurement, dashboard/reports | Weighted avg cost, margin management, daily report | ✅ Complete |
| **7E** | Quality of Life | Notifications, QR enhancements, bulk actions, help | Sound alerts, image requirements, bulk ops, help tooltips | ✅ Complete |

> **Note:** Using Phase 7 numbering since Phase 6 (Fleet) is complete.

---

## Phase 7A: Core Ordering Experience

### Goal
Replace the fragmented JPO creation + standalone PO creation with a **single unified order form** that handles both job orders and warehouse restocking, with smart job memory and special item support.

### Database Changes

**New table: `job_preferences`**
```sql
CREATE TABLE job_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    preference_type TEXT NOT NULL,  -- 'brand', 'color', 'supplier', 'part'
    entity_id INTEGER,              -- part_id, supplier_id, or NULL for text values
    text_value TEXT,                -- brand name, color name, etc.
    category TEXT,                  -- part category this applies to (e.g., 'outlets', 'switches')
    is_active INTEGER DEFAULT 1,
    auto_learned INTEGER DEFAULT 1, -- 1 = system learned, 0 = manually set
    confidence_score REAL DEFAULT 0.5, -- how confident the suggestion is
    last_used_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(job_id, preference_type, entity_id, text_value, category)
);

CREATE INDEX idx_job_prefs_job ON job_preferences(job_id, is_active);
CREATE INDEX idx_job_prefs_type ON job_preferences(preference_type, entity_id);
```

**New table: `special_items`**
```sql
CREATE TABLE special_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    jpo_id INTEGER REFERENCES job_parts_orders(id),
    description TEXT NOT NULL,
    part_number TEXT,           -- optional manufacturer part number
    quantity INTEGER NOT NULL DEFAULT 1,
    unit TEXT DEFAULT 'each',
    estimated_cost REAL,
    notes TEXT,
    is_flagged INTEGER DEFAULT 1,  -- auto-flagged for office review
    flag_resolved_by INTEGER REFERENCES users(id),
    flag_resolved_at TEXT,
    linked_part_id INTEGER REFERENCES parts(id),  -- if office matches to catalog
    created_at TEXT DEFAULT (datetime('now'))
);
```

**Alter `job_parts_orders` table:**
```sql
-- SQLite cannot ALTER NOT NULL, so the migration recreates the table with job_id nullable
ALTER TABLE job_parts_orders ADD COLUMN order_type TEXT DEFAULT 'job';  -- 'job' or 'warehouse'
ALTER TABLE job_parts_orders ADD COLUMN has_special_items INTEGER DEFAULT 0;
ALTER TABLE job_parts_orders ADD COLUMN smart_suggestions_enabled INTEGER DEFAULT 1;
```

### Backend Changes

**New service: `job_preferences_service.py`**
- `learn_from_order(jpo_id)` — After order creation, extract brand/color/supplier patterns and store in job_preferences
- `get_suggestions(job_id, category?)` — Return ranked suggestions for a job (brands, colors, suppliers)
- `get_preferred_supplier(job_id, part_id)` — For general parts, return last-used supplier for that part type on this job
- `toggle_preference(pref_id, is_active)` — Enable/disable a learned preference

**Updated service: `orders_service.py`**
- `create_jpo()` — Accept `order_type` field ('job' or 'warehouse')
- After creation, call `learn_from_order()` to update job preferences
- Accept `special_items` array in creation payload
- If warehouse restock: job_id is NULL, skip approval if configured

**New endpoints:**
- `GET /api/jobs/{job_id}/preferences` — Get all preferences for a job
- `PUT /api/jobs/{job_id}/preferences/{pref_id}` — Toggle/update preference
- `GET /api/jobs/{job_id}/suggestions?category=outlets` — Get smart suggestions
- `GET /api/orders/jpos/{jpo_id}/special-items` — List special items
- `POST /api/orders/jpos/{jpo_id}/special-items` — Add special item
- `PUT /api/orders/special-items/{item_id}/resolve` — Office resolves flagged item

### Frontend Changes

**New/Modified Pages:**

1. **`UnifiedOrderPage.tsx`** (replaces `NewPartsRequestPage` + `NewPurchaseOrderPage`)
   - Toggle switch at top: "Job Order <-> Warehouse Restock"
   - If Job Order: job selector -> loads job preferences -> color/brand auto-filter
   - Smart suggestion toggles (visible at top, easy on/off):
     - "Use job brands" (on/off)
     - "Use job colors" (on/off)
     - "Use job suppliers" (on/off)
   - Unified part search (merged CatalogBrowser + PartSearchModal)
   - "Add Special Item" button -> inline form section
   - Special items shown in line list with flag icon
   - Line items list with job tag, brand tag, color indicator
   - Save Draft / Submit buttons (no "Create & Submit")
   - Help button with explainer tooltips throughout

2. **`UnifiedPartSearch.tsx`** (replaces CatalogBrowser + PartSearchModal)
   - Responsive: inline panel on desktop, full modal on mobile
   - Sections: Recent Parts, Favorites, Suggestions, Search Results
   - Stock level color coding (green/amber/red)
   - Brand/color filter chips (from job preferences when active)
   - "Previously used on this job" badge on relevant parts

3. **Update `navigation.ts`**
   - Field workers: "My Orders" module with tabs:
     - "My Orders" (list of user's orders with status)
     - "New Order" (unified form)
     - "Returns" (initiate job-to-warehouse, view supplier return status)
   - Office: existing tabs remain for now (updated in 7B)

**Files to modify:**
- `frontend/src/lib/navigation.ts` — New module structure
- `frontend/src/App.tsx` — New routes
- `frontend/src/features/orders/pages/` — New UnifiedOrderPage
- `frontend/src/features/orders/components/` — New UnifiedPartSearch, SpecialItemForm
- `frontend/src/api/orders.ts` — New endpoints
- `frontend/src/lib/types.ts` — New types
- `backend/app/routers/orders.py` — New endpoints
- `backend/app/services/orders_service.py` — Updated create flow
- `backend/app/services/job_preferences_service.py` — New service
- `backend/app/repositories/orders_repo.py` — Updated queries
- `backend/app/models/orders.py` — Updated models
- `backend/app/migrations/018_orders_redesign_a.sql` — New migration

### Verification (Phase 7A)
1. Create a job order with parts -> verify job preferences are learned
2. Create another order for same job -> verify suggestions appear with correct brands/colors
3. Toggle suggestions on/off -> verify filtering changes
4. Add special items -> verify flag appears, office can resolve
5. Create warehouse restock order -> verify job selector is hidden, no approval required
6. Test on mobile (375x812), tablet (768x1024), desktop (1280x800)
7. Verify dark mode works on all new components
8. Run existing test suite to ensure no regressions

---

## Phase 7B: Office Workflow

### Goal
Build the **Office-centric PO management** experience: approvals tab, PO management by supplier, conversation threads, PDF bundle generation, and the "Review & Send" workflow.

### Database Changes

**New table: `po_conversations`**
```sql
CREATE TABLE po_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER REFERENCES purchase_orders(id),
    supplier_id INTEGER REFERENCES suppliers(id),
    entry_type TEXT NOT NULL,  -- 'note', 'call', 'email_summary', 'action', 'system'
    message TEXT NOT NULL,
    follow_up_needed INTEGER DEFAULT 0,
    follow_up_resolved_at TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_po_conv_po ON po_conversations(po_id, created_at);
CREATE INDEX idx_po_conv_supplier ON po_conversations(supplier_id, created_at);
CREATE INDEX idx_po_conv_followup ON po_conversations(follow_up_needed, follow_up_resolved_at);
```

**New table: `po_groups`**
```sql
CREATE TABLE po_groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_name TEXT,
    supplier_id INTEGER REFERENCES suppliers(id),
    created_by INTEGER REFERENCES users(id),
    pdf_path TEXT,                -- path to combined PDF
    individual_pdfs TEXT,         -- JSON array of individual PDF paths
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE po_group_members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER REFERENCES po_groups(id),
    po_id INTEGER REFERENCES purchase_orders(id),
    UNIQUE(group_id, po_id)
);
```

**Alter `purchase_orders` table:**
```sql
ALTER TABLE purchase_orders ADD COLUMN confirmation_checklist TEXT;  -- JSON: [{part_id, confirmed, confirmed_at}]
ALTER TABLE purchase_orders ADD COLUMN supplier_notes TEXT;
```

### Backend Changes

**New service: `po_conversation_service.py`**
- `add_entry(po_id, entry_type, message, user_id)` — Manual note/call/email entry
- `add_system_entry(po_id, message)` — Auto-logged actions (status changes, price updates)
- `get_thread(po_id)` — Full conversation for a PO
- `get_supplier_thread(supplier_id)` — All conversations across POs for a supplier
- `mark_follow_up(entry_id, resolved?)` — Toggle follow-up status

**Updated service: `pdf_service.py`**
- `generate_group_pdf(po_ids)` — Single PDF with all POs, each on its own section/page
- `generate_individual_pdfs(po_ids)` — Separate PDFs per PO, return folder path
- `open_pdf_folder(folder_path)` — Return the local path for the frontend to trigger OS file explorer

**New endpoints:**
- `GET /api/orders/pos/{po_id}/conversation` — Get conversation thread
- `POST /api/orders/pos/{po_id}/conversation` — Add entry
- `PUT /api/orders/conversation/{entry_id}/follow-up` — Toggle follow-up
- `POST /api/orders/pos/group` — Create PO group for bundled sending
- `POST /api/orders/pos/group/{group_id}/pdf` — Generate group PDF
- `POST /api/orders/pos/group/{group_id}/individual-pdfs` — Generate individual PDFs
- `GET /api/orders/office/pending-approvals` — All pending JPOs + returns for approval queue
- `POST /api/orders/pos/{po_id}/confirmation-checklist` — Update confirmation checklist

### Frontend Changes

**New Office Module Tabs:**

1. **`ApprovalsTab.tsx`** (Office module tab)
   - Queue of pending JPOs and pending returns
   - Bulk approve/reject with notes
   - Expandable rows to see line items inline
   - "Has Special Items" badge highlights flagged orders
   - One-click approve for routine orders

2. **`POManagementTab.tsx`** (Office module tab)
   - Supplier sidebar/dropdown to switch between suppliers
   - Active POs for selected supplier with status badges
   - Confirmation checklist: per-line checkbox "Confirmed ordered"
   - Conversation thread panel (right side on desktop, below on mobile)
   - Quick actions: Submit PO, Update Status, Generate PDF
   - "Review & Send" mode for converting approved JPOs -> POs

3. **`ReviewAndSendPage.tsx`** (replaces `GeneratePOsPage`)
   - Shows approved JPO lines grouped by suggested supplier
   - Drag to rearrange, merge, or split supplier groups
   - "Bundle for Same Supplier" — combine multiple job POs
   - Generate: Group PDF (single file) or Individual PDFs (one per PO)
   - After generation: show link to open folder in OS file explorer
   - PDF cleanup notice ("Files auto-delete after 3 days")

4. **`ConversationThread.tsx`** (shared component)
   - Threaded entries: system (gray), notes (blue), calls (green), emails (purple)
   - "Follow-up needed" flag with visual indicator
   - Add entry form with type selector
   - Timestamps with relative time ("2 hours ago")

**Files to modify:**
- `frontend/src/features/office/` — New tabs and components
- `frontend/src/lib/navigation.ts` — Office module tab updates
- `backend/app/services/po_conversation_service.py` — New
- `backend/app/services/pdf_service.py` — Group PDF, individual PDFs
- `backend/app/routers/orders.py` — New endpoints
- `backend/app/migrations/019_orders_redesign_b.sql` — New migration

### Verification (Phase 7B)
1. Approve JPO from Office Approvals tab -> verify status change, notification
2. Open PO Management -> switch suppliers -> verify correct POs shown
3. Add conversation entries (note, call, email) -> verify thread displays
4. Use confirmation checklist -> check off items -> verify persistence
5. Review & Send: group 3 POs -> generate group PDF -> verify content
6. Generate individual PDFs -> verify OS file explorer opens to folder
7. Test special item resolution from Office -> verify flag cleared
8. Full responsive audit at all 3 breakpoints
9. Run full test suite

---

## Phase 7C: Warehouse Workflow

### Goal
Redesign **receiving** (packing slip default + scan option), **streamline returns** (sorting guidance, condition checking), and improve the warehouse experience.

### Database Changes

**Alter `return_line_items` table:**
```sql
ALTER TABLE return_line_items ADD COLUMN returnable_to_supplier INTEGER DEFAULT 1;
ALTER TABLE return_line_items ADD COLUMN non_return_reason TEXT;  -- 'used', 'damaged', 'custom_modified', etc.
ALTER TABLE return_line_items ADD COLUMN below_target_flag INTEGER DEFAULT 0;  -- item below restock target
```

**New table: `receiving_sessions`**
```sql
CREATE TABLE receiving_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    po_id INTEGER REFERENCES purchase_orders(id),
    started_by INTEGER REFERENCES users(id),
    mode TEXT DEFAULT 'packing_slip',  -- 'packing_slip' or 'scan'
    completed_at TEXT,
    notes TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE receiving_session_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER REFERENCES receiving_sessions(id),
    po_line_id INTEGER REFERENCES po_line_items(id),
    expected_qty INTEGER,
    received_qty INTEGER DEFAULT 0,
    actual_cost REAL,
    staging_zone_id INTEGER REFERENCES staging_zones(id),
    scanned_at TEXT,
    notes TEXT
);
```

### Backend Changes

**Updated service: `receiving_service.py`**
- `start_session(po_id, mode, user_id)` — Create receiving session
- `receive_item(session_id, po_line_id, qty, actual_cost?, zone_id?)` — Record per-item receipt
- `complete_session(session_id)` — Finalize, create stock movements, update PO statuses
- `get_session_progress(session_id)` — Running total: received vs expected per line

**Updated service: `returns_service.py`**
- `check_return_eligibility(part_id, condition)` — Determine if returnable to supplier
- `check_below_target(part_id)` — Flag if part is below restock target
- `get_sorting_guidance(return_id)` — For each line: "Return to supplier" / "Keep in warehouse (below target)" / "Cannot return (used condition)"
- `process_sorted_return(return_id, dispositions[])` — Apply sorting decisions

### Frontend Changes

1. **`ReceivingPage.tsx`** (replaces `ReceiveShipmentPage`, in Warehouse module)
   - **Packing Slip Mode (default):**
     - Enter PO number -> see all expected line items
     - Each line: part name, expected qty, input for received qty
     - Visual running total bar (green = received, gray = remaining)
     - NO "Receive All" button
     - Large touch targets for mobile (qty input fields min 44px)
   - **Scan Mode (toggle):**
     - QR scanner active -> scan part -> find matching PO line -> enter qty
     - Audio beep on successful scan
   - Both modes: staging zone assignment per item, notes field

2. **`ReturnSortingPage.tsx`** (new, in Warehouse module)
   - Shows return items with sorting guidance
   - Per-item: condition selector, returnable status, reason if not returnable
   - "Below target" warning: "You only have 3 of target 10 — consider restocking instead"
   - Checklist: Check for damage, Check if opened/used, Check if custom modified
   - Color coding: green (return to supplier), amber (restock), red (write-off)

3. **Field worker Returns tab** (in My Orders module)
   - Create job-to-warehouse return (simplified 2-state flow)
   - View status of initiated returns
   - Read-only view of supplier return status for their jobs

**Files to modify:**
- `frontend/src/features/warehouse/pages/ReceivingPage.tsx` — New
- `frontend/src/features/warehouse/pages/ReturnSortingPage.tsx` — New
- `frontend/src/features/orders/pages/ReturnsPage.tsx` — Updated for field workers
- `backend/app/services/receiving_service.py` — Session-based receiving
- `backend/app/services/returns_service.py` — Sorting guidance, eligibility checks
- `backend/app/migrations/020_orders_redesign_c.sql` — New migration

### Verification (Phase 7C)
1. Packing slip receive: enter PO# -> see items -> enter quantities -> verify running total
2. Scan mode: scan QR -> verify correct PO line found -> enter qty
3. Partial shipment: receive 5 of 10 -> verify "partially_received" status
4. Return sorting: create return -> use sorting guidance -> verify dispositions applied
5. Below-target warning: return a part that's below target -> verify amber warning shown
6. Field worker: initiate job-to-warehouse return -> verify simplified flow
7. Mobile test: receiving on phone with large touch targets
8. Run full test suite

---

## Phase 7D: Analytics & Visibility

### Goal
Implement **weighted average cost tracking** (FIFO consumption, LIFO returns), **margin management**, **spending dashboard**, **job cost rollup**, and the **live daily report**.

### Database Changes

**New table: `cost_layers`** (for FIFO/LIFO tracking)
```sql
CREATE TABLE cost_layers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    purchase_date TEXT NOT NULL,
    po_line_id INTEGER REFERENCES po_line_items(id),
    original_qty INTEGER NOT NULL,
    remaining_qty INTEGER NOT NULL,
    unit_cost REAL NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    CHECK(remaining_qty >= 0)
);

CREATE INDEX idx_cost_layers_part ON cost_layers(part_id, remaining_qty);
CREATE INDEX idx_cost_layers_date ON cost_layers(part_id, purchase_date);
```

**Alter `parts` table:**
```sql
ALTER TABLE parts ADD COLUMN weighted_avg_cost REAL DEFAULT 0;
ALTER TABLE parts ADD COLUMN custom_margin_percent REAL;  -- NULL = use company default
ALTER TABLE parts ADD COLUMN cost_last_updated TEXT;
```

**New table: `company_cost_settings`**
```sql
CREATE TABLE company_cost_settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setting_key TEXT UNIQUE NOT NULL,
    setting_value TEXT NOT NULL,
    updated_by INTEGER REFERENCES users(id),
    updated_at TEXT DEFAULT (datetime('now'))
);
-- Seeds: default_margin_percent = '25', cost_method = 'weighted_average',
--         auto_update_pricing = 'true'
```

**Alter `jobs` table:**
```sql
ALTER TABLE jobs ADD COLUMN budget_limit REAL;  -- optional budget cap
ALTER TABLE jobs ADD COLUMN budget_alert_percent REAL DEFAULT 80;  -- warn at 80%
```

### Backend Changes

**New service: `cost_tracking_service.py`**
- `add_cost_layer(part_id, qty, unit_cost, po_line_id)` — On receive: add new cost layer
- `consume_fifo(part_id, qty)` — On job usage: remove oldest layers first, return weighted cost
- `return_lifo(part_id, qty)` — On return to warehouse: add back newest layers first
- `recalculate_weighted_average(part_id)` — Recompute from remaining layers
- `get_cost_history(part_id)` — All layers with remaining qty for audit
- `get_margin(part_id)` — Custom margin or company default
- `set_custom_margin(part_id, percent)` — Override margin
- `enforce_default_margin()` — Reset ALL parts to company default (the "Enforce Default" button)

**New service: `spending_service.py`**
- `get_spending_dashboard(date_from, date_to, group_by)` — Charts by supplier/category/job
- `get_job_cost_rollup(job_id)` — Total parts cost for a job (sum of PO costs via JPOs)
- `check_budget_alerts()` — Monthly + job budget threshold checks
- `get_price_variance_report(date_from, date_to)` — Received vs quoted price diffs
- `get_supplier_spend_analysis()` — Spend distribution across suppliers

**New endpoints:**
- `GET /api/costs/part/{part_id}/layers` — Cost layers for audit
- `GET /api/costs/part/{part_id}/history` — Cost trend over time
- `PUT /api/costs/part/{part_id}/margin` — Set custom margin
- `POST /api/costs/enforce-default-margin` — Reset all margins
- `GET /api/costs/dashboard` — Spending charts data
- `GET /api/costs/job/{job_id}/rollup` — Job cost summary
- `GET /api/costs/variance-report` — Price variance report
- `GET /api/costs/supplier-analysis` — Supplier spend analysis
- `GET /api/dashboard/daily-report` — Live daily report data

### Frontend Changes

1. **Parts Catalog: Cost & Margin section** (on part detail page)
   - Current weighted average cost display
   - Cost history sparkline
   - Margin setting: "Company Default (25%)" or custom override
   - Calculated sell price display
   - Permission-gated: only visible to users with `show_dollar_values`

2. **Office Spending Dashboard** (new tab in Office module)
   - Monthly/quarterly spending charts (bar, line)
   - Breakdowns: by supplier, by category, by job
   - Price variance highlights (amber for >5% variance, red for >15%)
   - Supplier spend pie chart
   - "Enforce Default Margin" button (with confirmation modal)

3. **Job Cost Rollup** (on job detail page)
   - Total parts ordered, total cost, budget remaining (if budget set)
   - Budget progress bar (green -> amber -> red as approaching limit)
   - Role-based: field workers see job costs, not company-wide data

4. **Dashboard Daily Report Tab**
   - Live "Today" view
   - Pending actions count with links
   - Expected deliveries this week
   - Overdue items highlighted
   - Quick action buttons
   - Date doesn't change — always shows current real-time data

**Files to modify:**
- `backend/app/services/cost_tracking_service.py` — New
- `backend/app/services/spending_service.py` — New
- `backend/app/routers/costs.py` — New router
- `frontend/src/features/parts/` — Cost section on part detail
- `frontend/src/features/office/` — Spending dashboard tab
- `frontend/src/features/jobs/` — Cost rollup on job detail
- `frontend/src/features/dashboard/` — Daily report tab
- `backend/app/migrations/021_orders_redesign_d.sql` — New migration

### Verification (Phase 7D)
1. Receive 10 units at $100, then 5 at $80 -> verify weighted avg = $93.33
2. Consume 1 unit (FIFO) -> verify oldest layer decremented, avg recalculated to $92.86
3. Return 1 unit (LIFO) -> verify newest layer incremented, avg recalculated
4. Set custom margin on a part -> verify sell price updates
5. Click "Enforce Default" -> verify all custom margins cleared
6. Check job cost rollup -> verify matches sum of PO costs
7. Set job budget -> approach limit -> verify amber/red warning
8. Verify field workers can see job costs but NOT company-wide spending
9. Daily report tab -> verify live data, pending actions, deliveries
10. Full responsive + dark mode audit

---

## Phase 7E: Quality of Life

### Goal
Enhanced **notifications with sound**, **QR scanning with image requirements**, **bulk actions** on all list pages, and **help buttons** throughout.

### Database Changes

**Alter `parts` table:**
```sql
ALTER TABLE parts ADD COLUMN device_image_url TEXT;
ALTER TABLE parts ADD COLUMN box_image_url TEXT;
ALTER TABLE parts ADD COLUMN qr_images_complete INTEGER DEFAULT 0;
```

**New table: `notification_sounds`**
```sql
CREATE TABLE notification_sounds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    notification_type TEXT NOT NULL,
    sound_enabled INTEGER DEFAULT 0,
    sound_file TEXT DEFAULT 'chime.mp3',
    UNIQUE(notification_type)
);
```

### Backend Changes

**Updated notification service:**
- Trigger notifications on: JPO submitted, JPO approved/rejected, PO submitted, PO overdue, shipment received, return approved, delay detected
- Include `is_urgent` flag for sound-triggering notifications
- New endpoint: `GET /api/notifications/settings` — Sound preferences

**Updated parts endpoints:**
- `PUT /api/parts/{part_id}/qr-link` — Now requires `device_image` + `box_image` file uploads
- Validation: reject if either image missing
- `GET /api/parts/{part_id}/images` — Return both images

**New bulk endpoints:**
- `POST /api/orders/jpos/bulk-approve` — Approve multiple JPOs
- `POST /api/orders/pos/bulk-submit` — Submit multiple POs
- `POST /api/orders/pos/bulk-status` — Update status on multiple POs
- `POST /api/orders/returns/bulk-approve` — Approve multiple returns

### Frontend Changes

1. **Notification Enhancements**
   - `NotificationBell.tsx` — Add sound playback on urgent notifications
   - Sound preferences in user settings (on/off per notification type)
   - Audio chime file: `/public/sounds/chime.mp3`
   - Respect browser audio policies (user interaction required first)

2. **QR Scanning Enhancements**
   - Update QR link flow: require device photo + box photo upload
   - Image upload component with camera capture or file picker
   - Preview of both images before saving
   - Parts without complete images show "Needs Images" badge in catalog

3. **Bulk Actions** (added to all list pages)
   - `BulkActionBar.tsx` — Shared component
     - Checkbox column on tables
     - Select All / Deselect All in header
     - Floating action bar when items selected
     - Action buttons based on context (Approve, Submit, Cancel)
     - Count badge: "3 items selected"
   - Applied to: PartsRequestsPage, PurchaseOrdersPage, ReturnsPage
   - Smart filtering: filter first, then Select All applies to filtered results

4. **Help System**
   - `HelpButton.tsx` — Small "?" icon button
   - Opens tooltip/popover with:
     - Brief explanation of the current section
     - Example of how to use it
     - Link to more detailed help (future)
   - Placed on: order form sections, status badges, approval queue, receiving page
   - Content stored in a `helpContent.ts` map (easy to update)

5. **Cleanup & Migration**
   - Remove legacy pages: DraftOrdersPage, ActiveOrdersPage, IncomingOrdersPage, PendingOrdersPage
   - Remove old routes and redirects
   - Update all navigation references
   - Consolidate PartSearchModal + CatalogBrowser references to UnifiedPartSearch

**Files to modify:**
- `frontend/src/components/ui/NotificationBell.tsx` — Sound support
- `frontend/src/features/orders/components/BulkActionBar.tsx` — New
- `frontend/src/features/orders/components/HelpButton.tsx` — New
- `frontend/src/features/parts/` — QR image upload flow
- All list pages — Add checkbox column + BulkActionBar
- `backend/app/routers/orders.py` — Bulk endpoints
- `backend/app/routers/parts.py` — Updated QR link validation
- `backend/app/migrations/022_orders_redesign_e.sql` — New migration

### Verification (Phase 7E)
1. Trigger urgent notification -> verify sound plays (if enabled)
2. Toggle sound off in settings -> verify no sound
3. Add QR code without images -> verify form blocks save
4. Add QR code with both images -> verify saves and displays
5. Bulk approve 5 JPOs -> verify all status changes
6. Bulk submit 3 POs -> verify all submitted
7. Filter list -> Select All -> verify only filtered items selected
8. Help buttons -> verify tooltips appear with useful content
9. Verify all legacy pages removed, no broken links
10. **Full end-to-end audit: complete order lifecycle from creation -> approval -> PO -> receive -> return -> cost tracking**
11. Responsive audit at all 3 breakpoints
12. Dark mode audit on all new/modified pages

---

## Cross-Phase Concerns

### Role-Based Visibility Summary

| Feature | Field Worker | Office Staff | Manager |
|---------|-------------|-------------|---------|
| Create orders | Yes (job orders) | Yes (job + warehouse) | Yes (all) |
| View own orders | Yes | Yes | Yes |
| Approve orders | No | No | Yes |
| PO Management | No | Yes | Yes |
| Receiving | No | Yes | Yes |
| Initiate returns | Yes (job-to-warehouse) | Yes (both types) | Yes |
| Approve returns | No | No | Yes |
| View job costs | Yes (own jobs only) | Yes (all jobs) | Yes |
| View company costs | No | Yes | Yes |
| Set margins | No | Yes | Yes |
| Procurement dashboard | No | Yes | Yes |

### Existing Code to Reuse

| Component/Pattern | Location | Reuse For |
|-------------------|----------|-----------|
| WizardStepper | `warehouse/components/WizardStepper.tsx` | Visual timeline on detail pages |
| QRScannerBubble | `warehouse/components/QRScannerBubble.tsx` | Scan mode in receiving |
| NotificationBell | `components/ui/NotificationBell.tsx` | Enhanced with sound |
| EditableCell | `office/pages/WarehouseExecPage.tsx` | Inline editing pattern |
| Modal | `components/ui/Modal.tsx` | All new modals |
| Badge | `components/ui/Badge.tsx` | Status badges, flags |
| EmptyState | `components/ui/EmptyState.tsx` | Empty list states |
| OrderStatusBadge | `orders/components/OrderStatusBadge.tsx` | Extend for new statuses |
| movement-wizard-store | `warehouse/stores/movement-wizard-store.ts` | Pattern for receiving session store |

### Migration Strategy

All 5 migrations (018-022) are **additive** — new tables and ALTER TABLE ADD COLUMN only. No destructive changes. Old endpoints continue working during development. New UI components are added alongside old ones, then old ones are removed in Phase 7E cleanup.

### Testing Strategy Per Phase

Each phase ends with:
1. **Unit verification** — Each new feature tested individually
2. **Integration test** — Full workflow from start to finish
3. **Responsive audit** — All 3 breakpoints (mobile, tablet, desktop)
4. **Dark mode audit** — All new/modified components
5. **Permission audit** — Test with field worker, office staff, and manager roles
6. **Regression check** — Existing features still work
7. **Plan update** — Document what changed, update next phase if needed

---

## File Impact Summary

### New Files (~25)
- `backend/app/services/job_preferences_service.py`
- `backend/app/services/po_conversation_service.py`
- `backend/app/services/cost_tracking_service.py`
- `backend/app/services/spending_service.py`
- `backend/app/routers/costs.py`
- `backend/app/migrations/018_orders_redesign_a.sql`
- `backend/app/migrations/019_orders_redesign_b.sql`
- `backend/app/migrations/020_orders_redesign_c.sql`
- `backend/app/migrations/021_orders_redesign_d.sql`
- `backend/app/migrations/022_orders_redesign_e.sql`
- `frontend/src/features/orders/pages/UnifiedOrderPage.tsx`
- `frontend/src/features/orders/components/UnifiedPartSearch.tsx`
- `frontend/src/features/orders/components/SpecialItemForm.tsx`
- `frontend/src/features/orders/components/BulkActionBar.tsx`
- `frontend/src/features/orders/components/HelpButton.tsx`
- `frontend/src/features/orders/components/ConversationThread.tsx`
- `frontend/src/features/office/pages/ApprovalsTab.tsx`
- `frontend/src/features/office/pages/POManagementTab.tsx`
- `frontend/src/features/office/pages/ReviewAndSendPage.tsx`
- `frontend/src/features/office/pages/SpendingDashboardTab.tsx`
- `frontend/src/features/warehouse/pages/ReceivingPage.tsx`
- `frontend/src/features/warehouse/pages/ReturnSortingPage.tsx`
- `frontend/src/features/dashboard/components/DailyReportTab.tsx`
- `frontend/src/api/costs.ts`
- `frontend/src/lib/helpContent.ts`

### Modified Files (~20)
- `backend/app/routers/orders.py`
- `backend/app/services/orders_service.py`
- `backend/app/services/receiving_service.py`
- `backend/app/services/returns_service.py`
- `backend/app/services/pdf_service.py`
- `backend/app/repositories/orders_repo.py`
- `backend/app/models/orders.py`
- `frontend/src/App.tsx`
- `frontend/src/lib/navigation.ts`
- `frontend/src/lib/types.ts`
- `frontend/src/api/orders.ts`
- `frontend/src/components/ui/NotificationBell.tsx`
- `frontend/src/features/parts/` (detail page for costs)
- `frontend/src/features/jobs/` (detail page for cost rollup)
- `frontend/src/features/dashboard/` (daily report)
- `frontend/src/features/orders/components/OrderStatusBadge.tsx`

### Deleted Files (Phase 7E cleanup)
- `frontend/src/features/orders/pages/DraftOrdersPage.tsx`
- `frontend/src/features/orders/pages/ActiveOrdersPage.tsx`
- `frontend/src/features/orders/pages/IncomingOrdersPage.tsx`
- `frontend/src/features/orders/pages/PendingOrdersPage.tsx`
- `frontend/src/features/orders/pages/NewPartsRequestPage.tsx` (replaced by UnifiedOrderPage)
- `frontend/src/features/orders/pages/NewPurchaseOrderPage.tsx` (replaced by UnifiedOrderPage)
- `frontend/src/features/orders/pages/GeneratePOsPage.tsx` (replaced by ReviewAndSendPage)
- `frontend/src/features/orders/components/CatalogBrowser.tsx` (replaced by UnifiedPartSearch)
- `frontend/src/features/orders/components/PartSearchModal.tsx` (replaced by UnifiedPartSearch)

---

## Production Readiness Checklist

Every phase must meet ALL of these criteria before moving to the next:

### Code Quality
- [ ] All new code has proper TypeScript types (no `any`)
- [ ] All API endpoints have proper error handling with meaningful messages
- [ ] All database queries use parameterized statements (no SQL injection)
- [ ] All new components follow existing patterns (Card, Modal, Button variants)
- [ ] All new services have proper logging for debugging
- [ ] Comments on complex logic explaining "why", not "what"

### User Experience
- [ ] Every new page/component tested at 375x812 (mobile), 768x1024 (tablet), 1280x800 (desktop)
- [ ] All touch targets minimum 44x44px on mobile
- [ ] No horizontal overflow on any viewport
- [ ] Dark mode works correctly on all new/modified components
- [ ] Loading states shown during API calls (spinners, skeleton screens)
- [ ] Error states handled gracefully (toast messages, retry options)
- [ ] Empty states shown when no data (EmptyState component)
- [ ] All forms validate before submission with clear error messages

### Security & Permissions
- [ ] All new endpoints check appropriate permissions (view_orders, manage_orders, approve_returns)
- [ ] Role-based visibility enforced (field workers can't see company costs)
- [ ] No sensitive data leaked in API responses to unauthorized roles
- [ ] File uploads validated (image types only for QR photos, size limits)

### Data Integrity
- [ ] All new migrations are additive (no destructive changes)
- [ ] Foreign key constraints properly defined
- [ ] Unique constraints prevent duplicate data
- [ ] Cost calculations verified with multiple test scenarios
- [ ] FIFO/LIFO logic verified with edge cases (zero qty, negative balance prevention)

### Performance
- [ ] List pages handle 100+ items without lag
- [ ] Search debounce (300ms) on all search inputs
- [ ] TanStack Query cache keys are correct (no stale data bugs)
- [ ] Large PDFs generate within 5 seconds
- [ ] Notification polling doesn't cause memory leaks

---

## Future Phases (Post-7E) — Roadmap

These are the next areas to plan after all Orders redesign phases are complete:

### Phase 8: Tools & Equipment Tracking
- Tool inventory management (drills, meters, ladders, etc.)
- Tool checkout/return system (who has what tool)
- Maintenance schedules for tools
- Tool condition tracking and replacement alerts
- QR codes on tools for quick checkout via scan
- Integration with Jobs (which tools needed per job type)

### Phase 9: Server-Free Syncing
- Peer-to-peer or local-network sync between devices (no cloud server dependency)
- Conflict resolution strategy for concurrent edits
- SQLite WAL-based replication or CRDT-based approach
- Automatic discovery of other devices on LAN
- Sync status indicators (connected, syncing, up-to-date, conflict)
- Selective sync (choose which data categories to sync)
- Fallback to manual export/import if network unavailable

### Phase 10: Reporting & Business Intelligence
- Comprehensive reports page (user activity, order history, spending trends)
- Custom report builder (select date range, filters, columns)
- Export to CSV/PDF
- Audit trail reports (who did what, when)
- Supplier performance scorecards
- Job profitability analysis
- Inventory turnover reports

### Phase 11: Customer & General Management
- Customer/General contractor management (contacts, jobs, billing)
- Quote generation system
- Invoice tracking
- Payment status tracking
- Customer communication history

### Phase 12: Advanced Integrations
- Email integration (send POs directly via email from the app)
- Accounting software integration (QuickBooks, etc.)
- Supplier portal (suppliers can acknowledge POs, update delivery dates)
- Browser push notifications (Service Worker + Push API)
- Calendar integration for delivery scheduling

### Phase 13: Mobile App Enhancements
- Progressive Web App (PWA) setup for mobile install
- Offline mode for field workers (sync when back online)
- Camera-first workflows (scan, photograph, document)
- GPS integration for delivery tracking

---

## Remaining Project TODO (Full Roadmap)

> This is the overall project status. Phases 1-6 are complete. Phase 7 (this plan) is the Orders redesign.

| Phase | Name | Status | Notes |
|-------|------|--------|-------|
| 1 | Foundation | Complete | Auth, layout, dark mode, base UI |
| 2 | Parts & Inventory | Complete | Parts catalog, categories, suppliers |
| 3 | Warehouse & Movements | Complete | Stock movements, staging zones |
| 3.5+4 | Jobs & Labor | Complete | Jobs, clock-in/out, labor tracking |
| 4.5 | Notebooks | Complete | Unified notebook system |
| 5 | Orders & Procurement | Complete | Original orders system (being redesigned) |
| 6 | Fleet & Vehicle Management | Complete | 10 tables, 35 endpoints, 7 pages |
| **7A** | **Core Ordering Experience** | ✅ Complete | Unified form, job memory, special items |
| **7B** | **Office Workflow** | ✅ Complete | PO management, approvals, PDF bundles |
| **7C** | **Warehouse Workflow** | ✅ Complete | Receiving, returns streamlining |
| **7D** | **Analytics & Visibility** | ✅ Complete | Cost tracking (FIFO/LIFO), margins, spending dashboard, job cost rollup |
| **7E** | **Quality of Life** | ✅ Complete | Notification sounds, QR enhancements, bulk actions |
| 8 | People Full | ✅ Complete | Employees, certifications, wages, skills, hats, permissions |
| 9 | Tools & Kits | ✅ Complete | Tool registry, kit verification, checkout/return, maintenance |
| 10 | People, Contacts & Scheduling | ✅ Complete | Customers, GCs, contacts, scheduling, dispatch, time-off, subcontractors |
| 11 | Reports & Pre-Billing | Planned | Pre-billing exports, timesheets, labor overview, export bundles |
| — | V1.0 Deployment | Planned | Shop server package, Capacitor mobile apps, production hardening |
