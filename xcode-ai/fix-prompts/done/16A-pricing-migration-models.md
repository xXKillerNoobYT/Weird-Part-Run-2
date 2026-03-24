# 16A — Pricing System: Migration + Models

> **Chain position:** 16A → 16B (FIFO engine) → 16C (hierarchical pricing) → 16D–16I
> **Prerequisite:** Prompts 01–15C complete
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

WiredPart needs a full FIFO/LIFO inventory costing system with hierarchical pricing. The `cost_layers` table already exists (migration 014) with `part_id`, `purchase_date`, `po_line_id`, `original_qty`, `remaining_qty`, `unit_cost`. The `company_cost_settings` table also exists with seeds for `default_margin_percent`, `cost_method`, `auto_update_pricing`.

What's MISSING: hierarchical price tiers, price history tracking, sale consumption records (which FIFO batches were used), markup/margin company-wide toggle, and stale price alert threshold.

## Task

### Step 1: Add migration 025 in `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`

Add a new migration registration call in the `registerAllMigrations` method:

```swift
registerMigration025PricingSystem(&migrator)
```

Then add the migration function:

```swift
// MARK: - 025: Pricing System

extension AppDatabase {
    private static func registerMigration025PricingSystem(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("025_pricing_system") { db in
            // Hierarchical price tiers — set price/markup at any hierarchy level
            // Prices cascade: category → style → type → brand → part (most specific wins)
            try db.create(table: "pricing_tiers") { t in
                t.autoIncrementedPrimaryKey("id")
                // Exactly ONE of these should be set to define the tier level
                t.column("category_id", .integer).references("part_categories")
                t.column("style_id", .integer).references("part_styles")
                t.column("type_id", .integer).references("part_types")
                t.column("brand_id", .integer).references("brands")
                t.column("part_id", .integer).references("parts")
                // The actual pricing values
                t.column("markup_percent", .double)        // e.g. 50.0 = 50% markup
                t.column("margin_percent", .double)         // alternative: margin mode
                t.column("fixed_sell_price", .double)       // optional: override with fixed price
                t.column("set_by", .integer).references("users")
                t.column("notes", .text)
                t.column("deleted_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("updated_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            // Ensure only one active tier per hierarchy point
            try db.create(index: "idx_pricing_tiers_category", on: "pricing_tiers", columns: ["category_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_style", on: "pricing_tiers", columns: ["style_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_type", on: "pricing_tiers", columns: ["type_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_brand", on: "pricing_tiers", columns: ["brand_id"], condition: Column("deleted_at") == nil)
            try db.create(index: "idx_pricing_tiers_part", on: "pricing_tiers", columns: ["part_id"], condition: Column("deleted_at") == nil)

            // Price change history — every time a price/markup changes, log it
            try db.create(table: "price_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("part_id", .integer).references("parts")
                t.column("pricing_tier_id", .integer).references("pricing_tiers")
                t.column("change_type", .text).notNull()     // "cost_update", "markup_change", "margin_change", "tier_set", "tier_removed", "reset"
                t.column("old_value", .double)
                t.column("new_value", .double)
                t.column("old_sell_price", .double)
                t.column("new_sell_price", .double)
                t.column("source", .text)                     // "manual", "receiving", "po_update", "bulk_edit", "tier_cascade"
                t.column("source_id", .integer)               // PO id, receiving session id, etc.
                t.column("changed_by", .integer).references("users")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_price_history_part", on: "price_history", columns: ["part_id", "created_at"])

            // Sale consumption records — track which FIFO batches were used for each sale
            // This enables LIFO returns: restore the most recently consumed batch
            try db.create(table: "cost_layer_consumptions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("cost_layer_id", .integer).notNull().references("cost_layers")
                t.column("part_id", .integer).notNull().references("parts")
                t.column("job_id", .integer).references("jobs")
                t.column("qty_consumed", .integer).notNull()
                t.column("unit_cost_at_sale", .double).notNull()  // locked cost from the batch
                t.column("sell_price_charged", .double)           // what the customer was charged
                t.column("supplier_id", .integer).references("suppliers") // which supplier this batch came from
                t.column("is_returned", .integer).notNull().defaults(to: 0) // 1 if this consumption was reversed by a return
                t.column("returned_at", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_consumptions_part_job", on: "cost_layer_consumptions", columns: ["part_id", "job_id"])
            try db.create(index: "idx_consumptions_layer", on: "cost_layer_consumptions", columns: ["cost_layer_id"])

            // Add new company cost settings
            try db.execute(sql: """
                INSERT OR IGNORE INTO company_cost_settings (setting_key, setting_value)
                VALUES
                    ('pricing_mode', 'markup'),
                    ('stale_price_threshold_days', '90'),
                    ('default_markup_percent', '50')
                """)
        }
    }
}
```

