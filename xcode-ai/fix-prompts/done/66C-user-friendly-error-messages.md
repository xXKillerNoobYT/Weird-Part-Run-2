# 66C — User-Friendly Error Messages Everywhere

> **Chain position:** **66C** (standalone)
> **Issue:** ~165 places still show raw `error.localizedDescription` to users
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT change error handling logic — only change what string is shown to the user
2. DO NOT remove any catch blocks or error assignments
3. Every `loadError = error.localizedDescription` must become `loadError = userFriendlyError(error, context: "...")`
4. The `context` parameter must describe what the page was trying to do (e.g., "load parts", "save job", "delete employee")
5. Project must build with zero errors when done

## Context

The app has a shared `userFriendlyError(_ error: Error, context: String) -> String` function in `Weird Parts IOS/Weird Parts IOS/Shared/UserFriendlyError.swift`. It wraps raw error messages into human-readable text:

```swift
func userFriendlyError(_ error: Error, context: String = "load data") -> String {
    let raw = error.localizedDescription
    if raw.contains("no such table") {
        return "This feature isn't set up yet. Contact your admin."
    }
    if raw.contains("UNIQUE constraint") {
        return "This item already exists. Try a different name or code."
    }
    if raw.contains("FOREIGN KEY constraint") {
        return "Can't complete this action — a related item is missing."
    }
    if raw.contains("database is locked") {
        return "The database is busy. Please try again in a moment."
    }
    return "Couldn't \(context). Pull down to retry."
}
```

### Step 1: Enhance the shared function

**File:** `Weird Parts IOS/Weird Parts IOS/Shared/UserFriendlyError.swift`

Add these additional cases BEFORE the default return:

```swift
if raw.contains("disk I/O error") || raw.contains("disk full") {
    return "Storage problem. Check your device has enough space."
}
if raw.contains("connection") || raw.contains("timeout") || raw.contains("network") {
    return "Connection issue. Check your network and try again."
}
if raw.contains("not found") && !raw.contains("no such table") {
    return "Item not found. It may have been deleted."
}
```

### Step 2: Replace ALL remaining `error.localizedDescription` in Features/

Search across ALL `.swift` files in `Weird Parts IOS/Weird Parts IOS/Features/` for this pattern:

```
error.localizedDescription
```

Replace each occurrence with `userFriendlyError(error, context: "...")` where the context matches what the function was doing. Use this mapping:

| Folder | Context String |
|--------|---------------|
| Features/Parts/ | `"load parts"`, `"save part"`, `"delete part"`, `"load pricing"`, `"update pricing"` |
| Features/Orders/ | `"load orders"`, `"save order"`, `"create PO"`, `"submit order"`, `"receive shipment"` |
| Features/Jobs/ | `"load jobs"`, `"save job"`, `"load clock data"`, `"submit report"`, `"load estimate"` |
| Features/Warehouse/ | `"load inventory"`, `"save movement"`, `"load audit"`, `"save audit"`, `"load locations"` |
| Features/Fleet/ | `"load vehicles"`, `"save vehicle"`, `"load inspections"`, `"load maintenance"` |
| Features/People/ | `"load employees"`, `"save employee"`, `"load customers"`, `"load teams"`, `"load contacts"` |
| Features/Tools/ | `"load tools"`, `"save tool"`, `"load checkouts"`, `"load maintenance"` |
| Features/Scheduling/ | `"load schedule"`, `"save entry"`, `"load dispatch"`, `"load time off"` |
| Features/Reports/ | `"load report"`, `"generate report"`, `"export report"` |
| Features/Chat/ | `"load messages"`, `"send message"`, `"load channels"` |
| Features/Notebooks/ | `"load notebooks"`, `"save notebook"`, `"load templates"` |
| Features/Office/ | `"load dashboard"`, `"load approvals"`, `"save settings"` |
| Features/Dashboard/ | `"load dashboard"`, `"load daily report"`, `"scan item"` |
| Features/Settings/ | `"load settings"`, `"save settings"` |

**Be specific with the context.** If a catch block is in a `loadData()` function, use "load X". If it's in a `save()` or `create()` function, use "save X" or "create X". If it's in a `delete()` function, use "delete X".

### Step 3: Also check non-Features files

Search these additional locations for `error.localizedDescription`:
- `Weird Parts IOS/Weird Parts IOS/Auth/`
- `Weird Parts IOS/Weird Parts IOS/App/`
- `Weird Parts IOS/Weird Parts IOS/Scanning/`

For Auth files use context `"sign in"` or `"set up profile"`.
For App files use context `"start app"` or `"load data"`.
For Scanning files use context `"scan item"` or `"print label"`.

### Step 4: Verify the pattern

After replacing, do a project-wide search for `error.localizedDescription`. The ONLY places it should remain are:
1. Inside `UserFriendlyError.swift` itself (where it reads the raw message)
2. Inside logging/debug code that is NOT shown to users (e.g., `print()` calls — though those should be rare)

If any `error.localizedDescription` is assigned to a `@State` variable that displays in the UI (like `loadError`, `saveError`, `actionError`, `errorMessage`), it MUST use `userFriendlyError()`.

## Success Criteria

- [ ] `UserFriendlyError.swift` has the 3 additional cases (disk I/O, connection, not found)
- [ ] ZERO occurrences of `loadError = error.localizedDescription` in Features/
- [ ] ZERO occurrences of `saveError = error.localizedDescription` in Features/
- [ ] ZERO occurrences of `actionError = error.localizedDescription` in Features/
- [ ] ZERO occurrences of `errorMessage = error.localizedDescription` in Features/
- [ ] Every replacement uses a meaningful context string (not just "load data")
- [ ] All files that use `userFriendlyError()` can see the function (it's a global function, so no import needed)
- [ ] Project builds with zero errors

## Log Entry Template

```
## Prompt 66C — User-Friendly Error Messages
**Date:** YYYY-MM-DD
**Status:** ✅ Complete
**Files modified:** XX
**Replacements made:** XX occurrences of error.localizedDescription → userFriendlyError()
**New error cases added:** 3 (disk I/O, connection, not found)
**Remaining raw error.localizedDescription:** X (only in non-UI code)
**Build:** PASS
```
