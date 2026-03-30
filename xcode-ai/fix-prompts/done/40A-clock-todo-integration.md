# 40A — Clock Page To-Do Integration

> **Chain position:** **40A** → 40B
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. All errors must update UI state — no `print()` only

## Instructions

**IMPORTANT:** Before implementing, read `IOSClockPage.swift` and `JobsService.swift` to understand the current clock-in flow. Then add to-do integration so workers can track what they're doing, not just which job they're on.

## Context

Currently the clock page lets you clock in/out of a job but doesn't track WHAT you're working on. The notebook system has to-dos (from prompt 43A+), and workers need to link their clock time to specific to-dos. This gives managers real-time visibility into work progress and makes daily reports accurate.

Workers should also classify their work as "New Work" or "Warranty" (for warranty job tracking in 45C/45D).

## Task

### Step 1: Add Service Methods to JobsService

```swift
// MARK: - Clock + To-Do Integration

/// Link a clock entry to a specific to-do
func linkClockEntryToTodo(clockEntryId: Int64, todoId: Int64) async throws {
    try await db.write { db in
        try db.execute(sql: """
            UPDATE clock_entries SET linked_todo_id = :todoId, updated_at = datetime('now')
            WHERE id = :clockEntryId
        """, arguments: ["todoId": todoId, "clockEntryId": clockEntryId])
    }
}

/// Get active (incomplete) to-dos for a job
func getActiveJobTodos(jobId: Int64) async throws -> [NotebookEntry] {
    try await db.read { db in
        try Row.fetchAll(db, sql: """
            SELECT ne.* FROM notebook_entries ne
            JOIN notebooks n ON ne.notebook_id = n.id
            WHERE n.job_id = :jobId
            AND ne.entry_type = 'todo'
            AND ne.is_complete = 0
            AND ne.deleted_at IS NULL
            ORDER BY ne.sort_order ASC
        """, arguments: ["jobId": jobId])
        .map { row in /* map to NotebookEntry */ }
    }
}

/// Set work type for current clock entry
func setClockEntryWorkType(clockEntryId: Int64, workType: String) async throws {
    // workType: "new_work" or "warranty"
    try await db.write { db in
        try db.execute(sql: """
            UPDATE clock_entries SET work_type = :workType, updated_at = datetime('now')
            WHERE id = :clockEntryId
        """, arguments: ["workType": workType, "clockEntryId": clockEntryId])
    }
}
```

### Step 2: Migration — Add Columns to clock_entries

```swift
// In AppDatabase+Migrations.swift — new migration
try db.alter(table: "clock_entries") { t in
    t.add(column: "linked_todo_id", .integer)
        .references("notebook_entries", onDelete: .setNull)
    t.add(column: "work_type", .text)
        .defaults(to: "new_work")  // "new_work" or "warranty"
}
```

### Step 3: Update IOSClockPage.swift

**A. To-Do Picker on Clock-In:**

After the user selects a job and taps Clock In, show a to-do picker:

```swift
// After clock-in succeeds, show to-do picker
@State private var showTodoPicker = false
@State private var activeTodos: [NotebookEntry] = []
@State private var currentTodo: NotebookEntry?
@State private var workType: String = "new_work"

// In the clock-in flow, after successful clock-in:
// 1. Load active to-dos for the job
// 2. Show picker sheet
// 3. Link selected to-do to clock entry
```

**B. While Clocked In — Show Current To-Do:**

```swift
// When clocked in, show a section:
Section {
    // Work Type Picker
    Picker("Work Type", selection: $workType) {
        Text("New Work").tag("new_work")
        Text("Warranty").tag("warranty")
    }
    .pickerStyle(.segmented)
    .onChange(of: workType) { _, newValue in
        Task { try? await service.setClockEntryWorkType(...) }
    }

    // Current To-Do display
    if let todo = currentTodo {
        HStack {
            VStack(alignment: .leading) {
                Text(todo.title).font(.headline)
                Text("Working on this").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }

        // Action buttons
        HStack(spacing: 12) {
            Button("Mark Done + Pick Next") {
                Task { await markTodoDoneAndPickNext() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button("Switch To-Do") {
                showTodoPicker = true
            }
            .buttonStyle(.bordered)
        }
    } else {
        Button("Pick a To-Do") {
            showTodoPicker = true
        }
    }
} header: {
    Text("Current Task")
}
```

**C. To-Do Picker Sheet:**

```swift
struct TodoPickerSheet: View {
    let todos: [NotebookEntry]
    let onSelect: (NotebookEntry) -> Void

    var body: some View {
        NavigationStack {
            List(todos) { todo in
                Button {
                    onSelect(todo)
                } label: {
                    VStack(alignment: .leading) {
                        Text(todo.title).font(.headline)
                        if let description = todo.content {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("What are you working on?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { /* dismiss without selecting */ }
                }
            }
        }
    }
}
```

**D. Mark Done + Pick Next Flow:**

```swift
func markTodoDoneAndPickNext() async {
    guard let todo = currentTodo else { return }
    do {
        // Mark current to-do as complete
        try await notebooksService.completeEntry(entryId: todo.id)

        // Reload active to-dos
        activeTodos = try await jobsService.getActiveJobTodos(jobId: currentJobId)

        if activeTodos.isEmpty {
            currentTodo = nil
            // Show "All to-dos done!" message
        } else {
            // Show picker for next to-do
            showTodoPicker = true
        }
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Step 4: Update ConflictResolver

Add `linked_todo_id` and `work_type` columns to the clock_entries handling in ConflictResolver if needed.

## Important Notes
- The to-do picker is OPTIONAL — workers can skip it and just clock in
- "Switch To-Do" changes the linked to-do WITHOUT completing the current one
- "Mark Done + Pick Next" completes the to-do AND shows the picker
- Work type defaults to "new_work" — warranty is only relevant for warranty jobs
- If the job has no notebook or no to-dos, the to-do section should not appear at all
- To-do picker should only show INCOMPLETE to-dos

## Success Criteria
- [ ] Migration adds linked_todo_id and work_type to clock_entries
- [ ] 3+ service methods added to JobsService
- [ ] Clock-in shows to-do picker after job selection
- [ ] While clocked in: current to-do displayed with Mark Done + Switch buttons
- [ ] Work type selector (New Work / Warranty) shown while clocked in
- [ ] All errors show in UI state
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 40A Results (YYYY-MM-DD)
- Migration: added linked_todo_id + work_type to clock_entries
- Service: X methods added to JobsService
- UI: to-do picker, current task section, work type selector
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 40B.**
