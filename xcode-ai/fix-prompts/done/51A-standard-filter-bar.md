# 51A — Standard Filter Bar

> **Chain position:** **51A** (cross-cutting — apply after other prompts)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read several pages that currently use date filtering (reports, scheduling, fleet, etc.). Create a reusable `StandardFilterBar` component with quick date filters, custom date range picker, and page-specific additional filters. Then apply it to ALL pages that have date-relevant data.

## Context

Many pages across the app need date filtering but each implements it differently (or not at all). A standard filter bar provides consistency: quick filters for common time ranges (This Week, Last Week, This Period, Last Period, This Month, Custom), a custom date range picker, and a slot for page-specific additional filters (Job, Employee, Vehicle, Supplier, Status). This is a cross-cutting component that should be used everywhere dates matter.

## Task

### Step 1: StandardFilterBar Component

```swift
struct StandardFilterBar<AdditionalFilters: View>: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var selectedQuickFilter: QuickFilter = .thisWeek
    @State private var showCustomRange = false
    let additionalFilters: () -> AdditionalFilters

    enum QuickFilter: String, CaseIterable {
        case thisWeek = "This Week"
        case lastWeek = "Last Week"
        case thisPeriod = "This Period"
        case lastPeriod = "Last Period"
        case thisMonth = "This Month"
        case custom = "Custom"
    }

    init(
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        @ViewBuilder additionalFilters: @escaping () -> AdditionalFilters = { EmptyView() }
    ) {
        self._startDate = startDate
        self._endDate = endDate
        self.additionalFilters = additionalFilters
    }

    var body: some View {
        VStack(spacing: 8) {
            // Quick filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickFilter.allCases, id: \.self) { filter in
                        Button {
                            selectedQuickFilter = filter
                            if filter == .custom {
                                showCustomRange = true
                            } else {
                                applyQuickFilter(filter)
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(selectedQuickFilter == filter
                                           ? Color.blue.opacity(0.2) : Color(.systemGray6))
                                .foregroundStyle(selectedQuickFilter == filter ? .blue : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Custom date range (expandable)
            if showCustomRange {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From").font(.caption2).foregroundStyle(.secondary)
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("To").font(.caption2).foregroundStyle(.secondary)
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    Button {
                        showCustomRange = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            // Additional filters slot
            additionalFilters()
        }
        .padding(.vertical, 4)
    }

    func applyQuickFilter(_ filter: QuickFilter) {
        let cal = Calendar.current
        switch filter {
        case .thisWeek:
            let interval = cal.dateInterval(of: .weekOfYear, for: Date())!
            startDate = interval.start
            endDate = Date()
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: Date())!
            let interval = cal.dateInterval(of: .weekOfYear, for: lastWeek)!
            startDate = interval.start
            endDate = interval.end
        case .thisPeriod:
            // Pay period: bi-weekly, starting from a known anchor
            // Use 2-week intervals from a fixed start date
            let anchor = cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
            let daysSinceAnchor = cal.dateComponents([.day], from: anchor, to: Date()).day ?? 0
            let periodStart = daysSinceAnchor - (daysSinceAnchor % 14)
            startDate = cal.date(byAdding: .day, value: periodStart, to: anchor)!
            endDate = Date()
        case .lastPeriod:
            let anchor = cal.date(from: DateComponents(year: 2024, month: 1, day: 1))!
            let daysSinceAnchor = cal.dateComponents([.day], from: anchor, to: Date()).day ?? 0
            let currentPeriodStart = daysSinceAnchor - (daysSinceAnchor % 14)
            startDate = cal.date(byAdding: .day, value: currentPeriodStart - 14, to: anchor)!
            endDate = cal.date(byAdding: .day, value: currentPeriodStart, to: anchor)!
        case .thisMonth:
            startDate = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            endDate = Date()
        case .custom:
            break // handled by date pickers
        }
        showCustomRange = false
    }
}
```

### Step 2: Convenience Initializer (No Additional Filters)

```swift
extension StandardFilterBar where AdditionalFilters == EmptyView {
    init(startDate: Binding<Date>, endDate: Binding<Date>) {
        self._startDate = startDate
        self._endDate = endDate
        self.additionalFilters = { EmptyView() }
    }
}
```

### Step 3: Page-Specific Filter Examples

