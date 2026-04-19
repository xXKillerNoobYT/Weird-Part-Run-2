# Performance Review Tracker

> Auto-maintained by `performance-review` SKILL.md body (invoked via `/auto-go` C9 check).

## Bundle Size Baseline

*(Not yet measured — Tauri frontend bundle; pending first clean-run baseline.)*

## Latest Run

**Date:** 2026-04-19
**Area:** chat
**Iteration:** AUTO GO day 2 iter 7 (C9)

### Files scanned (9 changed chat files, last 7 days)

### Phase results
- **B SQL patterns:** ✅ CLEAN — `getMessages` has `LIMIT ?` (default 50); `SELECT *` only in `getSupplierBridge` which is a single-row `fetchOne` with `WHERE channel_id = ?`
- **C N+1 patterns:** ✅ CLEAN — `getAttachmentsForMessages` takes `[Int64]` and uses `IN (?)` batch query; no per-message loops
- **D Heavy `.onAppear`:** ✅ CLEAN — all loads via `.task` modifier
- **E Main thread blocks:** ✅ CLEAN — no `DispatchQueue.main.sync` or synchronous FileManager in UI paths
- **H Memory leaks:** ✅ CLEAN — SwiftUI structs, no `@escaping` closures needing `[weak self]`

### Findings
**0 findings** — chat area passes performance review.

### Noted
- `IOSMessageThreadView` attachment picker uses `.onChange(of: searchText) { loadData() }` — intentional (search fires DB query for parts/POs/jobs by name). No change needed.

---

## Run: 2026-04-18 — parts area

### Files scanned (15 changed parts files, last 7 days)
- `core/Sources/WiredPartCore/Services/PartsService.swift`
- `Weird Parts IOS/.../Features/Parts/` — 14 iOS files

### Phase results

- **Phase B — SELECT * / unbounded fetchAll:** ✅ CLEAN
  - 5 matches on `SELECT * FROM parts`, all either single-row lookups by id (`WHERE id = ?` — safe) or paginated (`LIMIT ? OFFSET ?` — safe). Unbounded `findAll` concern is tracked at framework level via [#223](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/223) Phase-2 pagination cutover audit, not a parts-specific regression.
- **Phase C — N+1 queries:** ✅ CLEAN
  - No `for item in items { try db.fetchOne(..., item.id) }` patterns. JOIN/IN-clause strategies used throughout.
- **Phase D — Heavy `.onAppear`:** ✅ CLEAN
  - 12 `.onAppear` matches across parts iOS pages. All are NotificationCenter posts or in-memory state updates (`postXxxContext()`, `populateFromEditingRule()`). No synchronous DB work on appearance. Actual data loads use `.task` / `Task { }` / `.refreshable` idioms.
- **Phase E — Main-thread blocks:** ✅ CLEAN
  - 1 `FileManager.default.urls(for: .documentDirectory, ...)` call in PartsImportExportPage:440 — this is a cached path lookup, effectively free. No real `DispatchQueue.main.sync` hazards.
- **Phase H — `@escaping` without `[weak self]`:** ✅ CLEAN
  - 2 matches, both SwiftUI view-parameter closures (`onChange`, `action`) where SwiftUI's value-type struct-based views don't create retain cycles. `[weak self]` would be a no-op here.

### Findings
**0 critical, 0 high, 0 medium, 0 low** — parts area passes performance review.

### Noted (not findings)
- Framework-level pagination cutover at [#227](https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/227) still pending Phase 2/3. When that lands, re-scan parts to verify call-site classifications.

---

## 2026-04-19 — Jobs area (AUTO GO day 2 iter 3)

**Files scanned (6 files):**
- `core/Sources/WiredPartCore/Services/JobsService.swift`
- `core/Sources/WiredPartCore/Services/JobEstimationService.swift`
- `Weird Parts IOS/.../Features/Jobs/` — IOSClockPage, IOSJobDetailTabView, JobsListPage, IOSEstimationQuestionnairePage

### Phase results

- **Phase B — SELECT * / unbounded:** ✅ CLEAN — 0 `SELECT *`; all 8 SELECTs on `jobs` table bounded by `WHERE id=?`, `LIMIT`, or `COUNT`.
- **Phase C — N+1 queries:** ✅ CLEAN — The 1 loop-regex hit was a doc-comment false positive.
- **Phase D — Heavy `.onAppear`:** ✅ CLEAN — 2 `.onAppear` (IOSClockPage:172, JobsListPage:136) — both are pure NotificationCenter posts. Actual data loads via `.task { loadJobs() }` or explicit `loadData()` in `.onChange` handlers.
- **Phase E — Main-thread blocks:** ✅ CLEAN — 28 MainActor/DispatchQueue.main matches in IOSClockPage (timer-driven UI updates, expected) + 1 in IOSJobDetailTabView (single post).
- **Phase H — `@escaping` without `[weak self]`:** ✅ CLEAN — 1 hit (IOSJobDetailTabView:1234 `quickAction`) — SwiftUI view-builder parameter, not retained.

### Findings
**0 critical, 0 high, 0 medium, 0 low** — jobs area passes performance review.

## Findings Log

*(Empty — no findings to log this run.)*
