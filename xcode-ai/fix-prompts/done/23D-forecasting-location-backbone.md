# 23D — Forecasting: Per-Location Backbone (Migration + Service)

> **Chain position:** 23A → 23B → 23C → **23D** → 23E
> **Prerequisite:** 23C complete (stat card filters)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The forecasting system currently calculates global ADU and stock predictions for each part. But stock exists per-location (the `stock` table already has `location_type` + `location_id`). We need per-location forecast data and per-location MIN/TARGET/MAX overrides so the forecasting page can show "how is this part doing at the shop vs on Truck #3?"

The `parts` table already has `min_stock_level`, `max_stock_level`, `target_stock_level` — these become the **company-wide defaults**. The new `location_stock_targets` table holds per-location overrides.

**IMPORTANT — Truck HAUL concept:** Trucks have a distinction between "hauling" parts (in transit, doesn't count as truck inventory) and actual truck inventory. Parts being transferred TO a truck for delivery to a job site are HAUL — they're passing through. Only parts intentionally stocked on the truck for the truck's own use count as truck inventory. The `location_stock_targets` table only tracks actual truck inventory targets, not haul.

**Files to read first:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — see stock table (~line 424), parts table fields (~line 349)
- `core/Sources/WiredPartCore/Services/PartsService.swift` — see forecasting section (MARK: - 7. Forecasting)
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — Part struct

**Files to modify:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — add migration
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — add LocationStockTarget model
- `core/Sources/WiredPartCore/Services/PartsService.swift` — add per-location forecast methods
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` — add table to whitelist

## Task

### Step 1: Migration — location_stock_targets table

Add a new migration (use the next available number after the last migration in the file):

```swift
migrator.registerMigration("028_location_stock_targets") { db in
    try db.create(table: "location_stock_targets") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("part_id", .integer).notNull()
            .references("parts", onDelete: .cascade)
        t.column("location_type", .text).notNull()     // "warehouse", "truck", "trailer"
        t.column("location_id", .integer).notNull()
        t.column("min_stock", .integer).notNull().defaults(to: 0)
        t.column("target_stock", .integer).notNull().defaults(to: 0)
        t.column("max_stock", .integer).notNull().defaults(to: 0)
        t.column("forecast_adu_30", .double).defaults(to: 0)
        t.column("forecast_adu_90", .double).defaults(to: 0)
        t.column("forecast_days_until_low", .integer).defaults(to: 999)
        t.column("forecast_suggested_order", .integer).defaults(to: 0)
        t.column("forecast_last_run", .text)
        t.column("certainty_rating", .double).defaults(to: 0)
        t.column("deleted_at", .text)
        t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
    }
    try db.create(index: "idx_lst_part_location", on: "location_stock_targets",
                  columns: ["part_id", "location_type", "location_id"], unique: true)
    try db.create(index: "idx_lst_location", on: "location_stock_targets",
                  columns: ["location_type", "location_id"])
}
```

### Step 2: Model — LocationStockTarget

In `PartsModels.swift`, add:

```swift
// MARK: - LocationStockTarget

/// Per-location stock level targets and forecast data.
/// Overrides the part's global min/target/max for a specific location.
public struct LocationStockTarget: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "location_stock_targets"

    public var id: Int64?
    public var partId: Int64
    public var locationType: String       // "warehouse", "truck", "trailer"
    public var locationId: Int64
    public var minStock: Int
    public var targetStock: Int
    public var maxStock: Int
    public var forecastAdu30: Double?
    public var forecastAdu90: Double?
    public var forecastDaysUntilLow: Int?
    public var forecastSuggestedOrder: Int?
    public var forecastLastRun: String?
    public var certaintyRating: Double?
    public var deletedAt: String?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case locationType = "location_type"
        case locationId = "location_id"
        case minStock = "min_stock"
        case targetStock = "target_stock"
        case maxStock = "max_stock"
        case forecastAdu30 = "forecast_adu_30"
        case forecastAdu90 = "forecast_adu_90"
        case forecastDaysUntilLow = "forecast_days_until_low"
        case forecastSuggestedOrder = "forecast_suggested_order"
        case forecastLastRun = "forecast_last_run"
        case certaintyRating = "certainty_rating"
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### Step 3: Service — Per-location forecast methods

In `PartsService.swift`, add a new section after the existing forecasting section:

