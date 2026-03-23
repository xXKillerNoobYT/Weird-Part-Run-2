# 35C — Scheduling Pages: Remove Raw SQL + Add Error States

> **Chain position:** **35C** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

Two scheduling pages still use raw SQL and have no error states:
1. **IOSSubSchedulePage** — `import GRDB`, raw SQL, print() error, no loadError
2. **IOSWeeklyAvailabilityPage** — `import GRDB`, raw SQL, print() error, no loadError

Both need service layer migration and proper error handling.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSubSchedulePage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSWeeklyAvailabilityPage.swift`
- `core/Sources/WiredPartCore/Services/SchedulingService.swift` (add methods if missing)

## Task

### IOSSubSchedulePage
1. Remove `import GRDB`
2. Move SQL to SchedulingService methods
3. Add `@State private var loadError: String?`
4. Replace `print()` catch with `loadError = error.localizedDescription`
5. Add `ErrorStateView` display
6. Remove `#if os(iOS)` guard

### IOSWeeklyAvailabilityPage
1. Remove `import GRDB`
2. Move SQL to SchedulingService methods
3. Add `@State private var loadError: String?`
4. Replace `print()` catch with `loadError = error.localizedDescription`
5. Add `ErrorStateView` display
6. Remove `#if os(iOS)` guard
7. Remove fragile string-matching error check (`if !msg.contains("no such table")`)

## Success Criteria

- [ ] Zero `import GRDB` in scheduling UI files
- [ ] Zero raw SQL in scheduling UI files
- [ ] Both pages have loadError state with ErrorStateView
- [ ] Zero print() error logging
- [ ] Project builds with no errors
