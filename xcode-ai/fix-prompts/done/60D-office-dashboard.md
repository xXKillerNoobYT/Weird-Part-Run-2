# 60D — Office Dashboard
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

`IOSOfficeDashboardPage` already exists at `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSOfficeDashboardPage.swift` and is already wired as the first tab in `OfficeRouter` (case `"office-dashboard"`). The page has basic sections (AI briefing, attention items, schedule, financials, background tasks) but needs polish and missing features. This prompt improves it to match the design spec: better visual hierarchy, quick actions, and proper error handling.

## Task

### Step 1: Add Quick Actions section

The current page has no quick actions. Add a quick actions section between `scheduleSection` and `financialSection`:

```swift
// MARK: - Quick Actions Section

@ViewBuilder
private var quickActionsSection: some View {
    Section("Quick Actions") {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            quickActionButton("Review JPOs", icon: "cart.badge.questionmark", color: .blue) {
                // Navigate to office-approvals tab
            }
            quickActionButton("Manage Jobs", icon: "briefcase.fill", color: .green) {
                // Navigate to office-manage-jobs tab
            }
            quickActionButton("View Reports", icon: "chart.bar.fill", color: .purple) {
                // Navigate to office-reports tab
            }
            quickActionButton("Dispatch Board", icon: "person.3.sequence.fill", color: .orange) {
                // Navigate to office-pipeline tab
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

private func quickActionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
}
```

### Step 2: Add help button to toolbar

Add a toolbar help button:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { activeSheet = .help } label: {
            Image(systemName: "questionmark.circle")
        }
    }
}
```

Add `case help` to the `ActiveSheet` enum (you will need to create the enum if it doesn't exist):

```swift
private enum ActiveSheet: Identifiable {
    case help
    var id: String { String(describing: self) }
}
@State private var activeSheet: ActiveSheet?
```

Add the sheet modifier:

```swift
.sheet(item: $activeSheet) { sheet in
    switch sheet {
    case .help:
        PageHelpSheet(
            title: "Office Dashboard Help",
            sections: [
                ("Daily Briefing", "AI-generated summary of today's key items. Refreshes every hour. Pull down to get a new briefing."),
                ("Needs Your Attention", "Priority-colored items that need action — approvals, overdue tasks, alerts. Red = overdue, orange = high priority."),
                ("Today's Schedule", "Who is scheduled to work today and on which jobs."),
                ("Financial Snapshot", "Week-over-week and month-over-month spending comparison. Only visible to users with financial permissions."),
                ("Quick Actions", "Shortcut buttons to the most common office management tasks.")
            ]
        )
    }
}
```

### Step 3: Improve the attention items to be tappable

Each attention item should be wrapped in a `NavigationLink` or `Button` that navigates to the relevant entity. The `DashboardService.AttentionItem` should already have a `route` or `entityType`/`entityId` — if it does, wire navigation. If it doesn't, make the items tappable with a TODO comment noting future navigation wiring.

### Step 4: Add the quick actions section call

In the `body` property, add `quickActionsSection` between `scheduleSection` and the financial section conditional:

```swift
} else {
    aiSummarySection
    attentionSection
    scheduleSection
    quickActionsSection          // <-- ADD THIS
    if appCore.hasPermission("view_financials") {
        financialSection
    }
    backgroundTasksSection
}
```

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Office/IOSOfficeDashboardPage.swift` — add quick actions, help button, improve attention items

## Success Criteria

- [ ] Office Dashboard shows 5 sections: AI Briefing, Attention, Schedule, Quick Actions, Financials (if permitted), Background Tasks
- [ ] Quick Actions section has 4 buttons in a 2-column grid
- [ ] Help button is visible in the toolbar (not hidden in overflow)
- [ ] Attention items show priority-colored icons (green/yellow/orange/red)
- [ ] Financial section only appears for users with `view_financials` permission
- [ ] Pull-to-refresh reloads all sections
- [ ] No compilation errors