```swift
// MARK: - 7b. Per-Location Forecasting

/// Get or create a LocationStockTarget for a part at a specific location.
/// Falls back to the part's global min/target/max as initial values.
public func getLocationStockTarget(partId: Int64, locationType: String, locationId: Int64) throws -> LocationStockTarget {
    try db.writer.read { dbConn in
        if let existing = try LocationStockTarget.fetchOne(dbConn, sql: """
            SELECT * FROM location_stock_targets
            WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
            """, arguments: [partId, locationType, locationId]) {
            return existing
        }
        // Return a default based on part's global settings
        let part = try Part.fetchOne(dbConn, key: partId)
        return LocationStockTarget(
            id: nil,
            partId: partId,
            locationType: locationType,
            locationId: locationId,
            minStock: part?.minStockLevel ?? 0,
            targetStock: part?.targetStockLevel ?? 0,
            maxStock: part?.maxStockLevel ?? 0,
            forecastAdu30: nil, forecastAdu90: nil,
            forecastDaysUntilLow: nil, forecastSuggestedOrder: nil,
            forecastLastRun: nil, certaintyRating: nil,
            deletedAt: nil, updatedAt: nil
        )
    }
}

/// Update stock targets for a part at a specific location.
/// Creates the row if it doesn't exist (upsert).
public func setLocationStockTarget(partId: Int64, locationType: String, locationId: Int64,
                                    minStock: Int, targetStock: Int, maxStock: Int) throws {
    try db.writer.write { dbConn in
        let existing = try LocationStockTarget.fetchOne(dbConn, sql: """
            SELECT * FROM location_stock_targets
            WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
            """, arguments: [partId, locationType, locationId])

        if var target = existing {
            target.minStock = minStock
            target.targetStock = targetStock
            target.maxStock = maxStock
            target.updatedAt = ISO8601DateFormatter().string(from: Date())
            try target.update(dbConn)
        } else {
            var target = LocationStockTarget(
                id: nil, partId: partId,
                locationType: locationType, locationId: locationId,
                minStock: minStock, targetStock: targetStock, maxStock: maxStock,
                forecastAdu30: nil, forecastAdu90: nil,
                forecastDaysUntilLow: nil, forecastSuggestedOrder: nil,
                forecastLastRun: nil, certaintyRating: nil,
                deletedAt: nil, updatedAt: nil
            )
            try target.insert(dbConn)
        }
    }
}

/// List all location stock targets for a given part.
/// Returns one row per location where the part has stock or targets set.
public func listLocationStockTargets(partId: Int64) throws -> [LocationStockTargetWithStock] {
    try db.writer.read { dbConn in
        // Get all locations where this part has stock OR targets
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT
                COALESCE(lst.location_type, s.location_type) AS location_type,
                COALESCE(lst.location_id, s.location_id) AS location_id,
                COALESCE(lst.min_stock, p.min_stock_level, 0) AS min_stock,
                COALESCE(lst.target_stock, p.target_stock_level, 0) AS target_stock,
                COALESCE(lst.max_stock, p.max_stock_level, 0) AS max_stock,
                lst.forecast_adu_30,
                lst.forecast_days_until_low,
                lst.certainty_rating,
                COALESCE(SUM(s.qty), 0) AS current_stock,
                COALESCE(wl.name, v.name, tr.name, 'Unknown') AS location_name
            FROM (
                SELECT DISTINCT location_type, location_id FROM stock
                WHERE part_id = ? AND deleted_at IS NULL AND qty > 0
                UNION
                SELECT location_type, location_id FROM location_stock_targets
                WHERE part_id = ? AND deleted_at IS NULL
            ) AS locations
            LEFT JOIN stock s ON s.part_id = ? AND s.location_type = locations.location_type
                AND s.location_id = locations.location_id AND s.deleted_at IS NULL
            LEFT JOIN location_stock_targets lst ON lst.part_id = ?
                AND lst.location_type = locations.location_type
                AND lst.location_id = locations.location_id AND lst.deleted_at IS NULL
            LEFT JOIN parts p ON p.id = ?
            LEFT JOIN warehouse_locations wl ON locations.location_type = 'warehouse'
                AND wl.id = locations.location_id
            LEFT JOIN vehicles v ON locations.location_type = 'truck'
                AND v.id = locations.location_id
            LEFT JOIN trailers tr ON locations.location_type = 'trailer'
                AND tr.id = locations.location_id
            GROUP BY locations.location_type, locations.location_id
            ORDER BY locations.location_type ASC, location_name ASC
            """, arguments: [partId, partId, partId, partId, partId])

        return rows.map { row in
            LocationStockTargetWithStock(
                locationType: row["location_type"] ?? "warehouse",
                locationId: row["location_id"] ?? 1,
                locationName: row["location_name"] ?? "Unknown",
                minStock: row["min_stock"] ?? 0,
                targetStock: row["target_stock"] ?? 0,
                maxStock: row["max_stock"] ?? 0,
                currentStock: row["current_stock"] ?? 0,
                forecastAdu30: row["forecast_adu_30"],
                forecastDaysUntilLow: row["forecast_days_until_low"],
                certaintyRating: row["certainty_rating"]
            )
        }
    }
}

/// Per-location stock target with current stock included.
public struct LocationStockTargetWithStock: Sendable, Identifiable {
    public var id: String { "\(locationType)_\(locationId)" }
    public let locationType: String
    public let locationId: Int64
    public let locationName: String
    public let minStock: Int
    public let targetStock: Int
    public let maxStock: Int
    public let currentStock: Int
    public let forecastAdu30: Double?
    public let forecastDaysUntilLow: Int?
    public let certaintyRating: Double?

    /// Stock health: -1.0 (empty) to 0.0 (at target) to +1.0 (overstocked)
    public var healthScore: Double {
        guard targetStock > 0 else { return 0 }
        if currentStock <= minStock { return -1.0 }
        if currentStock < targetStock {
            return -Double(targetStock - currentStock) / Double(targetStock - minStock)
        }
        if currentStock > maxStock && maxStock > targetStock {
            return 1.0
        }
        if currentStock > targetStock && maxStock > targetStock {
            return Double(currentStock - targetStock) / Double(maxStock - targetStock)
        }
        return 0.0  // At target
    }
}

/// Recalculate forecasts per-location (in addition to the global recalculate).
/// For each part at each location, calculates ADU from stock_movements
/// that flow through that location.
public func recalculateForecastsPerLocation() throws {
    try db.writer.write { dbConn in
        // Get all active part-location combinations with movements
        let combinations = try Row.fetchAll(dbConn, sql: """
            SELECT DISTINCT part_id, to_location_type AS lt, to_location_id AS lid
            FROM stock_movements
            WHERE deleted_at IS NULL AND to_location_type IS NOT NULL
            UNION
            SELECT DISTINCT part_id, from_location_type AS lt, from_location_id AS lid
            FROM stock_movements
            WHERE deleted_at IS NULL AND from_location_type IS NOT NULL
            """)

        for combo in combinations {
            let partId: Int64 = combo["part_id"]
            let locType: String = combo["lt"] ?? "warehouse"
            let locId: Int64 = combo["lid"] ?? 1

            // ADU-30 for this location: outbound movements from this location
            let consumed30 = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                  AND movement_type IN ('consume', 'transfer')
                  AND created_at >= datetime('now', '-30 days')
                  AND deleted_at IS NULL
                """, arguments: [partId, locType, locId]) ?? 0
            let adu30 = Double(consumed30) / 30.0

            let consumed90 = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                  AND movement_type IN ('consume', 'transfer')
                  AND created_at >= datetime('now', '-90 days')
                  AND deleted_at IS NULL
                """, arguments: [partId, locType, locId]) ?? 0
            let adu90 = Double(consumed90) / 90.0

            // Movement count for certainty
            let movementCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM stock_movements
                WHERE part_id = ? AND (
                    (from_location_type = ? AND from_location_id = ?) OR
                    (to_location_type = ? AND to_location_id = ?)
                ) AND deleted_at IS NULL
                """, arguments: [partId, locType, locId, locType, locId]) ?? 0
            // Certainty: 0 moves = 0.0, 10 moves = 0.5, 50+ moves = 1.0
            let certainty = min(1.0, Double(movementCount) / 50.0)

            // Current stock at this location
            let currentStock = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(qty), 0) FROM stock
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [partId, locType, locId]) ?? 0

            // Get target (from location_stock_targets or part defaults)
            let minStock = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(
                    (SELECT min_stock FROM location_stock_targets
                     WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL),
                    (SELECT min_stock_level FROM parts WHERE id = ?),
                    0
                )
                """, arguments: [partId, locType, locId, partId]) ?? 0

            // Days until low
            let daysUntilLow: Int
            if adu30 > 0 {
                daysUntilLow = max(0, Int(Double(currentStock - minStock) / adu30))
            } else {
                daysUntilLow = 999
            }

            let targetStock = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(
                    (SELECT target_stock FROM location_stock_targets
                     WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL),
                    (SELECT target_stock_level FROM parts WHERE id = ?),
                    0
                )
                """, arguments: [partId, locType, locId, partId]) ?? 0
            let suggestedOrder = max(0, targetStock - currentStock)

            // Upsert location_stock_targets
            let existing = try Row.fetchOne(dbConn, sql: """
                SELECT id FROM location_stock_targets
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [partId, locType, locId])

            if let existingId: Int64 = existing?["id"] {
                try dbConn.execute(sql: """
                    UPDATE location_stock_targets SET
                        forecast_adu_30 = ?, forecast_adu_90 = ?,
                        forecast_days_until_low = ?, forecast_suggested_order = ?,
                        forecast_last_run = datetime('now'), certainty_rating = ?,
                        updated_at = datetime('now')
                    WHERE id = ?
                    """, arguments: [adu30, adu90, daysUntilLow, suggestedOrder, certainty, existingId])
            } else {
                try dbConn.execute(sql: """
                    INSERT INTO location_stock_targets
                        (part_id, location_type, location_id, min_stock, target_stock, max_stock,
                         forecast_adu_30, forecast_adu_90, forecast_days_until_low,
                         forecast_suggested_order, forecast_last_run, certainty_rating)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), ?)
                    """, arguments: [partId, locType, locId, minStock, targetStock, 0, adu30, adu90, daysUntilLow, suggestedOrder, certainty])
            }
        }
    }
}
```

