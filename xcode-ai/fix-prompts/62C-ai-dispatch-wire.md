# 62C — Wire AIDispatchService to AppCore
> Chain position: Standalone

## Task

The `AIDispatchService` exists in `core/Sources/WiredPartCore/Services/AIDispatchService.swift` but is never instantiated or exposed to the UI layer via `AppCore`. Wire it up so views can access it.

### Step 1: Add the property to AppCore

In `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift`, add a new service property alongside the other services (after `dailyReportGenerator`):

```swift
public private(set) var aiDispatchService: AIDispatchService?
```

### Step 2: Initialize in bootstrap()

Inside the `bootstrap()` function, find the `Task.detached` block where all other services are created (around lines 94-108). Add:

```swift
aiDispatch: AIDispatchService(db: database),
```

This goes right after `dailyReport: DailyReportGenerator(db: database),` in the tuple return.

### Step 3: Update the tuple type

The `Task.detached` block returns a tuple. You need to add `aiDispatch: AIDispatchService` to the tuple. Find where the result tuple is destructured (around lines 116-133) and add:

```swift
aiDispatchService = result.aiDispatch
```

This goes right after `dailyReportGenerator = result.dailyReport`.

### Step 4: Verify the tuple compiles

The tuple already has many fields. Make sure the new field is added to BOTH:
- The tuple construction (inside `Task.detached`)
- The tuple destructuring (the `result.xxx` assignments on MainActor)

### What the result should look like:

```swift
// In the service properties section:
public private(set) var aiDispatchService: AIDispatchService?

// In the Task.detached tuple:
aiDispatch: AIDispatchService(db: database),

// In the result assignment:
aiDispatchService = result.aiDispatch
```

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift`

## Success Criteria
- [ ] `AppCore` has a `public private(set) var aiDispatchService: AIDispatchService?` property
- [ ] The service is initialized with the database in `bootstrap()`
- [ ] The service is assigned from the result tuple after the detached task completes
- [ ] `appCore.aiDispatchService` is accessible from any view with `@EnvironmentObject var appCore: AppCore`
- [ ] Project compiles with no errors
