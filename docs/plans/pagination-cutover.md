# Pagination Cutover — `BaseRepository.findAll()` Defaults + Cursor-Based Migration

> **Status:** Design approved 2026-04-14. Phase 1 ready to ship.
> **Parent plan:** `docs/plans/april-2026-audit-closures.md` (#223/#227 closure)
> **Supersedes:** `docs/dev-qa.md` Q14 (now processed).
> **GitHub Issues:** #223, #227

---

## Context

`core/Sources/WiredPartCore/Database/BaseRepository.swift` lines ~36–51 defines the generic `findAll()` used by every repository. It already accepts optional `limit` and `offset` parameters — but **when neither is passed, it loads the entire table into memory.**

Real-world pain: a dev calling `PartsService.listAll()` without thought pulls thousands of parts rows into a struct array, then passes that to a SwiftUI `ForEach`. Result: app freezes on catalog load.

The owner decision (Q14, "Option C B-biased") is to:
1. Ship a default `LIMIT 500` stabilizer immediately (protects against the worst failures).
2. Audit every call site in parallel (produces an inventory document of what each call site actually needs).
3. Migrate to proper cursor pagination in ONE clean pass once the audit is done.

Rationale: the band-aid buys time for the audit so the cursor migration lands right the first time — not a half-migration that leaves some callers on the band-aid forever.

---

## Phase 1 — Default Limit + Unlimited Override

### Status: ✅ Code already in working tree (2026-04-14)

Verification on 2026-04-14 found `BaseRepository.findAll()` already had `limit: Int? = 1000` with a comment referencing fix #223 — earlier hunt-fix-verify had shipped this ahead of owner ratification. Implementation detail differs from the plan's original proposal: uses `limit: Int? = 1000` with `nil` meaning unlimited (not a separate `unlimited: Bool` flag). Both APIs achieve the same end; the current shape is simpler and idiomatic Swift. The Q&A answer today formalizes this phase's design; the next commit captures the code.

**Note:** default is 1000 rows, not the 500 originally proposed. 1000 is generous enough that most real UI lists fit unclipped while still blocking catastrophic unbounded scans. No change needed.

### Change

`core/Sources/WiredPartCore/Database/BaseRepository.swift`:

```swift
// BEFORE (simplified)
public func findAll(limit: Int? = nil, offset: Int? = nil) throws -> [T] {
    // ... builds SQL, applies limit/offset only if provided
}

// AFTER
public static let defaultLimit: Int = 500

public func findAll(
    limit: Int? = nil,
    offset: Int? = nil,
    unlimited: Bool = false
) throws -> [T] {
    let effectiveLimit: Int? = unlimited ? nil : (limit ?? Self.defaultLimit)
    // ... existing SQL builder uses effectiveLimit
}
```

### Semantics

- **Default call:** `repo.findAll()` → returns up to 500 rows. Was: all rows.
- **Explicit limit:** `repo.findAll(limit: 50)` → returns up to 50 rows. No change.
- **Unlimited override:** `repo.findAll(unlimited: true)` → returns all rows. Use when the caller has a genuine need (export, migration, scan).
- **Conflicting args:** `unlimited: true` overrides any `limit:` passed alongside (documented in docstring).

### Logging

Add a `os_log` warning when `unlimited: true` is used in a non-test/non-migration context. Every use of `unlimited: true` should eventually be justified in Phase 2's audit doc or converted to pagination in Phase 3.

### Testing

- Unit test: `repo.findAll()` returns at most 500 rows even when table has 1000+.
- Unit test: `repo.findAll(limit: 50)` returns at most 50.
- Unit test: `repo.findAll(unlimited: true)` returns all rows.
- Smoke: open Parts Catalog with seed DB containing 1000+ parts — does not freeze.

### Call sites that break

Any caller that previously relied on `findAll()` returning everything will now silently truncate at 500. Mitigation:

- Phase 2 audit is the systemic mitigation.
- Short-term: known heavy callers that NEED all rows (exports, batch sync) get an explicit `unlimited: true` added in the same commit that ships the default-limit change. Grep for: `findAll()` without `limit:` in `Services/` and assess.

---

## Phase 2 — Call-Site Audit (PARALLEL, NO CODE CHANGE)

### Output

A new tracking doc `docs/pagination-audit.md` with this format:

```markdown
| Caller | Method | Current state | Needs |
|---|---|---|---|
| PartsService.listAllCatalog | findAll() | unbounded | cursor pagination (UI = catalog with lazy load) |
| PartsService.exportAllParts | findAll() | unbounded | unlimited: true — export genuinely needs all |
| PartsCatalogPage | via listAllCatalog | displays in Form | lazy load via cursor |
| BadgeCountService.getUnreadCount | findAll(filter) | ~small result set | no change — filter narrows |
| ... | | | |
```

### Audit protocol

For each service method that returns a list:
1. Read the method and its callers.
2. Classify:
   - **"Already bounded"** → filter or known-small result. No change needed.
   - **"Needs unlimited"** → export, migration, full-scan. Add `unlimited: true` with a comment explaining why.
   - **"Needs cursor pagination"** → displayed in UI, potentially large. Mark for Phase 3.
3. Record in the audit doc.

Time estimate: ~2–3 days of focused work across ~150 methods.

---

## Phase 3 — Cursor Pagination Cutover (AFTER AUDIT)

### API design

Add to `BaseRepository`:

```swift
public struct Cursor: Codable {
    public let lastId: Int64           // ID of the last row in the previous page
    public let sortDirection: SortDir
    public let pageSize: Int
}

public enum SortDir: String, Codable { case ascending, descending }

public struct Page<T> {
    public let rows: [T]
    public let nextCursor: Cursor?     // nil if at end
}

public func findPage(
    cursor: Cursor? = nil,
    pageSize: Int = 50,
    sortDirection: SortDir = .ascending
) throws -> Page<T> {
    // Cursor-based: WHERE id > ? (or < ?) ORDER BY id ASC/DESC LIMIT ?
}
```

Uses keyset pagination (not offset) — stable under insertions, O(log n) per page, no "page 500 is slow" problem.

### Migration of marked call sites

For each call site marked "Needs cursor pagination" in Phase 2:
1. Rewrite service method to return `Page<T>` instead of `[T]`.
2. Update UI caller to accumulate rows + request next page on scroll.
3. Test: infinite scroll works, pull-to-refresh resets, no duplicate rows across pages.

### Removal of `unlimited: true`

After Phase 3, review every remaining `unlimited: true`. If a call site can use cursor pagination instead, convert. If not (genuine export/scan need), leave it explicit + commented.

---

## Rollout

| Phase | Timing | Closes |
|---|---|---|
| Phase 1 (default limit + unlimited override) | This week | First half of #223/#227 |
| Phase 2 (audit doc) | 2–3 day parallel task | None directly — produces artifact |
| Phase 3 (cursor cutover for marked call sites) | After audit complete | Second half of #223/#227 |

---

## Test Plan

### Phase 1
1. `repo.findAll()` returns ≤ 500 rows.
2. `repo.findAll(unlimited: true)` returns all rows.
3. App still boots; catalog page loads (truncated, but no freeze).
4. All existing passing tests still pass.

### Phase 3 (per-caller, post-cutover)
5. Infinite scroll requests subsequent pages as user scrolls.
6. Inserting a new row during pagination does not create duplicate or skipped rows (keyset-stability).
7. Pull-to-refresh resets to page 1.
8. `nextCursor == nil` at end of data; UI stops requesting.

---

## Risks

- **Silent truncation (Phase 1).** Call sites assuming full-table return now get 500 silently. Mitigation: Phase 2 audit + `os_log` warning on `unlimited: true` use.
- **API churn (Phase 3).** Every UI caller using a list-returning service method gets a signature change. Mitigation: batch the changes per-module so each commit is reviewable.
- **Cursor serialization.** `Cursor` must encode/decode cleanly for UI state restoration. Mitigation: Codable conformance + unit tests.

---

## Cross-References

- `docs/plans/april-2026-audit-closures.md` — parent plan.
- `core/Sources/WiredPartCore/Database/BaseRepository.swift` — the file being changed.
- GitHub issues `#223`, `#227`.
