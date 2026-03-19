# Phase 17 — Orders System Audit Gap Closure

> **Created:** 2026-03-09
> **Completed:** 2026-03-11
> **Status:** ✅ Complete — All 5 gaps implemented, build clean (0 TS errors), 218 tests passing.
> **Scope:** Close remaining gaps identified in the orders-system-audit.md. Everything here stems from the user's own feedback notes in that audit.
> **Depends on:** Phase 16 (UX Polish & Admin Hub) should be complete or in-progress first.
> **Audit source:** `docs/plans/Audit/orders-system-audit.md`

---

## Context

The orders system audit (dated 2026-03-03) contained extensive user feedback across JPO lifecycle, PO lifecycle, returns, procurement, cross-system connections, and page inventory. Most of those requirements were implemented during the Orders Redesign (Phase 7A-7E) and subsequent gap closures. However, a careful re-read of every user note reveals **5 gaps** that still need attention.

### What's Already Done (verified ✅)

These audit items are fully implemented — no work needed:

| Requirement | Status | Evidence |
|---|---|---|
| Unified order form (job/warehouse toggle) | ✅ | `UnifiedOrderPage.tsx` |
| Office page integration (all management tabs) | ✅ | `ApprovalsTab`, `POManagementTab`, `ReviewAndSendPage` |
| Manager approval tab | ✅ | `ApprovalsTab.tsx` + pending-approvals API |
| Special items in orders | ✅ | `SpecialItemForm.tsx` + 4 API endpoints |
| Suggestions during ordering | ✅ | `CompanionSuggestionCard.tsx` + companion engine |
| Job brand preferences (category-specific) | ✅ | `job_preferences` table with category column |
| Supplier acknowledgment flow | ✅ | Supplier portal + acknowledge endpoint |
| PO conversation/communication tracking | ✅ | `po_conversations` table + `POConversationService` |
| PDF generation with branding | ✅ | `PDFService` (fpdf2) |
| Notification on JPO creation | ✅ | "jpo_approval" notification type |
| PO management by supplier | ✅ | `POManagementTab.tsx` (3-panel layout) |
| Bulk management | ✅ | `BulkActionBar.tsx` + 4 bulk APIs |
| Both return types | ✅ | `job_to_warehouse` + `warehouse_to_supplier` |
| All 3 procurement views | ✅ | Reorder Alerts, Supplier Groups, Kanban |
| Review & Send in office | ✅ | `ReviewAndSendPage.tsx` |
| Email sending for POs | ✅ | `SendEmailModal.tsx` + `email_service.py` |
| Group/bundled PDFs | ✅ | `po_groups` + `generate_group_pdf()` |
| Confirmation checklist | ✅ | Per-PO per-line checkboxes in POManagementTab |

---

## Remaining Gaps (5 items)

### Gap 1: Category-Specific Supplier Preferences Per Job

**User quote:** *"If that part was ordered for that job through Electrical Wholesale, I wanted to remember that... that way when more of the same parts ordered... we get the exact same one from the same supplier."*

**Current state:** Supplier preferences are learned at the job level (`category=None` hardcoded in `job_preferences_service.py:346`). Brands and colors are already category-specific, but suppliers aren't. So if Job A uses Electrical Wholesale for outlets and Grainger for switches, the system can't distinguish — it just remembers "Electrical Wholesale for this job."

**What to do:**

1. **Backend: `job_preferences_service.py`** — Change `learn_from_order()` to pass the category when learning supplier preferences:
   ```python
   # Line ~346: Change from:
   category=None,    # suppliers aren't category-specific
   # To:
   category=category_name,  # remember supplier per category per job
   ```

2. **Backend: `get_preferred_supplier_for_part()`** — Update to prefer category-specific match, falling back to job-level:
   - First try: supplier preference for this job + this category
   - Fallback: supplier preference for this job (any category)
   - This ensures existing data still works

3. **Frontend: `UnifiedOrderPage.tsx`** — When showing supplier suggestions, include the category context: "Electrical Wholesale (used for Outlets on this job)"

**Effort:** Small — 2 backend edits + 1 frontend tweak

---

### Gap 2: Supplier Portal — Ongoing Notes & Communication

**User quote:** *"Have a note section for the supplier to add any notes about the order. Like if there's a delay or if they need more information. That way we can keep all the communication in one place."*

**Current state:** The supplier portal only allows notes during the **one-time acknowledgment** (`POST /view/pos/{id}/acknowledge` with `supplier_notes`). After acknowledgment, the supplier has no way to add follow-up notes about delays, questions, or changes.

