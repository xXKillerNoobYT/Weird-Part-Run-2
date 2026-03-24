# 19B — Companion Rules CRUD + Points Engine Service Methods

## Context
You are working on a SwiftUI iOS app. Migration 025 (from prompt 19A) added: `type_id` on `companion_rule_sources/targets`, `parent_rule_id` + `auto_delete_at` + `deleted_at` on `companion_rules`, and `points` + `match_level` + `rejection_count` + `is_blocked` + `tied_cooldown_until` on `co_occurrence_pairs`.

The existing `PartsService.swift` has companion methods starting around line 1759:
- `listCompanionRules()` — returns `[CompanionRuleWithRelations]` with sources/targets
- `createCompanionRule(name:, description:, styleMatch:, qtyMode:, qtyRatio:)` — inserts into `companion_rules`
- `updateCompanionRule(id:, ...)` — updates name/description/style_match/qty_mode/qty_ratio
- `deleteCompanionRule(id:)` — sets `is_active = 0`
- `listPartAlternatives(partId:)` — bidirectional query
- `linkPartAlternative(...)` — insert
- `unlinkPartAlternative(linkId:)` — hard delete

**Key tables for points calculation:**
- `job_parts` — job_id, part_id, qty_consumed (parts used on jobs)
- `parts` — category_id, style_id, type_id, brand_id, color_id
- `co_occurrence_pairs` — category_a_id, category_b_id, points, match_level, rejection_count, is_blocked, tied_cooldown_until

## Task

Add the following methods to `PartsService.swift`. Add them in a new `// MARK: - Companion Rules V2` section after the existing companion methods.

### 1. Enhanced Rule Listing

```swift
/// Row returned by the hierarchical rule listing.
public struct CompanionRuleHierarchyRow: Sendable {
    public let id: Int64
    public let name: String
    public let description: String?
    public let matchLevel: String       // "category", "style", "type"
    public let tryMatchBrand: Int
    public let autoColorMatch: Int
    public let qtyMode: String
    public let qtyRatio: Double
    public let isActive: Int
    public let parentRuleId: Int64?
    public let autoDeleteAt: String?    // non-nil = scheduled for deletion
    public let deletedAt: String?
    public let createdAt: String?
    public let sources: [CompanionRuleSource]
    public let targets: [CompanionRuleTarget]
    public let childCount: Int          // number of child rules
    public let isOrphaned: Bool         // parent was deleted, this child is pending deletion
}
```

```swift
/// List all companion rules grouped by hierarchy. Parent rules first, children indented.
/// Includes orphaned children (parent deleted, auto_delete_at set).
public func listCompanionRulesHierarchy() throws -> [CompanionRuleHierarchyRow] {
    // Query all rules (including soft-deleted ones with auto_delete_at still in future)
    // For each rule:
    //   - Fetch sources from companion_rule_sources (category_id, style_id, type_id)
    //   - Fetch targets from companion_rule_targets
    //   - Count children: SELECT COUNT(*) FROM companion_rules WHERE parent_rule_id = ?
    //   - Determine match level from which IDs are set in sources (category only = "category", + style = "style", + type = "type")
    //   - isOrphaned = parent_rule_id IS NOT NULL AND parent rule has deleted_at set
    // Sort: parent rules first (parent_rule_id IS NULL), then children grouped under parents
    // Exclude rules where auto_delete_at < datetime('now') (already expired)
}
```

### 2. Create Rule at Hierarchy Level

