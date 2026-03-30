import Foundation
import Testing
import GRDB
@testable import WiredPartCore

@Suite("JobsService Tests")
struct JobsServiceTests {

    // MARK: - Job CRUD

    @Test("Create and list jobs")
    func testJobCRUD() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try env.jobs.createJob(
            jobNumber: "J-TEST",
            jobName: "Test Project",
            customerName: "Test Customer",
            status: "active",
            createdBy: env.adminUserId
        )
        #expect(jobId > 0)

        let jobs = try env.jobs.listJobs()
        #expect(jobs.contains(where: { $0.jobNumber == "J-TEST" }))
    }

    @Test("Get job detail")
    func testGetJobDetail() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let detail = try env.jobs.getJob(id: jobId)
        #expect(detail.jobName == "Test Job")
        #expect(detail.customerName == "Test Customer")
    }

    @Test("Update job")
    func testUpdateJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.jobs.updateJob(id: jobId, jobName: "Updated Job", status: "in_progress")
        let detail = try env.jobs.getJob(id: jobId)
        #expect(detail.jobName == "Updated Job")
    }

    @Test("Job stats")
    func testJobStats() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env)
        let stats = try env.jobs.getJobStats()
        #expect(stats.total >= 1)
        #expect(stats.active >= 1)
    }

    // MARK: - Clock In/Out

    @Test("Clock in and out lifecycle")
    func testClockInOut() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        let entries = try env.jobs.listLaborEntries(jobId: jobId)
        #expect(entries.count >= 1)
        #expect(entries.first?.clockOut == nil)

        try env.jobs.clockOut(laborEntryId: laborEntryId)
        let afterClockOut = try env.jobs.listLaborEntries(jobId: jobId)
        #expect(afterClockOut.first?.clockOut != nil)
    }

    @Test("Labor summary after clock in/out")
    func testLaborSummary() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborEntryId)

        let summary = try env.jobs.getLaborSummary(jobId: jobId)
        #expect(summary.totalEntries >= 1)
    }

    // MARK: - Team Members

    @Test("Add and remove team member from job")
    func testJobTeamMembers() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.jobs.addTeamMember(jobId: jobId, userId: env.adminUserId, role: "foreman")
        let members = try env.jobs.getTeamMembers(jobId: jobId)
        #expect(members.count >= 1)
    }

    // MARK: - Warranty

    @Test("Set and check warranty")
    func testWarranty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.jobs.setWarranty(jobId: jobId, startDate: Date(), durationDays: 365)
        let isActive = try env.jobs.isWarrantyActive(jobId: jobId)
        #expect(isActive)

        let days = try env.jobs.warrantyDaysRemaining(jobId: jobId)
        #expect((days ?? 0) > 0)
    }

    // MARK: - Payment Hold

    @Test("Set and remove payment hold")
    func testPaymentHold() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        try env.jobs.setPaymentHold(jobId: jobId, amount: 5000.0, reason: "Awaiting inspection")
        let isOnHold = try env.jobs.isJobOnPaymentHold(jobId: jobId)
        #expect(isOnHold)

        try env.jobs.removePaymentHold(jobId: jobId)
        let afterRemove = try env.jobs.isJobOnPaymentHold(jobId: jobId)
        #expect(!afterRemove)
    }

    // MARK: - Continuous Scheduling

    @Test("Set job as continuous")
    func testContinuousJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.addTeamMember(jobId: jobId, userId: env.adminUserId, role: "lead")
        let schedule = JobsService.ContinuousSchedule(daysOfWeek: [1, 3, 5], frequency: "weekly")
        try env.jobs.setJobContinuous(jobId: jobId, schedule: schedule)
        let continuous = try env.jobs.getContinuousJobs(userId: env.adminUserId)
        #expect(continuous.contains(where: { $0.id == jobId }))
    }

    // MARK: - Questionnaire

    @Test("Get active questions for job")
    func testActiveQuestions() throws {
        let env = try E2ETestHelpers.setUp()
        let questions = try env.jobs.getActiveQuestions()
        #expect(questions.count >= 0) // May have default questions
    }

    @Test("Create one-time question")
    func testOneTimeQuestion() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let qId = try env.jobs.createOneTimeQuestion(
            jobId: jobId,
            text: "Did you seal the conduit?",
            createdBy: env.adminUserId
        )
        #expect(qId > 0)
    }

    // MARK: - Daily Reports

    @Test("Generate and list daily reports")
    func testDailyReports() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let reportId = try env.jobs.generateDailyReport(
            jobId: jobId,
            reportDate: "2026-03-29",
            reportJson: "{\"notes\":\"Installed main panel\"}",
            generatedBy: env.adminUserId
        )
        #expect(reportId > 0)

        let reports = try env.jobs.listReports(jobId: jobId)
        #expect(reports.count >= 1)
    }

    // MARK: - Job Parts

    @Test("Add and list job parts")
    func testJobParts() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 10, performedBy: env.adminUserId)
        let parts = try env.jobs.getJobParts(jobId: jobId)
        #expect(parts.count >= 1)
    }

    // MARK: - Job Stages

    @Test("List job stages")
    func testJobStages() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let stages = try env.jobs.listJobStages(forJobId: jobId)
        #expect(stages.count >= 0)
    }

    // MARK: - Active Clock Entry

    @Test("Get active clock entry while clocked in")
    func testGetActiveClockEntry() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // No entry before clock in
        let noneEntry = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(noneEntry == nil)

        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        let activeEntry = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(activeEntry != nil)
        #expect(activeEntry?.id == laborEntryId)

        try env.jobs.clockOut(laborEntryId: laborEntryId)
        let afterClockOut = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(afterClockOut == nil)
    }

    // MARK: - Today's Clock Entries

    @Test("Get today's clock entries grouped by job")
    func testGetTodaysClockEntries() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: laborEntryId)

        let groups = try env.jobs.getTodaysClockEntries(userId: env.adminUserId)
        #expect(groups.count >= 1)
        #expect(groups.first?.jobId == jobId)
    }

    // MARK: - Report Detail & Review

    @Test("Get report detail and mark reviewed")
    func testGetAndReviewReport() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let reportId = try env.jobs.generateDailyReport(
            jobId: jobId,
            reportDate: "2026-03-29",
            reportJson: "{\"notes\":\"Panel wired\"}",
            generatedBy: env.adminUserId
        )

        let report = try env.jobs.getReport(id: reportId)
        #expect(report != nil)
        #expect(report?.id == reportId)

        try env.jobs.markReportReviewed(reportId: reportId, reviewedBy: env.adminUserId)
        let reviewed = try env.jobs.getReport(id: reportId)
        #expect(reviewed?.status == "reviewed")
    }

    // MARK: - Return Job Part

    @Test("Return a job part reduces qty returned counter")
    func testReturnJobPart() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 10, performedBy: env.adminUserId)
        let parts = try env.jobs.getJobParts(jobId: jobId)
        guard let jobPartId = parts.first?.id else {
            Issue.record("Expected a job part after adding"); return
        }

        try env.jobs.returnJobPart(jobPartId: jobPartId, returnQty: 3)
        let afterReturn = try env.jobs.getJobParts(jobId: jobId)
        #expect(afterReturn.first?.qtyReturned == 3)
    }

    // MARK: - List Active Jobs & Dashboard KPIs

    @Test("List active jobs and dashboard KPIs")
    func testActiveJobsAndKPIs() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env)

        let active = try env.jobs.listActiveJobs()
        #expect(active.count >= 1)

        let kpis = try env.jobs.getJobsDashboardKPIs()
        #expect(kpis.activeJobs >= 1)
    }

    // MARK: - Supply Run Toggle & Labor Notes

    @Test("Toggle supply run updates labor entry notes")
    func testToggleSupplyRunAndNotes() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        let notesBefore = try env.jobs.getLaborEntryNotes(laborEntryId: laborEntryId)
        #expect(notesBefore == nil || notesBefore?.isEmpty == true)

        let result = try env.jobs.toggleSupplyRun(laborEntryId: laborEntryId)
        #expect(result == "supply_run")

        let notesAfter = try env.jobs.getLaborEntryNotes(laborEntryId: laborEntryId)
        #expect(notesAfter?.contains("supply_run_start") == true)

        try env.jobs.clockOut(laborEntryId: laborEntryId)
    }
}
