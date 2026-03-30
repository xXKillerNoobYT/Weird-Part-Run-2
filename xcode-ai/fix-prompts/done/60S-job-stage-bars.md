# 60S — Job Stage Progression Bars

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Jobs have stages (from migration 034_job_stages) but the UI never shows them visually. Add a stage progression bar to both JobsListPage rows and IOSJobDetailTabView. The bar shows connected circles representing each stage, with the current stage highlighted.

The `job_stages` table has columns: `id`, `name`, `sort_order`. Default stages seeded are: Rough-in (1), Prep/Makeup (2), Trim-out (3). Jobs have a `current_stage_id` column added by the same migration.

**Read first:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — search for "034_job_stages" to see the schema
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobsListPage.swift` — see the current job row layout
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift` — see the detail view layout
- `core/Sources/WiredPartCore/Services/JobsService.swift` — find how jobs are queried, check for `current_stage_id` in the job model

## Task

### Step 1: Add stage query methods to JobsService (if not already present)

In `core/Sources/WiredPartCore/Services/JobsService.swift`, add:

```swift
/// Fetch all job stages ordered by sort_order.
public func listJobStages() throws -> [JobStage] {
    try db.writer.read { dbConn in
        try Row.fetchAll(dbConn, sql: """
            SELECT id, name, sort_order FROM job_stages
            WHERE deleted_at IS NULL
            ORDER BY sort_order ASC
            """).map { row in
            JobStage(
                id: row["id"],
                name: row["name"] ?? "",
                sortOrder: row["sort_order"] ?? 0
            )
        }
    }
}

/// Simple stage model.
public struct JobStage: Identifiable, Sendable {
    public let id: Int64
    public let name: String
    public let sortOrder: Int
}
```

**IMPORTANT:** Check if `JobStage` or `listJobStages` already exists. If they do, use the existing ones. If the job model already exposes `currentStageId`, use that.

### Step 2: Create JobStageProgressBar component

Create `Weird Parts IOS/Weird Parts IOS/Shared/JobStageProgressBar.swift`:

```swift
import SwiftUI

/// A visual progression bar showing job stages as connected circles.
/// Current stage is highlighted, completed stages show checkmarks.
struct JobStageProgressBar: View {
    let stages: [StageInfo]
    let currentStageId: Int64?
    var compact: Bool = false  // true for list rows, false for detail view

    struct StageInfo: Identifiable {
        let id: Int64
        let name: String
        let sortOrder: Int
    }

    var body: some View {
        if stages.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    let state = stageState(stage)

                    if index > 0 {
                        // Connector line
                        Rectangle()
                            .fill(state == .future ? Color.gray.opacity(0.3) : Color.green)
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: compact ? 2 : 4) {
                        ZStack {
                            Circle()
                                .fill(circleColor(state))
                                .frame(width: compact ? 16 : 24, height: compact ? 16 : 24)

                            switch state {
                            case .completed:
                                Image(systemName: "checkmark")
                                    .font(compact ? .system(size: 8, weight: .bold) : .system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            case .current:
                                Circle()
                                    .fill(.white)
                                    .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                            case .future:
                                EmptyView()
                            }
                        }

                        if !compact {
                            Text(stage.name)
                                .font(.caption2)
                                .foregroundStyle(state == .future ? .secondary : .primary)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.vertical, compact ? 4 : 8)
        }
    }

    private enum StageState {
        case completed, current, future
    }

    private func stageState(_ stage: StageInfo) -> StageState {
        guard let currentId = currentStageId else { return .future }
        guard let currentStage = stages.first(where: { $0.id == currentId }) else { return .future }

        if stage.sortOrder < currentStage.sortOrder { return .completed }
        if stage.id == currentId { return .current }
        return .future
    }

    private func circleColor(_ state: StageState) -> Color {
        switch state {
        case .completed: .green
        case .current: .blue
        case .future: .gray.opacity(0.3)
        }
    }
}
```

### Step 3: Add stage bar to JobsListPage rows

In `JobsListPage.swift`:

1. Add a state variable for stages:

```swift
@State private var stages: [JobStageProgressBar.StageInfo] = []
```

2. In the data loading function, load stages:

```swift
if let jobsService = appCore.jobsService {
    let jobStages = try jobsService.listJobStages()
    stages = jobStages.map {
        JobStageProgressBar.StageInfo(id: $0.id, name: $0.name, sortOrder: $0.sortOrder)
    }
}
```

3. In each job row, add the compact progress bar BELOW the job name/status but ABOVE any metadata:

```swift
// After job name and status line:
if !stages.isEmpty {
    JobStageProgressBar(
        stages: stages,
        currentStageId: job.currentStageId,  // use the actual property name
        compact: true
    )
}
```

**IMPORTANT:** Read the existing job model to find the exact property name for the current stage. It might be `currentStageId`, `current_stage_id`, or accessed differently. If the job list model doesn't include `current_stage_id`, you may need to add it to the SQL query that loads jobs.

### Step 4: Add stage bar to IOSJobDetailTabView

In `IOSJobDetailTabView.swift`:

1. Add a state variable for stages (same pattern as above).
2. Add the full (non-compact) progress bar in a prominent position — ideally as a Section at the top of the detail view, just below the job header:

```swift
Section("Progress") {
    JobStageProgressBar(
        stages: stages,
        currentStageId: job.currentStageId,
        compact: false
    )
    .padding(.horizontal)
}
```

3. Load stages in the detail view's `.task` or `.onAppear`.

## Files to Modify

- `core/Sources/WiredPartCore/Services/JobsService.swift` — add `listJobStages()` method and `JobStage` struct (if not present)
- `Weird Parts IOS/Weird Parts IOS/Shared/JobStageProgressBar.swift` — CREATE new reusable component
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/JobsListPage.swift` — add compact stage bar to job rows
- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift` — add full stage bar to detail view

## Success Criteria

- [ ] `JobStageProgressBar` component exists as a reusable shared view
- [ ] Stages display as connected circles with lines between them
- [ ] Completed stages show green checkmarks
- [ ] Current stage shows blue circle with white dot
- [ ] Future stages show gray empty circles
- [ ] Compact mode used in list rows (smaller circles, no labels)
- [ ] Full mode used in detail view (larger circles with stage names)
- [ ] Stages loaded from `job_stages` table via service
- [ ] Jobs with no `current_stage_id` show all stages as future (graceful degradation)
- [ ] Builds without errors