```swift
/// Create a companion rule at a specific hierarchy level (category/style/type).
/// Returns the new rule ID.
@discardableResult
public func createCompanionRuleAtLevel(
    name: String,
    description: String? = nil,
    qtyMode: String = "sum",
    qtyRatio: Double = 1.0,
    tryMatchBrand: Bool = false,
    autoColorMatch: Bool = true,
    parentRuleId: Int64? = nil,
    sources: [(categoryId: Int64, styleId: Int64?, typeId: Int64?)],
    targets: [(categoryId: Int64, styleId: Int64?, typeId: Int64?)]
) throws -> Int64 {
    try db.writer.write { dbConn in
        // Determine match level from the first source entry
        let matchLevel: String
        if sources.first?.typeId != nil { matchLevel = "type" }
        else if sources.first?.styleId != nil { matchLevel = "style" }
        else { matchLevel = "category" }

        // Insert into companion_rules
        try dbConn.execute(sql: """
            INSERT INTO companion_rules
            (name, description, style_match, qty_mode, qty_ratio, try_match_brand, auto_color_match,
             parent_rule_id, is_active, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
            """,
            arguments: [name, description, matchLevel, qtyMode, qtyRatio,
                        tryMatchBrand ? 1 : 0, autoColorMatch ? 1 : 0, parentRuleId])
        let ruleId = dbConn.lastInsertedRowID

        // Insert sources
        for src in sources {
            try dbConn.execute(sql: """
                INSERT INTO companion_rule_sources (rule_id, category_id, style_id, type_id)
                VALUES (?, ?, ?, ?)
                """, arguments: [ruleId, src.categoryId, src.styleId, src.typeId])
        }

        // Insert targets
        for tgt in targets {
            try dbConn.execute(sql: """
                INSERT INTO companion_rule_targets (rule_id, category_id, style_id, type_id)
                VALUES (?, ?, ?, ?)
                """, arguments: [ruleId, tgt.categoryId, tgt.styleId, tgt.typeId])
        }

        return ruleId
    }
}
```

### 3. Soft Delete with Cascade

```swift
/// Soft-delete a companion rule. If it has children, schedule them for auto-deletion in 30 days.
/// Children turn red in the UI and can be restored if the parent is restored.
public func deleteCompanionRuleSoft(id: Int64) throws {
    try db.writer.write { dbConn in
        let now = ISO8601DateFormatter().string(from: Date())
        // Soft delete the rule itself
        try dbConn.execute(sql: """
            UPDATE companion_rules SET deleted_at = ?, is_active = 0, updated_at = ?
            WHERE id = ?
            """, arguments: [now, now, id])

        // Schedule children for auto-deletion in 30 days
        let deleteDate = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date())!)
        try dbConn.execute(sql: """
            UPDATE companion_rules SET auto_delete_at = ?, is_active = 0, updated_at = ?
            WHERE parent_rule_id = ? AND deleted_at IS NULL
            """, arguments: [deleteDate, now, id])
    }
}

/// Restore a soft-deleted companion rule and cancel auto-deletion of its children.
public func restoreCompanionRule(id: Int64) throws {
    try db.writer.write { dbConn in
        let now = ISO8601DateFormatter().string(from: Date())
        // Restore the rule
        try dbConn.execute(sql: """
            UPDATE companion_rules SET deleted_at = NULL, is_active = 1, updated_at = ?
            WHERE id = ?
            """, arguments: [now, id])

        // Cancel auto-deletion of children
        try dbConn.execute(sql: """
            UPDATE companion_rules SET auto_delete_at = NULL, is_active = 1, updated_at = ?
            WHERE parent_rule_id = ? AND deleted_at IS NULL
            """, arguments: [now, id])
    }
}

/// Hard-delete rules that have passed their auto_delete_at date.
/// Call this periodically (e.g., on app launch).
public func purgeExpiredRules() throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            DELETE FROM companion_rules
            WHERE auto_delete_at IS NOT NULL AND auto_delete_at < datetime('now')
            """)
    }
}
```

### 4. List All Alternatives (for the alternatives tab)

```swift
/// List ALL part alternatives (not filtered by a specific part). For the alternatives tab.
public func listAllAlternatives() throws -> [PartAlternativeWithName] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT pa.id, pa.part_id, pa.alternative_part_id,
                   pa.relationship, pa.preference, pa.notes,
                   pa.created_by, pa.created_at,
                   p1.name AS part_name, p1.code AS part_code,
                   p2.name AS alt_name, p2.code AS alt_code
            FROM part_alternatives pa
            JOIN parts p1 ON p1.id = pa.part_id
            JOIN parts p2 ON p2.id = pa.alternative_part_id
            WHERE p1.deleted_at IS NULL AND p2.deleted_at IS NULL
            ORDER BY pa.preference ASC, pa.id ASC
            """)
        return rows.map { row in
            PartAlternativeWithName(
                id: row["id"], partId: row["part_id"],
                alternativePartId: row["alternative_part_id"],
                relationship: row["relationship"], preference: row["preference"],
                notes: row["notes"], createdBy: row["created_by"],
                createdAt: row["created_at"],
                alternativePartName: row["alt_name"],
                alternativePartCode: row["alt_code"]
            )
        }
    }
}
```

