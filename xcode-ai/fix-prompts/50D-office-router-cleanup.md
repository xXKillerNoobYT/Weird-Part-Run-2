# 50D — Office Router Cleanup

> **Chain position:** 50A → 50B → 50C → **50D**
> **Prerequisite:** 50A-50C (dashboard, approvals, chat)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards
4. Use ActiveSheet enum for all sheets
5. Fix ALL silent guard returns — show errors in UI

## Instructions

**IMPORTANT:** Before implementing, read `IOSOfficeRouter.swift` and understand the current tab structure. Remove report page routes (moved to Reports section in 49A). Add new Office tabs: Dashboard, Approvals, Pipeline, Teams, Custom Reports. Update tab ordering.

## Context

The Office router previously included report pages. Since 49A moved all reports to the Reports module, those routes should be removed from Office. Replace them with new tabs: Dashboard (50A), Approvals (50B), Pipeline (scheduling pipeline link), Teams (team management), and Custom Reports (link to report builder). The old Deletion Approvals page is now folded into Unified Approvals (50B).

## Task

### Step 1: Update Router Tabs

```swift
struct IOSOfficeRouter: View {
    @EnvironmentObject var appCore: AppCore
    @State private var selectedTab: OfficeTab = .dashboard

    enum OfficeTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case approvals = "Approvals"
        case pipeline = "Pipeline"
        case teams = "Teams"
        case reports = "Reports"

        var icon: String {
            switch self {
            case .dashboard: return "gauge.with.dots.needle.50percent"
            case .approvals: return "checkmark.seal.fill"
            case .pipeline: return "chart.bar.xaxis"
            case .teams: return "person.3.fill"
            case .reports: return "chart.pie.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(OfficeTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.rawValue, systemImage: tab.icon)
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(selectedTab == tab
                                           ? Color.blue.opacity(0.15) : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            // Tab content
            switch selectedTab {
            case .dashboard:
                IOSOfficeDashboardPage()
            case .approvals:
                IOSUnifiedApprovalsPage()
            case .pipeline:
                pipelineView
            case .teams:
                teamsView
            case .reports:
                reportsLinkView
            }
        }
        .navigationTitle("Office")
    }
}
```

### Step 2: Remove Old Report Routes

```swift
// REMOVE these from the Office router:
// - IOSDailyReportPage (now in Reports > Labor)
// - IOSTimesheetReportPage (now in Reports > Labor)
// - IOSPeriodReportPage (now in Reports > Labor)
// - IOSPreBillingPage (now in Reports > Labor)
// - IOSBookkeeperExportPage (now in Reports > Labor)
// - IOSJobCostReportPage (now in Reports > Financial)
// - IOSSpendingDashboardPage (now in Reports > Financial)
// - IOSBudgetReportPage (now in Reports > Financial)
// - IOSDeletionApprovalsPage (now in Unified Approvals)

// These pages still exist — they're just accessed via the Reports module now
```

### Step 3: Pipeline Tab (Link to Scheduling)

```swift
var pipelineView: some View {
    List {
        NavigationLink {
            // Navigate to scheduling pipeline (46C/46D)
        } label: {
            HStack {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Short-Term Pipeline").font(.subheadline)
                    Text("Jobs ready to schedule").font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        NavigationLink {
            // Navigate to long-term pipeline (46D)
        } label: {
            HStack {
                Image(systemName: "calendar.badge.clock").foregroundStyle(.purple)
                VStack(alignment: .leading) {
                    Text("Long-Term Pipeline").font(.subheadline)
                    Text("3-year timeline view").font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        NavigationLink {
            // Navigate to dispatch board (46B)
        } label: {
            HStack {
                Image(systemName: "person.3.sequence.fill").foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("Dispatch Board").font(.subheadline)
                    Text("Assign crews to jobs").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

### Step 4: Teams Tab

```swift
var teamsView: some View {
    // Navigate to Teams page from People module
    IOSTeamsPage()
}
```

### Step 5: Reports Link Tab

```swift
var reportsLinkView: some View {
    List {
        Section {
            NavigationLink {
                // Navigate to Report Builder (49D)
                ReportBuilderView()
            } label: {
                Label("Build Custom Report", systemImage: "slider.horizontal.3")
            }
        }

        Section("Quick Links") {
            NavigationLink("Labor Reports") {
                LaborReportsView()
            }
            NavigationLink("Financial Reports") {
                FinancialReportsView()
            }
            NavigationLink("Fleet Reports") {
                FleetReportsView()
            }
        }

        Section {
            Text("Full reports available in the Reports module")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

## Important Notes
- REMOVE all report page routes from Office — they live in the Reports module now
- REMOVE IOSDeletionApprovalsPage route — it's now part of Unified Approvals (50B)
- New tab order: Dashboard, Approvals, Pipeline, Teams, Reports
- Pipeline tab is a link hub to scheduling pages (not a full pipeline implementation here)
- Teams tab embeds the existing IOSTeamsPage
- Reports tab provides quick links to the Reports module + custom report builder
- Tab picker is horizontal scrollable (same pattern as other routers)

## Success Criteria
- [ ] Removed report page routes from Office router
- [ ] Removed standalone Deletion Approvals route
- [ ] 5 new tabs: Dashboard, Approvals, Pipeline, Teams, Reports
- [ ] Dashboard tab uses IOSOfficeDashboardPage (50A)
- [ ] Approvals tab uses IOSUnifiedApprovalsPage (50B)
- [ ] Pipeline tab has links to scheduling pages
- [ ] Teams tab embeds IOSTeamsPage
- [ ] Reports tab has custom report builder link + quick links
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 50D Results (YYYY-MM-DD)
- Office router: removed report routes, added 5 new tabs
- Dashboard, Approvals, Pipeline, Teams, Reports
- Clean separation from Reports module
- Build: PASS/FAIL
```

**Office module complete. Proceed to Cross-Cutting prompt (51A).**
