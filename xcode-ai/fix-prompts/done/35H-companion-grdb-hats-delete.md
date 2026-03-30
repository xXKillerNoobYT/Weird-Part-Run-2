# 35H — Companion GRDB Removal + Hats Delete Confirmation

> **Chain position:** **35H** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

**2 Companion files still import GRDB with raw SQL:**
- CompanionAdminDashboardSheet.swift — 4 raw SQL queries in UI
- CompanionSandboxSheet.swift — multiple raw SQL blocks + 2 empty catch blocks

**1 People page missing delete confirmation:**
- IOSHatsPage.swift — swipe-to-delete with no confirmation alert. Deleting a hat is destructive (removes role + all permissions).

## Files to Fix

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CompanionAdminDashboardSheet.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CompanionSandboxSheet.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/People/IOSHatsPage.swift`

## Task

### CompanionAdminDashboardSheet
1. Remove `import GRDB`
2. Move 4 raw SQL queries to PartsService methods:
   - Manual vs auto-discovered rule counts
   - Per-user voting accuracy
   - Poll history (last 20)
   - Admin lock indicators
3. Replace `guard let db = appCore.db` with service calls
4. Fix empty catch at line ~212: set loadError

### CompanionSandboxSheet
1. Remove `import GRDB`
2. Move raw SQL (co-occurrence queries, job history) to PartsService methods
3. Fix 2 empty catch blocks (lines ~308, ~435): set appropriate error state
4. Replace `guard let db = appCore.db` with service calls

### IOSHatsPage — Delete Confirmation
Add confirmation alert before deleting a hat:
```swift
@State private var hatToDelete: HatItem?

// In swipe action:
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        hatToDelete = hat
    } label: {
        Label("Delete", systemImage: "trash")
    }
}

// Alert:
.alert("Delete Hat?", isPresented: .constant(hatToDelete != nil)) {
    Button("Cancel", role: .cancel) { hatToDelete = nil }
    Button("Delete", role: .destructive) {
        if let hat = hatToDelete {
            deleteHat(hat)
            hatToDelete = nil
        }
    }
} message: {
    Text("This will remove the '\(hatToDelete?.name ?? "")' role and all its permissions. This cannot be undone.")
}
```

## Success Criteria

- [ ] Zero `import GRDB` in Companion files
- [ ] Zero empty catch blocks in Companion files
- [ ] Hats page has delete confirmation alert
- [ ] Project builds with no errors