### Step 2: Add models in `core/Sources/WiredPartCore/Models/Costs/CostsModels.swift`

Append these structs after the existing `CostLayer` struct:

```swift
// MARK: - PricingTier

public struct PricingTier: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "pricing_tiers"
    public var id: Int64?
    public var categoryId: Int64?
    public var styleId: Int64?
    public var typeId: Int64?
    public var brandId: Int64?
    public var partId: Int64?
    public var markupPercent: Double?
    public var marginPercent: Double?
    public var fixedSellPrice: Double?
    public var setBy: Int64?
    public var notes: String?
    public var deletedAt: String?
    public var createdAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case categoryId = "category_id"
        case styleId = "style_id"
        case typeId = "type_id"
        case brandId = "brand_id"
        case partId = "part_id"
        case markupPercent = "markup_percent"
        case marginPercent = "margin_percent"
        case fixedSellPrice = "fixed_sell_price"
        case setBy = "set_by"
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Human-readable tier level name
    public var tierLevel: String {
        if partId != nil { return "Part" }
        if brandId != nil { return "Brand" }
        if typeId != nil { return "Type" }
        if styleId != nil { return "Style" }
        if categoryId != nil { return "Category" }
        return "Unknown"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - PriceHistory

public struct PriceHistory: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "price_history"
    public var id: Int64?
    public var partId: Int64?
    public var pricingTierId: Int64?
    public var changeType: String
    public var oldValue: Double?
    public var newValue: Double?
    public var oldSellPrice: Double?
    public var newSellPrice: Double?
    public var source: String?
    public var sourceId: Int64?
    public var changedBy: Int64?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case pricingTierId = "pricing_tier_id"
        case changeType = "change_type"
        case oldValue = "old_value"
        case newValue = "new_value"
        case oldSellPrice = "old_sell_price"
        case newSellPrice = "new_sell_price"
        case source, sourceId = "source_id"
        case changedBy = "changed_by"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CostLayerConsumption

public struct CostLayerConsumption: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "cost_layer_consumptions"
    public var id: Int64?
    public var costLayerId: Int64
    public var partId: Int64
    public var jobId: Int64?
    public var qtyConsumed: Int
    public var unitCostAtSale: Double
    public var sellPriceCharged: Double?
    public var supplierId: Int64?
    public var isReturned: Int
    public var returnedAt: String?
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case costLayerId = "cost_layer_id"
        case partId = "part_id"
        case jobId = "job_id"
        case qtyConsumed = "qty_consumed"
        case unitCostAtSale = "unit_cost_at_sale"
        case sellPriceCharged = "sell_price_charged"
        case supplierId = "supplier_id"
        case isReturned = "is_returned"
        case returnedAt = "returned_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### Step 3: Register migration 025 in the `registerAllMigrations` method

Find the last `registerMigration0XX` call in the `registerAllMigrations` method and add `registerMigration025PricingSystem(&migrator)` after it.

### Step 4: Add "pricing_tiers", "price_history", "cost_layer_consumptions" to the table whitelist

In `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`, find the `allowedTables` set and add:
```
"pricing_tiers", "price_history", "cost_layer_consumptions",
```

## Success Criteria

- [ ] Migration 025 creates 3 new tables: `pricing_tiers`, `price_history`, `cost_layer_consumptions`
- [ ] 3 new model structs added to CostsModels.swift with correct CodingKeys
- [ ] `PricingTier` has a computed `tierLevel` property
- [ ] New settings seeded: `pricing_mode`, `stale_price_threshold_days`, `default_markup_percent`
- [ ] Tables added to ConflictResolver whitelist
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16A Results (YYYY-MM-DD)
- Tables created: pricing_tiers, price_history, cost_layer_consumptions
- Models added: PricingTier, PriceHistory, CostLayerConsumption
- Settings seeded: pricing_mode=markup, stale_price_threshold_days=90, default_markup_percent=50
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16B.**
