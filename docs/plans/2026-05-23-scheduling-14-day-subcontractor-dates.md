# Scheduling 14-Day Preview + Subcontractor Dates Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Close the scope gap for GH #610 and GH #612 by adding a default next-14-days planning preview and accurate subcontractor scheduled-date entry/editing in the iOS scheduling area.

**Architecture:** Reuse the existing Scheduling feature instead of creating a new module. Employee/crew schedule entries already live in `job_dispatch`; subcontractor visits already have a dedicated `subcontractor_schedules` table/model with `scheduled_date`, `arrival_time`, `departure_time`, `scope_of_work`, `status`, and `notes`. The safest path is a UI-first vertical slice backed by small SchedulingService read/write additions and tests.

**Tech Stack:** SwiftUI iOS views, WiredPartCore `SchedulingService`, GRDB/SQLite, Swift Testing/XCTest-style existing core test harness.

---

## Source Requests

- GH #610: "the next 14 days purview" — user wants current day + next 13 days visible for multi-week planning; month view is useful but lower priority.
- GH #612: "accurately add in the dates that the subcontractors will be showing up if scheduled" — user needs subcontractor arrival dates entered accurately, not just viewed after existing data appears.

## Current Code Findings

- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleCalendarPage.swift`
  - Already has `CalendarMode.week` and `CalendarMode.month`.
  - Week view loads `getMySchedule(userId:startDate:endDate)` for a Monday-Sunday week.
  - Month view has `getMonthScheduleSummary(year:month)` and day detail.
  - Gap for GH #610: no rolling "Today + 14 days" planning preview. Week view is tied to calendar week, so a Friday view only shows three forward days before needing navigation.
- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/CreateScheduleEntrySheet.swift`
  - Creates employee schedule entries into `job_dispatch` for current user only.
  - Good reference for simple schedule creation UI.
- `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSubSchedulePage.swift`
  - Shows subcontractor rows for one selected date.
  - Gap for GH #612: no create/edit flow for subcontractor scheduled arrivals, and row does not show arrival/departure/scope/notes even though the data model has them.
- `core/Sources/WiredPartCore/Models/Scheduling/SchedulingModels.swift`
  - `SubcontractorSchedule` already has `scheduledDate`, `arrivalTime`, `departureTime`, `scopeOfWork`, `status`, and `notes`.
  - Date data model is adequate for first slice; no migration needed unless UI discovers missing recurrence/multi-day requirements later.
- `core/Sources/WiredPartCore/Services/SchedulingService.swift`
  - `SubScheduleRow` currently exposes only `id`, `subName`, `companyName`, `jobName`, `scheduleDate`, `status`.
  - `getSubSchedule(date:)` reads `subcontractor_schedules` by exact date.
  - Need create/update APIs for subcontractor schedules and row fields for arrival/departure/scope/notes.

## Product Decisions

1. Make the rolling 14-day preview the default scheduling planning view because GH #610 says it is more useful than month view in fast-paced planning.
2. Keep Month as a secondary option because it already exists and user said month view should exist, just lower priority.
3. Treat subcontractor scheduled-date entry as a scheduling write flow, not a notes-only workaround.
4. Do not add a schema migration in the first slice; the existing `subcontractor_schedules` table already stores the necessary exact date and time data.
5. Use date-only ISO strings (`yyyy-MM-dd`) consistently, matching existing `scheduled_date` and `dispatch_date` fields.

## Acceptance Criteria

- GH #610:
  - Scheduling calendar has a "14 Days" or "Plan" mode that starts at today by default and shows 14 consecutive days.
  - Each visible day shows scheduled employee entries and time-off counts at minimum.
  - Users can move the 14-day window backward/forward and return to Today.
  - Existing Month view still works.
- GH #612:
  - Sub Schedule page has an Add action for subcontractor schedules.
  - Add form requires job, subcontractor/GC, and scheduled date.
  - Optional arrival/departure time, scope of work, status, and notes can be stored.
  - Sub Schedule rows display scheduled date plus arrival/departure time and scope when present.
  - Existing read path still returns an empty list if tables are absent.
