# 45A — Jobs List Page Redesign

> **Chain position:** **45A** → 45B
> **Prerequisite:** 39A (hat permissions — view_job_financials, manage_jobs)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `JobsListPage.swift` and `JobsService.swift`. Redesign with smart cards for all job statuses, AI summary per job card, stage progression, dual progress bars, sort options, and permission-gated features.

## Context

The jobs list is the most-used page in the app. It needs smart cards for every status (Active, Warranty, Continuous, Complete, On Hold, Payment Hold, Cancelled, All), a cached AI summary note on each card, stage progression indicators, and dual progress bars for hours and budget (only when data exists). Certain statuses have special display rules: Payment Hold shows red to workers but a $ badge to managers. Continuous jobs are light gray and only visible to assigned qualified workers.

## Task

### Step 1: Smart Cards for All Statuses

```swift
@State private var statusFilter: JobStatusFilter = .active
@State private var sortOption: JobSort = .recentActivity

enum JobStatusFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case warranty = "Warranty"
    case continuous = "Continuous"
    case complete = "Complete"
    case onHold = "On Hold"
    case paymentHold = "Payment Hold"
    case cancelled = "Cancelled"
}

enum JobSort: String, CaseIterable {
    case recentActivity = "Recent Activity"
    case name = "Name"
    case startDate = "Start Date"
    case stage = "Stage"
}

ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 10) {
        ForEach(visibleFilters, id: \.self) { filter in
            SmartCard(
                title: filter.rawValue,
                count: countFor(filter),
                isActive: statusFilter == filter,
                color: colorFor(filter)
            ) {
                statusFilter = filter
            }
        }
    }
    .padding(.horizontal)
}

// Payment Hold card only visible to users with manage_jobs permission
var visibleFilters: [JobStatusFilter] {
    var filters = JobStatusFilter.allCases
    if !appCore.hasPermission("manage_jobs") {
        filters.removeAll { $0 == .paymentHold }
    }
    return filters
}
```

### Step 2: Job Card with AI Summary

```swift
struct JobListCard: View {
    let job: JobListItem
    let hasFinancialPermission: Bool
    @State private var aiSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: name + status badge
            HStack {
                Text(job.name).font(.headline)
                Spacer()
                StatusBadge(status: job.status, isPaymentHold: job.isPaymentHold,
                           hasManagePermission: hasFinancialPermission)
            }

            // Stage progression
            if let stage = job.currentStage {
                StageProgressionBar(currentStage: stage, totalStages: job.totalStages)
            }

            // AI summary (cached 1hr)
            if let summary = aiSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Dual progress bars (only if data exists)
            HStack(spacing: 16) {
                if let hoursUsed = job.hoursUsed, let hoursEstimate = job.hoursEstimate {
                    MiniProgressBar(label: "Hours", value: hoursUsed, total: hoursEstimate, color: .blue)
                }
                if hasFinancialPermission, let spent = job.budgetSpent, let budget = job.budgetTotal {
                    MiniProgressBar(label: "Budget", value: spent, total: budget, color: .green)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(job.classification == "continuous" ? 0.7 : 1.0)
        .task { await loadAISummary() }
    }

    func loadAISummary() async {
        // Check cache first (1hr TTL)
        // If expired, request AI summary
        // Cache result
    }
}
```

### Step 3: Payment Hold Display Rules

```swift
struct StatusBadge: View {
    let status: String
    let isPaymentHold: Bool
    let hasManagePermission: Bool

    var body: some View {
        if isPaymentHold {
            if hasManagePermission {
                // Managers see $ badge
                HStack(spacing: 2) {
                    Image(systemName: "dollarsign.circle.fill")
                    Text("Payment Hold")
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red)
                .clipShape(Capsule())
            } else {
                // Workers see generic hold
                Text("On Hold")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red)
                    .clipShape(Capsule())
            }
        } else {
            Text(status.capitalized)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(status))
                .clipShape(Capsule())
        }
    }
}
```

### Step 4: Continuous Job Visibility

```swift
// Continuous jobs only visible to assigned qualified workers
var filteredJobs: [JobListItem] {
    jobs.filter { job in
        if job.classification == "continuous" {
            // Only show to assigned workers or managers
            return job.isAssignedToCurrentUser || appCore.hasPermission("view_all_jobs")
        }
        return true
    }
}
```

### Step 5: Swipe Actions (Hat-Gated)

```swift
.swipeActions(edge: .trailing) {
    // AI Summary
    Button {
        Task { await showAISummary(for: job) }
    } label: {
        Label("AI Summary", systemImage: "sparkles")
    }
    .tint(.purple)

    // Status change (managers only)
    if appCore.hasPermission("manage_jobs") {
        Button {
            activeSheet = .changeStatus(job)
        } label: {
            Label("Status", systemImage: "arrow.triangle.2.circlepath")
        }
        .tint(.blue)
    }
}
```

### Step 6: Sort Options

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Menu {
            Picker("Sort", selection: $sortOption) {
                ForEach(JobSort.allCases, id: \.self) { sort in
                    Text(sort.rawValue).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }
}
```

### Step 7: Supporting Components

```swift
struct StageProgressionBar: View {
    let currentStage: Int
    let totalStages: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<totalStages, id: \.self) { stage in
                RoundedRectangle(cornerRadius: 2)
                    .fill(stage < currentStage ? Color.blue : Color.gray.opacity(0.2))
                    .frame(height: 4)
            }
        }
    }
}

struct MiniProgressBar: View {
    let label: String
    let value: Double
    let total: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(label): \(Int(value))/\(Int(total))")
                .font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: min(value / total, 1.0))
                .tint(value > total ? .red : color)
        }
    }
}
```

## Important Notes
- AI summaries are cached for 1 hour — don't re-request on every appear
- Budget progress bars ONLY shown with view_job_financials permission
- Payment Hold shows different UI to workers vs managers (privacy)
- Continuous jobs are grayed out (opacity 0.7) and filtered by assignment
- Stage progression bar shows completed stages filled, remaining empty
- Sort by "Recent Activity" uses last clock entry or last update date

## Success Criteria
- [ ] Smart cards for all 8 job statuses
- [ ] AI summary on each job card (cached 1hr)
- [ ] Stage progression bar on each row
- [ ] Dual progress bars (hours + budget) when data exists
- [ ] Payment Hold: red to workers, $ badge to managers
- [ ] Continuous jobs: light gray, only visible to assigned/qualified
- [ ] Sort options (Recent Activity, Name, Start Date, Stage)
- [ ] Swipe actions: AI summary + status change (hat-gated)
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 45A Results (YYYY-MM-DD)
- Smart cards: 8 status filters
- Job card: AI summary, stage bar, progress bars
- Payment Hold privacy rules
- Swipe actions + sort
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 45B.**
