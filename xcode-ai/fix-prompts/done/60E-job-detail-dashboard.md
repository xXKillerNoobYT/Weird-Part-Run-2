# 60E — Job Detail Dashboard (Overview Tab)
> Chain position: Standalone
> Log file: xcode-ai/prompt-results-log.md

## Instructions

The Overview tab of `IOSJobDetailTabView` currently has metric cards and a flat `LabeledContent` list of job fields. The plan calls for a proper dashboard with: stage progression bar, AI summary (cached 1hr), Today's Activity feed, Quick Actions, Warranty Info, and a Financial Summary (hat-gated). The metric cards already exist but need a stage bar, activity feed, and quick actions added below them.

## Task

### Step 1: Add stage progression bar

In `IOSJobDetailTabView.swift`, inside `overviewTab(_ job:)`, add a stage progression bar below the status badges section but above the metric cards. The stages are: `lead`, `estimated`, `scheduled`, `in_progress`, `complete`, `invoiced`, `paid`. The current stage comes from `job.status`.

Add this section inside the `overviewTab` function, after the status/info section and before the metric cards section:

```swift
// Stage Progression
Section("Stage") {
    let stages = ["lead", "estimated", "scheduled", "in_progress", "complete", "invoiced", "paid"]
    let currentIndex = stages.firstIndex(of: job.status) ?? 0

    VStack(alignment: .leading, spacing: 8) {
        // Progress bar
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(stages.count), height: 8)
            }
        }
        .frame(height: 8)

        // Stage labels
        HStack {
            ForEach(stages, id: \.self) { stage in
                let idx = stages.firstIndex(of: stage) ?? 0
                let isCurrent = stage == job.status
                let isPast = idx < currentIndex

                VStack(spacing: 2) {
                    Circle()
                        .fill(isCurrent ? Color.accentColor : isPast ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(stage.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 8))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    .padding(.vertical, 4)
}
```

### Step 2: Add AI Summary section

Below the metric cards section, add an AI-generated summary. Cache it for 1 hour to avoid redundant calls.

Add these state properties to `IOSJobDetailTabView`:

```swift
@State private var aiSummary: String?
@State private var aiSummaryLoadedAt: Date?
@State private var isLoadingAISummary = false
```

Add this section in `overviewTab` after the metric cards:

```swift
// AI Summary
Section {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("AI Summary")
                .font(.headline)
            Spacer()
            if isLoadingAISummary {
                ProgressView()
                    .controlSize(.small)
            }
        }

        if let summary = aiSummary {
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if !isLoadingAISummary {
            Text("Tap to generate a summary of this job.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .onTapGesture { loadAISummary(job) }
        }
    }
    .padding(.vertical, 4)
}
```

Add the AI loading function:

```swift
private func loadAISummary(_ job: JobsService.JobDetail) {
    // 1-hour cache
    if let loadedAt = aiSummaryLoadedAt,
       Date().timeIntervalSince(loadedAt) < 3600,
       aiSummary != nil {
        return
    }

    isLoadingAISummary = true
    Task {
        if let aiService = appCore.foundationModelsService, aiService.isAvailable() {
            let context: [String: String] = [
                "jobName": job.jobName,
                "jobNumber": job.jobNumber,
                "status": job.status,
                "priority": job.priority,
                "laborHours": String(format: "%.1f", job.laborHours),
                "partsCost": String(format: "%.2f", job.partsCost),
                "teamCount": "\(job.teamCount)"
            ]
            let result = await aiService.generatePreFill(
                fieldType: "brief job status summary (2-3 sentences)",
                contextData: context
            )
            if result.success, let text = result.text {
                aiSummary = text
                aiSummaryLoadedAt = Date()
            }
        }
        isLoadingAISummary = false
    }
}
```

### Step 3: Add Quick Actions section

Below the AI summary, add quick actions for the most common job operations:

```swift
// Quick Actions
Section("Quick Actions") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
        quickAction("Clock In", icon: "clock.fill", color: .green) {
            // Navigate to clock page for this job
        }
        quickAction("Order Parts", icon: "cart.fill", color: .blue) {
            selectedTab = "orders"
        }
        quickAction("Add Note", icon: "note.text.badge.plus", color: .purple) {
            selectedTab = "notebooks"
        }
        quickAction("Ask Q&A", icon: "questionmark.bubble.fill", color: .orange) {
            selectedTab = "qa"
        }
        quickAction("View Costs", icon: "dollarsign.circle.fill", color: .red) {
            selectedTab = "costs"
        }
        quickAction("Team", icon: "person.2.fill", color: .teal) {
            selectedTab = "team"
        }
    }
    .listRowInsets(EdgeInsets())
    .listRowBackground(Color.clear)
}
```

Add the helper:

```swift
private func quickAction(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
}
```

### Step 4: Add Warranty Info section (if data exists)

```swift
// Warranty
if let warrantyEnd = job.warrantyEndDate {
    Section("Warranty") {
        HStack {
            Image(systemName: warrantyEnd > Date() ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(warrantyEnd > Date() ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(warrantyEnd > Date() ? "Under Warranty" : "Warranty Expired")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Until \(warrantyEnd, format: .dateTime.month().day().year())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

Note: If `JobDetail` does not have a `warrantyEndDate` property, skip this section entirely and leave a `// TODO: Add warranty section when warrantyEndDate is added to JobDetail` comment.

### Step 5: Add Financial Summary section (hat-gated)

```swift
// Financial Summary (permission-gated)
if appCore.hasPermission("view_job_financials") {
    Section("Financial Summary") {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Parts Cost")
                    .font(.caption).foregroundStyle(.secondary)
                Text(formatCurrency(job.partsCost))
                    .font(.headline)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Labor Cost")
                    .font(.caption).foregroundStyle(.secondary)
                Text(formatCurrency(job.laborHours * 65.0)) // Rough estimate
                    .font(.headline)
            }
        }
        if let budget = job.budgetLimit {
            let total = job.partsCost + (job.laborHours * 65.0)
            let pct = budget > 0 ? total / budget : 0
            HStack {
                Text("Budget Usage")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(pct > 0.9 ? .red : pct > 0.7 ? .orange : .green)
            }
            ProgressView(value: min(pct, 1.0))
                .tint(pct > 0.9 ? .red : pct > 0.7 ? .orange : .green)
        }
    }
}
```

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift` — rebuild overviewTab with stage bar, AI summary, quick actions, warranty, financials

## Success Criteria

- [ ] Overview tab shows stage progression bar with 7 stages, current stage highlighted
- [ ] AI Summary section appears with sparkle icon; generates on tap; cached for 1 hour
- [ ] Quick Actions grid has 6 buttons that switch tabs or navigate
- [ ] Financial Summary only shows for users with `view_job_financials` permission
- [ ] Existing metric cards (Hours, Budget, Team, Parts) are preserved
- [ ] Status badges section still shows at the top
- [ ] No compilation errors
