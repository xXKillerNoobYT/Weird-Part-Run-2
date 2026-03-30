# 54D — AI-Assisted Sync Conflict Resolution

> **Chain position:** 54A → 54B → 54C → **54D**
> **Prerequisite:** 54C (full sync infrastructure)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

When two devices edit the same field offline, LWW (Last Writer Wins) handles simple cases. But some conflicts are HARD — both edits have value and blindly picking one loses important information. This is where Apple Foundation Models steps in, same pattern as the notebook block merge but applied to ALL sync conflicts.

## Task

### Step 1: Conflict Severity Classification

```swift
enum ConflictSeverity {
    case trivial      // Timestamps, sort orders — LWW is fine
    case simple       // One field changed — pick newer
    case moderate     // Multiple fields, both meaningful
    case hard         // Text merged, both edits have value — AI needed
    case critical     // Financial data, stock counts — human must decide
}

func classifyConflict(_ conflict: SyncConflict) -> ConflictSeverity {
    // Trivial: updated_at, sort_order, last_seen_at
    let trivialFields = ["updated_at", "sort_order", "last_seen_at", "sync_batch_id"]
    if trivialFields.contains(conflict.fieldName) { return .trivial }

    // Critical: financial, stock, pricing
    let criticalFields = ["qty", "stock", "cost", "price", "total", "budget",
                          "forecast_adu_30", "min_stock", "target_stock", "max_stock"]
    if criticalFields.contains(conflict.fieldName) { return .critical }

    // Hard: text content (notes, descriptions, names that were edited)
    let textFields = ["notes", "description", "content", "reason", "comment"]
    if textFields.contains(conflict.fieldName) &&
       conflict.localValue != conflict.remoteValue &&
       !conflict.localValue.isEmpty && !conflict.remoteValue.isEmpty {
        return .hard
    }

    // Simple: everything else with just one field
    if conflict.changedFields.count == 1 { return .simple }

    // Moderate: multiple fields changed on both sides
    return .moderate
}
```

### Step 2: AI Merge for Hard Conflicts

```swift
func resolveHardConflict(_ conflict: SyncConflict) async -> AIConflictResolution {
    let aiService = FoundationModelsService()

    let context: [String: String] = [
        "Entity": conflict.tableName,
        "Field": conflict.fieldName,
        "Original": conflict.baseValue,
        "Device A Edit": conflict.localValue,
        "Device A User": conflict.localUser,
        "Device A Time": conflict.localTimestamp,
        "Device B Edit": conflict.remoteValue,
        "Device B User": conflict.remoteUser,
        "Device B Time": conflict.remoteTimestamp
    ]

    let result = await aiService.generatePreFill(
        fieldType: """
            Merge two conflicting edits into one. Both users edited the same field.
            Combine both edits if possible — don't lose information from either side.
            If they contradict, include both perspectives clearly.
            Keep the result concise and natural-sounding.
            Return ONLY the merged text, nothing else.
            """,
        contextData: context
    )

    let merged = result.text ?? conflict.remoteValue // fallback to LWW

    // Generate 2 alternative merges
    let alt1 = await aiService.generatePreFill(
        fieldType: "Alternative merge: prioritize Device A's edit but include Device B's additions",
        contextData: context
    )
    let alt2 = await aiService.generatePreFill(
        fieldType: "Alternative merge: prioritize Device B's edit but include Device A's additions",
        contextData: context
    )

    return AIConflictResolution(
        original: conflict.baseValue,
        deviceAEdit: conflict.localValue,
        deviceBEdit: conflict.remoteValue,
        aiMerge: merged,
        aiAlternative1: alt1.text ?? conflict.localValue,
        aiAlternative2: alt2.text ?? conflict.remoteValue,
        deviceAUser: conflict.localUser,
        deviceBUser: conflict.remoteUser
    )
}
```

### Step 3: Conflict Resolution UI (with AI glow)

