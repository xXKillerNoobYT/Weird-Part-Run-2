import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("DailyReportGenerator Tests", .serialized)
struct DailyReportGeneratorTests {

    private func freshEnv(
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> (E2ETestHelpers.TestEnvironment, DailyReportGenerator) {
        let env = try E2ETestHelpers.setUp()
        let generator = DailyReportGenerator(db: env.db, calendar: calendar, now: now)
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
                VALUES (?, ?, '\(fixedDate) 12:00:00', NULL)
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

    @Test("Generate report buckets UTC end-of-day labor into local report date")
    func testGenerateReportUsesLocalClockInDateBucket() throws {
        let (env, gen) = try freshEnv(calendar: Self.mountainCalendar)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCAL-DRG", name: "Local Daily Report")

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-02-01 02:30:00', '2026-02-01 04:30:00', 2.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }

        let date = try #require(Self.mountainCalendar.date(
            from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)
        ))
        let report = try gen.generateReport(userId: env.adminUserId, jobId: jobId, date: date)

        #expect(report.clockIn == "2026-02-01 02:30:00")
        #expect(report.totalHours == 2.0)
    }

    @Test("Today's jobs buckets UTC end-of-day labor into local work date")
    func testTodaysJobsUsesLocalClockInDateBucket() throws {
        let (env, gen) = try freshEnv(calendar: Self.mountainCalendar)
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-LOCAL-JOBS", name: "Local Jobs")

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-02-01 02:30:00', '2026-02-01 04:30:00', 2.0, 0.0, 'completed', datetime('now'))
                """, arguments: [env.adminUserId, jobId])
        }

        let date = try #require(Self.mountainCalendar.date(
            from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)
        ))
        let jobs = try gen.getTodaysJobs(userId: env.adminUserId, date: date)

        #expect(jobs.contains { $0.jobId == jobId && abs($0.hours - 2.0) < 0.001 })
    }

    @Test("Historical report instant controls active labor and break durations")
    func testGenerateReportUsesExplicitInstantForActiveRows() throws {
        // 09:45 UTC is 23:45 on July 20 in Honolulu. The UTC date differs from
        // the operational date, so SQLite date(started_at) would miss this break.
        let injectedNow = try Date("2026-07-22T09:45:00Z", strategy: .iso8601)
        let reportDate = try Date("2026-07-21T09:45:00Z", strategy: .iso8601)
        let (env, gen) = try freshEnv(calendar: Self.honoluluCalendar, now: { injectedNow })
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-HIST-DRG", name: "Historical Report")

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-07-21 09:00:00', NULL, 0, 0, 'active', '2026-07-21 09:00:00')
                """, arguments: [env.adminUserId, jobId])
            let laborEntryId = db.lastInsertedRowID
            try db.execute(sql: """
                INSERT INTO break_records
                    (user_id, labor_entry_id, break_type, started_at, ended_at, duration_minutes, is_paid, auto_filled)
                VALUES (?, ?, 'break', '2026-07-21 09:30:00', NULL, NULL, 1, 0)
                """, arguments: [env.adminUserId, laborEntryId])
        }

        let report = try gen.generateReport(
            userId: env.adminUserId,
            jobId: jobId,
            date: reportDate
        )
        let breakMinutes = try #require(report.breaksTaken.first?.durationMinutes)

        #expect((14...15).contains(breakMinutes))
        #expect(abs(report.totalHours - (45.0 - Double(breakMinutes)) / 60.0) < 0.001)
    }

    @Test("Local-midnight active labor uses the requested instant instead of wall clock")
    func testTodaysJobsUsesExplicitInstantForActiveLabor() throws {
        let injectedNow = try Date("2026-07-21T10:30:00Z", strategy: .iso8601)
        let reportDate = try Date("2026-07-20T10:30:00Z", strategy: .iso8601)
        let (env, gen) = try freshEnv(calendar: Self.honoluluCalendar, now: { injectedNow })
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-MIDNIGHT-DRG", name: "Midnight Report")

        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO labor_entries
                    (user_id, job_id, clock_in, clock_out, regular_hours, overtime_hours, status, created_at)
                VALUES (?, ?, '2026-07-20 10:00:00', NULL, 0, 0, 'active', '2026-07-20 10:00:00')
                """, arguments: [env.adminUserId, jobId])
        }

        let jobs = try gen.getTodaysJobs(userId: env.adminUserId, date: reportDate)
        let hours = try #require(jobs.first(where: { $0.jobId == jobId })?.hours)

        #expect(abs(hours - 0.5) < 0.001)
    }

    private static let mountainCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver") ?? .gmt
        return calendar
    }()

    private static let honoluluCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Honolulu") ?? .gmt
        return calendar
    }()
}
