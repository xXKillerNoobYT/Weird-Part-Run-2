# 45B — Job Detail Overview Tab as Dashboard

> **Chain position:** 45A → **45B**
> **Prerequisite:** 45A (jobs list redesign)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `IOSJobDetailTabView.swift`. Rebuild the Overview tab as a proper per-job dashboard with stage progression, smart cards, AI summary, today's activity, and quick actions.

## Context

The job detail Overview tab currently shows basic info. It should be a mini-dashboard: stage progression bar at top, smart cards for key metrics (hours, budget, JPOs, to-dos), AI summary, who's working today, and quick actions. Different job types (warranty, continuous, payment hold) get different layouts.

## Task

### Step 1: Rebuild Overview Tab

```swift
// In IOSJobDetailTabView.swift — the Overview tab content:

var overviewTab: some View {
    List {
        // Stage Progression
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stage \(job.currentStage ?? 1) of \(job.totalStages ?? 5)")
                    .font(.caption).foregroundStyle(.secondary)
                StageProgressionBar(currentStage: job.currentStage ?? 1, totalStages: job.totalStages ?? 5)

                // Stage name and description
                if let stageName = job.currentStageName {
                    Text(stageName).font(.headline)
                }
            }
        }

        // Smart Cards (horizontal scroll)
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    MetricCard(title: "Hours", value: "\(Int(job.hoursUsed ?? 0))",
                               subtitle: job.hoursEstimate != nil ? "of \(Int(job.hoursEstimate!))" : nil,
                               color: .blue, icon: "clock")
                    if appCore.hasPermission("view_job_financials"), let budget = job.budgetTotal {
                        MetricCard(title: "Budget", value: formatCurrency(job.budgetSpent ?? 0),
                                   subtitle: "of \(formatCurrency(budget))",
                                   color: .green, icon: "dollarsign.circle")
                    }
                    MetricCard(title: "JPOs", value: "\(jpoCount)",
                               subtitle: "\(pendingJPOs) pending",
                               color: .orange, icon: "doc.plaintext")
                    MetricCard(title: "To-Dos", value: "\(completedTodos)/\(totalTodos)",
                               subtitle: "\(totalTodos - completedTodos) remaining",
                               color: .purple, icon: "checklist")
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        // Progress bars
        if job.hoursEstimate != nil || (appCore.hasPermission("view_job_financials") && job.budgetTotal != nil) {
            Section {
                if let est = job.hoursEstimate, let used = job.hoursUsed {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Hours Progress")
                            Spacer()
                            Text("\(Int(used))/\(Int(est))h")
                                .font(.caption).monospacedDigit()
                        }
                        ProgressView(value: min(used / est, 1.0))
                            .tint(used > est ? .red : .blue)
                    }
                }
                if appCore.hasPermission("view_job_financials"),
                   let budget = job.budgetTotal, let spent = job.budgetSpent {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Budget Progress")
                            Spacer()
                            Text("\(formatCurrency(spent))/\(formatCurrency(budget))")
                                .font(.caption).monospacedDigit()
                        }
                        ProgressView(value: min(spent / budget, 1.0))
                            .tint(spent > budget ? .red : .green)
                    }
                }
            } header: {
                Text("Progress")
            }
        }

        // AI Summary (cached 1hr)
        if let summary = aiSummary {
            Section {
                Text(summary)
                    .font(.callout)
                    .italic()
            } header: {
                HStack {
                    Text("AI Summary")
                    Spacer()
                    Button { Task { await refreshAISummary() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            }
        }

        // Today's Activity
        Section {
            if todaysWorkers.isEmpty {
                Text("No one working today").foregroundStyle(.secondary)
            } else {
                ForEach(todaysWorkers) { worker in
                    HStack {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text(worker.name)
                        Spacer()
                        if let todo = worker.currentTodo {
                            Text(todo).font(.caption).foregroundStyle(.blue)
                        }
                        Text(worker.elapsedTime)
                            .font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Working Today")
        }

        // Quick Actions (hat-gated)
        Section {
            if appCore.hasPermission("manage_jobs") {
                Button { activeSheet = .editJob } label: {
                    Label("Edit Job", systemImage: "pencil")
                }
                Button { activeSheet = .changeStage } label: {
                    Label("Advance Stage", systemImage: "arrow.right.circle")
                }
            }
            Button { activeSheet = .createJPO } label: {
                Label("New Parts Order", systemImage: "doc.badge.plus")
            }
            Button { activeSheet = .addNote } label: {
                Label("Add Note", systemImage: "square.and.pencil")
            }
        } header: {
            Text("Quick Actions")
        }

        // Warranty Info (if warranty status)
        if job.status == "warranty" {
            Section {
                if let start = job.warrantyStart {
                    LabeledContent("Warranty Start", value: start, format: .dateTime.month().day().year())
                }
                if let end = job.warrantyEnd {
                    LabeledContent("Warranty End", value: end, format: .dateTime.month().day().year())
                }
                if let days = job.warrantyDaysRemaining {
                    LabeledContent("Days Remaining", value: "\(days)")
                        .foregroundStyle(days < 30 ? .red : .primary)
                }
            } header: {
                Text("Warranty")
            }
        }

        // Financial Summary (hat: view_job_financials)
        if appCore.hasPermission("view_job_financials") {
            Section {
                LabeledContent("Labor Cost", value: formatCurrency(job.laborCost ?? 0))
                LabeledContent("Materials Cost", value: formatCurrency(job.materialsCost ?? 0))
                LabeledContent("Total Cost", value: formatCurrency((job.laborCost ?? 0) + (job.materialsCost ?? 0)))
                if let revenue = job.revenue {
                    LabeledContent("Revenue", value: formatCurrency(revenue))
                    let profit = revenue - (job.laborCost ?? 0) - (job.materialsCost ?? 0)
                    LabeledContent("Profit", value: formatCurrency(profit))
                        .foregroundStyle(profit >= 0 ? .green : .red)
                }
            } header: {
                Text("Financial Summary")
            }
        }
    }
}
```

### Step 2: MetricCard Component

```swift
struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2).bold()
            if let sub = subtitle {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(minWidth: 100)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

### Step 3: Different Layouts by Job Type

```swift
// Continuous jobs: to-do list driven (show active to-dos prominently)
if job.classification == "continuous" {
    // Replace stage progression with to-do list
    // Show active to-dos as the main content
    // No stage bar
}

// Payment hold jobs: disabled state
if job.status == "payment_hold" {
    // Show payment hold banner at top
    // Disable quick actions except "Add Note"
    // Show overdue info if payment tracking enabled
}
```

## Important Notes
- AI summary cached for 1 hour — refresh button available
- Budget/financial sections ONLY with view_job_financials permission
- Today's activity shows live worker status (from clock_entries)
- Quick actions are hat-gated — workers see fewer options
- Warranty section only appears for warranty-status jobs
- Continuous jobs replace stage progression with to-do list
- Payment hold jobs show a prominent banner and disable most actions

## Success Criteria
- [ ] Stage progression bar at top
- [ ] Smart metric cards (hours, budget, JPOs, to-dos)
- [ ] Progress bars for hours and budget
- [ ] AI summary with refresh button (cached 1hr)
- [ ] Today's activity: who's working, what to-do
- [ ] Quick actions (hat-gated)
- [ ] Warranty section for warranty jobs
- [ ] Financial summary (hat-gated)
- [ ] Different layouts for continuous/payment hold jobs
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 45B Results (YYYY-MM-DD)
- Overview tab rebuilt as mini-dashboard
- MetricCard component
- AI summary, today's activity, quick actions
- Warranty + financial sections
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding.**
