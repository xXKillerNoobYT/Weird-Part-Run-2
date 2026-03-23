# 33B — Fix Clock Page SQL Error + Add Lunch/Break/Supply Run

> **Chain position:** **33B** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Context

The Clock page crashes with "SQLite error 1: no such column: address" when loading jobs. The `jobs` table doesn't have an `address` column — job location info is stored differently.

Also, Lunch/Break/Supply Run buttons need to be on the Clock page (currently only on Daily Report).

## Files to Read First

- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift` — if it has inline clock
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift` — the clock page
- `core/Sources/WiredPartCore/Services/JobsService.swift` — check actual job columns
- `core/Sources/WiredPartCore/Models/Foundation/FoundationModels.swift` — Job model

## Task

### Step 1: Fix the SQL Error

Find the query that references `address` column in the jobs table. The `jobs` table has `site_address` (or similar) — check the actual column name in the model/migration and fix the query.

If the page uses raw SQL (`db.writer.read`), replace it with a `JobsService` method call.

### Step 2: Add Lunch/Break/Supply Run Buttons

When a user is clocked in, show these buttons below the clock-out button:

```swift
if isCurrentlyClockedIn {
    // Existing clock-out button

    Divider()

    // Break/Lunch/Supply Run buttons
    HStack(spacing: 12) {
        Button {
            // Start lunch — clock out with type "lunch"
        } label: {
            Label("Lunch", systemImage: "fork.knife")
        }
        .buttonStyle(.bordered)

        Button {
            // Start break — clock out with type "break"
        } label: {
            Label("Break", systemImage: "cup.and.saucer")
        }
        .buttonStyle(.bordered)

        Button {
            // Supply run — change status, stay clocked in
        } label: {
            Label("Supply Run", systemImage: "car.fill")
        }
        .buttonStyle(.bordered)
    }
}
```

**Supply Run is different from Lunch/Break:**
- Lunch/Break: clocks the user out (paid break, starts timer)
- Supply Run: keeps the user clocked in, changes activity status to "supply_run"

### Step 3: Verify Clock-Out + Questionnaire Flow

Make sure clocking out still triggers the questionnaire (`showQuestionnaire = true` from prompt 19G).

## Success Criteria

- [ ] No "no such column: address" error
- [ ] Job list loads successfully on Clock page
- [ ] Lunch/Break/Supply Run buttons visible when clocked in
- [ ] Supply Run keeps clock running (doesn't clock out)
- [ ] Lunch/Break clocks out and starts timer
- [ ] Clock-out still triggers questionnaire
- [ ] Project builds with no errors
