# 19J — Auto-Discovery Engine: Background Scan + Drill-Down

## Context
You are working on a SwiftUI iOS app. The auto-discovery engine scans `job_parts` data to find category pairs commonly used together, then cascades down through styles → types → brands when upper levels are accepted.

**Available PartsService methods (from 19B/19C):**
- `calculateCoOccurrencePoints(windowMonths:)` — scans job_parts, writes to co_occurrence_pairs
- `getQualifiedPairs(minPoints:, minConfidence:, minJobs:, level:)` — pairs meeting thresholds
- `createWeeklyPoll()` — picks highest pair, creates poll + notifications
- `closeExpiredPolls()` — auto-closes past-due polls
- `purgeExpiredRules()` — hard-deletes expired cascaded rules

**Key tables:**
- `co_occurrence_pairs` — category_a/b_id, style_a/b_id, type_a/b_id, brand_a/b_id, points, match_level, rejection_count, is_blocked, tied_cooldown_until
- `companion_polls` — co_occurrence_id, match_level, status, result
- `companion_auto_discovery_log` — analysis_date, match_level, data_window_months, pairs_analyzed, new_pairs_found

**Analysis window:** 3 months minimum to start, scans up to 48 months of history.

**Thresholds:** 50 POs OR 3 months data, 15+ co-occurrences, 15% confidence, 100 points minimum.

## Task

### 1. Add style-level co-occurrence calculation

In `PartsService.swift`, add a method that drills down from accepted category pairs to style-level analysis:

```swift
/// After a category-level poll is accepted, calculate style-level co-occurrence
/// for the styles within those accepted categories.
/// This is the hierarchical cascade: Category → Style → Type → Brand.
public func calculateStyleCoOccurrence(
    categoryAId: Int64,
    categoryBId: Int64,
    windowMonths: Int = 48
) throws {
    try db.writer.write { dbConn in
        let windowMonthsClamped = max(3, min(windowMonths, 48))
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -windowMonthsClamped, to: Date())!
        let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

        // Get job_parts grouped by job, filtered to parts in these two categories
        // Group by style_id within each category
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT jp.job_id, p.category_id, p.style_id, SUM(jp.qty_consumed) AS total_qty
            FROM job_parts jp
            JOIN parts p ON p.id = jp.part_id
            WHERE jp.deleted_at IS NULL AND p.deleted_at IS NULL
              AND p.category_id IN (?, ?)
              AND p.style_id IS NOT NULL
              AND jp.consumed_at >= ?
            GROUP BY jp.job_id, p.category_id, p.style_id
            """, arguments: [categoryAId, categoryBId, cutoff])

        // Group by job: { jobId: [(categoryId, styleId, qty)] }
        var jobStyles: [Int64: [(catId: Int64, styleId: Int64, qty: Int)]] = [:]
        for row in rows {
            let jobId: Int64 = row["job_id"]
            jobStyles[jobId, default: []].append((
                catId: row["category_id"],
                styleId: row["style_id"],
                qty: row["total_qty"]
            ))
        }

        // Calculate points for each style pair (one from each category)
        var pairPoints: [String: (styleA: Int64, catA: Int64, styleB: Int64, catB: Int64, points: Int, jobCount: Int)] = [:]
        for (_, styles) in jobStyles {
            let fromA = styles.filter { $0.catId == categoryAId }
            let fromB = styles.filter { $0.catId == categoryBId }
            for a in fromA {
                for b in fromB {
                    let (sA, sB) = a.styleId < b.styleId ? (a.styleId, b.styleId) : (b.styleId, a.styleId)
                    let key = "\(sA)-\(sB)"
                    var existing = pairPoints[key] ?? (styleA: sA, catA: categoryAId, styleB: sB, catB: categoryBId, points: 0, jobCount: 0)
                    existing.points += min(a.qty, b.qty)
                    existing.jobCount += 1
                    pairPoints[key] = existing
                }
            }
        }

        // Upsert into co_occurrence_pairs at style level
        for (_, pair) in pairPoints {
            let existing = try Row.fetchOne(dbConn, sql: """
                SELECT id FROM co_occurrence_pairs
                WHERE category_a_id = ? AND category_b_id = ?
                  AND style_a_id = ? AND style_b_id = ? AND match_level = 'style'
                """, arguments: [pair.catA, pair.catB, pair.styleA, pair.styleB])

            if let existing = existing {
                let existingId: Int64 = existing["id"]
                try dbConn.execute(sql: """
                    UPDATE co_occurrence_pairs
                    SET points = ?, co_occurrence_count = ?, last_computed = datetime('now')
                    WHERE id = ?
                    """, arguments: [pair.points, pair.jobCount, existingId])
            } else {
                try dbConn.execute(sql: """
                    INSERT INTO co_occurrence_pairs
                    (category_a_id, category_b_id, style_a_id, style_b_id,
                     co_occurrence_count, points, match_level, confidence, last_computed)
                    VALUES (?, ?, ?, ?, ?, ?, 'style', ?, datetime('now'))
                    """, arguments: [pair.catA, pair.catB, pair.styleA, pair.styleB,
                                     pair.jobCount, pair.points,
                                     Double(pair.jobCount) / Double(max(jobStyles.count, 1))])
            }
        }
    }
}
```

