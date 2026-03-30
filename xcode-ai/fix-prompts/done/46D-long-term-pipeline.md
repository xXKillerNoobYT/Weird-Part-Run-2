# 46D — Long-Term Pipeline Page

> **Chain position:** 46C → **46D**
> **Prerequisite:** 46C (short-term pipeline)
> **Log file:** `xcode-ai/prompt-results-log.md`

## MANDATORY RULES
1. DO NOT use `import GRDB` in UI files
2. DO NOT use empty `catch { }` blocks
3. DO NOT use `#if os(iOS)` guards

## Instructions

**IMPORTANT:** Before implementing, read `SchedulingService.swift` and `OfficeRouter.swift`. Create a long-term pipeline page with 3-year timeline, capacity bars, callback tracking, bid tracking, and AI capacity warnings.

## Context

Business planning requires a 3-year view of the job pipeline: pending bids, scheduled jobs, capacity per month. Monthly capacity bars show available work-days based on historical averages (how many hours your crew actually produces). AI warns about capacity gaps — months where you'll run out of work or be overcommitted. This links from the Office section for management use.

## Task

### Step 1: Create IOSLongTermPipelinePage.swift

Create `Weird Parts IOS/Weird Parts IOS/Features/Scheduling/IOSLongTermPipelinePage.swift`:

```swift
import SwiftUI

struct IOSLongTermPipelinePage: View {
    @EnvironmentObject var appCore: AppCore
    @State private var timelineMonths: [MonthCapacity] = []
    @State private var pendingBids: [BidItem] = []
    @State private var callbackItems: [CallbackItem] = []
    @State private var aiWarnings: [CapacityWarning] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedMonth: MonthCapacity?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading pipeline...")
            } else if let error = loadError {
                ErrorStateView(message: error, retryAction: { Task { await loadData() } })
            } else {
                pipelineContent
            }
        }
        .navigationTitle("Long-Term Pipeline")
        .task { await loadData() }
        .refreshable { await loadData() }
    }

    var pipelineContent: some View {
        List {
            // AI Warnings (if any)
            if !aiWarnings.isEmpty {
                Section {
                    ForEach(aiWarnings) { warning in
                        HStack {
                            Image(systemName: warning.isOvercommitted ? "exclamationmark.triangle.fill" : "chart.bar.xaxis")
                                .foregroundStyle(warning.isOvercommitted ? .red : .orange)
                            VStack(alignment: .leading) {
                                Text(warning.message).font(.subheadline)
                                Text(warning.suggestion).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("AI Capacity Warnings", systemImage: "sparkles")
                }
            }

            // 3-Year Timeline with Capacity Bars
            Section {
                ForEach(timelineMonths) { month in
                    Button {
                        selectedMonth = month
                    } label: {
                        MonthCapacityRow(month: month)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Capacity by Month")
            }

            // Selected Month Detail
            if let month = selectedMonth {
                Section {
                    ForEach(month.jobs) { job in
                        HStack {
                            Text(job.name).font(.subheadline)
                            Spacer()
                            Text("\(job.estimatedDays ?? 0) days")
                                .font(.caption).foregroundStyle(.secondary)
                            StatusBadge(status: job.status)
                        }
                    }
                } header: {
                    Text("\(month.monthLabel) — \(month.jobs.count) jobs")
                }
            }

            // Pending Bids
            Section {
                ForEach(pendingBids) { bid in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(bid.jobName).font(.headline)
                            Text(bid.customerName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(bid.status.capitalized)
                                .font(.caption)
                                .foregroundStyle(bid.status == "pending" ? .orange : .blue)
                            if let amount = bid.bidAmount {
                                Text(formatCurrency(amount))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Pending Bids (\(pendingBids.count))")
            }

            // Callback Tracking
            if !callbackItems.isEmpty {
                Section {
                    ForEach(callbackItems) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.jobName).font(.subheadline)
                                Text("Follow up: \(item.callbackDate, style: .date)")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Spacer()
                            Text(item.callbackDate, style: .relative)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Callbacks (\(callbackItems.count))")
                }
            }
        }
    }
}
```

### Step 2: Month Capacity Row

