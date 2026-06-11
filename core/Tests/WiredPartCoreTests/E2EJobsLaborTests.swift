import Foundation
import Testing
import GRDB
@testable import WiredPartCore

/// End-to-end tests for jobs and labor management.
///
/// Covers: job CRUD → clock in/out → labor entries → questionnaires → daily reports → team members → job parts.
@Suite("E2E: Jobs & Labor")
struct E2EJobsLaborTests {

    // MARK: - Job CRUD

    @Test("Full job lifecycle: create, read, update, list")
    func testJobLifecycle() throws {
        let env = try E2ETestHelpers.setUp()

        // Create
        let jobId = try env.jobs.createJob(
            jobNumber: "J-100",
            jobName: "Office Rewire",
            customerName: "Acme Corp",
            addressLine1: "123 Main St",
            city: "Springfield",
            state: "IL",
            status: "active",
            priority: "high",
            jobType: "service",
            createdBy: env.adminUserId
        )
        #expect(jobId > 0)

        // Read
        let job = try env.jobs.getJob(id: jobId)
        #expect(job.jobName == "Office Rewire")
        #expect(job.customerName == "Acme Corp")

        // Update
        try env.jobs.updateJob(id: jobId, status: "in_progress", notes: "Started work")
        let updated = try env.jobs.getJob(id: jobId)
        #expect(updated.status == "in_progress")

        // List
        let allJobs = try env.jobs.listJobs()
        #expect(allJobs.contains { $0.id == jobId })

        // List with filter
        let activeJobs = try env.jobs.listJobs(status: "in_progress")
        #expect(activeJobs.contains { $0.id == jobId })
    }

    @Test("Job search by name")
    func testJobSearch() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try env.jobs.createJob(jobNumber: "J-200", jobName: "Panel Upgrade", createdBy: env.adminUserId)
        _ = try env.jobs.createJob(jobNumber: "J-201", jobName: "Lighting Install", createdBy: env.adminUserId)

