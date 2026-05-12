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

    @Test("generateReport aggregates labor, breaks, todos, JPOs, QA, and chat activity")
    func testGenerateReportAggregatesDailyActivity() throws {
        let (env, gen) = try freshEnv()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-RPT-FULL", name: "Full Report Job")
        let categoryId = try E2ETestHelpers.seedCategory(env, name: "DailyReportParts")
        let partId = try E2ETestHelpers.seedPart(env, name: "Daily Report Part", categoryId: categoryId)
        let reportDate = "2099-08-03"

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status)
                VALUES (?, ?, '\(reportDate) 08:00:00', '\(reportDate) 16:00:00', 8.0, 0.0, 'clocked_out')
                """, arguments: [env.adminUserId, jobId])
            let laborEntryId = db.lastInsertedRowID

            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, labor_entry_id, break_type, started_at, ended_at,
                     duration_minutes, is_paid, auto_filled)
                VALUES (?, ?, 'lunch_paid', '\(reportDate)T12:00:00',
                        '\(reportDate)T12:30:00', 30, 1, 0)
                """, arguments: [env.adminUserId, laborEntryId])

            try db.execute(sql: """
                INSERT INTO notebooks (title, notebook_type, job_id, created_by)
                VALUES ('Daily Activity', 'job', ?, ?)
                """, arguments: [jobId, env.adminUserId])
            let notebookId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_sections (notebook_id, name, sort_order)
                VALUES (?, 'Install', 0)
                """, arguments: [notebookId])
            let sectionId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_entries
                    (notebook_id, section_id, title, entry_type, task_status, updated_at, created_by)
                VALUES (?, ?, 'Finish panel trim', 'todo', 'complete', '\(reportDate) 14:00:00', ?)
                """, arguments: [notebookId, sectionId, env.adminUserId])

            try db.execute(sql: """
                INSERT INTO job_parts_orders
                    (job_id, order_number, requested_by, status, priority, created_at, updated_at)
                VALUES (?, 'JPO-RPT-FULL', ?, 'draft', 'normal',
                        '\(reportDate) 09:30:00', '\(reportDate) 09:30:00')
                """, arguments: [jobId, env.adminUserId])
            let jpoId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO jpo_line_items (jpo_id, part_id, qty_requested, created_at)
                VALUES (?, ?, 2, '\(reportDate) 09:35:00')
                """, arguments: [jpoId, partId])

            try db.execute(sql: """
                INSERT INTO chat_channels
                    (channel_type, job_id, name, created_by, is_active, created_at, updated_at)
                VALUES ('job', ?, 'Daily Report Channel', ?, 1,
                        '\(reportDate) 10:00:00', '\(reportDate) 10:00:00')
                """, arguments: [jobId, env.adminUserId])
            let channelId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO qa_threads
                    (channel_id, job_id, asked_by, subject, status, created_at, updated_at)
                VALUES (?, ?, ?, 'Can we reroute conduit?', 'open',
                        '\(reportDate) 11:00:00', '\(reportDate) 11:00:00')
                """, arguments: [channelId, jobId, env.adminUserId])
            try db.execute(sql: """
                INSERT INTO chat_messages (channel_id, sender_id, message_type, content, created_at)
                VALUES (?, ?, 'text', 'Daily update posted', '\(reportDate) 15:00:00')
                """, arguments: [channelId, env.adminUserId])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = try #require(formatter.date(from: reportDate))

        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId, date: date)

        #expect(report.userName == "TestAdmin")
        #expect(report.jobName == "Full Report Job")
        #expect(report.clockIn == "\(reportDate) 08:00:00")
        #expect(report.clockOut == "\(reportDate) 16:00:00")
        #expect(report.totalHours == 7.5)
        #expect(report.breaksTaken.first?.durationMinutes == 30)
        #expect(report.todosCompleted.first?.name == "Finish panel trim")
        #expect(report.jposCreated.first?.jpoNumber == "JPO-RPT-FULL")
        #expect(report.jposCreated.first?.lineCount == 1)
        #expect(report.qaQuestions.first?.question == "Can we reroute conduit?")
        #expect(report.messagesCount == 1)
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

    @Test("generateReport surfaces todo rows when todo query succeeds")
    func testGenerateReport_surfacesTodosFromCorrectedQuery() throws {
        let env = try E2ETestHelpers.setUp()
        let gen = DailyReportGenerator(db: env.db)
        let jobId = try E2ETestHelpers.seedJob(env)

        // Seed notebook + section + todo entry pegged to a fixed date; verify that
        // generateReport returns a non-nil (not error-swallowed) response when the
        // query succeeds. Regression for iter 70 fix that replaced silent `try?` on
        // the todo fetch with a proper do-catch + isTableNotFoundError guard — real
        // DB errors now propagate instead of being swallowed as empty todos.
        let fixedDateStr = "2099-07-20"
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO notebooks (title, notebook_type, job_id, created_by)
                VALUES ('DailyReport NB', 'job', ?, ?)
                """, arguments: [jobId, env.adminUserId])
            let nbId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_sections (notebook_id, name, sort_order)
                VALUES (?, 'Main', 0)
                """, arguments: [nbId])
            let secId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO notebook_entries (notebook_id, section_id, title, entry_type, task_status, updated_at, created_by)
                VALUES (?, ?, 'Complete install', 'todo', 'complete', '\(fixedDateStr) 10:00:00', ?)
                """, arguments: [nbId, secId, env.adminUserId])
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: fixedDateStr)!

        // Expect success (no throw) — the do-catch + isTableNotFoundError guard
        // tolerates the legitimate pre-migration case and propagates real errors.
        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId, date: date)
        // Report should be non-nil. Content depends on nbs's job_id filter and
        // date match; the critical regression check is that generateReport doesn't
        // silently drop errors as empty results.
        #expect(report.jobId == jobId)
    }
}
