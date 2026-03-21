# iOS Supplier System — Scores, Traceability, Contacts, AI

> **Status:** Prompts 17A-17H written, pending implementation
> **Prompt files:** `xcode-ai/fix-prompts/17A-*.md` through `17H-*.md`
> **Date planned:** 2026-03-19

## Overview

Comprehensive supplier management system for the WiredPart iOS app. Adds auto-calculated performance scores, part traceability, multi-contact People integration, and read-only AI assistance.

## Architecture

### Data Model Changes

**Migration 026 — Supplier Enhancements:**
- `account_number` TEXT column on `suppliers` table

**New Swift model:**
- `StockMovement` struct — maps all 20+ columns of the existing `stock_movements` table (migration 002)

**Existing tables used:**
- `suppliers` (migration 002) — has quality_score, on_time_rate, reliability_score columns
- `stock_movements` (migration 002) — part movement tracking
- `part_suppliers` (migration 002) — supplier-part links with pricing
- `brand_suppliers` (migration 002) — supplier-brand links
- `entity_contacts` (migration 014) — polymorphic contacts (entity_type='supplier')
- `purchase_orders` (migration 005) — PO history
- `receiving_sessions` (migration 010) — receiving completion dates

### Service Methods Added to PartsService

| Section | Method | Purpose |
|---------|--------|---------|
| 10. Traceability | `tracePartMovements(partId:)` | Full chronological journey of a part |
| 10. Traceability | `tracePartFromSupplier(partId:supplierId:)` | Filter trace to one supplier chain |
| 10. Traceability | `getPartCurrentLocations(partId:)` | Where stock is right now |
| 11. Scores | `calculateSupplierScores(supplierId:)` | Compute quality/on-time/reliability |
| 11. Scores | `updateSupplierScores(supplierId:)` | Persist scores to suppliers table |
| 11. Scores | `recalculateAllSupplierScores()` | Batch recalc for all suppliers |
| 12. Detail | `getSupplierBrands(supplierId:)` | Brands linked to supplier |
| 12. Detail | `getSupplierRecentPOs(supplierId:)` | Last 10 POs |
| 12. Detail | `getSupplierPartCount(supplierId:)` | Count of linked parts |
| 13. Contacts | `getSupplierContacts(supplierId:)` | Contacts via entity_contacts |
| 13. Contacts | `addSupplierContact(...)` | Quick-add with role |
| 13. Contacts | `removeSupplierContact(contactId:)` | Soft-delete contact link |
| 14. Costs | `getPartSupplierCosts(partId:)` | All supplier costs for a part |
| 15. AI | `buildSupplierAIContext()` | Text summary for AI queries |

### Performance Score Formulas

| Score | Formula | Weight |
|-------|---------|--------|
| Quality | `100 - (returns / total_received × 100)` | 40% of reliability |
| On-Time | `orders_on_time / total_orders × 100` | 60% of reliability |
| Reliability | `(on_time × 0.6) + (quality × 0.4)` | — |

- "On time" = `receiving_sessions.completed_at` within expected delivery days
- Expected delivery days: `CAST(delivery_days AS INTEGER)` with fallback to 14 days
- Scores = 0% with explanation when no data exists

### Part Traceability

Track individual parts from supplier → PO → shop → truck → job. Uses `stock_movements` table:

```
Supplier → Receipt → Warehouse → Transfer → Staging → Transfer → Truck → Consumption → Job
```

Each step is a `TraceStep` with: date, movement type, from/to location, qty, unit cost, performed by, reference number.

### Supplier Detail Sheet (8 sections)

1. **Overview** — account #, active status, delivery method/days
2. **Contact** — tappable phone (tel:), email (mailto:), website
3. **Sales Rep** — tappable phone/email
4. **Performance** — quality/on-time/reliability scores, order count, avg delivery days
5. **Contacts** — multi-contact from entity_contacts, add button, swipe-to-delete
6. **Brands Carried** — linked brands with part counts
7. **Parts** — count only (pricing is on Pricing page)
8. **Recent Orders** — last 10 POs with status badges
9. **Notes** — if present

### Supplier Form (15 editable fields)

Organized in 5 sections:
1. **Supplier Details** — name*, account #, active toggle
2. **Main Contact** — contact name, email, phone, address, website
3. **Sales Representative** — rep name, rep email, rep phone
4. **Delivery Info** — delivery method (picker with presets), delivery days
5. **Notes** — multiline text

### Sort Options (7)

Name A→Z, Name Z→A, Quality ↓, On-Time ↓, Reliability ↓, Most Parts, Recently Added

### AI Integration (Read-Only)

- Sparkles button in toolbar
- Lazy context loading (built on first panel open)
- Context invalidated after any CRUD operation
- System prompt emphasizes READ-ONLY — cannot modify suppliers
- Can answer: best supplier by score, supplier for brand X, compare quality, etc.

## Brand-Supplier Linking (Prompts 11A-11C, 15A-15C — ALL DONE)

**Service methods (11A):**
- `linkBrandToSupplier(brandId:supplierId:)` / `unlinkBrandToSupplier(brandId:supplierId:)` in PartsService
- Uses existing `brand_supplier_links` table

**Brand detail sheet (11B):**
- Shows linked suppliers list with name and contact
- Edit button opens supplier picker

**Brand-supplier picker (11C):**
- Checkbox picker for managing brand-supplier links
- Toggle on/off, shows current links, searchable

**Brands + Suppliers cleanup (15A-15C — DONE):**
- 15A: Removed raw SQL from both pages → PartsService methods, removed `import GRDB`
- 15B: Delete confirmations, save error feedback on both pages
- 15C: Fixed nested .sheet conflict in SupplierDetailSheet → onEdit closure pattern

## Bug Fixes Included

| Bug | Fix | Prompt |
|-----|-----|--------|
| `partCount: item.brandCount` wrong field | Correct field mapping + subquery | 17F |
| `supplierCount: 0` hardcoded | Query from brand_suppliers | 17G |
| BrandDetailSheet double `.sheet` | Single `.sheet(item:)` enum pattern | 17G |

## Key Design Decision

**No per-part pricing on supplier page.** Supplier-specific costs (`part_suppliers.supplier_cost_price`) display ONLY on:
- Pricing page (in the edit sheet, with all suppliers and their costs)
- Categories page (supplier cost summary when viewing parts)

The supplier detail page shows a parts COUNT and directs users to the Pricing page.

## Dependencies

- Requires 16A migration for pricing_tiers (if showing supplier costs on pricing page)
- Uses entity_contacts from migration 014
- Uses stock_movements from migration 002
- Integrates with PeopleService for contact management