```swift
// Example: Labor report with employee + job filters
struct LaborReportFilters: View {
    @Binding var selectedEmployeeId: Int64?
    @Binding var selectedJobId: Int64?
    let employees: [EmployeeBasic]
    let jobs: [JobBasic]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Employee filter
                Menu {
                    Button("All Employees") { selectedEmployeeId = nil }
                    ForEach(employees, id: \.id) { emp in
                        Button(emp.fullName) { selectedEmployeeId = emp.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                        Text(selectedEmployeeId != nil
                             ? employees.first { $0.id == selectedEmployeeId }?.fullName ?? "Employee"
                             : "All Employees")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }

                // Job filter
                Menu {
                    Button("All Jobs") { selectedJobId = nil }
                    ForEach(jobs, id: \.id) { job in
                        Button(job.name) { selectedJobId = job.id }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.fill")
                        Text(selectedJobId != nil
                             ? jobs.first { $0.id == selectedJobId }?.name ?? "Job"
                             : "All Jobs")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
    }
}

// Usage in a report page:
StandardFilterBar(startDate: $startDate, endDate: $endDate) {
    LaborReportFilters(
        selectedEmployeeId: $selectedEmployeeId,
        selectedJobId: $selectedJobId,
        employees: employees,
        jobs: jobs
    )
}
```

### Step 4: Apply to All Date-Relevant Pages

```swift
// Apply StandardFilterBar to these pages:
// Reports:
// - IOSDailyReportPage
// - IOSTimesheetReportPage
// - IOSPeriodReportPage
// - IOSPreBillingPage
// - IOSBookkeeperExportPage
// - IOSJobCostReportPage
// - IOSSpendingDashboardPage
// - All new report pages from 49C

// Scheduling:
// - IOSScheduleCalendarPage (46A)
// - IOSDispatchBoardPage (46B)

// Fleet:
// - Fleet fuel/mileage/maintenance reports

// Warehouse:
// - IOSAuditPage (audit sessions by date)
// - Stock movement history

// Jobs:
// - Clock history (in job detail)
// - Daily report history

// Office:
// - Office Dashboard (date range for financial snapshot)
// - Approvals (filter by request date)

// Tools:
// - Checkout history
// - Maintenance history
// - Audit trail (47F)

// For each page:
// 1. Add @State private var startDate = default
// 2. Add @State private var endDate = Date()
// 3. Add StandardFilterBar at top of list
// 4. Filter data by startDate/endDate
// 5. Reload data on date change via .onChange
```

### Step 5: Integration Pattern

```swift
// Standard integration pattern for any page:
struct SomeDateFilteredPage: View {
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var endDate = Date()
    @State private var items: [SomeItem] = []

    var body: some View {
        List {
            StandardFilterBar(startDate: $startDate, endDate: $endDate)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            // Data rows
            ForEach(filteredItems) { item in
                // ...
            }
        }
        .onChange(of: startDate) { _, _ in Task { await loadData() } }
        .onChange(of: endDate) { _, _ in Task { await loadData() } }
        .task { await loadData() }
    }

    var filteredItems: [SomeItem] {
        items.filter { $0.date >= startDate && $0.date <= endDate }
    }
}
```

## Important Notes
- Quick filters: This Week, Last Week, This Period (bi-weekly), Last Period, This Month, Custom
- "This Period" and "Last Period" use bi-weekly pay periods anchored to Jan 1, 2024
- Custom shows inline date pickers (not a sheet — stays visible)
- Additional filters slot uses @ViewBuilder for page-specific filters
- The bar is a standalone component — pages just add it to the top of their List
- Date changes trigger .onChange to reload data
- Apply to ALL pages with date-relevant data across the entire app (20+ pages)
- Use .listRowSeparator(.hidden) and .listRowInsets(EdgeInsets()) for full-width bar

## Success Criteria
- [ ] Reusable StandardFilterBar component with generic additional filters
- [ ] 6 quick filters: This Week, Last Week, This Period, Last Period, This Month, Custom
- [ ] Custom date range with inline DatePickers
- [ ] Additional filters slot (employee, job, vehicle, supplier, status)
- [ ] Convenience initializer for pages without additional filters
- [ ] Applied to all date-relevant pages (20+ pages)
- [ ] .onChange triggers data reload on date change
- [ ] Consistent styling across all pages
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 51A Results (YYYY-MM-DD)
- StandardFilterBar component created
- 6 quick filters + custom date range
- Additional filters slot for page-specific filters
- Applied to 20+ pages across all modules
- Build: PASS/FAIL
```

**Cross-cutting filter bar complete. All prompt series 47-51 done.**
