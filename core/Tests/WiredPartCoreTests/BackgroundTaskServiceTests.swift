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

        _ = try svc.startTask(name: "stale", type: "sync")

        // With 0 minutes, all running tasks are considered stale
        let cleaned = try svc.cleanupStaleTasks(maxRunMinutes: 0)
        #expect(cleaned >= 1)
    }

    // MARK: - Scheduled Maintenance Jobs

    @Test("Tools maintenance expires trades, decays confidence, and records bounded task log")
    func testToolsMaintenanceRunsAndLogsResults() throws {
        let env = try E2ETestHelpers.setUp()
        let svc = BackgroundTaskService(db: env.db)
        let toolId = try seedToolForMaintenance(env)
        try seedExpiredTrade(env, toolId: toolId)
        try seedDecreasingMaintenanceConfig(env, toolId: toolId, decayRate: 0.10)

        let result = try svc.runToolsMaintenance(toolsService: env.tools)

        #expect(result.didRun)
        #expect(result.expiredTrades == 1)
        #expect(result.updatedConfidenceScores == 1)
        #expect(result.itemsProcessed == 2)

        let row = try env.db.writer.read { db in
            try Row.fetchOne(db, sql: """
                SELECT
                    (SELECT status FROM tool_trades WHERE tool_id = ?) AS trade_status,
                    (SELECT confidence_score FROM tools WHERE id = ?) AS confidence_score
                """, arguments: [toolId, toolId])
        }
        let fetched = try #require(row)
        #expect((fetched["trade_status"] as String?) == "expired")
        let score: Double = fetched["confidence_score"] ?? -1
        #expect(abs(score - 0.90) < 0.0001)

        let logs = try svc.tasksByType("tools_maintenance")
        #expect(logs.count == 1)
        #expect(logs[0].status == "completed")
        #expect(logs[0].itemsProcessed == 2)
    }

    @Test("Tools maintenance skips a recent successful run to avoid duplicate daily decay")
    func testToolsMaintenanceSkipsRecentRun() throws {
        let env = try E2ETestHelpers.setUp()
        let svc = BackgroundTaskService(db: env.db)
        let toolId = try seedToolForMaintenance(env)
        try seedDecreasingMaintenanceConfig(env, toolId: toolId, decayRate: 0.10)

        let first = try svc.runToolsMaintenance(toolsService: env.tools)
        let second = try svc.runToolsMaintenance(toolsService: env.tools)

        #expect(first.didRun)
        #expect(!second.didRun)

        let score = try env.db.writer.read { db in
            try Double.fetchOne(db, sql: "SELECT confidence_score FROM tools WHERE id = ?", arguments: [toolId])
        }
        #expect(abs((score ?? -1) - 0.90) < 0.0001)

        let logs = try svc.tasksByType("tools_maintenance")
        #expect(logs.count == 1)
    }

    @discardableResult
    private func seedToolForMaintenance(_ env: E2ETestHelpers.TestEnvironment) throws -> Int64 {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO tools
                    (tool_number, name, category, status, confidence_score, created_at, updated_at)
                VALUES ('T-SCHED', 'Scheduled Tool', 'hand_tools', 'available', 1.0, datetime('now'), datetime('now'))
                """)
            return db.lastInsertedRowID
        }
    }

    private func seedExpiredTrade(_ env: E2ETestHelpers.TestEnvironment, toolId: Int64) throws {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO tool_trades
                    (tool_id, from_user_id, to_user_id, condition_at_send, status, expires_at, created_at)
                VALUES (?, ?, ?, 'Good', 'pending', datetime('now', '-8 days'), datetime('now', '-9 days'))
                """, arguments: [toolId, env.adminUserId, env.adminUserId])
        }
    }

    private func seedDecreasingMaintenanceConfig(
        _ env: E2ETestHelpers.TestEnvironment,
        toolId: Int64,
        decayRate: Double
    ) throws {
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO tool_maintenance_configs
                    (tool_id, maintenance_type, decay_rate, is_active, created_at)
                VALUES (?, 'decreasing_based', ?, 1, datetime('now'))
                """, arguments: [toolId, decayRate])
        }
    }
}
