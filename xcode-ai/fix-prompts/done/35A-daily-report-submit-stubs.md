# 35A — Fix Daily Report Submit Stubs + Service Bypass

> **Chain position:** **35A** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT leave TODO stubs on user-facing buttons
3. ALWAYS use `appCore.xxxService` — never create services directly

## Context

DashboardDailyReportPage has TWO submit buttons that do nothing:
1. ReportProblemSheet Submit → `// TODO: Create notebook entry tagged as 'problem'` → just dismisses
2. SubmitDailyReportSheet Submit → `// TODO: Save daily report via JobsService` → just dismisses

Also: DashboardKPIDetailSheets creates `JobsService(db: db)` and `OrdersService(db: db)` directly instead of using `appCore.jobsService` / `appCore.ordersService`.

Also: DashboardDailyReportPage has 225+ lines of raw SQL and `import GRDB`.

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardDailyReportPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardKPIDetailSheets.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift`

## Task

### 1. Wire ReportProblemSheet Submit
Create a notebook entry tagged as "problem" using NotebooksService:
```swift
guard let service = appCore.notebooksService else {
    saveError = "Service not available"
    return
}
try service.createNotebookEntry(
    notebookId: jobNotebookId,
    entryType: "problem",
    content: problemDescription,
    createdBy: appCore.currentUser?.id ?? 0
)
```

### 2. Wire SubmitDailyReportSheet Submit
Save daily report using JobsService:
```swift
guard let service = appCore.jobsService else {
    saveError = "Service not available"
    return
}
try service.submitDailyReport(
    jobId: selectedJobId,
    date: reportDate,
    summary: reportSummary,
    hoursWorked: totalHours,
    submittedBy: appCore.currentUser?.id ?? 0
)
```

### 3. Fix DashboardKPIDetailSheets Service Bypass
Replace ALL direct service creation:
```swift
// BEFORE:
let service = JobsService(db: db)
// AFTER:
guard let service = appCore.jobsService else {
    loadError = "Service not available"
    return
}
```

### 4. Remove raw SQL from DashboardDailyReportPage
Move the 225+ lines of SQL into service methods and use those instead.

### 5. Remove raw SQL from DashboardView
Move chart data queries into service methods.

## Success Criteria

- [ ] Both Submit buttons actually save data
- [ ] No direct service creation — all through appCore
- [ ] No `import GRDB` in any Dashboard file
- [ ] No raw SQL in any Dashboard file
- [ ] Project builds with no errors