- Verification:
  - Core scheduling tests cover subcontractor schedule create/list/update by date.
  - iOS project compiles after UI changes.

---

## Task 1: Extend SubScheduleRow and getSubSchedule to expose the stored detail fields

**Objective:** Make the existing subcontractor schedule read API return all fields the UI needs before adding write UI.

**Files:**
- Modify: `core/Sources/WiredPartCore/Services/SchedulingService.swift:136-155`
- Modify: `core/Sources/WiredPartCore/Services/SchedulingService.swift:610-642`
- Test: `core/Tests/WiredPartCoreTests/SchedulingServiceTests.swift` or the existing scheduling test file if named differently.

**Step 1: Find existing SchedulingService tests**

Run:
```bash
find core/Tests -name '*Scheduling*' -o -name '*Schedule*'
```

Expected: identify the scheduling test file to extend. If none exists, create `core/Tests/WiredPartCoreTests/SchedulingServiceTests.swift` following the nearest service-test pattern.

**Step 2: Write failing test**

Add a test that inserts a job, a general contractor, and a `subcontractor_schedules` row with:
- `scheduled_date = "2026-06-01"`
- `arrival_time = "07:30"`
- `departure_time = "15:30"`
- `scope_of_work = "Rough-in inspection support"`
- `notes = "Bring lift"`

Then assert `getSubSchedule(date: "2026-06-01")` returns those fields.

**Step 3: Update result type**

Change `SubScheduleRow` to:
```swift
public struct SubScheduleRow: Sendable, Identifiable {
    public let id: Int64
    public let subName: String
    public let companyName: String
    public let jobName: String
    public let scheduleDate: String
    public let arrivalTime: String?
    public let departureTime: String?
    public let scopeOfWork: String?
    public let status: String
    public let notes: String?

    public init(
        id: Int64,
        subName: String,
        companyName: String,
        jobName: String,
        scheduleDate: String,
        arrivalTime: String? = nil,
        departureTime: String? = nil,
        scopeOfWork: String? = nil,
        status: String,
        notes: String? = nil
    ) {
        self.id = id
        self.subName = subName
        self.companyName = companyName
        self.jobName = jobName
        self.scheduleDate = scheduleDate
        self.arrivalTime = arrivalTime
        self.departureTime = departureTime
        self.scopeOfWork = scopeOfWork
        self.status = status
        self.notes = notes
    }
}
```

**Step 4: Update SQL selection**

In `getSubSchedule(date:)`, select:
```sql
ss.arrival_time,
ss.departure_time,
ss.scope_of_work,
ss.notes,
```

Map them into the new initializer.

**Step 5: Run test**

Run the narrow core test command used by this repo. If unsure, start with:
```bash
swift test --package-path core --filter SchedulingServiceTests
```

Expected: new test passes.

---

## Task 2: Add SchedulingService create/update APIs for subcontractor schedule dates

**Objective:** Provide a deterministic service layer for the Add/Edit subcontractor UI.

**Files:**
- Modify: `core/Sources/WiredPartCore/Services/SchedulingService.swift` near `getSubSchedule(date:)`
- Test: same scheduling test file as Task 1.

**Step 1: Write failing create test**

Test `createSubcontractorSchedule(...)` inserts one row and `getSubSchedule(date:)` returns it for the selected date.

**Step 2: Add create API**

Add:
```swift
@discardableResult
public func createSubcontractorSchedule(
    jobId: Int64,
    gcId: Int64,
    scheduledDate: String,
    arrivalTime: String? = nil,
    departureTime: String? = nil,
    scopeOfWork: String? = nil,
    status: String = "scheduled",
    notes: String? = nil,
    createdBy: Int64? = nil
) throws -> Int64
```

Validation:
- throw `SchedulingError.requiredFieldEmpty` if `scheduledDate` is blank.
- verify job exists and is not deleted; reuse `SchedulingError.jobNotFound(jobId)`.
- add a new error only if there is already a general contractor error pattern; otherwise throw `requiredFieldEmpty` for missing/invalid `gcId` in first slice.
- insert into `subcontractor_schedules` with timestamps.

