# 19A — Companion System Migration + Models

## Context
You are working on a SwiftUI iOS app. The companion rules system needs new tables for polls (team voting on auto-suggested rules), expanded hierarchy matching (type-level + brand matching + color auto-match), a points-based auto-discovery system, and rule hierarchy (parent/child linking).

**Existing tables** (migration 016):
- `companion_rules` — name, description, style_match, qty_mode, qty_ratio, is_active, created_by
- `companion_rule_sources` — rule_id, category_id, style_id
- `companion_rule_targets` — rule_id, category_id, style_id
- `companion_suggestions` — rule_id, target info, suggested_qty, status
- `companion_suggestion_sources` — suggestion_id, category_id, style_id, qty
- `co_occurrence_pairs` — category_a_id, category_b_id, co_occurrence_count, total_jobs_a, total_jobs_b, avg_ratio_a_to_b, confidence, last_computed. UNIQUE(category_a_id, category_b_id)
- `companion_feedback` — suggestion_id, rule_id, action, suggested_qty, final_qty
- `part_alternatives` — part_id, alternative_part_id, relationship, preference

**Existing notifications table** (migration 001): `notifications` — user_id, title, body, severity, source, entity_type, entity_id, is_read

**Existing permissions system**: `hat_permissions` table with `hat_id` + `permission_key`. Hats: Admin(100), Manager(80), Office(60), Lead(50), Worker(30), Apprentice(20), Grunt(10). Permissions seeded in `AuthService.defaultPermissionMap()`.

## Task

### 1. Add migration 025 in `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`

Register it as `registerMigration025CompanionPolls` and add the call in `registerAllMigrations` (after `registerMigration024ScheduledDeletions`).

#### ALTER existing tables:

```sql
-- Add type_id to sources and targets (rules can now match at type level)
ALTER TABLE companion_rule_sources ADD COLUMN type_id INTEGER REFERENCES part_types;
ALTER TABLE companion_rule_targets ADD COLUMN type_id INTEGER REFERENCES part_types;

-- Add brand matching + color auto-match flags to rules
ALTER TABLE companion_rules ADD COLUMN try_match_brand INTEGER NOT NULL DEFAULT 0;
ALTER TABLE companion_rules ADD COLUMN auto_color_match INTEGER NOT NULL DEFAULT 1;

-- Add parent/child rule hierarchy (for cascade: category→style→type→brand)
ALTER TABLE companion_rules ADD COLUMN parent_rule_id INTEGER REFERENCES companion_rules;
-- When parent deleted, children turn red and auto-delete after 30 days
ALTER TABLE companion_rules ADD COLUMN auto_delete_at TEXT;
-- Soft delete for rules
ALTER TABLE companion_rules ADD COLUMN deleted_at TEXT;

-- Add points system + drill-down level to co_occurrence_pairs
ALTER TABLE co_occurrence_pairs ADD COLUMN points INTEGER NOT NULL DEFAULT 0;
ALTER TABLE co_occurrence_pairs ADD COLUMN style_a_id INTEGER REFERENCES part_styles;
ALTER TABLE co_occurrence_pairs ADD COLUMN style_b_id INTEGER REFERENCES part_styles;
ALTER TABLE co_occurrence_pairs ADD COLUMN type_a_id INTEGER REFERENCES part_types;
ALTER TABLE co_occurrence_pairs ADD COLUMN type_b_id INTEGER REFERENCES part_types;
ALTER TABLE co_occurrence_pairs ADD COLUMN brand_a_id INTEGER REFERENCES brands;
ALTER TABLE co_occurrence_pairs ADD COLUMN brand_b_id INTEGER REFERENCES brands;
ALTER TABLE co_occurrence_pairs ADD COLUMN match_level TEXT NOT NULL DEFAULT 'category';
-- match_level: "category", "style", "type", "brand"
ALTER TABLE co_occurrence_pairs ADD COLUMN rejection_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE co_occurrence_pairs ADD COLUMN is_blocked INTEGER NOT NULL DEFAULT 0;
-- is_blocked: 1 when rejection_count >= 5 (admin can reset)
ALTER TABLE co_occurrence_pairs ADD COLUMN tied_cooldown_until TEXT;
-- tied_cooldown_until: if poll result was tied, don't re-ask until this date (2 months out)
```

Note: The existing unique key on `co_occurrence_pairs` is `(category_a_id, category_b_id)`. After adding match_level, create a new index:
```sql
CREATE INDEX IF NOT EXISTS idx_co_occurrence_level ON co_occurrence_pairs(match_level, points DESC);
CREATE INDEX IF NOT EXISTS idx_co_occurrence_blocked ON co_occurrence_pairs(is_blocked, match_level);
```

#### CREATE new tables:

