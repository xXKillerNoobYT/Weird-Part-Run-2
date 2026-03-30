# 62E — Add isTableNotFoundError Fallback to 4 Services
> Chain position: Standalone

## Task

Four services are missing the `isTableNotFoundError` guard in some of their methods. When a table doesn't exist yet (before migration runs), the app should gracefully return empty/default results instead of crashing. Three of the four services already have the helper method defined — they just don't use it consistently in all methods.

### Service 1: BreakService

**File:** `core/Sources/WiredPartCore/Services/BreakService.swift`

The `isTableNotFoundError` helper already exists (line ~407). Check EVERY public method in this file. The following methods are already guarded: `getBreakPolicy`, `getAllPolicies`, `getBreakBonuses`, `getBreakRecordsForDay`, `getActiveBreak`, `getCompanyBreakSettings`.

Check these methods — if they do raw SQL queries without a try/catch + isTableNotFoundError guard, add one:
- `savePolicy` — wraps in `db.writer.write`, should have fallback
- `createBonus` — wraps in `db.writer.write`, should have fallback
- `toggleBonus` — wraps in `db.writer.write`, should have fallback
- `endBreak` — wraps in `db.writer.write`, should have fallback
- `autoFillBreaksForDay` — wraps in `db.writer.write`, should have fallback
- `updateCompanyBreakSettings` — wraps in `db.writer.write`, should have fallback

For write methods, wrap the body in do/catch and silently return on table-not-found:
```swift
public func toggleBonus(bonusId: Int64, isEnabled: Bool) throws {
    do {
        try db.writer.write { dbConn in
            // ... existing code ...
        }
    } catch {
        if isTableNotFoundError(error) { return }
        throw error
    }
}
```

### Service 2: DailyReportGenerator

**File:** `core/Sources/WiredPartCore/Services/DailyReportGenerator.swift`

Check if `isTableNotFoundError` helper exists. If not, add it:
```swift
private func isTableNotFoundError(_ error: Error) -> Bool {
    let message = String(describing: error)
    return message.contains("no such table")
}
```

Then wrap the `generateReport` method (and any other public methods) in do/catch with the fallback.

### Service 3: AIDispatchService

**File:** `core/Sources/WiredPartCore/Services/AIDispatchService.swift`

The `isTableNotFoundError` helper already exists (line ~443). The service already uses it in `recordDispatcherChoice`, `getAvailableWorkers`, `getJobsNeedingWorkers`, `checkWorkerOnJob`, `checkWorkerJobHistory`.

Verify the `generateSuggestions` method properly propagates the guard — it calls internal methods that are already guarded, so it should be fine. But `getDispatchContext` calls `getAvailableWorkers` and `getJobsNeedingWorkers` which are guarded, so that's fine too. **This service may already be complete** — verify and skip if so.

### Service 4: JobEstimationService

**File:** `core/Sources/WiredPartCore/Services/JobEstimationService.swift`

Check if `isTableNotFoundError` helper exists. If not, add it. Then verify EVERY public method has the guard. The read methods (`getQuestionsForStage`, `getAllQuestions`) already have it. Check all write methods (`createQuestion`, `updateQuestion`, `deleteQuestion`, `saveResponse`, etc.) and add the do/catch guard where missing.

## Files to Modify

- `core/Sources/WiredPartCore/Services/BreakService.swift`
- `core/Sources/WiredPartCore/Services/DailyReportGenerator.swift`
- `core/Sources/WiredPartCore/Services/AIDispatchService.swift`
- `core/Sources/WiredPartCore/Services/JobEstimationService.swift`

## Success Criteria
- [ ] Every public method in all 4 services has isTableNotFoundError protection
- [ ] Write methods return silently (or return a default value) when the table doesn't exist
- [ ] Read methods return empty arrays/nil/default values when the table doesn't exist
- [ ] No compile errors
- [ ] The helper function `isTableNotFoundError` exists in each service
