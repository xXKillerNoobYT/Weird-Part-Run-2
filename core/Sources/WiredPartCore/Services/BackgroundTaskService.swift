import Foundation
import GRDB

/// Background Task Service — logging and monitoring for background operations.
///
/// Tracks background tasks like forecast recalculations, companion discovery,
/// sync operations, and cleanup jobs. Provides start/complete/fail lifecycle
/// and summary queries for the dashboard card.
///
/// All queries run against the local SQLite database via GRDB.
/// Table may not yet exist on first launch (handled gracefully).
public final class BackgroundTaskService: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // =========================================================================
    // MARK: - Data Types
    // =========================================================================

    /// A single background task log entry.
    public struct TaskLogEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
        public var id: Int64?
        public var taskName: String
        public var taskType: String
        public var status: String
        public var startedAt: Date
        public var completedAt: Date?
        public var resultSummary: String?
        public var errorMessage: String?
        public var itemsProcessed: Int
        public var deviceId: String?

        public static let databaseTableName = "background_task_log"

        public enum CodingKeys: String, CodingKey {
            case id
            case taskName = "task_name"
            case taskType = "task_type"
            case status
            case startedAt = "started_at"
            case completedAt = "completed_at"
            case resultSummary = "result_summary"
            case errorMessage = "error_message"
            case itemsProcessed = "items_processed"
            case deviceId = "device_id"
        }

        public mutating func didInsert(_ inserted: InsertionSuccess) {
            id = inserted.rowID
        }

        /// Duration string (e.g. "1.2s", "45ms", "2m 3s") computed from start/complete times.
        public var durationString: String? {
            guard let completed = completedAt else { return nil }
            let elapsed = completed.timeIntervalSince(startedAt)
            if elapsed < 1.0 {
                return "\(Int(elapsed * 1000))ms"
            } else if elapsed < 60.0 {
                return String(format: "%.1fs", elapsed)
            } else {
                let minutes = Int(elapsed) / 60
                let seconds = Int(elapsed) % 60
                return "\(minutes)m \(seconds)s"
            }
        }

        /// Status icon for display.
        public var statusIcon: String {
            switch status {
            case "completed": return "checkmark.circle.fill"
            case "failed": return "xmark.circle.fill"
            case "running": return "arrow.triangle.2.circlepath"
            default: return "questionmark.circle"
            }
        }
    }

    /// Aggregated summary of background task activity over a time window.
    public struct TaskSummary: Sendable {
        public let totalRuns: Int
        public let successCount: Int
        public let failureCount: Int
        public let runningCount: Int

        public init(totalRuns: Int = 0, successCount: Int = 0, failureCount: Int = 0, runningCount: Int = 0) {
            self.totalRuns = totalRuns
            self.successCount = successCount
            self.failureCount = failureCount
            self.runningCount = runningCount
        }
    }

    /// Result from the tools maintenance task.
    public struct ToolsMaintenanceResult: Sendable {
        public let didRun: Bool
        public let expiredTrades: Int
        public let updatedConfidenceScores: Int

        public var itemsProcessed: Int {
            expiredTrades + updatedConfidenceScores
        }

        public init(didRun: Bool, expiredTrades: Int, updatedConfidenceScores: Int) {
            self.didRun = didRun
            self.expiredTrades = expiredTrades
            self.updatedConfidenceScores = updatedConfidenceScores
        }
    }

    // =========================================================================
    // MARK: - Task Lifecycle
    // =========================================================================

    /// Start a background task and return its ID for later completion/failure.
    @discardableResult
    public func startTask(name: String, type: String, deviceId: String? = nil) throws -> Int64 {
        try db.writer.write { dbConn in
            var entry = TaskLogEntry(
                id: nil,
                taskName: name,
                taskType: type,
                status: "running",
                startedAt: Date(),
                completedAt: nil,
                resultSummary: nil,
                errorMessage: nil,
                itemsProcessed: 0,
                deviceId: deviceId
            )
            try entry.insert(dbConn)
            guard let newId = entry.id else {
                throw DatabaseError(message: "Background task insert succeeded but returned no ID")
            }
            return newId
        }
    }

    /// Mark a running task as completed with an optional summary and item count.
    public func completeTask(id: Int64, summary: String? = nil, itemsProcessed: Int = 0) throws {
        try db.writer.write { dbConn in
            guard var entry = try TaskLogEntry.fetchOne(dbConn, key: id) else { return }
            entry.status = "completed"
            entry.completedAt = Date()
            entry.resultSummary = summary
            entry.itemsProcessed = itemsProcessed
            try entry.update(dbConn)
        }
    }

    /// Mark a running task as failed with an error message.
    public func failTask(id: Int64, error: String) throws {
        try db.writer.write { dbConn in
            guard var entry = try TaskLogEntry.fetchOne(dbConn, key: id) else { return }
            entry.status = "failed"
            entry.completedAt = Date()
            entry.errorMessage = error
            try entry.update(dbConn)
        }
    }

    // =========================================================================
    // MARK: - Queries
    // =========================================================================

    /// Fetch the most recent task log entries.
    public func recentTasks(limit: Int = 10) throws -> [TaskLogEntry] {
        do {
            return try db.writer.read { dbConn in
                try TaskLogEntry
                    .order(Column("started_at").desc)
                    .limit(limit)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get a summary of all tasks started within the last 24 hours.
    public func last24HoursSummary() throws -> TaskSummary {
        do {
            return try db.writer.read { dbConn in
                let cutoff = Date().addingTimeInterval(-86400) // 24 hours ago

                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT status, COUNT(*) as cnt
                    FROM background_task_log
                    WHERE started_at >= ?
                    GROUP BY status
                """, arguments: [cutoff])

                var total = 0, success = 0, failure = 0, running = 0
                for row in rows {
                    let status: String = row["status"]
                    let count: Int = row["cnt"]
                    total += count
                    switch status {
                    case "completed": success = count
                    case "failed": failure = count
                    case "running": running = count
                    default: break
                    }
                }
                return TaskSummary(
                    totalRuns: total,
                    successCount: success,
                    failureCount: failure,
                    runningCount: running
                )
            }
        } catch {
            if isTableNotFoundError(error) { return TaskSummary() }
            throw error
        }
    }

    /// Get tasks of a specific type.
    public func tasksByType(_ type: String, limit: Int = 10) throws -> [TaskLogEntry] {
        do {
            return try db.writer.read { dbConn in
                try TaskLogEntry
                    .filter(Column("task_type") == type)
                    .order(Column("started_at").desc)
                    .limit(limit)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    /// Get currently running tasks.
    public func runningTasks() throws -> [TaskLogEntry] {
        do {
            return try db.writer.read { dbConn in
                try TaskLogEntry
                    .filter(Column("status") == "running")
                    .order(Column("started_at").desc)
                    .fetchAll(dbConn)
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Scheduled Maintenance Jobs
    // =========================================================================

    /// Run daily tools maintenance through the existing background task log.
    ///
    /// The confidence score update is intentionally throttled because it is a
    /// daily decay operation, not an idempotent status reconciliation. Expired
    /// trades are also safe to run through this path and remain idempotent after
    /// the first update.
    @discardableResult
    public func runToolsMaintenance(
        toolsService: ToolsService,
        minimumIntervalHours: Int = 24
    ) throws -> ToolsMaintenanceResult {
        let taskType = "tools_maintenance"
        let taskName = "Tools Maintenance"

        guard minimumIntervalHours > 0 else {
            return try performToolsMaintenance(
                toolsService: toolsService,
                taskName: taskName,
                taskType: taskType
            )
        }

        let cutoff = Date().addingTimeInterval(-Double(minimumIntervalHours) * 3600)
        guard try !hasRecentToolsMaintenanceTask(type: taskType, since: cutoff) else {
            return ToolsMaintenanceResult(
                didRun: false,
                expiredTrades: 0,
                updatedConfidenceScores: 0
            )
        }

        return try performToolsMaintenance(
            toolsService: toolsService,
            taskName: taskName,
            taskType: taskType
        )
    }

    // =========================================================================
    // MARK: - Cleanup
    // =========================================================================

    /// Delete log entries older than a specified number of days.
    /// Returns the count of deleted rows.
    @discardableResult
    public func cleanupOldEntries(daysToKeep: Int = 30) throws -> Int {
        do {
            return try db.writer.write { dbConn in
                let cutoff = Date().addingTimeInterval(-Double(daysToKeep) * 86400)

                try dbConn.execute(
                    sql: "DELETE FROM background_task_log WHERE started_at <= ?",
                    arguments: [cutoff]
                )
                return dbConn.changesCount
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    /// Mark any stale "running" tasks as failed (e.g., after app crash).
    /// Tasks running for more than `maxRunMinutes` are considered stale.
    @discardableResult
    public func cleanupStaleTasks(maxRunMinutes: Int = 60) throws -> Int {
        do {
            return try db.writer.write { dbConn in
                let cutoff = Date().addingTimeInterval(-Double(maxRunMinutes) * 60)

                try dbConn.execute(
                    sql: """
                        UPDATE background_task_log
                        SET status = 'failed',
                            completed_at = datetime('now'),
                            error_message = 'Task timed out (stale cleanup)'
                        WHERE status = 'running' AND started_at <= ?
                    """,
                    arguments: [cutoff]
                )
                return dbConn.changesCount
            }
        } catch {
            if isTableNotFoundError(error) { return 0 }
            throw error
        }
    }

    // =========================================================================
    // MARK: - Helpers
    // =========================================================================

    private func performToolsMaintenance(
        toolsService: ToolsService,
        taskName: String,
        taskType: String
    ) throws -> ToolsMaintenanceResult {
        let taskId = try startTask(name: taskName, type: taskType)
        do {
            let expiredTrades = try toolsService.expireOldTrades()
            let updatedConfidenceScores = try toolsService.updateConfidenceScores()
            let result = ToolsMaintenanceResult(
                didRun: true,
                expiredTrades: expiredTrades,
                updatedConfidenceScores: updatedConfidenceScores
            )
            try completeTask(
                id: taskId,
                summary: "Expired \(expiredTrades) trade(s), updated \(updatedConfidenceScores) confidence score(s)",
                itemsProcessed: result.itemsProcessed
            )
            return result
        } catch {
            try? failTask(id: taskId, error: error.localizedDescription)
            throw error
        }
    }

    private func hasRecentToolsMaintenanceTask(type: String, since: Date) throws -> Bool {
        do {
            return try db.writer.read { dbConn in
                let count = try Int.fetchOne(dbConn, sql: """
                    SELECT COUNT(*) FROM background_task_log
                    WHERE task_type = ?
                      AND status IN ('running', 'completed')
                      AND started_at >= ?
                    """, arguments: [type, since]) ?? 0
                return count > 0
            }
        } catch {
            if isTableNotFoundError(error) { return false }
            throw error
        }
    }

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
