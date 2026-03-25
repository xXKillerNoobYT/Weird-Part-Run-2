# 60T — Background Task Log

> **Chain position:** Standalone
> **Log file:** `xcode-ai/prompt-results-log.md`

## Instructions

Background tasks (forecast recalculations, companion discovery, etc.) run silently with no visibility. Create a `background_task_log` table, a `BackgroundTaskService`, and a Dashboard card showing recent task runs.

**Read first:**
- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — last migration is 055_office_channel (or 056 if 60O ran first)
- `core/Sources/WiredPartCore/Services/DashboardService.swift` — see how dashboard data is structured
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift` — see where dashboard cards are rendered
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift` — see how services are wired

## Task

### Step 1: Create the migration

In `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift`:

1. Check the last migration number. If 056 already exists (from 60O), use 057. Otherwise use 056. The instructions below assume 057 — adjust if needed.

2. Add `registerMigration057BackgroundTaskLog(&migrator)` to the migrator registration list.

3. Add the migration function:

```swift
// MARK: - 057: Background Task Log

extension AppDatabase {
    private static func registerMigration057BackgroundTaskLog(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("057_background_task_log") { db in
            try db.create(table: "background_task_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("task_name", .text).notNull()
                    // e.g., "Forecast Recalculation", "Companion Discovery"
                t.column("task_type", .text).notNull()
                    // "forecast", "companion", "sync", "cleanup", "report"
                t.column("status", .text).notNull().defaults(to: "running")
                    // "running", "completed", "failed", "cancelled"
                t.column("started_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
                t.column("completed_at", .text)
                t.column("result_summary", .text)
                    // e.g., "Recalculated 142 parts in 3.2s", "Found 8 new companion rules"
                t.column("error_message", .text)
                t.column("items_processed", .integer)
                t.column("device_id", .text)
                t.column("created_at", .text).notNull()
                    .defaults(sql: "(datetime('now'))")
            }

            try db.create(index: "idx_btl_type", on: "background_task_log", columns: ["task_type"])
            try db.create(index: "idx_btl_status", on: "background_task_log", columns: ["status"])
            try db.create(index: "idx_btl_started", on: "background_task_log", columns: ["started_at"])
        }
    }
}
```

### Step 2: Create BackgroundTaskService

Create `core/Sources/WiredPartCore/Services/BackgroundTaskService.swift`:

```swift
import Foundation
import GRDB

/// Service for logging and querying background task executions.
public final class BackgroundTaskService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Models

    public struct TaskLogEntry: Identifiable, Sendable {
        public let id: Int64
        public let taskName: String
        public let taskType: String
        public let status: String
        public let startedAt: String
        public let completedAt: String?
        public let resultSummary: String?
        public let errorMessage: String?
        public let itemsProcessed: Int?
        public let deviceId: String?

        /// Duration in seconds if completed.
        public var durationSeconds: Double? {
            guard let completedAt,
                  let start = ISO8601DateFormatter().date(from: startedAt),
                  let end = ISO8601DateFormatter().date(from: completedAt) else { return nil }
            return end.timeIntervalSince(start)
        }

        /// Formatted duration string.
        public var durationFormatted: String? {
            guard let seconds = durationSeconds else { return nil }
            if seconds < 1 { return String(format: "%.0fms", seconds * 1000) }
            if seconds < 60 { return String(format: "%.1fs", seconds) }
            return String(format: "%.0fm %.0fs", floor(seconds / 60), seconds.truncatingRemainder(dividingBy: 60))
        }
    }

    // MARK: - Logging

    /// Start logging a new background task. Returns the log entry ID.
    @discardableResult
    public func startTask(name: String, type: String, deviceId: String? = nil) throws -> Int64 {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO background_task_log (task_name, task_type, status, device_id)
                VALUES (?, ?, 'running', ?)
                """, arguments: [name, type, deviceId])
            return dbConn.lastInsertedRowID
        }
    }

    /// Mark a task as completed.
    public func completeTask(id: Int64, summary: String?, itemsProcessed: Int? = nil) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE background_task_log
                SET status = 'completed', completed_at = datetime('now'),
                    result_summary = ?, items_processed = ?
                WHERE id = ?
                """, arguments: [summary, itemsProcessed, id])
        }
    }

    /// Mark a task as failed.
    public func failTask(id: Int64, error: String) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                UPDATE background_task_log
                SET status = 'failed', completed_at = datetime('now'), error_message = ?
                WHERE id = ?
                """, arguments: [error, id])
        }
    }

    // MARK: - Queries

    /// Get recent task log entries (last N).
    public func recentTasks(limit: Int = 20) throws -> [TaskLogEntry] {
        try db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: """
                SELECT id, task_name, task_type, status, started_at, completed_at,
                       result_summary, error_message, items_processed, device_id
                FROM background_task_log
                ORDER BY started_at DESC
                LIMIT ?
                """, arguments: [limit]).map { row in
                TaskLogEntry(
                    id: row["id"],
                    taskName: row["task_name"] ?? "",
                    taskType: row["task_type"] ?? "",
                    status: row["status"] ?? "unknown",
                    startedAt: row["started_at"] ?? "",
                    completedAt: row["completed_at"],
                    resultSummary: row["result_summary"],
                    errorMessage: row["error_message"],
                    itemsProcessed: row["items_processed"],
                    deviceId: row["device_id"]
                )
            }
        }
    }

    /// Get counts of tasks by status in the last 24 hours.
    public func last24HoursSummary() throws -> (running: Int, completed: Int, failed: Int) {
        try db.writer.read { dbConn in
            let rows = try Row.fetchAll(dbConn, sql: """
                SELECT status, COUNT(*) AS cnt FROM background_task_log
                WHERE started_at >= datetime('now', '-1 day')
                GROUP BY status
                """)
            var running = 0, completed = 0, failed = 0
            for row in rows {
                let status = (row["status"] as String?) ?? ""
                let count = (row["cnt"] as Int?) ?? 0
                switch status {
                case "running": running = count
                case "completed": completed = count
                case "failed": failed = count
                default: break
                }
            }
            return (running, completed, failed)
        }
    }

    /// Clean up old log entries (older than N days).
    public func cleanupOldEntries(olderThanDays: Int = 30) throws {
        try db.writer.write { dbConn in
            try dbConn.execute(sql: """
                DELETE FROM background_task_log
                WHERE started_at < datetime('now', '-\(olderThanDays) days')
                """)
        }
    }
}
```

