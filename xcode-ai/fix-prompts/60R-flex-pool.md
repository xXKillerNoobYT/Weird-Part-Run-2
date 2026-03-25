# 60R — Flex Pool Section on Clock Page

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

When a worker has no dispatch assignment for today, they see nothing actionable on the Clock page. Add a "Flex Pool" section that shows available flex jobs the worker can self-assign to. This helps workers find work when they're not pre-dispatched.

**Read first:**
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift` — see the current layout, clock in/out flow, current job display
- `core/Sources/WiredPartCore/Services/SchedulingService.swift` — find dispatch-related methods
- `core/Sources/WiredPartCore/Services/JobsService.swift` — find job listing methods, status filters

## Task

### Step 1: Determine if the worker has a dispatch today

In `IOSClockPage.swift`, check whether the current user has a dispatch assignment for today. If they do, the Flex Pool section is hidden. If they do NOT, show it.

```swift
@State private var hasDispatchToday = false
@State private var flexJobs: [FlexJob] = []

struct FlexJob: Identifiable {
    let id: Int64
    let jobName: String
    let jobAddress: String?
    let status: String       // "ready" or "needs_scheduling"
    let customerName: String?
}
```

In the `.task` or `.onAppear`, check for dispatch:

```swift
// Check if user has dispatch for today
if let schedulingService = appCore.schedulingService,
   let userId = appCore.currentUser?.id {
    let todayStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
    // Look up dispatch assignments for this user on today's date
    // Use whatever method exists on SchedulingService
    let dispatches = try? schedulingService.getDispatchesForEmployee(employeeId: userId, date: String(todayStr))
    hasDispatchToday = !(dispatches?.isEmpty ?? true)

    if !hasDispatchToday {
        loadFlexJobs()
    }
}
```

**IMPORTANT:** Read `SchedulingService.swift` to find the actual method for checking an employee's dispatches. The method name above is approximate.

### Step 2: Load flex jobs

```swift
private func loadFlexJobs() {
    guard let jobsService = appCore.jobsService else { return }
    do {
        // Get active jobs that need workers — "confirmed" or "in_progress" status
        let activeJobs = try jobsService.listJobs(status: "active")

        flexJobs = activeJobs.compactMap { job in
            // Determine if job is "ready" (confirmed, can start anytime)
            // or "needs_scheduling" (need to coordinate with owner)
            let flexStatus: String
            if job.status == "confirmed" || job.status == "in_progress" {
                flexStatus = "ready"
            } else {
                flexStatus = "needs_scheduling"
            }

            return FlexJob(
                id: job.id,
                jobName: job.jobName ?? "Untitled Job",
                jobAddress: job.address,
                status: flexStatus,
                customerName: job.customerName
            )
        }
    } catch {
        // Don't block the clock page for flex pool errors
    }
}
```

**IMPORTANT:** Read `JobsService.swift` to find the actual method names and return types. Adapt the code above to match. The job model may have different property names.

### Step 3: Add the Flex Pool section to the view

In `IOSClockPage.swift`, add this section BELOW the main clock controls, but only when `!hasDispatchToday`:

```swift
if !hasDispatchToday && !flexJobs.isEmpty {
    Section {
        VStack(alignment: .leading, spacing: 8) {
            Label("Flex Pool", systemImage: "person.badge.plus")
                .font(.headline)
            Text("No dispatch today. Pick up available work:")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        // Ready to start jobs
        let readyJobs = flexJobs.filter { $0.status == "ready" }
        if !readyJobs.isEmpty {
            ForEach(readyJobs) { job in
                flexJobRow(job, label: "Ready to Start", color: .green)
            }
        }

        // Needs scheduling jobs
        let scheduleJobs = flexJobs.filter { $0.status == "needs_scheduling" }
        if !scheduleJobs.isEmpty {
            ForEach(scheduleJobs) { job in
                flexJobRow(job, label: "Needs Scheduling", color: .orange)
            }
        }
    } header: {
        Text("Available Jobs")
    }
}
```

### Step 4: Create the flex job row with tap-to-assign

```swift
@ViewBuilder
private func flexJobRow(_ job: FlexJob, label: String, color: Color) -> some View {
    Button {
        assignFlexJob(job)
    } label: {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.jobName)
                    .font(.subheadline.weight(.medium))
                if let address = job.jobAddress {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let customer = job.customerName {
                    Text(customer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
}
```

### Step 5: Handle flex job assignment

```swift
@State private var showFlexConfirm = false
@State private var selectedFlexJob: FlexJob?

private func assignFlexJob(_ job: FlexJob) {
    selectedFlexJob = job
    showFlexConfirm = true
}

// Add confirmation alert:
.alert("Start Working?", isPresented: $showFlexConfirm) {
    Button("Assign & Clock In") {
        performFlexAssignment()
    }
    Button("Cancel", role: .cancel) { }
} message: {
    if let job = selectedFlexJob {
        Text("Assign yourself to \"\(job.jobName)\" and clock in now?")
    }
}

private func performFlexAssignment() {
    guard let job = selectedFlexJob,
          let schedulingService = appCore.schedulingService,
          let userId = appCore.currentUser?.id else { return }

    Task {
        do {
            // Create dispatch assignment for today
            let todayStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
            try schedulingService.createDispatchAssignment(
                employeeId: userId,
                jobId: job.id,
                date: String(todayStr)
            )

            // Clock in to the job
            // Use whatever clock-in method exists on the service
            // try jobsService.clockIn(userId: userId, jobId: job.id)

            hasDispatchToday = true
            flexJobs = []
            // Refresh the clock page data
        } catch {
            actionError = "Failed to assign: \(error.localizedDescription)"
        }
    }
}
```

### Step 6: Permission gate

The flex pool should only appear if the user has the `self_assign_ready_jobs` permission (or similar). Check permissions:

```swift
private var canSelfAssign: Bool {
    appCore.currentUser?.permissions?.contains("self_assign_ready_jobs") ?? false
}
```

Wrap the flex pool section with: `if !hasDispatchToday && canSelfAssign && !flexJobs.isEmpty {`

If no such permission exists in the current system, use a reasonable fallback like checking if the user has any job-related hat/permission. Add a comment noting the intended permission name.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift` — add flex pool section, assignment logic, confirmation alert

## Success Criteria

- [ ] Flex Pool section appears on Clock page when worker has no dispatch for today
- [ ] Flex Pool hidden when worker already has a dispatch
- [ ] Jobs split into "Ready to Start" (green) and "Needs Scheduling" (orange)
- [ ] Tapping a flex job shows confirmation alert
- [ ] Confirming creates dispatch assignment + triggers clock-in flow
- [ ] Section gated by permission check (with comment noting intended permission name)
- [ ] Error messages shown to user, not swallowed
- [ ] Builds without errors
