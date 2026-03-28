import Foundation
import GRDB

/// Auto-populates daily reports from system data (clock events, to-dos, parts, Q&A).
public final class DailyReportGenerator: Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Report Data Models

    public struct DailyReportData: Codable, Sendable {
        public let date: String
        public let userId: Int64
        public let userName: String
        public let jobId: Int64
        public let jobName: String
        public let clockIn: String?
        public let clockOut: String?
        public let totalHours: Double
        public let breaksTaken: [BreakSummary]
        public let todosCompleted: [TodoSummary]
        public let jposCreated: [JPOSummary]
        public let qaQuestions: [QASummary]
        public let messagesCount: Int
        public var userNotes: String?
    }

    public struct BreakSummary: Codable, Sendable {
        public let type: String
        public let startTime: String
        public let durationMinutes: Int
    }

    public struct TodoSummary: Codable, Sendable {
        public let name: String
        public let stage: String
    }

    public struct JPOSummary: Codable, Sendable {
        public let jpoNumber: String
        public let lineCount: Int
    }

    public struct QASummary: Codable, Sendable {
        public let question: String
        public let status: String
    }

    // MARK: - Generate Report

    /// Generate daily report data from system records for a user on a job.
    public func generateReport(userId: Int64, jobId: Int64, date: Date = Date()) throws -> DailyReportData {
        let dateStr = formatDate(date)

        do { return try db.writer.read { dbConn in
            let userName = try String.fetchOne(dbConn, sql: """
                SELECT COALESCE(display_name, email, 'Unknown')
                FROM users WHERE id = ?
                """, arguments: [userId]) ?? "Unknown"

            let jobName = try String.fetchOne(dbConn, sql: """
                SELECT COALESCE(job_name, job_number, 'Unknown') FROM jobs WHERE id = ?
                """, arguments: [jobId]) ?? "Unknown"

            let clockRows = try Row.fetchAll(dbConn, sql: """
                SELECT clock_in, clock_out, regular_hours, overtime_hours
                FROM labor_entries
                WHERE user_id = ? AND job_id = ? AND date(clock_in) = ?
                  AND deleted_at IS NULL
                ORDER BY clock_in ASC
                """, arguments: [userId, jobId, dateStr])

            let clockIn = clockRows.first?["clock_in"] as String?
            let clockOut = clockRows.last?["clock_out"] as String?
            var totalMinutes: Double = 0
            var totalBreakMinutes: Int = 0

            for row in clockRows {
                let cin: String = row["clock_in"] ?? ""
                let cout: String? = row["clock_out"]
                if let inDate = parseDateTime(cin) {
                    let outDate = cout.flatMap { parseDateTime($0) } ?? date
                    totalMinutes += outDate.timeIntervalSince(inDate) / 60
                }
            }

            // Get break minutes from break_records table
            totalBreakMinutes = try Int.fetchOne(dbConn, sql: """
                SELECT COALESCE(SUM(
                    CAST((julianday(COALESCE(ended_at, datetime('now'))) - julianday(started_at)) * 1440 AS INTEGER)
                ), 0)
                FROM break_records
                WHERE user_id = ? AND date(started_at) = ? AND deleted_at IS NULL
                """, arguments: [userId, dateStr]) ?? 0

            let totalHours = max(0, (totalMinutes - Double(totalBreakMinutes))) / 60.0

            var breaks: [BreakSummary] = []
            if totalBreakMinutes > 0 {
                breaks.append(BreakSummary(type: "break", startTime: "", durationMinutes: totalBreakMinutes))
            }

            let todoRows = try Row.fetchAll(dbConn, sql: """
                SELECT te.name, te.current_stage
                FROM todo_entries te
                WHERE te.job_id = ? AND date(te.updated_at) = ?
                  AND te.current_stage IN ('complete', 'punch_list', 'in_progress')
                ORDER BY te.updated_at DESC
                LIMIT 50
                """, arguments: [jobId, dateStr])

            let todos = todoRows.map { row in
                TodoSummary(name: row["name"] ?? "", stage: row["current_stage"] ?? "")
            }

            let jpoRows = try Row.fetchAll(dbConn, sql: """
                SELECT jpo.order_number, COUNT(jpol.id) as line_count
                FROM job_parts_orders jpo
                LEFT JOIN jpo_line_items jpol ON jpol.jpo_id = jpo.id
                WHERE jpo.job_id = ? AND date(jpo.created_at) = ?
                  AND jpo.deleted_at IS NULL
                GROUP BY jpo.id
                ORDER BY jpo.created_at DESC
                """, arguments: [jobId, dateStr])

            let jpos = jpoRows.map { row in
                JPOSummary(jpoNumber: row["order_number"] ?? "", lineCount: row["line_count"] ?? 0)
            }

            let qaRows = try Row.fetchAll(dbConn, sql: """
                SELECT qt.question, qt.status
                FROM qa_threads qt
                WHERE qt.job_id = ? AND date(qt.created_at) = ?
                  AND qt.deleted_at IS NULL
                ORDER BY qt.created_at DESC
                LIMIT 20
                """, arguments: [jobId, dateStr])

            let qaQuestions = qaRows.map { row in
                QASummary(question: row["question"] ?? "", status: row["status"] ?? "open")
            }

            let messagesCount = try Int.fetchOne(dbConn, sql: """
                SELECT COUNT(*) FROM chat_messages
                WHERE user_id = ? AND date(created_at) = ?
                  AND deleted_at IS NULL
                """, arguments: [userId, dateStr]) ?? 0

            return DailyReportData(
                date: dateStr, userId: userId, userName: userName,
                jobId: jobId, jobName: jobName,
                clockIn: clockIn, clockOut: clockOut,
                totalHours: totalHours, breaksTaken: breaks,
                todosCompleted: todos, jposCreated: jpos,
                qaQuestions: qaQuestions, messagesCount: messagesCount,
                userNotes: nil
            )
        }
        } catch {
            if isTableNotFoundError(error) {
                return DailyReportData(
                    date: dateStr, userId: userId, userName: "Unknown",
                    jobId: jobId, jobName: "Unknown",
                    clockIn: nil, clockOut: nil,
                    totalHours: 0, breaksTaken: [],
                    todosCompleted: [], jposCreated: [],
                    qaQuestions: [], messagesCount: 0,
                    userNotes: nil
                )
            }
            throw error
        }
    }

    /// Get today's jobs for a user to determine primary job.
    public func getTodaysJobs(userId: Int64, date: Date = Date()) throws -> [(jobId: Int64, jobName: String, hours: Double)] {
        let dateStr = formatDate(date)
        do {
            return try db.writer.read { dbConn in
                let rows = try Row.fetchAll(dbConn, sql: """
                    SELECT le.job_id,
                           COALESCE(j.job_name, j.job_number, 'Unknown') as job_name,
                           SUM(
                               (julianday(COALESCE(le.clock_out, datetime('now'))) - julianday(le.clock_in)) * 24
                           ) as total_hours
                    FROM labor_entries le
                    LEFT JOIN jobs j ON j.id = le.job_id
                    WHERE le.user_id = ? AND date(le.clock_in) = ?
                      AND le.deleted_at IS NULL
                    GROUP BY le.job_id
                    ORDER BY total_hours DESC
                    """, arguments: [userId, dateStr])
                return rows.map { row in
                    (
                        jobId: row["job_id"] as Int64? ?? 0,
                        jobName: row["job_name"] as String? ?? "Unknown",
                        hours: row["total_hours"] as Double? ?? 0
                    )
                }
            }
        } catch {
            if isTableNotFoundError(error) { return [] }
            throw error
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func parseDateTime(_ str: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        if let d = f2.date(from: str) { return d }
        let f3 = DateFormatter()
        f3.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f3.date(from: str)
    }

    private func isTableNotFoundError(_ error: Error) -> Bool {
        let message = String(describing: error)
        return message.contains("no such table") || message.contains("no such column")
    }
}