### Step 3: Wire BackgroundTaskService into AppCore

In `AppCore.swift`:

1. Add property: `public private(set) var backgroundTaskService: BackgroundTaskService?`
2. In the service initialization block, add: `backgroundTaskService = BackgroundTaskService(db: database)`
3. In the teardown/reset, add: `backgroundTaskService = nil`

### Step 4: Wire existing background operations to log their runs

Find the forecast recalculation and companion discovery code. These likely live in:
- `core/Sources/WiredPartCore/Services/PartsService.swift` (forecasting)
- `core/Sources/WiredPartCore/Services/PartsService.swift` (companion discovery)

Or they may be triggered from the iOS side. Wherever these operations run, wrap them with task logging:

```swift
// Example: wrapping forecast recalculation
let taskId = try? backgroundTaskService.startTask(name: "Forecast Recalculation", type: "forecast")
do {
    let result = try performForecastRecalc()
    if let taskId {
        try? backgroundTaskService.completeTask(id: taskId, summary: "Recalculated \(result.count) parts", itemsProcessed: result.count)
    }
} catch {
    if let taskId {
        try? backgroundTaskService.failTask(id: taskId, error: error.localizedDescription)
    }
}
```

**IMPORTANT:** Search the codebase for forecast and companion operations. If you cannot find exactly where they run, add the logging calls as `// TODO:` comments with clear instructions on where to add them.

### Step 5: Add "Background Tasks" card to DashboardView

In `DashboardView.swift`, add a new card section:

```swift
// Background Tasks card
Section {
    VStack(alignment: .leading, spacing: 8) {
        Label("Background Tasks", systemImage: "gearshape.2.fill")
            .font(.headline)

        if let summary = taskSummary {
            HStack(spacing: 16) {
                VStack {
                    Text("\(summary.completed)")
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                    Text("Done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(summary.running)")
                        .font(.title2.bold())
                        .foregroundStyle(.blue)
                    Text("Running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(summary.failed)")
                        .font(.title2.bold())
                        .foregroundStyle(.red)
                    Text("Failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !recentTasks.isEmpty {
                Divider()
                ForEach(recentTasks.prefix(3)) { task in
                    HStack {
                        Image(systemName: task.status == "completed" ? "checkmark.circle.fill" : task.status == "failed" ? "xmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .foregroundStyle(task.status == "completed" ? .green : task.status == "failed" ? .red : .blue)
                        VStack(alignment: .leading) {
                            Text(task.taskName)
                                .font(.caption.weight(.medium))
                            if let summary = task.resultSummary {
                                Text(summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let duration = task.durationFormatted {
                            Text(duration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
```

Add state variables and load in the dashboard's data loading method:

```swift
@State private var taskSummary: (running: Int, completed: Int, failed: Int)?
@State private var recentTasks: [BackgroundTaskService.TaskLogEntry] = []

// In loadDashboardData() or similar:
if let taskService = appCore.backgroundTaskService {
    taskSummary = try? taskService.last24HoursSummary()
    recentTasks = (try? taskService.recentTasks(limit: 5)) ?? []
}
```

## Files to Modify

- `core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift` — add migration 057 (or next available number)
- `core/Sources/WiredPartCore/Services/BackgroundTaskService.swift` — CREATE new service
- `Weird Parts IOS/Weird Parts IOS/App/AppCore.swift` — wire BackgroundTaskService
- `Weird Parts IOS/Weird Parts IOS/Features/Dashboard/DashboardView.swift` — add Background Tasks card

## Success Criteria

- [ ] Migration creates `background_task_log` table with all columns and indexes
- [ ] BackgroundTaskService has `startTask`, `completeTask`, `failTask`, `recentTasks`, `last24HoursSummary`
- [ ] AppCore exposes `backgroundTaskService` property
- [ ] Dashboard shows "Background Tasks" card with 24-hour summary counts
- [ ] Dashboard card shows up to 3 recent tasks with name, status icon, summary, duration
- [ ] Completed tasks show green checkmark, failed show red X, running show spinner
- [ ] Migration number doesn't conflict with other migrations
- [ ] No force unwraps, no empty catch blocks
- [ ] Builds without errors
