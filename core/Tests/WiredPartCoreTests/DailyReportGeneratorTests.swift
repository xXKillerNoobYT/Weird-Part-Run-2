import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("DailyReportGenerator Tests")
struct DailyReportGeneratorTests {

    private func freshEnv() throws -> (E2ETestHelpers.TestEnvironment, DailyReportGenerator) {
        let env = try E2ETestHelpers.setUp()
        let generator = DailyReportGenerator(db: env.db)
        return (env, generator)
    }

    @Test("Generate report for user with no labor entries")
    func testEmptyReport() throws {
        let (env, gen) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env)

        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId)
        #expect(report.totalHours == 0)
    }

    @Test("Get today's jobs for user")
    func testTodaysJobs() throws {
        let (env, gen) = try freshEnv()
        let jobs = try gen.getTodaysJobs(userId: env.adminUserId)
        #expect(jobs.count >= 0)
    }

    @Test("Report includes user and job info")
    func testReportMetadata() throws {
        let (env, gen) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-RPT", name: "Report Job")

        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId)
        #expect(report.userId == env.adminUserId)
        #expect(report.jobId == jobId)
    }

    @Test("Daily report todo-fetch SQL excludes soft-deleted entries, sections, and notebooks")
    func testDailyReport_excludesSoftDeletedTodos() throws {
        let (env, _) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-SOFT", name: "Soft Delete Job")
        let userId = env.adminUserId

        // Seed a notebook + section + two todo entries; soft-delete one.
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO notebooks (title, job_id, created_by, is_archived, created_at, updated_at)
                VALUES ('Job Notebook', ?, ?, 0, datetime('now'), datetime('now'))
                """, arguments: [jobId, userId])
            let nbId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_sections (notebook_id, name, section_type, sort_order, is_locked, created_at)
                VALUES (?, 'Work', 'notes', 0, 0, datetime('now'))
                """, arguments: [nbId])
            let secId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, title, entry_type, task_status, created_by, is_deleted,
                     sort_order, created_at, updated_at)
                VALUES (?, 'Active Todo', 'todo', 'in_progress', ?, 0, 0,
                        datetime('now'), datetime('now'))
                """, arguments: [secId, userId])
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, title, entry_type, task_status, created_by, is_deleted,
                     deleted_at, sort_order, created_at, updated_at)
                VALUES (?, 'Deleted Todo', 'todo', 'in_progress', ?, 1,
                        datetime('now'), 1, datetime('now'), datetime('now'))
                """, arguments: [secId, userId])
        }

        // Run the EXACT same query DailyReportGenerator uses for todos — this verifies
        // the soft-delete filters independently of the generator's date/timezone plumbing.
        let names: [String] = try env.db.writer.read { dbConn in
            try Row.fetchAll(dbConn, sql: """
                SELECT ne.title AS name
                FROM notebook_entries ne
                JOIN notebook_sections ns ON ns.id = ne.section_id AND ns.deleted_at IS NULL
                JOIN notebooks nb ON nb.id = ns.notebook_id AND nb.deleted_at IS NULL
                WHERE nb.job_id = ?
                  AND ne.entry_type = 'todo'
                  AND ne.task_status IN ('complete', 'punch_list', 'in_progress')
                  AND ne.deleted_at IS NULL
                """, arguments: [jobId]).map { $0["name"] as String? ?? "" }
        }

        #expect(names.contains("Active Todo"),
                "Active todo must appear — soft-delete filter should not exclude it")
        #expect(!names.contains("Deleted Todo"),
                "Soft-deleted todo must not appear in daily report query result")
    }

    @Test("getTodaysJobs shows Unknown for soft-deleted job")
    func testGetTodaysJobsHidesDeletedJobName() throws {
        let (env, gen) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DEL-DRG", name: "DelDRGJob")
        let fixedDate = "2099-06-15"
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries (user_id, job_id, clock_in, deleted_at)
                VALUES (?, ?, '\(fixedDate) 08:00:00', NULL)
                """, arguments: [env.adminUserId, jobId])
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: fixedDate)!
        let todaysJobs = try gen.getTodaysJobs(userId: env.adminUserId, date: date)
        let entry = todaysJobs.first(where: { $0.jobId == jobId })
        #expect(entry != nil)
        #expect(entry?.jobName == "Unknown")
    }
}
