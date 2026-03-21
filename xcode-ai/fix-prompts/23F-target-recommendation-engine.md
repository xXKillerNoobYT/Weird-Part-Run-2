# 23F — Target Recommendation Engine (Migration + Service)

> **Chain position:** 23A → … → 23E → **23F** → 23G
> **Prerequisite:** 23E complete (forecast_settings + location_free_space tables exist)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

**IMPORTANT:** Before implementing, first plan your approach by reading all files mentioned below. Understand the current state, then implement the fixes. When done, wait for the user to confirm before proceeding to the next prompt.

## Context

The system recommends changes to MIN, TARGET, and MAX stock levels per location. It generates max 1 recommendation per day, picks the most impactful candidate, and shows up to 14 days of recommendations. Once a recommendation is made for a part+location, that combination enters a 60-day cooldown. The system also recommends adding/removing parts from locations and category changes (Common↔Critical).

**Two calculation units:**
- **Shop (ADU):** Parts per day, averaged over `adu_lookback_days` (default 365)
- **Truck (APW):** Parts per X-week window (1-6 weeks, configurable per truck)

Multipliers are in the same unit as the calculation — shop multipliers = days, truck multipliers = weeks.

**Validation:** MIN < TARGET < MAX always. MIN cannot exceed current inventory. MAX cannot be below current inventory.

**Files to read first:**
- `docs/plans/inventory-intelligence-system.md` — full spec for recommendations (Part C2) and lifecycle rules
- `core/Sources/WiredPartCore/Services/PartsService.swift` — existing forecast methods
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift` — ForecastSettings model

**Files to modify:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`
- `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift`
- `core/Sources/WiredPartCore/Services/PartsService.swift`
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`

## Task

### Step 1: Migration — target_recommendations table

```swift
migrator.registerMigration("030_target_recommendations") { db in
    try db.create(table: "target_recommendations") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("part_id", .integer).notNull().references("parts", onDelete: .cascade)
        t.column("location_type", .text).notNull()
        t.column("location_id", .integer).notNull()
        t.column("recommendation_type", .text).notNull().defaults(to: "adjust")
            // 'adjust' = change MIN/TARGET/MAX
            // 'add' = add part to this location
            // 'remove' = remove part from this location
            // 'category_change' = switch Common↔Critical
        t.column("current_min", .integer)
        t.column("current_target", .integer)
        t.column("current_max", .integer)
        t.column("recommended_min", .integer)
        t.column("recommended_target", .integer)
        t.column("recommended_max", .integer)
        t.column("current_category", .text)          // for category_change type
        t.column("recommended_category", .text)      // for category_change type
        t.column("usage_value", .double).notNull()    // ADU or APW depending on location
        t.column("usage_unit", .text).notNull()       // 'daily' or 'weekly'
        t.column("data_days", .integer).notNull()     // how many days of data used
        t.column("impact_score", .double).notNull()   // for ranking — higher = more impactful
        t.column("reason", .text)                     // human-readable explanation
        t.column("status", .text).defaults(to: "pending")  // pending/approved/dismissed/expired
        t.column("approved_by", .integer).references("users")
        t.column("approved_at", .text)
        t.column("dismissed_by", .integer).references("users")
        t.column("dismissed_reason", .text)           // REQUIRED when dismissing
        t.column("cooldown_until", .text)             // created_at + 60 days
        t.column("created_at", .text).defaults(sql: "(datetime('now'))")
        t.column("deleted_at", .text)
    }
    try db.create(index: "idx_tr_part_loc", on: "target_recommendations",
                  columns: ["part_id", "location_type", "location_id"])
    try db.create(index: "idx_tr_status", on: "target_recommendations", columns: ["status"])
}
```

### Step 2: Model

In `PartsModels.swift`, add:

```swift
// MARK: - TargetRecommendation

/// A system-generated recommendation to change stock levels at a location.
public struct TargetRecommendation: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Identifiable {
    public static let databaseTableName = "target_recommendations"

