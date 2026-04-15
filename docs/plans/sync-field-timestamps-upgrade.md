# Sync LWW Upgrade — Per-Field Timestamps

> **Status:** Design approved 2026-04-14. Implementation pending.
> **Parent plan:** `docs/plans/april-2026-audit-closures.md` (#221 closure)
> **Supersedes:** `docs/dev-qa.md` Q13 (now processed).
> **GitHub Issue:** #221

---

## Context

The sync system uses Last-Write-Wins (LWW) for conflict resolution across devices. Per `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` line 79, the resolver is already **field-level** (per-field merge, not whole-row replacement). But the tiebreaker it uses to decide "which device's write wins for this field" is the ROW-level `updated_at` timestamp.

This has a subtle data-loss scenario:

- **10:00am** — Device A updates `parts` row 42, sets `name = "Cantex 3/4 PVC"`. `parts.updated_at` ← 10:00am.
- **10:05am** — Device A updates same row, sets `price = 12.50`. `parts.updated_at` ← 10:05am.
- **10:03am** — Device B (offline) updates same row, sets `name = "PVC 3/4 (Cantex)"`. `parts.updated_at` (on B's copy) ← 10:03am.
- **10:10am** — Devices sync.

ConflictResolver compares per-field. For `name`: Device A's 10:00 vs Device B's 10:03 → B wins the field (correct). For `price`: Device A's 10:05 vs Device B's (no change, still 10:03) → but because the tiebreaker is row-level `updated_at`, Device B's untouched `price` might win if the comparison logic isn't careful. At best this works by accident of the merge direction; at worst it loses Device A's 10:05 price update.

The true-correct behavior requires per-field timestamps.

---

## Design

### Schema change: `_field_timestamps` column on every synced table

```sql
-- Migration N — add field-level timestamps
-- Applied to every synced table (see list below).
ALTER TABLE <table> ADD COLUMN _field_timestamps TEXT;
```

The column holds a JSON map: `{"<field_name>": "<iso8601_timestamp>"}`. Fields not present in the map fall back to the row's `updated_at` (so pre-migration rows still merge correctly).

### Backfill

On migration, set `_field_timestamps = NULL` for every existing row. The ConflictResolver treats NULL as "all fields last-updated at row's `updated_at`." No immediate data change; pre-migration rows will begin accruing per-field timestamps the first time they're written after the migration.

### Write-path update pattern

Every service method that writes to a synced table must stamp the touched field(s) in `_field_timestamps`. The canonical helper:

```swift
// In a new file: core/Sources/WiredPartCore/Database/FieldTimestampHelper.swift

import GRDB

public enum FieldTimestampHelper {
    /// Merge new timestamp(s) into the existing _field_timestamps JSON blob.
    /// Call at the end of any write that touches synced fields.
    public static func stamp(_ fields: [String], table: String, rowId: Int64, in db: Database) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let existing: String? = try String.fetchOne(db,
            sql: "SELECT _field_timestamps FROM \(table) WHERE id = ?",
            arguments: [rowId])

        var map: [String: String] = [:]
        if let json = existing, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }

        for field in fields { map[field] = now }

        let newJSON = String(data: try JSONEncoder().encode(map), encoding: .utf8)!
        try db.execute(
            sql: "UPDATE \(table) SET _field_timestamps = ? WHERE id = ?",
            arguments: [newJSON, rowId])
    }
}
```

Every service write becomes:

```swift
// Before
try db.execute(sql: "UPDATE parts SET name = ? WHERE id = ?", arguments: [name, id])

// After
try db.execute(sql: "UPDATE parts SET name = ? WHERE id = ?", arguments: [name, id])
try FieldTimestampHelper.stamp(["name"], table: "parts", rowId: id, in: db)
```

**Alternative** (cleaner but more invasive): wrap `db.execute` for synced tables in a helper that takes `SetValue(field:, value:)` and stamps automatically. Defer to review during implementation.

### ConflictResolver change

`ConflictResolver.swift` lines ~453–460 currently compare row-level `updated_at` as the per-field tiebreaker. New logic:

```swift
// Pseudocode
func mergeField(_ fieldName: String, local: Value, remote: Value,
                localRow: Row, remoteRow: Row) -> Value {
    let localTs = fieldTimestamp(fieldName, in: localRow) ?? localRow["updated_at"]
    let remoteTs = fieldTimestamp(fieldName, in: remoteRow) ?? remoteRow["updated_at"]
    return localTs > remoteTs ? local : remote
}

private func fieldTimestamp(_ field: String, in row: Row) -> String? {
    guard let json = row["_field_timestamps"] as String? else { return nil }
    return (try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)))?[field]
}
```

---

## Affected Tables (~35 synced tables)

This list must be verified against `AppDatabase+Migrations.swift` during implementation. Likely scope:

- `parts`, `part_colors`, `parts_types`, `parts_brands`, `parts_categories`
- `part_supplier_links`, `type_brand_links`, `type_color_links`, `brand_supplier_links`
- `color_brand_skus` (new, per `colors-parts-redesign.md`)
- `pricing_tiers`, `price_history`, `cost_layers`, `cost_layer_consumptions`, `company_cost_settings`
- `employees`, `certifications`, `wages`, `customers`, `general_contractors`, `contacts`
- `jobs`, `job_clock_entries`, `job_daily_reports`, `job_questionnaires`
- `notebooks`, `notebook_sections`, `notebook_entries`, `todos`
- `purchase_orders`, `po_line_items`, `jpo`, `jpo_line_items`, `receiving_sessions`
- `vehicles`, `vehicle_assignments`, `vehicle_deliveries`, `vehicle_maintenance`
- `schedules`, `dispatches`, `time_off_requests`, `shift_templates`
- `tools`, `tool_checkouts`, `tool_kits`, `tool_maintenance`
- `chat_channels`, `chat_messages`, `chat_threads`, `qa_escalations`

Tables NOT in scope: local-only tables (`_change_log`, `_conflict_log`, `_sync_state`, `company_setup_draft`).

### Affected write paths (~every service)

Each of: `PartsService`, `PricingService`, `PeopleService`, `JobsService`, `NotebooksService`, `OrdersService`, `FleetService`, `SchedulingService`, `ToolsService`, `ChatService`, `SettingsService`, etc.

Every `create*`, `update*`, `patch*` method that writes to a synced table must add a `FieldTimestampHelper.stamp(...)` call. Estimated ~200+ call sites.

---

## Rollout

### Phase 1 — Scaffolding (no behavior change)
1. Write `FieldTimestampHelper.swift`.
2. Add single migration with `ALTER TABLE ... ADD COLUMN _field_timestamps TEXT` for one pilot table (suggest `parts`).
3. Update `PartsService` create/update methods to call `stamp()`.
4. Update `ConflictResolver` to CHECK for the new column — if present, use per-field; if absent, fall back to row-level. (Backward-compatible during rollout.)
5. Test on pilot table: seed conflicting writes, verify per-field merge correctness.

### Phase 2 — Fleet-wide migration
6. Expand migration to add `_field_timestamps` to all ~35 synced tables in one pass.
7. Write a code-generation or hunt-fix script that finds every synced-table write and adds a `stamp()` call. Given the scale (~200 call sites), this is a good candidate for automation that `CLAUDE.md`'s 3-layer architecture recommends.
8. Human-review a sample of the generated edits before committing.
9. Run full test suite; add conflict-merge tests for representative tables.

### Phase 3 — Cleanup
10. Once every write path is stamped and the fallback is no longer exercised in practice, the `ConflictResolver` can drop the fallback path (tracked as a cleanup issue, not a blocker).

---

## Test Plan

1. Two-device simulated sync with conflicting same-field writes at different times → later timestamp wins.
2. Two-device sync with non-overlapping field edits on same row → both survive (this already works, verify still works after migration).
3. Pre-migration row with no `_field_timestamps` JSON → merges using row-level `updated_at` (backward compatibility).
4. Write to a field, verify `_field_timestamps` JSON updates.
5. Write to multiple fields in one transaction → verify all get the same timestamp.
6. `_conflict_log` still records both sides of every conflict (no regression).

---

## Risks

- **Performance:** Every synced write now runs an additional UPDATE. Measure on the pilot table — if >5ms overhead per write, batch the stamp into the main UPDATE via a single `UPDATE ... SET field = ?, _field_timestamps = ? WHERE id = ?` form instead of a separate statement.
- **JSON size:** `_field_timestamps` grows with the number of distinct fields. On very wide tables (20+ columns) the column could reach ~1KB per row after heavy editing. Acceptable but worth monitoring.
- **Migration safety:** Adding a nullable column is safe. No data copy, no locking issues on SQLite.

---

## Cross-References

- `docs/plans/april-2026-audit-closures.md` — parent plan.
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` lines 79, 453–460, 526 — current LWW logic.
- `docs/plans/bluetooth_sync_expanded.md` — companion sync design (LWW interacts with BT transport).
- GitHub issue `#221`.