### 2. Add type-level co-occurrence calculation

Same pattern as style, but drills from accepted style pairs to type pairs:

```swift
/// After a style-level poll is accepted, calculate type-level co-occurrence.
public func calculateTypeCoOccurrence(
    styleAId: Int64,
    styleBId: Int64,
    categoryAId: Int64,
    categoryBId: Int64,
    windowMonths: Int = 48
) throws {
    // Same pattern as calculateStyleCoOccurrence but groups by p.type_id
    // and inserts with match_level = 'type'
    // Uses type_a_id, type_b_id columns
    try db.writer.write { dbConn in
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -max(3, min(windowMonths, 48)), to: Date())!
        let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT jp.job_id, p.style_id, p.type_id, SUM(jp.qty_consumed) AS total_qty
            FROM job_parts jp
            JOIN parts p ON p.id = jp.part_id
            WHERE jp.deleted_at IS NULL AND p.deleted_at IS NULL
              AND p.style_id IN (?, ?)
              AND p.type_id IS NOT NULL
              AND jp.consumed_at >= ?
            GROUP BY jp.job_id, p.style_id, p.type_id
            """, arguments: [styleAId, styleBId, cutoff])

        var jobTypes: [Int64: [(styleId: Int64, typeId: Int64, qty: Int)]] = [:]
        for row in rows {
            let jobId: Int64 = row["job_id"]
            jobTypes[jobId, default: []].append((
                styleId: row["style_id"],
                typeId: row["type_id"],
                qty: row["total_qty"]
            ))
        }

        var pairPoints: [String: (typeA: Int64, typeB: Int64, points: Int, jobCount: Int)] = [:]
        for (_, types) in jobTypes {
            let fromA = types.filter { $0.styleId == styleAId }
            let fromB = types.filter { $0.styleId == styleBId }
            for a in fromA {
                for b in fromB {
                    let (tA, tB) = a.typeId < b.typeId ? (a.typeId, b.typeId) : (b.typeId, a.typeId)
                    let key = "\(tA)-\(tB)"
                    var existing = pairPoints[key] ?? (typeA: tA, typeB: tB, points: 0, jobCount: 0)
                    existing.points += min(a.qty, b.qty)
                    existing.jobCount += 1
                    pairPoints[key] = existing
                }
            }
        }

        for (_, pair) in pairPoints {
            let existing = try Row.fetchOne(dbConn, sql: """
                SELECT id FROM co_occurrence_pairs
                WHERE category_a_id = ? AND category_b_id = ?
                  AND type_a_id = ? AND type_b_id = ? AND match_level = 'type'
                """, arguments: [categoryAId, categoryBId, pair.typeA, pair.typeB])

            if let existing = existing {
                let existingId: Int64 = existing["id"]
                try dbConn.execute(sql: "UPDATE co_occurrence_pairs SET points = ?, co_occurrence_count = ?, last_computed = datetime('now') WHERE id = ?",
                                   arguments: [pair.points, pair.jobCount, existingId])
            } else {
                try dbConn.execute(sql: """
                    INSERT INTO co_occurrence_pairs
                    (category_a_id, category_b_id, style_a_id, style_b_id, type_a_id, type_b_id,
                     co_occurrence_count, points, match_level, confidence, last_computed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'type', ?, datetime('now'))
                    """, arguments: [categoryAId, categoryBId, styleAId, styleBId,
                                     pair.typeA, pair.typeB, pair.jobCount, pair.points,
                                     Double(pair.jobCount) / Double(max(jobTypes.count, 1))])
            }
        }
    }
}
```

