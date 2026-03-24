# 16C — Hierarchical Pricing Service Layer

> **Chain position:** 16A → 16B → **16C** → 16D (UI rebuild) → 16E–16I
> **Prerequisite:** 16A + 16B complete (pricing_tiers table + FIFO engine)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

WiredPart uses hierarchical pricing: markup/margin can be set at Category, Style, Type, Brand, or individual Part level. Prices cascade DOWN — a Category-level markup applies to all parts under it unless overridden at a lower level. The most specific tier wins.

**Hierarchy:** Category → Style → Type → Brand → Part

**Override rules:**
- Setting a price at a higher level auto-applies to everything below with NO existing override
- Existing lower-level overrides are NOT replaced automatically
- To push a higher-level price through overrides, the user must confirm each override point one at a time, seeing old vs new values
- Margins lock at 0 minimum — sell price can never go below cost

**Company-wide setting:** `pricing_mode` in `company_cost_settings` — either `"markup"` or `"margin"`. This controls which value is the PRIMARY input; the other is calculated and displayed. Default is `"markup"`.

**Key files:**
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add methods after the FIFO methods from 16B
- `core/Sources/WiredPartCore/Models/Costs/CostsModels.swift` — PricingTier model

## Task

Add these methods to `PartsService.swift` in a new section after the FIFO methods:

```swift
// =========================================================================
// MARK: - 5b. Hierarchical Pricing
// =========================================================================
```

### Method 1: Get the effective pricing for a part (resolve hierarchy)