    public var id: Int64?
    public var partId: Int64
    public var locationType: String
    public var locationId: Int64
    public var recommendationType: String   // adjust, add, remove, category_change
    public var currentMin: Int?
    public var currentTarget: Int?
    public var currentMax: Int?
    public var recommendedMin: Int?
    public var recommendedTarget: Int?
    public var recommendedMax: Int?
    public var currentCategory: String?
    public var recommendedCategory: String?
    public var usageValue: Double
    public var usageUnit: String
    public var dataDays: Int
    public var impactScore: Double
    public var reason: String?
    public var status: String
    public var approvedBy: Int64?
    public var approvedAt: String?
    public var dismissedBy: Int64?
    public var dismissedReason: String?
    public var cooldownUntil: String?
    public var createdAt: String?
    public var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case partId = "part_id"
        case locationType = "location_type"
        case locationId = "location_id"
        case recommendationType = "recommendation_type"
        case currentMin = "current_min"
        case currentTarget = "current_target"
        case currentMax = "current_max"
        case recommendedMin = "recommended_min"
        case recommendedTarget = "recommended_target"
        case recommendedMax = "recommended_max"
        case currentCategory = "current_category"
        case recommendedCategory = "recommended_category"
        case usageValue = "usage_value"
        case usageUnit = "usage_unit"
        case dataDays = "data_days"
        case impactScore = "impact_score"
        case reason, status
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
        case dismissedBy = "dismissed_by"
        case dismissedReason = "dismissed_reason"
        case cooldownUntil = "cooldown_until"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### Step 3: Service — Recommendation engine

In `PartsService.swift`, add:

```swift
// MARK: - 7d. Target Recommendations

/// Generate the daily recommendation. Call from background task.
/// Picks the single most impactful candidate and creates a recommendation.
/// Max 1 per day. Respects 60-day cooldown per part+location.
public func generateDailyRecommendation() throws {
    try db.writer.write { dbConn in
        // Check if we already generated one today
        let todayCount = try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM target_recommendations
            WHERE DATE(created_at) = DATE('now') AND deleted_at IS NULL
            """) ?? 0
        guard todayCount == 0 else { return }

        // Get all location-type settings
        let allSettings = try ForecastSettings.fetchAll(dbConn, sql: """
            SELECT * FROM forecast_settings ORDER BY location_id ASC
            """)

        var bestCandidate: (partId: Int64, locType: String, locId: Int64,
                            currentMin: Int, currentTarget: Int, currentMax: Int,
                            recMin: Int, recTarget: Int, recMax: Int,
                            usage: Double, unit: String, dataDays: Int,
                            impact: Double, reason: String, type: String,
                            curCategory: String?, recCategory: String?)?

        // Scan all active part+location combinations
        let combinations = try Row.fetchAll(dbConn, sql: """
            SELECT DISTINCT
                lst.part_id, lst.location_type, lst.location_id,
                lst.min_stock, lst.target_stock, lst.max_stock,
                lst.part_category, lst.forecast_adu_30,
                COALESCE(SUM(s.qty), 0) AS current_stock
            FROM location_stock_targets lst
            LEFT JOIN stock s ON s.part_id = lst.part_id
                AND s.location_type = lst.location_type
                AND s.location_id = lst.location_id
                AND s.deleted_at IS NULL
            WHERE lst.deleted_at IS NULL AND lst.do_not_restock = 0
            GROUP BY lst.part_id, lst.location_type, lst.location_id
            """)

        for combo in combinations {
            let partId: Int64 = combo["part_id"]
            let locType: String = combo["location_type"] ?? "warehouse"
            let locId: Int64 = combo["location_id"] ?? 1
            let curMin: Int = combo["min_stock"] ?? 0
            let curTarget: Int = combo["target_stock"] ?? 0
            let curMax: Int = combo["max_stock"] ?? 0
            let category: String = combo["part_category"] ?? "common"
            let currentStock: Int = combo["current_stock"] ?? 0

            // Check cooldown — skip if recommended in last 60 days
            let inCooldown = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM target_recommendations
                WHERE part_id = ? AND location_type = ? AND location_id = ?
                  AND cooldown_until > datetime('now') AND deleted_at IS NULL
                """, arguments: [partId, locType, locId]) ?? 0
            guard inCooldown == 0 else { continue }

            // Get settings for this location (specific override or type default)
            let settings = allSettings.first(where: {
                $0.locationType == locType && $0.locationId == locId
            }) ?? allSettings.first(where: {
                $0.locationType == locType && $0.locationId == nil
            })
            guard let s = settings else { continue }

            // Check minimum data requirement
            let firstMovement = try String.fetchOne(dbConn, sql: """
                SELECT MIN(created_at) FROM stock_movements
                WHERE part_id = ? AND deleted_at IS NULL
                  AND (from_location_type = ? AND from_location_id = ?
                    OR to_location_type = ? AND to_location_id = ?)
                """, arguments: [partId, locType, locId, locType, locId])
            guard let firstDate = firstMovement else { continue }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            guard let first = formatter.date(from: firstDate) else { continue }
            let daysSinceFirst = Int(Date().timeIntervalSince(first) / 86400)
            guard daysSinceFirst >= s.minDataDays else { continue }

            // Calculate usage based on unit
            let usage: Double
            let unit: String
            if s.usageUnit == "weekly" {
                // APW: parts per X-week window
                let windowDays = s.windowWeeks * 7
                let consumed = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                    WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                      AND movement_type IN ('consume', 'transfer')
                      AND created_at >= datetime('now', '-\(windowDays) days')
                      AND deleted_at IS NULL
                    """, arguments: [partId, locType, locId]) ?? 0
                usage = Double(consumed) // total in window, not per-day
                unit = "weekly"
            } else {
                // ADU: parts per day over lookback period
                let consumed = try Int.fetchOne(dbConn, sql: """
                    SELECT COALESCE(SUM(ABS(qty)), 0) FROM stock_movements
                    WHERE part_id = ? AND from_location_type = ? AND from_location_id = ?
                      AND movement_type IN ('consume', 'transfer')
                      AND created_at >= datetime('now', '-\(s.aduLookbackDays) days')
                      AND deleted_at IS NULL
                    """, arguments: [partId, locType, locId]) ?? 0
                usage = Double(consumed) / Double(s.aduLookbackDays)
                unit = "daily"
            }

            // Calculate recommended values using multipliers
            let multipliers = category == "critical"
                ? (s.criticalMinMultiplier, s.criticalTargetMultiplier, s.criticalMaxMultiplier)
                : (s.commonMinMultiplier, s.commonTargetMultiplier, s.commonMaxMultiplier)

            var recMin = Int(usage * multipliers.0)
            var recTarget = Int(usage * multipliers.1)
            var recMax = Int(usage * multipliers.2)

            // Enforce validation: MIN < TARGET < MAX
            if recMin >= recTarget { recTarget = recMin + 1 }
            if recTarget >= recMax { recMax = recTarget + 1 }

            // MIN cannot exceed current inventory, MAX cannot be below current inventory
            if recMin > currentStock { recMin = currentStock }
            if recMax < currentStock { recMax = currentStock }
            // Re-validate after clamping
            if recMin >= recTarget { recTarget = recMin + 1 }
            if recTarget >= recMax { recMax = recTarget + 1 }

            // Calculate impact score (bigger gap = more impactful)
            let minDiff = abs(recMin - curMin)
            let targetDiff = abs(recTarget - curTarget)
            let maxDiff = abs(recMax - curMax)
            let impact = Double(minDiff + targetDiff * 2 + maxDiff) // weight target changes more

            // Skip if change is trivial
            guard impact > 2 else { continue }

            // Check if this is the best candidate so far
            if bestCandidate == nil || impact > (bestCandidate?.impact ?? 0) {
                var reason = ""
                if recTarget > curTarget {
                    reason = "Usage (\(String(format: "%.1f", usage))/\(unit == "daily" ? "day" : "window")) suggests higher stock levels."
                } else {
                    reason = "Usage (\(String(format: "%.1f", usage))/\(unit == "daily" ? "day" : "window")) suggests lower stock levels."
                }
                bestCandidate = (partId, locType, locId,
                                 curMin, curTarget, curMax,
                                 recMin, recTarget, recMax,
                                 usage, unit, daysSinceFirst,
                                 impact, reason, "adjust",
                                 nil, nil)
            }
        }

        // Also check for category change candidates
        // Common → Critical: unused 6 months at a location
        let staleCommon = try Row.fetchAll(dbConn, sql: """
            SELECT lst.part_id, lst.location_type, lst.location_id
            FROM location_stock_targets lst
            WHERE lst.part_category = 'common' AND lst.deleted_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements sm
                WHERE sm.part_id = lst.part_id
                  AND (sm.from_location_type = lst.location_type AND sm.from_location_id = lst.location_id
                    OR sm.to_location_type = lst.location_type AND sm.to_location_id = lst.location_id)
                  AND sm.created_at >= datetime('now', '-180 days')
                  AND sm.deleted_at IS NULL
              )
              AND NOT EXISTS (
                SELECT 1 FROM target_recommendations tr
                WHERE tr.part_id = lst.part_id AND tr.location_type = lst.location_type
                  AND tr.location_id = lst.location_id
                  AND tr.cooldown_until > datetime('now') AND tr.deleted_at IS NULL
              )
            LIMIT 5
            """)

        for row in staleCommon {
            let partId: Int64 = row["part_id"]
            let locType: String = row["location_type"] ?? "warehouse"
            let locId: Int64 = row["location_id"] ?? 1
            let impact = 5.0 // moderate impact
            if bestCandidate == nil || impact > (bestCandidate?.impact ?? 0) {
                bestCandidate = (partId, locType, locId, 0, 0, 0, 0, 0, 0,
                                 0, "daily", 180, impact,
                                 "No usage in 6 months. Consider marking as Critical or removing.",
                                 "category_change", "common", "critical")
            }
        }

        // Critical → Common: used consistently 4 of last 6 months
        let activeCritical = try Row.fetchAll(dbConn, sql: """
            SELECT lst.part_id, lst.location_type, lst.location_id,
                   COUNT(DISTINCT strftime('%Y-%m', sm.created_at)) AS active_months
            FROM location_stock_targets lst
            JOIN stock_movements sm ON sm.part_id = lst.part_id
                AND (sm.from_location_type = lst.location_type AND sm.from_location_id = lst.location_id
                  OR sm.to_location_type = lst.location_type AND sm.to_location_id = lst.location_id)
                AND sm.created_at >= datetime('now', '-180 days')
                AND sm.deleted_at IS NULL
            WHERE lst.part_category = 'critical' AND lst.deleted_at IS NULL
              AND NOT EXISTS (
                SELECT 1 FROM target_recommendations tr
                WHERE tr.part_id = lst.part_id AND tr.location_type = lst.location_type
                  AND tr.location_id = lst.location_id
                  AND tr.cooldown_until > datetime('now') AND tr.deleted_at IS NULL
              )
            GROUP BY lst.part_id, lst.location_type, lst.location_id
            HAVING active_months >= 4
            LIMIT 5
            """)

        for row in activeCritical {
            let partId: Int64 = row["part_id"]
            let locType: String = row["location_type"] ?? "warehouse"
            let locId: Int64 = row["location_id"] ?? 1
            let impact = 5.0
            if bestCandidate == nil || impact > (bestCandidate?.impact ?? 0) {
                bestCandidate = (partId, locType, locId, 0, 0, 0, 0, 0, 0,
                                 0, "daily", 180, impact,
                                 "Used consistently (4+ of last 6 months). Consider switching to Common for better restocking.",
                                 "category_change", "critical", "common")
            }
        }

        // Create the recommendation if we found a candidate
        guard let best = bestCandidate else { return }

        try dbConn.execute(sql: """
            INSERT INTO target_recommendations
                (part_id, location_type, location_id, recommendation_type,
                 current_min, current_target, current_max,
                 recommended_min, recommended_target, recommended_max,
                 current_category, recommended_category,
                 usage_value, usage_unit, data_days, impact_score, reason,
                 cooldown_until, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                    datetime('now', '+60 days'), 'pending')
            """, arguments: [
                best.partId, best.locType, best.locId, best.type,
                best.currentMin, best.currentTarget, best.currentMax,
                best.recMin, best.recTarget, best.recMax,
                best.curCategory, best.recCategory,
                best.usage, best.unit, best.dataDays, best.impact, best.reason
            ])
    }
}

/// List pending recommendations (up to 14 days).
public func listPendingRecommendations(limit: Int = 14) throws -> [TargetRecommendation] {
    try db.writer.read { dbConn in
        try TargetRecommendation.fetchAll(dbConn, sql: """
            SELECT * FROM target_recommendations
            WHERE status = 'pending' AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT ?
            """, arguments: [limit])
    }
}

/// Approve a recommendation — applies the new values to location_stock_targets.
public func approveRecommendation(id: Int64, userId: Int64) throws {
    try db.writer.write { dbConn in
        guard let rec = try TargetRecommendation.fetchOne(dbConn, key: id),
              rec.status == "pending" else { return }

        if rec.recommendationType == "adjust" {
            // Update location_stock_targets with new values
            try dbConn.execute(sql: """
                UPDATE location_stock_targets SET
                    min_stock = COALESCE(?, min_stock),
                    target_stock = COALESCE(?, target_stock),
                    max_stock = COALESCE(?, max_stock),
                    updated_at = datetime('now')
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [rec.recommendedMin, rec.recommendedTarget, rec.recommendedMax,
                                 rec.partId, rec.locationType, rec.locationId])
        } else if rec.recommendationType == "category_change" {
            try dbConn.execute(sql: """
                UPDATE location_stock_targets SET
                    part_category = ?,
                    updated_at = datetime('now')
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [rec.recommendedCategory, rec.partId, rec.locationType, rec.locationId])
        } else if rec.recommendationType == "remove" {
            try dbConn.execute(sql: """
                UPDATE location_stock_targets SET
                    do_not_restock = 1,
                    updated_at = datetime('now')
                WHERE part_id = ? AND location_type = ? AND location_id = ? AND deleted_at IS NULL
                """, arguments: [rec.partId, rec.locationType, rec.locationId])
        }

        // Mark recommendation as approved
        try dbConn.execute(sql: """
            UPDATE target_recommendations SET
                status = 'approved', approved_by = ?, approved_at = datetime('now')
            WHERE id = ?
            """, arguments: [userId, id])
    }
}

/// Dismiss a recommendation with required reason.
public func dismissRecommendation(id: Int64, userId: Int64, reason: String) throws {
    guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw PartsServiceError.invalidInput("Dismiss reason is required")
    }
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE target_recommendations SET
                status = 'dismissed', dismissed_by = ?, dismissed_reason = ?,
                dismissed_reason = ?
            WHERE id = ? AND status = 'pending'
            """, arguments: [userId, reason, reason, id])
    }
}

/// Count pending recommendations (for badge display).
public func pendingRecommendationCount() throws -> Int {
    try db.writer.read { dbConn in
        try Int.fetchOne(dbConn, sql: """
            SELECT COUNT(*) FROM target_recommendations
            WHERE status = 'pending' AND deleted_at IS NULL
            """) ?? 0
    }
}
```

### Step 4: ConflictResolver whitelist

Add `"target_recommendations"` to the table name whitelist.

## Important Notes

- `generateDailyRecommendation()` is designed to be called by the background task system. For now, it can also be triggered manually.
- The engine checks category changes (Common↔Critical) as candidates alongside stock level adjustments — the single most impactful candidate wins the daily slot.
- Impact score weights TARGET changes at 2× since TARGET is the most important value.
- The `dismissed_reason` field is REQUIRED — the service method validates this. UI must enforce a non-empty text field.
- Cooldown is set to 60 days from creation, regardless of whether the recommendation was approved, dismissed, or expired.
- The `invalidInput` error case may need to be added to PartsServiceError if it doesn't exist.

## Success Criteria

- [ ] Migration creates `target_recommendations` table with indexes
- [ ] `TargetRecommendation` model with correct CodingKeys
- [ ] `generateDailyRecommendation()` creates max 1 per day, respects cooldown, validates MIN<TARGET<MAX
- [ ] Engine handles both ADU (shop/daily) and APW (truck/weekly) calculations
- [ ] Category change candidates (Common↔Critical) included in daily pick
- [ ] `approveRecommendation()` applies values to `location_stock_targets`
- [ ] `dismissRecommendation()` requires non-empty reason
- [ ] `listPendingRecommendations()` returns up to 14 days
- [ ] `pendingRecommendationCount()` for badge display
- [ ] Table added to ConflictResolver whitelist
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 23F Results (YYYY-MM-DD)
- Migration 030: target_recommendations table
- TargetRecommendation model
- 5 service methods: generate daily, list pending, approve, dismiss, count
- Engine handles ADU (shop) + APW (truck), category changes, validation constraints
- Build: [PASS/FAIL]
```

**Wait for user confirmation before proceeding to prompt 23G.**
