# 46A — Scheduling Calendar Month View

> **Chain position:** **46A** → 46B
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSScheduleCalendarPage.swift` and `SchedulingService.swift`. Add month view alongside existing week view, day detail on tap, and half-day scheduling support.

## Context

The schedule calendar currently only shows a week view. Managers need a month overview to see the big picture — which days are busy, which have gaps. Tapping a day shows detail. Half-day scheduling (AM/PM split) enables more flexible dispatch where workers do one job in the morning and another in the afternoon.

## Task

### Step 1: Month View

```swift
@State private var calendarMode: CalendarMode = .week
@State private var selectedDate: Date = Date()
@State private var monthScheduleData: [Date: DayScheduleSummary] = [:]

enum CalendarMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
}

// Mode picker
Picker("View", selection: $calendarMode) {
    ForEach(CalendarMode.allCases, id: \.self) { mode in
        Text(mode.rawValue).tag(mode)
    }
}
.pickerStyle(.segmented)
.padding(.horizontal)

// Month grid
if calendarMode == .month {
    monthView
} else {
    weekView  // existing week view
}

var monthView: some View {
    VStack(spacing: 0) {
        // Month/year header with navigation
        HStack {
            Button { previousMonth() } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(selectedDate, format: .dateTime.month(.wide).year())
                .font(.headline)
            Spacer()
            Button { nextMonth() } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()

        // Day-of-week headers
        HStack {
            ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                Text(day)
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)

        // Calendar grid
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(daysInMonth(), id: \.self) { date in
                DayCell(
                    date: date,
                    isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                    isToday: Calendar.current.isDateInToday(date),
                    isCurrentMonth: Calendar.current.isDate(date, equalTo: selectedDate, toGranularity: .month),
                    summary: monthScheduleData[date]
                )
                .onTapGesture {
                    selectedDate = date
                }
            }
        }
        .padding(.horizontal)
    }
}
```

### Step 2: Day Cell with Indicators

```swift
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    let summary: DayScheduleSummary?

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isCurrentMonth ? .primary : .tertiary)

            // Dots for scheduled work
            if let summary = summary {
                HStack(spacing: 2) {
                    if summary.amCount > 0 {
                        Circle()
                            .fill(.blue)
                            .frame(width: 5, height: 5)
                    }
                    if summary.pmCount > 0 {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                    }
                    if summary.fullDayCount > 0 {
                        Circle()
                            .fill(.orange)
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.2) : isToday ? Color.blue.opacity(0.05) : Color.clear)
        )
    }
}

struct DayScheduleSummary: Sendable {
    let date: Date
    let amCount: Int      // workers scheduled for AM
    let pmCount: Int      // workers scheduled for PM
    let fullDayCount: Int // workers scheduled full day
    let totalWorkers: Int
    let timeOffCount: Int
}
```

### Step 3: Day Detail on Tap

```swift
// Below the calendar, show selected day detail
if let summary = monthScheduleData[selectedDate] {
    Section {
        // AM assignments
        if summary.amCount > 0 {
            DisclosureGroup("AM (\(summary.amCount))") {
                ForEach(amEntries) { entry in
                    ScheduleEntryRow(entry: entry)
                }
            }
        }
        // PM assignments
        if summary.pmCount > 0 {
            DisclosureGroup("PM (\(summary.pmCount))") {
                ForEach(pmEntries) { entry in
                    ScheduleEntryRow(entry: entry)
                }
            }
        }
        // Full day
        ForEach(fullDayEntries) { entry in
            ScheduleEntryRow(entry: entry)
        }
        // Time off
        if summary.timeOffCount > 0 {
            ForEach(timeOffEntries) { entry in
                HStack {
                    Image(systemName: "moon.fill").foregroundStyle(.orange)
                    Text(entry.employeeName)
                    Spacer()
                    Text("Time Off").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    } header: {
        Text(selectedDate, format: .dateTime.weekday(.wide).month().day())
    }
} else {
    Section {
        Text("No schedule for this day").foregroundStyle(.secondary)
    }
}
```

### Step 4: Half-Day Scheduling

```swift
// Migration: add time_slot to schedule_entries
try db.alter(table: "schedule_entries") { t in
    t.add(column: "time_slot", .text).defaults(to: "full")
    // Values: "full", "am", "pm"
}

// Service method
func getMonthScheduleSummary(year: Int, month: Int) async throws -> [Date: DayScheduleSummary]

func createHalfDayEntry(
    employeeId: Int64, jobId: Int64, date: Date, timeSlot: String  // "am" or "pm"
) async throws -> ScheduleEntry
```

### Step 5: Update CreateScheduleEntrySheet

Add time slot picker:

```swift
// In the create schedule entry form:
Picker("Time Slot", selection: $timeSlot) {
    Text("Full Day").tag("full")
    Text("AM Only").tag("am")
    Text("PM Only").tag("pm")
}
.pickerStyle(.segmented)
```

## Important Notes
- Month view calendar uses LazyVGrid for 7-column layout
- Dots indicate AM (blue), PM (green), Full Day (orange) assignments
- Tapping a date shows detail below the calendar (not a sheet)
- Half-day scheduling adds "am"/"pm" to existing schedule entry model
- Previous/next month buttons navigate the calendar
- Today is highlighted with subtle background
- Selected date has blue background
- Days outside current month are dimmed

## Success Criteria
- [ ] Month view with 7-column calendar grid
- [ ] Week/Month toggle (segmented control)
- [ ] Dots/badges on days with scheduled work
- [ ] Tap day shows detail (AM/PM/Full Day sections)
- [ ] Half-day scheduling (AM/PM split) migration + service
- [ ] Time slot picker in create schedule entry
- [ ] Month navigation (previous/next)
- [ ] Today highlighting
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 46A Results (YYYY-MM-DD)
- Month view calendar grid
- Day detail on tap
- Half-day scheduling: migration + service + UI
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 46B.**
