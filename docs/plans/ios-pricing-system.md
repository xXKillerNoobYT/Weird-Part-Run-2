# iOS Pricing System — FIFO/LIFO, Hierarchical Tiers, Stale Alerts

> **Status:** Prompts 16A-16I written, pending implementation
> **Prompt files:** `xcode-ai/fix-prompts/16A-*.md` through `16I-*.md`
> **Date planned:** 2026-03-19

## Overview

Complete pricing system for the WiredPart iOS app. Replaces the current flat cost×markup page with a full FIFO/LIFO inventory costing engine, hierarchical price inheritance, and stale price alerts.

## Architecture

### Data Model

**New tables (Migration 025):**

| Table | Purpose |
|-------|---------|
| `pricing_tiers` | Hierarchical price tiers (category/style/type/brand/part level) |
| `price_history` | Audit trail of all price changes |
| `cost_layer_consumptions` | FIFO/LIFO consumption tracking per batch |

**Existing tables used:**
- `cost_layers` (migration 014) — FIFO batches with unit cost
- `company_cost_settings` (migration 014) — default margin, cost method, auto-update
- `part_suppliers` (migration 002) — supplier-specific pricing per part

### FIFO/LIFO Engine (9 service methods)

| Method | Purpose |
|--------|---------|
| `addCostLayer` | Create a new FIFO batch when receiving inventory |
| `consumeInventoryFIFO` | Consume oldest batches first when parts go to jobs |
| `returnInventoryLIFO` | Restore most recently consumed batches for returns |
| `recalculateWeightedAvgCost` | `Σ(remaining_qty × unit_cost) / Σ(remaining_qty)` |
| `getCostLayers` | Get all batches for a part |
| `getConsumptionHistory` | Get consumption records for a batch |
| `resetToCurrentBuyPrice` | Reset avg cost to latest buy price |
| `logPriceChange` | Record price change in history |
| `getPriceHistory` | Get price change audit trail |

**Key rules:**
- Price precision: up to $0.00001 (5 decimal places)
- Partial deliveries: each arrival creates its own batch
- Weighted average recalculated after every add/consume/return
- Minimum margin = 0% (sell price can never go below cost)

### Hierarchical Pricing

**Inheritance chain:** Category → Style → Type → Brand → Part (most specific wins)

**`pricing_tiers` table design:**
- Polymorphic FK: exactly ONE of `category_id`, `style_id`, `type_id`, `brand_id`, `part_id` is set per row
- Fields: `markup_percent`, `margin_percent`, `sell_price_override`, `is_active`

**Override flow (strictly one-at-a-time):**
1. User sets a tier (e.g., markup at Category level)
2. System finds all parts that already have custom pricing at lower levels
3. User steps through each override point one at a time
4. For each: sees old vs new, picks "Replace" (removes custom tier) or "Keep" (preserves custom)
5. "Replace" = soft-delete the custom PricingTier record

**Preview (separate from Override):**
- Shows 15 random affected parts
- READ ONLY — no action buttons
- Locked for session duration

### Markup vs Margin

- Company-wide setting (company_cost_settings: `pricing_display_mode`)
- **Markup** (default): `(sell - cost) / cost × 100`
- **Margin**: `(sell - cost) / sell × 100`
- Both shown on screen, but only the primary mode is editable
- User can toggle in settings

### Stale Price Alerts

- Configurable threshold (default 90 days)
- Parts not price-updated within threshold flagged in catalog and during ordering
- Receiving verification: 3 options per line item — Matches, Different (enter new), Not Shown (skip)

### UI Components

| Prompt | Component |
|--------|-----------|
| 16D | PricingPage rebuild: PricingDisplayRow, tier badges, category filter, stale indicators |
| 16E | PricingTierSetSheet: 5-step wizard for setting hierarchical tiers with override flow |
| 16F | PricingBulkEditSheet + PricingSettingsSheet: bulk markup, mode toggle, stale threshold |
| 16G | Stale alerts + receiving verification |
| 16H | 3 view modes (List/Cards/Table) + catalog "Show Prices" toggle |
| 16I | AI panel for pricing page (can query costs, compare, suggest) |

## Supplier Pricing Display

Supplier-specific costs from `part_suppliers.supplier_cost_price` display on:
- **Pricing page** — supplier cost section in edit sheet (shows all suppliers for a part with their price)
- **Categories page** — supplier cost summary when viewing parts

**NOT on the supplier detail page** — that shows brands, contacts, scores, PO history.

## Dependencies

- Requires existing `cost_layers` and `company_cost_settings` tables (migration 014)
- Requires existing `part_suppliers` table (migration 002)
- Integrates with receiving flow (IOSReceiveShipmentPage)
- Integrates with catalog page (PartsCatalogPage)
