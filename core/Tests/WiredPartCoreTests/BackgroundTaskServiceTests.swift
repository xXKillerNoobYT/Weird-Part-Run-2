import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("BackgroundTaskService Tests")
struct BackgroundTaskServiceTests {

    private func freshService() throws -> BackgroundTaskService {
        let db = try AppDatabase.openInMemoryDatabase()
        return BackgroundTaskService(db: db)
    }

    // MARK: - Task Lifecycle

    @Test("Start and complete a task")
    func testStartAndComplete() throws {
        let svc = try freshService()

        let taskId = try svc.startTask(name: "sync_pull", type: "sync")
        #expect(taskId > 0)

        try svc.completeTask(id: taskId, summary: "Pulled 42 records", itemsProcessed: 42)

        let recent = try svc.recentTasks()
        #expect(recent.count == 1)
        #expect(recent[0].status == "completed")
        #expect(recent[0].itemsProcessed == 42)
    }

    @Test("Start and fail a task")
    func testStartAndFail() throws {
        let svc = try freshService()

        let taskId = try svc.startTask(name: "sync_push", type: "sync")
        try svc.failTask(id: taskId, error: "Network unreachable")

        let recent = try svc.recentTasks()
        #expect(recent[0].status == "failed")
        #expect(recent[0].errorMessage?.contains("Network") == true)
    }

    // MARK: - Queries

    @Test("Recent tasks ordered by most recent first")
    func testRecentTasksOrder() throws {
        let svc = try freshService()

        let t1 = try svc.startTask(name: "task_1", type: "sync")
        try svc.completeTask(id: t1)
        let t2 = try svc.startTask(name: "task_2", type: "sync")
        try svc.completeTask(id: t2)

        let recent = try svc.recentTasks(limit: 2)
        #expect(recent.count == 2)
        #expect(recent[0].taskName == "task_2")
    }

    @Test("Tasks by type filters correctly")
    func testTasksByType() throws {
        let svc = try freshService()

        let s1 = try svc.startTask(name: "sync_1", type: "sync")
        try svc.completeTask(id: s1)
        let b1 = try svc.startTask(name: "backup_1", type: "backup")
        try svc.completeTask(id: b1)

        let syncTasks = try svc.tasksByType("sync")
        #expect(syncTasks.count == 1)
        #expect(syncTasks[0].taskType == "sync")

        let backupTasks = try svc.tasksByType("backup")
        #expect(backupTasks.count == 1)
    }

    @Test("Running tasks shows in-progress only")
    func testRunningTasks() throws {
        let svc = try freshService()

        let t1 = try svc.startTask(name: "running", type: "sync")
        let t2 = try svc.startTask(name: "done", type: "sync")
        try svc.completeTask(id: t2)

        let running = try svc.runningTasks()
        #expect(running.count == 1)
        #expect(running[0].id == t1)
    }

    @Test("Office status rows expose known background tasks")
    func testOfficeStatusRowsExposeKnownTasks() throws {
        let svc = try freshService()

        let forecast = try svc.startTask(name: "Forecast Recalculation", type: "forecast_recalculation")
        try svc.completeTask(id: forecast, summary: "Forecasts refreshed", itemsProcessed: 3)
        let companion = try svc.startTask(name: "Companion Auto-Discovery", type: "companion_discovery")
        try svc.failTask(id: companion, error: "Model unavailable")
        _ = try svc.startTask(name: "Peer Sync", type: "sync")

        let rows = Dictionary(uniqueKeysWithValues: try svc.officeStatusRows().map { ($0.id, $0) })
        #expect(rows["forecast_recalculation"]?.status == .completed)
        #expect(rows["forecast_recalculation"]?.detail.contains("Forecasts refreshed") == true)
        #expect(rows["companion_discovery"]?.status == .failed)
        #expect(rows["companion_discovery"]?.detail.contains("Model unavailable") == true)
        #expect(rows["sync"]?.status == .running)
        #expect(rows["audit"]?.status == .neverRun)
    }