```swift
struct AIConflictResolutionView: View {
    let resolution: AIConflictResolution
    let onResolve: (String) -> Void
    @State private var showAllOptions = false
    @State private var customText = ""
    @State private var showCustomEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // AI Merged version (with glow)
            VStack(alignment: .leading, spacing: 4) {
                Label("AI Merged", systemImage: "sparkles")
                    .font(.caption.bold())
                    .foregroundStyle(.purple)

                Text(resolution.aiMerge)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.purple.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.purple.opacity(0.3), lineWidth: 1.5)
                            )
                    )
                    // Apple AI glow effect
                    .shadow(color: .purple.opacity(0.2), radius: 8)

                Button("Use AI Merge") { onResolve(resolution.aiMerge) }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)
            }

            Divider()

            // Show original edits
            Button { showAllOptions.toggle() } label: {
                HStack {
                    Text("See all options")
                    Image(systemName: showAllOptions ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
            }

            if showAllOptions {
                // Original
                conflictOption(
                    label: "Original (before edits)",
                    text: resolution.original,
                    icon: "clock.arrow.circlepath",
                    color: .secondary
                )

                // Device A
                conflictOption(
                    label: "\(resolution.deviceAUser)'s edit",
                    text: resolution.deviceAEdit,
                    icon: "iphone",
                    color: .blue
                )

                // Device B
                conflictOption(
                    label: "\(resolution.deviceBUser)'s edit",
                    text: resolution.deviceBEdit,
                    icon: "iphone",
                    color: .orange
                )

                // AI Alternative 1
                conflictOption(
                    label: "AI Alt: \(resolution.deviceAUser) priority",
                    text: resolution.aiAlternative1,
                    icon: "sparkles",
                    color: .purple.opacity(0.7)
                )

                // AI Alternative 2
                conflictOption(
                    label: "AI Alt: \(resolution.deviceBUser) priority",
                    text: resolution.aiAlternative2,
                    icon: "sparkles",
                    color: .purple.opacity(0.7)
                )

                // Manual rewrite
                Button {
                    customText = resolution.aiMerge
                    showCustomEditor = true
                } label: {
                    Label("Write my own", systemImage: "pencil")
                }
                .font(.caption)

                if showCustomEditor {
                    TextEditor(text: $customText)
                        .frame(height: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))

                    Button("Use My Version") { onResolve(customText) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }

    func conflictOption(label: String, text: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.05)))

            Button("Use This") { onResolve(text) }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
    }
}
```

### Step 4: Critical Conflicts — Human Must Decide

```swift
// Stock counts, prices, financial data — AI CANNOT auto-resolve
// Show both values side by side, user picks

struct CriticalConflictView: View {
    let conflict: SyncConflict

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Manual Resolution Required")
                    .font(.headline)
            }

            Text("Financial/inventory data conflicts must be resolved manually.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                VStack {
                    Text(conflict.localUser).font(.caption.bold())
                    Text(conflict.localValue).font(.title2.monospaced())
                    Text(conflict.localTimestamp).font(.caption2)
                    Button("Use This") { /* resolve with local */ }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack {
                    Text(conflict.remoteUser).font(.caption.bold())
                    Text(conflict.remoteValue).font(.title2.monospaced())
                    Text(conflict.remoteTimestamp).font(.caption2)
                    Button("Use This") { /* resolve with remote */ }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }

            Text("Tip: Check the physical count if this is a stock discrepancy.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Step 5: Auto-Resolution Pipeline

```swift
func resolveAllConflicts(_ conflicts: [SyncConflict]) async -> [ResolvedConflict] {
    var resolved: [ResolvedConflict] = []

    for conflict in conflicts {
        let severity = classifyConflict(conflict)

        switch severity {
        case .trivial, .simple:
            // LWW — auto-resolve, no user action needed
            resolved.append(ResolvedConflict(
                conflict: conflict,
                resolution: conflict.remoteValue, // newer wins
                method: .automatic,
                needsReview: false
            ))

        case .moderate:
            // LWW but flag for review
            resolved.append(ResolvedConflict(
                conflict: conflict,
                resolution: conflict.remoteValue,
                method: .automatic,
                needsReview: true // show in review banner
            ))

        case .hard:
            // AI merge
            let aiResult = await resolveHardConflict(conflict)
            resolved.append(ResolvedConflict(
                conflict: conflict,
                resolution: aiResult.aiMerge,
                method: .aiMerge(aiResult),
                needsReview: true // show with AI glow for user to confirm
            ))

        case .critical:
            // Cannot auto-resolve — queue for human
            resolved.append(ResolvedConflict(
                conflict: conflict,
                resolution: nil, // not resolved yet
                method: .humanRequired,
                needsReview: true
            ))
        }
    }

    return resolved
}
```

## Important Notes

- Trivial/simple conflicts: auto-resolve silently (LWW)
- Moderate conflicts: auto-resolve but show in review banner
- Hard conflicts (text): AI merges with glow effect, user confirms
- Critical conflicts (numbers/money): NEVER auto-resolve, human must decide
- AI uses Foundation Models on-device — no internet needed for conflict resolution
- The notebook block merge system uses this same pipeline
- All resolutions logged for audit trail
- If AI is unavailable, hard conflicts fall back to "human must decide"

## Success Criteria

- [ ] Conflict severity classification (5 levels)
- [ ] AI merge for hard text conflicts
- [ ] AI glow effect on merged content
- [ ] 5 options shown: AI merge, AI alt 1, AI alt 2, Device A, Device B
- [ ] Manual rewrite option
- [ ] Critical conflicts require human decision (no auto)
- [ ] Auto-resolution pipeline handles all severity levels
- [ ] Resolution audit trail logged
- [ ] Works without internet (on-device AI)
- [ ] Build: PASS

## Log Entry

```
## Prompt 54D Results (YYYY-MM-DD)
- 5-level conflict classification
- AI merge with glow for hard text conflicts
- Critical conflicts blocked from auto-resolve
- Full pipeline: trivial→simple→moderate→hard→critical
- Build: [PASS/FAIL]
```

**Bluetooth sync backbone is now complete with AI-assisted conflict resolution.**
