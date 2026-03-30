# 60Q — Dispatch Page Drag-and-Drop

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

The dispatch page is a visual board but has zero drag-and-drop interaction. Workers in the "Unassigned" section should be draggable onto job rows to create dispatch assignments. This uses SwiftUI's native `.draggable()` and `.dropDestination()` modifiers (iOS 16+).

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSDispatchPage.swift` — see the current layout, worker list, job rows
- `core/Sources/WiredPartCore/Services/SchedulingService.swift` — find the dispatch assignment creation method and the time-off checking method

## Task

### Step 1: Create a Transferable model for dragged workers

At the top of `IOSDispatchPage.swift` (or in a shared models area), define a transferable type:

```swift
import UniformTypeIdentifiers

/// Represents a worker being dragged in the dispatch board.
struct DraggableWorker: Codable, Transferable {
    let employeeId: Int64
    let displayName: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .draggableWorker)
    }
}

extension UTType {
    static let draggableWorker = UTType(exportedAs: "com.wiredpart.draggable-worker")
}
```

**IMPORTANT:** You must also add the UTType to the app's `Info.plist` or use the exported type declarations. Add to the Xcode project's Info tab under "Exported Type Identifiers":
- Identifier: `com.wiredpart.draggable-worker`
- Conforms To: `public.data`

### Step 2: Make unassigned worker rows draggable

Find the section in IOSDispatchPage that shows unassigned workers. Wrap each worker row with `.draggable()`:

```swift
// In the unassigned workers section:
ForEach(unassignedWorkers, id: \.id) { worker in
    HStack {
        Image(systemName: "person.circle.fill")
            .foregroundStyle(.secondary)
        Text(worker.displayName)
            .font(.subheadline)
        Spacer()
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 12)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemBackground)))
    .draggable(DraggableWorker(employeeId: worker.id, displayName: worker.displayName)) {
        // Drag preview
        HStack {
            Image(systemName: "person.fill")
            Text(worker.displayName)
        }
        .padding(8)
        .background(.blue.opacity(0.2))
        .cornerRadius(8)
    }
}
```

### Step 3: Make job rows accept drops

Find each job row in the dispatch board. Add `.dropDestination()`:

```swift
// On each job row:
jobRowView(job)
    .dropDestination(for: DraggableWorker.self) { workers, _ in
        guard let worker = workers.first else { return false }
        handleWorkerDrop(worker: worker, onto: job)
        return true
    } isTargeted: { isTargeted in
        // Highlight the job row when a worker is being dragged over it
        jobHighlightStates[job.id] = isTargeted
    }
```

Add a state variable to track highlights:

```swift
@State private var jobHighlightStates: [Int64: Bool] = [:]
```

Apply visual feedback on the job row:

```swift
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(jobHighlightStates[job.id] == true ? Color.blue : Color.clear, lineWidth: 2)
)
```

### Step 4: Handle the drop — create dispatch assignment

```swift
private func handleWorkerDrop(worker: DraggableWorker, onto job: DispatchJob) {
    // Check for time-off conflicts first
    Task {
        guard let schedulingService = appCore.schedulingService else { return }

        do {
            // Check if worker has approved time off on the selected date
            let timeOff = try schedulingService.getTimeOffForEmployee(
                employeeId: worker.employeeId,
                date: selectedDate  // the currently selected dispatch date
            )

            if let timeOff, timeOff.status == "approved" {
                // Show conflict alert
                conflictWorker = worker
                conflictJob = job
                conflictTimeOff = timeOff
                showTimeOffConflict = true
                return
            }

            // No conflict — create the assignment
            try createDispatchAssignment(worker: worker, job: job)
            await loadDispatchData()  // refresh the board
        } catch {
            actionError = "Failed to assign \(worker.displayName): \(error.localizedDescription)"
        }
    }
}

private func createDispatchAssignment(worker: DraggableWorker, job: DispatchJob) throws {
    guard let schedulingService = appCore.schedulingService else {
        throw NSError(domain: "WiredPart", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scheduling service unavailable"])
    }

    try schedulingService.createDispatchAssignment(
        employeeId: worker.employeeId,
        jobId: job.id,
        date: selectedDate
    )
}
```

**IMPORTANT:** Read `SchedulingService.swift` to find the ACTUAL method names for creating dispatch assignments and checking time off. The names above are approximate. Use whatever methods exist.

### Step 5: Add time-off conflict alert

```swift
@State private var showTimeOffConflict = false
@State private var conflictWorker: DraggableWorker?
@State private var conflictJob: DispatchJob?  // use the actual job type
@State private var conflictTimeOff: TimeOffRequest?  // use the actual type

// Add to the view body:
.alert("Time-Off Conflict", isPresented: $showTimeOffConflict) {
    Button("Assign Anyway", role: .destructive) {
        if let worker = conflictWorker, let job = conflictJob {
            Task {
                do {
                    try createDispatchAssignment(worker: worker, job: job)
                    await loadDispatchData()
                } catch {
                    actionError = error.localizedDescription
                }
            }
        }
    }
    Button("Cancel", role: .cancel) { }
} message: {
    if let worker = conflictWorker {
        Text("\(worker.displayName) has approved time off on this date. Assign anyway?")
    }
}
```

### Step 6: Add error banner for action errors

```swift
@State private var actionError: String?

// At the top of the List:
if let actionError {
    Section {
        Text(actionError)
            .foregroundStyle(.red)
            .font(.caption)
    }
}
```

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSDispatchPage.swift` — add drag-and-drop, conflict alert, assignment creation

## Success Criteria

- [ ] Unassigned worker rows have `.draggable()` modifier with a DraggableWorker payload
- [ ] Job rows have `.dropDestination(for: DraggableWorker.self)` modifier
- [ ] Dropping a worker onto a job creates a dispatch assignment via SchedulingService
- [ ] Job row highlights blue when a worker is dragged over it
- [ ] Time-off conflict check runs before assignment creation
- [ ] Conflict alert shows with "Assign Anyway" and "Cancel" options
- [ ] After successful drop, the board refreshes (worker moves from unassigned to assigned)
- [ ] Action errors displayed to user, not silently swallowed
- [ ] Builds without errors