### 5. Points Calculation Engine

```swift
/// Calculate co-occurrence points by scanning job_parts data.
/// Groups parts by job, counts category-level co-occurrences.
/// 1 point per part qty co-occurring on the same job.
/// Analysis window: 3 months minimum, up to 48 months of history.
///
/// Example: Job has Boxes(100) + Outlets(75) → Boxes+Outlets = 75 points (min of the two quantities)
///
/// Updates the co_occurrence_pairs table with new point totals.
public func calculateCoOccurrencePoints(windowMonths: Int = 48) throws {
    try db.writer.write { dbConn in
        let windowMonthsClamped = max(3, min(windowMonths, 48))
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -windowMonthsClamped, to: Date())!
        let cutoff = ISO8601DateFormatter().string(from: cutoffDate)

        // Get all job_parts within the analysis window, grouped by job
        // Join parts to get category_id
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT jp.job_id, p.category_id, SUM(jp.qty_consumed) AS total_qty
            FROM job_parts jp
            JOIN parts p ON p.id = jp.part_id
            WHERE jp.deleted_at IS NULL
              AND p.deleted_at IS NULL
              AND p.category_id IS NOT NULL
              AND jp.consumed_at >= ?
            GROUP BY jp.job_id, p.category_id
            """, arguments: [cutoff])

        // Group by job_id: { jobId: [(categoryId, totalQty)] }
        var jobCategories: [Int64: [(categoryId: Int64, qty: Int)]] = [:]
        for row in rows {
            let jobId: Int64 = row["job_id"]
            let catId: Int64 = row["category_id"]
            let qty: Int = row["total_qty"]
            jobCategories[jobId, default: []].append((categoryId: catId, qty: qty))
        }

        // Calculate points for each unique category pair across all jobs
        var pairPoints: [String: (catA: Int64, catB: Int64, points: Int, jobCount: Int)] = [:]
        for (_, categories) in jobCategories {
            guard categories.count >= 2 else { continue }
            // Generate all unique pairs
            for i in 0..<categories.count {
                for j in (i+1)..<categories.count {
                    let a = categories[i]
                    let b = categories[j]
                    // Ensure consistent ordering (smaller ID first)
                    let (catA, catB, pts) = a.categoryId < b.categoryId
                        ? (a.categoryId, b.categoryId, min(a.qty, b.qty))
                        : (b.categoryId, a.categoryId, min(a.qty, b.qty))
                    let key = "\(catA)-\(catB)"
                    var existing = pairPoints[key] ?? (catA: catA, catB: catB, points: 0, jobCount: 0)
                    existing.points += pts
                    existing.jobCount += 1
                    pairPoints[key] = existing
                }
            }
        }

        // Upsert into co_occurrence_pairs
        for (_, pair) in pairPoints {
            // Check if pair exists
            let existing = try Row.fetchOne(dbConn, sql: """
                SELECT id, points FROM co_occurrence_pairs
                WHERE category_a_id = ? AND category_b_id = ? AND match_level = 'category'
                """, arguments: [pair.catA, pair.catB])

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
                    (category_a_id, category_b_id, co_occurrence_count, points, match_level,
                     confidence, last_computed)
                    VALUES (?, ?, ?, ?, 'category', ?, datetime('now'))
                    """, arguments: [pair.catA, pair.catB, pair.jobCount, pair.points,
                                     Double(pair.jobCount) / Double(max(jobCategories.count, 1))])
            }
        }
    }
}

/// Get qualified pairs that meet all thresholds for poll candidacy.
/// Excludes: blocked pairs, pairs with active polls, pairs with tied_cooldown_until in the future.
public func getQualifiedPairs(
    minPoints: Int = 100,
    minConfidence: Double = 0.15,
    minJobs: Int = 15,
    level: String = "category"
) throws -> [(pairId: Int64, catAId: Int64, catBId: Int64, catAName: String, catBName: String, points: Int, confidence: Double, jobCount: Int)] {
    try db.writer.read { dbConn in
        let rows = try Row.fetchAll(dbConn, sql: """
            SELECT cop.id, cop.category_a_id, cop.category_b_id,
                   cop.points, cop.confidence, cop.co_occurrence_count,
                   ca.name AS cat_a_name, cb.name AS cat_b_name
            FROM co_occurrence_pairs cop
            JOIN part_categories ca ON ca.id = cop.category_a_id
            JOIN part_categories cb ON cb.id = cop.category_b_id
            WHERE cop.match_level = ?
              AND cop.points >= ?
              AND cop.confidence >= ?
              AND cop.co_occurrence_count >= ?
              AND cop.is_blocked = 0
              AND (cop.tied_cooldown_until IS NULL OR cop.tied_cooldown_until < date('now'))
              AND cop.id NOT IN (
                  SELECT co_occurrence_id FROM companion_polls
                  WHERE status = 'active' AND match_level = ?
              )
            ORDER BY cop.points DESC
            """, arguments: [level, minPoints, minConfidence, minJobs, level])

        return rows.map { row in
            (pairId: row["id"] as Int64,
             catAId: row["category_a_id"] as Int64,
             catBId: row["category_b_id"] as Int64,
             catAName: row["cat_a_name"] as String,
             catBName: row["cat_b_name"] as String,
             points: row["points"] as Int,
             confidence: row["confidence"] as Double,
             jobCount: row["co_occurrence_count"] as Int)
        }
    }
}

/// Apply a rejection penalty to a co-occurrence pair (-100 points).
/// If rejection_count reaches 5, mark as permanently blocked.
public func applyRejectionPenalty(pairId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE co_occurrence_pairs
            SET points = MAX(0, points - 100),
                rejection_count = rejection_count + 1,
                is_blocked = CASE WHEN rejection_count + 1 >= 5 THEN 1 ELSE 0 END,
                last_computed = datetime('now')
            WHERE id = ?
            """, arguments: [pairId])
    }
}

/// Apply a skip penalty to a co-occurrence pair (-50 points only, no rejection count increase).
public func applySkipPenalty(pairId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE co_occurrence_pairs
            SET points = MAX(0, points - 50),
                last_computed = datetime('now')
            WHERE id = ?
            """, arguments: [pairId])
    }
}

/// Admin reset: unblock a permanently blocked pair and reset its rejection count.
public func resetBlockedPair(pairId: Int64) throws {
    try db.writer.write { dbConn in
        try dbConn.execute(sql: """
            UPDATE co_occurrence_pairs
            SET is_blocked = 0, rejection_count = 0, last_computed = datetime('now')
            WHERE id = ?
            """, arguments: [pairId])
    }
}
```