        let results = try env.jobs.listJobs(search: "Panel")
        #expect(results.count == 1)
        #expect(results[0].jobName == "Panel Upgrade")
    }

    // MARK: - Clock In / Clock Out

    @Test("Clock in and clock out creates labor entry with duration")
    func testClockInOut() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Clock in
        let entryId = try env.jobs.clockIn(
            userId: env.adminUserId,
            jobId: jobId,
            gpsLat: 39.7817,
            gpsLng: -89.6501
        )
        #expect(entryId > 0)

        // Check active entry
        let active = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(active != nil)
        #expect(active?.jobId == jobId)

        // Clock out
        let duration = try env.jobs.clockOut(
            laborEntryId: entryId,
            gpsLat: 39.7817,
            gpsLng: -89.6501
        )
        #expect(duration > 0) // At least 1 second

        // No active entry after clock out
        let afterClockOut = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(afterClockOut == nil)
    }

    // MARK: - Labor Entries

    @Test("Labor entries list by job and user")
    func testLaborEntries() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        _ = try env.jobs.clockOut(laborEntryId: entryId)

        // By job
        let jobEntries = try env.jobs.listLaborEntries(jobId: jobId)
        #expect(jobEntries.count == 1)

        // By user
        let userEntries = try env.jobs.listLaborEntries(userId: env.adminUserId)
        #expect(userEntries.count == 1)
    }

    @Test("Labor summary calculates total hours for job")
    func testLaborSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        _ = try env.jobs.clockOut(laborEntryId: entryId)

        let summary = try env.jobs.getLaborSummary(jobId: jobId)
        #expect(summary.totalEntries == 1)
    }

    // MARK: - Clock-Out Questionnaire

    @Test("Clock-out questionnaire responses are saved and retrievable")
    func testClockOutQuestionnaire() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Create a question (column is answer_type, not question_type per migration)
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO clock_out_questions (question_text, answer_type, is_active, sort_order, created_at, updated_at)
                VALUES ('What did you accomplish?', 'text', 1, 1, datetime('now'), datetime('now'))
                """)
        }

        let questions = try env.jobs.getActiveQuestions()
        #expect(!questions.isEmpty)

        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        _ = try env.jobs.clockOut(laborEntryId: entryId)

        let customQuestion = try #require(questions.first { $0.questionText == "What did you accomplish?" })
        let responsesToSave = questions.map { question in
            (
                questionId: question.questionId,
                answer: question.questionId == customQuestion.questionId
                    ? "Installed new panel"
                    : "Completed panel labeling and staged tomorrow's materials"
            )
        }

        try env.jobs.saveClockOutResponses(
            laborEntryId: entryId,
            responses: responsesToSave
        )

        let responses = try env.jobs.getResponsesForEntry(laborEntryId: entryId)
        #expect(responses.count == questions.count)
        #expect(responses.first { $0.questionId == customQuestion.questionId }?.answer == "Installed new panel")
        #expect(responses.contains { response in
            response.questionText.localizedCaseInsensitiveContains("daily report") &&
            response.answer == "Completed panel labeling and staged tomorrow's materials"
        })
    }

    // MARK: - One-Time Questions

    @Test("One-time question lifecycle")
    func testOneTimeQuestions() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let qId = try env.jobs.createOneTimeQuestion(
            jobId: jobId,
            text: "Did you check the breaker panel?",
            createdBy: env.adminUserId,
            targetUserId: env.adminUserId
        )
        #expect(qId > 0)

        let pending = try env.jobs.getPendingQuestions(userId: env.adminUserId)
        #expect(!pending.isEmpty)

        try env.jobs.answerOneTimeQuestion(
            questionId: qId,
            answerText: "Yes, all breakers tested",
            answeredBy: env.adminUserId
        )
    }

    // MARK: - Team Members

    @Test("Team member assignment")
    func testTeamMembers() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let memberId = try env.jobs.addTeamMember(
            jobId: jobId,
            userId: env.adminUserId,
            role: "lead"
        )
        #expect(memberId > 0)

        let team = try env.jobs.getTeamMembers(jobId: jobId)
        #expect(team.count == 1)

        try env.jobs.removeTeamMember(id: memberId)
        let afterRemove = try env.jobs.getTeamMembers(jobId: jobId)
        #expect(afterRemove.isEmpty)
    }

    // MARK: - Job Parts (Consumption)

    @Test("Consume parts on a job and track cost")
    func testJobPartConsumption() throws {
        let env = try E2ETestHelpers.setUp()
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try env.parts.createPart(
            categoryId: catId,
            name: "Wire",
            code: "WR-001",
            companyCostPrice: 10.0
        )
        _ = try E2ETestHelpers.seedStock(env, partId: partId, qty: 100)
        let jobId = try E2ETestHelpers.seedJob(env)

        let jobPartId = try env.jobs.addJobPart(
            jobId: jobId,
            partId: partId,
            qty: 5,
            costAtConsume: 10.0,
            performedBy: env.adminUserId
        )
        #expect(jobPartId > 0)

        let jobParts = try env.jobs.getJobParts(jobId: jobId)
        #expect(jobParts.count == 1)
        #expect(jobParts[0].qtyConsumed == 5)
    }

    // MARK: - Daily Reports

    @Test("Generate and retrieve daily report")
    func testDailyReport() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let reportId = try env.jobs.generateDailyReport(
            jobId: jobId,
            reportDate: "2026-03-15",
            reportJson: "{\"summary\":\"Completed panel install\"}",
            generatedBy: env.adminUserId
        )
        #expect(reportId > 0)

        let report = try env.jobs.getReport(id: reportId)
        #expect(report != nil)

        try env.jobs.markReportReviewed(reportId: reportId, reviewedBy: env.adminUserId)

        let reports = try env.jobs.listReports(jobId: jobId)
        #expect(reports.count == 1)
    }

    // MARK: - Job Stats

    @Test("Job stats reflect data")
    func testJobStats() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env)

        let stats = try env.jobs.getJobStats()
        #expect(stats.total >= 1)
    }

    @Test("Jobs dashboard KPIs")
    func testJobsDashboardKPIs() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env)

        let kpis = try env.jobs.getJobsDashboardKPIs()
        #expect(kpis.activeJobs >= 1)
    }
}
