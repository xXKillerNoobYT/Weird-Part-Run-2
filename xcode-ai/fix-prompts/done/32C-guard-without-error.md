# 32C — Fix Guard-Without-Error Pattern (42 Files)

> **Chain position:** **32C** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use empty `catch { }` blocks — ALWAYS set loadError
2. DO NOT use `#if os(iOS)` guards — app is iOS-only
3. ALWAYS handle `guard let service` with loadError + isLoading = false

## Instructions

Search the ENTIRE `Weird Parts IOS/` directory for this pattern:

```swift
guard let service = appCore.xxxService else { return }
```

Every occurrence that doesn't set `loadError` and `isLoading = false` must be fixed.

## Fix Pattern

**BEFORE:**
```swift
private func loadData() {
    guard let service = appCore.ordersService else { return }
    // ...
}
```

**AFTER:**
```swift
private func loadData() {
    guard let service = appCore.ordersService else {
        loadError = "Service not available"
        isLoading = false
        return
    }
    // ...
}
```

**For async functions:**
```swift
@Sendable
private func loadData() async {
    guard let service = appCore.ordersService else {
        await MainActor.run {
            loadError = "Service not available"
            isLoading = false
        }
        return
    }
    // ...
}
```

If the file doesn't have `@State private var loadError: String?`, ADD it.
If the file doesn't have `@State private var isLoading = true`, ADD it.

Search ALL `.swift` files in `Weird Parts IOS/Weird Parts IOS/Features/` recursively.

## Success Criteria

- [ ] Zero `guard let service else { return }` without error handling in entire project
- [ ] Every file with guard-let-service has `loadError` and `isLoading` states
- [ ] Project builds with no errors
