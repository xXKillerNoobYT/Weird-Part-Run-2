# 46B — Dispatch Board (Gantt-Style)

> **Chain position:** 46A → **46B**
> **Prerequisite:** 46A (half-day scheduling)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSDispatchPage.swift` and `SchedulingService.swift`. Build a Gantt-style dispatch board showing job rows with employee assignment bars, unassigned worker pool, and available jobs.

## Context

Dispatchers need a visual board showing the week: job rows on the left, daily columns across, colored bars showing who's assigned where. Unassigned workers at the bottom need to be assigned. Available jobs from the pipeline need to be scheduled. Drag-and-drop would be ideal but a tap-to-assign flow works on mobile. Time-off conflicts warn before assignment.

## Task

### Step 1: Dispatch Board Layout

```swift
struct DispatchBoardView: View {
    @State private var weekStart: Date = startOfWeek()
    @State private var assignments: [DispatchAssignment] = []
    @State private var unassignedWorkers: [EmployeeSummary] = []
    @State private var availableJobs: [JobSummary] = []
    @State private var selectedCell: DispatchCell?
    @State private var showAssignSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Week navigation
            weekHeader

            // Scrollable board
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 1) {
                    // Day headers
                    dayHeaderRow

                    // Job rows
                    ForEach(jobRows) { row in
                        jobRow(row)
                    }

                    Divider().padding(.vertical, 8)

                    // Unassigned workers
                    unassignedSection
                }
            }
        }
    }

    var weekHeader: some View {
        HStack {
            Button { previousWeek() } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text("Week of \(weekStart, format: .dateTime.month().day())")
                .font(.headline)
            Spacer()
            Button { nextWeek() } label: { Image(systemName: "chevron.right") }
        }
        .padding()
    }

    var dayHeaderRow: some View {
        HStack(spacing: 1) {
            Text("Job")
                .frame(width: 120, alignment: .leading)
                .font(.caption).bold()
            ForEach(weekDays, id: \.self) { day in
                VStack {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                    Text(day, format: .dateTime.day())
                        .font(.caption).bold()
                }
                .frame(width: 80)
                .background(Calendar.current.isDateInToday(day) ? Color.blue.opacity(0.1) : Color.clear)
            }
        }
        .padding(.horizontal, 8)
    }
}
```

### Step 2: Job Row with Employee Bars

```swift
func jobRow(_ row: DispatchJobRow) -> some View {
    HStack(spacing: 1) {
        // Job name
        VStack(alignment: .leading) {
            Text(row.jobName)
                .font(.caption).bold()
                .lineLimit(1)
            Text(row.stageName ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, alignment: .leading)

        // Day cells
        ForEach(weekDays, id: \.self) { day in
            dayCellForJob(row: row, date: day)
        }
    }
    .padding(.horizontal, 8)
}

func dayCellForJob(row: DispatchJobRow, date: Date) -> some View {
    let workers = assignments.filter {
        $0.jobId == row.jobId && Calendar.current.isDate($0.date, inSameDayAs: date)
    }

    return VStack(spacing: 1) {
        if workers.isEmpty {
            // Empty cell — tap to assign
            Button {
                selectedCell = DispatchCell(jobId: row.jobId, date: date)
                showAssignSheet = true
            } label: {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.1))
                    .frame(width: 80, height: 24)
                    .overlay {
                        Image(systemName: "plus").font(.caption2).foregroundStyle(.gray)
                    }
            }
        } else {
            ForEach(workers) { worker in
                Text(worker.employeeInitials)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(worker.timeSlot == "am" ? .blue : worker.timeSlot == "pm" ? .green : .orange)
                    )
            }
        }
    }
    .frame(width: 80, minHeight: 24)
}
```

### Step 3: Unassigned Workers Section

```swift
var unassignedSection: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("Unassigned Workers")
            .font(.caption).bold()
            .foregroundStyle(.red)
            .padding(.horizontal, 8)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(unassignedWorkers) { worker in
                    VStack {
                        Text(worker.name)
                            .font(.caption)
                        Text(worker.skills ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture {
                        selectedWorkerForAssignment = worker
                        showAssignSheet = true
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}
```

### Step 4: Available Jobs Pool

```swift
// Jobs that need workers assigned
Section {
    ForEach(availableJobs) { job in
        HStack {
            VStack(alignment: .leading) {
                Text(job.name).font(.caption).bold()
                Text("Needs \(job.workersNeeded) workers")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
            if let stage = job.currentStageName {
                Text(stage).font(.caption2).foregroundStyle(.blue)
            }
        }
    }
} header: {
    Text("Available Jobs (\(availableJobs.count))")
}
```

### Step 5: Assignment Sheet

```swift
// Tap empty cell or worker → show assignment sheet
.sheet(isPresented: $showAssignSheet) {
    DispatchAssignSheet(
        cell: selectedCell,
        worker: selectedWorkerForAssignment,
        availableWorkers: unassignedWorkers,
        availableJobs: availableJobs,
        onAssign: { assignment in
            Task { await createAssignment(assignment) }
        }
    )
}
```

### Step 6: Time-Off Conflict Warning

```swift
func createAssignment(_ assignment: DispatchAssignment) async {
    do {
        // Check for time-off conflicts
        let conflict = try await schedulingService.checkTimeOffConflict(
            employeeId: assignment.employeeId,
            date: assignment.date
        )
        if let conflict = conflict {
            conflictWarning = "Warning: \(conflict.employeeName) has time off on this date (\(conflict.reason ?? ""))"
            showConflictAlert = true
            pendingAssignment = assignment
            return
        }
        // No conflict — proceed
        try await schedulingService.createDispatchAssignment(assignment)
        await loadData()
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Step 7: Job Info Popup

```swift
// Long-press on job name → popup with details
.contextMenu {
    VStack {
        Text(row.jobName).font(.headline)
        Text("Stage: \(row.stageName ?? "None")")
        Text("Crew: \(row.crewHistory)")
        if let blockers = row.blockers {
            Text("Blockers: \(blockers)")
                .foregroundStyle(.red)
        }
    }
}
```

## Important Notes
- The board is horizontally scrollable (7 day columns + job name column)
- Color coding: AM=blue, PM=green, Full Day=orange
- Employee initials fit in small cells (2-3 characters)
- Tap empty cell to assign a worker to that job+day
- Tap unassigned worker to see available jobs
- Time-off conflicts show a warning popup before allowing override
- The board should show the current week by default
- Half-day support from 46A enables AM/PM split assignments

## Success Criteria
- [ ] Gantt-style board with job rows and day columns
- [ ] Employee bars with initials and color coding
- [ ] Half-day support (AM/PM bars)
- [ ] Unassigned workers section at bottom
- [ ] Available jobs pool
- [ ] Tap to assign (cell or worker)
- [ ] Time-off conflict warning popup
- [ ] Job info on long-press
- [ ] Week navigation
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 46B Results (YYYY-MM-DD)
- Dispatch board: Gantt-style with job rows + day columns
- Employee assignment bars with AM/PM/Full Day
- Unassigned workers + available jobs
- Time-off conflict detection
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
