# 23E — Forecast Settings + Free Space Migrations

> **Chain position:** 23A → 23B → 23C → 23D → **23E** → 23F
> **Prerequisite:** 23D complete (location_stock_targets table exists)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The forecasting system needs per-location-type settings (shop vs truck use completely different calculation units) and per-individual-location overrides (each truck can have its own settings). The shop calculates ADU (parts per day) over a 365-day lookback. Trucks calculate APW (parts per X-week window, configurable 1-6 weeks per truck).

We also need a free space rating per location (1-10 scale, updated monthly by notification) that constrains inventory recommendations — don't suggest adding parts to a location that's nearly full.

**Files to read first:**
- `docs/plans/inventory-intelligence-system.md` — full design spec, search for "forecast_settings" and "location_free_space"
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — find the last migration number
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` — table whitelist

**Files to modify:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift`
- `core/Sources/WiredPartCore/Services/PartsService.swift`
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`

## Task

### Step 1: Migration — forecast_settings table

Add migration (use next number after 028):

```swift
migrator.registerMigration("029_forecast_settings") { db in
    // Per location-type defaults + per individual location overrides
    // Row with location_id=NULL is the default for that location_type
    // Row with location_id set overrides for that specific truck/warehouse/trailer
    try db.create(table: "forecast_settings") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("location_type", .text).notNull()        // 'warehouse', 'truck', 'trailer'
        t.column("location_id", .integer)                   // NULL = default, set = specific location
        t.column("usage_unit", .text).notNull().defaults(to: "daily")  // 'daily' (shop) or 'weekly' (truck)
        t.column("adu_lookback_days", .integer).defaults(to: 365)      // shop: days of history for ADU
        t.column("window_weeks", .integer).defaults(to: 3)             // truck: 1-6 week averaging window
        t.column("min_data_days", .integer).defaults(to: 90)           // min days before recommendations
        t.column("common_min_multiplier", .double).defaults(to: 3.5)
        t.column("common_target_multiplier", .double).defaults(to: 14.0)
        t.column("common_max_multiplier", .double).defaults(to: 21.0)
        t.column("critical_min_multiplier", .double).defaults(to: 7.0)
        t.column("critical_target_multiplier", .double).defaults(to: 14.0)
        t.column("critical_max_multiplier", .double).defaults(to: 30.0)
        t.column("free_space_suppress_threshold", .integer).defaults(to: 3)
        t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
    }
    try db.create(index: "idx_fs_location", on: "forecast_settings",
                  columns: ["location_type", "location_id"], unique: true)

    // Seed default settings for each location type
    // Shop: ADU (parts/day), 365-day lookback
    try db.execute(sql: """
        INSERT INTO forecast_settings (location_type, usage_unit, adu_lookback_days, min_data_days,
            common_min_multiplier, common_target_multiplier, common_max_multiplier,
            critical_min_multiplier, critical_target_multiplier, critical_max_multiplier)
        VALUES ('warehouse', 'daily', 365, 90, 3.5, 14.0, 21.0, 7.0, 21.0, 30.0)
        """)

    // Truck: APW (parts/X-weeks), 3-week window default
    try db.execute(sql: """
        INSERT INTO forecast_settings (location_type, usage_unit, window_weeks, min_data_days,
            common_min_multiplier, common_target_multiplier, common_max_multiplier,
            critical_min_multiplier, critical_target_multiplier, critical_max_multiplier)
        VALUES ('truck', 'weekly', 3, 60, 1.0, 2.0, 3.0, 7.0, 14.0, 21.0)
        """)

    // Trailer: same as truck defaults
    try db.execute(sql: """
        INSERT INTO forecast_settings (location_type, usage_unit, window_weeks, min_data_days,
            common_min_multiplier, common_target_multiplier, common_max_multiplier,
            critical_min_multiplier, critical_target_multiplier, critical_max_multiplier)
        VALUES ('trailer', 'weekly', 3, 60, 1.0, 2.0, 3.0, 7.0, 14.0, 21.0)
        """)

    // Free space ratings per location (1-10 scale, monthly notification to update)
    try db.create(table: "location_free_space") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("location_type", .text).notNull()
        t.column("location_id", .integer).notNull()
        t.column("free_space_rating", .integer).notNull().defaults(to: 5) // 1=full, 10=lots of room
        t.column("updated_by", .integer).references("users")
        t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
    }
    try db.create(index: "idx_lfs_location", on: "location_free_space",
                  columns: ["location_type", "location_id"], unique: true)

    // Add do_not_restock and part_category to location_stock_targets if not already present
    // (23D may have created the table without these)
    try? db.alter(table: "location_stock_targets") { t in
        t.add(column: "part_category", .text).defaults(to: "common")
        t.add(column: "do_not_restock", .integer).defaults(to: 0)
    }
}
```

### Step 2: Models

In `PartsModels.swift`, add:

```swift
// MARK: - ForecastSettings

