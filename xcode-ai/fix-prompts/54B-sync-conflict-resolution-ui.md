# 54B — Sync Conflict Resolution UI

> **Chain position:** 54A → **54B** → 54C
> **Prerequisite:** 54A (sync activation)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

When two devices edit the same record offline and then sync, conflicts need resolution. The core ConflictResolver handles LWW (Last Writer Wins) with field-level merge automatically for most cases. But some conflicts need user attention — this prompt builds the UI for that.

**Files to read first:**
- `core/Sources/WiredPartCore/Sync/ConflictResolver.swift` — understand existing merge logic
- `core/Sources/WiredPartCore/Sync/SyncEngine.swift` — understand sync flow

## Task

### Step 1: Conflict notification banner

When sync detects conflicts that were auto-resolved, show a banner:

```swift
// In IOSMainView or AppCore notification:
struct SyncConflictBanner: View {
    let conflictCount: Int
    let onReview: () -> Void

    var body: some View {
        if conflictCount > 0 {
            HStack {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.orange)
                Text("\(conflictCount) sync conflicts auto-resolved")
                    .font(.caption)
                Spacer()
                Button("Review") { onReview() }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.orange.opacity(0.1))
        }
    }
}
```

### Step 2: Conflict review page

```swift
struct SyncConflictReviewPage: View {
    // Shows auto-resolved conflicts for review
    // User can accept the auto-resolution or manually pick a version

    // For each conflict:
    // - Show the field name
    // - Show "Device A value" vs "Device B value"
    // - Show which one was picked (LWW)
    // - [Accept Auto] [Use Device A] [Use Device B] [Manual Edit]
}
```

### Step 3: Notebook block conflicts (special handling)

For notebook blocks, use the AI merge system designed in the notebooks plan:
- Show both edits
- AI merges with Apple AI glow
- User can pick: AI merge, Device A, Device B, or manual rewrite

### Step 4: Sync history log

Show recent sync events in Settings → Sync:
```
Last 10 syncs:
✅ Mar 22, 4:30 PM — 12 changes sent, 8 received, 0 conflicts
✅ Mar 22, 2:15 PM — 3 changes sent, 0 received, 0 conflicts
⚠️ Mar 22, 12:00 PM — 5 changes sent, 4 received, 1 conflict (auto-resolved)
```

## Success Criteria
- [ ] Conflict banner shows when auto-resolved conflicts exist
- [ ] Conflict review page shows field-level diffs
- [ ] Accept/override options for each conflict
- [ ] Notebook block conflicts use AI merge
- [ ] Sync history log in Settings
- [ ] Build: PASS

**Wait for user confirmation before proceeding to prompt 54C.**
