# 60A — Standard Date Filter Bar
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

The app has ZERO date filtering on any page. There is an existing `ReportDateRange` enum in `Weird Parts IOS/Weird Parts IOS/Features/Reports/ReportDateRange.swift` with basic date ranges, but no UI component uses it, and it lacks "Last Period", "This Period", and "Custom" options. This prompt creates a reusable `StandardFilterBar` SwiftUI component and wires it into every page that shows date-relevant data.

## Task

### Step 1: Extend ReportDateRange

In `Weird Parts IOS/Weird Parts IOS/Features/Reports/ReportDateRange.swift`, replace the entire file with:

```swift
import Foundation

/// Shared date range options for all time-based filtering.
enum ReportDateRange: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisPeriod = "This Period"
    case lastPeriod = "Last Period"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "This Quarter"
    case thisYear = "This Year"
    case custom = "Custom"

    var id: String { rawValue }

    /// Returns (startDate, endDate) for non-custom ranges.
    /// For `.custom`, returns nil — the caller supplies custom dates.
    var dateInterval: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, now)
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: now)!
            let interval = cal.dateInterval(of: .weekOfYear, for: lastWeek)!
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .thisPeriod:
            // Pay period = bi-weekly, anchored to Jan 1 of current year
            let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
            let days = cal.dateComponents([.day], from: yearStart, to: now).day ?? 0
            let periodIndex = days / 14
            let periodStart = cal.date(byAdding: .day, value: periodIndex * 14, to: yearStart)!
            return (periodStart, now)
        case .lastPeriod:
            let yearStart = cal.date(from: cal.dateComponents([.year], from: now))!
            let days = cal.dateComponents([.day], from: yearStart, to: now).day ?? 0
            let periodIndex = days / 14
            let periodStart = cal.date(byAdding: .day, value: (periodIndex - 1) * 14, to: yearStart)!
            let periodEnd = cal.date(byAdding: .day, value: periodIndex * 14 - 1, to: yearStart)!
            return (periodStart, periodEnd)
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return (start, now)
        case .lastMonth:
            let lastMonth = cal.date(byAdding: .month, value: -1, to: now)!
            let start = cal.date(from: cal.dateComponents([.year, .month], from: lastMonth))!
            let end = cal.date(byAdding: .day, value: -1,
                               to: cal.date(from: cal.dateComponents([.year, .month], from: now))!)!
            return (start, end)
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let quarterStart = ((month - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: quarterStart))!
            return (start, now)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now)))!
            return (start, now)
        case .custom:
            return nil
        }
    }
}
```

### Step 2: Create StandardFilterBar

Create a new file `Weird Parts IOS/Weird Parts IOS/Shared/StandardFilterBar.swift`:

```swift
import SwiftUI

/// Reusable horizontal date filter bar with quick-pick buttons and custom date range picker.
///
/// Usage:
/// ```
/// @State private var dateRange: ReportDateRange = .thisWeek
/// @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
/// @State private var customEnd: Date = Date()
///
/// StandardFilterBar(
///     selectedRange: $dateRange,
///     customStart: $customStart,
///     customEnd: $customEnd
/// )
/// ```
///
/// Read the effective dates via `effectiveStart` and `effectiveEnd`:
/// ```
/// var effectiveStart: Date {
///     dateRange.dateInterval?.start ?? customStart
/// }
/// var effectiveEnd: Date {
///     dateRange.dateInterval?.end ?? customEnd
/// }
/// ```
struct StandardFilterBar: View {
    @Binding var selectedRange: ReportDateRange
    @Binding var customStart: Date
    @Binding var customEnd: Date

    /// Which quick buttons to show. Defaults to the most common set.
    var quickOptions: [ReportDateRange] = [.thisWeek, .lastWeek, .thisPeriod, .lastPeriod, .thisMonth, .custom]

    @State private var showCustomPicker = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickOptions) { option in
                        Button {
                            selectedRange = option
                            if option == .custom {
                                showCustomPicker = true
                            }
                        } label: {
                            Text(option.rawValue)
                                .font(.caption)
                                .fontWeight(selectedRange == option ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selectedRange == option ? Color.accentColor : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(selectedRange == option ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Custom date pickers — only show when Custom is selected
            if selectedRange == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedRange)
    }
}
```

### Step 3: Add StandardFilterBar to date-relevant pages

For each page below, add three `@State` properties at the top and insert `StandardFilterBar(...)` as the first child inside the main VStack/List, right below the navigation title area. Then pass the effective start/end dates to the `loadData()` call so the query is filtered.

**Pattern to add to each page:**

```swift
// Add these @State properties:
@State private var dateRange: ReportDateRange = .thisWeek
@State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
@State private var customEnd: Date = Date()

// Add this computed property:
private var effectiveStart: Date { dateRange.dateInterval?.start ?? customStart }
private var effectiveEnd: Date { dateRange.dateInterval?.end ?? customEnd }

// Insert the bar in the view body, above the list/content:
StandardFilterBar(selectedRange: $dateRange, customStart: $customStart, customEnd: $customEnd)

// Add .onChange to reload when dates change:
.onChange(of: dateRange) { loadData() }
.onChange(of: customStart) { loadData() }
.onChange(of: customEnd) { loadData() }
```

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Reports/ReportDateRange.swift` — extend enum
2. `Weird Parts IOS/Weird Parts IOS/Shared/StandardFilterBar.swift` — **CREATE** new file
3. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSLaborOverviewPage.swift` — add filter bar
4. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSSpendingPage.swift` — add filter bar
5. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSProfitabilityPage.swift` — add filter bar
6. `Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSDailyReportsSummaryPage.swift` — add filter bar
7. `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSSpendingDashboardPage.swift` — add filter bar
8. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/LaborPage.swift` — add filter bar (job labor hours)
9. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobReportsPage.swift` — add filter bar
10. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSClockPage.swift` — add filter bar (clock history)
11. `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/WarehouseMovementsPage.swift` — add filter bar
12. `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPurchaseOrdersPage.swift` — add filter bar
13. `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSMileagePage.swift` — add filter bar
14. `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSFuelPage.swift` — add filter bar
15. `Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSMaintenancePage.swift` — add filter bar
16. `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSTimeOffPage.swift` — add filter bar

## Success Criteria

- [ ] `StandardFilterBar` compiles and renders a horizontal scrolling chip bar
- [ ] Tapping "Custom" shows inline DatePickers for start/end
- [ ] ReportDateRange includes `.thisPeriod`, `.lastPeriod`, `.custom` cases
- [ ] At least 14 pages now show the filter bar at the top of their content
- [ ] Changing the date range triggers `loadData()` on each page
- [ ] Filter bar scrolls horizontally without clipping on iPhone SE width (375pt)