```swift
struct MonthCapacityRow: View {
    let month: MonthCapacity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(month.monthLabel)
                    .font(.subheadline).bold()
                Spacer()
                Text("\(month.scheduledDays)/\(month.availableDays) days")
                    .font(.caption)
                    .foregroundStyle(month.utilizationPercent > 1.0 ? .red : .secondary)
            }

            // Capacity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(capacityColor(month.utilizationPercent))
                        .frame(width: geo.size.width * min(month.utilizationPercent, 1.0))
                }
            }
            .frame(height: 8)

            // Job count
            HStack {
                Text("\(month.jobCount) jobs")
                    .font(.caption2).foregroundStyle(.secondary)
                if month.pendingBidCount > 0 {
                    Text("+ \(month.pendingBidCount) bids pending")
                        .font(.caption2).foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }

    func capacityColor(_ percent: Double) -> Color {
        if percent > 1.0 { return .red }
        if percent > 0.8 { return .orange }
        if percent > 0.5 { return .blue }
        return .green
    }
}
```

### Step 3: Models and Service

```swift
struct MonthCapacity: Identifiable, Sendable {
    let id: String  // "2026-04"
    let monthLabel: String  // "April 2026"
    let availableDays: Int  // work-days in month × crew size
    let scheduledDays: Int  // estimated job days
    let jobCount: Int
    let pendingBidCount: Int
    let jobs: [JobSummary]
    var utilizationPercent: Double {
        Double(scheduledDays) / max(Double(availableDays), 1)
    }
}

struct BidItem: Identifiable, Sendable {
    let id: Int64
    let jobName: String
    let customerName: String
    let bidAmount: Double?
    let status: String  // "pending", "submitted", "accepted", "rejected"
    let submittedDate: Date?
    let expectedDecisionDate: Date?
}

struct CallbackItem: Identifiable, Sendable {
    let id: Int64
    let jobName: String
    let callbackDate: Date
}

struct CapacityWarning: Identifiable, Sendable {
    let id = UUID()
    let month: String
    let message: String
    let suggestion: String
    let isOvercommitted: Bool
}

// In SchedulingService:
func getLongTermTimeline(months: Int) async throws -> [MonthCapacity]
func getPendingBids() async throws -> [BidItem]
func createBid(jobId: Int64, amount: Double?, notes: String?) async throws -> BidItem
func updateBidStatus(bidId: Int64, status: String) async throws
func getAICapacityWarnings(timeline: [MonthCapacity]) async throws -> [CapacityWarning]
```

### Step 4: Update Routing

```swift
// Add to SchedulingRouter (as a tab)
// Add link from OfficeRouter (management view)

// In OfficeRouter — add navigation link:
NavigationLink {
    IOSLongTermPipelinePage()
} label: {
    Label("Long-Term Pipeline", systemImage: "chart.bar.xaxis")
}
```

## Important Notes
- Available days = work-days in month (22 avg) times active crew members
- Scheduled days = sum of estimated job days for confirmed jobs in that month
- Historical averages: calculate from past 6 months of actual work data
- Capacity > 100% = overcommitted (red bar)
- AI warnings: triggered when <50% capacity (underscheduled) or >100% (overcommitted)
- Bid tracker is simple: name, amount, status — NOT full estimating software
- The timeline shows 36 months (3 years) — scrollable list
- Tapping a month shows the jobs in that month

## Success Criteria
- [ ] IOSLongTermPipelinePage.swift created
- [ ] 3-year timeline with monthly capacity bars
- [ ] Color-coded utilization (green/blue/orange/red)
- [ ] Tap month shows job detail
- [ ] Pending bids section with status
- [ ] Callback tracking
- [ ] AI capacity warnings
- [ ] Added to scheduling router and office router
- [ ] All errors show in UI
- [ ] Project builds with no errors

## Log Entry
```
## Prompt 46D Results (YYYY-MM-DD)
- IOSLongTermPipelinePage: 36-month timeline
- Capacity bars with utilization colors
- Bid tracker, callbacks, AI warnings
- Build: PASS/FAIL
```

**Wait for user confirmation before proceeding to prompt 46E.**