**Step 3: Write failing update test**

Create a subcontractor schedule, update date/time/scope/status/notes, assert old date no longer returns it and new date returns updated details.

**Step 4: Add update API**

Add:
```swift
public func updateSubcontractorSchedule(
    id: Int64,
    scheduledDate: String,
    arrivalTime: String? = nil,
    departureTime: String? = nil,
    scopeOfWork: String? = nil,
    status: String = "scheduled",
    notes: String? = nil
) throws
```

Keep it narrow: date/time/scope/status/notes only. Do not change job or GC in this first slice unless UI requires it.

**Step 5: Run tests**

Run:
```bash
swift test --package-path core --filter SchedulingServiceTests
```

Expected: create and update tests pass.

---

## Task 3: Show subcontractor arrival details in IOSSubSchedulePage

**Objective:** Make GH #612 visible immediately after service work.

**Files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSubSchedulePage.swift:122-149`

**Step 1: Update row display**

In `subRow(_:)`, after the date label, add:
```swift
if let arrival = row.arrivalTime, !arrival.isEmpty {
    let timeText = [row.arrivalTime, row.departureTime]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
    Label(timeText, systemImage: "clock")
        .font(.caption)
        .foregroundStyle(.tertiary)
}
if let scope = row.scopeOfWork, !scope.isEmpty {
    Label(scope, systemImage: "list.clipboard")
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(2)
}
```

**Step 2: Update help text**

Mention exact scheduled dates and optional arrival/departure times.

**Step 3: Build iOS target**

Run the existing iOS build command documented in repo scripts/CI. If unknown, inspect package/project commands first, then run the narrowest compile check available.

Expected: no compile errors from the new row fields.

---

## Task 4: Add CreateSubcontractorScheduleSheet

**Objective:** Let users accurately add the date subcontractors will show up.

**Files:**
- Create: `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/CreateSubcontractorScheduleSheet.swift`
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSSubSchedulePage.swift`
- May need to read existing services for list methods:
  - `core/Sources/WiredPartCore/Services/JobsService.swift`
  - `core/Sources/WiredPartCore/Services/PeopleService.swift` or whatever service lists GCs/subcontractors.

**Step 1: Discover existing GC/subcontractor list API**

Search:
```bash
grep -R "general_contractors\|GeneralContractor\|list.*Contract" -n core/Sources "Weird Parts IOS/Weird Parts IOS" | head -80
```

Use an existing list method if present. If no list method exists, add a minimal service method in the correct service rather than raw SQL in SwiftUI.

**Step 2: Create sheet UI**

Fields:
- Job picker (active/scheduled/pending jobs are acceptable; active only is okay for first slice if reusing `JobsService.listJobs`).
- Subcontractor/GC picker.
- DatePicker for scheduled date, defaulting to `selectedDate`.
- Optional arrival time text field.
- Optional departure time text field.
- Optional scope of work text editor.
- Status picker with `scheduled`, `confirmed`, `completed`, `cancelled`.
- Optional notes text editor.

**Step 3: Save through service**

Call `SchedulingService.createSubcontractorSchedule(...)` and refresh parent list on save.

**Step 4: Add toolbar button**

In `IOSSubSchedulePage`, extend `ActiveSheet` to support `.create` and add a plus toolbar button.

**Step 5: Build**

Run iOS compile check.

Expected: Add sheet compiles and creates visible rows for the selected date.

---

## Task 5: Add rolling 14-day planning mode to IOSScheduleCalendarPage

**Objective:** Implement the highest-value part of GH #610.

**Files:**
- Modify: `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSScheduleCalendarPage.swift`
- Potentially add helper subview in same file first; split later only if file grows too large.

**Step 1: Extend mode enum**

Change:
```swift
enum CalendarMode: String, CaseIterable {
    case fourteenDays = "14 Days"
    case week = "Week"
    case month = "Month"
}
```

Set default:
```swift
@State private var calendarMode: CalendarMode = .fourteenDays
```

