# 37A — Audit Confidence System: Migration + Service

> **Chain position:** **37A** → 37B → 37C → 37D
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

Full confidence system per `docs/plans/warehouse-audit-intelligence.md`. Part confidence decays daily, audits reset it, movements affect it, multi-user consensus verification.

## Task

### Migration: part_confidence
```sql
CREATE TABLE part_confidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id) ON DELETE CASCADE,
    confidence_percent REAL NOT NULL DEFAULT 0.0,
    reliability_level INTEGER NOT NULL DEFAULT 0,  -- 0-10 scale
    last_audit_date TEXT,
    last_audit_by INTEGER REFERENCES users(id),
    last_audit_count INTEGER,
    system_count INTEGER NOT NULL DEFAULT 0,
    decay_rate REAL NOT NULL DEFAULT 0.066,  -- % per day
    movement_decay_factor REAL NOT NULL DEFAULT 1.0,
    clean_audit_streak INTEGER NOT NULL DEFAULT 0,
    misplacement_count INTEGER NOT NULL DEFAULT 0,
    last_misplacement_date TEXT,
    total_audit_count INTEGER NOT NULL DEFAULT 0,
    total_variance_dollars REAL NOT NULL DEFAULT 0.0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(part_id, area_id)
);
```

### Migration: audit_sessions
```sql
CREATE TABLE audit_sessions_v2 (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_type TEXT NOT NULL DEFAULT 'count',  -- 'count', 'organization', 'quick', 'speed', 'consensus'
    started_by INTEGER NOT NULL REFERENCES users(id),
    floor_plan_id INTEGER REFERENCES warehouse_floor_plans(id),
    target_area_id INTEGER REFERENCES warehouse_storage_areas(id),
    target_unit_id INTEGER REFERENCES warehouse_storage_units(id),
    status TEXT NOT NULL DEFAULT 'active',  -- 'active', 'paused', 'completed'
    parts_counted INTEGER NOT NULL DEFAULT 0,
    discrepancies_found INTEGER NOT NULL DEFAULT 0,
    misplaced_found INTEGER NOT NULL DEFAULT 0,
    started_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    deleted_at TEXT
);
```

### Migration: audit_counts
```sql
CREATE TABLE audit_counts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES audit_sessions_v2(id) ON DELETE CASCADE,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id),
    system_count INTEGER NOT NULL,
    user_count INTEGER NOT NULL,
    variance INTEGER NOT NULL,
    variance_dollars REAL NOT NULL DEFAULT 0.0,
    variance_percent REAL NOT NULL DEFAULT 0.0,
    result TEXT NOT NULL,  -- 'exact', 'neutral', 'over', 'under'
    counted_by INTEGER NOT NULL REFERENCES users(id),
    counted_at TEXT DEFAULT (datetime('now'))
);
```

### Migration: misplaced_parts_log
```sql
CREATE TABLE misplaced_parts_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    found_at_area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id),
    home_area_id INTEGER REFERENCES warehouse_storage_areas(id),
    qty_found INTEGER NOT NULL,
    resolution TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'moved_to_home', 'left_here', 'reassigned', 'carted'
    resolved_by INTEGER REFERENCES users(id),
    resolved_at TEXT,
    found_by INTEGER NOT NULL REFERENCES users(id),
    found_at TEXT DEFAULT (datetime('now'))
);
```

### Migration: user_warehouse_ratings
```sql
CREATE TABLE user_warehouse_ratings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    overall_rating REAL NOT NULL DEFAULT 5.0,
    accuracy_rating REAL NOT NULL DEFAULT 5.0,
    effort_rating REAL NOT NULL DEFAULT 5.0,
    placement_rating REAL NOT NULL DEFAULT 5.0,
    wizard_compliance REAL NOT NULL DEFAULT 5.0,
    speed_rating REAL NOT NULL DEFAULT 5.0,
    proactive_rating REAL NOT NULL DEFAULT 5.0,
    total_audits INTEGER NOT NULL DEFAULT 0,
    total_accurate INTEGER NOT NULL DEFAULT 0,
    total_misplacements_found INTEGER NOT NULL DEFAULT 0,
    total_proactive_fixes INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(user_id)
);
```

