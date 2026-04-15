# April 2026 Audit — Architectural Closures

> **Status:** Design approved 2026-04-14. Implementation pending.
> **Supersedes:** `docs/dev-qa.md` Q12–Q14 (now processed).
> **GitHub Issues:** #221, #223, #224, #227
> **Pipeline context:** April 2026 full program audit surfaced 4 issues needing owner design calls (as opposed to straight bug fixes). All 4 decisions captured here; two of them earn their own dedicated sub-plans due to blast radius.

---

## Context

The April 2026 audit (run by the usability + hunt-fix scanners) closed ~40 clear bugs directly but flagged 4 issues where multiple solutions had real trade-offs requiring owner input. Those 4 decisions were posed as Q12–Q14 in `docs/dev-qa.md` and answered on 2026-04-14.

This document is the umbrella closure plan. Two of the three decisions are big enough to warrant dedicated sub-plans (`sync-field-timestamps-upgrade.md`, `pagination-cutover.md`); those are referenced below. The ADU change is small enough to live here in full.

---

## Decision 1 — #224 Forecasting ADU: Exclude Transfer Movements

### Status: ✅ Code already in working tree (2026-04-14)

Verification on 2026-04-14 found the filter change was already applied in the uncommitted working tree — an earlier hunt-fix-verify run had landed it ahead of owner ratification. The Q&A answer today formalizes the decision; the next commit captures the code. `git diff` on `PartsService.swift` shows the change + two additional related ADU queries (per-location consumption) receiving the same fix.

### What's broken
`PartsService.swift` lines ~3082–3165 compute Average Daily Usage (ADU) by summing movement rows matching types `('consume', 'transfer', 'return_to_supplier')` over 30-day and 90-day windows. Counting `transfer` inflates ADU whenever inventory is moved between locations (warehouse → van, van → job, warehouse → warehouse). False demand signal → false reorder alerts → wasted POs.

### Fix
Remove `'transfer'` from the filter. Only `'consume'` (real demand — installed/used on a job) and `'return_to_supplier'` (effectively negative demand) count.

### Exact code change
`core/Sources/WiredPartCore/Services/PartsService.swift` (ADU calculation block, lines ~3099 and ~3106):

```swift
// BEFORE
WHERE m.movement_type IN ('consume', 'transfer', 'return_to_supplier')

// AFTER
WHERE m.movement_type IN ('consume', 'return_to_supplier')
```

Occurs in both the 30-day and 90-day query blocks. Two-line change.

### Impact
- No schema change, no data migration.
- Next ADU recalculation picks up the cleaner formula automatically.
- Existing `parts.forecast_adu_30` / `parts.forecast_adu_90` values are overwritten on next run — no stale-data cleanup needed.
- Forecasting page and reorder alert thresholds across Parts Catalog instantly reflect real demand.

### Test plan
1. Seed part X with 100 qty in location A.
2. Transfer 50 qty from location A to location B.
3. Call `PartsService.recalculateForecastMetrics(partId:)` for X.
4. Verify `forecast_adu_30` for X is 0 (no consume movements), not ~1.67 (50/30).
5. Consume 30 qty from location B over 10 days (3 per day).
6. Verify `forecast_adu_30` ≈ 1.0 (30 qty / 30 days), transfers still excluded.

### GitHub issue
- `#224` — close after fix lands with comment: "ADU filter updated to exclude transfers. Two-line change in PartsService.swift. Plan: `docs/plans/april-2026-audit-closures.md`."

---

## Decision 2 — #221 LWW Conflict Resolution: Per-Field Timestamps

Earns its own sub-plan due to blast radius (~35 synced tables + migration + every service's write path).

**See:** `docs/plans/sync-field-timestamps-upgrade.md`

Summary: current `ConflictResolver` is field-level merge but tied to row-level `updated_at`. Upgrade adds `_field_timestamps TEXT` JSON column to every synced table, updates all write paths to stamp the touched field, and changes `ConflictResolver` to consult the per-field column. Eliminates same-field-same-row data loss when devices make batched edits.

---

## Decision 3 — #223/#227 Pagination: Phased Cutover

Earns its own sub-plan due to call-site breadth (every service method returning a list).

**See:** `docs/plans/pagination-cutover.md`

Summary: phased — (1) ship `LIMIT 500` default on `BaseRepository.findAll()` with `unlimited: true` override immediately to stop memory issues, (2) audit every call site and document whether it needs pagination, unlimited, or already has it, (3) one clean cutover to proper cursor-based pagination once audit is complete.

---

## Rollout Order

1. **First (ship immediately, cheap):** ADU fix. Two-line change. No schema. Lands in the next commit. Closes `#224`.
2. **Second (ship this week, stabilizer):** Pagination Phase 1 — `LIMIT 500` default. See `pagination-cutover.md`. Closes first part of `#223/#227`.
3. **Third (parallel, ongoing):** Pagination Phase 2 — call-site audit. Doesn't land code yet, produces an inventory document.
4. **Fourth (1–2 week project):** LWW per-field timestamps. See `sync-field-timestamps-upgrade.md`. Closes `#221`.
5. **Fifth (after audit complete):** Pagination Phase 3 — cursor cutover. Closes second part of `#223/#227`.

---

## Verification

- `#224`: Forecasting page shows unchanged ADU when transfers occur; ADU updates only when consumption happens.
- `#221`: Two devices edit the same row's same field within seconds of each other — both writes visible with the later timestamp winning; neither device loses data for other-field edits.
- `#223/#227`: `BaseRepository.findAll()` returns at most 500 rows by default; callers that pass `unlimited: true` still receive full results; cursor pagination callers navigate forward/back correctly.

---

## Cross-References

- `docs/plans/sync-field-timestamps-upgrade.md` — full #221 design.
- `docs/plans/pagination-cutover.md` — full #223/#227 design.
- `core/Sources/WiredPartCore/Services/PartsService.swift` — ADU calculation.
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` — LWW logic.
- `core/Sources/WiredPartCore/Database/BaseRepository.swift` — pagination entry point.
- GitHub issues: `#221`, `#223`, `#224`, `#227`.