**What to do:**

1. **Backend: `supplier_portal.py`** — Add a new public endpoint:
   ```
   POST /api/supplier-portal/view/pos/{po_id}/note
   Body: { "message": "..." }
   ```
   - Validates token, creates a `po_conversations` entry with `entry_type='supplier_note'`
   - Marks it with `created_by_supplier=true` flag (or use `created_by=0` convention)

2. **Backend: `po_conversation_service.py`** — Add `entry_type='supplier_note'` to the allowed types

3. **Frontend: `SupplierPortalPage.tsx`** — Add a "Add Note" form below the acknowledge section (or replace it after acknowledgment). Supplier sees their PO, the existing notes, and can submit follow-ups.

4. **Frontend: `ConversationThread.tsx`** — Style supplier-submitted notes distinctly (different color/icon) so office staff can immediately see which notes came from the supplier vs internal.

**Effort:** Medium — 1 new endpoint, 1 service change, 2 frontend updates

---

### Gap 3: PDF Template System

**User quote:** *"Have a template system for those PDFs so that we can easily generate them without having to manually format each one. That would save us a lot of time and help us keep everything consistent."*

**Current state:** PDF generation is hardcoded in `pdf_service.py` using fpdf2. The layout (company header, PO number, dates, line items table, totals, notes) is baked into Python code. No way for the user to customize layout, logo, fonts, or sections without editing code.

**What to do:**

1. **Backend: Settings-based PDF configuration** — Store PDF template settings in the `settings` table:
   ```
   pdf.company_name      → Company name for header
   pdf.company_address   → Company address lines
   pdf.company_phone     → Phone number
   pdf.company_email     → Email
   pdf.company_logo_path → Path to logo file (uploaded separately)
   pdf.accent_color      → Hex color for header/accent bars
   pdf.footer_text       → Custom footer text (e.g. "Thank you for your business!")
   pdf.show_unit_prices  → true/false — whether to show unit price column
   pdf.show_extended     → true/false — whether to show line extended totals
   pdf.delivery_notes    → Default delivery instructions text
   pdf.payment_terms     → Default payment terms text
   ```

2. **Backend: `pdf_service.py`** — Refactor `_build_pdf()` to read these settings and use them:
   - Company name/address from settings instead of hardcoded
   - Logo from settings path
   - Accent color from settings
   - Conditional columns (unit prices, extended totals)
   - Footer text from settings
   - Default delivery/payment terms from settings

3. **Frontend: PDF Settings page** — Add "PDF & Documents" page in Office (or Settings → Documents):
   - Form to edit all the above settings
   - Logo upload with preview
   - Live preview panel showing a sample PDF with current settings
   - "Reset to Defaults" button

4. **Backend: Logo upload endpoint** — `POST /api/settings/logo` to upload and store company logo file

**Effort:** Medium-Large — Settings CRUD, PDF service refactor, new frontend page, logo upload

---

### Gap 4: Cross-Job Aggregate Summary

**User quote:** *"Straightforward summary. How many of each part ordered, how many jobs are affected."*

**Current state:** `ReviewAndSendPage` shows supplier groupings per individual JPO (expand one order at a time). `POManagementTab` shows POs by supplier. Neither shows a cross-job aggregate like "You're ordering 15 outlets total across 3 jobs."

**What to do:**

1. **Backend: New endpoint** — `GET /api/orders/office/order-summary`:
   - Aggregates all approved (unprocessed) JPO lines
   - Groups by part (or part category/type)
   - Returns: part name, total quantity needed, number of distinct jobs affected, list of job names
   - Optionally groups by supplier too

2. **Frontend: `ReviewAndSendPage.tsx`** — Add a **Summary Card** at the top (above the per-JPO list):
   - "15 parts needed across 3 jobs from 2 suppliers"
   - Expandable table: Part Name | Total Qty | Jobs | Suggested Supplier
   - This gives the office the bird's-eye view before expanding individual JPOs

**Effort:** Medium — 1 new endpoint, 1 frontend summary section

---

### Gap 5: Preferred Supplier Per Job (as explicit setting, not just learned)

**User quote:** *"I want to be able to select a preferred supplier for a job. So I want to have a job that uses electrical wholesale. We get as many parts as we can through electrical wholesale, then we'll go to a backup supplier for the parts that they don't carry."*