```swift
/// Resolved pricing info for a part — includes the effective markup/margin,
/// where it was set (tier level), and whether it's inherited or direct.
public struct ResolvedPricing: Sendable {
    public let partId: Int64
    public let weightedAvgCost: Double
    public let effectiveMarkup: Double       // the markup % that applies
    public let effectiveMargin: Double       // calculated margin %
    public let sellPrice: Double             // calculated sell price
    public let tierLevel: String             // "Part", "Brand", "Type", "Style", "Category", "Default"
    public let tierId: Int64?               // the pricing_tier.id that set this, nil for default
    public let isInherited: Bool            // true if price comes from a parent level
    public let isDirectOverride: Bool       // true if this part has its own tier
}

/// Resolve the effective pricing for a part by walking UP the hierarchy.
/// Checks: Part → Brand → Type → Style → Category → Company Default
public func resolvePartPricing(partId: Int64) throws -> ResolvedPricing {
    try db.writer.read { dbConn in
        // Get part details
        guard let part = try Part.fetchOne(dbConn, key: partId) else {
            throw PartsError.partNotFound(partId)
        }

        let weightedAvg: Double = part.weightedAvgCost ?? 0
        let pricingMode = try getCompanySetting(dbConn: dbConn, key: "pricing_mode") ?? "markup"
        let defaultMarkup = Double(try getCompanySetting(dbConn: dbConn, key: "default_markup_percent") ?? "50") ?? 50

        // Check each level from most specific to least
        // 1. Part-level tier
        if let tier = try PricingTier.fetchOne(dbConn, sql: """
            SELECT * FROM pricing_tiers WHERE part_id = ? AND deleted_at IS NULL
            """, arguments: [partId]) {
            let (markup, margin, sell) = calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
            return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Part", tierId: tier.id, isInherited: false, isDirectOverride: true)
        }

        // 2. Brand-level tier (if part has a brand)
        if let brandId = part.brandId {
            if let tier = try PricingTier.fetchOne(dbConn, sql: """
                SELECT * FROM pricing_tiers WHERE brand_id = ? AND deleted_at IS NULL
                """, arguments: [brandId]) {
                let (markup, margin, sell) = calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Brand", tierId: tier.id, isInherited: true, isDirectOverride: false)
            }
        }

        // 3. Type-level tier
        if let typeId = part.typeId {
            if let tier = try PricingTier.fetchOne(dbConn, sql: """
                SELECT * FROM pricing_tiers WHERE type_id = ? AND deleted_at IS NULL
                """, arguments: [typeId]) {
                let (markup, margin, sell) = calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Type", tierId: tier.id, isInherited: true, isDirectOverride: false)
            }
        }

        // 4. Style-level tier
        if let styleId = part.styleId {
            if let tier = try PricingTier.fetchOne(dbConn, sql: """
                SELECT * FROM pricing_tiers WHERE style_id = ? AND deleted_at IS NULL
                """, arguments: [styleId]) {
                let (markup, margin, sell) = calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
                return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Style", tierId: tier.id, isInherited: true, isDirectOverride: false)
            }
        }

        // 5. Category-level tier
        if let tier = try PricingTier.fetchOne(dbConn, sql: """
            SELECT * FROM pricing_tiers WHERE category_id = ? AND deleted_at IS NULL
            """, arguments: [part.categoryId]) {
            let (markup, margin, sell) = calculatePricing(tier: tier, cost: weightedAvg, mode: pricingMode, defaultMarkup: defaultMarkup)
            return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: markup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Category", tierId: tier.id, isInherited: true, isDirectOverride: false)
        }

        // 6. Company default
        let sell = weightedAvg * (1 + defaultMarkup / 100)
        let margin = sell > 0 ? ((sell - weightedAvg) / sell) * 100 : 0
        return ResolvedPricing(partId: partId, weightedAvgCost: weightedAvg, effectiveMarkup: defaultMarkup, effectiveMargin: margin, sellPrice: sell, tierLevel: "Default", tierId: nil, isInherited: true, isDirectOverride: false)
    }
}

/// Calculate markup, margin, and sell price from a tier.
/// Enforces minimum 0% margin — sell price never goes below cost.
private func calculatePricing(
    tier: PricingTier,
    cost: Double,
    mode: String,
    defaultMarkup: Double
) -> (markup: Double, margin: Double, sellPrice: Double) {
    if let fixedPrice = tier.fixedSellPrice, fixedPrice > 0 {
        let safeSell = max(fixedPrice, cost) // never below cost
        let markup = cost > 0 ? ((safeSell - cost) / cost) * 100 : 0
        let margin = safeSell > 0 ? ((safeSell - cost) / safeSell) * 100 : 0
        return (markup, max(margin, 0), safeSell)
    }

    let markup: Double
    if mode == "margin", let marginPct = tier.marginPercent {
        // Convert margin to markup: markup = margin / (1 - margin/100)
        let clampedMargin = max(marginPct, 0)
        markup = clampedMargin < 100 ? (clampedMargin / (100 - clampedMargin)) * 100 : defaultMarkup
    } else {
        markup = max(tier.markupPercent ?? defaultMarkup, 0)
    }

    let sellPrice = cost * (1 + markup / 100)
    let margin = sellPrice > 0 ? ((sellPrice - cost) / sellPrice) * 100 : 0
    return (markup, max(margin, 0), sellPrice)
}
```

### Method 2: Set a pricing tier at any level

```swift
/// Set or update a pricing tier at a specific hierarchy level.
/// Only ONE of the id parameters should be non-nil.
@discardableResult
public func setPricingTier(
    categoryId: Int64? = nil,
    styleId: Int64? = nil,
    typeId: Int64? = nil,
    brandId: Int64? = nil,
    partId: Int64? = nil,
    markupPercent: Double? = nil,
    marginPercent: Double? = nil,
    fixedSellPrice: Double? = nil,
    setBy: Int64? = nil,
    notes: String? = nil
) throws -> PricingTier {
    try db.writer.write { dbConn in
        // Find existing tier at this level
        var conditions: [String] = []
        var args: [any DatabaseValueConvertible] = []

        if let id = categoryId { conditions.append("category_id = ?"); args.append(id) }
        else { conditions.append("category_id IS NULL") }

        if let id = styleId { conditions.append("style_id = ?"); args.append(id) }
        else { conditions.append("style_id IS NULL") }

        if let id = typeId { conditions.append("type_id = ?"); args.append(id) }
        else { conditions.append("type_id IS NULL") }

        if let id = brandId { conditions.append("brand_id = ?"); args.append(id) }
        else { conditions.append("brand_id IS NULL") }

        if let id = partId { conditions.append("part_id = ?"); args.append(id) }
        else { conditions.append("part_id IS NULL") }

        let whereClause = conditions.joined(separator: " AND ")

        // Soft-delete existing tier at this level
        try dbConn.execute(
            sql: "UPDATE pricing_tiers SET deleted_at = datetime('now') WHERE \(whereClause) AND deleted_at IS NULL",
            arguments: StatementArguments(args)
        )

        // Insert new tier
        var tier = PricingTier(
            categoryId: categoryId,
            styleId: styleId,
            typeId: typeId,
            brandId: brandId,
            partId: partId,
            markupPercent: markupPercent,
            marginPercent: marginPercent,
            fixedSellPrice: fixedSellPrice,
            setBy: setBy,
            notes: notes
        )
        try tier.insert(dbConn)
        return tier
    }
}

/// Remove a pricing tier (soft delete). Parts under this level revert to parent pricing.
public func removePricingTier(tierId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(
            sql: "UPDATE pricing_tiers SET deleted_at = datetime('now') WHERE id = ?",
            arguments: [tierId]
        )
    }
}
```