### Step 4: Update recalculateForecasts to include per-location

In the existing `recalculateForecasts()` method, at the very end (after the for loop), add:

```swift
// After global forecast update, also update per-location data
try recalculateForecastsPerLocation()
```

This way a single "Recalculate" button press updates both global and per-location forecasts.

### Step 5: ConflictResolver whitelist

In `ConflictResolver.swift`, add `"location_stock_targets"` to the table name whitelist.

## Important Notes

- The `location_stock_targets` table uses a UNIQUE constraint on `(part_id, location_type, location_id)` — upsert logic handles this.
- `certainty_rating` is 0.0 to 1.0 based on movement count (50+ movements = 1.0 certainty). This is a simple heuristic; future refinement can factor in recency and consistency.
- The `healthScore` computed property on `LocationStockTargetWithStock` returns -1.0 (below min) to 0.0 (at target) to +1.0 (at/above max). This drives the health bar visualization in the UI (prompt 23E).
- Truck HAUL transfers (parts being delivered to a job, not stocked on the truck) should use a different movement_type or flag. This will be refined when we review the Warehouse/Movement pages. For now, the forecast calculation treats all movements equally per location.
- `recalculateForecastsPerLocation()` is called inside the existing `recalculateForecasts()`, so one button press does both.

## Success Criteria

- [ ] Migration creates `location_stock_targets` table with proper indexes
- [ ] `LocationStockTarget` model with correct CodingKeys
- [ ] `getLocationStockTarget()` returns existing or falls back to part defaults
- [ ] `setLocationStockTarget()` upserts min/target/max per location
- [ ] `listLocationStockTargets()` returns all locations for a part with current stock + health data
- [ ] `LocationStockTargetWithStock` has `healthScore` computed property
- [ ] `recalculateForecastsPerLocation()` calculates ADU + certainty per location
- [ ] Global `recalculateForecasts()` now also calls per-location recalc
- [ ] `location_stock_targets` added to ConflictResolver whitelist
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23D Results (YYYY-MM-DD)
- Migration 028: location_stock_targets table with UNIQUE(part_id, location_type, location_id)
- LocationStockTarget model + LocationStockTargetWithStock (with healthScore)
- 4 service methods: get, set, list, recalculatePerLocation
- Global recalculate now chains into per-location recalculate
- ConflictResolver: location_stock_targets added
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 23E.**
