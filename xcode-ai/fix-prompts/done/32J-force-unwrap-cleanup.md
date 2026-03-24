# 32J — Force Unwrap Cleanup + DispatchQueue Modernization

> **Chain position:** **32J** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

### Part 1: Fix Force Unwraps

Search for `try!` and `!` force unwraps in non-test Swift files:

**Known locations:**
1. `core/Sources/WiredPartCore/Services/PartsService.swift` line ~2638:
   - `let part = try! Part(row: row)` → `guard let part = try? Part(row: row) else { continue }`

2. `core/Sources/WiredPartCore/Services/ChatService.swift` lines ~270, ~595:
   - `StatementArguments(args as [Any])!` → use proper typed arguments or guard

Search for any others in `core/Sources/` and `Weird Parts IOS/`.

### Part 2: Replace DispatchQueue.main.asyncAfter

Search for `DispatchQueue.main.asyncAfter` in ALL files. Replace with modern async:

**BEFORE:**
```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    doSomething()
}
```

**AFTER:**
```swift
Task {
    try? await Task.sleep(nanoseconds: 1_000_000_000)
    await MainActor.run {
        doSomething()
    }
}
```

**Known files:** IOSJPOCreationPage, IOSAIAssistantPanel, IOSDataExportPage, IOSBackupsPage, IOSUpdateProtocolPage, IOSAIConfigPage

## Success Criteria

- [ ] Zero `try!` in non-test code
- [ ] Zero force-unwrap `!` on optionals in non-test code (except @IBOutlet which don't exist in SwiftUI)
- [ ] Zero `DispatchQueue.main.asyncAfter` — all replaced with async/await
- [ ] Project builds with no errors