### 3. Trigger drill-down after poll acceptance

Update `closePoll()` (from 19C) to trigger the next-level calculation when a poll is accepted:

After the line that creates the companion rule (inside the `if passed && result != "tied"` block), add:

```swift
// Trigger drill-down to next level
let matchLevel: String = poll["match_level"]
switch matchLevel {
case "category":
    // Drill down to style level
    if let catA: Int64 = poll["source_category_id"],
       let catB: Int64 = poll["target_category_id"] {
        // This runs in the same write transaction
        // but we need to call it after the transaction completes
        // Store the IDs for post-transaction drill-down
    }
case "style":
    // Drill down to type level
    break
case "type":
    // Brand level is the end — no further drill-down
    break
default:
    break
}
```

**Important:** Since `closePoll()` runs inside a write transaction, and the drill-down methods also need write access, the drill-down should be triggered AFTER the `closePoll()` transaction completes. Add a new method:

```swift
/// Run the full auto-discovery cycle: close expired polls, calculate points,
/// trigger drill-downs for accepted polls, create weekly poll if needed.
/// Call this on app launch or daily.
public func runAutoDiscoveryCycle() throws {
    // 1. Close expired polls
    try closeExpiredPolls()

    // 2. Purge expired cascade-deleted rules
    try purgeExpiredRules()

    // 3. Recalculate category-level co-occurrence points
    try calculateCoOccurrencePoints()

    // 4. For any recently accepted category-level polls, trigger style drill-down
    let recentlyAccepted = try db.writer.read { dbConn in
        try Row.fetchAll(dbConn, sql: """
            SELECT cp.source_category_id, cp.target_category_id,
                   cp.source_style_id, cp.target_style_id,
                   cp.match_level
            FROM companion_polls cp
            WHERE cp.result = 'accepted'
              AND cp.completed_at >= datetime('now', '-7 days')
            ORDER BY cp.completed_at DESC
            """)
    }

    for poll in recentlyAccepted {
        let level: String = poll["match_level"]
        switch level {
        case "category":
            if let catA: Int64 = poll["source_category_id"],
               let catB: Int64 = poll["target_category_id"] {
                try calculateStyleCoOccurrence(categoryAId: catA, categoryBId: catB)
            }
        case "style":
            if let styleA: Int64 = poll["source_style_id"],
               let styleB: Int64 = poll["target_style_id"],
               let catA: Int64 = poll["source_category_id"],
               let catB: Int64 = poll["target_category_id"] {
                try calculateTypeCoOccurrence(styleAId: styleA, styleBId: styleB,
                                              categoryAId: catA, categoryBId: catB)
            }
        default:
            break
        }
    }

    // 5. Create weekly poll if none exists this week
    try createWeeklyPoll()

    // 6. Log the analysis run
    let now = ISO8601DateFormatter().string(from: Date())
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            INSERT INTO companion_auto_discovery_log
            (analysis_date, match_level, data_window_months, pairs_analyzed, created_at)
            VALUES (?, 'all', 48, 0, datetime('now'))
            """, arguments: [now])
    }
}
```

### 4. Trigger on app launch

In `AppCore.swift` (or wherever the app initializes services), add a call to run the auto-discovery cycle after login:

```swift
// In AppCore, after services are initialized and user is logged in:
Task {
    do {
        try appCore.partsService?.runAutoDiscoveryCycle()
    } catch {
        print("[AppCore] Auto-discovery cycle failed: \(error)")
    }
}
```

This should run asynchronously and not block the UI.

## Success Criteria
- [ ] `calculateStyleCoOccurrence()` drills down from category pairs to style-level points
- [ ] `calculateTypeCoOccurrence()` drills from style pairs to type-level points
- [ ] `runAutoDiscoveryCycle()` orchestrates the full cycle: close expired → purge → recalculate → drill-down → create poll → log
- [ ] Drill-down triggered for recently accepted polls (last 7 days)
- [ ] Auto-discovery runs on app launch without blocking UI
- [ ] Analysis logged to `companion_auto_discovery_log`
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19J Results (YYYY-MM-DD)
- Added calculateStyleCoOccurrence() and calculateTypeCoOccurrence() drill-down methods
- Added runAutoDiscoveryCycle() orchestration method
- Wired auto-discovery into AppCore app launch
- Build: [PASS/FAIL]
```

When done, start prompt 19K next.