### Method 3: Find override points that would be affected by a tier change

```swift
/// When setting a price at a higher level, find all lower-level overrides
/// that would conflict. Returns the override tiers with their current pricing
/// so the user can confirm each one.
public struct OverrideConflict: Sendable {
    public let tier: PricingTier
    public let currentSellPrice: Double
    public let newSellPrice: Double       // what the price would be under the new tier
    public let difference: Double          // newSellPrice - currentSellPrice
    public let affectedPartCount: Int      // how many parts this override covers
}

public func findOverrideConflicts(
    categoryId: Int64? = nil,
    styleId: Int64? = nil,
    typeId: Int64? = nil,
    brandId: Int64? = nil,
    newMarkupPercent: Double? = nil,
    newMarginPercent: Double? = nil,
    newFixedPrice: Double? = nil
) throws -> [OverrideConflict] {
    try db.writer.read { dbConn in
        let pricingMode = try getCompanySetting(dbConn: dbConn, key: "pricing_mode") ?? "markup"
        let defaultMarkup = Double(try getCompanySetting(dbConn: dbConn, key: "default_markup_percent") ?? "50") ?? 50

        // Build a temporary tier for calculation
        let proposedTier = PricingTier(
            markupPercent: newMarkupPercent,
            marginPercent: newMarginPercent,
            fixedSellPrice: newFixedPrice
        )

        var conflicts: [OverrideConflict] = []

        // Find all active tiers that are MORE specific than the proposed level
        var sql = "SELECT * FROM pricing_tiers WHERE deleted_at IS NULL AND ("
        var conditions: [String] = []

        if categoryId != nil {
            // Category-level change: find style, type, brand, part overrides in this category
            conditions.append("style_id IN (SELECT id FROM part_styles WHERE category_id = ?)")
            conditions.append("type_id IN (SELECT id FROM part_types WHERE style_id IN (SELECT id FROM part_styles WHERE category_id = ?))")
            conditions.append("brand_id IS NOT NULL")
            conditions.append("part_id IN (SELECT id FROM parts WHERE category_id = ?)")
        } else if styleId != nil {
            conditions.append("type_id IN (SELECT id FROM part_types WHERE style_id = ?)")
            conditions.append("brand_id IS NOT NULL")
            conditions.append("part_id IN (SELECT id FROM parts WHERE style_id = ?)")
        } else if typeId != nil {
            conditions.append("brand_id IS NOT NULL")
            conditions.append("part_id IN (SELECT id FROM parts WHERE type_id = ?)")
        } else if brandId != nil {
            conditions.append("part_id IN (SELECT id FROM parts WHERE brand_id = ?)")
        }

        guard !conditions.isEmpty else { return [] }

        sql += conditions.joined(separator: " OR ") + ")"

        let tiers = try PricingTier.fetchAll(dbConn, sql: sql, arguments: StatementArguments(
            conditions.map { _ -> any DatabaseValueConvertible in
                categoryId ?? styleId ?? typeId ?? brandId ?? Int64(0)
            }
        ))

        for tier in tiers {
            // Get a representative cost for this tier's parts
            let costRow = try Row.fetchOne(dbConn, sql: """
                SELECT AVG(weighted_avg_cost) AS avg_cost, COUNT(*) AS cnt FROM parts
                WHERE deleted_at IS NULL AND (
                    (? IS NOT NULL AND category_id = ?) OR
                    (? IS NOT NULL AND style_id = ?) OR
                    (? IS NOT NULL AND type_id = ?) OR
                    (? IS NOT NULL AND brand_id = ?) OR
                    (? IS NOT NULL AND id = ?)
                )
                """, arguments: [
                    tier.categoryId, tier.categoryId,
                    tier.styleId, tier.styleId,
                    tier.typeId, tier.typeId,
                    tier.brandId, tier.brandId,
                    tier.partId, tier.partId
                ])

            let avgCost: Double = costRow?["avg_cost"] ?? 0
            let count: Int = costRow?["cnt"] ?? 0

            let (_, _, currentSell) = calculatePricing(tier: tier, cost: avgCost, mode: pricingMode, defaultMarkup: defaultMarkup)
            let (_, _, newSell) = calculatePricing(tier: proposedTier, cost: avgCost, mode: pricingMode, defaultMarkup: defaultMarkup)

            conflicts.append(OverrideConflict(
                tier: tier,
                currentSellPrice: currentSell,
                newSellPrice: newSell,
                difference: newSell - currentSell,
                affectedPartCount: count
            ))
        }

        return conflicts
    }
}
```