**Current state:** Supplier preferences are **learned implicitly** from past orders (via `learn_from_order()`). There's no way for the user to **explicitly set** "Job X uses Electrical Wholesale as its primary supplier." The learning happens after the first order, not before.

**What to do:**

1. **Backend: `job_preferences_service.py`** — Add explicit preference methods:
   ```python
   async def set_preferred_supplier(self, job_id: int, supplier_id: int, priority: int = 1) -> dict:
       """Explicitly set a preferred supplier for a job. Priority 1 = primary, 2 = backup."""
   
   async def get_preferred_suppliers(self, job_id: int) -> list[dict]:
       """Get explicitly set suppliers for a job, ordered by priority."""
   ```
   - Uses `job_preferences` with `preference_type='explicit_supplier'` and `confidence_score` as priority

2. **Backend: New endpoint** — `PUT /api/jobs/{job_id}/preferred-supplier`:
   ```json
   { "supplier_id": 5, "priority": 1 }
   ```
   Also `DELETE /api/jobs/{job_id}/preferred-supplier/{supplier_id}`

3. **Frontend: Job Detail** — In the Job Settings or Overview tab, add a "Preferred Suppliers" section:
   - Primary supplier (dropdown)
   - Backup supplier(s) (optional, draggable priority)
   - When creating orders for this job, auto-populate the supplier from this list
   - Falls back to learned preferences if no explicit preference set

4. **Auto-generation awareness** — `create_po_from_jpo()` should check explicit preferred suppliers first, then fall back to learned preferences, then to global supplier rankings.

**Effort:** Medium — 2-3 new endpoints, service additions, frontend section on job detail

---

## Implementation Order

| Priority | Gap | Effort | Rationale |
|----------|-----|--------|-----------|
| 1 | Gap 1: Category-specific supplier preferences | Small | Trivial code change with big impact on ordering accuracy |
| 2 | Gap 5: Explicit preferred supplier per job | Medium | Directly addresses user's core workflow request |
| 3 | Gap 4: Cross-job aggregate summary | Medium | Important for office visibility before sending orders |
| 4 | Gap 2: Supplier portal ongoing notes | Medium | Enables the supplier communication loop the user described |
| 5 | Gap 3: PDF template system | Medium-Large | Important but lower urgency — current PDFs work, just not customizable |

---

## Migration Plan

| Migration | Table(s) | Contents |
|-----------|----------|----------|
| None needed for Gap 1 | — | `job_preferences` schema already supports category on suppliers |
| None needed for Gap 2 | — | `po_conversations` already supports new entry types |
| `049_pdf_settings.sql` | `settings` rows | Default PDF template settings |
| None needed for Gap 4 | — | Aggregation query only |
| None needed for Gap 5 | — | Uses existing `job_preferences` table with new preference_type |

---

## Completion Gates

- [x] Supplier preferences learned per category (outlets → Supplier A, switches → Supplier B)
- [x] `get_preferred_supplier_for_part()` checks category-specific match first
- [x] Frontend shows category context on supplier suggestions
- [x] Explicit preferred supplier settable on job detail page
- [x] Primary + backup supplier priority ordering
- [x] PO auto-generation uses explicit preferred suppliers
- [x] Cross-job summary card on ReviewAndSendPage
- [x] Summary shows total parts, distinct jobs, supplier breakdown
- [x] Supplier portal supports ongoing note submission
- [x] Supplier notes appear distinctly in ConversationThread
- [x] PDF settings configurable (company info, logo, colors, columns)
- [x] PDF service reads settings instead of hardcoded values
- [x] Logo upload functional
- [x] `vite build` passes — 0 TS errors, built in 15.39s
- [x] `pytest tests/ -v` all pass — 218 passed, 0 failures

---

## Files Affected (estimated)

**Backend:**
- `backend/app/services/job_preferences_service.py` (Gaps 1, 5)
- `backend/app/services/pdf_service.py` (Gap 3)
- `backend/app/services/po_conversation_service.py` (Gap 2)
- `backend/app/routers/supplier_portal.py` (Gap 2)
- `backend/app/routers/orders.py` (Gap 4)
- `backend/app/routers/jobs.py` (Gap 5)
- `backend/app/models/orders.py` (Gaps 2, 4)
- `backend/app/migrations/049_pdf_settings.sql` (Gap 3)

