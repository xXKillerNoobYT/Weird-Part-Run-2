# 64F — AI Dispatch: Surface Full Suggestion Flow in Short-Term Pipeline

> **Chain position:** After 64E, before 64G
> **Priority:** MEDIUM — AI dispatch exists in core but the UI doesn't show Apply/Dismiss/Record choices
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

`AIDispatchService` exists in core and is wired into `AppCore` (property + bootstrap). The `IOSShortTermPipelinePage` already calls `generateSuggestions()` and displays results in a sheet. However:

1. The sheet has no "Apply" button — users can view suggestions but cannot act on them
2. There is no "Dismiss" action that records the choice
3. `recordDispatcherChoice()` is never called
4. The error path silently swallows failures (`catch { aiSuggestions = [] }`)

**Read these files first:**
- `Features/Scheduling/IOSShortTermPipelinePage.swift` — current AI suggestions sheet (~line 354)
- `core/Sources/WiredPartCore/Services/AIDispatchService.swift` — `generateSuggestions()`, `recordDispatcherChoice()`, result types

## Context

The `AIDispatchService` has:
- `generateSuggestions(date:) throws -> [DispatchSuggestion]` — returns up to 3 ranked options
- `recordDispatcherChoice(date:, chosenRank:, wasModified:) throws` — logs which option the dispatcher picked (for learning)
- `DispatchSuggestion` has: `id`, `rank`, `assignments: [SuggestedAssignment]`, `totalPoints`, `reasoning: [ScoringFactor]`

The existing sheet shows suggestions in a list with reasoning disclosure groups. It needs Apply and Dismiss actions.

## Task

### Step 1: Fix the error path in `loadAISuggestions()`

Change:
```swift
} catch {
    aiSuggestions = []
}
```

To:
```swift
} catch {
    aiSuggestions = []
    loadError = userFriendlyError(error, context: "generate AI suggestions")
}
```

### Step 2: Add Apply and Dismiss buttons to each suggestion

In the `aiSuggestionsSheet` view builder, add action buttons to each suggestion section. After the reasoning DisclosureGroup, add:

```swift
HStack(spacing: 12) {
    Button {
        applyAISuggestion(suggestion)
    } label: {
        Label("Apply This Plan", systemImage: "checkmark.circle.fill")
            .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .tint(.green)
}
.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
```

### Step 3: Add a Dismiss button at the bottom of the sheet

After the ForEach of suggestions, add a section with a dismiss-and-record action:

```swift
Section {
    Button(role: .destructive) {
        dismissAISuggestions()
    } label: {
        Label("Dismiss All Suggestions", systemImage: "xmark.circle")
            .frame(maxWidth: .infinity)
    }
}
```

### Step 4: Implement `applyAISuggestion()`

Create this method. It should:
1. Record the choice via `AIDispatchService.recordDispatcherChoice(date:, chosenRank:, wasModified: false)`
2. Apply the assignments by calling the scheduling service to create dispatch entries for each assignment
3. Close the sheet
4. Reload data

```swift
private func applyAISuggestion(_ suggestion: AIDispatchService.DispatchSuggestion) {
    guard let aiService = appCore.aiDispatchService else { return }
    guard let schedService = appCore.schedulingService else { return }

    do {
        // Record the dispatcher's choice for AI learning
        try aiService.recordDispatcherChoice(
            date: todayString,
            chosenRank: suggestion.rank,
            wasModified: false
        )

        // Apply each assignment
        for assignment in suggestion.assignments {
            try schedService.createDispatchEntry(
                jobId: assignment.jobId,
                employeeId: assignment.employeeId,
                date: todayString,
                timeSlot: assignment.timeSlot,
                source: "ai_dispatch"
            )
        }

        activeSheet = nil
        loadData()
    } catch {
        loadError = userFriendlyError(error, context: "apply AI suggestion")
    }
}
```

**Note:** If `schedulingService.createDispatchEntry()` does not exist with these exact parameters, find the closest method that creates a dispatch/schedule assignment and use that instead. Check the SchedulingService for available methods.

### Step 5: Implement `dismissAISuggestions()`

```swift
private func dismissAISuggestions() {
    // Record that the dispatcher dismissed all suggestions (rank 0 = none chosen)
    if let aiService = appCore.aiDispatchService {
        try? aiService.recordDispatcherChoice(
            date: todayString,
            chosenRank: 0,
            wasModified: false
        )
    }
    activeSheet = nil
}
```

### Step 6: Add a toolbar Done button to the suggestions sheet

Wrap the suggestions sheet content in a NavigationStack (if not already) with a Done/Close toolbar button so users can dismiss without recording a choice:

```swift
.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Close") { activeSheet = nil }
    }
}
```

## Success Criteria

- [ ] AI suggestions sheet shows "Apply This Plan" button on each suggestion
- [ ] Applying a suggestion calls `recordDispatcherChoice()` with the chosen rank
- [ ] Applying creates dispatch entries via scheduling service
- [ ] "Dismiss All" button records rank 0 choice and closes sheet
- [ ] Error in suggestion generation shows user-friendly message (not silent swallow)
- [ ] Sheet has Close button in toolbar
- [ ] Project builds with zero errors
- [ ] Log entry added to `xcode-ai/prompt-results-log.md`

## Log Entry

```
## Prompt 64F — AI Dispatch Surface
**Date:** YYYY-MM-DD
**Status:** ✅ / ❌
**Files changed:** (list)
**What changed:** Apply/Dismiss buttons, recordDispatcherChoice wiring, error handling
**Build:** PASS / FAIL
```
