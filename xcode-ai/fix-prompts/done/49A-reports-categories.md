# 49A — Reports Categories Reorganization

> **Chain position:** **49A** → 49B → 49C → 49D
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read the existing Reports router and all report pages. Reorganize from a flat tab layout into categorized sections: Labor, Financial, Fleet, Warehouse, Scheduling, Custom, Shared.

## Context

The Reports module currently uses flat tabs. As we add Fleet, Warehouse, and Scheduling reports (49C), plus a report builder (49D), the flat structure won't scale. Reorganize into categories with a category picker at the top. Each category expands to show its sub-pages. This also prepares for custom/saved reports from 49D.

## Task

### Step 1: Category Model

```swift
enum ReportCategory: String, CaseIterable {
    case labor = "Labor"
    case financial = "Financial"
    case fleet = "Fleet"
    case warehouse = "Warehouse"
    case scheduling = "Scheduling"
    case custom = "Custom"
    case shared = "Shared"

    var icon: String {
        switch self {
        case .labor: return "clock.fill"
        case .financial: return "dollarsign.circle.fill"
        case .fleet: return "car.fill"
        case .warehouse: return "building.2.fill"
        case .scheduling: return "calendar"
        case .custom: return "slider.horizontal.3"
        case .shared: return "person.2.fill"
        }
    }

    var color: Color {
        switch self {
        case .labor: return .blue
        case .financial: return .green
        case .fleet: return .orange
        case .warehouse: return .purple
        case .scheduling: return .cyan
        case .custom: return .indigo
        case .shared: return .pink
        }
    }
}
```

### Step 2: Reports Router Redesign

```swift
struct IOSReportsRouter: View {
    @EnvironmentObject var appCore: AppCore
    @State private var selectedCategory: ReportCategory = .labor

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleCategories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: category.icon)
                                    Text(category.rawValue)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(selectedCategory == category
                                           ? category.color.opacity(0.2) : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    selectedCategory == category ? category.color : .secondary.opacity(0.3)
                                ))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                // Category content
                categoryContent
            }
            .navigationTitle("Reports")
        }
    }

    var visibleCategories: [ReportCategory] {
        var cats = ReportCategory.allCases
        if !appCore.hasPermission("view_financials") {
            cats.removeAll { $0 == .financial }
        }
        if !appCore.hasPermission("view_fleet_financials") {
            cats.removeAll { $0 == .fleet }
        }
        return cats
    }

    @ViewBuilder
    var categoryContent: some View {
        switch selectedCategory {
        case .labor:
            LaborReportsView()
        case .financial:
            FinancialReportsView()
        case .fleet:
            FleetReportsView()
        case .warehouse:
            WarehouseReportsView()
        case .scheduling:
            SchedulingReportsView()
        case .custom:
            CustomReportsView()
        case .shared:
            SharedReportsView()
        }
    }
}
```

### Step 3: Labor Reports (Existing, Reorganized)

```swift
struct LaborReportsView: View {
    var body: some View {
        List {
            NavigationLink("Daily Hours Summary") {
                IOSDailyReportPage()
            }
            NavigationLink("Timesheet Report") {
                IOSTimesheetReportPage()
            }
            NavigationLink("Period Report") {
                IOSPeriodReportPage()
            }
            NavigationLink("Pre-Billing Export") {
                IOSPreBillingPage()
            }
            NavigationLink("Bookkeeper Export") {
                IOSBookkeeperExportPage()
            }
        }
    }
}
```

### Step 4: Financial Reports (Existing, Reorganized)

```swift
struct FinancialReportsView: View {
    var body: some View {
        List {
            NavigationLink("Job Cost Summary") {
                IOSJobCostReportPage()
            }
            NavigationLink("Spending Dashboard") {
                IOSSpendingDashboardPage()
            }
            NavigationLink("Budget vs Actual") {
                IOSBudgetReportPage()
            }
        }
    }
}
```

### Step 5: Placeholder Views for New Categories

```swift
// Fleet, Warehouse, Scheduling — populated in 49C
struct FleetReportsView: View {
    var body: some View {
        List {
            Text("Fleet reports coming in prompt 49C")
                .foregroundStyle(.secondary)
        }
    }
}

struct WarehouseReportsView: View {
    var body: some View {
        List {
            Text("Warehouse reports coming in prompt 49C")
                .foregroundStyle(.secondary)
        }
    }
}

struct SchedulingReportsView: View {
    var body: some View {
        List {
            Text("Scheduling reports coming in prompt 49C")
                .foregroundStyle(.secondary)
        }
    }
}

// Custom — populated in 49D
struct CustomReportsView: View {
    var body: some View {
        List {
            Text("Custom report builder coming in prompt 49D")
                .foregroundStyle(.secondary)
        }
    }
}

// Shared reports
struct SharedReportsView: View {
    @State private var sharedReports: [SavedReport] = []

    var body: some View {
        List {
            if sharedReports.isEmpty {
                Text("No shared reports yet").foregroundStyle(.secondary)
            } else {
                ForEach(sharedReports) { report in
                    NavigationLink(report.name) {
                        // Run saved report
                    }
                }
            }
        }
    }
}
```

## Important Notes
- Category picker is a horizontally scrollable capsule bar (not tabs, not segmented control)
- Financial category hidden without view_financials permission
- Fleet category hidden without view_fleet_financials permission
- Existing report pages move into their respective categories but remain unchanged
- Custom and Shared categories are placeholders until 49D
- Each category is a separate view that can be independently loaded

## Success Criteria
- [ ] 7 report categories with icons and colors
- [ ] Horizontal scrollable category picker
- [ ] Labor: 5 existing report pages reorganized
- [ ] Financial: 3 existing report pages (hat-gated)
- [ ] Fleet/Warehouse/Scheduling: placeholder views for 49C
- [ ] Custom: placeholder view for 49D
- [ ] Shared: list of shared saved reports
- [ ] Permission-gated categories
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 49A Results (YYYY-MM-DD)
- Reports reorganized into 7 categories
- Category picker with permission gating
- Existing reports moved to Labor + Financial
- Placeholder views for Fleet/Warehouse/Scheduling/Custom
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 49B.**