## Success Criteria
- [ ] `listCompanionRulesHierarchy()` returns rules grouped by parent with orphan detection
- [ ] `createCompanionRuleAtLevel(...)` inserts rule + sources + targets at correct level
- [ ] `deleteCompanionRuleSoft(id:)` sets deleted_at and schedules children for 30-day auto-delete
- [ ] `restoreCompanionRule(id:)` clears deletion cascade
- [ ] `purgeExpiredRules()` hard-deletes expired rules
- [ ] `listAllAlternatives()` returns all alternatives with joined part names
- [ ] `calculateCoOccurrencePoints()` scans job_parts and writes correct point totals
- [ ] `getQualifiedPairs(...)` filters by points, confidence, job count, excludes blocked/cooldown/active
- [ ] `applyRejectionPenalty(pairId:)` subtracts 100 points, blocks at 5 rejections
- [ ] `applySkipPenalty(pairId:)` subtracts 50 points only
- [ ] `resetBlockedPair(pairId:)` unblocks and resets rejection count
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19B Results (YYYY-MM-DD)
- Added CompanionRuleHierarchyRow struct
- Added listCompanionRulesHierarchy() with parent/child grouping
- Added createCompanionRuleAtLevel() with source/target insertion
- Added deleteCompanionRuleSoft/restoreCompanionRule/purgeExpiredRules cascade
- Added listAllAlternatives() for alternatives tab
- Added calculateCoOccurrencePoints() scanning job_parts (3-48 month window)
- Added getQualifiedPairs() with threshold filtering
- Added applyRejectionPenalty/applySkipPenalty/resetBlockedPair
- Build: [PASS/FAIL]
```

When done, start prompt 19C next.
