# 40B — Clock Page Live Timer + Today's Hours

> **Chain position:** 40A → **40B**
> **Prerequisite:** 40A (to-do integration)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSClockPage.swift` to understand the current state after 40A. Then add a live elapsed timer, today's hours breakdown, and a Switch Job shortcut button.

## Context

Workers need to see how long they've been on the clock at a glance. They also need to see today's total hours broken down by job AND by to-do. The "Switch Job" button eliminates a 2-step process (clock out → clock in to new job) into one action.

## Task

### Step 1: Live Elapsed Timer

Add a timer that updates every minute showing elapsed time since clock-in:

```swift
@State private var elapsedTimer: Timer?
@State private var elapsedText: String = "0h 0m"

// Start timer when clocked in
func startElapsedTimer() {
    updateElapsedText()
    elapsedTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
        updateElapsedText()
    }
}

func updateElapsedText() {
    guard let clockInTime = currentClockEntry?.clockInTime else { return }
    let elapsed = Date().timeIntervalSince(clockInTime)
    let hours = Int(elapsed) / 3600
    let minutes = (Int(elapsed) % 3600) / 60
    elapsedText = "\(hours)h \(minutes)m"
}

// In the view, when clocked in:
VStack {
    Text(elapsedText)
        .font(.system(size: 48, weight: .bold, design: .rounded))
        .monospacedDigit()
    Text("on \(currentJob?.name ?? "Unknown Job")")
        .font(.subheadline)
        .foregroundStyle(.secondary)
}
.onAppear { if isClockedIn { startElapsedTimer() } }
.onDisappear { elapsedTimer?.invalidate() }
```

### Step 2: Today's Hours Breakdown

Add a section showing today's completed + current clock entries:

```swift
// Service method in JobsService:
func getTodaysClockEntries(userId: Int64) async throws -> [ClockEntrySummary] {
    // Returns all clock entries for today, grouped by job
    // Each entry: job name, to-do name (if linked), start time, end time (or "now"), duration
}

struct ClockEntrySummary {
    let jobId: Int64
    let jobName: String
    let todoName: String?
    let startTime: Date
    let endTime: Date?  // nil = still clocked in
    let workType: String
    var duration: TimeInterval { (endTime ?? Date()).timeIntervalSince(startTime) }
}

// In the view:
Section {
    // Per-job breakdown
    ForEach(todaysByJob, id: \.jobId) { jobGroup in
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(jobGroup.jobName).font(.headline)
                Spacer()
                Text(formatDuration(jobGroup.totalDuration))
                    .font(.headline).monospacedDigit()
            }
            // Per-to-do breakdown within job
            ForEach(jobGroup.entries) { entry in
                HStack {
                    if let todo = entry.todoName {
                        Text("  \(todo)").font(.caption)
                    }
                    Spacer()
                    Text(formatDuration(entry.duration))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // Total
    HStack {
        Text("Today Total").font(.headline).bold()
        Spacer()
        Text(formatDuration(todaysTotal))
            .font(.headline).bold().monospacedDigit()
    }
    .padding(.top, 4)
} header: {
    Text("Today's Hours")
}
```

### Step 3: Switch Job Button

One-action button that clocks out of current job and immediately shows job picker for new clock-in:

```swift
Button {
    Task { await switchJob() }
} label: {
    Label("Switch Job", systemImage: "arrow.triangle.swap")
}
.buttonStyle(.bordered)

func switchJob() async {
    do {
        // 1. Clock out of current job
        try await jobsService.clockOut(clockEntryId: currentClockEntry!.id)

        // 2. Immediately show job picker for new clock-in
        // The to-do picker from 40A will show after job selection
        showJobPicker = true
    } catch {
        actionError = error.localizedDescription
    }
}
```

### Step 4: Format Helper

```swift
func formatDuration(_ interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    return "\(hours)h \(minutes)m"
}
```

## Important Notes
- Timer uses 60-second interval — no need for second-level precision on a work clock
- Timer must be invalidated on view disappear to prevent memory leaks
- Today's hours should reload when the view appears (`.task` modifier)
- Switch Job should preserve the work type selection if the new job is also a warranty job
- If no clock entries exist today, show "No hours logged today" in the breakdown section
- The elapsed timer section replaces or enhances any existing "clocked in" indicator

## Success Criteria
- [ ] Live timer shows elapsed time updating every minute
- [ ] Timer displays in large, readable format (48pt bold)
- [ ] Today's hours section shows per-job and per-to-do breakdown
- [ ] Total hours shown at bottom of breakdown
- [ ] Switch Job button clocks out + shows job picker in one flow
- [ ] Timer invalidated on view disappear
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 40B Results (YYYY-MM-DD)
- Live timer: 60s interval, large display
- Today's breakdown: per-job + per-to-do grouping
- Switch Job: one-action clock out + picker
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
