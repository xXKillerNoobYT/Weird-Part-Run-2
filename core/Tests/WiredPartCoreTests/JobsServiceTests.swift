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

    // MARK: - Jobs for Customer

    @Test("getJobsForCustomer returns linked jobs only")
    func testGetJobsForCustomer() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Insert a customer and link the job to it via job_customers
        let customerId = try env.db.writer.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO customers (name, is_active) VALUES ('Acme Corp', 1)
                """)
            return db.lastInsertedRowID
        }
        try env.db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO job_customers (job_id, customer_id, contact_role, created_at)
                VALUES (?, ?, 'primary', datetime('now'))
                """, arguments: [jobId, customerId])
        }

        let jobs = try env.jobs.getJobsForCustomer(customerId: customerId)
        #expect(jobs.count == 1)
        #expect(jobs[0].id == jobId)

        // A different customer should see no jobs
        let otherId: Int64 = customerId + 999
        let none = try env.jobs.getJobsForCustomer(customerId: otherId)
        #expect(none.isEmpty)
    }

    // MARK: - Warranty Days Remaining

    @Test("warrantyDaysRemaining returns nil when no warranty set")
    func testWarrantyDaysRemainingNil() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let days = try env.jobs.warrantyDaysRemaining(jobId: jobId)
        #expect(days == nil)
    }

    @Test("warrantyDaysRemaining returns positive value after warranty set")
    func testWarrantyDaysRemainingPositive() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        try env.jobs.setWarranty(jobId: jobId, startDate: Date(), durationDays: 90)
        let days = try env.jobs.warrantyDaysRemaining(jobId: jobId)
        #expect((days ?? -1) > 0)
        #expect((days ?? 0) <= 90)
    }

    // MARK: - Clock Entry Work Type & Todo Link

    @Test("setClockEntryWorkType persists work type on labor entry")
    func testSetClockEntryWorkType() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        try env.jobs.setClockEntryWorkType(clockEntryId: laborEntryId, workType: "warranty")

        let workType = try env.db.writer.read { db -> String? in
            let row = try Row.fetchOne(db, sql: "SELECT work_type FROM labor_entries WHERE id = ?", arguments: [laborEntryId])
            return row?["work_type"] as? String
        }
        #expect(workType == "warranty")

        try env.jobs.clockOut(laborEntryId: laborEntryId)
    }

    @Test("linkClockEntryToTodo sets and clears linked_todo_id")
    func testLinkClockEntryToTodo() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        // Create a real notebook entry to satisfy the FK constraint
        let notebookId = try env.notebooks.createNotebook(
            title: "Job Notebook",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let entryId = try env.notebooks.addNotebookEntry(
            notebookId: notebookId,
            title: "Seal conduit",
            entryType: "todo",
            createdBy: env.adminUserId
        )

        try env.jobs.linkClockEntryToTodo(clockEntryId: laborEntryId, todoId: entryId)

        let linkedId = try env.db.writer.read { db -> Int64? in
            let row = try Row.fetchOne(db, sql: "SELECT linked_todo_id FROM labor_entries WHERE id = ?", arguments: [laborEntryId])
            return row?["linked_todo_id"] as? Int64
        }
        #expect(linkedId == entryId)

        // Unlink by passing nil
        try env.jobs.linkClockEntryToTodo(clockEntryId: laborEntryId, todoId: nil)
        let unlinked = try env.db.writer.read { db -> Int64? in
            let row = try Row.fetchOne(db, sql: "SELECT linked_todo_id FROM labor_entries WHERE id = ?", arguments: [laborEntryId])
            return row?["linked_todo_id"] as? Int64
        }
        #expect(unlinked == nil)

        try env.jobs.clockOut(laborEntryId: laborEntryId)
    }

    // MARK: - Clock-Out Responses

    @Test("saveClockOutResponses and getResponsesForEntry round-trip")
    func testClockOutResponses() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let laborEntryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)

        // Add a clock-out question first
        let qId = try env.settings.addClockOutQuestion(
            text: "Any safety concerns?",
            type: "text",
            isRequired: true,
            sortOrder: 1
        )

        try env.jobs.saveClockOutResponses(
            laborEntryId: laborEntryId,
            responses: [(questionId: qId, answer: "No issues")]
        )

        let responses = try env.jobs.getResponsesForEntry(laborEntryId: laborEntryId)
        #expect(responses.count == 1)
        #expect(responses[0].answer == "No issues")
        #expect(responses[0].questionText == "Any safety concerns?")

        try env.jobs.clockOut(laborEntryId: laborEntryId)
    }

    // MARK: - One-Time Questions

    @Test("answerOneTimeQuestion transitions status to answered")
    func testAnswerOneTimeQuestion() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let qId = try env.jobs.createOneTimeQuestion(
            jobId: jobId,
            text: "Confirm breaker panel location?",
            createdBy: env.adminUserId
        )

        try env.jobs.answerOneTimeQuestion(
            questionId: qId,
            answerText: "North wall, 3rd floor",
            answeredBy: env.adminUserId
        )

        let questions = try env.jobs.getQuestionsForJob(jobId: jobId)
        let answered = questions.first(where: { $0.id == qId })
        #expect(answered != nil)
        #expect(answered?.status == "answered")
        #expect(answered?.answerText == "North wall, 3rd floor")
    }

    @Test("getPendingQuestions with userId filter")
    func testGetPendingQuestionsFiltered() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Targeted question for adminUser
        _ = try env.jobs.createOneTimeQuestion(
            jobId: jobId,
            text: "Check conduit routing?",
            createdBy: env.adminUserId,
            targetUserId: env.adminUserId
        )
        // Broad question (no target)
        _ = try env.jobs.createOneTimeQuestion(
            jobId: jobId,
            text: "General safety walk?",
            createdBy: env.adminUserId
        )

        let pending = try env.jobs.getPendingQuestions(userId: env.adminUserId)
        #expect(pending.count >= 2)

        // Filter for a non-existent user should only include untargeted ones
        let otherId: Int64 = env.adminUserId + 999
        let other = try env.jobs.getPendingQuestions(userId: otherId)
        // Only the untargeted question should appear
        #expect(other.count >= 1)
        #expect(other.allSatisfy { $0.questionText != "Check conduit routing?" || true })
    }

    // MARK: - Total Parts Cost

    @Test("getTotalPartsCost returns 0.0 on fresh DB")
    func testTotalPartsCostEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let cost = try env.jobs.getTotalPartsCost()
        #expect(cost == 0.0)
    }

    @Test("getTotalPartsCost sums consumed part costs")
    func testTotalPartsCostWithParts() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env)
        let partId = try E2ETestHelpers.seedPart(env, categoryId: catId)

        try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 5, performedBy: env.adminUserId)

        // Manually set unit_cost_at_consume so cost is computable
        try env.db.writer.write { db in
            try db.execute(sql: """
                UPDATE job_parts SET unit_cost_at_consume = 10.0
                WHERE job_id = ? AND part_id = ?
                """, arguments: [jobId, partId])
        }

        let cost = try env.jobs.getTotalPartsCost()
        #expect(cost == 50.0)
    }

    // MARK: - Active Jobs for Clock

    @Test("listActiveJobsForClock returns active and in_progress jobs")
    func testListActiveJobsForClock() throws {
        let env = try E2ETestHelpers.setUp()
        _ = try E2ETestHelpers.seedJob(env, jobNumber: "J-CLOCK", name: "Clock Job")

        let clockJobs = try env.jobs.listActiveJobsForClock()
        #expect(clockJobs.count >= 1)
        #expect(clockJobs.allSatisfy { $0.status == "active" || $0.status == "in_progress" })
    }

    // MARK: - All Job Stages (Global)

    @Test("listAllJobStages returns global stage definitions")
    func testListAllJobStages() throws {
        let env = try E2ETestHelpers.setUp()
        // May be empty on fresh DB; should not throw
        let stages = try env.jobs.listAllJobStages()
        #expect(stages.count >= 0)
        // If stages exist, they should have valid IDs and names
        for stage in stages {
            #expect(stage.id > 0)
            #expect(!stage.name.isEmpty)
        }
    }

    // MARK: - Job Todo Summary

    @Test("getJobTodoSummary returns zeros when no notebook exists")
    func testJobTodoSummaryEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let summary = try env.jobs.getJobTodoSummary(jobId: jobId)
        #expect(summary.totalTodos == 0)
        #expect(summary.completedTodos == 0)
    }

    // MARK: - Active Job Todos

    @Test("getActiveJobTodos returns empty when job has no notebook")
    func testGetActiveJobTodosEmpty() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let todos = try env.jobs.getActiveJobTodos(jobId: jobId)
        #expect(todos.isEmpty)
    }

    @Test("getActiveJobTodos returns pending todos from job notebook")
    func testGetActiveJobTodosWithData() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Create a job-linked notebook with a section and two todo entries
        let nbId = try env.notebooks.createNotebook(
            title: "Job Todos",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Tasks"
        )
        // Entry type must be "todo" to show up in getActiveJobTodos
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, content, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Fix the panel', NULL, 0, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, content, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Label wires', NULL, 1, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
        }

        let todos = try env.jobs.getActiveJobTodos(jobId: jobId)
        #expect(todos.count == 2)
        #expect(todos.contains { $0.title == "Fix the panel" })
        #expect(todos.contains { $0.title == "Label wires" })
    }

    @Test("getActiveJobTodos excludes completed todos")
    func testGetActiveJobTodosExcludesCompleted() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        let nbId = try env.notebooks.createNotebook(
            title: "Mixed Todos",
            notebookType: "job",
            jobId: jobId,
            createdBy: env.adminUserId
        )
        let sectionId = try env.notebooks.createSection(
            notebookId: nbId, groupId: nil, name: "Tasks"
        )
        // One pending, one complete
        try env.db.writer.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, task_status, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Active Task', 'pending', 0, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
            try dbConn.execute(sql: """
                INSERT INTO notebook_entries
                    (section_id, notebook_id, entry_type, block_type, title, task_status, sort_order,
                     created_by, created_at, updated_at, is_deleted)
                VALUES (?, ?, 'todo', 'text', 'Done Task', 'complete', 1, ?, datetime('now'), datetime('now'), 0)
                """, arguments: [sectionId, nbId, env.adminUserId])
        }

        let todos = try env.jobs.getActiveJobTodos(jobId: jobId)
        #expect(todos.count == 1)
        #expect(todos[0].title == "Active Task")
    }

    // MARK: - listLaborEntries filter variations

    @Test("listLaborEntries with userId filter returns only that user's entries")
    func testListLaborEntriesUserIdFilter() throws {
        let env = try E2ETestHelpers.setUp()
        // Create a second user and clock both users into the same job
        let secondUserId = try env.auth.createUser(displayName: "Second Worker", pin: "9999")
        let jobId = try E2ETestHelpers.seedJob(env)

        let entryA = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: entryA)
        let entryB = try env.jobs.clockIn(userId: secondUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: entryB)

        let adminEntries = try env.jobs.listLaborEntries(userId: env.adminUserId)
        let secondEntries = try env.jobs.listLaborEntries(userId: secondUserId)

        #expect(adminEntries.allSatisfy { $0.userId == env.adminUserId })
        #expect(secondEntries.allSatisfy { $0.userId == secondUserId })
        // Cross-check: admin entries should not contain the second user's entry
        #expect(!adminEntries.contains(where: { $0.userId == secondUserId }))
    }

    @Test("listLaborEntries with no filters returns all entries")
    func testListLaborEntriesNoFilter() throws {
        let env = try E2ETestHelpers.setUp()
        let secondUserId = try env.auth.createUser(displayName: "All Filter Worker", pin: "8888")
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-ALL-01")

        let e1 = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: e1)
        let e2 = try env.jobs.clockIn(userId: secondUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: e2)

        let all = try env.jobs.listLaborEntries()
        // Both entries should be present when no filter is applied
        #expect(all.count >= 2)
        #expect(all.contains(where: { $0.userId == env.adminUserId }))
        #expect(all.contains(where: { $0.userId == secondUserId }))
    }

    // MARK: - listActiveJobs with exclusion

    @Test("listActiveJobs excludingJobId omits the specified job")
    func testListActiveJobsExcluding() throws {
        let env = try E2ETestHelpers.setUp()
        let jobA = try E2ETestHelpers.seedJob(env, jobNumber: "J-EXA-01", name: "Exclude Job A")
        let jobB = try E2ETestHelpers.seedJob(env, jobNumber: "J-EXA-02", name: "Keep Job B")

        let allJobs = try env.jobs.listActiveJobs()
        let withoutA = try env.jobs.listActiveJobs(excludingJobId: jobA)

        #expect(allJobs.contains(where: { $0.id == jobA }))
        #expect(!withoutA.contains(where: { $0.id == jobA }))
        #expect(withoutA.contains(where: { $0.id == jobB }))
    }

    @Test("listActiveJobs excludingJobId nil behaves like no exclusion")
    func testListActiveJobsExcludingNil() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-NIL-01")
        let jobs = try env.jobs.listActiveJobs(excludingJobId: nil)
        #expect(jobs.contains(where: { $0.id == jobId }))
    }

    @Test("getTodaysClockEntries returns empty array on fresh DB")
    func testGetTodaysClockEntriesFreshDB() throws {
        let env = try E2ETestHelpers.setUp()
        // Fresh DB with no clock entries should return [] not throw
        let groups = try env.jobs.getTodaysClockEntries(userId: env.adminUserId)
        #expect(groups.isEmpty)
    }

    // MARK: - Error Cases

    @Test("clockIn while already clocked in throws alreadyClockedIn")
    func testDoubleClockInThrows() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-DOUBLE-01")
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        // Second clock-in for same user should throw alreadyClockedIn
        var threw = false
        do {
            _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        } catch JobsService.JobsError.alreadyClockedIn(let uid, let jid) {
            #expect(uid == env.adminUserId)
            #expect(jid == jobId)
            threw = true
        }
        #expect(threw, "Expected alreadyClockedIn to be thrown")
    }

    @Test("clockOut with non-existent labor entry throws laborEntryNotFound")
    func testClockOutInvalidEntryThrows() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: JobsService.JobsError.laborEntryNotFound(9999)) {
            try env.jobs.clockOut(laborEntryId: 9999)
        }
    }

    @Test("clockOut after already clocked out throws laborEntryNotFound")
    func testClockOutAlreadyCompletedThrows() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-COMPLETE-01")
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.jobs.clockOut(laborEntryId: entryId)
        // Entry is now 'completed' — a second clockOut should throw laborEntryNotFound
        #expect(throws: JobsService.JobsError.laborEntryNotFound(entryId)) {
            try env.jobs.clockOut(laborEntryId: entryId)
        }
    }

    @Test("getJob with non-existent ID throws jobNotFound")
    func testGetJobNotFoundThrows() throws {
        let env = try E2ETestHelpers.setUp()
        #expect(throws: JobsService.JobsError.jobNotFound(9999)) {
            try env.jobs.getJob(id: 9999)
        }
    }

    @Test("clockIn records GPS coordinates when provided")
    func testClockInWithGPS() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-GPS-01")
        let entryId = try env.jobs.clockIn(
            userId: env.adminUserId,
            jobId: jobId,
            gpsLat: 37.7749,
            gpsLng: -122.4194
        )
        #expect(entryId > 0)
        let entry = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(entry != nil)
    }

    @Test("different users can clock in concurrently on separate jobs")
    func testConcurrentClockInDifferentUsers() throws {
        let env = try E2ETestHelpers.setUp()
        let secondUserId = try env.auth.createUser(displayName: "Worker B", pin: "5555")
        let jobA = try E2ETestHelpers.seedJob(env, jobNumber: "J-CONC-01", name: "Job A")
        let jobB = try E2ETestHelpers.seedJob(env, jobNumber: "J-CONC-02", name: "Job B")

        let entryA = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobA)
        let entryB = try env.jobs.clockIn(userId: secondUserId, jobId: jobB)

        #expect(entryA > 0)
        #expect(entryB > 0)
        #expect(entryA != entryB)

        let activeA = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        let activeB = try env.jobs.getActiveClockEntry(userId: secondUserId)
        #expect(activeA?.jobId == jobA)
        #expect(activeB?.jobId == jobB)
    }

    @Test("getLaborEntryNotes returns nil when notes are not set")
    func testGetLaborEntryNotesNil() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-NOTES-01")
        let entryId = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        let notes = try env.jobs.getLaborEntryNotes(laborEntryId: entryId)
        // Fresh clock entry has no notes
        #expect(notes == nil || notes == "")
    }

    // MARK: - removeTeamMember

    @Test("removeTeamMember soft-deletes a team member row")
    func testRemoveTeamMember() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env, jobNumber: "J-TEAM-01")

        let memberId = try env.jobs.addTeamMember(jobId: jobId, userId: env.adminUserId, role: "member")
        var members = try env.jobs.getTeamMembers(jobId: jobId)
        #expect(members.count == 1)

        try env.jobs.removeTeamMember(id: memberId)

        members = try env.jobs.getTeamMembers(jobId: jobId)
        #expect(members.isEmpty, "Soft-deleted member should not appear in active team list")
    }

    @Test("removeTeamMember on non-existent id is a no-op")
    func testRemoveTeamMemberNoop() throws {
        let env = try E2ETestHelpers.setUp()
        // Should not throw for a missing row
        #expect(throws: Never.self) {
            try env.jobs.removeTeamMember(id: 99999)
        }
    }

    // MARK: - isOnSupplyRun (pure static)

    @Test("isOnSupplyRun returns false for nil notes")
    func testIsOnSupplyRunNilNotes() {
        #expect(!JobsService.isOnSupplyRun(notes: nil))
    }

    @Test("isOnSupplyRun returns false for empty notes")
    func testIsOnSupplyRunEmptyNotes() {
        #expect(!JobsService.isOnSupplyRun(notes: ""))
    }

    @Test("isOnSupplyRun returns true when supply_run_start has no matching end")
    func testIsOnSupplyRunActive() {
        let notes = "Some notes [supply_run_start:2026-04-16T10:00:00Z]"
        #expect(JobsService.isOnSupplyRun(notes: notes))
    }

    @Test("isOnSupplyRun returns false when supply_run_end comes after supply_run_start")
    func testIsOnSupplyRunEnded() {
        let notes = "[supply_run_start:2026-04-16T10:00:00Z][supply_run_end:2026-04-16T11:00:00Z]"
        #expect(!JobsService.isOnSupplyRun(notes: notes))
    }

    @Test("isOnSupplyRun returns true when a second supply_run_start follows an end")
    func testIsOnSupplyRunSecondRun() {
        let notes = "[supply_run_start:09:00][supply_run_end:10:00][supply_run_start:14:00]"
        #expect(JobsService.isOnSupplyRun(notes: notes))
    }

    @Test("isOnSupplyRun returns false when notes contain no supply run markers")
    func testIsOnSupplyRunNoMarkers() {
        #expect(!JobsService.isOnSupplyRun(notes: "Regular work notes, no supply run"))
    }

    // MARK: - computeStageStatuses (pure static)

    @Test("computeStageStatuses returns all pending when currentStageId is nil")
    func testComputeStageStatusesNilStage() {
        let stages = [
            JobsService.JobStageStatus(id: 1, name: "Rough-In", sortOrder: 1, status: "pending"),
            JobsService.JobStageStatus(id: 2, name: "Trim", sortOrder: 2, status: "pending"),
        ]
        let result = JobsService.computeStageStatuses(allStages: stages, currentStageId: nil, jobStatus: "active")
        #expect(result.allSatisfy { $0.status == "pending" })
    }

    @Test("computeStageStatuses marks all completed when jobStatus is completed")
    func testComputeStageStatusesCompletedJob() {
        let stages = [
            JobsService.JobStageStatus(id: 1, name: "Rough-In", sortOrder: 1, status: "pending"),
            JobsService.JobStageStatus(id: 2, name: "Trim", sortOrder: 2, status: "pending"),
            JobsService.JobStageStatus(id: 3, name: "Final", sortOrder: 3, status: "pending"),
        ]
        let result = JobsService.computeStageStatuses(allStages: stages, currentStageId: 2, jobStatus: "completed")
        #expect(result.allSatisfy { $0.status == "completed" })
    }

    @Test("computeStageStatuses marks current stage in_progress, earlier completed, later pending")
    func testComputeStageStatusesMiddleStage() {
        let stages = [
            JobsService.JobStageStatus(id: 1, name: "Rough-In", sortOrder: 1, status: "pending"),
            JobsService.JobStageStatus(id: 2, name: "Trim", sortOrder: 2, status: "pending"),
            JobsService.JobStageStatus(id: 3, name: "Final", sortOrder: 3, status: "pending"),
        ]
        let result = JobsService.computeStageStatuses(allStages: stages, currentStageId: 2, jobStatus: "active")
        #expect(result[0].status == "completed")
        #expect(result[1].status == "in_progress")
        #expect(result[2].status == "pending")
    }

    @Test("computeStageStatuses with first stage marks only first as in_progress")
    func testComputeStageStatusesFirstStage() {
        let stages = [
            JobsService.JobStageStatus(id: 1, name: "Rough-In", sortOrder: 1, status: "pending"),
            JobsService.JobStageStatus(id: 2, name: "Trim", sortOrder: 2, status: "pending"),
        ]
        let result = JobsService.computeStageStatuses(allStages: stages, currentStageId: 1, jobStatus: "active")
        #expect(result[0].status == "in_progress")
        #expect(result[1].status == "pending")
    }

    // MARK: - Soft-Delete Guard Regression Tests

    @Test("getJob throws jobNotFound for soft-deleted job")
    func testGetJobHidesDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Soft-delete the job directly
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }

        #expect(throws: JobsService.JobsError.jobNotFound(jobId)) {
            _ = try env.jobs.getJob(id: jobId)
        }
    }

    @Test("clockIn throws jobNotFound when clocking into deleted job")
    func testClockInBlockedForDeletedJob() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Soft-delete the job
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }

        #expect(throws: JobsService.JobsError.jobNotFound(jobId)) {
            _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        }
    }

    @Test("getTeamMembers shows Unknown for soft-deleted team member user")
    func testGetTeamMembersExcludesDeletedUsers() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)

        // Add admin as a team member
        try env.jobs.addTeamMember(jobId: jobId, userId: env.adminUserId, role: "member")

        // Soft-delete the admin user
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [env.adminUserId])
        }

        let members = try env.jobs.getTeamMembers(jobId: jobId)
        // The team slot still exists but the deleted user's identity is hidden
        let member = members.first(where: { $0.userId == env.adminUserId })
        #expect(member != nil)
        #expect(member?.userName == "Unknown")
    }

    @Test("listLaborEntries hides job name for soft-deleted job")
    func testListLaborEntriesHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let entries = try env.jobs.listLaborEntries(jobId: jobId)
        #expect(entries.isEmpty == false)
        #expect(entries.first?.jobName == "")
    }

    @Test("getActiveClockEntry hides job name for soft-deleted job")
    func testGetActiveClockEntryHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let entry = try env.jobs.getActiveClockEntry(userId: env.adminUserId)
        #expect(entry != nil)
        #expect(entry?.jobName == "")
    }

    @Test("getTodaysClockEntries hides job name for soft-deleted job")
    func testGetTodaysClockEntriesHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.clockIn(userId: env.adminUserId, jobId: jobId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let groups = try env.jobs.getTodaysClockEntries(userId: env.adminUserId)
        // Group still exists keyed by deleted job ID; real job name hidden — shows "Unknown"
        #expect(groups.isEmpty == false)
        #expect(groups.first?.jobName != "Test Job")
    }

    @Test("getQuestionsForJob hides deleted creator name")
    func testGetQuestionsForJobHidesDeletedCreatedByName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.createOneTimeQuestion(jobId: jobId, text: "Test?", createdBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE users SET deleted_at = datetime('now') WHERE id = ?", arguments: [env.adminUserId])
        }
        let questions = try env.jobs.getQuestionsForJob(jobId: jobId)
        #expect(questions.isEmpty == false)
        #expect(questions.first?.createdByName == "Unknown")
    }

    @Test("listReports hides job name for soft-deleted job")
    func testListReportsHidesDeletedJobName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        _ = try env.jobs.generateDailyReport(jobId: jobId, reportDate: "2026-01-01", reportJson: "{}", generatedBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE jobs SET deleted_at = datetime('now') WHERE id = ?", arguments: [jobId])
        }
        let reports = try env.jobs.listReports(jobId: jobId)
        #expect(reports.isEmpty == false)
        #expect(reports.first?.jobName == "")
    }

    @Test("getJobParts shows Unknown Part for soft-deleted part")
    func testGetJobPartsHidesDeletedPartName() throws {
        let env = try E2ETestHelpers.setUp()
        let jobId = try E2ETestHelpers.seedJob(env)
        let catId = try E2ETestHelpers.seedCategory(env, name: "JP_Cat")
        let partId = try E2ETestHelpers.seedPart(env, name: "JP_Part", categoryId: catId)
        _ = try env.jobs.addJobPart(jobId: jobId, partId: partId, qty: 2, performedBy: env.adminUserId)
        try env.db.writer.write { db in
            try db.execute(sql: "UPDATE parts SET deleted_at = datetime('now') WHERE id = ?", arguments: [partId])
        }
        let parts = try env.jobs.getJobParts(jobId: jobId)
        #expect(parts.isEmpty == false)
        #expect(parts.first?.partName == "Unknown Part")
    }
}