### Migration: organization_ratings
```sql
CREATE TABLE organization_ratings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id) ON DELETE CASCADE,
    overall_rating REAL NOT NULL DEFAULT 5.0,
    labels_accurate INTEGER NOT NULL DEFAULT 0,  -- bool
    parts_in_home INTEGER NOT NULL DEFAULT 0,
    no_duplicates INTEGER NOT NULL DEFAULT 0,
    not_overcrowded INTEGER NOT NULL DEFAULT 0,
    bins_assigned INTEGER NOT NULL DEFAULT 0,
    similar_parts_nearby INTEGER NOT NULL DEFAULT 0,
    clean_audit_count INTEGER NOT NULL DEFAULT 0,
    last_org_check TEXT,
    last_org_check_by INTEGER REFERENCES users(id),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(area_id)
);
```

### Migration: consolidation_votes
```sql
CREATE TABLE consolidation_votes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    part_id INTEGER NOT NULL REFERENCES parts(id),
    current_areas TEXT NOT NULL,  -- JSON array of area IDs
    chosen_area_id INTEGER REFERENCES warehouse_storage_areas(id),
    status TEXT NOT NULL DEFAULT 'voting',  -- 'voting', 'decided', 'applied', 'dismissed'
    manager_override INTEGER NOT NULL DEFAULT 0,
    dismiss_reason TEXT,
    ignore_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    decided_at TEXT,
    deleted_at TEXT
);

CREATE TABLE consolidation_vote_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    vote_id INTEGER NOT NULL REFERENCES consolidation_votes(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id),
    chosen_area_id INTEGER NOT NULL REFERENCES warehouse_storage_areas(id),
    voted_at TEXT DEFAULT (datetime('now'))
);
```

### Service Methods (WarehouseService)

**Confidence:**
- `getPartConfidence(partId:areaId:)` → PartConfidence?
- `setPartConfidence(partId:areaId:percent:)` → updates
- `decayAllConfidence()` → daily batch job, applies decay modifiers
- `recordAuditCount(sessionId:partId:areaId:userCount:countedBy:)` → AuditCount + updates confidence
- `calculateMovementDecayFactor(partId:areaId:)` → factor based on movement count since last audit

**Reliability Level:**
- `calculateReliabilityLevel(partId:areaId:)` → Int (0-10)
- `getPartsAtLevel(level:)` → [PartConfidence]

**User Ratings:**
- `getUserWarehouseRating(userId:)` → UserWarehouseRating
- `updateUserRating(userId:action:result:)` → recalculates
- `getWarehouseLeaderboard()` → [UserWarehouseRating] sorted

**Organization:**
- `getOrganizationRating(areaId:)` → OrganizationRating
- `recordOrgCheck(areaId:checkedBy:labels:partsInHome:noDuplicates:notOvercrowded:binsAssigned:)` → updates
- `getWarehouseOverallScore()` → Double (0-10 composite)

**Consolidation:**
- `suggestConsolidation(partId:)` → ConsolidationVote?
- `castConsolidationVote(voteId:userId:chosenAreaId:)` → updates
- `managerOverrideConsolidation(voteId:chosenAreaId:)` → applies
- `applyConsolidation(voteId:)` → creates pending movements

**Misplaced Parts:**
- `logMisplacedPart(partId:foundAtAreaId:homeAreaId:qtyFound:foundBy:)` → MisplacedPartsLog
- `resolveMisplacedPart(logId:resolution:resolvedBy:)` → updates

### ConflictResolver
Add all new tables to whitelist.

## Success Criteria
- [ ] 8 new tables created
- [ ] All models with CodingKeys + Sendable
- [ ] 20+ service methods for confidence, ratings, consolidation
- [ ] ConflictResolver updated
- [ ] Project builds with no errors