```swift
// companion_polls — one poll per auto-suggested companion rule
try db.create(table: "companion_polls") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("co_occurrence_id", .integer).notNull()
        .references("co_occurrence_pairs", onDelete: .cascade)
    t.column("proposed_rule_name", .text).notNull()
    t.column("proposed_rule_description", .text)
    t.column("source_category_id", .integer).references("part_categories")
    t.column("source_style_id", .integer).references("part_styles")
    t.column("source_type_id", .integer).references("part_types")
    t.column("target_category_id", .integer).references("part_categories")
    t.column("target_style_id", .integer).references("part_styles")
    t.column("target_type_id", .integer).references("part_types")
    t.column("match_level", .text).notNull().defaults(to: "category")
    // match_level: "category", "style", "type", "brand"
    t.column("try_match_brand", .integer).notNull().defaults(to: 0)
    t.column("auto_color_match", .integer).notNull().defaults(to: 1)
    t.column("status", .text).notNull().defaults(to: "active")
    // status: "active", "closed", "locked", "skipped"
    // "locked" = admin used "I know the answer"
    t.column("admin_locked_result", .text)
    // admin_locked_result: "accept" or "reject" — set when admin locks
    t.column("admin_locked_by", .integer).references("users")
    t.column("admin_locked_at", .text)
    t.column("result", .text)
    // result: "accepted", "rejected", "tied" — final outcome
    t.column("created_rule_id", .integer).references("companion_rules")
    // created_rule_id: if accepted, points to the auto-created companion_rule
    t.column("start_date", .text).notNull().defaults(sql: "(date('now'))")
    t.column("end_date", .text).notNull().defaults(sql: "(date('now', '+30 days'))")
    t.column("completed_at", .text)
    t.column("created_at", .text).defaults(sql: "(datetime('now'))")
}

// companion_votes — one vote per user per poll (all users can vote, only some count)
try db.create(table: "companion_votes") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("poll_id", .integer).notNull()
        .references("companion_polls", onDelete: .cascade)
    t.column("user_id", .integer).notNull()
        .references("users", onDelete: .cascade)
    t.column("vote", .text).notNull()
    // vote: "accept" or "reject"
    t.column("has_power", .integer).notNull().defaults(to: 0)
    // has_power: 1 if user has companion_vote_power permission when they voted
    // cached at vote time — if hat changes later, this vote keeps its original power
    t.column("voted_at", .text).notNull().defaults(sql: "(datetime('now'))")
    t.column("updated_at", .text).defaults(sql: "(datetime('now'))")
    t.uniqueKey(["poll_id", "user_id"])
}

// companion_poll_results — finalized results for closed polls
try db.create(table: "companion_poll_results") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("poll_id", .integer).notNull().unique()
        .references("companion_polls", onDelete: .cascade)
    t.column("passed", .integer).notNull()
    // passed: 1 = accepted, 0 = rejected
    t.column("total_votes", .integer).notNull().defaults(to: 0)
    t.column("powered_accept", .integer).notNull().defaults(to: 0)
    t.column("powered_reject", .integer).notNull().defaults(to: 0)
    t.column("all_accept", .integer).notNull().defaults(to: 0)
    // all_accept: total accept votes including non-powered (for leaderboard tracking)
    t.column("all_reject", .integer).notNull().defaults(to: 0)
    t.column("was_admin_locked", .integer).notNull().defaults(to: 0)
    t.column("finalized_at", .text).notNull().defaults(sql: "(datetime('now'))")
}

// companion_auto_discovery_log — tracks analysis runs
try db.create(table: "companion_auto_discovery_log") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("analysis_date", .text).notNull()
    t.column("match_level", .text).notNull()
    // match_level: "category", "style", "type", "brand"
    t.column("data_window_months", .integer).notNull()
    // how many months of history were analyzed (3-48)
    t.column("pairs_analyzed", .integer).notNull().defaults(to: 0)
    t.column("new_pairs_found", .integer).notNull().defaults(to: 0)
    t.column("poll_created_id", .integer).references("companion_polls")
    t.column("created_at", .text).defaults(sql: "(datetime('now'))")
}
```

Add indexes:
```swift
try db.create(index: "idx_polls_status", on: "companion_polls", columns: ["status"])
try db.create(index: "idx_polls_dates", on: "companion_polls", columns: ["start_date", "end_date"])
try db.create(index: "idx_votes_poll", on: "companion_votes", columns: ["poll_id"])
try db.create(index: "idx_votes_user", on: "companion_votes", columns: ["user_id"])
try db.create(index: "idx_rules_parent", on: "companion_rules", columns: ["parent_rule_id"])
```

#### Seed new permissions:

After the table creation, seed two new permission keys into `hat_permissions`:

