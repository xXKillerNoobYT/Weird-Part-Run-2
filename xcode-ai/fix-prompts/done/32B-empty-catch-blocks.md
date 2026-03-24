# 32B — Fix Empty Catch Blocks (Critical Error Silencing)

> **Chain position:** **32B** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use empty `catch { }` blocks — ALWAYS set loadError
2. DO NOT use `catch { print(...) }` — use @State loadError instead
3. DO NOT use `#if os(iOS)` guards — app is iOS-only
4. DO NOT use `showXxx` Bool for sheets — use ActiveSheet enum
5. ALWAYS handle `guard let service` with loadError + isLoading = false

## Instructions

Read ALL files listed below. Fix EVERY empty catch block and every `catch { print() }` block. Replace them with proper error state handling.

## Files to Fix

Search the ENTIRE `Weird Parts IOS/` directory for these patterns:
1. `catch { }` — completely empty catch blocks
2. `catch { print(` — catch blocks that only print
3. `catch {` followed by only a `print()` or `debugPrint()` call

## Fix Pattern

**BEFORE (empty catch):**
```swift
do {
    let jobs = try service.listJobs(status: "active")
    activeJobs = jobs
} catch { }
```

**AFTER:**
```swift
do {
    let jobs = try service.listJobs(status: "active")
    activeJobs = jobs
} catch {
    loadError = error.localizedDescription
    isLoading = false
}
```

**BEFORE (print-only catch):**
```swift
} catch {
    print("[PageName] Load error: \(error)")
}
```

**AFTER:**
```swift
} catch {
    loadError = error.localizedDescription
    isLoading = false
}
```

If the file doesn't have a `loadError` state variable, ADD one:
```swift
@State private var loadError: String?
```

And add the error display in the body (if not already present):
```swift
if let error = loadError {
    ErrorStateView(message: error) { Task { await loadData() } }
}
```

For catch blocks in non-loading contexts (like save/delete operations), use an `actionError` or inline alert instead:
```swift
@State private var actionError: String?

// In the action:
} catch {
    actionError = error.localizedDescription
}

// In the body:
.alert("Error", isPresented: .constant(actionError != nil)) {
    Button("OK") { actionError = nil }
} message: {
    Text(actionError ?? "")
}
```

## Known Affected Files (from audit)

1. `IOSJPOsPage.swift` — 2 empty catches (lines ~363, ~373)
2. `IOSJPOCreationPage.swift` — 3 empty catches (lines ~765, ~891, ~901)
3. `IOSOrderStagingPage.swift` — 1 empty catch (line ~332)
4. `PartHistoryView.swift` — 1 empty catch (line ~140)
5. `DashboardView.swift` — 1 print-only catch (line ~630)

BUT: Search the ENTIRE codebase for ANY others. Fix ALL of them, not just these 5.

## Success Criteria

- [ ] Zero empty `catch { }` blocks in the entire project
- [ ] Zero `catch { print() }` blocks in the entire project
- [ ] Every catch block sets a visible error state (@State var)
- [ ] Every file with error catches has an ErrorStateView or alert
- [ ] Project builds with no errors

## Log Entry

```
## Prompt 32B Results (YYYY-MM-DD)
- Fixed X empty catch blocks across Y files
- Fixed X print-only catch blocks across Y files
- Added loadError/actionError state to Z files
- Build: [PASS/FAIL]
```