**Step 2: Add range helpers**

Add:
```swift
private var fourteenDayStartDate: Date {
    calendar.startOfDay(for: selectedDate)
}

private var fourteenDayEndDate: Date {
    calendar.date(byAdding: .day, value: 13, to: fourteenDayStartDate) ?? fourteenDayStartDate
}

private var fourteenDayStart: String {
    Formatters.iso8601DateOnly.string(from: fourteenDayStartDate)
}

private var fourteenDayEnd: String {
    Formatters.iso8601DateOnly.string(from: fourteenDayEndDate)
}
```

**Step 3: Render a 14-day list grouped by date**

For first slice, reuse `entries = getMySchedule(userId:startDate:endDate)` and group client-side by `entry.date`.

Suggested UI:
- Header: `Today - <end date>`.
- Buttons: previous 14 days, Today, next 14 days.
- List sections for each date in the 14-day range.
- Empty day rows should say `No scheduled work` so planning gaps are visible.

**Step 4: Update loadData**

When `.fourteenDays`, call `getMySchedule(userId:startDate:fourteenDayStart,endDate:fourteenDayEnd)`.

**Step 5: Update help text**

Explain that 14 Days is the default planning preview and Month is for lower-detail overview.

**Step 6: Build**

Run iOS compile check.

Expected: Scheduling page opens to a rolling 14-day planning preview.

---

## Task 6: Add optional all-crew planning preview after first slice

**Objective:** Decide whether "planning preview" should show only current user or all crew.

**Files:**
- `SchedulingService.swift`
- `IOSScheduleCalendarPage.swift`

**Decision needed:** The current `IOSScheduleCalendarPage` title is "My Schedule" and `getMySchedule` filters to current user. GH #610 wording sounds like company planning, not personal schedule. After the first 14-day UI lands, evaluate whether to add a segmented filter: `Mine | Crew | Subs`.

Implementation if approved:
- Add `getScheduleEntries(startDate:endDate:)` that returns all users for a date range, based on `getScheduleEntriesForDate(date:)` SQL.
- Add a mode/filter in the UI.
- Keep permissions in mind: only users with `view_schedule`/`manage_schedule` should see all crew.

---

## Task 7: Paperclip/GitHub routing

**Objective:** Keep implementation work moving without overloading one issue.

Create two Paperclip child issues under WEI-1939:

1. Frontend-focused:
   - Title: `Implement GH#610 rolling 14-day scheduling preview`
   - Assignee: FrontendCoder
   - Acceptance: Task 5 and iOS build pass.
2. Backend + UI slice:
   - Title: `Implement GH#612 subcontractor scheduled-date add/edit flow`
   - Assignee: BackendCoder or CTO-directed engineer
   - Acceptance: Tasks 1-4 and core tests pass.

Add GitHub comments on #610 and #612 once implementation starts, linking the Paperclip child issue identifiers.

---

## Verification Checklist

- `swift test --package-path core --filter SchedulingServiceTests` passes.
- iOS compile check passes with `IOSScheduleCalendarPage.swift`, `IOSSubSchedulePage.swift`, and new sheet.
- Manual smoke path:
  1. Open Scheduling Calendar.
  2. Confirm default mode is 14 Days.
  3. Confirm today plus 13 more days are visible.
  4. Navigate next/previous windows and back to Today.
  5. Open Sub Schedule.
  6. Add a subcontractor schedule for a chosen date with arrival time and scope.
  7. Confirm the row appears on that date and not on adjacent dates.

## Risks / Watchouts

- The repo currently may have unrelated uncommitted work on another branch. Do not mix implementation commits for GH #610/#612 with unrelated branch changes.
- Use existing service methods for jobs and subcontractors; do not query SQLite directly from SwiftUI.
- Keep date formatting consistent with existing `Formatters.localDateFormatter` / `Formatters.iso8601DateOnly` usage.
- Do not remove Month view; user explicitly asked for month view options, only lower priority.
- If no GC list service exists, add the smallest reusable service API and test it rather than hard-coding picker data.