/// Per-location-type (or per-individual-location) forecast calculation settings.
/// Shop uses ADU (parts/day). Trucks use APW (parts/X-weeks).
public struct ForecastSettings: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "forecast_settings"

    public var id: Int64?
    public var locationType: String
    public var locationId: Int64?       // nil = default for type, set = specific location
    public var usageUnit: String        // "daily" or "weekly"
    public var aduLookbackDays: Int
    public var windowWeeks: Int
    public var minDataDays: Int
    public var commonMinMultiplier: Double
    public var commonTargetMultiplier: Double
    public var commonMaxMultiplier: Double
    public var criticalMinMultiplier: Double
    public var criticalTargetMultiplier: Double
    public var criticalMaxMultiplier: Double
    public var freeSpaceSuppressThreshold: Int
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case locationType = "location_type"
        case locationId = "location_id"
        case usageUnit = "usage_unit"
        case aduLookbackDays = "adu_lookback_days"
        case windowWeeks = "window_weeks"
        case minDataDays = "min_data_days"
        case commonMinMultiplier = "common_min_multiplier"
        case commonTargetMultiplier = "common_target_multiplier"
        case commonMaxMultiplier = "common_max_multiplier"
        case criticalMinMultiplier = "critical_min_multiplier"
        case criticalTargetMultiplier = "critical_target_multiplier"
        case criticalMaxMultiplier = "critical_max_multiplier"
        case freeSpaceSuppressThreshold = "free_space_suppress_threshold"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - LocationFreeSpace

/// Physical free space rating for a location (1=nearly full, 10=lots of room).
/// Updated monthly by notification prompt.
public struct LocationFreeSpace: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "location_free_space"

    public var id: Int64?
    public var locationType: String
    public var locationId: Int64
    public var freeSpaceRating: Int      // 1-10
    public var updatedBy: Int64?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case locationType = "location_type"
        case locationId = "location_id"
        case freeSpaceRating = "free_space_rating"
        case updatedBy = "updated_by"
        case updatedAt = "updated_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### Step 3: Service methods

In `PartsService.swift`, add a new section:

```swift
// MARK: - 7c. Forecast Settings

/// Get forecast settings for a specific location.
/// Returns location-specific override if exists, otherwise falls back to location-type default.
public func getForecastSettings(locationType: String, locationId: Int64? = nil) throws -> ForecastSettings? {
    try db.writer.read { dbConn in
        // Try specific location first
        if let locId = locationId {
            if let specific = try ForecastSettings.fetchOne(dbConn, sql: """
                SELECT * FROM forecast_settings
                WHERE location_type = ? AND location_id = ?
                """, arguments: [locationType, locId]) {
                return specific
            }
        }
        // Fall back to location-type default
        return try ForecastSettings.fetchOne(dbConn, sql: """
            SELECT * FROM forecast_settings
            WHERE location_type = ? AND location_id IS NULL
            """, arguments: [locationType])
    }
}

/// Save or update forecast settings.
/// If locationId is nil, updates the default for that location type.
/// If locationId is set, creates/updates override for that specific location.
public func saveForecastSettings(_ settings: ForecastSettings) throws {
    try db.writer.write { dbConn in
        var s = settings
        s.updatedAt = ISO8601DateFormatter().string(from: Date())
        if s.id != nil {
            try s.update(dbConn)
        } else {
            try s.insert(dbConn)
        }
    }
}

/// Get free space rating for a location. Returns 5 (middle) if not set.
public func getFreeSpaceRating(locationType: String, locationId: Int64) throws -> Int {
    try db.writer.read { dbConn in
        try Int.fetchOne(dbConn, sql: """
            SELECT free_space_rating FROM location_free_space
            WHERE location_type = ? AND location_id = ?
            """, arguments: [locationType, locationId]) ?? 5
    }
}

/// Update free space rating for a location (1-10 scale).
public func setFreeSpaceRating(locationType: String, locationId: Int64, rating: Int, userId: Int64) throws {
    let clamped = max(1, min(10, rating))
    try db.writer.write { dbConn in
        let existing = try LocationFreeSpace.fetchOne(dbConn, sql: """
            SELECT * FROM location_free_space
            WHERE location_type = ? AND location_id = ?
            """, arguments: [locationType, locationId])
        if var fs = existing {
            fs.freeSpaceRating = clamped
            fs.updatedBy = userId
            fs.updatedAt = ISO8601DateFormatter().string(from: Date())
            try fs.update(dbConn)
        } else {
            var fs = LocationFreeSpace(
                id: nil, locationType: locationType, locationId: locationId,
                freeSpaceRating: clamped, updatedBy: userId, updatedAt: nil
            )
            try fs.insert(dbConn)
        }
    }
}

/// List all forecast settings (defaults + overrides) for the settings UI.
public func listAllForecastSettings() throws -> [ForecastSettings] {
    try db.writer.read { dbConn in
        try ForecastSettings.fetchAll(dbConn, sql: """
            SELECT * FROM forecast_settings ORDER BY location_type ASC, location_id ASC
            """)
    }
}
```

### Step 4: ConflictResolver whitelist

Add `"forecast_settings"` and `"location_free_space"` to the table name whitelist.

## Success Criteria

- [ ] Migration creates `forecast_settings` with 3 seeded defaults (warehouse, truck, trailer)
- [ ] Migration creates `location_free_space` table
- [ ] Migration adds `part_category` and `do_not_restock` columns to `location_stock_targets`
- [ ] `ForecastSettings` model with correct CodingKeys
- [ ] `LocationFreeSpace` model with correct CodingKeys
- [ ] `getForecastSettings()` returns specific override or falls back to type default
- [ ] `saveForecastSettings()` creates or updates
- [ ] `getFreeSpaceRating()` / `setFreeSpaceRating()` with 1-10 clamping
- [ ] Both tables added to ConflictResolver whitelist
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23E Results (YYYY-MM-DD)
- Migration 029: forecast_settings (3 seeded defaults), location_free_space, alter location_stock_targets
- ForecastSettings + LocationFreeSpace models
- 5 service methods: get/save settings, get/set free space, list all
- ConflictResolver: 2 tables added
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 23F.**