**Frontend:**
- `frontend/src/features/orders/pages/UnifiedOrderPage.tsx` (Gap 1)
- `frontend/src/features/office/pages/ReviewAndSendPage.tsx` (Gap 4)
- `frontend/src/features/settings/pages/SupplierPortalPage.tsx` (Gap 2)
- `frontend/src/features/orders/components/ConversationThread.tsx` (Gap 2)
- `frontend/src/features/jobs/pages/JobDetailPage.tsx` (Gap 5)
- New: `frontend/src/features/office/pages/PDFSettingsPage.tsx` (Gap 3)
- `frontend/src/api/orders.ts` (Gaps 2, 4)
- `frontend/src/api/jobs.ts` (Gap 5)
- `frontend/src/lib/types.ts` (all gaps)

---

## Implementation Notes (completed 2026-03-11)

### Gap 1: Category-Specific Supplier Preferences
- `job_preferences_service.py` updated: `learn_from_order()` now passes `category=category_name` instead of `None`
- `get_preferred_supplier_for_part()` checks category-specific match first, falls back to job-level
- `UnifiedOrderPage.tsx` shows category context in supplier suggestions
- **Fixed (2026-03-10):** `/suggestions` endpoint now returns grouped `{brands, colors, suppliers, parts}` format (was returning flat list)
- **Added (2026-03-10):** `supplierPrefs` derived from suggestions, displayed as emerald chips in Job Preferences strip
- **Added (2026-03-10):** `matchSupplierForPart()` matches part's category_name to supplier prefs—category-specific first, then highest-confidence fallback
- **Added (2026-03-10):** Each line item shows "→ SupplierName (for Category)" badge via Truck icon
- **Added (2026-03-10):** `suggested_supplier_id` sent in JPO submission payload from frontend
- **Added (2026-03-10):** Backend `create_jpo()` auto-populates `suggested_supplier_id` on each line using `get_preferred_supplier()` for lines where frontend didn't set one

### Gap 2: Supplier Portal Ongoing Notes
- New `POST /api/supplier-portal/view/pos/{po_id}/note` endpoint in `supplier_portal.py`
- Added `SupplierPortalNote` model in `orders.py` (message with 1-2000 char validation)
- Creates `po_conversations` entry with `entry_type='supplier_note'` and `follow_up_needed=1`
- `ConversationThread.tsx` styles supplier notes distinctly (orange, Building2 icon, "Supplier" label)
- `SupplierPortalPage.tsx` has note submission form in PortalPOCard (visible after acknowledgment)

### Gap 3: PDF Template System
- Migration `056_pdf_settings.sql` seeds 6 settings: accent_color, show_unit_prices, show_extended, footer_text, payment_terms, delivery_notes
- `pdf_service.py` fully refactored: reads settings via `_get_pdf_settings()`, dynamic columns via `_get_table_columns()`, accent color bar, conditional unit/extended columns, payment terms, footer text
- All 4 PDF generators updated (single PO, group, clipboard text variants)
- New endpoints: `GET/PUT /api/settings/pdf`, `POST /api/settings/company-logo` (logo upload with 5MB limit, image format validation)
- New `PDFSettingsPage.tsx` with logo upload/preview, accent color picker, column toggles, default text areas, save/reset
- Route at `/settings/pdf`, nav tab "PDF & Docs" in Settings

### Gap 4: Cross-Job Aggregate Summary
- New `get_order_summary()` in `orders_service.py` — SQL aggregation across jpo_line_items → jobs → parts → categories → suppliers
- New `GET /api/orders/office/order-summary` endpoint with `manage_orders` permission
- New `OrderSummaryCard.tsx` — expandable banner with stat pills (total parts, qty, jobs, suppliers) + detail table
- Wired into `ReviewAndSendPage.tsx` with TanStack Query + cache invalidation on PO generation

### Gap 5: Explicit Preferred Suppliers Per Job
- `job_preferences_service.py` — `set_explicit_suppliers()`, `get_explicit_suppliers()` (with deactivate-and-replace pattern)
- Uses `job_preferences` table with `preference_type='supplier'`, `auto_learned=0`, and `confidence_score` as priority (1.0=primary, 0.9=backup1, etc.)
- Endpoints: `PUT /api/jobs/{id}/preferred-suppliers`, `GET /api/jobs/{id}/preferred-suppliers`
- `PreferredSuppliersSection.tsx` component on `JobDetailPage.tsx` with supplier dropdown, move up/down reordering, save/cancel
- **Fixed (2026-03-10):** `auto_generate_pos()` now checks job's explicit preferred suppliers as fallback before `part_supplier_links`. Resolution order: suggested_supplier_id on line → explicit job preferred suppliers (primary first) → catalog-level preferred supplier → skip line