    // MARK: - Summary

    @Test("24-hour summary aggregates correctly")
    func testLast24HoursSummary() throws {
        let svc = try freshService()

        let t1 = try svc.startTask(name: "s1", type: "sync")
        try svc.completeTask(id: t1, itemsProcessed: 10)
        let t2 = try svc.startTask(name: "s2", type: "sync")
        try svc.completeTask(id: t2, itemsProcessed: 20)
        let t3 = try svc.startTask(name: "s3", type: "sync")
        try svc.failTask(id: t3, error: "oops")

        let summary = try svc.last24HoursSummary()
        #expect(summary.totalRuns == 3)
        #expect(summary.successCount == 2)
        #expect(summary.failureCount == 1)
        #expect(summary.runningCount == 0)
    }

    // MARK: - Cleanup

    @Test("Cleanup old entries removes old tasks")
    func testCleanupOldEntries() throws {
        let svc = try freshService()

        let t = try svc.startTask(name: "old", type: "sync")
        try svc.completeTask(id: t)

        // Cleanup with 0 days should remove all
        let removed = try svc.cleanupOldEntries(daysToKeep: 0)
        #expect(removed >= 1)
    }

    @Test("Cleanup stale tasks marks long-running as failed")
    func testCleanupStaleTasks() throws {
        let svc = try freshService()

        let taskId = try svc.startTask(name: "stale", type: "sync")

        // With 0 minutes, all running tasks are considered stale
        let cleaned = try svc.cleanupStaleTasks(maxRunMinutes: 0)
        #expect(cleaned >= 1)

        let running = try svc.runningTasks()
        #expect(running.isEmpty)

        let recent = try svc.recentTasks(limit: 1)
        #expect(recent.first?.id == taskId)
        #expect(recent.first?.status == "failed")
        #expect(recent.first?.errorMessage == "Task timed out (stale cleanup)")
    }

    @Test("completeTask and failTask no-op when id does not exist")
    func testCompleteAndFailUnknownTaskIdNoop() throws {
        let svc = try freshService()

        try svc.completeTask(id: 999_999, summary: "noop", itemsProcessed: 1)
        try svc.failTask(id: 999_999, error: "noop")

        let recent = try svc.recentTasks()
        #expect(recent.isEmpty)
    }

    @Test("officeStatusRows returns unavailable rows when table is missing")
    func testOfficeStatusRowsUnavailableWhenTableMissing() throws {
        let db = try AppDatabase.openInMemoryDatabase()
        let svc = BackgroundTaskService(db: db)

        try db.writer.write { dbConn in
            try dbConn.execute(sql: "DROP TABLE background_task_log")
        }

        let rows = try svc.officeStatusRows()
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { $0.status == .unavailable })
    }

    @Test("TaskLogEntry durationString and statusIcon format expected values")
    func testTaskLogEntryDisplayHelpers() {
        let startedAt = Date()

        var entry = BackgroundTaskService.TaskLogEntry(
            id: 1,
            taskName: "task",
            taskType: "sync",
            status: "running",
            startedAt: startedAt,
            completedAt: nil,
            resultSummary: nil,
            errorMessage: nil,
            itemsProcessed: 0,
            deviceId: nil
        )
        #expect(entry.durationString == nil)
        #expect(entry.statusIcon == "arrow.triangle.2.circlepath")

        entry.completedAt = startedAt.addingTimeInterval(0.250)
        #expect(entry.durationString == "250ms")

        entry.completedAt = startedAt.addingTimeInterval(2.5)
        #expect(entry.durationString == "2.5s")

        entry.completedAt = startedAt.addingTimeInterval(125)
        #expect(entry.durationString == "2m 5s")

        entry.status = "completed"
        #expect(entry.statusIcon == "checkmark.circle.fill")
        entry.status = "failed"
        #expect(entry.statusIcon == "xmark.circle.fill")
        entry.status = "mystery"
        #expect(entry.statusIcon == "questionmark.circle")
    }
}
