# 61C — Add Auto-Fill Job Context from Active Clock Entry

> **Chain position:** **61C** (standalone)
> **Issue:** T2-05
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT auto-submit anything — only PRE-SELECT the job
2. The user must be able to CHANGE the pre-selected job
3. If no active clock entry exists, leave the job field empty (current behavior)
4. DO NOT break existing manual job selection
5. Project must build with zero errors when done

## Context

When a worker is clocked into a job and opens Q&A, creates a notebook, sends a chat message, or reports a problem, the system should automatically know which job they're working on. Currently these forms start with no job selected, forcing the user to manually pick the job they're ALREADY clocked into. This is unnecessary friction.

The pattern: call `appCore.jobsService.getActiveClockEntry(userId:)` on appear. If a clock entry exists, pre-select its `jobId` in the form's job picker.

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSQAQuestionForm.swift`
2. `Weird Parts IOS/Weird Parts IOS/Features/Notebooks/CreateNotebookSheet.swift`
3. `Weird Parts IOS/Weird Parts IOS/Features/Chat/IOSMessageThreadView.swift`
4. `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardDailyReportPage.swift` (ReportProblemSheet)

## Task

### 1. Add Auto-Fill to IOSQAQuestionForm

Find the job selection state variable (likely `@State private var selectedJobId: Int64?` or similar).

Add an `.onAppear` or `.task` block:
```swift
.task {
    // Auto-fill job from active clock entry
    if selectedJobId == nil {
        do {
            guard let service = appCore.jobsService else { return }
            let userId = appCore.currentUser?.id ?? 0
            if let activeEntry = try service.getActiveClockEntry(userId: userId) {
                selectedJobId = activeEntry.jobId
            }
        } catch { }
    }
}
```

**Important:** Only set `selectedJobId` if it's currently `nil` (user hasn't already picked one). The `if selectedJobId == nil` guard prevents overwriting a manual selection if the form is re-rendered.

### 2. Add Auto-Fill to CreateNotebookSheet

Same pattern. Find the job ID state variable. Add the `.task` block to auto-fill from active clock entry.

If the sheet has a `jobId` parameter passed in from the parent, check that first:
```swift
.task {
    if selectedJobId == nil && initialJobId == nil {
        // Only auto-fill if no job was passed in AND none selected
        do {
            guard let service = appCore.jobsService else { return }
            let userId = appCore.currentUser?.id ?? 0
            if let activeEntry = try service.getActiveClockEntry(userId: userId) {
                selectedJobId = activeEntry.jobId
            }
        } catch { }
    }
}
```

### 3. Add Auto-Fill to IOSMessageThreadView

This page may already have a job context from navigation. Only auto-fill if the thread is being created NEW (not viewing an existing thread). Look for a "new message" or "compose" mode.

### 4. Add Auto-Fill to ReportProblemSheet (in DashboardDailyReportPage)

The ReportProblemSheet is embedded in DashboardDailyReportPage. Find the job picker in that sheet and auto-fill.

### 5. Show Auto-Fill Indicator

When the job is auto-filled, show a small label below the job picker:
```swift
if wasAutoFilled {
    Text("Auto-filled from your active clock entry")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

Add a `@State private var wasAutoFilled = false` and set it to `true` when auto-fill succeeds.

### 6. Verify getActiveClockEntry Exists

Check that `JobsService` has a `getActiveClockEntry(userId:)` method. If it doesn't exist, check for similar methods like `getCurrentClockEntry`, `getActiveEntry`, or `getClockStatus`. Use whatever method returns the current active clock entry for a user.

If NO such method exists, add one to JobsService:
```swift
func getActiveClockEntry(userId: Int64) throws -> ClockEntry? {
    return try db.read { db in
        try ClockEntry
            .filter(Column("userId") == userId)
            .filter(Column("clockOut") == nil)
            .order(Column("clockIn").desc)
            .fetchOne(db)
    }
}
```

## Success Criteria

- [ ] IOSQAQuestionForm auto-fills job from active clock entry
- [ ] CreateNotebookSheet auto-fills job from active clock entry
- [ ] IOSMessageThreadView auto-fills job context when composing new message
- [ ] ReportProblemSheet auto-fills job from active clock entry
- [ ] Auto-fill only triggers when no job is already selected
- [ ] "Auto-filled from your active clock entry" caption shown when auto-filled
- [ ] User can still change the auto-filled job manually
- [ ] Project builds with zero errors