### Method 4: Get preview parts for pricing changes

```swift
/// Get up to 15 random in-stock parts that would be affected by a pricing change.
/// These parts are "locked in" for the preview — the caller should hold this array
/// for the duration of the review session.
public struct PricingPreviewPart: Sendable {
    public let partId: Int64
    public let partName: String
    public let currentSellPrice: Double
    public let newSellPrice: Double
    public let currentMarkup: Double
    public let newMarkup: Double
    public let weightedAvgCost: Double
    public let difference: Double
}

public func getPreviewParts(
    categoryId: Int64? = nil,
    styleId: Int64? = nil,
    typeId: Int64? = nil,
    brandId: Int64? = nil,
    newMarkupPercent: Double? = nil,
    newMarginPercent: Double? = nil,
    newFixedPrice: Double? = nil,
    limit: Int = 15
) throws -> [PricingPreviewPart] {
    try db.writer.read { dbConn in
        let pricingMode = try getCompanySetting(dbConn: dbConn, key: "pricing_mode") ?? "markup"
        let defaultMarkup = Double(try getCompanySetting(dbConn: dbConn, key: "default_markup_percent") ?? "50") ?? 50

        // Find parts in the target scope that have stock
        var conditions: [String] = ["p.deleted_at IS NULL"]
        var args: [any DatabaseValueConvertible] = []

        if let id = categoryId { conditions.append("p.category_id = ?"); args.append(id) }
        if let id = styleId { conditions.append("p.style_id = ?"); args.append(id) }
        if let id = typeId { conditions.append("p.type_id = ?"); args.append(id) }
        if let id = brandId { conditions.append("p.brand_id = ?"); args.append(id) }

        let whereClause = conditions.joined(separator: " AND ")

        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT p.id, p.name, p.weighted_avg_cost, p.company_markup_percent
            FROM parts p
            WHERE \(whereClause)
            ORDER BY RANDOM()
            LIMIT ?
            """, arguments: StatementArguments(args + [limit]))

        let proposedTier = PricingTier(
            markupPercent: newMarkupPercent,
            marginPercent: newMarginPercent,
            fixedSellPrice: newFixedPrice
        )

        return rows.map { row in
            let partId: Int64 = row["id"]
            let name: String = row["name"]
            let cost: Double = row["weighted_avg_cost"] ?? 0
            let currentMarkup: Double = row["company_markup_percent"] ?? defaultMarkup

            let currentSell = cost * (1 + currentMarkup / 100)
            let (newMarkup, _, newSell) = calculatePricing(tier: proposedTier, cost: cost, mode: pricingMode, defaultMarkup: defaultMarkup)

            return PricingPreviewPart(
                partId: partId,
                partName: name,
                currentSellPrice: currentSell,
                newSellPrice: newSell,
                currentMarkup: currentMarkup,
                newMarkup: newMarkup,
                weightedAvgCost: cost,
                difference: newSell - currentSell
            )
        }
    }
}
```

