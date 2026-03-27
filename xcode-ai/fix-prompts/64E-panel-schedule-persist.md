# 64E — Panel Schedule Persist: Wire Save Through NotebooksService

> **Chain position:** After 64D, before 64F
> **Priority:** MEDIUM — panel schedule data is lost on page close
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

In `IOSNotebookDetailPage.swift`, the `persistPanelSchedule()` function (line ~794) partially works — it encodes the schedule to JSON and tries to save it. But the save logic uses `try?` which silently swallows errors, and the `findPanelScheduleEntryId()` lookup may not find an existing entry, causing data loss.

**Read these files first:**
- `Features/Notebooks/IOSNotebookDetailPage.swift` — the persist function (~line 794) and panel schedule editor sheet (~line 680)
- `core/Sources/WiredPartCore/Services/NotebooksService.swift` — service methods for block entries

## Context

The panel schedule builder produces a `PanelSchedule` struct. When the user taps "Save" in the builder, it calls `persistPanelSchedule(saved)`. The function:

1. Encodes the schedule to JSON
2. Looks for an existing `panel_schedule` block entry to update
3. If found, updates the entry's `blockData`
4. If not found... does nothing (data lost)

## Task

### Step 1: Fix `persistPanelSchedule()` to handle both create and update

Replace the current implementation with robust save logic:

```swift
private func persistPanelSchedule(_ schedule: PanelSchedule) {
    guard let service = appCore.notebooksService else {
        loadError = "Service not available"
        return
    }
    guard let notebookId = notebook?.id else {
        loadError = "No notebook loaded"
        return
    }
    guard let json = try? JSONEncoder().encode(schedule),
          let jsonString = String(data: json, encoding: .utf8) else {
        loadError = "Failed to encode panel schedule"
        return
    }

    do {
        if let existingEntryId = findPanelScheduleEntryId() {
            // Update existing panel schedule entry
            try service.updateBlockEntry(entryId: existingEntryId, content: nil, blockData: jsonString)
        } else {
            // Create new panel_schedule block entry in the first section
            let sectionId = findOrCreateDefaultSectionId()
            guard let sectionId else {
                loadError = "No section available for panel schedule"
                return
            }
            try service.addBlockEntry(
                sectionId: sectionId,
                blockType: "panel_schedule",
                content: "Panel Schedule",
                blockData: jsonString,
                sortOrder: 9999  // append at end
            )
        }
        // Reload to reflect saved state
        loadNotebookDetail()
    } catch {
        loadError = userFriendlyError(error, context: "save panel schedule")
    }
}
```

### Step 2: Ensure `findPanelScheduleEntryId()` works correctly

Verify or fix this helper. It should search all block entries in the current notebook for one with `blockType == "panel_schedule"` and return its ID. If it doesn't exist, add it:

```swift
private func findPanelScheduleEntryId() -> Int64? {
    // Search through loaded sections/entries for a panel_schedule block
    for section in sections {
        for entry in section.entries {
            if entry.blockType == "panel_schedule" {
                return entry.id
            }
        }
    }
    return nil
}
```

### Step 3: Add `findOrCreateDefaultSectionId()` helper

If the notebook has sections loaded, return the first section's ID. If no sections exist, create one via the service:

```swift
private func findOrCreateDefaultSectionId() -> Int64? {
    if let firstSection = sections.first {
        return firstSection.id
    }
    // If no sections, try to create a default one
    guard let service = appCore.notebooksService,
          let notebookId = notebook?.id else { return nil }
    return try? service.addSection(notebookId: notebookId, name: "General", sortOrder: 0)
}
```

### Step 4: Load saved panel schedule on page open

In the `loadNotebookDetail()` function (or wherever sections/entries are loaded), check for a `panel_schedule` block entry and decode it into `panelSchedule`:

```swift
// After loading sections/entries:
if let scheduleEntry = sections.flatMap(\.entries).first(where: { $0.blockType == "panel_schedule" }),
   let data = scheduleEntry.blockData?.data(using: .utf8),
   let decoded = try? JSONDecoder().decode(PanelSchedule.self, from: data) {
    panelSchedule = decoded
}
```

This ensures the panel schedule is restored when the user reopens the notebook.

## Success Criteria

- [ ] Panel schedule saves to database via NotebooksService (no `try?` swallowing errors)
- [ ] New notebooks get a panel_schedule entry created on first save
- [ ] Existing notebooks update the existing panel_schedule entry
- [ ] Panel schedule loads from database when notebook opens
- [ ] Errors shown to user via `loadError` (not silently swallowed)
- [ ] Project builds with zero errors
- [ ] Log entry added to `xcode-ai/prompt-results-log.md`

## Log Entry

```
## Prompt 64E — Panel Schedule Persist
**Date:** YYYY-MM-DD
**Status:** ✅ / ❌
**Files changed:** (list)
**What changed:** persist function rebuilt, create-or-update logic, load-on-open
**Build:** PASS / FAIL
```