```swift
// companion_vote_power — votes that actually count toward poll results
// Seeded for Admin, Manager, Lead hats
let voteHats = try Row.fetchAll(db, sql: "SELECT id FROM hats WHERE name IN ('Admin', 'Manager', 'Lead')")
for hat in voteHats {
    let hatId: Int64 = hat["id"]
    try db.execute(sql: "INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, 'companion_vote_power')", arguments: [hatId])
}

// vote_veto — admin controls: lock result, skip poll, preview next week
// Seeded for Admin hat only
if let adminHat = try Row.fetchOne(db, sql: "SELECT id FROM hats WHERE name = 'Admin'") {
    let adminId: Int64 = adminHat["id"]
    try db.execute(sql: "INSERT OR IGNORE INTO hat_permissions (hat_id, permission_key) VALUES (?, 'vote_veto')", arguments: [adminId])
}
```

### 2. Add model structs in `core/Sources/WiredPartCore/Models/Parts/PartsModels.swift`

Add after the existing `CompanionRule` struct (around line 437):

```swift
// MARK: - CompanionPoll

public struct CompanionPoll: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_polls"
    public var id: Int64?
    public var coOccurrenceId: Int64
    public var proposedRuleName: String
    public var proposedRuleDescription: String?
    public var sourceCategoryId: Int64?
    public var sourceStyleId: Int64?
    public var sourceTypeId: Int64?
    public var targetCategoryId: Int64?
    public var targetStyleId: Int64?
    public var targetTypeId: Int64?
    public var matchLevel: String
    public var tryMatchBrand: Int
    public var autoColorMatch: Int
    public var status: String
    public var adminLockedResult: String?
    public var adminLockedBy: Int64?
    public var adminLockedAt: String?
    public var result: String?
    public var createdRuleId: Int64?
    public var startDate: String
    public var endDate: String
    public var completedAt: String?
    public var createdAt: String?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionVote

public struct CompanionVote: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_votes"
    public var id: Int64?
    public var pollId: Int64
    public var userId: Int64
    public var vote: String
    public var hasPower: Int
    public var votedAt: String?
    public var updatedAt: String?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionPollResult

public struct CompanionPollResult: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_poll_results"
    public var id: Int64?
    public var pollId: Int64
    public var passed: Int
    public var totalVotes: Int
    public var poweredAccept: Int
    public var poweredReject: Int
    public var allAccept: Int
    public var allReject: Int
    public var wasAdminLocked: Int
    public var finalizedAt: String?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

// MARK: - CompanionAutoDiscoveryLog

public struct CompanionAutoDiscoveryLog: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "companion_auto_discovery_log"
    public var id: Int64?
    public var analysisDate: String
    public var matchLevel: String
    public var dataWindowMonths: Int
    public var pairsAnalyzed: Int
    public var newPairsFound: Int
    public var pollCreatedId: Int64?
    public var createdAt: String?

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### 3. Update ConflictResolver sync whitelist

In `core/Sources/WiredPartCore/Sync/ConflictResolver.swift`, find the companions section in the table whitelist (around line 153) and add:

```swift
"companion_polls", "companion_votes", "companion_poll_results", "companion_auto_discovery_log",
```

### 4. Update ChangeTracker

In `core/Sources/WiredPartCore/Sync/ChangeTracker.swift`, find where companion tables are registered and add the 4 new tables to the tracked tables list.

## Success Criteria
- [ ] Migration 025 registered and called in `registerAllMigrations`
- [ ] All ALTER TABLE statements execute: type_id on sources/targets, try_match_brand + auto_color_match + parent_rule_id + auto_delete_at + deleted_at on rules, points + style/type/brand IDs + match_level + rejection_count + is_blocked + tied_cooldown_until on co_occurrence_pairs
- [ ] 4 new tables created: `companion_polls`, `companion_votes`, `companion_poll_results`, `companion_auto_discovery_log`
- [ ] All indexes created
- [ ] 2 new permissions seeded: `companion_vote_power` (Admin, Manager, Lead) and `vote_veto` (Admin only)
- [ ] 4 model structs added to PartsModels.swift with correct column mapping
- [ ] ConflictResolver whitelist updated with 4 new tables
- [ ] ChangeTracker updated with 4 new tables
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 19A Results (YYYY-MM-DD)
- Added migration 025_companion_polls
- ALTER: companion_rule_sources + targets got type_id
- ALTER: companion_rules got try_match_brand, auto_color_match, parent_rule_id, auto_delete_at, deleted_at
- ALTER: co_occurrence_pairs got points, style/type/brand IDs, match_level, rejection_count, is_blocked, tied_cooldown_until
- CREATE: companion_polls, companion_votes, companion_poll_results, companion_auto_discovery_log
- SEED: companion_vote_power (Admin/Manager/Lead), vote_veto (Admin)
- Models: CompanionPoll, CompanionVote, CompanionPollResult, CompanionAutoDiscoveryLog
- Sync: ConflictResolver + ChangeTracker updated
- Build: [PASS/FAIL]
```

When done, start prompt 19B next.