### Method 5: Get/set company settings helper

```swift
/// Read a company cost setting value.
public func getCompanyCostSetting(key: String) throws -> String? {
    try db.writer.read { dbConn in
        try getCompanySetting(dbConn: dbConn, key: key)
    }
}

/// Internal helper for reading settings within an existing connection.
private func getCompanySetting(dbConn: Database, key: String) throws -> String? {
    let row = try Row.fetchOne(dbConn, sql: """
        SELECT setting_value FROM company_cost_settings WHERE setting_key = ?
        """, arguments: [key])
    return row?["setting_value"] as? String
}

/// Update a company cost setting.
public func updateCompanyCostSetting(key: String, value: String, updatedBy: Int64? = nil) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            INSERT INTO company_cost_settings (setting_key, setting_value, updated_by, updated_at)
            VALUES (?, ?, ?, datetime('now'))
            ON CONFLICT(setting_key) DO UPDATE SET
                setting_value = excluded.setting_value,
                updated_by = excluded.updated_by,
                updated_at = datetime('now')
            """, arguments: [key, value, updatedBy])
    }
}

/// Get all pricing tiers at a specific level.
public func getPricingTiers(
    categoryId: Int64? = nil,
    styleId: Int64? = nil,
    typeId: Int64? = nil,
    brandId: Int64? = nil
) throws -> [PricingTier] {
    try db.writer.read { dbConn in
        var conditions: [String] = ["deleted_at IS NULL"]
        var args: [any DatabaseValueConvertible] = []

        if let id = categoryId { conditions.append("category_id = ?"); args.append(id) }
        if let id = styleId { conditions.append("style_id = ?"); args.append(id) }
        if let id = typeId { conditions.append("type_id = ?"); args.append(id) }
        if let id = brandId { conditions.append("brand_id = ?"); args.append(id) }

        let whereClause = conditions.joined(separator: " AND ")
        return try PricingTier.fetchAll(dbConn, sql: """
            SELECT * FROM pricing_tiers WHERE \(whereClause)
            ORDER BY created_at DESC
            """, arguments: StatementArguments(args))
    }
}
```

## Important Notes

- `calculatePricing` is a private helper — it must be accessible from both `resolvePartPricing` and `findOverrideConflicts` / `getPreviewParts`.
- The `getCompanySetting(dbConn:key:)` private helper takes an existing database connection so it can be called inside `read` blocks without nesting.
- All `PricingTier` queries filter `deleted_at IS NULL`.
- The `findOverrideConflicts` method has complex SQL — test carefully. If the SQL argument binding is tricky, simplify by splitting into multiple queries.

## Success Criteria

- [ ] `resolvePartPricing` walks hierarchy: Part → Brand → Type → Style → Category → Default
- [ ] `setPricingTier` creates/replaces tiers with soft-delete of old ones
- [ ] `findOverrideConflicts` returns lower-level overrides with price comparisons
- [ ] `getPreviewParts` returns up to 15 random affected parts locked for review
- [ ] `calculatePricing` enforces 0% minimum margin (sell ≥ cost)
- [ ] Company settings read/write works for pricing_mode, default_markup_percent
- [ ] Margin ↔ Markup conversion is correct
- [ ] Project builds with no errors

## Log Entry

Append to `xcode-ai/prompt-results-log.md`:
```
## Prompt 16C Results (YYYY-MM-DD)
- Methods: resolvePartPricing, setPricingTier, removePricingTier, findOverrideConflicts, getPreviewParts, getCompanyCostSetting, updateCompanyCostSetting, getPricingTiers
- Structs: ResolvedPricing, OverrideConflict, PricingPreviewPart
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 16D.**
