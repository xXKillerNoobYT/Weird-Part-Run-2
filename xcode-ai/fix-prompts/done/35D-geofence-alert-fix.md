# 35D — GeofenceAlertView: Remove GRDB + Fix Error Handling

> **Chain position:** **35D** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

GeofenceAlertView.swift (in App/) imports GRDB and runs raw SQL to load active jobs. It also has silent error handling — clock-in/clock-out failures show no feedback to the user.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/App/GeofenceAlertView.swift`

## Task

### 1. Remove `import GRDB` and raw SQL
Replace the raw SQL job query (lines ~253-267) with a JobsService call:
```swift
// BEFORE: raw SQL with db.writer.read
// AFTER:
guard let service = appCore.jobsService else { return }
let jobs = try service.listJobs(status: "active", limit: 100)
```

### 2. Fix silent error handling
- `handleResponse()` catch block: show error to user via alert or banner
- `loadActiveJobs()` print() catch: add `@State private var loadError: String?` and display it
- `activeEntryId` computed property: replace `try?` with proper error handling

### 3. Remove platform guards if any exist

## Success Criteria

- [ ] `import GRDB` removed
- [ ] Raw SQL replaced with JobsService call
- [ ] Clock-in/clock-out errors visible to user
- [ ] Job loading errors visible to user
- [ ] Project builds with no errors
